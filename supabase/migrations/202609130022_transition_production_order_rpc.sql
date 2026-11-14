-- The app has called pomgt.transition_production_order for every OP status
-- change (Iniciar producción, Pausar, Reanudar, Completar, Cancelar, and now
-- the Kanban board's drag-and-drop). No migration in this repo ever created
-- it, yet a version of it already exists live with a different return type
-- (create or replace can't change that), so drop it first.
drop function if exists pomgt.transition_production_order(uuid, text, text, numeric);

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
  allowed text[];
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

  allowed := case previous
    when 'draft' then array['planned', 'ready', 'cancelled']
    when 'planned' then array['draft', 'ready', 'cancelled']
    when 'ready' then array['draft', 'planned', 'in_progress', 'cancelled']
    when 'in_progress' then array['on_hold', 'completed', 'cancelled']
    when 'on_hold' then array['in_progress', 'cancelled']
    else array[]::text[]
  end;

  if not (p_new_status = any(allowed)) then
    raise exception 'No se puede cambiar la OP de "%" a "%"', previous, p_new_status;
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
           else actual_end_at
         end,
         completed_quantity = case
           when p_new_status = 'completed' and p_completed_quantity is not null
             then p_completed_quantity
           else completed_quantity
         end,
         closed_at = case
           when p_new_status in ('completed', 'cancelled') then now()
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
