-- Reportes / BI: OEE y costo real vs estándar.
--
-- A read-only view, not new tables — it rolls up data the app already
-- captures (production_orders timing, production_order_quality_checks,
-- production_order_costs) instead of asking operators to log anything new.
--
-- OEE here is a pragmatic per-order approximation, not the textbook
-- work-center-level OEE (which needs dedicated downtime/scrap logging this
-- app doesn't capture yet):
--   Availability = planned duration / actual duration (capped to 100%)
--   Performance  = completed_quantity / planned_quantity (capped to 100%)
--   Quality      = share of required quality checks that passed
--   OEE          = Availability × Performance × Quality
-- Any factor is null (and OEE is left null) when the order doesn't yet have
-- the data that factor needs — e.g. no actual_start_at/actual_end_at yet.

create or replace view pomgt.v_report_production_performance
with (security_invoker = true)
as
select
  po.id as production_order_id,
  po.organization_id,
  po.op_number,
  po.status,
  po.product_id,
  p.sku as product_sku,
  p.name as product_name,
  po.planned_quantity,
  po.completed_quantity,
  po.planned_start_at,
  po.planned_end_at,
  po.actual_start_at,
  po.actual_end_at,
  case
    when po.planned_start_at is not null and po.planned_end_at is not null
      and po.actual_start_at is not null and po.actual_end_at is not null
      and extract(epoch from (po.actual_end_at - po.actual_start_at)) > 0
    then least(
      1,
      greatest(
        0,
        extract(epoch from (po.planned_end_at - po.planned_start_at))
          / extract(epoch from (po.actual_end_at - po.actual_start_at))
      )
    )
    else null
  end as availability_ratio,
  case
    when coalesce(po.planned_quantity, 0) > 0
    then least(1, greatest(0, coalesce(po.completed_quantity, 0) / po.planned_quantity))
    else null
  end as performance_ratio,
  qc.quality_ratio,
  coalesce(costs.estimated_total, 0) as estimated_cost_total,
  coalesce(costs.actual_total, 0) as actual_cost_total,
  case
    when coalesce(costs.estimated_total, 0) > 0
    then round((costs.actual_total - costs.estimated_total) / costs.estimated_total * 100, 2)
    else null
  end as cost_variance_pct,
  case
    when po.planned_start_at is not null and po.planned_end_at is not null
      and po.actual_start_at is not null and po.actual_end_at is not null
      and extract(epoch from (po.actual_end_at - po.actual_start_at)) > 0
      and coalesce(po.planned_quantity, 0) > 0
      and qc.quality_ratio is not null
    then round(
      least(
        1,
        greatest(
          0,
          extract(epoch from (po.planned_end_at - po.planned_start_at))
            / extract(epoch from (po.actual_end_at - po.actual_start_at))
        )
      )
      * least(1, greatest(0, coalesce(po.completed_quantity, 0) / po.planned_quantity))
      * qc.quality_ratio
      * 100,
      2
    )
    else null
  end as oee_pct
from pomgt.production_orders po
left join pomgt.products p on p.id = po.product_id
left join lateral (
  select
    case
      when count(*) filter (where is_required) = 0 then null
      else (count(*) filter (where is_required and result_status = 'passed'))::numeric
           / nullif(count(*) filter (where is_required), 0)
    end as quality_ratio
  from pomgt.production_order_quality_checks
  where production_order_id = po.id
) qc on true
left join lateral (
  select
    coalesce(sum(
      coalesce(estimated_material, 0) + coalesce(estimated_labor, 0) + coalesce(estimated_machine, 0)
      + coalesce(estimated_subcontract, 0) + coalesce(estimated_overhead, 0)
    ), 0) as estimated_total,
    coalesce(sum(
      coalesce(actual_material, 0) + coalesce(actual_labor, 0) + coalesce(actual_machine, 0)
      + coalesce(actual_subcontract, 0) + coalesce(actual_overhead, 0)
    ), 0) as actual_total
  from pomgt.production_order_costs
  where production_order_id = po.id
) costs on true;

grant select on pomgt.v_report_production_performance to authenticated, service_role;

notify pgrst, 'reload schema';
