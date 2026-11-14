-- Inventario / Almacén module.
--
-- Adds real stock tracking ahead of BOM/production: warehouses, a
-- server-maintained stock balance per warehouse+product, and a kardex
-- (inventory_movements) that is the only way balances change. A trigger
-- keeps inventory_stock in sync and blocks any movement that would push a
-- balance negative, so "producción sin material" becomes a hard error
-- instead of a silent overdraw.
--
-- This module is intentionally standalone in this pass: production order
-- material consumption does not yet auto-post an `issue` movement. Wiring
-- that (and purchase receiving, added next) is the natural continuation.

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

drop trigger if exists warehouses_set_updated_at on pomgt.warehouses;
create trigger warehouses_set_updated_at
  before update on pomgt.warehouses
  for each row execute function pomgt.set_updated_at();

-- Keeps inventory_stock as a running balance derived from movements, and
-- refuses any movement that would take a balance below zero.
create or replace function pomgt.apply_inventory_movement()
returns trigger
language plpgsql
as $$
declare
  delta numeric;
  resulting numeric;
begin
  delta := case
    when new.movement_type in ('receipt', 'adjustment_in', 'transfer_in') then new.quantity
    when new.movement_type in ('issue', 'adjustment_out', 'transfer_out') then -new.quantity
    else 0
  end;

  insert into pomgt.inventory_stock (organization_id, warehouse_id, product_id, quantity_on_hand, uom_id)
  values (new.organization_id, new.warehouse_id, new.product_id, delta, new.uom_id)
  on conflict (warehouse_id, product_id)
  do update set
    quantity_on_hand = pomgt.inventory_stock.quantity_on_hand + excluded.quantity_on_hand,
    uom_id = excluded.uom_id,
    updated_at = now();

  select quantity_on_hand into resulting
  from pomgt.inventory_stock
  where warehouse_id = new.warehouse_id and product_id = new.product_id;

  if resulting < 0 then
    raise exception 'La existencia de este producto no puede quedar negativa en el almacén (resultaría en %).', resulting;
  end if;

  return new;
end;
$$;

drop trigger if exists inventory_movements_apply on pomgt.inventory_movements;
create trigger inventory_movements_apply
  after insert on pomgt.inventory_movements
  for each row execute function pomgt.apply_inventory_movement();

-- Moves stock between two warehouses atomically as a linked transfer_out /
-- transfer_in pair, so a partial failure never leaves stock "in transit"
-- nowhere.
create or replace function pomgt.transfer_inventory(
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_uom_id uuid,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  org uuid;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  if p_from_warehouse_id = p_to_warehouse_id then
    raise exception 'El almacén de origen y destino no pueden ser el mismo';
  end if;
  if p_quantity <= 0 then
    raise exception 'La cantidad a transferir debe ser mayor a cero';
  end if;

  select organization_id into org from pomgt.warehouses where id = p_from_warehouse_id;
  if org is null then
    raise exception 'Almacén de origen no encontrado';
  end if;
  if not pomgt.is_member(org) then
    raise exception 'No tiene acceso a esta organización';
  end if;
  if not exists (select 1 from pomgt.warehouses where id = p_to_warehouse_id and organization_id = org) then
    raise exception 'Almacén de destino no encontrado en la misma organización';
  end if;

  insert into pomgt.inventory_movements (
    organization_id, warehouse_id, product_id, movement_type, quantity, uom_id,
    reference_type, related_warehouse_id, notes, created_by
  ) values (
    org, p_from_warehouse_id, p_product_id, 'transfer_out', p_quantity, p_uom_id,
    'transfer', p_to_warehouse_id, p_notes, auth.uid()
  );

  insert into pomgt.inventory_movements (
    organization_id, warehouse_id, product_id, movement_type, quantity, uom_id,
    reference_type, related_warehouse_id, notes, created_by
  ) values (
    org, p_to_warehouse_id, p_product_id, 'transfer_in', p_quantity, p_uom_id,
    'transfer', p_from_warehouse_id, p_notes, auth.uid()
  );
end;
$$;

grant execute on function pomgt.transfer_inventory(uuid, uuid, uuid, numeric, uuid, text) to authenticated;

alter table pomgt.warehouses enable row level security;
drop policy if exists tenant_member_all on pomgt.warehouses;
create policy tenant_member_all
  on pomgt.warehouses
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.inventory_stock enable row level security;
drop policy if exists tenant_member_all on pomgt.inventory_stock;
create policy tenant_member_all
  on pomgt.inventory_stock
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.inventory_movements enable row level security;
drop policy if exists tenant_member_all on pomgt.inventory_movements;
create policy tenant_member_all
  on pomgt.inventory_movements
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update, delete on pomgt.warehouses to authenticated;
grant select, insert, update on pomgt.inventory_stock to authenticated;
grant select, insert on pomgt.inventory_movements to authenticated;

notify pgrst, 'reload schema';
