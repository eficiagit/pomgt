-- Adds a 'Sustrato' material type (the facestock labels are printed on),
-- its technical attributes, and registers the 15 substrates the user
-- listed as individual materials with their inferable attribute values.
-- Attribute values left blank (adhesive on most items, caliper, gramaje,
-- use/resistance) were not stated in the source list and were not guessed.
--
-- Assumes a single organization; adjust the org subquery below if there is
-- more than one.

insert into pomgt.product_types (organization_id, code, name, system_class, is_active)
select (select id from pomgt.organizations order by created_at limit 1), 'RAW_MATERIAL', 'Materia prima', 'raw_material', true
where not exists (
  select 1 from pomgt.product_types
  where organization_id = (select id from pomgt.organizations order by created_at limit 1) and code = 'RAW_MATERIAL'
);

insert into pomgt.uom_categories (organization_id, code, name, description)
select (select id from pomgt.organizations order by created_at limit 1), 'CANTIDAD', 'Cantidad', 'Unidades discretas, por ejemplo piezas o rollos.'
where not exists (
  select 1 from pomgt.uom_categories
  where organization_id = (select id from pomgt.organizations order by created_at limit 1) and code = 'CANTIDAD'
);

insert into pomgt.units_of_measure (organization_id, category_id, code, name, symbol, is_base_unit, is_active)
select (select id from pomgt.organizations order by created_at limit 1),
       (select id from pomgt.uom_categories where organization_id = (select id from pomgt.organizations order by created_at limit 1) and code = 'CANTIDAD'),
       'ROLLO', 'Rollo', 'rollo', true, true
where not exists (
  select 1 from pomgt.units_of_measure
  where organization_id = (select id from pomgt.organizations order by created_at limit 1) and code = 'ROLLO'
);

insert into pomgt.material_types (organization_id, code, name, description, system_class, is_active)
select (select id from pomgt.organizations order by created_at limit 1), 'SUSTRATO', 'Sustrato',
  'Material base (facestock) con el que se fabrican las etiquetas.', 'raw_material', true
where not exists (
  select 1 from pomgt.material_types
  where organization_id = (select id from pomgt.organizations order by created_at limit 1) and code = 'SUSTRATO'
);

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'SUSTRATO'
)
insert into pomgt.material_attribute_definitions (
  organization_id, material_type_id, attribute_key, label, data_type,
  is_required, is_filterable, is_searchable, validation_rules, section_name, sort_order, is_active
)
select (select id from org), (select id from mt), v.attribute_key, v.label, v.data_type,
       false, v.filterable, false, '{}'::jsonb, v.section_name, v.sort_order, true
from (values
  ('acabado', 'Acabado', 'select', true, 'Apariencia', 10),
  ('color', 'Color', 'select', true, 'Apariencia', 20),
  ('adhesivo', 'Adhesivo', 'select', true, 'Adhesivo y construcción', 30),
  ('material_base', 'Material base / Liner', 'select', true, 'Adhesivo y construcción', 40),
  ('caliper', 'Caliper / Espesor', 'decimal', false, 'Dimensiones', 50),
  ('gramaje', 'Gramaje', 'decimal', false, 'Dimensiones', 60),
  ('compatibilidad_impresion', 'Compatibilidad de impresión', 'multiselect', true, 'Compatibilidad', 70),
  ('uso_resistencia', 'Uso / Resistencia', 'multiselect', true, 'Uso', 80)
) as v(attribute_key, label, data_type, filterable, section_name, sort_order);

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'SUSTRATO'
)
insert into pomgt.material_attribute_options (organization_id, attribute_definition_id, option_value, option_label, sort_order, is_active)
select (select id from org), ad.id, v.option_value, v.option_label, v.sort_order, true
from (values
  ('acabado', 'mate', 'Mate', 10),
  ('acabado', 'semi_brillante', 'Semi-brillante', 20),
  ('acabado', 'brillante', 'Brillante', 30),
  ('acabado', 'alto_brillo', 'Alto brillo', 40),
  ('color', 'blanco', 'Blanco', 10),
  ('color', 'transparente', 'Transparente', 20),
  ('color', 'negro', 'Negro', 30),
  ('color', 'plateado', 'Plateado', 40),
  ('adhesivo', 'permanente', 'Permanente', 10),
  ('adhesivo', 'removible', 'Removible', 20),
  ('adhesivo', 'ultra_removible', 'Ultra removible', 30),
  ('material_base', 'papel', 'Papel', 10),
  ('material_base', 'filmico', 'Fílmico', 20),
  ('material_base', 'sintetico', 'Sintético', 30),
  ('material_base', 'glassine', 'Glassine', 40),
  ('material_base', 'kraft', 'Kraft', 50),
  ('material_base', 'sin_liner', 'Sin liner', 60),
  ('compatibilidad_impresion', 'termica_directa', 'Térmica directa', 10),
  ('compatibilidad_impresion', 'transferencia_termica', 'Transferencia térmica', 20),
  ('compatibilidad_impresion', 'flexografia', 'Flexografía', 30),
  ('compatibilidad_impresion', 'digital', 'Digital', 40),
  ('uso_resistencia', 'interior', 'Interior', 10),
  ('uso_resistencia', 'exterior', 'Exterior', 20),
  ('uso_resistencia', 'resistente_congelacion', 'Resistente a congelación', 30),
  ('uso_resistencia', 'resistente_quimicos', 'Resistente a químicos', 40)
) as v(attribute_key, option_value, option_label, sort_order)
join pomgt.material_attribute_definitions ad
  on ad.material_type_id = (select id from mt) and ad.attribute_key = v.attribute_key;

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'SUSTRATO'
),
pt as (
  select id from pomgt.product_types where organization_id = (select id from org) and code = 'RAW_MATERIAL'
),
uom as (
  select id from pomgt.units_of_measure where organization_id = (select id from org) and code = 'ROLLO'
)
insert into pomgt.products (
  organization_id, sku, name, material_type_id, product_type_catalog_id, product_type,
  base_uom_id, is_manufacturable, is_purchasable, is_sellable, track_lots, is_active
)
select (select id from org), v.sku, v.name, (select id from mt), (select id from pt), 'raw_material',
       (select id from uom), false, true, false, true, true
