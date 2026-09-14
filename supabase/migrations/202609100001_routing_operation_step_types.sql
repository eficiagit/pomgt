alter table if exists pomgt.routing_operations
  add column if not exists operation_type text not null default 'activity';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'routing_operations_operation_type_check'
  ) then
    alter table pomgt.routing_operations
      add constraint routing_operations_operation_type_check
      check (
        operation_type in (
          'activity',
          'material',
          'quality',
          'packaging',
          'setup',
          'external_service'
        )
      );
  end if;
end $$;

alter table if exists pomgt.routing_operations
  alter column process_definition_id drop not null,
  alter column operation_code drop not null,
  alter column currency_code set default 'MXN';
