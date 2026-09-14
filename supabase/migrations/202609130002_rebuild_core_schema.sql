create schema if not exists pomgt;
create extension if not exists pgcrypto;

create table if not exists pomgt.currencies (
  code text primary key,
  name text not null,
  symbol text not null,
  decimal_places integer not null default 2,
  is_active boolean not null default true
);

insert into pomgt.currencies (code, name, symbol, decimal_places)
values ('MXN', 'Peso mexicano', '$', 2), ('USD', 'Dolar estadounidense', '$', 2)
on conflict (code) do nothing;

create table if not exists pomgt.organizations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  legal_name text not null,
  display_name text not null,
  tax_id text,
  country_code text,
  timezone text not null default 'America/Tijuana',
  locale text not null default 'es-MX',
  default_currency_code text not null default 'MXN' references pomgt.currencies(code),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists pomgt.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text,
  email text,
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table if not exists pomgt.payment_terms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  due_days integer not null default 0,
  early_payment_days integer,
  early_payment_discount_pct numeric,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists pomgt.uom_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists pomgt.units_of_measure (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  category_id uuid references pomgt.uom_categories(id),
  code text not null,
  name text not null,
  symbol text not null,
  conversion_to_base numeric not null default 1,
  is_base_unit boolean not null default false,
  decimal_precision integer not null default 4,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists pomgt.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  customer_code text not null,
  legal_name text not null,
  trade_name text,
  tax_id text,
  tax_country_code text,
  website text,
  default_currency_code text not null default 'MXN' references pomgt.currencies(code),
  payment_term_id uuid references pomgt.payment_terms(id),
  notes text,
  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, customer_code)
);

create table if not exists pomgt.product_categories (
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

create table if not exists pomgt.material_categories (
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

create table if not exists pomgt.product_types (
  id uuid primary key default gen_random_uuid(), organization_id uuid references pomgt.organizations(id) on delete cascade,
  code text, name text, description text, system_class text, is_active boolean default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists pomgt.material_types (
  id uuid primary key default gen_random_uuid(), organization_id uuid references pomgt.organizations(id) on delete cascade,
  code text, name text, description text, system_class text default 'raw_material', sort_order integer default 0,
  is_default boolean default false, notes text, is_active boolean default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists pomgt.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  sku text not null, name text not null, description text,
  category_id uuid references pomgt.product_categories(id),
  material_category_id uuid references pomgt.material_categories(id),
  product_type_catalog_id uuid references pomgt.product_types(id),
  material_type_id uuid references pomgt.material_types(id),
  product_type text not null default 'finished_good', owner_customer_id uuid references pomgt.customers(id),
  base_uom_id uuid references pomgt.units_of_measure(id),
  is_manufacturable boolean not null default false, is_purchasable boolean not null default false,
  is_sellable boolean not null default true, is_customer_specific boolean not null default false,
  track_lots boolean not null default false, track_serials boolean not null default false,
  default_lead_time_days integer not null default 0, is_active boolean not null default true,
  created_by uuid, updated_by uuid, created_at timestamptz default now(), updated_at timestamptz default now(),
  unique (organization_id, sku)
);

create table if not exists pomgt.product_revisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid references pomgt.organizations(id) on delete cascade,
  product_id uuid not null references pomgt.products(id) on delete cascade, revision_code text not null,
  revision_no integer not null default 1, status text not null default 'draft', description text,
  effective_from date, effective_to date, is_current boolean not null default false,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists pomgt.customer_orders (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  order_number text not null, source_type text not null default 'customer_order', customer_id uuid references pomgt.customers(id),
  customer_contact_id uuid, external_reference text, customer_po_number text, order_date date not null default current_date,
  requested_delivery_date date, status text not null default 'draft', priority text not null default 'normal',
  currency_code text references pomgt.currencies(code), payment_term_id uuid references pomgt.payment_terms(id),
  billing_address_id uuid, shipping_address_id uuid, billing_address_snapshot jsonb, shipping_address_snapshot jsonb,
  notes text, special_instructions text, created_at timestamptz default now(), updated_at timestamptz default now(),
  unique (organization_id, order_number)
);

create table if not exists pomgt.customer_order_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  customer_order_id uuid not null references pomgt.customer_orders(id) on delete cascade, line_no integer not null,
  product_id uuid not null references pomgt.products(id), product_description_snapshot text not null,
  requested_quantity numeric not null, uom_id uuid references pomgt.units_of_measure(id), requested_delivery_date date,
  unit_price numeric, discount_pct numeric not null default 0, tax_pct numeric not null default 0,
  line_status text not null default 'open', requirement_snapshot jsonb, created_at timestamptz default now(), updated_at timestamptz default now()
);

create or replace function pomgt.bootstrap_organization(p_code text, p_legal_name text, p_display_name text)
returns uuid language plpgsql security definer set search_path = pomgt, public
as $$
declare org_id uuid;
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión'; end if;
  insert into organizations(code, legal_name, display_name) values (p_code, p_legal_name, p_display_name) returning id into org_id;
  insert into organization_members(organization_id, user_id, full_name, email)
  select org_id, id, coalesce(raw_user_meta_data->>'full_name', email), email from auth.users where id = auth.uid();
  return org_id;
end;
$$;

create or replace function pomgt.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function pomgt.is_member(target_org uuid)
returns boolean language sql stable security definer set search_path = pomgt, public
as $$ select exists (select 1 from organization_members where organization_id = target_org and user_id = auth.uid() and is_active); $$;

alter table pomgt.organizations enable row level security;
alter table pomgt.organization_members enable row level security;
alter table pomgt.payment_terms enable row level security;
alter table pomgt.uom_categories enable row level security;
alter table pomgt.units_of_measure enable row level security;
alter table pomgt.customers enable row level security;
alter table pomgt.product_categories enable row level security;
alter table pomgt.material_categories enable row level security;
alter table pomgt.product_types enable row level security;
alter table pomgt.material_types enable row level security;
alter table pomgt.products enable row level security;
alter table pomgt.product_revisions enable row level security;
alter table pomgt.customer_orders enable row level security;
alter table pomgt.customer_order_lines enable row level security;

create policy organization_members_self on pomgt.organization_members for select to authenticated using (user_id = auth.uid() or pomgt.is_member(organization_id));
create policy organizations_member on pomgt.organizations for select to authenticated using (pomgt.is_member(id));

do $$
declare t text;
begin
  foreach t in array array['payment_terms','uom_categories','units_of_measure','customers','product_categories','material_categories','product_types','material_types','products','product_revisions','customer_orders','customer_order_lines'] loop
    execute format('create policy %I_member_all on pomgt.%I for all to authenticated using (pomgt.is_member(organization_id)) with check (pomgt.is_member(organization_id))', t, t);
  end loop;
end $$;

grant usage on schema pomgt to authenticated, service_role;
grant select, insert, update, delete on all tables in schema pomgt to authenticated, service_role;
grant execute on function pomgt.bootstrap_organization(text, text, text) to authenticated;
grant execute on function pomgt.is_member(uuid) to authenticated;

notify pgrst, 'reload schema';
