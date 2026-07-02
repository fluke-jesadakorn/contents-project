-- World ERP — Cross-Slice Summary tile
-- Run after 0008_static_tile_catalog.sql.
--
-- Adds a read-only tile at /summary that surfaces per-feature / per-department /
-- per-RBAC-group / per-persona activity counts in a single view. No mutation.
-- Intended as the YouTube-series "show me everything at once" tile.

BEGIN;

INSERT INTO rbac.modules (id, display_name, group_name, sort_order) VALUES
  ('tile-summary', 'Cross-Slice Summary', 'cockpit', 245)
ON CONFLICT (id) DO NOTHING;

INSERT INTO rbac.tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, module_id, request_target, sort_order) VALUES
  ('summary', 'Cross-Slice Summary', 'Activity across features, departments, groups, personas', '📊', 'purple', 'cockpit', 'summary', '/summary', 'tile-summary', 'cfo', 245)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  subtitle = EXCLUDED.subtitle,
  icon = EXCLUDED.icon,
  accent = EXCLUDED.accent,
  group_name = EXCLUDED.group_name,
  sub_view = EXCLUDED.sub_view,
  href = EXCLUDED.href,
  module_id = EXCLUDED.module_id,
  request_target = EXCLUDED.request_target,
  sort_order = EXCLUDED.sort_order;

-- Grant read access to cfo + admin via direct role permissions
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by) VALUES
  ('L4', 'tile-summary', 'read', 'allow', 'youtube-cull')
ON CONFLICT (role_id, module_id, action) DO UPDATE SET state = EXCLUDED.state, updated_by = EXCLUDED.updated_by;

COMMIT;