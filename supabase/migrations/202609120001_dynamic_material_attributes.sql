alter type pomgt.product_type add value if not exists 'tooling';

alter table if exists pomgt.material_types
  add column if not exists system_class pomgt.product_type not null default 'raw_material',
  add column if not exists icon_name text,
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_default boolean not null default false,
  add column if not exists notes text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'material_types_organization_code_key'
  ) then
    alter table pomgt.material_types
      add constraint material_types_organization_code_key
      unique (organization_id, code);
  end if;
end $$;

create table if not exists pomgt.material_attribute_definitions (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id),
  material_type_id uuid not null references pomgt.material_types(id),
  attribute_key character varying not null,
  label character varying not null,
  description text,
  data_type character varying not null check (
    data_type in ('text', 'long_text', 'integer', 'decimal', 'boolean', 'date', 'select', 'multiselect')
  ),
  uom_id uuid references pomgt.units_of_measure(id),
  placeholder text,
  help_text text,
  is_required boolean not null default false,
  is_filterable boolean not null default false,
  is_searchable boolean not null default false,
  validation_rules jsonb not null default '{}'::jsonb,
  default_value jsonb,
  section_name character varying,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint material_attribute_definitions_pkey primary key (id),
  constraint material_attribute_definitions_key_unique unique (material_type_id, attribute_key)
);

create table if not exists pomgt.material_attribute_options (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id),
  attribute_definition_id uuid not null references pomgt.material_attribute_definitions(id),
  option_value character varying not null,
  option_label character varying not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  constraint material_attribute_options_pkey primary key (id),
  constraint material_attribute_options_value_unique unique (attribute_definition_id, option_value)
);

