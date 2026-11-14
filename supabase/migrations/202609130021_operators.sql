-- Operators (production floor personnel) and their assignment to production orders.
-- Powers the "Operadores" master-data tab and the operator chips on the
-- production Kanban board / OP detail.

create table if not exists pomgt.operators (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  employee_code varchar,
  full_name varchar not null,
  email varchar,
  phone varchar,
  role varchar,
  work_center_id uuid references pomgt.work_centers(id) on delete set null,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists operators_organization_idx
  on pomgt.operators (organization_id);

create table if not exists pomgt.production_order_operators (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id) on delete cascade,
  production_order_id uuid not null references pomgt.production_orders(id) on delete cascade,
  operator_id uuid not null references pomgt.operators(id) on delete cascade,
  role varchar not null default 'operator',
  notes text,
  created_at timestamptz not null default now(),
  unique (production_order_id, operator_id)
);

create index if not exists production_order_operators_order_idx
  on pomgt.production_order_operators (production_order_id);
create index if not exists production_order_operators_operator_idx
  on pomgt.production_order_operators (operator_id);

create or replace function pomgt.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists operators_set_updated_at on pomgt.operators;
create trigger operators_set_updated_at
  before update on pomgt.operators
  for each row execute function pomgt.set_updated_at();

alter table pomgt.operators enable row level security;
drop policy if exists tenant_member_all on pomgt.operators;
create policy tenant_member_all
  on pomgt.operators
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

alter table pomgt.production_order_operators enable row level security;
drop policy if exists tenant_member_all on pomgt.production_order_operators;
create policy tenant_member_all
  on pomgt.production_order_operators
  for all to authenticated
  using (pomgt.is_member(organization_id))
  with check (pomgt.is_member(organization_id));

grant select, insert, update, delete on pomgt.operators to authenticated;
grant select, insert, update, delete on pomgt.production_order_operators to authenticated;

notify pgrst, 'reload schema';
