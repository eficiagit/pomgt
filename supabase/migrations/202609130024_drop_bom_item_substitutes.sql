-- "Sustitutos" (alternate materials per BOM component) has been removed from
-- the app: it never made sense as a separate concept, so drop the table.
-- Nothing else references bom_item_substitutes as a parent, so this is safe.
drop table if exists pomgt.bom_item_substitutes;

notify pgrst, 'reload schema';
