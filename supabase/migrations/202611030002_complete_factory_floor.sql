-- Restores warehouse balances removed from the MVP; no historical balances
-- are inferred from production consumption. All new balances come from ledger entries.
begin;
create table if not exists pomgt.warehouses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  code varchar not null,
  name varchar not null,
  address text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouses_org_code_unique unique (organization_id, code)
);

create index if not exists warehouses_organization_idx on pomgt.warehouses (organization_id);

create table if not exists pomgt.inventory_stock (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  warehouse_id uuid not null references pomgt.warehouses(id) on delete cascade,
  product_id uuid not null references pomgt.products(id) on delete cascade,
  quantity_on_hand numeric not null default 0,
  uom_id uuid not null references pomgt.units_of_measure(id),
  updated_at timestamptz not null default now(),
  constraint inventory_stock_unique unique (warehouse_id, product_id)
);

create index if not exists inventory_stock_organization_idx on pomgt.inventory_stock (organization_id);
create index if not exists inventory_stock_product_idx on pomgt.inventory_stock (product_id);

create table if not exists pomgt.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  warehouse_id uuid not null references pomgt.warehouses(id),
  product_id uuid not null references pomgt.products(id),
  movement_type text not null
    check (movement_type in ('receipt', 'issue', 'adjustment_in', 'adjustment_out', 'transfer_in', 'transfer_out')),
  quantity numeric not null check (quantity > 0),
  uom_id uuid not null references pomgt.units_of_measure(id),
  unit_cost numeric not null default 0 check (unit_cost >= 0),
  reference_type text
    check (reference_type is null or reference_type in ('purchase_order', 'production_order', 'manual', 'transfer')),
  reference_id uuid,
  related_warehouse_id uuid references pomgt.warehouses(id),
  notes text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists inventory_movements_organization_idx on pomgt.inventory_movements (organization_id);
create index if not exists inventory_movements_warehouse_idx on pomgt.inventory_movements (warehouse_id);
create index if not exists inventory_movements_product_idx on pomgt.inventory_movements (product_id);
create index if not exists inventory_movements_reference_idx on pomgt.inventory_movements (reference_type, reference_id);


alter table pomgt.warehouses
  add column if not exists floor_pos_x double precision,
  add column if not exists floor_pos_y double precision;
alter table pomgt.inventory_movements
  add column if not exists request_id uuid,
  add column if not exists production_material_id uuid;
create unique index if not exists inventory_movements_request_idx
  on pomgt.inventory_movements(request_id) where request_id is not null;

