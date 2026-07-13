-- World ERP — every tile gets a required_permission (tile:<slug>:view).
-- Tile visibility: a tile is visible to the actor iff
--   session.permissions.includes(tile.required_permission)
-- Tile rows are seeded in db/rbac/0008_static_tile_catalog.sql;
-- this migration adds the column and backfills from the tile id.

BEGIN;

ALTER TABLE rbac.tiles
  ADD COLUMN IF NOT EXISTS required_permission text;

CREATE INDEX IF NOT EXISTS rbac_tiles_required_perm_idx
  ON rbac.tiles (required_permission);

-- Backfill: tile id "approve-expense" -> "tile:approve_expense:view"
-- Falls back to current module_id (which is already "tile-<slug>" for most).
UPDATE rbac.tiles
   SET required_permission = 'tile:' || replace(id, '-', '_') || ':view'
 WHERE required_permission IS NULL;

-- Fix known mismatches (tiles whose id doesn't match an existing perm).
UPDATE rbac.tiles SET required_permission = 'tile:org_chart:view' WHERE id = 'permissions';
UPDATE rbac.tiles SET required_permission = 'tile:hook_view:view'  WHERE id IN ('hook', 'hook-inbox');

-- Anything still NULL gets a generic perm (admin can edit later).
UPDATE rbac.tiles
   SET required_permission = 'tile:' || replace(id, '-', '_') || ':view'
 WHERE required_permission IS NULL;

COMMIT;