alter table if exists pomgt.organization_members enable row level security;
alter table if exists pomgt.organizations enable row level security;

grant usage on schema pomgt to authenticated;
grant select on pomgt.organization_members to authenticated;
grant select on pomgt.organizations to authenticated;

drop policy if exists organization_members_self_access on pomgt.organization_members;
create policy organization_members_self_access
  on pomgt.organization_members
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists organizations_member_access on pomgt.organizations;
create policy organizations_member_access
  on pomgt.organizations
  for select
  to authenticated
  using (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = organizations.id
        and om.user_id = auth.uid()
        and om.is_active
    )
  );

notify pgrst, 'reload schema';
