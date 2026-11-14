-- Compras + Proveedores module.
--
-- Suppliers and purchase orders (OC), closing the MRP loop that Cotizaciones
-- opened on the sales side: what to buy, from whom, and receiving it posts
-- straight into Inventario as a `receipt` movement (see
-- pomgt.receive_purchase_order_line). Receiving also refreshes the
-- product's standard_cost with a simple "last cost" method — not a moving
-- average — which is the same simplification already used by the quote
-- costing rollup.

create table if not exists pomgt.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  supplier_code varchar not null,
  legal_name varchar not null,
  trade_name varchar,
  tax_id varchar,
  email varchar,
  phone varchar,
  default_currency_code varchar not null references pomgt.currencies(code),
  payment_term_id uuid references pomgt.payment_terms(id),
  notes text,
  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suppliers_org_code_unique unique (organization_id, supplier_code)
);

create index if not exists suppliers_organization_idx on pomgt.suppliers (organization_id);

create table if not exists pomgt.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  po_number varchar not null,
  supplier_id uuid not null references pomgt.suppliers(id),
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'confirmed', 'partially_received', 'received', 'cancelled')),
  order_date date not null default current_date,
  expected_date date,
  warehouse_id uuid references pomgt.warehouses(id),
  currency_code varchar not null references pomgt.currencies(code),
  notes text,
  subtotal numeric not null default 0,
  tax_total numeric not null default 0,
  total_amount numeric not null default 0,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint purchase_orders_org_number_unique unique (organization_id, po_number)
);

create index if not exists purchase_orders_organization_idx on pomgt.purchase_orders (organization_id);
create index if not exists purchase_orders_supplier_idx on pomgt.purchase_orders (supplier_id);
create index if not exists purchase_orders_status_idx on pomgt.purchase_orders (status);

create table if not exists pomgt.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  purchase_order_id uuid not null references pomgt.purchase_orders(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  product_id uuid not null references pomgt.products(id),
  description text,
  uom_id uuid not null references pomgt.units_of_measure(id),
  quantity numeric not null check (quantity > 0),
  received_quantity numeric not null default 0 check (received_quantity >= 0),
  unit_cost numeric not null default 0 check (unit_cost >= 0),
  tax_pct numeric not null default 0 check (tax_pct >= 0 and tax_pct <= 100),
  line_subtotal numeric not null default 0,
  line_tax numeric not null default 0,
  line_total numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint purchase_order_lines_unique_line unique (purchase_order_id, line_no)
);

create index if not exists purchase_order_lines_po_idx on pomgt.purchase_order_lines (purchase_order_id);
create index if not exists purchase_order_lines_product_idx on pomgt.purchase_order_lines (product_id);

drop trigger if exists suppliers_set_updated_at on pomgt.suppliers;
create trigger suppliers_set_updated_at
  before update on pomgt.suppliers
  for each row execute function pomgt.set_updated_at();

create or replace function pomgt.purchase_order_line_before_write()
returns trigger
language plpgsql
as $$
begin
  new.line_subtotal := round(coalesce(new.quantity, 0) * coalesce(new.unit_cost, 0), 4);
  new.line_tax := round(new.line_subtotal * coalesce(new.tax_pct, 0) / 100.0, 4);
  new.line_total := new.line_subtotal + new.line_tax;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists purchase_order_lines_before_write on pomgt.purchase_order_lines;
create trigger purchase_order_lines_before_write
  before insert or update on pomgt.purchase_order_lines
  for each row execute function pomgt.purchase_order_line_before_write();

