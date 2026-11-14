-- The Kanban board drags cards freely between any two columns (forward or
-- backward), but pomgt.transition_production_order enforced a state machine
-- that blocked most backward moves (e.g. in_progress -> ready), which is the
-- "No se puede cambiar la OP de ... a ..." error the board was showing.
-- This drops that restriction: any status can move to any other status.
-- The side effects (timestamps, activity log) are unchanged.
create or replace function pomgt.transition_production_order(
  p_order_id uuid,
  p_new_status text,
  p_note text default null,
  p_completed_quantity numeric default null
)
returns pomgt.production_orders
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  order_row pomgt.production_orders%rowtype;
  previous text;
  result pomgt.production_orders%rowtype;
  status_label text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into order_row from pomgt.production_orders where id = p_order_id;
  if not found then
    raise exception 'Orden de producción no encontrada';
  end if;

  if not pomgt.is_member(order_row.organization_id) then
    raise exception 'No tiene acceso a la organización de la OP';
  end if;

  previous := order_row.status::text;
  if previous = p_new_status then
    return order_row;
  end if;

  update pomgt.production_orders
     set status = p_new_status::pomgt.production_order_status,
         actual_start_at = case
           when p_new_status = 'in_progress' and actual_start_at is null
             then now()
           else actual_start_at
         end,
         actual_end_at = case
           when p_new_status = 'completed' then now()
           when p_new_status not in ('completed', 'cancelled') then null
           else actual_end_at
         end,
         completed_quantity = case
           when p_new_status = 'completed' and p_completed_quantity is not null
             then p_completed_quantity
           else completed_quantity
         end,
         closed_at = case
           when p_new_status in ('completed', 'cancelled') then now()
           when p_new_status not in ('completed', 'cancelled') then null
           else closed_at
         end,
         updated_by = auth.uid(),
         updated_at = now()
   where id = p_order_id
  returning * into result;

  status_label := case p_new_status
    when 'draft' then 'Borrador'
    when 'planned' then 'Planificada'
    when 'ready' then 'Lista'
    when 'in_progress' then 'En producción'
    when 'on_hold' then 'En pausa'
    when 'completed' then 'Completada'
    when 'cancelled' then 'Cancelada'
    else p_new_status
  end;

  insert into pomgt.production_order_events (
    organization_id,
    production_order_id,
    event_type,
    title,
    description,
    previous_status,
    new_status,
    payload,
    occurred_at,
    created_by
  )
  values (
    order_row.organization_id,
    p_order_id,
    'status_change',
    'Cambio de estado a ' || status_label,
    p_note,
    previous,
    p_new_status,
    '{}'::jsonb,
    now(),
    auth.uid()
  );

  return result;
end;
$$;

grant execute on function pomgt.transition_production_order(uuid, text, text, numeric)
  to authenticated;

notify pgrst, 'reload schema';
