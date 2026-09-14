alter table if exists pomgt.organizations
  alter column country_code type varchar(2)
  using nullif(trim(country_code::text), '');

alter table if exists pomgt.customers
  alter column tax_country_code type varchar(2)
  using nullif(trim(tax_country_code::text), '');

alter table if exists pomgt.customer_addresses
  alter column country_code type varchar(2)
  using nullif(trim(country_code::text), '');

alter table if exists pomgt.organizations
  alter column country_code set default 'MX';

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
  new_organization_id uuid;
  current_user_id uuid := auth.uid();
  current_email text;
  current_name text;
begin
  if current_user_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  select email, coalesce(raw_user_meta_data->>'full_name', '')
    into current_email, current_name
  from auth.users
  where id = current_user_id;

  insert into pomgt.organizations (
    code, legal_name, display_name, country_code
  )
  values (
    upper(trim(p_code)), trim(p_legal_name), trim(p_display_name), 'MX'
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
