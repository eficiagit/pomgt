create or replace view pomgt.v_production_order_workspace
with (security_invoker = true)
as
select
  po.*,
  p.sku as product_sku,
  p.name as product_name,
  u.symbol as uom_symbol,
  order_link.customer_id,
  order_link.customer_order_id,
  order_link.order_number,
  order_link.customer_po_number,
  c.trade_name as customer_trade_name,
  c.legal_name as customer_name,
  b.bom_code,
  br.revision_code as bom_revision_code,
  r.routing_code,
  rr.revision_code as routing_revision_code,
  case
    when coalesce(po.planned_quantity, 0) > 0 then
      round(
        least(
          100,
          greatest(
            0,
            coalesce(po.completed_quantity, 0) * 100 / po.planned_quantity
          )
        ),
        2
      )
    else 0
  end as progress_pct
from pomgt.production_orders po
left join pomgt.products p on p.id = po.product_id
left join pomgt.units_of_measure u on u.id = po.uom_id
left join lateral (
  select
    co.customer_id,
    co.id as customer_order_id,
    co.order_number,
    co.customer_po_number
  from pomgt.production_order_allocations poa
  join pomgt.customer_order_lines col
    on col.id = poa.customer_order_line_id
  join pomgt.customer_orders co
    on co.id = col.customer_order_id
  where poa.production_order_id = po.id
  order by poa.created_at
  limit 1
) order_link on true
left join pomgt.customers c on c.id = order_link.customer_id
left join pomgt.bom_revisions br on br.id = po.bom_revision_id
left join pomgt.boms b on b.id = br.bom_id
left join pomgt.routing_revisions rr on rr.id = po.routing_revision_id
left join pomgt.routings r on r.id = rr.routing_id;

grant select on pomgt.v_production_order_workspace to authenticated, service_role;
notify pgrst, 'reload schema';
