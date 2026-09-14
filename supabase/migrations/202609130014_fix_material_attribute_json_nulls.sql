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
    'Rev.01',
    1,
    'active',
    'Revisión inicial',
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

notify pgrst, 'reload schema';
