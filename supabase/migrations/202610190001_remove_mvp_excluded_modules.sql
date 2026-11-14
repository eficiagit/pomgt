-- Removes Cotizaciones, Inventario, Compras, Trazabilidad and Reportes from
-- the MVP scope. Dropped in dependency order: Trazabilidad depends on
-- Inventario (warehouse_id, lot_id/serial_id on inventory_movements) and on
-- Producción (production_order_id — production_orders itself is kept);
-- Compras depends on Inventario (warehouse_id) and on its own Proveedores;
-- Inventario is dropped last of the three since both others reference it;
-- Reportes and Cotizaciones are independent of the others.
--
-- Kept as-is: Clientes, Pedidos, Productos, Materiales, Estructuras de
-- fabricación, Rutas  de fabricación, Producción, Documentos, Datos
-- maestros, Roles y auditoría (including the operator-as-member + invite
-- flow from 202609290001, which Producción's operator assignment depends
-- on) and Cobertura.

-- Trazabilidad --------------------------------------------------------
drop function if exists pomgt.create_lot_from_production_order(uuid, text, numeric, uuid, date, date);
drop table if exists pomgt.product_serials cascade;
drop table if exists pomgt.product_lots cascade;
alter table if exists pomgt.inventory_movements
  drop column if exists lot_id,
  drop column if exists serial_id;

-- Compras + Proveedores -------------------------------------------------
drop function if exists pomgt.delete_purchase_order(uuid);
drop function if exists pomgt.receive_purchase_order_line(uuid, numeric, uuid, text);
drop function if exists pomgt.purchase_order_line_after_write() cascade;
drop function if exists pomgt.recompute_purchase_order_totals(uuid);
drop function if exists pomgt.purchase_order_line_before_write() cascade;
drop table if exists pomgt.purchase_order_lines cascade;
drop table if exists pomgt.purchase_orders cascade;
drop table if exists pomgt.suppliers cascade;

-- Inventario / Almacén ---------------------------------------------------
drop function if exists pomgt.transfer_inventory(uuid, uuid, uuid, numeric, uuid, text);
drop function if exists pomgt.apply_inventory_movement() cascade;
drop table if exists pomgt.inventory_movements cascade;
drop table if exists pomgt.inventory_stock cascade;
drop table if exists pomgt.warehouses cascade;

-- Reportes / BI -----------------------------------------------------------
drop view if exists pomgt.v_report_production_performance;

-- Cotizaciones ------------------------------------------------------------
drop function if exists pomgt.delete_quote(uuid);
drop function if exists pomgt.convert_quote_to_order(uuid);
drop function if exists pomgt.compute_product_unit_cost(uuid);
drop function if exists pomgt.quote_header_discount_changed() cascade;
drop function if exists pomgt.quote_line_after_write() cascade;
drop function if exists pomgt.recompute_quote_totals(uuid);
drop function if exists pomgt.quote_line_before_write() cascade;
drop table if exists pomgt.quote_lines cascade;
drop table if exists pomgt.quotes cascade;
alter table if exists pomgt.document_links
  drop column if exists quote_id;

-- Roles module cleanup: drop the permission rows seeded for the removed
-- modules (harmless to leave, but keeps the Roles screen's matrix tidy),
-- and stop seeding them for orgs that run ensure_default_roles from now on.
delete from pomgt.role_permissions
where module_key in ('quotes', 'inventory', 'purchasing', 'traceability', 'reports');

create or replace function pomgt.ensure_default_roles(p_org uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  admin_id uuid;
  supervisor_id uuid;
  sales_id uuid;
  viewer_id uuid;
  operator_id uuid;
  modules text[] := array[
    'dashboard', 'customers', 'orders', 'products', 'materials', 'bom',
    'routings', 'production', 'documents', 'master_data', 'roles'
  ];
  m text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  if not pomgt.is_member(p_org) then
    raise exception 'No tiene acceso a esta organización';
  end if;

  if not exists (select 1 from pomgt.roles where organization_id = p_org and code = 'operator') then
    insert into pomgt.roles (organization_id, code, name, description, is_system)
    values (p_org, 'operator', 'Operador', 'Personal de planta asignable a órdenes de producción.', true)
    returning id into operator_id;

    insert into pomgt.role_permissions (role_id, module_key, can_view, can_edit, can_delete)
    select operator_id, m, m in ('dashboard', 'production'), false, false
    from unnest(modules) as m;
  end if;

  if exists (select 1 from pomgt.roles where organization_id = p_org and code <> 'operator') then
    return;
  end if;

  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'admin', 'Administrador', 'Acceso completo a todos los módulos.', true)
  returning id into admin_id;
  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'supervisor', 'Supervisor de planta', 'Gestiona producción y materiales.', true)
  returning id into supervisor_id;
  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'sales', 'Ventas', 'Pedidos y clientes.', true)
  returning id into sales_id;
  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'viewer', 'Solo lectura', 'Consulta todos los módulos sin editar.', true)
  returning id into viewer_id;

  foreach m in array modules loop
    insert into pomgt.role_permissions (role_id, module_key, can_view, can_edit, can_delete)
    values (admin_id, m, true, true, true);
    insert into pomgt.role_permissions (role_id, module_key, can_view, can_edit, can_delete)
    values (viewer_id, m, true, false, false);
  end loop;

  insert into pomgt.role_permissions (role_id, module_key, can_view, can_edit, can_delete)
  select
    supervisor_id,
    m,
    true,
    m in ('production', 'materials', 'bom', 'routings', 'documents'),
    m = 'production'
  from unnest(modules) as m;

  insert into pomgt.role_permissions (role_id, module_key, can_view, can_edit, can_delete)
  select
    sales_id,
    m,
    true,
    m in ('orders', 'customers'),
    m = 'orders'
  from unnest(modules) as m;
end;
$$;

grant execute on function pomgt.ensure_default_roles(uuid) to authenticated;

notify pgrst, 'reload schema';
