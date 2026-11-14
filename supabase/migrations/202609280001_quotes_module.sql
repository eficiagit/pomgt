-- Cotizaciones (Quotes) module.
--
-- Adds a commercial quoting layer ahead of pedidos: a quote can list any
-- product (manufacturable, raw material, or a free-text concept with no
-- product_id), carries its own discount/IVA handling, and tracks utility
-- (profit) automatically from each line's cost snapshot. A quote can later
-- be converted 1:1 into a customer_order (pedido), which already has its
-- own release-to-production flow (release_order_line_to_production).
--
-- Cost snapshot: for a manufacturable product with an active default BOM,
-- the unit cost is rolled up from pomgt.products.standard_cost of each BOM
-- component (quantity * (1 + scrap%) / output_quantity). Formula-based BOM
-- items (quantity_formula instead of a fixed quantity) are not evaluated
-- here and contribute 0 to the rollup — a known simplification. Any other
-- product, or one without an active BOM, falls back to its own
-- standard_cost directly.

create table if not exists pomgt.quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  quote_number varchar not null,
  customer_id uuid references pomgt.customers(id) on delete set null,
  customer_contact_id uuid references pomgt.customer_contacts(id) on delete set null,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'accepted', 'rejected', 'expired', 'converted')),
  quote_date date not null default current_date,
  valid_until date,
  deposit_amount numeric not null default 0 check (deposit_amount >= 0),
  external_order_reference varchar,
  discount_type text not null default 'amount'
    check (discount_type in ('amount', 'percentage')),
  discount_value numeric not null default 0 check (discount_value >= 0),
  currency_code varchar not null references pomgt.currencies(code),
  notes text,
  subtotal numeric not null default 0,
  discount_amount numeric not null default 0,
  tax_total numeric not null default 0,
  total_amount numeric not null default 0,
  cost_total numeric not null default 0,
  profit_amount numeric not null default 0,
  profit_pct numeric,
  converted_order_id uuid references pomgt.customer_orders(id) on delete set null,
  converted_at timestamptz,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotes_org_number_unique unique (organization_id, quote_number)
);

create index if not exists quotes_organization_idx on pomgt.quotes (organization_id);
create index if not exists quotes_customer_idx on pomgt.quotes (customer_id);
create index if not exists quotes_status_idx on pomgt.quotes (status);

create table if not exists pomgt.quote_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  quote_id uuid not null references pomgt.quotes(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  product_id uuid references pomgt.products(id) on delete set null,
  concept varchar not null,
  description text,
  uom_id uuid references pomgt.units_of_measure(id) on delete set null,
  quantity numeric not null default 1 check (quantity > 0),
  unit_price numeric not null default 0 check (unit_price >= 0),
  unit_cost numeric not null default 0 check (unit_cost >= 0),
  tax_pct numeric not null default 0 check (tax_pct >= 0 and tax_pct <= 100),
  line_subtotal numeric not null default 0,
  line_tax numeric not null default 0,
  line_total numeric not null default 0,
  line_cost numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_lines_unique_line unique (quote_id, line_no)
);

create index if not exists quote_lines_quote_idx on pomgt.quote_lines (quote_id);
create index if not exists quote_lines_product_idx on pomgt.quote_lines (product_id);

alter table pomgt.document_links
  add column if not exists quote_id uuid references pomgt.quotes(id) on delete set null;

-- updated_at bookkeeping -----------------------------------------------

drop trigger if exists quotes_set_updated_at on pomgt.quotes;
create trigger quotes_set_updated_at
  before update on pomgt.quotes
  for each row execute function pomgt.set_updated_at();

-- Line totals are derived server-side so the client can never desync them
-- from the header aggregates (utilidad, impuestos, etc).
create or replace function pomgt.quote_line_before_write()
returns trigger
language plpgsql
as $$
begin
  new.line_subtotal := round(coalesce(new.quantity, 0) * coalesce(new.unit_price, 0), 4);
  new.line_tax := round(new.line_subtotal * coalesce(new.tax_pct, 0) / 100.0, 4);
  new.line_total := new.line_subtotal + new.line_tax;
  new.line_cost := round(coalesce(new.quantity, 0) * coalesce(new.unit_cost, 0), 4);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists quote_lines_before_write on pomgt.quote_lines;
create trigger quote_lines_before_write
  before insert or update on pomgt.quote_lines
  for each row execute function pomgt.quote_line_before_write();

