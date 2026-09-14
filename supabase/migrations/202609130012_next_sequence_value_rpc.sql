create schema if not exists pomgt;
create extension if not exists pgcrypto;

alter table pomgt.number_sequences
  add column if not exists sequence_key text,
  add column if not exists prefix text not null default '',
  add column if not exists next_value integer not null default 1,
  add column if not exists padding integer not null default 5,
  add column if not exists separator text not null default '-';

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'pomgt'
      and table_name = 'number_sequences'
      and column_name = 'data'
  ) then
    update pomgt.number_sequences
    set
      sequence_key = coalesce(sequence_key, data->>'sequence_key'),
      prefix = coalesce(nullif(prefix, ''), data->>'prefix', ''),
      next_value = coalesce(next_value, nullif(data->>'next_value', '')::integer, 1),
      padding = coalesce(padding, nullif(data->>'padding', '')::integer, 5),
      separator = coalesce(nullif(separator, ''), data->>'separator', '-')
    where data is not null;
  end if;
end;
$$;

create unique index if not exists number_sequences_organization_key_idx
  on pomgt.number_sequences (organization_id, sequence_key)
  where sequence_key is not null;

create or replace function pomgt.next_sequence_value(p_org uuid, p_key text)
returns text
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  sequence_row pomgt.number_sequences%rowtype;
  normalized_key text;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  if not pomgt.is_member(p_org) then
    raise exception 'No tiene acceso a esta organización';
  end if;

  normalized_key := upper(trim(coalesce(p_key, '')));
  if normalized_key = '' then
    raise exception 'La clave de secuencia es requerida';
  end if;

  insert into pomgt.number_sequences (
    organization_id,
    sequence_key,
    prefix,
    next_value,
    padding,
    separator
  )
  values (
    p_org,
    normalized_key,
    case normalized_key
      when 'CUSTOMER' then 'CLI'
      when 'ORDER' then 'PED'
      when 'DELIVERY' then 'ENT'
      when 'CLAIM' then 'REC'
      else normalized_key
    end,
    1,
    5,
    '-'
  )
  on conflict (organization_id, sequence_key)
  where sequence_key is not null
  do nothing;

  update pomgt.number_sequences
  set
    next_value = next_value + 1,
    updated_at = now()
  where organization_id = p_org
    and sequence_key = normalized_key
  returning * into sequence_row;

  if sequence_row.id is null then
    raise exception 'No fue posible obtener el siguiente folio';
  end if;

  return concat(
    sequence_row.prefix,
    case when sequence_row.prefix = '' then '' else sequence_row.separator end,
    lpad((sequence_row.next_value - 1)::text, sequence_row.padding, '0')
  );
end;
$$;

grant execute on function pomgt.next_sequence_value(uuid, text)
to authenticated, service_role;

notify pgrst, 'reload schema';