create table if not exists pomgt.material_revision_attribute_values (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null references pomgt.organizations(id),
  product_revision_id uuid not null references pomgt.product_revisions(id),
  attribute_definition_id uuid not null references pomgt.material_attribute_definitions(id),
  value_text text,
  value_number numeric,
  value_boolean boolean,
  value_date date,
  value_json jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint material_revision_attribute_values_pkey primary key (id),
  constraint material_revision_attribute_values_unique unique (product_revision_id, attribute_definition_id)
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
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists material_types_set_updated_at on pomgt.material_types;
create trigger material_types_set_updated_at
  before update on pomgt.material_types
  for each row execute function pomgt.set_updated_at();

drop trigger if exists material_attribute_definitions_set_updated_at on pomgt.material_attribute_definitions;
create trigger material_attribute_definitions_set_updated_at
  before update on pomgt.material_attribute_definitions
  for each row execute function pomgt.set_updated_at();

drop trigger if exists material_revision_attribute_values_set_updated_at on pomgt.material_revision_attribute_values;
create trigger material_revision_attribute_values_set_updated_at
  before update on pomgt.material_revision_attribute_values
  for each row execute function pomgt.set_updated_at();

create or replace function pomgt.validate_material_attribute_definition()
returns trigger
language plpgsql
as $$
declare
  type_org uuid;
begin
  select organization_id into type_org
  from pomgt.material_types
  where id = new.material_type_id;

  if type_org is null or type_org <> new.organization_id then
    raise exception 'El atributo debe pertenecer a la misma organización que el tipo de material.';
  end if;

  if new.uom_id is not null and not exists (
    select 1 from pomgt.units_of_measure u
    where u.id = new.uom_id and u.organization_id = new.organization_id
  ) then
    raise exception 'La unidad debe pertenecer a la misma organización.';
  end if;

  if tg_op = 'UPDATE' and old.data_type <> new.data_type and exists (
    select 1 from pomgt.material_revision_attribute_values v
    where v.attribute_definition_id = new.id
  ) then
    raise exception 'No se puede cambiar el tipo de dato porque ya existen valores históricos.';
  end if;

  new.attribute_key = lower(regexp_replace(trim(new.attribute_key), '[^a-zA-Z0-9_]+', '_', 'g'));
  return new;
end;
$$;

drop trigger if exists material_attribute_definitions_validate on pomgt.material_attribute_definitions;
create trigger material_attribute_definitions_validate
  before insert or update on pomgt.material_attribute_definitions
  for each row execute function pomgt.validate_material_attribute_definition();

create or replace function pomgt.validate_material_attribute_option()
returns trigger
language plpgsql
as $$
declare
  attr_org uuid;
  attr_type text;
begin
  select organization_id, data_type into attr_org, attr_type
  from pomgt.material_attribute_definitions
  where id = new.attribute_definition_id;

  if attr_org is null or attr_org <> new.organization_id then
    raise exception 'La opción debe pertenecer a la misma organización que el atributo.';
  end if;

  if attr_type not in ('select', 'multiselect') then
    raise exception 'Solo los atributos select o multiselect pueden tener opciones.';
  end if;

  return new;
end;
$$;

drop trigger if exists material_attribute_options_validate on pomgt.material_attribute_options;
create trigger material_attribute_options_validate
  before insert or update on pomgt.material_attribute_options
  for each row execute function pomgt.validate_material_attribute_option();

create or replace function pomgt.validate_material_revision_attribute_value()
returns trigger
language plpgsql
as $$
declare
  attr record;
  revision_org uuid;
  product_material_type uuid;
  allowed_count integer;
  submitted_count integer;
begin
  select * into attr
  from pomgt.material_attribute_definitions
  where id = new.attribute_definition_id;

  select pr.organization_id, p.material_type_id
    into revision_org, product_material_type
  from pomgt.product_revisions pr
  join pomgt.products p on p.id = pr.product_id
  where pr.id = new.product_revision_id;

  if attr.id is null or revision_org is null then
    raise exception 'La revisión o el atributo no existe.';
  end if;

  if new.organization_id <> revision_org or new.organization_id <> attr.organization_id then
    raise exception 'El valor técnico debe pertenecer a la misma organización.';
  end if;

  if product_material_type is distinct from attr.material_type_id then
    raise exception 'El atributo no corresponde al tipo de material del producto.';
  end if;

  if attr.data_type in ('text', 'long_text', 'select') and
     (new.value_number is not null or new.value_boolean is not null or new.value_date is not null or new.value_json is not null) then
    raise exception 'Tipo de valor inválido para atributo de texto.';
  end if;
  if attr.data_type in ('integer', 'decimal') and
     (new.value_text is not null or new.value_boolean is not null or new.value_date is not null or new.value_json is not null) then
    raise exception 'Tipo de valor inválido para atributo numérico.';
  end if;
  if attr.data_type = 'integer' and new.value_number is not null and new.value_number <> trunc(new.value_number) then
    raise exception 'El atributo requiere un entero.';
  end if;
  if attr.data_type = 'boolean' and
     (new.value_text is not null or new.value_number is not null or new.value_date is not null or new.value_json is not null) then
    raise exception 'Tipo de valor inválido para atributo booleano.';
  end if;
  if attr.data_type = 'date' and
     (new.value_text is not null or new.value_number is not null or new.value_boolean is not null or new.value_json is not null) then
    raise exception 'Tipo de valor inválido para atributo de fecha.';
  end if;
  if attr.data_type = 'multiselect' and
     (new.value_text is not null or new.value_number is not null or new.value_boolean is not null or new.value_date is not null) then
    raise exception 'Tipo de valor inválido para atributo multiselección.';
  end if;

  if attr.data_type = 'select' and new.value_text is not null and not exists (
    select 1 from pomgt.material_attribute_options o
    where o.attribute_definition_id = new.attribute_definition_id
      and o.option_value = new.value_text
      and o.is_active
  ) then
    raise exception 'La opción seleccionada no es válida.';
  end if;

  if attr.data_type = 'multiselect' and new.value_json is not null then
    if jsonb_typeof(new.value_json) <> 'array' then
      raise exception 'El valor multiselección debe ser un arreglo.';
    end if;
    select count(*) into submitted_count from jsonb_array_elements_text(new.value_json);
    select count(*) into allowed_count
    from jsonb_array_elements_text(new.value_json) selected(value)
    join pomgt.material_attribute_options o
      on o.attribute_definition_id = new.attribute_definition_id
     and o.option_value = selected.value
     and o.is_active;
    if submitted_count <> allowed_count then
      raise exception 'Una o más opciones seleccionadas no son válidas.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists material_revision_attribute_values_validate on pomgt.material_revision_attribute_values;
create trigger material_revision_attribute_values_validate
  before insert or update on pomgt.material_revision_attribute_values
  for each row execute function pomgt.validate_material_revision_attribute_value();

create or replace function pomgt.sync_product_material_type()
returns trigger
language plpgsql
as $$
declare
  material_class pomgt.product_type;
begin
  if new.material_type_id is null then
    return new;
  end if;

  select system_class into material_class
  from pomgt.material_types
  where id = new.material_type_id
    and organization_id = new.organization_id;

  if material_class is null then
    raise exception 'El tipo de material no pertenece a la organización.';
  end if;

  new.product_type = material_class;
  return new;
end;
$$;

drop trigger if exists products_sync_material_type on pomgt.products;
create trigger products_sync_material_type
  before insert or update of material_type_id, organization_id on pomgt.products
  for each row execute function pomgt.sync_product_material_type();

create or replace function pomgt.create_material_with_revision(
  p_material jsonb,
  p_attribute_values jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  org uuid := (p_material->>'organization_id')::uuid;
  type_row pomgt.material_types%rowtype;
  type_catalog_id uuid;
  product_id uuid;
  revision_id uuid;
  item jsonb;
begin
  if not exists (
    select 1 from pomgt.organization_members om
    where om.organization_id = org and om.user_id = auth.uid() and om.is_active
  ) then
    raise exception 'No tienes acceso a esta organización.';
  end if;

  select * into type_row
  from pomgt.material_types
  where id = (p_material->>'material_type_id')::uuid
    and organization_id = org;
  if type_row.id is null then
    raise exception 'Selecciona un tipo de material válido.';
  end if;

  select id into type_catalog_id
  from pomgt.product_types
  where organization_id = org and system_class = type_row.system_class and is_active
  order by created_at
  limit 1;

  if type_catalog_id is null then
    insert into pomgt.product_types (organization_id, code, name, description, system_class, is_active)
    values (org, upper(type_row.system_class::text), initcap(replace(type_row.system_class::text, '_', ' ')), 'Tipo interno creado para materiales.', type_row.system_class, true)
    returning id into type_catalog_id;
  end if;

  insert into pomgt.products (
    organization_id, sku, name, description, product_type, product_type_catalog_id,
    material_type_id, material_category_id, base_uom_id, is_manufacturable,
    is_purchasable, is_sellable, is_customer_specific, track_lots,
    track_serials, default_lead_time_days, is_active, standard_cost,
    standard_cost_currency_code, created_by, updated_by
  )
  values (
    org, p_material->>'sku', p_material->>'name', nullif(p_material->>'description', ''),
    type_row.system_class, type_catalog_id, type_row.id,
    nullif(p_material->>'material_category_id', '')::uuid,
    (p_material->>'base_uom_id')::uuid, false, true, false, false,
    coalesce((p_material->>'track_lots')::boolean, false),
    coalesce((p_material->>'track_serials')::boolean, false),
    coalesce((p_material->>'default_lead_time_days')::integer, 0),
    coalesce((p_material->>'is_active')::boolean, true),
    nullif(p_material->>'standard_cost', '')::numeric,
    nullif(p_material->>'standard_cost_currency_code', '')::bpchar,
    auth.uid(), auth.uid()
  )
  returning id into product_id;

  insert into pomgt.product_revisions (
    organization_id, product_id, revision_code, revision_no, status, description, created_by, updated_by
  )
  values (org, product_id, 'Rev.01', 1, 'active', 'Revisión inicial', auth.uid(), auth.uid())
  returning id into revision_id;

  for item in select * from jsonb_array_elements(coalesce(p_attribute_values, '[]'::jsonb))
  loop
    insert into pomgt.material_revision_attribute_values (
      organization_id, product_revision_id, attribute_definition_id,
      value_text, value_number, value_boolean, value_date, value_json
    )
    values (
      org, revision_id, (item->>'attribute_definition_id')::uuid,
      item->>'value_text',
      nullif(item->>'value_number', '')::numeric,
      case when item ? 'value_boolean' then (item->>'value_boolean')::boolean else null end,
      nullif(item->>'value_date', '')::date,
      item->'value_json'
    );
  end loop;

  return jsonb_build_object('product_id', product_id, 'revision_id', revision_id);
end;
$$;

create or replace function pomgt.create_material_revision(
  p_product_id uuid,
  p_copy_from_revision_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  org uuid;
  next_no integer;
  new_revision_id uuid;
begin
  select organization_id into org from pomgt.products where id = p_product_id;
  if org is null or not exists (
    select 1 from pomgt.organization_members om
    where om.organization_id = org and om.user_id = auth.uid() and om.is_active
  ) then
    raise exception 'No tienes acceso a este material.';
  end if;

  select coalesce(max(revision_no), 0) + 1 into next_no
  from pomgt.product_revisions
  where product_id = p_product_id;

  insert into pomgt.product_revisions (
    organization_id, product_id, revision_code, revision_no, status, description, created_by, updated_by
  )
  values (org, p_product_id, 'Rev.' || lpad(next_no::text, 2, '0'), next_no, 'draft', 'Nueva revisión', auth.uid(), auth.uid())
  returning id into new_revision_id;

  if p_copy_from_revision_id is not null then
    insert into pomgt.material_revision_attribute_values (
      organization_id, product_revision_id, attribute_definition_id,
      value_text, value_number, value_boolean, value_date, value_json
    )
    select organization_id, new_revision_id, attribute_definition_id,
      value_text, value_number, value_boolean, value_date, value_json
    from pomgt.material_revision_attribute_values
    where product_revision_id = p_copy_from_revision_id;
  end if;

  return new_revision_id;
end;
$$;

alter table pomgt.material_attribute_definitions enable row level security;
alter table pomgt.material_attribute_options enable row level security;
alter table pomgt.material_revision_attribute_values enable row level security;
alter table pomgt.material_types enable row level security;

drop policy if exists material_attribute_definitions_member_all on pomgt.material_attribute_definitions;
create policy material_attribute_definitions_member_all on pomgt.material_attribute_definitions
  for all using (
    exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_definitions.organization_id and om.user_id = auth.uid() and om.is_active)
  )
  with check (
    exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_definitions.organization_id and om.user_id = auth.uid() and om.is_active)
  );

drop policy if exists material_attribute_options_member_all on pomgt.material_attribute_options;
create policy material_attribute_options_member_all on pomgt.material_attribute_options
  for all using (
    exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_options.organization_id and om.user_id = auth.uid() and om.is_active)
  )
  with check (
    exists (select 1 from pomgt.organization_members om where om.organization_id = material_attribute_options.organization_id and om.user_id = auth.uid() and om.is_active)
  );

drop policy if exists material_revision_attribute_values_member_all on pomgt.material_revision_attribute_values;
create policy material_revision_attribute_values_member_all on pomgt.material_revision_attribute_values
  for all using (
    exists (select 1 from pomgt.organization_members om where om.organization_id = material_revision_attribute_values.organization_id and om.user_id = auth.uid() and om.is_active)
  )
  with check (
    exists (select 1 from pomgt.organization_members om where om.organization_id = material_revision_attribute_values.organization_id and om.user_id = auth.uid() and om.is_active)
  );

grant select, insert, update, delete on pomgt.material_attribute_definitions to authenticated;
grant select, insert, update, delete on pomgt.material_attribute_options to authenticated;
grant select, insert, update, delete on pomgt.material_revision_attribute_values to authenticated;
grant execute on function pomgt.create_material_with_revision(jsonb, jsonb) to authenticated;
grant execute on function pomgt.create_material_revision(uuid, uuid) to authenticated;
