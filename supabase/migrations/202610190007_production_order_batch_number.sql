-- Lets several production orders created together (releasing 2+ pedido
-- lines in one bulk action, or splitting one line into several OPs) share a
-- readable "lote" folio, so they can be found/treated as one job without
-- merging them into a single row — each OP still needs its own product,
-- BOM, routing and execution tracking (see the plan this session: a true
-- multi-product OP would mean rewriting the whole execution model).
--
-- v_production_order_workspace selects po.* from production_orders, so this
-- column flows through to the app automatically — no view change needed.
alter table pomgt.production_orders
  add column if not exists batch_number text;

create index if not exists idx_production_orders_batch_number
  on pomgt.production_orders (organization_id, batch_number)
  where batch_number is not null;

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
