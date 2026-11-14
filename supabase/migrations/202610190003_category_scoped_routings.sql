-- Category-scoped routings: a routing can now belong to a product category
-- instead of a single product. A category routing becomes the default
-- manufacturing sequence for any product of that category that has no
-- routing of its own; an explicit product-level routing always wins over
-- the category default. Mirrors the already-established "a product's BOM
-- supersedes a category default" absence in this app — there was no such
-- concept before, so this introduces it from scratch for routings only.
--
-- Routing operation materials can now also be assigned by material TYPE
-- instead of a specific material product, so the same category routing
-- works across products that consume different concrete materials of the
-- same type. This is a design-time/reference field only: actual material
-- consumption for a production order is still materialized from the
-- product's own BOM (see ensureOperationalSnapshot in production_repository
-- .dart), never from routing_operation_materials — so this column carries
-- no risk to existing production flows.

alter table pomgt.routings
  alter column product_id drop not null;

alter table pomgt.routings
  add column if not exists category_id uuid references pomgt.product_categories(id);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'routings_product_or_category_check'
  ) then
    alter table pomgt.routings
      add constraint routings_product_or_category_check
      check ((product_id is not null) <> (category_id is not null));
  end if;
end $$;

-- At most one default, active routing per product and per category.
create unique index if not exists routings_one_default_per_product
  on pomgt.routings (organization_id, product_id)
  where is_default and is_active and product_id is not null;

create unique index if not exists routings_one_default_per_category
  on pomgt.routings (organization_id, category_id)
  where is_default and is_active and category_id is not null;

alter table pomgt.routing_operation_materials
  add column if not exists material_type_id uuid references pomgt.material_types(id);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'routing_operation_materials_product_or_type_check'
  ) then
    alter table pomgt.routing_operation_materials
      add constraint routing_operation_materials_product_or_type_check
      check (not (material_product_id is not null and material_type_id is not null));
  end if;
end $$;

-- prepare_production_order: add a category-default fallback when the order's
-- product has no routing of its own.
create or replace function pomgt.prepare_production_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  order_row pomgt.production_orders%rowtype;
  target_bom_revision_id uuid;
  target_routing_revision_id uuid;
  set_clauses text[] := array[
    'status = ''ready''',
    'updated_at = now()',
    'updated_by = auth.uid()'
  ];
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select *
    into order_row
  from pomgt.production_orders
  where id = p_order_id;

  if not found then
    raise exception 'Orden de producción no encontrada';
  end if;

  if not pomgt.is_member(order_row.organization_id) then
    raise exception 'No tiene acceso a la organización de la OP';
  end if;

  if order_row.status::text not in ('draft', 'planned', 'ready') then
    raise exception 'La OP no se puede preparar desde su estado actual';
  end if;

  target_bom_revision_id := order_row.bom_revision_id;
  if target_bom_revision_id is null then
    select br.id
      into target_bom_revision_id
    from pomgt.bom_revisions br
    join pomgt.boms b on b.id = br.bom_id
    where b.organization_id = order_row.organization_id
      and b.product_id = order_row.product_id
      and b.is_active = true
    order by
      case when br.status::text = 'active' then 0 else 1 end,
      b.is_default desc,
      br.effective_from desc nulls last,
      br.created_at desc
    limit 1;
  end if;

  target_routing_revision_id := order_row.routing_revision_id;
  if target_routing_revision_id is null then
    select rr.id
      into target_routing_revision_id
    from pomgt.routing_revisions rr
    join pomgt.routings r on r.id = rr.routing_id
    where r.organization_id = order_row.organization_id
      and r.product_id = order_row.product_id
      and r.is_active = true
    order by
      case when rr.status::text = 'active' then 0 else 1 end,
      r.is_default desc,
      rr.effective_from desc nulls last,
      rr.created_at desc
    limit 1;
  end if;

  -- No routing of its own: fall back to the default routing of the
  -- product's category, if one exists.
  if target_routing_revision_id is null then
    select rr.id
      into target_routing_revision_id
    from pomgt.routing_revisions rr
    join pomgt.routings r on r.id = rr.routing_id
    join pomgt.products p on p.id = order_row.product_id
    where r.organization_id = order_row.organization_id
      and p.category_id is not null
      and r.category_id = p.category_id
      and r.is_active = true
    order by
      case when rr.status::text = 'active' then 0 else 1 end,
      r.is_default desc,
      rr.effective_from desc nulls last,
      rr.created_at desc
    limit 1;
  end if;

  if target_bom_revision_id is null then
    raise exception 'No hay una BOM activa para preparar la OP';
  end if;

  if target_routing_revision_id is null then
    raise exception 'No hay una ruta activa para preparar la OP';
  end if;

  set_clauses := set_clauses || array[
    format('bom_revision_id = %L::uuid', target_bom_revision_id),
    format('routing_revision_id = %L::uuid', target_routing_revision_id)
  ];

 if exists (
  select 1
  from information_schema.columns
  where table_schema = 'pomgt'
    and table_name = 'production_orders'
    and column_name = 'prepared_at'
) then
  set_clauses := array_append(
    set_clauses,
    'prepared_at = now()'
  );
