-- Reference-only x/y position for each machine on the new "Mapa de planta"
-- floor map (lib/features/floor_map/floor_map_screen.dart). Not a real
-- physical layout - just where the user last dragged the machine's icon.
-- Added idempotently: this project's live `machines` table already has
-- columns (status, hourly_cost, etc.) that predate its own creation
-- migration, so `if not exists` keeps this safe to re-run.
alter table pomgt.machines
  add column if not exists floor_pos_x double precision,
  add column if not exists floor_pos_y double precision;

notify pgrst, 'reload schema';
