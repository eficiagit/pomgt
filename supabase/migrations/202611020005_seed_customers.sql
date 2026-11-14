-- Registers the customer list provided by the user. Only the name was
-- given, so customer_code is derived from it and legal_name is kept
-- exactly as provided; everything else (tax id, currency, payment terms,
-- contacts, addresses) is left for later via the Clientes screen.
-- Assumes a single organization; adjust the org subquery below if there is
-- more than one. Uses "where not exists" (not "on conflict") because the
-- unique constraint documented in this repo's migration history may not
-- match what is actually enforced on the live database.

insert into pomgt.customers (organization_id, customer_code, legal_name, default_currency_code, is_active)
select (select id from pomgt.organizations order by created_at limit 1), v.customer_code, v.legal_name, 'MXN', true
from (values
  ('ALL_AMERICAN', 'ALL AMERICAN'),
  ('BALBOA_WHATER_GROUP', 'BALBOA WHATER GROUP'),
  ('BC_TAGS', 'BC-TAGS'),
  ('CENGROW', 'CENGROW'),
  ('DAEYOUNG', 'DAEYOUNG'),
  ('GECKO_ALLIANCE', 'GECKO ALLIANCE'),
  ('GENERAC', 'GENERAC'),
  ('HUSSMANN', 'HUSSMANN'),
  ('IMPORTACIONES_REGIONALES', 'IMPORTACIONES REGIONALES'),
  ('LA_SINALOA', 'LA SINALOA'),
  ('LIMEX_SICAR_FARM', 'LIMEX SICAR FARM'),
  ('PANASONIC_TECMA', 'PANASONIC TECMA'),
  ('PARPRO', 'PARPRO'),
  ('PEMCO', 'PEMCO'),
  ('PLANTIMEX', 'PLANTIMEX'),
  ('SEACOMP_DISPLAYS_INC', 'SEACOMP DISPLAYS INC'),
  ('SOHNEN_MXC', 'SOHNEN MXC'),
  ('SPECK_PRODUCT', 'SPECK PRODUCT'),
  ('TIJUANA_BOX', 'TIJUANA BOX')
) as v(customer_code, legal_name)
where not exists (
  select 1 from pomgt.customers c
  where c.organization_id = (select id from pomgt.organizations order by created_at limit 1)
    and (c.customer_code = v.customer_code or c.legal_name = v.legal_name)
);

notify pgrst, 'reload schema';
