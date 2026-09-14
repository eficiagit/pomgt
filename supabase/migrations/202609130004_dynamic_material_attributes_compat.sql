create schema if not exists pomgt;
create extension if not exists pgcrypto;

-- Keep the universal classification stable across restored or rebuilt databases.
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'pomgt' and t.typname = 'product_type'
  ) then
    create type pomgt.product_type as enum (
      'finished_good', 'semi_finished', 'raw_material', 'consumable',
      'packaging', 'tooling', 'service'
    );
  else
    alter type pomgt.product_type add value if not exists 'tooling';
  end if;
end;
$$;

alter table pomgt.material_types
  add column if not exists system_class pomgt.product_type not null default 'raw_material',
  add column if not exists icon_name text,
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_default boolean not null default false,
  add column if not exists notes text;

alter table pomgt.products
  add column if not exists material_type_id uuid,
  add column if not exists material_category_id uuid,
  add column if not exists standard_cost numeric,
  add column if not exists standard_cost_currency_code text;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'pomgt'
      and table_name = 'material_types'
      and column_name = 'system_class'
      and udt_name <> 'product_type'
  ) then
    alter table pomgt.material_types alter column system_class drop default;
    alter table pomgt.material_types
      alter column system_class type pomgt.product_type
      using system_class::pomgt.product_type;
    alter table pomgt.material_types alter column system_class set default 'raw_material'::pomgt.product_type;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'pomgt'
      and table_name = 'products'
      and column_name = 'product_type'
      and udt_name <> 'product_type'
  ) then
    alter table pomgt.products alter column product_type drop default;
    alter table pomgt.products
      alter column product_type type pomgt.product_type
      using product_type::pomgt.product_type;
    alter table pomgt.products alter column product_type set default 'finished_good'::pomgt.product_type;
  end if;
end;
$$;

create unique index if not exists material_types_organization_code_key
  on pomgt.material_types (organization_id, code);

create table if not exists pomgt.material_attribute_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id),
  material_type_id uuid not null references pomgt.material_types(id),
  attribute_key text not null,
  label text not null,
  description text,
  data_type text not null check (data_type in ('text','long_text','integer','decimal','boolean','date','select','multiselect')),
  uom_id uuid references pomgt.units_of_measure(id),
  placeholder text,
  help_text text,
  is_required boolean not null default false,
  is_filterable boolean not null default false,
  is_searchable boolean not null default false,
  validation_rules jsonb not null default '{}'::jsonb,
  default_value jsonb,
  section_name text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (material_type_id, attribute_key)
);

create table if not exists pomgt.material_attribute_options (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id),
  attribute_definition_id uuid not null references pomgt.material_attribute_definitions(id) on delete cascade,
  option_value text not null,
  option_label text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (attribute_definition_id, option_value)
);

create table if not exists pomgt.material_revision_attribute_values (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id),
  product_revision_id uuid not null references pomgt.product_revisions(id) on delete cascade,
  attribute_definition_id uuid not null references pomgt.material_attribute_definitions(id),
  value_text text,
  value_number numeric,
  value_boolean boolean,
  value_date date,
  value_json jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_revision_id, attribute_definition_id)
);

create index if not exists material_attribute_definitions_org_type_idx
  on pomgt.material_attribute_definitions (organization_id, material_type_id, is_active, sort_order);
create index if not exists material_attribute_options_definition_idx
  on pomgt.material_attribute_options (attribute_definition_id, is_active, sort_order);
create index if not exists material_revision_attribute_values_revision_idx
  on pomgt.material_revision_attribute_values (product_revision_id);
create index if not exists products_material_type_idx
  on pomgt.products (organization_id, material_type_id, product_type);

