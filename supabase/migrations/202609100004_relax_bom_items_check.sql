alter table if exists pomgt.bom_items
  drop constraint if exists bom_items_check;

alter table if exists pomgt.bom_items
  add constraint bom_items_check
  check (
    (component_type = 'subassembly' or child_bom_revision_id is null)
    and (quantity is null or quantity > 0)
    and (scrap_pct is null or scrap_pct >= 0)
    and (expected_yield_pct is null or expected_yield_pct > 0)
  );
