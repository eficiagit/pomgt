-- Operators become organization_members + invite flow.
--
-- Context: the standalone `operators` catalog duplicated people already
-- tracked as `organization_members`. From now on a "floor operator" IS a
-- member — just one with a lighter role (see the new 'operator' default
-- role in pomgt.ensure_default_roles) — assigned to production orders via
-- production_order_operators.member_id instead of .operator_id.
--
-- Members require a real Supabase Auth account (organization_members.user_id
-- is NOT NULL), and this project has no server-side/admin-privileged code
-- path (no Edge Functions, no service_role usage) to create Auth users on
-- an admin's behalf. So account creation stays entirely client-side via the
-- existing public signUp flow, and an invite closes the loop: an admin
-- creates an invite (email + role) for their org, the invitee signs up
-- normally with that exact email, then redeems the invite's token to join
-- the org with the assigned role — instead of bootstrapping their own new
-- organization.

create extension if not exists pgcrypto;

create table if not exists pomgt.organization_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  email varchar not null,
  role_id uuid references pomgt.roles(id) on delete set null,
  token text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  invited_by uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz
);

create index if not exists organization_invites_organization_idx
  on pomgt.organization_invites (organization_id);
create index if not exists organization_invites_token_idx
  on pomgt.organization_invites (token);

alter table pomgt.organization_invites enable row level security;
drop policy if exists tenant_member_all on pomgt.organization_invites;
create policy tenant_member_all
  on pomgt.organization_invites
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update on pomgt.organization_invites to authenticated;

-- Any member can invite, mirroring this app's existing org-level (not yet
-- role-level) security model everywhere else.
create or replace function pomgt.create_organization_invite(
  p_org uuid,
  p_email text,
  p_role_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  new_token text;
  normalized_email text := lower(trim(p_email));
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  if not pomgt.is_member(p_org) then
    raise exception 'No tiene acceso a esta organización';
  end if;
  if normalized_email = '' then
    raise exception 'El correo es requerido';
  end if;
  if p_role_id is not null and not exists (
    select 1 from pomgt.roles where id = p_role_id and organization_id = p_org
  ) then
    raise exception 'El rol no pertenece a esta organización';
  end if;

  new_token := encode(gen_random_bytes(24), 'hex');

  insert into pomgt.organization_invites (organization_id, email, role_id, token, invited_by)
  values (p_org, normalized_email, p_role_id, new_token, auth.uid());

  return new_token;
end;
$$;

grant execute on function pomgt.create_organization_invite(uuid, text, uuid) to authenticated;

-- Lets the invitee preview what they're accepting (org + role name) before
-- and after they redeem it. Only reachable while authenticated, matching
-- this app's flow (sign up first, then paste the code on Organization Setup).
create or replace function pomgt.get_invite_info(p_token text)
returns table (organization_name text, role_name text, email text, status text)
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  invite_row pomgt.organization_invites%rowtype;
  org_name text;
  r_name text;
  eff_status text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into invite_row from pomgt.organization_invites where token = p_token;
  if not found then
    raise exception 'Código de invitación no válido';
  end if;

  select display_name into org_name from pomgt.organizations where id = invite_row.organization_id;
  select name into r_name from pomgt.roles where id = invite_row.role_id;

  eff_status := invite_row.status;
  if eff_status = 'pending' and invite_row.expires_at < now() then
    eff_status := 'expired';
  end if;

  return query select org_name, r_name, invite_row.email, eff_status;
end;
$$;

grant execute on function pomgt.get_invite_info(text) to authenticated;

create or replace function pomgt.accept_organization_invite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  invite_row pomgt.organization_invites%rowtype;
  current_email text;
  current_name text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into invite_row from pomgt.organization_invites where token = p_token for update;
  if not found then
    raise exception 'Código de invitación no válido';
  end if;
  if invite_row.status <> 'pending' then
    raise exception 'Esta invitación ya no está disponible';
  end if;
  if invite_row.expires_at < now() then
    update pomgt.organization_invites set status = 'expired' where id = invite_row.id;
    raise exception 'Esta invitación venció';
  end if;

  select email, coalesce(raw_user_meta_data->>'full_name', '')
    into current_email, current_name
  from auth.users
  where id = auth.uid();

  if current_email is null or lower(current_email) <> invite_row.email then
    raise exception 'Esta invitación fue enviada a otro correo electrónico';
  end if;

  if exists (
    select 1 from pomgt.organization_members
    where organization_id = invite_row.organization_id and user_id = auth.uid()
  ) then
    raise exception 'Ya eres miembro de esta organización';
  end if;

  insert into pomgt.organization_members (
    organization_id, user_id, full_name, email, role_id, is_active
  )
  values (
    invite_row.organization_id, auth.uid(), nullif(current_name, ''), current_email,
    invite_row.role_id, true
  );

  update pomgt.organization_invites
  set status = 'accepted', accepted_at = now()
  where id = invite_row.id;

  return invite_row.organization_id;
end;
$$;

grant execute on function pomgt.accept_organization_invite(text) to authenticated;

-- Add a starter 'operator' role alongside the four seeded in
-- 202609280006_roles_and_audit.sql. create or replace with the full body so
-- orgs that already called ensure_default_roles (and thus already have
-- roles, making the "no roles yet" early-return trigger) still get it via a
-- second, targeted insert below.
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

-- production_order_operators: operator_id (-> operators) becomes member_id
-- (-> organization_members). There is no reliable identity mapping between
-- the old standalone operator rows and real member accounts, so existing
-- assignments are cleared rather than guessed at — this is a clean cutover,
-- not a data-preserving migration.
delete from pomgt.production_order_operators;

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'production_order_operators_production_order_id_operator_id_key'
  ) then
    alter table pomgt.production_order_operators
      drop constraint production_order_operators_production_order_id_operator_id_key;
  end if;
end $$;

alter table pomgt.production_order_operators
  drop constraint if exists production_order_operators_operator_id_fkey;
alter table pomgt.production_order_operators
  drop column if exists operator_id;

alter table pomgt.production_order_operators
  add column if not exists member_id uuid references pomgt.organization_members(id) on delete cascade;
alter table pomgt.production_order_operators
  alter column member_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'production_order_operators_production_order_id_member_id_key'
  ) then
    alter table pomgt.production_order_operators
      add constraint production_order_operators_production_order_id_member_id_key
      unique (production_order_id, member_id);
  end if;
end $$;

drop table if exists pomgt.operators cascade;

notify pgrst, 'reload schema';
