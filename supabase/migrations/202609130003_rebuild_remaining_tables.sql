create schema if not exists pomgt;
create extension if not exists pgcrypto;

do $$
declare
  table_name text;
  table_names constant text[] := array[
    'number_sequences', 'documents', 'document_versions',
    'customer_addresses', 'customer_contacts', 'customer_contact_emails',
    'customer_contact_phones', 'material_attribute_definitions',
    'material_attribute_options', 'material_revision_attribute_values',
    'product_tolerances', 'product_custom_field_definitions',
    'product_custom_field_options', 'product_revision_custom_values',
    'customer_products', 'customer_requirements', 'design_approvals',
    'boms', 'bom_revisions', 'bom_items', 'bom_item_substitutes',
    'work_centers', 'machines', 'machine_parameter_definitions',
    'labor_roles', 'process_definitions', 'routings', 'routing_revisions',
    'routing_operations', 'routing_operation_dependencies',
    'routing_operation_materials', 'routing_operation_labor_requirements',
    'routing_operation_machine_parameters', 'checklist_templates',
    'checklist_items', 'routing_operation_checklists',
    'quality_check_templates', 'quality_check_items',
    'routing_operation_quality_checks', 'routing_operation_cost_components',
    'production_orders', 'production_order_allocations',
    'production_order_costs', 'deliveries', 'delivery_lines',
    'customer_claims', 'nonconformities', 'document_links'
  ];
begin
  foreach table_name in array table_names loop
    execute format($sql$
      create table if not exists pomgt.%I (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid references pomgt.organizations(id) on delete cascade,
        data jsonb not null default '{}'::jsonb,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )
    $sql$, table_name);
  end loop;
end;
$$;

grant select, insert, update, delete on all tables in schema pomgt to authenticated, service_role;
notify pgrst, 'reload schema';
