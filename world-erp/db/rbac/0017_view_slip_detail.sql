-- World ERP — Slip detail page RBAC
-- Run after 0011_domains.sql.
--
-- Adds:
--   view-slip-detail (read access to /slip/<id> detail page)
-- Maps to the existing `slips` domain so the visibility matrix treats the
-- detail page the same as the search-slips and ops-overview tiles.

BEGIN;

INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions) VALUES
  ('view-slip-detail', 'Slip · View Detail', 'workflow', 145, ARRAY['read']::rbac.action[])
ON CONFLICT (id) DO UPDATE SET
  display_name    = EXCLUDED.display_name,
  group_name      = EXCLUDED.group_name,
  sort_order      = EXCLUDED.sort_order,
  allowed_actions = EXCLUDED.allowed_actions;

INSERT INTO rbac.domain_modules (domain_id, module_id) VALUES
  ('slips', 'view-slip-detail')
ON CONFLICT DO NOTHING;

DELETE FROM rbac.permissions WHERE module_id = 'view-slip-detail' AND updated_by = 'seed-0017';

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT r.id, 'view-slip-detail', 'read', 'allow', 'seed-0017'
FROM rbac.roles r
WHERE r.id IN ('L1','L2A','L2B','L3','L4','hr_manager')
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'module.create', 'seed-0017', jsonb_build_object('id', m.id, 'name', m.display_name)
FROM rbac.modules m
WHERE m.id = 'view-slip-detail'
ON CONFLICT DO NOTHING;

COMMIT;