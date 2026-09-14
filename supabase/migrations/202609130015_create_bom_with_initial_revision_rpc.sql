create or replace function pomgt.create_bom_with_initial_revision(
  p_product_id uuid,
  p_bom_code text,
  p_name text,
  p_description text default null,
  p_is_default boolean default false,
  p_revision_code text default 'Rev. 01',
  p_output_quantity numeric default 1,
  p_output_uom_id uuid default null,
  p_revision_status text default 'draft'
)
returns uuid
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  product_row pomgt.products%rowtype;
  new_bom_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  if nullif(trim(coalesce(p_bom_code, '')), '') is null then
    raise exception 'El código de estructura es requerido';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception 'El nombre de la estructura es requerido';
  end if;

  if nullif(trim(coalesce(p_revision_code, '')), '') is null then
    raise exception 'El código de revisión es requerido';
  end if;

  if coalesce(p_output_quantity, 0) <= 0 then
    raise exception 'La cantidad base de salida debe ser mayor a cero';
  end if;

  select *
    into product_row
  from pomgt.products
  where id = p_product_id;

  if not found then
    raise exception 'Producto no encontrado';
  end if;

  if not pomgt.is_member(product_row.organization_id) then
    raise exception 'No tiene acceso a la organización del producto';
  end if;

  if p_output_uom_id is null then
    p_output_uom_id := product_row.base_uom_id;
  end if;

  if p_output_uom_id is null then
    raise exception 'Selecciona una unidad de salida';
  end if;

  if p_is_default then
    update pomgt.boms
       set is_default = false,
           updated_at = now()
     where organization_id = product_row.organization_id
       and product_id = p_product_id
       and is_default = true;
  end if;

  insert into pomgt.boms (
    organization_id,
    product_id,
    bom_code,
    name,
    description,
    is_default,
    is_active
  )
  values (
    product_row.organization_id,
    p_product_id,
    trim(p_bom_code),
    trim(p_name),
    nullif(trim(coalesce(p_description, '')), ''),
    coalesce(p_is_default, false),
    true
  )
  returning id into new_bom_id;

  insert into pomgt.bom_revisions (
    organization_id,
    bom_id,
    revision_code,
    status,
    output_quantity,
    output_uom_id,
    expected_scrap_pct,
    expected_yield_pct
  )
  values (
    product_row.organization_id,
    new_bom_id,
    trim(p_revision_code),
    coalesce(nullif(trim(p_revision_status), ''), 'draft')::pomgt.bom_status,
    p_output_quantity,
    p_output_uom_id,
    0,
    100
  );

  return new_bom_id;
end;
$$;

grant execute on function pomgt.create_bom_with_initial_revision(
  uuid,
  text,
  text,
  text,
  boolean,
  text,
  numeric,
  uuid,
  text
) to authenticated;

notify pgrst, 'reload schema';
