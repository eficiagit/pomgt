create or replace function pomgt.delete_production_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  order_row pomgt.production_orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into order_row from pomgt.production_orders where id = p_order_id;
  if not found then
    raise exception 'Orden de producción no encontrada';
  end if;

  if not pomgt.is_member(order_row.organization_id) then
    raise exception 'No tiene acceso a la organización de la orden';
  end if;

  -- Trazabilidad externa: si ya hay entregas, reclamos o no conformidades, no se borra.
  if exists (select 1 from pomgt.delivery_lines where production_order_id = p_order_id) then
    raise exception 'La orden tiene entregas registradas y no puede eliminarse';
  end if;
  if exists (select 1 from pomgt.customer_claims where production_order_id = p_order_id) then
    raise exception 'La orden tiene reclamos de cliente y no puede eliminarse';
  end if;
  if exists (select 1 from pomgt.nonconformities where production_order_id = p_order_id) then
    raise exception 'La orden tiene no conformidades y no puede eliminarse';
  end if;
  if exists (select 1 from pomgt.production_orders where parent_production_order_id = p_order_id) then
    raise exception 'La orden es padre de otras órdenes y no puede eliminarse';
  end if;

  delete from pomgt.production_order_material_movements where production_order_id = p_order_id;
  delete from pomgt.production_order_events where production_order_id = p_order_id;
  delete from pomgt.production_order_machine_parameters where production_order_id = p_order_id;
  delete from pomgt.production_order_quality_checks where production_order_id = p_order_id;
  delete from pomgt.production_order_checklist_items where production_order_id = p_order_id;
  delete from pomgt.production_order_materials where production_order_id = p_order_id;
  delete from pomgt.production_order_operation_dependencies where production_order_id = p_order_id;
  delete from pomgt.production_order_operations where production_order_id = p_order_id;
  delete from pomgt.production_order_allocations where production_order_id = p_order_id;
  delete from pomgt.production_order_costs where production_order_id = p_order_id;
  delete from pomgt.document_links where production_order_id = p_order_id;
  delete from pomgt.production_orders where id = p_order_id;
end;
$$;

grant execute on function pomgt.delete_production_order(uuid) to authenticated;
notify pgrst, 'reload schema';
