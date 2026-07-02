-- World ERP — Hook (webhook receiver) RBAC + tile
-- Run after 0008_static_tile_catalog.sql.
--
-- Adds:
--   view-hook-events   (read-only access to /hook tile)
--   manage-hook-events (CRUD — replay / delete hook events)
-- Plus the `hook` tile at /hook routed through the generic [slug] workbench.

BEGIN;

INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions) VALUES
  ('view-hook-events',   'Hook · View Events',   'it',  600, ARRAY['read']::rbac.action[]),
  ('manage-hook-events', 'Hook · Manage Events', 'it',  610, ARRAY['create','read','update','delete']::rbac.action[])
ON CONFLICT (id) DO UPDATE SET
  display_name    = EXCLUDED.display_name,
  group_name      = EXCLUDED.group_name,
  sort_order      = EXCLUDED.sort_order,
  allowed_actions = EXCLUDED.allowed_actions;

INSERT INTO rbac.tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, module_id, request_target, sort_order) VALUES
  ('hook', 'Hook Events', 'Inbound webhooks (LINE, generic). Inspect, replay.', '📨', 'cyan', 'it', NULL, '/hook', 'view-hook-events', 'admin', 340)
ON CONFLICT (id) DO UPDATE SET
  display_name   = EXCLUDED.display_name,
  subtitle       = EXCLUDED.subtitle,
  icon           = EXCLUDED.icon,
  accent         = EXCLUDED.accent,
  group_name     = EXCLUDED.group_name,
  sub_view       = EXCLUDED.sub_view,
  href           = EXCLUDED.href,
  module_id      = EXCLUDED.module_id,
  request_target = EXCLUDED.request_target,
  sort_order     = EXCLUDED.sort_order;

DELETE FROM rbac.permissions WHERE module_id IN ('view-hook-events','manage-hook-events') AND updated_by = 'seed-0015';

-- L4 (admin / it) — full CRUD on manage, read on view
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L4', m.id, a, 'allow', 'seed-0015'
FROM rbac.modules m,
     unnest(ARRAY['create','read','update','delete']::rbac.action[]) a
WHERE m.id = 'manage-hook-events'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L4', m.id, a, 'allow', 'seed-0015'
FROM rbac.modules m,
     unnest(ARRAY['read']::rbac.action[]) a
WHERE m.id = 'view-hook-events'
ON CONFLICT DO NOTHING;

-- L2A (staff / hr / accounting) — read-only on view-hook-events
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, 'read', 'allow', 'seed-0015'
FROM rbac.modules m
WHERE m.id = 'view-hook-events'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'module.create', 'seed-0015', jsonb_build_object('id', m.id, 'name', m.display_name)
FROM rbac.modules m
WHERE m.id IN ('view-hook-events','manage-hook-events')
ON CONFLICT DO NOTHING;

COMMIT;