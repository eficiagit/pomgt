-- Roles y auditoría granular.
--
-- Two independent pieces:
--   1) Roles: a per-organization role catalog + a permission matrix
--      (module_key -> can_view/can_edit/can_delete), assignable to members.
--      `pomgt.ensure_default_roles` seeds four starter roles the first time
--      the Roles screen opens for an org, instead of touching the existing
--      bootstrap_organization RPC.
--   2) Audit log: an append-only trail of INSERT/UPDATE/DELETE on the
--      highest-value business tables, written by a generic trigger.
--
-- Scope note: this ships the data model, the seeding, and a management/
-- viewer UI. It does NOT yet gate every button in every screen by
-- permission — enforcing the matrix across ~15 existing screens is a much
-- larger, separate change. The audit log, by contrast, IS fully live: it
-- captures every write to the audited tables regardless of the UI.
--
-- Side fix: organization_members previously only had a SELECT policy
-- scoped to `user_id = auth.uid()` (see 202609130010), with no UPDATE
-- policy at all. That silently limited the existing "Miembros" tab in
-- Datos maestros to showing only yourself, and would have made role
-- assignment here impossible. Both are replaced with org-scoped policies.

drop policy if exists organization_members_self_access on pomgt.organization_members;
create policy organization_members_member_read
  on pomgt.organization_members
  for select
  to authenticated
  using (pomgt.is_member(organization_id));

drop policy if exists organization_members_member_update on pomgt.organization_members;
create policy organization_members_member_update
  on pomgt.organization_members
  for update
  to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

create table if not exists pomgt.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  code varchar not null,
  name varchar not null,
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roles_org_code_unique unique (organization_id, code)
);

create index if not exists roles_organization_idx on pomgt.roles (organization_id);

create table if not exists pomgt.role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null references pomgt.roles(id) on delete cascade,
  module_key text not null,
  can_view boolean not null default true,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  constraint role_permissions_unique unique (role_id, module_key)
);

alter table pomgt.organization_members
  add column if not exists role_id uuid references pomgt.roles(id) on delete set null;

drop trigger if exists roles_set_updated_at on pomgt.roles;
create trigger roles_set_updated_at
  before update on pomgt.roles
  for each row execute function pomgt.set_updated_at();

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
  modules text[] := array[
    'dashboard', 'customers', 'quotes', 'orders', 'products', 'materials', 'bom',
    'routings', 'production', 'documents', 'inventory', 'purchasing',
    'traceability', 'reports', 'master_data', 'roles'
  ];
  m text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  if not pomgt.is_member(p_org) then
    raise exception 'No tiene acceso a esta organización';
  end if;

  if exists (select 1 from pomgt.roles where organization_id = p_org) then
    return;
  end if;

  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'admin', 'Administrador', 'Acceso completo a todos los módulos.', true)
  returning id into admin_id;
  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'supervisor', 'Supervisor de planta', 'Gestiona producción, materiales e inventario.', true)
  returning id into supervisor_id;
  insert into pomgt.roles (organization_id, code, name, description, is_system)
  values (p_org, 'sales', 'Ventas', 'Cotizaciones, pedidos y clientes.', true)
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
    m in ('production', 'materials', 'bom', 'routings', 'inventory', 'purchasing', 'traceability', 'documents'),
    m in ('production', 'inventory')
  from unnest(modules) as m;

  insert into pomgt.role_permissions (role_id, module_key, can_view, can_edit, can_delete)
  select
    sales_id,
    m,
    true,
    m in ('quotes', 'orders', 'customers'),
    m in ('quotes', 'orders')
  from unnest(modules) as m;
end;
$$;

grant execute on function pomgt.ensure_default_roles(uuid) to authenticated;

-- Audit log ---------------------------------------------------------------

create table if not exists pomgt.audit_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  table_name text not null,
  record_id uuid,
  action text not null check (action in ('insert', 'update', 'delete')),
  changed_by uuid,
  changed_at timestamptz not null default now(),
  old_data jsonb,
  new_data jsonb
);

create index if not exists audit_log_organization_idx on pomgt.audit_log (organization_id, changed_at desc);
create index if not exists audit_log_table_idx on pomgt.audit_log (table_name, record_id);

create or replace function pomgt.audit_row_change()
returns trigger
language plpgsql
as $$
declare
  rec_id uuid;
  org uuid;
begin
  if tg_op = 'DELETE' then
    rec_id := old.id;
    org := old.organization_id;
  else
    rec_id := new.id;
    org := new.organization_id;
  end if;

  insert into pomgt.audit_log (organization_id, table_name, record_id, action, changed_by, old_data, new_data)
  values (
    org,
    tg_table_name,
    rec_id,
    lower(tg_op),
    auth.uid(),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $$
declare
  audited_tables text[] := array[
    'customers', 'customer_orders', 'production_orders', 'quotes',
    'purchase_orders', 'inventory_movements', 'suppliers'
  ];
  t text;
begin
  foreach t in array audited_tables loop
    execute format('drop trigger if exists %I_audit on pomgt.%I', t, t);
    execute format(
      'create trigger %I_audit after insert or update or delete on pomgt.%I for each row execute function pomgt.audit_row_change()',
      t, t
    );
  end loop;
end;
$$;

alter table pomgt.roles enable row level security;
drop policy if exists tenant_member_all on pomgt.roles;
create policy tenant_member_all
  on pomgt.roles
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.role_permissions enable row level security;
drop policy if exists tenant_member_all on pomgt.role_permissions;
create policy tenant_member_all
  on pomgt.role_permissions
  for all to authenticated
  using (pomgt.is_member((select organization_id from pomgt.roles where id = role_id)))
  with check (pomgt.is_member((select organization_id from pomgt.roles where id = role_id)));

alter table pomgt.audit_log enable row level security;
drop policy if exists tenant_member_all on pomgt.audit_log;
create policy tenant_member_all
  on pomgt.audit_log
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update, delete on pomgt.roles to authenticated;
grant select, insert, update, delete on pomgt.role_permissions to authenticated;
grant select, insert on pomgt.audit_log to authenticated;

notify pgrst, 'reload schema';
