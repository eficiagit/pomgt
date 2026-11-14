-- Seed data generated from the physical inventory list provided by the user.
-- Assumes a single organization; adjust the org subquery below if there is more than one.

insert into pomgt.machine_categories (organization_id, code, name, is_active)
select (select id from pomgt.organizations order by created_at limit 1), v.code, v.name, true
from (values
  ('produccion', 'Producción'),
  ('almacen', 'Almacén'),
  ('administracion', 'Administración'),
  ('instalaciones', 'Instalaciones')
) as v(code, name)
on conflict (organization_id, code) do nothing;

insert into pomgt.machine_types (organization_id, code, name, is_active)
select (select id from pomgt.organizations order by created_at limit 1), v.code, v.name, true
from (values
  ('printer_label', 'Impresora de etiquetas'),
  ('appliance', 'Electrodoméstico'),
  ('furniture', 'Mobiliario'),
  ('sanitary', 'Sanitario'),
  ('flexo_press', 'Maquinaria de impresión'),
  ('rewinder', 'Embobinador'),
  ('power_tool', 'Herramienta eléctrica'),
  ('hand_tool', 'Herramienta manual'),
  ('computer_equipment', 'Equipo de cómputo'),
  ('office_equipment', 'Equipo de oficina'),
  ('hvac', 'Climatización'),
  ('audio', 'Audio'),
  ('measuring', 'Instrumento de medición'),
  ('industrial_sink', 'Fregadero industrial'),
  ('handling', 'Equipo de manejo de materiales')
) as v(code, name)
on conflict (organization_id, code) do nothing;

