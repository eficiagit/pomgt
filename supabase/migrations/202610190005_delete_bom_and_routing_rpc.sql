-- Deleting a BOM or a routing header hit the exact same raw foreign-key
-- error as product/customer delete used to (e.g. "violates foreign key
-- constraint bom_revisions_bom_id_fkey" / "routing_revisions_routing_id_
-- fkey"), because both went straight through a plain DELETE with no
-- cascade and no error translation. Same safety posture as delete_product /
-- delete_customer: block when a production order already used this BOM or
-- routing (real traceability), or when this BOM is used as a sub-assembly
-- inside another product's BOM; otherwise cascade away everything that only
-- makes sense attached to the BOM/routing being deleted.
create or replace function pomgt.delete_bom(p_bom_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  bom_row pomgt.boms%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into bom_row from pomgt.boms where id = p_bom_id;
  if not found then
    raise exception 'Estructura de fabricación no encontrada';
  end if;
  if not pomgt.is_member(bom_row.organization_id) then
    raise exception 'No tiene acceso a la organización de esta estructura de fabricación';
  end if;

  if exists (
    select 1 from pomgt.production_orders
    where bom_revision_id in (select id from pomgt.bom_revisions where bom_id = p_bom_id)
  ) then
    raise exception 'Esta estructura de fabricación ya se usó para preparar una orden de producción y no puede eliminarse';
  end if;

  if exists (
    select 1 from pomgt.bom_items
    where child_bom_revision_id in (select id from pomgt.bom_revisions where bom_id = p_bom_id)
  ) then
    raise exception 'Esta estructura de fabricación se usa como subensamble en otro producto y no puede eliminarse';
  end if;

  -- Design-time reference only (see migration 202610190003): safe to remove
  -- rather than block, the bom_item it pointed to no longer exists.
  delete from pomgt.routing_operation_materials
   where bom_item_id in (
           select bi.id from pomgt.bom_items bi
           join pomgt.bom_revisions br on br.id = bi.bom_revision_id
           where br.bom_id = p_bom_id
         );

  delete from pomgt.document_links
   where bom_revision_id in (select id from pomgt.bom_revisions where bom_id = p_bom_id);

  delete from pomgt.bom_items
   where bom_revision_id in (select id from pomgt.bom_revisions where bom_id = p_bom_id);

  delete from pomgt.bom_revisions where bom_id = p_bom_id;

  delete from pomgt.boms where id = p_bom_id;
end;
$$;

grant execute on function pomgt.delete_bom(uuid) to authenticated;

create or replace function pomgt.delete_routing(p_routing_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  routing_row pomgt.routings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into routing_row from pomgt.routings where id = p_routing_id;
  if not found then
    raise exception 'Ruta de fabricación no encontrada';
  end if;
  if not pomgt.is_member(routing_row.organization_id) then
    raise exception 'No tiene acceso a la organización de esta ruta de fabricación';
  end if;

  if exists (
    select 1 from pomgt.production_orders
    where routing_revision_id in (select id from pomgt.routing_revisions where routing_id = p_routing_id)
  ) then
    raise exception 'Esta ruta de fabricación ya se usó para preparar una orden de producción y no puede eliminarse';
  end if;

  delete from pomgt.document_links
   where routing_revision_id in (select id from pomgt.routing_revisions where routing_id = p_routing_id)
      or routing_operation_id in (
           select ro.id
           from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_dependencies
   where operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         )
      or predecessor_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_materials
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_labor_requirements
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_machine_parameters
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_checklists
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_quality_checks
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operation_cost_components
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           where rr.routing_id = p_routing_id
         );

  delete from pomgt.routing_operations
   where routing_revision_id in (select id from pomgt.routing_revisions where routing_id = p_routing_id);

  delete from pomgt.routing_revisions where routing_id = p_routing_id;

  delete from pomgt.routings where id = p_routing_id;
end;
$$;

grant execute on function pomgt.delete_routing(uuid) to authenticated;

notify pgrst, 'reload schema';
