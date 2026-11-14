-- Releasing a pedido line into production effectively prepares it, so it
-- needs the same hard requirement BOM already has: an active routing
-- (the product's own, or its category's default) must resolve, or the OP
-- would have nothing to execute against. Mirrors the category-scoped
-- fallback pomgt.prepare_production_order already uses, but strictly
-- requires an `active`-status revision (not merely the newest one),
-- matching the BOM check's own strictness just above it.
create or replace function pomgt.release_order_line_to_production(
  p_order_line_id uuid,
  p_split_quantities numeric[],
  p_required_at timestamptz default null,
  p_priority text default 'normal',
  p_batch_number text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  line_row pomgt.customer_order_lines%rowtype;
  allocated numeric := 0;
  release_total numeric := 0;
  qty numeric;
  op_id uuid;
  op_number text;
  created_rows jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select *
    into line_row
  from pomgt.customer_order_lines
  where id = p_order_line_id;

  if not found then
    raise exception 'Línea de pedido no encontrada';
  end if;

  if not pomgt.is_member(line_row.organization_id) then
    raise exception 'No tiene acceso a la organización de la línea';
  end if;

  if not exists (
    select 1
    from pomgt.bom_revisions br
    join pomgt.boms b on b.id = br.bom_id
    where b.organization_id = line_row.organization_id
      and b.product_id = line_row.product_id
      and b.is_active = true
      and br.status::text = 'active'
  ) then
    raise exception 'Este producto no tiene una estructura de fabricación activa; vincula materiales antes de liberarlo a producción';
  end if;

  if not exists (
    select 1
    from pomgt.routing_revisions rr
    join pomgt.routings r on r.id = rr.routing_id
    where r.organization_id = line_row.organization_id
      and r.is_active = true
      and rr.status::text = 'active'
      and (
        r.product_id = line_row.product_id
        or (
          r.category_id is not null
          and r.category_id = (
            select p.category_id from pomgt.products p where p.id = line_row.product_id
          )
        )
      )
  ) then
    raise exception 'Este producto no tiene una ruta de fabricación activa; vincula una ruta antes de liberarlo a producción';
  end if;

  if p_split_quantities is null or array_length(p_split_quantities, 1) is null then
    raise exception 'Captura al menos una cantidad a liberar';
  end if;

  select coalesce(sum(allocated_quantity), 0)
    into allocated
  from pomgt.production_order_allocations
  where customer_order_line_id = p_order_line_id;

  foreach qty in array p_split_quantities loop
    if coalesce(qty, 0) <= 0 then
      raise exception 'Todas las cantidades deben ser mayores a cero';
    end if;
    release_total := release_total + qty;
  end loop;

  if release_total > line_row.requested_quantity - allocated + 0.000001 then
    raise exception 'La cantidad liberada supera el pendiente de la línea';
  end if;

  foreach qty in array p_split_quantities loop
    op_number := pomgt.next_sequence_value(line_row.organization_id, 'OP');

    insert into pomgt.production_orders (
      organization_id,
      op_number,
      product_id,
      planned_quantity,
      completed_quantity,
      uom_id,
      status,
      priority,
      required_at,
      notes,
      batch_number,
      created_by,
      updated_by
    )
    values (
      line_row.organization_id,
      op_number,
      line_row.product_id,
      qty,
      0,
      line_row.uom_id,
      'draft',
      coalesce(nullif(trim(p_priority), ''), 'normal')::pomgt.priority_level,
      coalesce(p_required_at, line_row.requested_delivery_date::timestamptz),
      'Creada desde línea de pedido',
      nullif(trim(coalesce(p_batch_number, '')), ''),
      auth.uid(),
      auth.uid()
    )
    returning id into op_id;

    insert into pomgt.production_order_allocations (
      organization_id,
      production_order_id,
      customer_order_line_id,
      allocated_quantity,
      uom_id
    )
    values (
      line_row.organization_id,
      op_id,
      p_order_line_id,
      qty,
      line_row.uom_id
    );

    created_rows := created_rows || jsonb_build_array(
      (
        select to_jsonb(po)
        from pomgt.production_orders po
        where po.id = op_id
      )
    );
  end loop;

  return created_rows;
end;
$$;

grant execute on function pomgt.release_order_line_to_production(
  uuid,
  numeric[],
  timestamptz,
  text,
  text
) to authenticated;

notify pgrst, 'reload schema';
