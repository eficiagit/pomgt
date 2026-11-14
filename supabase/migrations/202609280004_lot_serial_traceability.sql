-- Trazabilidad por lote / serie.
--
-- products.track_lots / track_serials already existed but nothing recorded
-- an actual lot or serial. This adds the ledger tables and ties them to
-- both ends of the chain: a lot can come FROM a production order (finished
-- goods genealogy) and inventory_movements can reference a lot, so a kardex
-- entry says not just "how much" but "which lot".
--
-- Scope note: creating a lot is a manual action from the Lotes screen in
-- this pass (pick the production order, confirm quantity/dates) rather than
-- an automatic button wired into the production detail screen — that
-- screen is already one of the largest in the app and a deeper integration
-- is better done as its own follow-up change.

create table if not exists pomgt.product_lots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  product_id uuid not null references pomgt.products(id) on delete cascade,
  lot_code varchar not null,
  production_order_id uuid references pomgt.production_orders(id) on delete set null,
  manufactured_at date,
  expires_at date,
  quantity_produced numeric not null default 0 check (quantity_produced >= 0),
  quality_status text not null default 'pending'
    check (quality_status in ('pending', 'approved', 'rejected', 'quarantine')),
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_lots_org_code_unique unique (organization_id, product_id, lot_code)
);

create index if not exists product_lots_organization_idx on pomgt.product_lots (organization_id);
create index if not exists product_lots_product_idx on pomgt.product_lots (product_id);
create index if not exists product_lots_production_order_idx on pomgt.product_lots (production_order_id);

create table if not exists pomgt.product_serials (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  product_id uuid not null references pomgt.products(id) on delete cascade,
  serial_code varchar not null,
  lot_id uuid references pomgt.product_lots(id) on delete set null,
  production_order_id uuid references pomgt.production_orders(id) on delete set null,
  status text not null default 'in_stock'
    check (status in ('in_stock', 'shipped', 'installed', 'returned', 'scrapped')),
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_serials_org_code_unique unique (organization_id, product_id, serial_code)
);

create index if not exists product_serials_organization_idx on pomgt.product_serials (organization_id);
create index if not exists product_serials_product_idx on pomgt.product_serials (product_id);
create index if not exists product_serials_lot_idx on pomgt.product_serials (lot_id);

alter table pomgt.inventory_movements
  add column if not exists lot_id uuid references pomgt.product_lots(id) on delete set null;
alter table pomgt.inventory_movements
  add column if not exists serial_id uuid references pomgt.product_serials(id) on delete set null;

create index if not exists inventory_movements_lot_idx on pomgt.inventory_movements (lot_id);

drop trigger if exists product_lots_set_updated_at on pomgt.product_lots;
create trigger product_lots_set_updated_at
  before update on pomgt.product_lots
  for each row execute function pomgt.set_updated_at();

drop trigger if exists product_serials_set_updated_at on pomgt.product_serials;
create trigger product_serials_set_updated_at
  before update on pomgt.product_serials
  for each row execute function pomgt.set_updated_at();

-- Registers a finished-goods lot for a completed production order and
-- credits it straight into inventory as a traceable `receipt`.
create or replace function pomgt.create_lot_from_production_order(
  p_order_id uuid,
  p_lot_code text,
  p_quantity numeric,
  p_warehouse_id uuid,
  p_manufactured_at date default current_date,
  p_expires_at date default null
)
returns uuid
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  order_row pomgt.production_orders%rowtype;
  new_lot_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  if p_quantity <= 0 then
    raise exception 'La cantidad del lote debe ser mayor a cero';
  end if;

  select * into order_row from pomgt.production_orders where id = p_order_id;
  if not found then
    raise exception 'Orden de producción no encontrada';
  end if;
  if not pomgt.is_member(order_row.organization_id) then
    raise exception 'No tiene acceso a la organización de esta orden';
  end if;
  if not exists (select 1 from pomgt.warehouses where id = p_warehouse_id and organization_id = order_row.organization_id) then
    raise exception 'Almacén no encontrado en esta organización';
  end if;

  insert into pomgt.product_lots (
    organization_id, product_id, lot_code, production_order_id,
    manufactured_at, expires_at, quantity_produced, created_by
  ) values (
    order_row.organization_id, order_row.product_id, p_lot_code, p_order_id,
    p_manufactured_at, p_expires_at, p_quantity, auth.uid()
  ) returning id into new_lot_id;

  insert into pomgt.inventory_movements (
    organization_id, warehouse_id, product_id, movement_type, quantity, uom_id,
    reference_type, reference_id, lot_id, notes, created_by
  ) values (
    order_row.organization_id, p_warehouse_id, order_row.product_id, 'receipt', p_quantity, order_row.uom_id,
    'production_order', p_order_id, new_lot_id, concat('Lote generado desde OP ', order_row.op_number), auth.uid()
  );

  return new_lot_id;
end;
$$;

grant execute on function pomgt.create_lot_from_production_order(uuid, text, numeric, uuid, date, date) to authenticated;

alter table pomgt.product_lots enable row level security;
drop policy if exists tenant_member_all on pomgt.product_lots;
create policy tenant_member_all
  on pomgt.product_lots
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.product_serials enable row level security;
drop policy if exists tenant_member_all on pomgt.product_serials;
create policy tenant_member_all
  on pomgt.product_serials
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update, delete on pomgt.product_lots to authenticated;
grant select, insert, update, delete on pomgt.product_serials to authenticated;

notify pgrst, 'reload schema';
