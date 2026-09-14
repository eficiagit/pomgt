create or replace function pomgt.is_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = pomgt, public
as $$
  select exists (
    select 1
    from pomgt.organization_members om
    where om.organization_id = target_org
      and om.user_id = auth.uid()
      and om.is_active
  );
$$;

grant execute on function pomgt.is_member(uuid) to authenticated;

grant usage on schema pomgt to authenticated;
grant select, insert, update, delete
on all tables in schema pomgt
to authenticated;

-- Every tenant-owned table receives the same organization boundary.
do $$
declare
  row_data record;
begin
  for row_data in
    select table_name
    from information_schema.columns
    where table_schema = 'pomgt'
      and column_name = 'organization_id'
      and table_name not in ('organizations', 'organization_members')
  loop
    execute format(
      'alter table pomgt.%I enable row level security',
      row_data.table_name
    );
    execute format(
      'drop policy if exists tenant_member_all on pomgt.%I',
      row_data.table_name
    );
    execute format(
      'create policy tenant_member_all on pomgt.%I for all to authenticated using (pomgt.is_member(organization_id)) with check (pomgt.is_member(organization_id))',
      row_data.table_name
    );
  end loop;
end;
$$;

alter table pomgt.organizations enable row level security;
drop policy if exists organizations_member_access on pomgt.organizations;
create policy organizations_member_access
  on pomgt.organizations
  for select
  to authenticated
  using (pomgt.is_member(id));

alter table pomgt.organization_members enable row level security;
drop policy if exists organization_members_self_access on pomgt.organization_members;
create policy organization_members_self_access
  on pomgt.organization_members
  for select
  to authenticated
  using (user_id = auth.uid());

alter table pomgt.currencies enable row level security;
drop policy if exists currencies_authenticated_read on pomgt.currencies;
create policy currencies_authenticated_read
  on pomgt.currencies
  for select
  to authenticated
  using (true);

-- Tables without organization_id inherit access from their tenant-owned parent.
alter table pomgt.document_versions enable row level security;
drop policy if exists document_versions_member_all on pomgt.document_versions;
create policy document_versions_member_all
  on pomgt.document_versions
  for all to authenticated
  using (exists (
    select 1 from pomgt.documents d
    where d.id = document_versions.document_id
      and pomgt.is_member(d.organization_id)
  ))
  with check (exists (
    select 1 from pomgt.documents d
    where d.id = document_versions.document_id
      and pomgt.is_member(d.organization_id)
  ));

alter table pomgt.customer_contact_emails enable row level security;
drop policy if exists customer_contact_emails_member_all on pomgt.customer_contact_emails;
create policy customer_contact_emails_member_all
  on pomgt.customer_contact_emails
  for all to authenticated
  using (exists (
    select 1 from pomgt.customer_contacts c
    where c.id = customer_contact_emails.contact_id
      and pomgt.is_member(c.organization_id)
  ))
  with check (exists (
    select 1 from pomgt.customer_contacts c
    where c.id = customer_contact_emails.contact_id
      and pomgt.is_member(c.organization_id)
  ));

alter table pomgt.customer_contact_phones enable row level security;
drop policy if exists customer_contact_phones_member_all on pomgt.customer_contact_phones;
create policy customer_contact_phones_member_all
  on pomgt.customer_contact_phones
  for all to authenticated
  using (exists (
    select 1 from pomgt.customer_contacts c
    where c.id = customer_contact_phones.contact_id
      and pomgt.is_member(c.organization_id)
  ))
  with check (exists (
    select 1 from pomgt.customer_contacts c
    where c.id = customer_contact_phones.contact_id
      and pomgt.is_member(c.organization_id)
  ));

alter table pomgt.product_custom_field_options enable row level security;
drop policy if exists product_custom_field_options_member_all on pomgt.product_custom_field_options;
create policy product_custom_field_options_member_all
  on pomgt.product_custom_field_options
  for all to authenticated
  using (exists (
    select 1
    from pomgt.product_custom_field_definitions f
    where f.id = product_custom_field_options.field_definition_id
      and pomgt.is_member(f.organization_id)
  ))
  with check (exists (
    select 1
    from pomgt.product_custom_field_definitions f
    where f.id = product_custom_field_options.field_definition_id
      and pomgt.is_member(f.organization_id)
  ));

