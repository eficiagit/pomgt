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
      and r.product_id = p_product_id
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
