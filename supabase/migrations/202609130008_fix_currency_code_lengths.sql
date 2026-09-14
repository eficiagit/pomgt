alter table if exists pomgt.organizations
  drop constraint if exists organizations_default_currency_code_fkey;
alter table if exists pomgt.customers
  drop constraint if exists customers_default_currency_code_fkey;
alter table if exists pomgt.customer_orders
  drop constraint if exists customer_orders_currency_code_fkey;
alter table if exists pomgt.work_centers
  drop constraint if exists work_centers_currency_code_fkey;
alter table if exists pomgt.machines
  drop constraint if exists machines_currency_code_fkey;
alter table if exists pomgt.labor_roles
  drop constraint if exists labor_roles_currency_code_fkey;
alter table if exists pomgt.routing_operations
  drop constraint if exists routing_operations_currency_code_fkey;
alter table if exists pomgt.routing_operation_cost_components
  drop constraint if exists routing_operation_cost_components_currency_code_fkey;
alter table if exists pomgt.production_order_costs
  drop constraint if exists production_order_costs_currency_code_fkey;
alter table if exists pomgt.products
  drop constraint if exists products_standard_cost_currency_code_fkey;

alter table if exists pomgt.currencies
  alter column code type varchar(3)
  using trim(code::text);

alter table if exists pomgt.organizations
  alter column default_currency_code drop default;
alter table if exists pomgt.organizations
  alter column default_currency_code type varchar(3)
  using trim(default_currency_code::text);
alter table if exists pomgt.organizations
  alter column default_currency_code set default 'MXN';
alter table if exists pomgt.customers
  alter column default_currency_code type varchar(3)
  using trim(default_currency_code::text);
alter table if exists pomgt.customer_orders
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.work_centers
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.machines
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.labor_roles
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.routing_operations
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.routing_operation_cost_components
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.production_order_costs
  alter column currency_code type varchar(3)
  using trim(currency_code::text);
alter table if exists pomgt.products
  alter column standard_cost_currency_code type varchar(3)
  using trim(standard_cost_currency_code::text);

alter table pomgt.organizations
  add constraint organizations_default_currency_code_fkey
  foreign key (default_currency_code) references pomgt.currencies(code);
alter table pomgt.customers
  add constraint customers_default_currency_code_fkey
  foreign key (default_currency_code) references pomgt.currencies(code);
alter table pomgt.customer_orders
  add constraint customer_orders_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.work_centers
  add constraint work_centers_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.machines
  add constraint machines_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.labor_roles
  add constraint labor_roles_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.routing_operations
  add constraint routing_operations_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.routing_operation_cost_components
  add constraint routing_operation_cost_components_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.production_order_costs
  add constraint production_order_costs_currency_code_fkey
  foreign key (currency_code) references pomgt.currencies(code);
alter table pomgt.products
  add constraint products_standard_cost_currency_code_fkey
  foreign key (standard_cost_currency_code) references pomgt.currencies(code);

notify pgrst, 'reload schema';