-- Recomputes a quote's header totals (subtotal, discount, IVA, total, costo
-- and utilidad) from its current lines. Discount is applied proportionally
-- per line before tax so the "Impuestos por producto" total in the summary
-- always matches what each line would owe net of its share of the discount.
create or replace function pomgt.recompute_quote_totals(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  q pomgt.quotes%rowtype;
  v_subtotal numeric := 0;
  v_cost numeric := 0;
  v_discount numeric := 0;
  v_tax numeric := 0;
  v_net numeric := 0;
begin
  select * into q from pomgt.quotes where id = p_quote_id;
  if not found then
    return;
  end if;

  select coalesce(sum(line_subtotal), 0), coalesce(sum(line_cost), 0)
    into v_subtotal, v_cost
  from pomgt.quote_lines
  where quote_id = p_quote_id;

  v_discount := case
    when q.discount_type = 'percentage' then round(v_subtotal * coalesce(q.discount_value, 0) / 100.0, 4)
    else coalesce(q.discount_value, 0)
  end;
  if v_discount > v_subtotal then
    v_discount := v_subtotal;
  end if;
  v_net := v_subtotal - v_discount;

  if v_subtotal > 0 then
    select coalesce(sum(
      (line_subtotal - (line_subtotal / v_subtotal) * v_discount) * coalesce(tax_pct, 0) / 100.0
    ), 0)
    into v_tax
    from pomgt.quote_lines
    where quote_id = p_quote_id;
  else
    v_tax := 0;
  end if;

  update pomgt.quotes
  set
    subtotal = v_subtotal,
    discount_amount = v_discount,
    tax_total = v_tax,
    total_amount = v_net + v_tax,
    cost_total = v_cost,
    profit_amount = v_net - v_cost,
    profit_pct = case when v_net > 0 then round((v_net - v_cost) / v_net * 100, 2) else null end
  where id = p_quote_id;
end;
$$;

grant execute on function pomgt.recompute_quote_totals(uuid) to authenticated, service_role;

create or replace function pomgt.quote_line_after_write()
returns trigger
language plpgsql
as $$
begin
  perform pomgt.recompute_quote_totals(coalesce(new.quote_id, old.quote_id));
  return null;
end;
$$;

drop trigger if exists quote_lines_after_write on pomgt.quote_lines;
create trigger quote_lines_after_write
  after insert or update or delete on pomgt.quote_lines
  for each row execute function pomgt.quote_line_after_write();

create or replace function pomgt.quote_header_discount_changed()
returns trigger
language plpgsql
as $$
begin
  perform pomgt.recompute_quote_totals(new.id);
  return null;
end;
$$;

drop trigger if exists quotes_after_discount_update on pomgt.quotes;
create trigger quotes_after_discount_update
  after update of discount_type, discount_value on pomgt.quotes
  for each row
  when (
    old.discount_type is distinct from new.discount_type
    or old.discount_value is distinct from new.discount_value
  )
  execute function pomgt.quote_header_discount_changed();

-- Cost rollup used to prefill a quote line's unit_cost when a product is
-- picked (see QuoteRepository.productUnitCost in the Flutter app).
create or replace function pomgt.compute_product_unit_cost(p_product_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = pomgt, public
as $$
declare
  bom_rev_id uuid;
  bom_rev_output numeric;
  computed numeric := 0;
  base_cost numeric;
begin
  -- Plain scalars, not a `record`: a bare record target left unassigned by
  -- a zero-row SELECT INTO raises "record is not assigned yet" the moment
  -- its fields are read, which is exactly the common case of a product with
  -- no BOM yet.
  select br.id, br.output_quantity
    into bom_rev_id, bom_rev_output
  from pomgt.bom_revisions br
  join pomgt.boms b on b.id = br.bom_id
  where b.product_id = p_product_id
    and b.is_active
    and br.status = 'active'
  order by b.is_default desc, br.created_at desc
  limit 1;

  if bom_rev_id is not null then
    select coalesce(sum(
      bi.quantity * (1 + coalesce(bi.scrap_pct, 0) / 100.0) * coalesce(p.standard_cost, 0)
    ), 0)
    into computed
    from pomgt.bom_items bi
    join pomgt.products p on p.id = bi.component_product_id
    where bi.bom_revision_id = bom_rev_id
      and bi.quantity is not null;

    if bom_rev_output > 0 then
      computed := computed / bom_rev_output;
    end if;
    return round(computed, 4);
  end if;

  select standard_cost into base_cost from pomgt.products where id = p_product_id;
  return coalesce(base_cost, 0);
end;
$$;

grant execute on function pomgt.compute_product_unit_cost(uuid) to authenticated;

-- Extend the shared folio generator so key 'QUOTE' yields COT-00001 instead
-- of QUOTE-00001, matching the other business prefixes.
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
    organization_id,
    sequence_key,
    prefix,
    next_value,
    padding,
    separator
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
      else normalized_key
    end,
    1,
    5,
    '-'
  )
  on conflict (organization_id, sequence_key)
  where sequence_key is not null
  do nothing;

  update pomgt.number_sequences
  set
    next_value = next_value + 1,
    updated_at = now()
  where organization_id = p_org
    and sequence_key = normalized_key
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

-- Convert a quote into a pedido (customer_order + lines). Free-concept
-- lines (no product_id) stay quote-only since a pedido line always needs a
-- catalog product. The resulting pedido keeps using the existing
-- release_order_line_to_production flow to reach a production order (PO).
create or replace function pomgt.convert_quote_to_order(p_quote_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  quote_row pomgt.quotes%rowtype;
  new_order_id uuid;
  order_number text;
  line_row pomgt.quote_lines%rowtype;
  line_no integer := 1;
  resolved_uom uuid;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into quote_row from pomgt.quotes where id = p_quote_id;
  if not found then
    raise exception 'Cotización no encontrada';
  end if;
  if not pomgt.is_member(quote_row.organization_id) then
    raise exception 'No tiene acceso a la organización de la cotización';
  end if;
  if quote_row.customer_id is null then
    raise exception 'La cotización necesita un cliente antes de convertirse en pedido';
  end if;
  if quote_row.converted_order_id is not null then
    raise exception 'Esta cotización ya fue convertida a pedido';
  end if;
  if not exists (
    select 1 from pomgt.quote_lines where quote_id = p_quote_id and product_id is not null
  ) then
    raise exception 'La cotización no tiene productos del catálogo para generar un pedido';
  end if;

  order_number := pomgt.next_sequence_value(quote_row.organization_id, 'ORDER');

  insert into pomgt.customer_orders (
    organization_id, order_number, source_type, customer_id, customer_contact_id,
    external_reference, customer_po_number, order_date, status, priority,
    currency_code, notes, created_by, updated_by
  ) values (
    quote_row.organization_id, order_number, 'customer_order', quote_row.customer_id,
    quote_row.customer_contact_id, quote_row.quote_number, quote_row.external_order_reference,
    current_date, 'draft', 'normal', quote_row.currency_code,
    concat(
      'Generado desde cotización ', quote_row.quote_number,
      case when coalesce(quote_row.notes, '') <> '' then concat(chr(10), quote_row.notes) else '' end
    ),
    auth.uid(), auth.uid()
  ) returning id into new_order_id;

  for line_row in
    select * from pomgt.quote_lines where quote_id = p_quote_id order by line_no
  loop
    if line_row.product_id is null then
      continue;
    end if;

    resolved_uom := line_row.uom_id;
    if resolved_uom is null then
      select base_uom_id into resolved_uom from pomgt.products where id = line_row.product_id;
    end if;

    insert into pomgt.customer_order_lines (
      organization_id, customer_order_id, line_no, product_id, product_description_snapshot,
      requested_quantity, uom_id, unit_price, discount_pct, tax_pct, line_status
    ) values (
      quote_row.organization_id, new_order_id, line_no, line_row.product_id, line_row.concept,
      line_row.quantity, resolved_uom, line_row.unit_price, 0, line_row.tax_pct, 'open'
    );
    line_no := line_no + 1;
  end loop;

  update pomgt.quotes
  set status = 'converted', converted_order_id = new_order_id, converted_at = now(), updated_by = auth.uid()
  where id = p_quote_id;

  return new_order_id;
end;
$$;

grant execute on function pomgt.convert_quote_to_order(uuid) to authenticated;

-- Deleting a quote is blocked once it already produced a pedido, mirroring
-- delete_customer_order's traceability guard.
create or replace function pomgt.delete_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  quote_row pomgt.quotes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into quote_row from pomgt.quotes where id = p_quote_id;
  if not found then
    raise exception 'Cotización no encontrada';
  end if;
  if not pomgt.is_member(quote_row.organization_id) then
    raise exception 'No tiene acceso a la organización de la cotización';
  end if;
  if quote_row.converted_order_id is not null then
    raise exception 'Esta cotización ya generó un pedido y no puede eliminarse';
  end if;

  delete from pomgt.document_links where quote_id = p_quote_id;
  delete from pomgt.quote_lines where quote_id = p_quote_id;
  delete from pomgt.quotes where id = p_quote_id;
end;
$$;

grant execute on function pomgt.delete_quote(uuid) to authenticated;

-- RLS --------------------------------------------------------------------

alter table pomgt.quotes enable row level security;
drop policy if exists tenant_member_all on pomgt.quotes;
create policy tenant_member_all
  on pomgt.quotes
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.quote_lines enable row level security;
drop policy if exists tenant_member_all on pomgt.quote_lines;
create policy tenant_member_all
  on pomgt.quote_lines
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update, delete on pomgt.quotes to authenticated;
grant select, insert, update, delete on pomgt.quote_lines to authenticated;

notify pgrst, 'reload schema';
