do $$
begin
  if to_regclass('pomgt.customer_order_lines') is not null then
    execute 'drop trigger if exists trg_validate_customer_order_line on pomgt.customer_order_lines';
    execute 'alter table pomgt.customer_order_lines drop column if exists customer_product_id, drop column if exists product_revision_id';
  end if;

  if to_regclass('pomgt.product_categories') is not null then
    execute 'alter table pomgt.product_categories drop column if exists icon_name';
  end if;

  if to_regclass('pomgt.material_categories') is not null then
    execute 'alter table pomgt.material_categories drop column if exists icon_name';
  end if;
end;
$$;