with org as (
  select id from pomgt.organizations order by created_at limit 1
),
cats as (
  select code, id from pomgt.machine_categories where organization_id = (select id from org)
),
types as (
  select code, id from pomgt.machine_types where organization_id = (select id from org)
),
data (machine_code, name, manufacturer, model, serial_number, capacity, voltage, status, description, location, category_code, type_code) as (
  values
  ('PRIN_BL_001', 'IMPRESORA C/RIBBON', 'ZEBRA', '170XiII', '7059721', null, '110-350V', 'maintenance', 'RALLA LA IMPRESIÓN, PERO NO AFECTA TANTO.', 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_002', 'IMPRESORA C/RIBBON', 'ZEBRA', '140Xi4', '15J114800305', null, '110-240V', 'available', null, 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_003', 'IMPRESORA C/RIBBON', 'ZEBRA', '105SL', '65J123800201', null, '110-240V', 'maintenance', 'RALLA LA IMPRESIÓN, PERO NO AFECTA TANTO.', 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_004', 'IMPRESORA C/RIBBON', 'AVERY DENNISON AP 5.4', 'AP 5.4', '0026400312-AP54', null, '110-240V', 'available', null, 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_005', 'IMPRESORA C/RIBBON', 'AVERY DENNISON AP 5.4', 'AP 5.5', '1189830809-AP54', null, '110-240V', 'available', null, 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_006', 'IMPRESORA C/RIBBON', 'ZEBRA', '105SL', '65J123800201', null, '110-240V', 'available', null, 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_007', 'IMPRESORA C/RIBBON', 'AVERY DENNISON AP 5.4', '6405', '0717260706-6405', null, '115-240V', 'available', null, 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_008', 'IMPRESORA C/RIBBON', 'AVERY DENNISON AP 5.4', '6406', '0438980305-6405', null, '115-240V', 'down', 'PARTES Y PIEZAS', 'ALMACEN 1', 'almacen', 'printer_label'),
  ('PRIN_BL_009', 'CAFETERA', 'KEURIG', 'K-SLIM', '900.2100.0861289', '12 oz', '127V', 'available', null, 'ALMACEN 2', 'almacen', 'appliance'),
  ('PRIN_BL_010', 'MICROONDAS', 'BLACK+DECKER', null, 'Y250610018779', '1.1  ft³', '110-240V', 'available', null, 'ALMACEN 2', 'almacen', 'appliance'),
  ('PRIN_BL_011', 'MESA COMEDOR PLASTICA', 'LIFETIME', null, null, '2 PERSONAS', null, 'available', null, 'ALMACEN 2', 'almacen', 'furniture'),
  ('PRIN_BL_012', 'SILLA PLASICA', 'LIFETIME', null, null, '1 PERSONA', null, 'available', null, 'ALMACEN 2', 'almacen', 'furniture'),
  ('PRIN_BL_013', 'SILLA PLASICA', 'LIFETIME', null, null, '1 PERSONA', null, 'available', null, 'ALMACEN 2', 'almacen', 'furniture'),
  ('PRIN_BL_014', 'RACA METAL', null, null, null, '4 MODULOS', null, 'available', null, 'ALMACEN 2', 'almacen', 'furniture'),
  ('PRIN_BL_015', 'RACA METAL', null, null, null, '4 MODULOS', null, 'available', null, 'ALMACEN 2', 'almacen', 'furniture'),
  ('PRIN_BL_016', 'TASA DE BAÑO', 'LAMOSA', null, null, null, null, 'available', null, 'BAÑO 3 ALM.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_017', 'TANQUE DE TASA DE BAÑO', 'LAMOSA', null, null, '10LTS', null, 'available', null, 'BAÑO 3 ALM.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_018', 'MUEBLE LAVAMANOS', null, null, null, null, null, 'maintenance', 'DETERIORADO', 'BAÑO 3 ALM.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_019', 'LAVAMANOS', 'LAMOSA', null, null, null, null, 'available', null, 'BAÑO 3 ALM.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_020', 'GRIFO SENCILLO', null, null, null, null, null, 'available', null, 'BAÑO 3 ALM.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_021', 'MAQUINA DE PLACAS', 'ANDERSSON&VREELAND HYD. INC.', 'ORB X', '1218X-100095', '20LTS', '110-230V', 'available', null, 'ALMACEN 1', 'almacen', 'flexo_press'),
  ('PRIN_BL_022', 'MESA DE TRABAJO METAL/MADERA', null, null, null, '6 PERSONAS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_023', 'ARCHIVO METALICO', 'HON', null, null, '5 GABETAS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_024', 'RACA PLÁSTICO', null, null, null, '4 MODULOS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_025', 'RACA METAL', null, null, null, '4 MODULOS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_026', 'RACA METAL', null, null, null, '3 MODULOS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_027', 'RACA METAL', null, null, null, '3 MODULOS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_028', 'RACA METAL', null, null, null, '3 MODULOS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_029', 'RACA METAL', null, null, null, '3 MODULOS', null, 'available', null, 'ALMACEN 1', 'almacen', 'furniture'),
  ('PRIN_BL_030', 'EMBOBINADOR DE IMPRESORA', 'TAKE-A-LABEL', 'TAL-600R-06', null, null, '120V', 'available', null, 'ALMACEN 1', 'almacen', 'rewinder'),
  ('PRIN_BL_031', 'EMBOBINADOR DE IMPRESORA', 'LABELMATE USA', null, 'UCAT1-1019000', null, null, 'available', null, 'ALMACEN 1', 'almacen', 'rewinder'),
  ('PRIN_BL_032', 'IMPRENTA ALLIED GEAR', 'ALLIED GEAR', null, null, null, '330V', 'maintenance', 'DETERIORADO', 'PRODUCCION', 'produccion', 'flexo_press'),
  ('PRIN_BL_033', 'IMPRENTA MARK ANDY INC. 2200 SISTEM', 'MARK ANDY SISTEM 2200 INC.', '2200 SYSTEM', null, null, '330V', 'available', null, 'PRODUCCION', 'produccion', 'flexo_press'),
  ('PRIN_BL_034', 'MESA DE TRABAJO METAL/MADERA', null, null, null, '10 PERSONAS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_035', 'MESA DE CONTEO EMBOBINADOR', 'LEDERLE MACHINE COMPANY', '730-7', 'RT7930308', '3 PERSONAS', '180V', 'available', null, 'PRODUCCION', 'produccion', 'rewinder'),
  ('PRIN_BL_036', 'RACA METAL', null, null, null, '2 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_037', 'RACA METAL', null, null, null, '2 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_038', 'RACA METAL', null, null, null, '2 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_039', 'RACA METAL', null, null, null, '5 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_040', 'PISTOLA SECADORA', 'MILWAUKEE', '1220', null, null, '120V', 'available', null, 'PRODUCCION', 'produccion', 'power_tool'),
  ('PRIN_BL_041', 'EMBOBINADOR DE IMPRESORA', 'LABELMATE USA', null, 'MC10-A-1527016', null, '120V', 'available', null, 'PRODUCCION', 'produccion', 'rewinder'),
  ('PRIN_BL_042', 'TEIPERA MANUAL', null, null, null, '2 ft', null, 'available', null, 'PRODUCCION', 'produccion', 'hand_tool'),
  ('PRIN_BL_043', 'TEIPERA MANUAL', null, null, null, '2 ft', null, 'maintenance', 'ROTA', 'PRODUCCION', 'produccion', 'hand_tool'),
  ('PRIN_BL_044', 'TEIPERA MANUAL', null, null, null, '3 ft', null, 'available', null, 'PRODUCCION', 'produccion', 'hand_tool'),
  ('PRIN_BL_045', 'TEIPERA MANUAL', null, null, null, '3 ft', null, 'available', null, 'PRODUCCION', 'produccion', 'hand_tool'),
  ('PRIN_BL_046', 'RACA METAL', null, null, null, '5 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_047', 'RACA MAD/ANILOX', null, 'PIRAMIDAL', null, '18 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_048', 'BANCO', null, null, null, null, null, 'maintenance', 'TAPIZAR', 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_049', 'CPU', 'INTEL', 'OPTIPLEX745', 'CORE¨2DUO', null, '127', 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_050', 'MONITOR PC', 'LG', '24MP60VQ-P', '710USL7A3112', '24¨', '19V', 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_051', 'TECLADO USB', 'DELL', null, null, null, null, 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_052', 'MOUSE OPTICO USB', 'DELL', null, null, null, null, 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_053', 'SELECTOR IMPRESORA', null, null, null, null, null, 'available', null, 'PRODUCCION', 'produccion', 'office_equipment'),
  ('PRIN_BL_054', 'CALCULADORA', 'CANON', 'LS-100TS', null, null, 'BATERIA', 'available', null, 'PRODUCCION', 'produccion', 'office_equipment'),
  ('PRIN_BL_055', 'CALCULADORA', 'CASIO', 'MS-80B', null, null, 'BATERIA', 'available', null, 'PRODUCCION', 'produccion', 'office_equipment'),
  ('PRIN_BL_056', 'CALCULADORA', 'CASIO', 'MS-80B', null, null, 'BATERIA', 'available', null, 'PRODUCCION', 'produccion', 'office_equipment'),
  ('PRIN_BL_057', 'CINC INDUSTRIAL', 'ADVANCE', null, null, 'DOBLE', null, 'available', null, 'PRODUCCION', 'produccion', 'industrial_sink'),
  ('PRIN_BL_058', 'GRIFO MEZCLADOR', 'ADVANCE', null, null, 'DOBLE', null, 'maintenance', 'EMPAQUE', 'PRODUCCION', 'produccion', 'sanitary'),
  ('PRIN_BL_059', 'ARCHIVO METALICO', null, null, null, '4 GABETAS', null, 'maintenance', 'VIEJITO', 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_060', 'COMPRESOR', 'DEWALT', 'DXCM301.M', 'SN1315103A2580063', '30 GAL.107 bar', '120V', 'available', 'CONSUME MUCHO ACEITE SYNTHETIC', 'PRODUCCION', 'produccion', 'power_tool'),
  ('PRIN_BL_061', 'RACA METAL', null, null, null, '2 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_062', 'RACA METAL', null, null, null, '6 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_063', 'RACA METAL', null, null, null, '6 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_064', 'RACA METAL', null, null, null, '6 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_065', 'ESCALERA METALICA', 'TRUPER', 'TIJERA', '10335', '175KG', null, 'available', null, 'PRODUCCION', 'produccion', 'hand_tool'),
  ('PRIN_BL_066', 'VENTILADOR', 'DEWALT', 'DXF1616', '3122025', 'FIJO', '135V', 'available', null, 'PRODUCCION', 'produccion', 'hvac'),
  ('PRIN_BL_067', 'AIRE ACONDICIONADO', 'TRANE', null, null, '4 TON', '230V', 'maintenance', 'VIEJITO', 'PRODUCCION', 'produccion', 'hvac'),
  ('PRIN_BL_068', 'BARRA SONIDO', 'SAMSUNG', null, null, null, '120V', 'available', null, 'PRODUCCION', 'produccion', 'audio'),
  ('PRIN_BL_069', 'CARRITO CENTROS CARTON', null, null, null, null, null, 'available', null, 'PRODUCCION', 'produccion', 'handling'),
  ('PRIN_BL_070', 'CARRITO LISO', null, null, null, '2 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'handling'),
  ('PRIN_BL_071', 'CALENTADOR INDUSTRIAL', 'MARK ANDY INC.', '3DS-0237', '1167054-1', '3 PHASE', '230V', 'available', null, 'PRODUCCION', 'produccion', 'flexo_press'),
  ('PRIN_BL_072', 'CENTRO ENERGETICO MARK ANDY INC. 2200 SYSTEM', 'MARK ANDY INC.', '2200-10E', '1167054-1', '3 PHASE', '230V', 'available', null, 'PRODUCCION', 'produccion', 'flexo_press'),
  ('PRIN_BL_073', 'LAPARA SECADO UV', 'AMERICAN ULTRAVIOLET', 'PKW120134', '19990-2', '3 PHASE', '230V', 'available', null, 'PRODUCCION', 'produccion', 'flexo_press'),
  ('PRIN_BL_074', 'MONITOR PC', 'DELL', 'E170Sc', 'CN-0U072N-64180-9AD-0D5U', '17¨', '100-240V', 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_075', 'MONITOR PC', 'DELL', '2009Wt', 'CN-0FH8MW-74445-9BB-DE1L', '17¨', '100-240V', 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_076', 'MONITOR PC', 'DELL', '2009Wt', 'CN-0FH8MW-74445-0AI-570L', '17¨', '100-240V', 'available', null, 'PRODUCCION', 'produccion', 'computer_equipment'),
  ('PRIN_BL_077', 'STACKER', 'gbFlexo EQUIPAMENT', '2200-10', null, '10¨', '120V', 'available', null, 'PRODUCCION', 'produccion', 'flexo_press'),
  ('PRIN_BL_078', 'RACA METAL', null, null, null, '3 MODULOS', null, 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_079', 'MESA DE TRABAJO METAL/MADERA', null, null, null, '3 MODULOS', '120V', 'available', null, 'PRODUCCION', 'produccion', 'furniture'),
  ('PRIN_BL_080', 'TASA DE BAÑO', 'LAMOSA', null, null, null, null, 'available', null, 'BAÑO 1 PROD.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_081', 'TANQUE DE TASA DE BAÑO', 'LAMOSA', null, null, '10LTS', null, 'available', null, 'BAÑO 1 PROD.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_082', 'PORTARROLLO', 'KIIMBERLY-CLARK', null, null, null, null, 'available', null, 'BAÑO 1 PROD.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_083', 'DISPENZADOR DE TOALLAS PAPEL', 'KIIMBERLY-CLARK', null, null, null, null, 'available', null, 'BAÑO 1 PROD.', 'instalaciones', 'sanitary'),
  ('PRIN_BL_084', 'PORTARROLLO', 'WypAll', null, null, null, null, 'available', null, 'PRODUCCION', 'produccion', 'sanitary'),
  ('PRIN_BL_085', 'PORTARROLLO', 'WypAll', null, null, null, null, 'available', null, 'PRODUCCION', 'produccion', 'sanitary'),
  ('PRIN_BL_086', 'BASCULA', 'AWS', 'PS-25KG', null, '25KG', '6V/BATERIAS', 'available', null, 'PRODUCCION', 'produccion', 'measuring'),
  ('PRIN_BL_087', 'STROBO', 'SHIMPO', 'DT301', null, null, '115V', 'available', null, 'PRODUCCION', 'produccion', 'measuring'),
  ('PRIN_BL_088', 'STROBO', 'SHIMPO', 'DT301', null, null, '115V', 'available', null, 'PRODUCCION', 'produccion', 'measuring')
)
insert into pomgt.machines (
  organization_id, machine_code, name, manufacturer, model, serial_number,
  capacity, voltage, status, description, location, category_id, machine_type_id, is_active
)
select (select id from org), d.machine_code, d.name, d.manufacturer, d.model, d.serial_number,
       d.capacity, d.voltage, d.status::pomgt.machine_status, d.description, d.location, c.id, t.id, true
from data d
left join cats c on c.code = d.category_code
left join types t on t.code = d.type_code;

notify pgrst, 'reload schema';
