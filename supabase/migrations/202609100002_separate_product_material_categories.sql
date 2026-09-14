alter table if exists pomgt.product_categories
  add column if not exists icon_name text not null default 'category';

create table if not exists pomgt.material_categories (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  code character varying not null,
  name character varying not null,
  description text,
  icon_name text not null default 'layers',
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint material_categories_pkey primary key (id),
  constraint material_categories_organization_id_fkey
    foreign key (organization_id) references pomgt.organizations(id)
);

alter table if exists pomgt.products
  add column if not exists material_category_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_material_category_id_fkey'
  ) then
    alter table pomgt.products
      add constraint products_material_category_id_fkey
      foreign key (material_category_id)
      references pomgt.material_categories(id);
  end if;
end $$;

insert into pomgt.material_categories (
  organization_id,
  code,
  name,
  description,
  icon_name,
  is_active,
  created_at,
  updated_at
)
select distinct
  pc.organization_id,
  pc.code,
  pc.name,
  pc.description,
  coalesce(pc.icon_name, 'layers'),
  pc.is_active,
  now(),
  now()
from pomgt.products p
join pomgt.product_categories pc on pc.id = p.category_id
where p.product_type::text in ('raw_material', 'consumable', 'packaging')
  and p.material_category_id is null
  and not exists (
    select 1
    from pomgt.material_categories mc
    where mc.organization_id = pc.organization_id
      and mc.code = pc.code
      and mc.name = pc.name
  );

update pomgt.products p
set material_category_id = mc.id,
    category_id = null
from pomgt.product_categories pc
join pomgt.material_categories mc
  on mc.organization_id = pc.organization_id
 and mc.code = pc.code
 and mc.name = pc.name
where p.category_id = pc.id
  and p.product_type::text in ('raw_material', 'consumable', 'packaging')
  and p.material_category_id is null;

alter table if exists pomgt.product_categories
  drop constraint if exists product_categories_parent_id_fkey;

alter table if exists pomgt.product_categories
  drop column if exists parent_id;