create or replace function pomgt.recompute_purchase_order_totals(p_po_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  v_subtotal numeric := 0;
  v_tax numeric := 0;
begin
  select coalesce(sum(line_subtotal), 0), coalesce(sum(line_tax), 0)
    into v_subtotal, v_tax
  from pomgt.purchase_order_lines
  where purchase_order_id = p_po_id;

  update pomgt.purchase_orders
  set subtotal = v_subtotal, tax_total = v_tax, total_amount = v_subtotal + v_tax
  where id = p_po_id;
end;
$$;

grant execute on function pomgt.recompute_purchase_order_totals(uuid) to authenticated, service_role;

create or replace function pomgt.purchase_order_line_after_write()
returns trigger
language plpgsql
as $$
begin
  perform pomgt.recompute_purchase_order_totals(coalesce(new.purchase_order_id, old.purchase_order_id));
  return null;
end;
$$;

drop trigger if exists purchase_order_lines_after_write on pomgt.purchase_order_lines;
create trigger purchase_order_lines_after_write
  after insert or update or delete on pomgt.purchase_order_lines
  for each row execute function pomgt.purchase_order_line_after_write();

-- Extend the folio generator with the OC prefix.
create or replace function pomgt.next_sequence_value(p_org uuid, p_key text)
returns text
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  sequence_row pomgt.number_sequences%rowtype;
  normalized_key text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  if not pomgt.is_member(p_org) then
    raise exception 'No tiene acceso a esta organización';
  end if;

  normalized_key := upper(trim(coalesce(p_key, '')));
  if normalized_key = '' then
    raise exception 'La clave de secuencia es requerida';
  end if;

  insert into pomgt.number_sequences (
    organization_id, sequence_key, prefix, next_value, padding, separator
  )
  values (
    p_org,
    normalized_key,
    case normalized_key
      when 'CUSTOMER' then 'CLI'
      when 'ORDER' then 'PED'
      when 'DELIVERY' then 'ENT'
      when 'CLAIM' then 'REC'
      when 'QUOTE' then 'COT'
      when 'PURCHASE' then 'OC'
      when 'SUPPLIER' then 'PROV'
      else normalized_key
    end,
    1, 5, '-'
  )
  on conflict (organization_id, sequence_key)
  where sequence_key is not null
  do nothing;

  update pomgt.number_sequences
  set next_value = next_value + 1, updated_at = now()
  where organization_id = p_org and sequence_key = normalized_key
  returning * into sequence_row;

  if sequence_row.id is null then
    raise exception 'No fue posible obtener el siguiente folio';
  end if;

  return concat(
    sequence_row.prefix,
    case when sequence_row.prefix = '' then '' else sequence_row.separator end,
    lpad((sequence_row.next_value - 1)::text, sequence_row.padding, '0')
  );
end;
$$;

grant execute on function pomgt.next_sequence_value(uuid, text) to authenticated, service_role;

-- Receiving posts an inventory receipt and keeps the PO/line status honest.
-- Also refreshes the product's standard_cost with the received unit cost
-- (last-cost method) so future quote/BOM cost rollups reflect reality.
create or replace function pomgt.receive_purchase_order_line(
  p_line_id uuid,
  p_quantity numeric,
  p_warehouse_id uuid,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  line_row pomgt.purchase_order_lines%rowtype;
  po_row pomgt.purchase_orders%rowtype;
  pending numeric;
  all_received boolean;
  any_received boolean;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  if p_quantity <= 0 then
    raise exception 'La cantidad recibida debe ser mayor a cero';
  end if;

  select * into line_row from pomgt.purchase_order_lines where id = p_line_id;
  if not found then
    raise exception 'Línea de orden de compra no encontrada';
  end if;
  if not pomgt.is_member(line_row.organization_id) then
    raise exception 'No tiene acceso a la organización de esta orden de compra';
  end if;
  if not exists (select 1 from pomgt.warehouses where id = p_warehouse_id and organization_id = line_row.organization_id) then
    raise exception 'Almacén no encontrado en esta organización';
  end if;

  pending := line_row.quantity - line_row.received_quantity;
  if p_quantity > pending + 0.000001 then
    raise exception 'La cantidad recibida supera lo pendiente de la línea (%).', pending;
  end if;

  insert into pomgt.inventory_movements (
    organization_id, warehouse_id, product_id, movement_type, quantity, uom_id,
    unit_cost, reference_type, reference_id, notes, created_by
  ) values (
    line_row.organization_id, p_warehouse_id, line_row.product_id, 'receipt', p_quantity, line_row.uom_id,
    line_row.unit_cost, 'purchase_order', line_row.purchase_order_id, p_notes, auth.uid()
  );

  update pomgt.purchase_order_lines
  set received_quantity = received_quantity + p_quantity
  where id = p_line_id;

  update pomgt.products
  set standard_cost = line_row.unit_cost, standard_cost_currency_code = coalesce(standard_cost_currency_code, (
    select currency_code from pomgt.purchase_orders where id = line_row.purchase_order_id
  ))
  where id = line_row.product_id;

  select * into po_row from pomgt.purchase_orders where id = line_row.purchase_order_id;

  select
    bool_and(received_quantity >= quantity),
    bool_or(received_quantity > 0)
    into all_received, any_received
  from pomgt.purchase_order_lines
  where purchase_order_id = line_row.purchase_order_id;

  update pomgt.purchase_orders
  set status = case
      when all_received then 'received'
      when any_received then 'partially_received'
      else po_row.status
    end,
    updated_by = auth.uid()
  where id = line_row.purchase_order_id;
end;
$$;

grant execute on function pomgt.receive_purchase_order_line(uuid, numeric, uuid, text) to authenticated;

create or replace function pomgt.delete_purchase_order(p_po_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  po_row pomgt.purchase_orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  select * into po_row from pomgt.purchase_orders where id = p_po_id;
  if not found then
    raise exception 'Orden de compra no encontrada';
  end if;
  if not pomgt.is_member(po_row.organization_id) then
    raise exception 'No tiene acceso a la organización de esta orden de compra';
  end if;
  if exists (select 1 from pomgt.purchase_order_lines where purchase_order_id = p_po_id and received_quantity > 0) then
    raise exception 'Esta orden de compra ya tiene recepciones registradas y no puede eliminarse';
  end if;

  delete from pomgt.purchase_order_lines where purchase_order_id = p_po_id;
  delete from pomgt.purchase_orders where id = p_po_id;
end;
$$;

grant execute on function pomgt.delete_purchase_order(uuid) to authenticated;

alter table pomgt.suppliers enable row level security;
drop policy if exists tenant_member_all on pomgt.suppliers;
create policy tenant_member_all
  on pomgt.suppliers
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.purchase_orders enable row level security;
drop policy if exists tenant_member_all on pomgt.purchase_orders;
create policy tenant_member_all
  on pomgt.purchase_orders
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.purchase_order_lines enable row level security;
drop policy if exists tenant_member_all on pomgt.purchase_order_lines;
create policy tenant_member_all
  on pomgt.purchase_order_lines
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update, delete on pomgt.suppliers to authenticated;
grant select, insert, update, delete on pomgt.purchase_orders to authenticated;
grant select, insert, update, delete on pomgt.purchase_order_lines to authenticated;

notify pgrst, 'reload schema';
