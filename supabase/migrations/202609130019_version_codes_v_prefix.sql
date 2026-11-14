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
  org uuid;
  product_id uuid;
  revision_id uuid;
  item jsonb;
  type_row pomgt.material_types%rowtype;
  type_catalog_id uuid;
begin
  org := (p_material->>'organization_id')::uuid;
  if org is null or not exists (
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
    raise exception 'El tipo de material no pertenece a la organización.';
  end if;

  select id into type_catalog_id
  from pomgt.product_types
  where organization_id = org
    and system_class = type_row.system_class
  order by created_at
  limit 1;

  if type_catalog_id is null then
    insert into pomgt.product_types (
      organization_id,
      code,
      name,
      description,
      system_class,
      is_active
    )
    values (
      org,
      upper(type_row.system_class::text),
      initcap(replace(type_row.system_class::text, '_', ' ')),
      'Tipo interno creado para materiales.',
      type_row.system_class,
      true
    )
    returning id into type_catalog_id;
  end if;

  insert into pomgt.products (
    organization_id,
    sku,
    name,
    description,
    product_type,
    product_type_catalog_id,
    material_type_id,
    material_category_id,
    base_uom_id,
    is_manufacturable,
    is_purchasable,
    is_sellable,
    is_customer_specific,
    track_lots,
    track_serials,
    default_lead_time_days,
    is_active,
    standard_cost,
    standard_cost_currency_code,
    created_by,
    updated_by
  )
  values (
    org,
    p_material->>'sku',
    p_material->>'name',
    nullif(p_material->>'description', ''),
    type_row.system_class,
    type_catalog_id,
    type_row.id,
    nullif(p_material->>'material_category_id', '')::uuid,
    (p_material->>'base_uom_id')::uuid,
    false,
    true,
    false,
    false,
    coalesce((p_material->>'track_lots')::boolean, false),
    coalesce((p_material->>'track_serials')::boolean, false),
    coalesce((p_material->>'default_lead_time_days')::integer, 0),
    coalesce((p_material->>'is_active')::boolean, true),
    nullif(p_material->>'standard_cost', '')::numeric,
    nullif(p_material->>'standard_cost_currency_code', '')::bpchar,
    auth.uid(),
    auth.uid()
  )
  returning id into product_id;

  insert into pomgt.product_revisions (
    organization_id,
    product_id,
    revision_code,
    revision_no,
    status,
    description,
    created_by,
    updated_by
  )
  values (
    org,
    product_id,
    'V.01',
    1,
    'active',
    'Versión inicial',
    auth.uid(),
    auth.uid()
  )
  returning id into revision_id;

  for item in select * from jsonb_array_elements(coalesce(p_attribute_values, '[]'::jsonb))
  loop
    insert into pomgt.material_revision_attribute_values (
      organization_id,
      product_revision_id,
      attribute_definition_id,
      value_text,
      value_number,
      value_boolean,
      value_date,
      value_json
    )
    values (
      org,
      revision_id,
      (item->>'attribute_definition_id')::uuid,
      nullif(item->>'value_text', ''),
      nullif(item->>'value_number', '')::numeric,
      case
        when item ? 'value_boolean'
          and jsonb_typeof(item->'value_boolean') <> 'null'
        then (item->>'value_boolean')::boolean
        else null
      end,
      nullif(item->>'value_date', '')::date,
      case
        when item ? 'value_json'
          and jsonb_typeof(item->'value_json') <> 'null'
        then item->'value_json'
        else null
      end
    );
  end loop;

  return jsonb_build_object('product_id', product_id, 'revision_id', revision_id);
end;
$$;


grant execute on function pomgt.create_material_with_revision(jsonb, jsonb)
to authenticated, service_role;

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
  values (org, p_product_id, 'V.' || lpad(next_no::text, 2, '0'), next_no, 'draft', 'Nueva versión', auth.uid(), auth.uid())
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

grant execute on function pomgt.create_material_revision(uuid, uuid) to authenticated;

-- Normaliza los códigos de versión existentes a V.01, V.02...
-- Acepta: REV1, Rev 2, rev-03, Rev.01, Rev. 01, R1, Ver. 01, Versión 2, V1, etc.
-- Si el código nuevo ya existe en la misma estructura/ruta/producto, esa fila se omite.
update pomgt.product_revisions r
   set revision_code = 'V.' || lpad((regexp_match(r.revision_code, '(\d+)\s*$'))[1]::int::text, 2, '0')
 where r.revision_code ~* '^(rev(isi[oó]n)?|ver(si[oó]n)?|r|v)[\s._-]*\d+\s*$'
   and r.revision_code !~ '^V\.\d{2,}$'
   and not exists (
     select 1 from pomgt.product_revisions o
      where o.product_id = r.product_id and o.id <> r.id
        and o.revision_code = 'V.' || lpad((regexp_match(r.revision_code, '(\d+)\s*$'))[1]::int::text, 2, '0'));

update pomgt.bom_revisions r
   set revision_code = 'V.' || lpad((regexp_match(r.revision_code, '(\d+)\s*$'))[1]::int::text, 2, '0')
 where r.revision_code ~* '^(rev(isi[oó]n)?|ver(si[oó]n)?|r|v)[\s._-]*\d+\s*$'
   and r.revision_code !~ '^V\.\d{2,}$'
   and not exists (
     select 1 from pomgt.bom_revisions o
      where o.bom_id = r.bom_id and o.id <> r.id
        and o.revision_code = 'V.' || lpad((regexp_match(r.revision_code, '(\d+)\s*$'))[1]::int::text, 2, '0'));

update pomgt.routing_revisions r
   set revision_code = 'V.' || lpad((regexp_match(r.revision_code, '(\d+)\s*$'))[1]::int::text, 2, '0')
 where r.revision_code ~* '^(rev(isi[oó]n)?|ver(si[oó]n)?|r|v)[\s._-]*\d+\s*$'
   and r.revision_code !~ '^V\.\d{2,}$'
   and not exists (
     select 1 from pomgt.routing_revisions o
      where o.routing_id = r.routing_id and o.id <> r.id
        and o.revision_code = 'V.' || lpad((regexp_match(r.revision_code, '(\d+)\s*$'))[1]::int::text, 2, '0'));

notify pgrst, 'reload schema';