create table if not exists pomgt.floor_zones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  kind text not null default 'production' check (kind in ('production','storage','quality','shipping')),
  x double precision not null default 24 check (x >= 0 and x < 'Infinity'::float8),
  y double precision not null default 24 check (y >= 0 and y < 'Infinity'::float8),
  width double precision not null default 700 check (width >= 240 and width <= 10000),
  height double precision not null default 450 check (height >= 200 and height <= 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists floor_zones_org_idx on pomgt.floor_zones(organization_id);

create or replace function pomgt.protect_floor_warehouse()
returns trigger language plpgsql set search_path = pomgt, public as $$
begin
  if tg_op = 'UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'No se puede cambiar la organización de un almacén';
  end if;
  if (new.floor_pos_x is not null and not (new.floor_pos_x >= 0 and new.floor_pos_x < 'Infinity'::float8))
    or (new.floor_pos_y is not null and not (new.floor_pos_y >= 0 and new.floor_pos_y < 'Infinity'::float8)) then
    raise exception 'La posición debe estar dentro del plano';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists warehouses_floor_guard on pomgt.warehouses;
create trigger warehouses_floor_guard before insert or update on pomgt.warehouses
  for each row execute function pomgt.protect_floor_warehouse();
drop function if exists pomgt.transfer_inventory(uuid,uuid,uuid,numeric,uuid,text);

-- The ledger is append-only to application users. Only the validated RPC can
-- change balances, atomically with optional production material issue/return.
drop trigger if exists inventory_movements_apply on pomgt.inventory_movements;
create or replace function pomgt.record_floor_inventory_movement(
  p_warehouse_id uuid, p_product_id uuid, p_movement_type text,
  p_quantity numeric, p_request_id uuid, p_notes text default null,
  p_material_id uuid default null
) returns uuid
language plpgsql security definer set search_path = pomgt, public
as $$
declare
  org uuid;
  unit_id uuid;
  delta numeric;
  movement_id uuid;
  prior pomgt.inventory_movements%rowtype;
  material_row pomgt.production_order_materials%rowtype;
  order_org uuid;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  select organization_id into org from pomgt.warehouses
    where id = p_warehouse_id and is_active;
  if org is null or not pomgt.is_member(org) then
    raise exception 'Almacén no disponible para esta organización';
  end if;
  select base_uom_id into unit_id from pomgt.products
    where id = p_product_id and organization_id = org;
  if unit_id is null then raise exception 'El producto requiere una unidad base válida'; end if;
  if p_request_id is null or p_quantity is null or p_quantity <= 0
    or p_quantity::text in ('NaN','Infinity','-Infinity') then
    raise exception 'La cantidad y el identificador del movimiento deben ser válidos';
  end if;
  if p_movement_type is null or p_movement_type not in
    ('receipt','issue','adjustment_in','adjustment_out') then
    raise exception 'Tipo de movimiento no válido';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 0));
  select * into prior from pomgt.inventory_movements where request_id = p_request_id;
  if found then
    if prior.organization_id <> org or prior.warehouse_id <> p_warehouse_id
      or prior.product_id <> p_product_id or prior.quantity <> p_quantity
      or prior.movement_type <> p_movement_type
      or prior.production_material_id is distinct from p_material_id then
      raise exception 'El identificador ya se utilizó para otro movimiento';
    end if;
    return prior.id;
  end if;
  if p_material_id is not null then
    select * into material_row from pomgt.production_order_materials
      where id = p_material_id for update;
    select organization_id into order_org from pomgt.production_orders
      where id = material_row.production_order_id;
    if order_org is distinct from org or material_row.material_product_id <> p_product_id
      or material_row.uom_id is distinct from unit_id then
      raise exception 'El material debe pertenecer a la organización, producto y unidad del almacén';
    end if;
    if p_movement_type not in ('issue','receipt') then
      raise exception 'Para una orden utilice surtido o devolución';
    end if;
    execute format('select pomgt.register_production_material_movement($1, %L, $2, null, $3, $4)',
      case when p_movement_type = 'issue' then 'issue' else 'return' end)
      using p_material_id, p_quantity, p_warehouse_id::text, p_notes;
  end if;
  delta := case when p_movement_type in ('receipt','adjustment_in') then p_quantity else -p_quantity end;
  insert into pomgt.inventory_stock(organization_id,warehouse_id,product_id,quantity_on_hand,uom_id)
    values(org,p_warehouse_id,p_product_id,0,unit_id)
    on conflict (warehouse_id,product_id) do nothing;
  update pomgt.inventory_stock
    set quantity_on_hand = quantity_on_hand + delta, updated_at = now()
    where warehouse_id = p_warehouse_id and product_id = p_product_id
      and organization_id = org and uom_id = unit_id
      and quantity_on_hand + delta >= 0;
  if not found then raise exception 'Existencias insuficientes o unidad incompatible'; end if;
  insert into pomgt.inventory_movements(organization_id,warehouse_id,product_id,
    movement_type,quantity,uom_id,reference_type,reference_id,notes,created_by,request_id,production_material_id)
    values(org,p_warehouse_id,p_product_id,p_movement_type,p_quantity,unit_id,
      case when p_material_id is null then 'manual' else 'production_order' end,
      material_row.production_order_id,p_notes,auth.uid(),p_request_id,p_material_id) returning id into movement_id;
  return movement_id;
end;
$$;
revoke all on function pomgt.record_floor_inventory_movement(uuid,uuid,text,numeric,uuid,text,uuid) from public;
grant execute on function pomgt.record_floor_inventory_movement(uuid,uuid,text,numeric,uuid,text,uuid) to authenticated;

alter table pomgt.floor_zones enable row level security;
alter table pomgt.warehouses enable row level security;
alter table pomgt.inventory_stock enable row level security;
alter table pomgt.inventory_movements enable row level security;
do $$
declare t text;
begin
  foreach t in array array['floor_zones','warehouses','inventory_stock','inventory_movements'] loop
    execute format('drop policy if exists tenant_member_all on pomgt.%I', t);
    execute format('create policy tenant_member_all on pomgt.%I for all to authenticated using (pomgt.is_member(organization_id)) with check (pomgt.is_member(organization_id))', t);
  end loop;
end;
$$;
revoke all on pomgt.inventory_stock,pomgt.inventory_movements from authenticated,anon;
grant select on pomgt.inventory_stock,pomgt.inventory_movements to authenticated;
grant select,insert,update,delete on pomgt.floor_zones,pomgt.warehouses to authenticated;
notify pgrst, 'reload schema';
commit;