end if;

if exists (
  select 1
  from information_schema.columns
  where table_schema = 'pomgt'
    and table_name = 'production_orders'
    and column_name = 'snapshot_version'
) then
  set_clauses := array_append(
    set_clauses,
    'snapshot_version = coalesce(snapshot_version, 0) + 1'
  );
end if;

execute format(
  'with updated as (
     update pomgt.production_orders
     set %s
     where id = $1
     returning *
   )
   select to_jsonb(updated) from updated',
  array_to_string(set_clauses, ', ')
)
into result
using p_order_id;

  return result;
end;
$$;

grant execute on function pomgt.prepare_production_order(uuid) to authenticated;

-- create_production_order: the routing-ownership check only accepted a
-- routing tied directly to the product. A category-resolved routing has
-- product_id null, so this always rejected it — fixed to also accept a
-- routing whose category matches the product's category.
create or replace function pomgt.create_production_order(
  p_product_id uuid,
  p_quantity numeric,
  p_uom_id uuid default null,
  p_required_at timestamptz default null,
  p_priority text default 'normal',
  p_planned_start_at timestamptz default null,
  p_planned_end_at timestamptz default null,
  p_notes text default null,
  p_source_type text default 'internal',
  p_bom_revision_id uuid default null,
  p_routing_revision_id uuid default null
)
returns pomgt.production_orders
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  product_row pomgt.products%rowtype;
  op_id uuid;
  op_number text;
  result pomgt.production_orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  if coalesce(p_quantity, 0) <= 0 then
    raise exception 'La cantidad planificada debe ser mayor a cero';
  end if;

  select * into product_row from pomgt.products where id = p_product_id;
  if not found then
    raise exception 'Producto no encontrado';
  end if;

  if not pomgt.is_member(product_row.organization_id) then
    raise exception 'No tiene acceso a la organización del producto';
  end if;

  if p_bom_revision_id is not null and not exists (
    select 1
    from pomgt.bom_revisions br
    join pomgt.boms b on b.id = br.bom_id
    where br.id = p_bom_revision_id
      and b.organization_id = product_row.organization_id
      and b.product_id = p_product_id
  ) then
    raise exception 'La estructura de fabricación no corresponde a este producto';
  end if;

  if p_routing_revision_id is not null and not exists (
    select 1
    from pomgt.routing_revisions rr
    join pomgt.routings r on r.id = rr.routing_id
    where rr.id = p_routing_revision_id
      and r.organization_id = product_row.organization_id
      and (
        r.product_id = p_product_id
        or (r.category_id is not null and r.category_id = product_row.category_id)
      )
  ) then
    raise exception 'La ruta de fabricación no corresponde a este producto';
  end if;

  op_number := pomgt.next_sequence_value(product_row.organization_id, 'OP');

  insert into pomgt.production_orders (
    organization_id,
    op_number,
    product_id,
    bom_revision_id,
    routing_revision_id,
    planned_quantity,
    completed_quantity,
    uom_id,
    status,
    priority,
    source_type,
    planned_start_at,
    planned_end_at,
    required_at,
    notes,
    created_by,
    updated_by
  )
  values (
    product_row.organization_id,
    op_number,
    p_product_id,
    p_bom_revision_id,
    p_routing_revision_id,
    p_quantity,
    0,
    coalesce(p_uom_id, product_row.base_uom_id),
    'draft',
    coalesce(nullif(trim(p_priority), ''), 'normal')::pomgt.priority_level,
    coalesce(nullif(trim(p_source_type), ''), 'internal'),
    p_planned_start_at,
    p_planned_end_at,
    p_required_at,
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid(),
    auth.uid()
  )
  returning id into op_id;

  select * into result from pomgt.production_orders where id = op_id;
  return result;
end;
$$;

grant execute on function pomgt.create_production_order(
  uuid, numeric, uuid, timestamptz, text, timestamptz, timestamptz, text, text, uuid, uuid
) to authenticated;

notify pgrst, 'reload schema';
