-- Deleting a customer failed with a raw foreign-key error the moment it had
-- ANY related record (a product it owns, an address, a pedido...). This
-- mirrors the safety posture already used by delete_customer_order and
-- delete_production_order: block the delete when real traceability exists
-- (production released, a delivery, a customer claim), otherwise cascade
-- away everything that belongs only to the customer record itself.
--
-- Products the customer owns are detached (owner_customer_id set to null),
-- never deleted — they may carry their own BOM/routing/production history
-- unrelated to "cleaning up this customer".
create or replace function pomgt.delete_customer(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  customer_row pomgt.customers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into customer_row from pomgt.customers where id = p_customer_id;
  if not found then
    raise exception 'Cliente no encontrado';
  end if;
  if not pomgt.is_member(customer_row.organization_id) then
    raise exception 'No tiene acceso a la organización de este cliente';
  end if;

  if exists (
    select 1 from pomgt.deliveries
    where customer_id = p_customer_id
       or customer_order_id in (select id from pomgt.customer_orders where customer_id = p_customer_id)
  ) then
    raise exception 'Este cliente tiene entregas registradas y no puede eliminarse';
  end if;

  if exists (
    select 1 from pomgt.customer_claims
    where customer_id = p_customer_id
       or customer_order_id in (select id from pomgt.customer_orders where customer_id = p_customer_id)
  ) then
    raise exception 'Este cliente tiene reclamos registrados y no puede eliminarse';
  end if;

  if exists (select 1 from pomgt.nonconformities where customer_id = p_customer_id) then
    raise exception 'Este cliente tiene no conformidades de calidad registradas y no puede eliminarse';
  end if;

  if exists (
    select 1
    from pomgt.production_order_allocations poa
    join pomgt.customer_order_lines col on col.id = poa.customer_order_line_id
    join pomgt.customer_orders co on co.id = col.customer_order_id
    where co.customer_id = p_customer_id
  ) then
    raise exception 'Este cliente ya tiene producción liberada y no puede eliminarse';
  end if;

  if exists (
    select 1
    from pomgt.delivery_lines dl
    join pomgt.customer_order_lines col on col.id = dl.customer_order_line_id
    join pomgt.customer_orders co on co.id = col.customer_order_id
    where co.customer_id = p_customer_id
  ) then
    raise exception 'Este cliente tiene líneas ya entregadas y no puede eliminarse';
  end if;

  delete from pomgt.document_links
   where customer_id = p_customer_id
      or customer_order_id in (select id from pomgt.customer_orders where customer_id = p_customer_id)
      or customer_order_line_id in (
           select col.id
           from pomgt.customer_order_lines col
           join pomgt.customer_orders co on co.id = col.customer_order_id
           where co.customer_id = p_customer_id
         )
      or customer_product_id in (select id from pomgt.customer_products where customer_id = p_customer_id);

  delete from pomgt.customer_order_lines
   where customer_order_id in (select id from pomgt.customer_orders where customer_id = p_customer_id);
  delete from pomgt.customer_orders where customer_id = p_customer_id;

  delete from pomgt.customer_requirements where customer_id = p_customer_id;
  delete from pomgt.design_approvals where customer_id = p_customer_id;
  delete from pomgt.customer_products where customer_id = p_customer_id;

  delete from pomgt.customer_contact_emails
   where contact_id in (select id from pomgt.customer_contacts where customer_id = p_customer_id);
  delete from pomgt.customer_contact_phones
   where contact_id in (select id from pomgt.customer_contacts where customer_id = p_customer_id);
  delete from pomgt.customer_contacts where customer_id = p_customer_id;

  delete from pomgt.customer_addresses where customer_id = p_customer_id;

  update pomgt.products set owner_customer_id = null where owner_customer_id = p_customer_id;

  delete from pomgt.customers where id = p_customer_id;
end;
$$;

grant execute on function pomgt.delete_customer(uuid) to authenticated;

notify pgrst, 'reload schema';
