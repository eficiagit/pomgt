-- Deleting a pedido failed with a foreign-key error ("Este registro está
-- relacionado con otra información...") because customer_order_lines has no
-- ON DELETE CASCADE from customer_orders. This mirrors the approach already
-- used for production orders: block the delete when real trazability exists
-- (a delivery, a claim, or production already released against a line),
-- otherwise remove the order's own dependents first.
create or replace function pomgt.delete_customer_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  order_row pomgt.customer_orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into order_row from pomgt.customer_orders where id = p_order_id;
  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if not pomgt.is_member(order_row.organization_id) then
    raise exception 'No tiene acceso a la organización del pedido';
  end if;

  if exists (select 1 from pomgt.deliveries where customer_order_id = p_order_id) then
    raise exception 'El pedido tiene entregas registradas y no puede eliminarse';
  end if;
  if exists (select 1 from pomgt.customer_claims where customer_order_id = p_order_id) then
    raise exception 'El pedido tiene reclamos de cliente y no puede eliminarse';
  end if;
  if exists (
    select 1
    from pomgt.production_order_allocations poa
    join pomgt.customer_order_lines col on col.id = poa.customer_order_line_id
    where col.customer_order_id = p_order_id
  ) then
    raise exception 'El pedido ya tiene producción liberada y no puede eliminarse';
  end if;
  if exists (
    select 1
    from pomgt.delivery_lines dl
    join pomgt.customer_order_lines col on col.id = dl.customer_order_line_id
    where col.customer_order_id = p_order_id
  ) then
    raise exception 'El pedido tiene líneas ya entregadas y no puede eliminarse';
  end if;

  delete from pomgt.document_links
   where customer_order_id = p_order_id
      or customer_order_line_id in (
           select id from pomgt.customer_order_lines where customer_order_id = p_order_id
         );
  delete from pomgt.customer_order_lines where customer_order_id = p_order_id;
  delete from pomgt.customer_orders where id = p_order_id;
end;
$$;

grant execute on function pomgt.delete_customer_order(uuid) to authenticated;

notify pgrst, 'reload schema';