create or replace function pomgt.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists material_types_set_updated_at on pomgt.material_types;
create trigger material_types_set_updated_at before update on pomgt.material_types
for each row execute function pomgt.set_updated_at();
drop trigger if exists material_attribute_definitions_set_updated_at on pomgt.material_attribute_definitions;
create trigger material_attribute_definitions_set_updated_at before update on pomgt.material_attribute_definitions
for each row execute function pomgt.set_updated_at();
drop trigger if exists material_revision_attribute_values_set_updated_at on pomgt.material_revision_attribute_values;
create trigger material_revision_attribute_values_set_updated_at before update on pomgt.material_revision_attribute_values
for each row execute function pomgt.set_updated_at();

create or replace function pomgt.validate_material_attribute_definition()
returns trigger language plpgsql as $$
declare type_org uuid;
begin
  select organization_id into type_org from pomgt.material_types where id = new.material_type_id;
  if type_org is null or type_org <> new.organization_id then
    raise exception 'El atributo debe pertenecer a la misma organización que el tipo de material.';
  end if;
  if new.uom_id is not null and not exists (
    select 1 from pomgt.units_of_measure u where u.id = new.uom_id and u.organization_id = new.organization_id
  ) then
    raise exception 'La unidad debe pertenecer a la misma organización.';
  end if;
  if tg_op = 'UPDATE' and old.data_type <> new.data_type and exists (
    select 1 from pomgt.material_revision_attribute_values v where v.attribute_definition_id = new.id
  ) then
    raise exception 'No se puede cambiar el tipo de dato porque ya existen valores históricos.';
  end if;
  new.attribute_key = lower(regexp_replace(trim(new.attribute_key), '[^a-zA-Z0-9_]+', '_', 'g'));
  return new;
end;
$$;

drop trigger if exists material_attribute_definitions_validate on pomgt.material_attribute_definitions;
create trigger material_attribute_definitions_validate before insert or update on pomgt.material_attribute_definitions
for each row execute function pomgt.validate_material_attribute_definition();

create or replace function pomgt.validate_material_attribute_option()
returns trigger language plpgsql as $$
declare attr_org uuid; attr_type text;
begin
  select organization_id, data_type into attr_org, attr_type
  from pomgt.material_attribute_definitions where id = new.attribute_definition_id;
  if attr_org is null or attr_org <> new.organization_id then raise exception 'La opción no pertenece a la organización del atributo.'; end if;
  if attr_type not in ('select', 'multiselect') then raise exception 'Solo select y multiselect aceptan opciones.'; end if;
  return new;
end;
$$;

drop trigger if exists material_attribute_options_validate on pomgt.material_attribute_options;
create trigger material_attribute_options_validate before insert or update on pomgt.material_attribute_options
for each row execute function pomgt.validate_material_attribute_option();

create or replace function pomgt.validate_material_revision_attribute_value()
returns trigger language plpgsql as $$
declare attr record; revision_org uuid; product_material_type uuid; submitted_count integer; allowed_count integer;
begin
  select * into attr from pomgt.material_attribute_definitions where id = new.attribute_definition_id;
  select pr.organization_id, p.material_type_id into revision_org, product_material_type
  from pomgt.product_revisions pr join pomgt.products p on p.id = pr.product_id where pr.id = new.product_revision_id;
  if attr.id is null or revision_org is null then raise exception 'La revisión o el atributo no existe.'; end if;
  if new.organization_id <> revision_org or new.organization_id <> attr.organization_id then raise exception 'El valor técnico no pertenece a la organización.'; end if;
  if product_material_type is distinct from attr.material_type_id then raise exception 'El atributo no corresponde al tipo de material.'; end if;
  if attr.data_type in ('text','long_text','select') and (new.value_number is not null or new.value_boolean is not null or new.value_date is not null or new.value_json is not null) then raise exception 'Tipo de valor inválido.'; end if;
  if attr.data_type in ('integer','decimal') and (new.value_text is not null or new.value_boolean is not null or new.value_date is not null or new.value_json is not null) then raise exception 'Tipo de valor inválido.'; end if;
  if attr.data_type = 'integer' and new.value_number is not null and new.value_number <> trunc(new.value_number) then raise exception 'El atributo requiere un entero.'; end if;
  if attr.data_type = 'boolean' and (new.value_text is not null or new.value_number is not null or new.value_date is not null or new.value_json is not null) then raise exception 'Tipo de valor inválido.'; end if;
  if attr.data_type = 'date' and (new.value_text is not null or new.value_number is not null or new.value_boolean is not null or new.value_json is not null) then raise exception 'Tipo de valor inválido.'; end if;
  if attr.data_type = 'multiselect' and (new.value_text is not null or new.value_number is not null or new.value_boolean is not null or new.value_date is not null) then raise exception 'Tipo de valor inválido.'; end if;
  if attr.data_type = 'select' and new.value_text is not null and not exists (
    select 1 from pomgt.material_attribute_options o where o.attribute_definition_id = new.attribute_definition_id and o.option_value = new.value_text and o.is_active
  ) then raise exception 'La opción seleccionada no es válida.'; end if;
  if attr.data_type = 'multiselect' and new.value_json is not null then
    if jsonb_typeof(new.value_json) <> 'array' then raise exception 'El valor multiselección debe ser un arreglo.'; end if;
    select count(*) into submitted_count from jsonb_array_elements_text(new.value_json);
    select count(*) into allowed_count from jsonb_array_elements_text(new.value_json) s(value)
      join pomgt.material_attribute_options o on o.attribute_definition_id = new.attribute_definition_id and o.option_value = s.value and o.is_active;
    if submitted_count <> allowed_count then raise exception 'Una o más opciones no son válidas.'; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists material_revision_attribute_values_validate on pomgt.material_revision_attribute_values;