alter table pomgt.product_revision_custom_values enable row level security;
drop policy if exists product_revision_custom_values_member_all on pomgt.product_revision_custom_values;
create policy product_revision_custom_values_member_all
  on pomgt.product_revision_custom_values
  for all to authenticated
  using (exists (
    select 1
    from pomgt.product_revisions r
    join pomgt.products p on p.id = r.product_id
    where r.id = product_revision_custom_values.product_revision_id
      and pomgt.is_member(p.organization_id)
  ))
  with check (exists (
    select 1
    from pomgt.product_revisions r
    join pomgt.products p on p.id = r.product_id
    where r.id = product_revision_custom_values.product_revision_id
      and pomgt.is_member(p.organization_id)
  ));

alter table pomgt.checklist_items enable row level security;
drop policy if exists checklist_items_member_all on pomgt.checklist_items;
create policy checklist_items_member_all
  on pomgt.checklist_items
  for all to authenticated
  using (exists (
    select 1 from pomgt.checklist_templates t
    where t.id = checklist_items.checklist_template_id
      and pomgt.is_member(t.organization_id)
  ))
  with check (exists (
    select 1 from pomgt.checklist_templates t
    where t.id = checklist_items.checklist_template_id
      and pomgt.is_member(t.organization_id)
  ));

alter table pomgt.routing_operation_checklists enable row level security;
drop policy if exists routing_operation_checklists_member_all on pomgt.routing_operation_checklists;
create policy routing_operation_checklists_member_all
  on pomgt.routing_operation_checklists
  for all to authenticated
  using (exists (
    select 1
    from pomgt.routing_operations o
    join pomgt.routing_revisions rr on rr.id = o.routing_revision_id
    join pomgt.routings r on r.id = rr.routing_id
    where o.id = routing_operation_checklists.routing_operation_id
      and pomgt.is_member(r.organization_id)
  ))
  with check (exists (
    select 1
    from pomgt.routing_operations o
    join pomgt.routing_revisions rr on rr.id = o.routing_revision_id
    join pomgt.routings r on r.id = rr.routing_id
    where o.id = routing_operation_checklists.routing_operation_id
      and pomgt.is_member(r.organization_id)
  ));

alter table pomgt.quality_check_items enable row level security;
drop policy if exists quality_check_items_member_all on pomgt.quality_check_items;
create policy quality_check_items_member_all
  on pomgt.quality_check_items
  for all to authenticated
  using (exists (
    select 1 from pomgt.quality_check_templates t
    where t.id = quality_check_items.quality_template_id
      and pomgt.is_member(t.organization_id)
  ))
  with check (exists (
    select 1 from pomgt.quality_check_templates t
    where t.id = quality_check_items.quality_template_id
      and pomgt.is_member(t.organization_id)
  ));

alter table pomgt.routing_operation_quality_checks enable row level security;
drop policy if exists routing_operation_quality_checks_member_all on pomgt.routing_operation_quality_checks;
create policy routing_operation_quality_checks_member_all
  on pomgt.routing_operation_quality_checks
  for all to authenticated
  using (exists (
    select 1
    from pomgt.routing_operations o
    join pomgt.routing_revisions rr on rr.id = o.routing_revision_id
    join pomgt.routings r on r.id = rr.routing_id
    where o.id = routing_operation_quality_checks.routing_operation_id
      and pomgt.is_member(r.organization_id)
  ))
  with check (exists (
    select 1
    from pomgt.routing_operations o
    join pomgt.routing_revisions rr on rr.id = o.routing_revision_id
    join pomgt.routings r on r.id = rr.routing_id
    where o.id = routing_operation_quality_checks.routing_operation_id
      and pomgt.is_member(r.organization_id)
  ));

notify pgrst, 'reload schema';
