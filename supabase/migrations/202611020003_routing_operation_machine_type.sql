-- Lets a routing step require a machine TYPE (e.g. "Embobinador") without
-- committing to one specific physical unit, independent of the optional
-- preferred_machine_id (a specific machine).

alter table if exists pomgt.routing_operations
  add column if not exists machine_type_id uuid references pomgt.machine_types(id);

notify pgrst, 'reload schema';
