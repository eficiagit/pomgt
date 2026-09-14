create or replace view pomgt.v_order_line_production_status
with (security_invoker = true)
as
select
  col.organization_id,
  col.customer_order_id,
  col.id as customer_order_line_id,
  col.line_no,
  col.product_id,
  col.product_description_snapshot,
  col.requested_quantity,
  col.uom_id,
  col.requested_delivery_date,
  col.line_status,
  coalesce(allocation_totals.allocated_quantity, 0) as allocated_quantity,
  greatest(
    col.requested_quantity - coalesce(allocation_totals.allocated_quantity, 0),
    0
  ) as quantity_pending_release,
  coalesce(allocation_totals.production_order_count, 0) as production_order_count
from pomgt.customer_order_lines col
left join (
  select
    poa.customer_order_line_id,
    sum(poa.allocated_quantity) as allocated_quantity,
    count(distinct poa.production_order_id) as production_order_count
  from pomgt.production_order_allocations poa
  group by poa.customer_order_line_id
) allocation_totals
  on allocation_totals.customer_order_line_id = col.id;

grant select on pomgt.v_order_line_production_status
to authenticated, service_role;

notify pgrst, 'reload schema';
