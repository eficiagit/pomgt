alter table if exists pomgt.bom_items
  alter column quantity_basis drop not null,
  alter column formula_language drop not null,
  alter column uom_id drop not null,
  alter column scrap_pct drop not null,
  alter column expected_yield_pct drop not null,
  alter column is_optional drop not null,
  alter column is_phantom drop not null,
  alter column issue_method drop not null;

alter table if exists pomgt.bom_items
  alter column quantity_basis set default 'per_output_unit',
  alter column formula_language set default 'pomgt-expression',
  alter column scrap_pct set default 0,
  alter column expected_yield_pct set default 100,
  alter column is_optional set default false,
  alter column is_phantom set default false,
  alter column issue_method set default 'manual';

alter table if exists pomgt.material_categories enable row level security;

drop policy if exists material_categories_select on pomgt.material_categories;
drop policy if exists material_categories_insert on pomgt.material_categories;
drop policy if exists material_categories_update on pomgt.material_categories;
drop policy if exists material_categories_delete on pomgt.material_categories;

create policy material_categories_select
  on pomgt.material_categories
  for select
  using (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
    )
  );

create policy material_categories_insert
  on pomgt.material_categories
  for insert
  with check (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
    )
  );

create policy material_categories_update
  on pomgt.material_categories
  for update
  using (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
    )
  );

create policy material_categories_delete
  on pomgt.material_categories
  for delete
  using (
    exists (
      select 1
      from pomgt.organization_members om
      where om.organization_id = material_categories.organization_id
        and om.user_id = auth.uid()
    )
  );
