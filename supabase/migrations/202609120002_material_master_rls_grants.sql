alter table if exists pomgt.material_categories enable row level security;
alter table if exists pomgt.material_types enable row level security;

drop policy if exists material_categories_member_all on pomgt.material_categories;
drop policy if exists material_categories_select on pomgt.material_categories;
drop policy if exists material_categories_insert on pomgt.material_categories;
drop policy if exists material_categories_update on pomgt.material_categories;
drop policy if exists material_categories_delete on pomgt.material_categories;

create policy material_categories_member_all
  on pomgt.material_categories
  for all
  using (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
        and om.is_active
    )
  )
  with check (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
        and om.is_active
    )
  );

drop policy if exists material_types_member_all on pomgt.material_types;

create policy material_types_member_all
  on pomgt.material_types
  for all
  using (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_types.organization_id
        and om.user_id = auth.uid()
        and om.is_active
    )
  )
  with check (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_types.organization_id
        and om.user_id = auth.uid()
        and om.is_active
    )
  );

grant select, insert, update, delete on pomgt.material_categories to authenticated;
grant select, insert, update, delete on pomgt.material_types to authenticated;
