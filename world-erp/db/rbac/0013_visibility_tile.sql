-- World ERP — Visibility Matrix tile
-- Run after 0012_domain_scope.sql.
--
-- Adds:
--   rbac.module 'rbac-visibility' : granular permission for the cross-domain
--                                  visibility matrix page (separate from
--                                  'rbac-view-matrix' which is for the role ×
--                                  module matrix in /org-chart).
--   rbac.tile  'visibility'       : Hub entry point at /visibility
--
-- Grants:
--   L4  : read + update on rbac-visibility (admins edit the matrix)
--   L2A : read only (HR may view but not edit)

BEGIN;

INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions) VALUES
  ('rbac-visibility', 'Admin · Visibility Matrix', 'Admin', 430, ARRAY['read','update']::rbac.action[])
ON CONFLICT (id) DO UPDATE SET
  display_name    = EXCLUDED.display_name,
  group_name      = EXCLUDED.group_name,
  sort_order      = EXCLUDED.sort_order,
  allowed_actions = EXCLUDED.allowed_actions;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by) VALUES
  ('L4',  'rbac-visibility', 'read',   'allow', 'seed-0013'),
  ('L4',  'rbac-visibility', 'update', 'allow', 'seed-0013'),
  ('L2A', 'rbac-visibility', 'read',   'allow', 'seed-0013')
ON CONFLICT (role_id, module_id, action) DO NOTHING;

INSERT INTO rbac.tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, module_id, request_target, sort_order) VALUES
  ('visibility', 'Visibility Matrix', 'Domains × Roles scope matrix', '🔭', 'purple', 'cockpit', NULL, '/visibility', 'rbac-visibility', 'admin', 245)
ON CONFLICT (id) DO UPDATE SET
  display_name   = EXCLUDED.display_name,
  subtitle       = EXCLUDED.subtitle,
  icon           = EXCLUDED.icon,
  accent         = EXCLUDED.accent,
  group_name     = EXCLUDED.group_name,
  href           = EXCLUDED.href,
  module_id      = EXCLUDED.module_id,
  request_target = EXCLUDED.request_target,
  sort_order     = EXCLUDED.sort_order;

INSERT INTO rbac.audit (kind, actor, target) VALUES
  ('module.create',  'seed-0013', jsonb_build_object('id', 'rbac-visibility', 'note', 'cross-domain visibility matrix permission')),
  ('cell.set',       'seed-0013', jsonb_build_object('module', 'rbac-visibility', 'note', 'L4 r/u, L2A r'))
ON CONFLICT DO NOTHING;

COMMIT;
