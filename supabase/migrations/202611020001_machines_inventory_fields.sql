-- Adds free-text inventory attributes to pomgt.machines (capacidad, voltaje,
-- ubicación), two new catalogs (categorías y tipos de máquina) so they can be
-- tagged and filtered from a dropdown instead of free text, and relaxes
-- work_center_id / currency_code to optional so a machine can be registered
-- as a standalone inventory record before it is assigned to a work center or
-- has a costed currency. The table already links to
-- pomgt.routing_operations via preferred_machine_id, so no changes are
-- needed there.

create table if not exists pomgt.machine_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists pomgt.machine_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

alter table pomgt.machine_categories enable row level security;
alter table pomgt.machine_types enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'pomgt' and tablename = 'machine_categories' and policyname = 'machine_categories_member_all'
  ) then
    create policy machine_categories_member_all on pomgt.machine_categories
      for all to authenticated
      using (pomgt.is_member(organization_id))
      with check (pomgt.is_member(organization_id));
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'pomgt' and tablename = 'machine_types' and policyname = 'machine_types_member_all'
  ) then
    create policy machine_types_member_all on pomgt.machine_types
      for all to authenticated
      using (pomgt.is_member(organization_id))
      with check (pomgt.is_member(organization_id));
  end if;
end;
$$;

grant select, insert, update, delete on pomgt.machine_categories to authenticated, service_role;
grant select, insert, update, delete on pomgt.machine_types to authenticated, service_role;

alter table if exists pomgt.machines
  add column if not exists capacity character varying;
alter table if exists pomgt.machines
  add column if not exists voltage character varying;
alter table if exists pomgt.machines
  add column if not exists location character varying;
alter table if exists pomgt.machines
  add column if not exists category_id uuid references pomgt.machine_categories(id);
alter table if exists pomgt.machines
  add column if not exists machine_type_id uuid references pomgt.machine_types(id);

alter table if exists pomgt.machines
  alter column work_center_id drop not null;
alter table if exists pomgt.machines
  alter column currency_code drop not null;

notify pgrst, 'reload schema';
