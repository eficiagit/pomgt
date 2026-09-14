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