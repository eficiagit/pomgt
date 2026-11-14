-- Prevent two production orders from executing on the same machine. Advisory
-- transaction locks serialize simultaneous starts for the same machine.
create or replace function pomgt.assert_machine_available(
  p_machine_id uuid,
  p_order_id uuid
)
returns void
language plpgsql
set search_path = pomgt, public
as $$
declare
  occupied_machine text;
  occupied_order text;
begin
  if p_machine_id is null then
    return;
  end if;

  if not exists (
    select 1 from pomgt.production_orders o
     where o.id = p_order_id
       and pomgt.is_member(o.organization_id)
  ) then
    raise exception 'No tiene acceso a la orden de producción';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_machine_id::text));

  select coalesce(m.name, p_machine_id::text), o.op_number::text
    into occupied_machine, occupied_order
    from pomgt.production_order_operations op
    join pomgt.production_orders o on o.id = op.production_order_id
    left join pomgt.machines m on m.id = op.machine_id
   where op.machine_id = p_machine_id
     and o.id <> p_order_id
     and o.status::text in ('ready', 'in_progress')
     and (
       op.status::text = 'in_progress'
       or (
         o.status::text = 'in_progress'
         and op.id = (
           select current_op.id
             from pomgt.production_order_operations current_op
            where current_op.production_order_id = o.id
              and current_op.status::text not in ('completed', 'skipped', 'cancelled')
            order by current_op.sequence_no, current_op.id
            limit 1
         )
       )
     )
   limit 1;

  if occupied_order is not null then
    raise exception using
      errcode = 'P0001',
      message = format(
        'No se puede iniciar la ejecución: la máquina %s ya está ocupada por la orden %s. Libera esa máquina antes de continuar.',
        occupied_machine,
        occupied_order
      );
  end if;
end;
$$;

revoke all on function pomgt.assert_machine_available(uuid, uuid) from public;
grant execute on function pomgt.assert_machine_available(uuid, uuid) to authenticated;

create or replace function pomgt.enforce_operation_machine_exclusivity()
returns trigger
language plpgsql
set search_path = pomgt, public
as $$
declare
  parent_status text;
  current_operation uuid;
begin
  if new.machine_id is null then
    return new;
  end if;

  select status::text into parent_status
    from pomgt.production_orders
   where id = new.production_order_id;

  if new.status::text = 'in_progress' then
    perform pomgt.assert_machine_available(new.machine_id, new.production_order_id);
  elsif parent_status = 'in_progress'
    and new.machine_id is distinct from old.machine_id then
    select op.id into current_operation
      from pomgt.production_order_operations op
     where op.production_order_id = new.production_order_id
       and op.status::text not in ('completed', 'skipped', 'cancelled')
     order by op.sequence_no, op.id
     limit 1;
    if current_operation = new.id then
      perform pomgt.assert_machine_available(new.machine_id, new.production_order_id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists production_operation_machine_exclusivity
  on pomgt.production_order_operations;
create trigger production_operation_machine_exclusivity
  before insert or update of status, machine_id
  on pomgt.production_order_operations
  for each row
  execute function pomgt.enforce_operation_machine_exclusivity();

create or replace function pomgt.enforce_order_machine_exclusivity()
returns trigger
language plpgsql
set search_path = pomgt, public
as $$
declare
  first_machine uuid;
begin
  if new.status::text = 'in_progress'
     and old.status::text is distinct from 'in_progress' then
    select op.machine_id
      into first_machine
      from pomgt.production_order_operations op
     where op.production_order_id = new.id
       and op.status::text not in ('completed', 'skipped', 'cancelled')
       and op.machine_id is not null
     order by op.sequence_no, op.id
     limit 1;

    if first_machine is not null then
      perform pomgt.assert_machine_available(first_machine, new.id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists production_order_machine_exclusivity
  on pomgt.production_orders;
create trigger production_order_machine_exclusivity
  before update of status
  on pomgt.production_orders
  for each row
  execute function pomgt.enforce_order_machine_exclusivity();

notify pgrst, 'reload schema';
