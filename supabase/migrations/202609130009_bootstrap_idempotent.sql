insert into pomgt.currencies (code, name, symbol, decimal_places, is_active)
values
  ('MXN', 'Peso mexicano', '$', 2, true),
  ('USD', 'Dolar estadounidense', '$', 2, true)
on conflict (code) do nothing;

drop function if exists pomgt.bootstrap_organization(text, text, text);

create function pomgt.bootstrap_organization(
  p_code text,
  p_legal_name text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  normalized_code text := upper(trim(p_code));
  new_organization_id uuid;
  current_user_id uuid := auth.uid();
  current_email text;
  current_name text;
begin
  if current_user_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  select id
    into new_organization_id
  from pomgt.organizations
  where code = normalized_code;

  if new_organization_id is not null then
    if exists (
      select 1
      from pomgt.organization_members
      where organization_id = new_organization_id
        and user_id = current_user_id
        and is_active
    ) then
      return new_organization_id;
    end if;

    raise exception 'El código de organización ya está en uso.';
  end if;

  select email, coalesce(raw_user_meta_data->>'full_name', '')
    into current_email, current_name
  from auth.users
  where id = current_user_id;

  insert into pomgt.organizations (
    code, legal_name, display_name, country_code
  )
  values (
    normalized_code, trim(p_legal_name), trim(p_display_name), 'MX'
  )
  returning id into new_organization_id;

  insert into pomgt.organization_members (
    organization_id, user_id, full_name, email, is_active
  )
  values (
    new_organization_id, current_user_id, nullif(current_name, ''), current_email, true
  );

  return new_organization_id;
end;
$$;

grant execute on function pomgt.bootstrap_organization(text, text, text)
  to authenticated;

notify pgrst, 'reload schema';
