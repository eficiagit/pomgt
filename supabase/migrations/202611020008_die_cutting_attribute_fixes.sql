-- Corrects the 'Dados de corte' attribute definitions created in
-- 202611020007 based on reviewing ~381 of the ~448 real rows:
--
-- 1. AC / AR are NOT millimeter measurements (as originally guessed from
--    the single example row, where they coincidentally looked numeric).
--    Across the full data they are small integers (cavity counts: how
--    many cavities the die has across the web / around the cylinder),
--    e.g. AC=2, AR=7. Changed to integer and relabeled.
-- 2. GAP AC / GAP AR sometimes hold compound values the original example
--    didn't show, e.g. "0.125 / 0.375" or "0.0625 & 0.1875". Changed from
--    decimal to text so no data is lost or silently truncated.
-- 3. Added the additional SHAPE / TYPE (die) / STATE options observed in
--    the real data (the original seed only had the one option visible in
--    the single example row).
--
-- No die records exist yet, so these are safe in-place corrections.

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'DADOS_CORTE'
)
update pomgt.material_attribute_definitions ad
set data_type = 'integer', label = 'AC · cavidades a lo ancho'
from mt
where ad.material_type_id = mt.id and ad.attribute_key = 'ac';

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'DADOS_CORTE'
)
update pomgt.material_attribute_definitions ad
set data_type = 'integer', label = 'AR · cavidades alrededor'
from mt
where ad.material_type_id = mt.id and ad.attribute_key = 'ar';

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'DADOS_CORTE'
)
update pomgt.material_attribute_definitions ad
set data_type = 'text'
from mt
where ad.material_type_id = mt.id and ad.attribute_key in ('gap_ac', 'gap_ar');

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'DADOS_CORTE'
)
insert into pomgt.material_attribute_options (organization_id, attribute_definition_id, option_value, option_label, sort_order, is_active)
select (select id from org), ad.id, v.option_value, v.option_label, v.sort_order, true
from (values
  ('shape', 'rect_perf', 'Rectangular perforado', 20),
  ('shape', 'circle', 'Círculo', 30),
  ('shape', 'square', 'Cuadrado', 40),
  ('shape', 'square_perf', 'Cuadrado perforado', 50),
  ('shape', 'ellipse', 'Elipse', 60),
  ('die_type', 'flexible_die', 'Flexible die', 20),
  ('die_type', 'solid_drill', 'Solid drill', 30),
  ('die_type', 'magnetic', 'Magnético', 40),
  ('state', 'regular', 'Regular', 20),
  ('state', 'bad', 'Malo', 30)
) as v(attribute_key, option_value, option_label, sort_order)
join pomgt.material_attribute_definitions ad
  on ad.material_type_id = (select id from mt) and ad.attribute_key = v.attribute_key
where not exists (
  select 1 from pomgt.material_attribute_options o
  where o.attribute_definition_id = ad.id and o.option_value = v.option_value
);

notify pgrst, 'reload schema';
