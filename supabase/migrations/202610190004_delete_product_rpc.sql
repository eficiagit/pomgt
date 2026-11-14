-- Deleting a product (or a material — materials live in the same products
-- table) failed with a raw foreign-key error the moment it had a BOM, a
-- routing, or anything else attached, e.g. "violates foreign key constraint
-- boms_product_id_fkey". Mirrors the safety posture already used by
-- delete_customer: block when real traceability exists (production orders,
-- order lines, deliveries, claims, nonconformities, or being used as a
-- component in ANOTHER product's BOM/sub-assembly), otherwise cascade away
-- everything that only makes sense attached to this product's own record
-- (its BOM, its routings, its revisions, its document links, its
-- customer-specific catalog entries).
--
-- routing_operation_materials.material_product_id is a design-time
-- reference only (see migration 202610190003 — actual consumption is always
-- resolved from the product's own BOM), so a product referenced there from
-- someone else's routing step is detached (set to null) rather than
-- blocking the delete.
create or replace function pomgt.delete_product(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  product_row pomgt.products%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into product_row from pomgt.products where id = p_product_id;
  if not found then
    raise exception 'Producto no encontrado';
  end if;
  if not pomgt.is_member(product_row.organization_id) then
    raise exception 'No tiene acceso a la organización de este producto';
  end if;

  if exists (select 1 from pomgt.production_orders where product_id = p_product_id) then
    raise exception 'Este producto tiene órdenes de producción registradas y no puede eliminarse';
  end if;

  if exists (select 1 from pomgt.customer_order_lines where product_id = p_product_id) then
    raise exception 'Este producto tiene líneas de pedido registradas y no puede eliminarse';
  end if;

  if exists (select 1 from pomgt.delivery_lines where product_id = p_product_id) then
    raise exception 'Este producto tiene líneas de entrega registradas y no puede eliminarse';
  end if;

  if exists (select 1 from pomgt.customer_claims where product_id = p_product_id) then
    raise exception 'Este producto tiene reclamos de cliente registrados y no puede eliminarse';
  end if;

  if exists (select 1 from pomgt.nonconformities where product_id = p_product_id) then
    raise exception 'Este producto tiene no conformidades de calidad registradas y no puede eliminarse';
  end if;

  if exists (select 1 from pomgt.bom_items where component_product_id = p_product_id) then
    raise exception 'Este producto se usa como material o componente en la estructura de fabricación de otro producto y no puede eliminarse';
  end if;

  if exists (
    select 1
    from pomgt.bom_items bi
    where bi.child_bom_revision_id in (
      select br.id
      from pomgt.bom_revisions br
      join pomgt.boms b on b.id = br.bom_id
      where b.product_id = p_product_id
    )
  ) then
    raise exception 'La estructura de fabricación de este producto se usa como subensamble en otro producto y no puede eliminarse';
  end if;

  -- Design-time reference only: safe to detach rather than block.
  update pomgt.routing_operation_materials
     set material_product_id = null
   where material_product_id = p_product_id;

  delete from pomgt.document_links
   where product_id = p_product_id
      or customer_product_id in (select id from pomgt.customer_products where product_id = p_product_id)
      or product_revision_id in (select id from pomgt.product_revisions where product_id = p_product_id)
      or bom_revision_id in (
           select br.id from pomgt.bom_revisions br
           join pomgt.boms b on b.id = br.bom_id
           where b.product_id = p_product_id
         )
      or routing_revision_id in (
           select rr.id from pomgt.routing_revisions rr
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         )
      or routing_operation_id in (
           select ro.id
           from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.design_approvals
   where customer_product_id in (select id from pomgt.customer_products where product_id = p_product_id)
      or product_revision_id in (select id from pomgt.product_revisions where product_id = p_product_id);

  delete from pomgt.customer_requirements
   where customer_product_id in (select id from pomgt.customer_products where product_id = p_product_id);

  delete from pomgt.customer_products where product_id = p_product_id;

  delete from pomgt.routing_operation_dependencies
   where operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         )
      or predecessor_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operation_materials
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operation_labor_requirements
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operation_machine_parameters
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operation_checklists
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operation_quality_checks
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operation_cost_components
   where routing_operation_id in (
           select ro.id from pomgt.routing_operations ro
           join pomgt.routing_revisions rr on rr.id = ro.routing_revision_id
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_operations
   where routing_revision_id in (
           select rr.id from pomgt.routing_revisions rr
           join pomgt.routings r on r.id = rr.routing_id
           where r.product_id = p_product_id
         );

  delete from pomgt.routing_revisions
   where routing_id in (select id from pomgt.routings where product_id = p_product_id);

  delete from pomgt.routings where product_id = p_product_id;

  delete from pomgt.bom_items
   where bom_revision_id in (
           select br.id from pomgt.bom_revisions br
           join pomgt.boms b on b.id = br.bom_id
           where b.product_id = p_product_id
         );

  delete from pomgt.bom_revisions
   where bom_id in (select id from pomgt.boms where product_id = p_product_id);

  delete from pomgt.boms where product_id = p_product_id;

  delete from pomgt.material_revision_attribute_values
   where product_revision_id in (select id from pomgt.product_revisions where product_id = p_product_id);

  delete from pomgt.product_tolerances
   where product_revision_id in (select id from pomgt.product_revisions where product_id = p_product_id);

  delete from pomgt.product_revision_custom_values
   where product_revision_id in (select id from pomgt.product_revisions where product_id = p_product_id);

  delete from pomgt.product_revisions where product_id = p_product_id;

  delete from pomgt.products where id = p_product_id;
end;
$$;

grant execute on function pomgt.delete_product(uuid) to authenticated;

notify pgrst, 'reload schema';