create trigger material_revision_attribute_values_validate before insert or update on pomgt.material_revision_attribute_values
for each row execute function pomgt.validate_material_revision_attribute_value();

create or replace function pomgt.sync_product_material_type()
returns trigger language plpgsql as $$
declare material_class text;
begin
  if new.material_type_id is null then return new; end if;
  select system_class into material_class from pomgt.material_types where id = new.material_type_id and organization_id = new.organization_id;
  if material_class is null then raise exception 'El tipo de material no pertenece a la organización.'; end if;
  new.product_type = material_class;
  return new;
end;
$$;

drop trigger if exists products_sync_material_type on pomgt.products;
create trigger products_sync_material_type before insert or update of material_type_id, organization_id on pomgt.products
for each row execute function pomgt.sync_product_material_type();

alter table pomgt.material_attribute_definitions enable row level security;
alter table pomgt.material_attribute_options enable row level security;
alter table pomgt.material_revision_attribute_values enable row level security;
alter table pomgt.material_types enable row level security;

drop policy if exists material_attribute_definitions_member_all on pomgt.material_attribute_definitions;
create policy material_attribute_definitions_member_all on pomgt.material_attribute_definitions for all using (exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_definitions.organization_id and om.user_id = auth.uid() and om.is_active)) with check (exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_definitions.organization_id and om.user_id = auth.uid() and om.is_active));
drop policy if exists material_attribute_options_member_all on pomgt.material_attribute_options;
create policy material_attribute_options_member_all on pomgt.material_attribute_options for all using (exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_options.organization_id and om.user_id = auth.uid() and om.is_active)) with check (exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_options.organization_id and om.user_id = auth.uid() and om.is_active));
drop policy if exists material_revision_attribute_values_member_all on pomgt.material_revision_attribute_values;
create policy material_revision_attribute_values_member_all on pomgt.material_revision_attribute_values for all using (exists (select 1 from pomgt.organization_members om where om.organization_id = material_revision_attribute_values.organization_id and om.user_id = auth.uid() and om.is_active)) with check (exists (select 1 from pomgt.organization_members om where om.organization_id = material_revision_attribute_values.organization_id and om.user_id = auth.uid() and om.is_active));

grant select, insert, update, delete on pomgt.material_attribute_definitions to authenticated;
grant select, insert, update, delete on pomgt.material_attribute_options to authenticated;
grant select, insert, update, delete on pomgt.material_revision_attribute_values to authenticated;
notify pgrst, 'reload schema';
