-- Adds a 'Dados de corte' (cutting dies) material type with its technical
-- attributes. Does NOT insert the 448 die records yet — that comes once
-- the user shares the full data; this only prepares the type + attribute
-- definitions (and a minimal seed of select options) so the format can be
-- reviewed first.
--
-- "No." (row sequence) is not stored as an attribute — it is only used to
-- derive each die's SKU at mass-insert time.
-- "SPECIAL CLIENT" is intentionally NOT a dynamic attribute here — it maps
-- to pomgt.products.owner_customer_id / is_customer_specific (the same
-- customer-link mechanism added for Materiales), since the dynamic
-- material-attribute system has no "reference" data type. "GENERIC" means
-- owner_customer_id = null.
--
-- Assumes a single organization; adjust the org subquery below if there is
-- more than one.

insert into pomgt.material_types (organization_id, code, name, description, system_class, is_active)
select (select id from pomgt.organizations order by created_at limit 1), 'DADOS_CORTE', 'Dados de corte',
  'Dados (troqueles) de corte rotativo usados en la producción de etiquetas.', 'tooling', true
where not exists (
  select 1 from pomgt.material_types
  where organization_id = (select id from pomgt.organizations order by created_at limit 1) and code = 'DADOS_CORTE'
);

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'DADOS_CORTE'
)
insert into pomgt.material_attribute_definitions (
  organization_id, material_type_id, attribute_key, label, data_type,
  is_required, is_filterable, is_searchable, validation_rules, section_name, sort_order, is_active
)
select (select id from org), (select id from mt), v.attribute_key, v.label, v.data_type,
       false, v.filterable, false, '{}'::jsonb, v.section_name, v.sort_order, true
from (values
  ('ancho_in', 'Ancho (pulgadas)', 'decimal', false, 'Medidas (pulgadas)', 10),
  ('alto_in', 'Alto (pulgadas)', 'decimal', false, 'Medidas (pulgadas)', 20),
  ('ancho_mm', 'Ancho (mm)', 'decimal', false, 'Medidas (milímetros)', 30),
  ('alto_mm', 'Alto (mm)', 'decimal', false, 'Medidas (milímetros)', 40),
  ('ac', 'AC · Across (mm)', 'decimal', true, 'Medidas (milímetros)', 50),
  ('ar', 'AR · Around (mm)', 'decimal', true, 'Medidas (milímetros)', 60),
  ('special_type', 'Tipo especial', 'text', false, 'Construcción del dado', 70),
  ('shape', 'Forma', 'select', true, 'Construcción del dado', 80),
  ('die_type', 'Tipo de dado', 'select', true, 'Construcción del dado', 90),
  ('teeth', 'Dientes (Teeth)', 'integer', false, 'Construcción del dado', 100),
  ('roll_repeat', 'Repetición de rodillo (pulgadas)', 'decimal', false, 'Construcción del dado', 110),
  ('gap_ac', 'Separación AC (pulgadas)', 'decimal', false, 'Construcción del dado', 120),
  ('gap_ar', 'Separación AR (pulgadas)', 'decimal', false, 'Construcción del dado', 130),
  ('corner_radius', 'Radio de esquina (pulgadas)', 'decimal', false, 'Construcción del dado', 140),
  ('dice_size', 'Tamaño de cilindro (pulgadas)', 'decimal', false, 'Construcción del dado', 150),
  ('liner', 'Liner', 'text', false, 'Construcción del dado', 160),
  ('internal_folio', 'Folio interno', 'text', true, 'Identificación', 170),
  ('given_folio', 'Folio dado', 'text', true, 'Identificación', 180),
  ('state', 'Estado físico', 'select', true, 'Estado y ubicación', 190),
  ('location', 'Ubicación', 'text', true, 'Estado y ubicación', 200),
  ('details', 'Detalles', 'long_text', false, 'Estado y ubicación', 210)
) as v(attribute_key, label, data_type, filterable, section_name, sort_order);

-- Minimal starter options, seeded only from the one example row shared so
-- far. More will be added once the full 448-row list is reviewed.
with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'DADOS_CORTE'
)
insert into pomgt.material_attribute_options (organization_id, attribute_definition_id, option_value, option_label, sort_order, is_active)
select (select id from org), ad.id, v.option_value, v.option_label, v.sort_order, true
from (values
  ('shape', 'rect', 'Rectangular', 10),
  ('die_type', 'solid_die', 'Solid die', 10),
  ('state', 'good', 'Bueno', 10)
) as v(attribute_key, option_value, option_label, sort_order)
join pomgt.material_attribute_definitions ad
  on ad.material_type_id = (select id from mt) and ad.attribute_key = v.attribute_key;

notify pgrst, 'reload schema';
