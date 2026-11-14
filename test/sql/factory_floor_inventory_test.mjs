// Run with PGLITE_MODULE pointing at @electric-sql/pglite's dist/index.js,
// or install that package in your Node environment. Uses an isolated database.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const org = '10000000-0000-0000-0000-000000000001';
const foreignOrg = '10000000-0000-0000-0000-000000000002';
const warehouse = '20000000-0000-0000-0000-000000000001';
const foreignWarehouse = '20000000-0000-0000-0000-000000000002';
const product = '30000000-0000-0000-0000-000000000001';
const foreignProduct = '30000000-0000-0000-0000-000000000002';
const material = '40000000-0000-0000-0000-000000000001';
const unit = '50000000-0000-0000-0000-000000000001';
const order = '60000000-0000-0000-0000-000000000001';
const user = '70000000-0000-0000-0000-000000000001';
await db.exec(`
  create schema pomgt; create schema auth;
  create role authenticated; create role anon;
  create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.user',true),'')::uuid $$;
  create table pomgt.organizations(id uuid primary key);
  insert into pomgt.organizations values ('${org}'),('${foreignOrg}');
  create function pomgt.is_member(id uuid) returns boolean language sql as $$ select id = '${org}'::uuid and auth.uid() = '${user}'::uuid $$;
  create table pomgt.units_of_measure(id uuid primary key);
  insert into pomgt.units_of_measure values ('${unit}');
  create table pomgt.products(id uuid primary key,organization_id uuid references pomgt.organizations(id),base_uom_id uuid references pomgt.units_of_measure(id));
  insert into pomgt.products values ('${product}','${org}','${unit}'),('${foreignProduct}','${foreignOrg}','${unit}');
  create table pomgt.machines(id uuid primary key);
  create table pomgt.production_orders(id uuid primary key,organization_id uuid references pomgt.organizations(id));
  insert into pomgt.production_orders values ('${order}','${org}');
  create table pomgt.production_order_materials(id uuid primary key,production_order_id uuid references pomgt.production_orders(id),material_product_id uuid references pomgt.products(id),uom_id uuid references pomgt.units_of_measure(id),issued_quantity numeric default 0);
  insert into pomgt.production_order_materials values ('${material}','${order}','${product}','${unit}',0);
  -- Fixture for the existing production RPC. The new migration must call it
  -- inside the same transaction as stock, preserving its production rules.
  create function pomgt.register_production_material_movement(p_material_id uuid,p_movement_type text,p_quantity numeric,p_lot_number text,p_warehouse_reference text,p_note text)
    returns jsonb language plpgsql as $$
    begin
      update pomgt.production_order_materials set issued_quantity=issued_quantity+case when p_movement_type='issue' then p_quantity else -p_quantity end where id=p_material_id;
      return '{}'::jsonb;
    end $$;
  grant usage on schema pomgt,auth to authenticated,anon;
  select set_config('test.user','${user}',false);
`);
const root = new URL('../../', import.meta.url);
for (let repeat=0;repeat<2;repeat++) {
  for (const file of ['202611030001_machine_floor_position.sql','202611030002_complete_factory_floor.sql']) {
    await db.exec(await readFile(new URL(`supabase/migrations/${file}`,root),'utf8'));
  }
}
await db.exec(await readFile(new URL('supabase/factory_floor_upgrade.sql',root),'utf8'));
await db.exec(`insert into pomgt.warehouses(id,organization_id,code,name) values ('${warehouse}','${org}','A','Almacén'),('${foreignWarehouse}','${foreignOrg}','B','Otro');set role authenticated;`);
let serial=0;
const request=()=>`80000000-0000-0000-0000-${String(++serial).padStart(12,'0')}`;
const move=(type,quantity,{id=request(),w=warehouse,p=product,m=null}={})=>db.query(
  'select pomgt.record_floor_inventory_movement($1,$2,$3,$4,$5,$6,$7) as id',[w,p,type,quantity,id,'Prueba',m]);
const balance=async()=>Number((await db.query('select quantity_on_hand from pomgt.inventory_stock where warehouse_id=$1 and product_id=$2',[warehouse,product])).rows[0]?.quantity_on_hand??0);
const count=async()=>Number((await db.query('select count(*) from pomgt.inventory_movements')).rows[0].count);
await assert.rejects(db.exec(`insert into pomgt.inventory_stock(organization_id,warehouse_id,product_id,uom_id) values ('${org}','${warehouse}','${product}','${unit}')`),/permission denied/);
await move('receipt',100);assert.equal(await balance(),100);
await assert.rejects(db.exec('update pomgt.inventory_stock set quantity_on_hand=999'),/permission denied/);
await assert.rejects(db.exec('delete from pomgt.inventory_movements'),/permission denied/);
await assert.rejects(db.exec(`update pomgt.warehouses set floor_pos_x=-10 where id='${warehouse}'`),/posición/);
await assert.rejects(db.exec(`update pomgt.warehouses set organization_id='${foreignOrg}' where id='${warehouse}'`),/organización/);
const duplicate=request();
await move('issue',10,{id:duplicate});await move('issue',10,{id:duplicate});
assert.equal(await balance(),90);assert.equal(await count(),2);
await assert.rejects(move('issue',11,{id:duplicate}),/otro movimiento/);
const before=await count();
await assert.rejects(move('issue',1000),/Existencias insuficientes/);
assert.equal(await balance(),90);assert.equal(await count(),before);
await assert.rejects(move('receipt',2,{p:foreignProduct}),/unidad base/);
await assert.rejects(move('receipt',2,{w:foreignWarehouse}),/organización/);
await assert.rejects(move('receipt',-1),/cantidad/);
await assert.rejects(move('receipt','NaN'),/cantidad/);
await assert.rejects(move('invalid',1),/Tipo/);
await move('issue',20,{m:material});assert.equal(await balance(),70);
await db.exec('reset role');
assert.equal(Number((await db.query('select issued_quantity from pomgt.production_order_materials')).rows[0].issued_quantity),20);
await db.exec('set role authenticated');
await assert.rejects(move('issue',1000,{m:material}),/Existencias insuficientes/);
await db.exec('reset role');
assert.equal(Number((await db.query('select issued_quantity from pomgt.production_order_materials')).rows[0].issued_quantity),20,'production rolls back with a rejected stock debit');
await db.exec('set role authenticated');
await move('receipt',5,{m:material});assert.equal(await balance(),75);
await db.exec('reset role');
assert.equal(Number((await db.query('select issued_quantity from pomgt.production_order_materials')).rows[0].issued_quantity),15);
await db.exec(`set role authenticated;select set_config('test.user','',false)`);
await assert.rejects(move('receipt',1),/iniciar sesión/);
assert.equal((await db.query('select * from pomgt.inventory_stock')).rows.length,0,'RLS hides balances without membership');
await db.exec(`select set_config('test.user','${user}',false)`);
await assert.rejects(db.exec(`insert into pomgt.floor_zones(organization_id,name) values ('${foreignOrg}','Intrusión')`),/row-level security/);
await db.exec(`insert into pomgt.floor_zones(organization_id,name) values ('${org}','Producción')`);
assert.equal((await db.query('select * from pomgt.warehouses')).rows.length,1,'RLS hides the other organization');
await db.close();
console.log('Factory inventory SQL passed: migrations repeat safely; stock, idempotency, insufficient balance, atomic production rollback, tenant isolation and permissions verified.');