from (values
  ('SUB-BOPP-CLEAR', 'BOPP Clear'),
  ('SUB-BOPP-MATTE', 'BOPP Matte'),
  ('SUB-CARDBOARD', 'Cardboard'),
  ('SUB-COVERUP-BLACK', 'Cover Up Black'),
  ('SUB-HIGLOSS', 'Hi-Gloss'),
  ('SUB-PAPER', 'Paper'),
  ('SUB-PET-MATTE', 'PET Matte'),
  ('SUB-POLYESTER', 'Polyester'),
  ('SUB-POLYIMIDE', 'Polyimide'),
  ('SUB-REM-SYNTHETIC', 'Removable Synthetic'),
  ('SUB-SEMIGLOSS', 'Semigloss'),
  ('SUB-THERMAL-DIRECT', 'Thermal Direct'),
  ('SUB-THERMAL-TRANSFER', 'Thermal Transfer'),
  ('SUB-VALERON', 'Valeron'),
  ('SUB-VINYL', 'Vinyl')
) as v(sku, name)
where not exists (
  select 1 from pomgt.products p
  where p.organization_id = (select id from org) and p.sku = v.sku
);

with org as (
  select id from pomgt.organizations order by created_at limit 1
)
insert into pomgt.product_revisions (organization_id, product_id, revision_code, revision_no, status)
select (select id from org), p.id, 'V.01', 1, 'active'
from pomgt.products p
where p.organization_id = (select id from org)
  and p.sku in ('SUB-BOPP-CLEAR', 'SUB-BOPP-MATTE', 'SUB-CARDBOARD', 'SUB-COVERUP-BLACK', 'SUB-HIGLOSS', 'SUB-PAPER', 'SUB-PET-MATTE', 'SUB-POLYESTER', 'SUB-POLYIMIDE', 'SUB-REM-SYNTHETIC', 'SUB-SEMIGLOSS', 'SUB-THERMAL-DIRECT', 'SUB-THERMAL-TRANSFER', 'SUB-VALERON', 'SUB-VINYL')
  and not exists (select 1 from pomgt.product_revisions pr where pr.product_id = p.id);

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
mt as (
  select id from pomgt.material_types where organization_id = (select id from org) and code = 'SUSTRATO'
)
insert into pomgt.material_revision_attribute_values (organization_id, product_revision_id, attribute_definition_id, value_text, value_json)
select (select id from org), pr.id, ad.id, v.value_text, v.value_json::jsonb
from (values
  ('SUB-BOPP-CLEAR', 'color', 'transparente', null),
  ('SUB-BOPP-CLEAR', 'material_base', 'filmico', null),
  ('SUB-BOPP-CLEAR', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-BOPP-MATTE', 'acabado', 'mate', null),
  ('SUB-BOPP-MATTE', 'material_base', 'filmico', null),
  ('SUB-BOPP-MATTE', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-CARDBOARD', 'material_base', 'papel', null),
  ('SUB-CARDBOARD', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-COVERUP-BLACK', 'color', 'negro', null),
  ('SUB-COVERUP-BLACK', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-HIGLOSS', 'acabado', 'alto_brillo', null),
  ('SUB-HIGLOSS', 'material_base', 'papel', null),
  ('SUB-HIGLOSS', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-PAPER', 'material_base', 'papel', null),
  ('SUB-PAPER', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-PET-MATTE', 'acabado', 'mate', null),
  ('SUB-PET-MATTE', 'material_base', 'filmico', null),
  ('SUB-PET-MATTE', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-POLYESTER', 'material_base', 'filmico', null),
  ('SUB-POLYESTER', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-POLYIMIDE', 'material_base', 'filmico', null),
  ('SUB-POLYIMIDE', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-REM-SYNTHETIC', 'adhesivo', 'removible', null),
  ('SUB-REM-SYNTHETIC', 'material_base', 'sintetico', null),
  ('SUB-REM-SYNTHETIC', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-SEMIGLOSS', 'acabado', 'semi_brillante', null),
  ('SUB-SEMIGLOSS', 'material_base', 'papel', null),
  ('SUB-SEMIGLOSS', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-THERMAL-DIRECT', 'material_base', 'papel', null),
  ('SUB-THERMAL-DIRECT', 'compatibilidad_impresion', null, '["termica_directa"]'),
  ('SUB-THERMAL-TRANSFER', 'compatibilidad_impresion', null, '["transferencia_termica"]'),
  ('SUB-VALERON', 'material_base', 'sintetico', null),
  ('SUB-VALERON', 'compatibilidad_impresion', null, '["flexografia"]'),
  ('SUB-VINYL', 'material_base', 'filmico', null),
  ('SUB-VINYL', 'compatibilidad_impresion', null, '["flexografia"]')
) as v(sku, attribute_key, value_text, value_json)
join pomgt.products p on p.sku = v.sku and p.organization_id = (select id from org)
join pomgt.product_revisions pr on pr.product_id = p.id and pr.revision_code = 'V.01'
join pomgt.material_attribute_definitions ad
  on ad.material_type_id = (select id from mt) and ad.attribute_key = v.attribute_key;

notify pgrst, 'reload schema';
