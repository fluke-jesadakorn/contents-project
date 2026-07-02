-- World ERP — RBAC: rbac-manage-groups module + Hub group + view-hub module
-- Run after 0006_modules_seed.sql.
--
-- Adds:
--   rbac.module 'rbac-manage-groups' : granular permission for HR to manage groups
--   rbac.module 'view-hub'           : permission gate for the Hub home page
--   rbac.group  'grp-hub'            : module-group holding view-hub, every role member
--
-- Grants:
--   L4  : full rwx on rbac-manage-groups (back-compat with requireAdmin)
--   L2A : c/r/u on rbac-manage-groups (HR can manage but not delete)
--   L1..L4 : read on grp-hub (Hub is accessible to everyone)

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Modules
-- ---------------------------------------------------------------------------

INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions) VALUES
  ('rbac-manage-groups', 'Admin · Manage Groups', 'Admin', 420, ARRAY['create','read','update','delete']::rbac.action[]),
  ('view-hub',           'Permission · View Hub', 'Perm',  525, ARRAY['read']::rbac.action[])
ON CONFLICT (id) DO UPDATE SET
  display_name    = EXCLUDED.display_name,
  group_name      = EXCLUDED.group_name,
  sort_order      = EXCLUDED.sort_order,
  allowed_actions = EXCLUDED.allowed_actions;

-- ---------------------------------------------------------------------------
-- 2. Hub group
-- ---------------------------------------------------------------------------

INSERT INTO rbac.groups (id, name, kind, sort_order, is_system) VALUES
  ('grp-hub', 'Hub', 'module-group', 50, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  kind = EXCLUDED.kind,
  sort_order = EXCLUDED.sort_order;

-- ---------------------------------------------------------------------------
-- 3. Module ↔ Group membership
-- ---------------------------------------------------------------------------

INSERT INTO rbac.module_groups (module_id, group_id) VALUES
  ('view-hub', 'grp-hub')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Role ↔ Group membership (all roles → grp-hub)
-- ---------------------------------------------------------------------------

INSERT INTO rbac.role_groups (role_id, group_id) VALUES
  ('L1',  'grp-hub'),
  ('L2A', 'grp-hub'),
  ('L2B', 'grp-hub'),
  ('L3',  'grp-hub'),
  ('L4',  'grp-hub')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 5. Group-level rwx (read on grp-hub for every role)
-- ---------------------------------------------------------------------------

INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT r, 'grp-hub', 'read'::rbac.action, 'allow', 'seed-0007'
FROM unnest(ARRAY['L1','L2A','L2B','L3','L4']) r
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6. rbac-manage-groups grants
--    L4  : full rwx (back-compat with previous requireAdmin callers)
--    L2A : c/r/u (HR can manage groups, cannot delete)
-- ---------------------------------------------------------------------------

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L4', 'rbac-manage-groups', a, 'allow', 'seed-0007'
FROM unnest(ARRAY['create','read','update','delete']::rbac.action[]) a
ON CONFLICT DO NOTHING;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', 'rbac-manage-groups', a, 'allow', 'seed-0007'
FROM unnest(ARRAY['create','read','update']::rbac.action[]) a
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 7. Audit
-- ---------------------------------------------------------------------------

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'module.create', 'seed-0007', jsonb_build_object('id', m.id, 'name', m.display_name)
FROM rbac.modules m
WHERE m.id IN ('rbac-manage-groups', 'view-hub')
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'group.create', 'seed-0007', jsonb_build_object('id', g.id, 'name', g.name, 'kind', g.kind)
FROM rbac.groups g
WHERE g.id = 'grp-hub'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'module.add_to_group', 'seed-0007', jsonb_build_object('module', mg.module_id, 'group', mg.group_id)
FROM rbac.module_groups mg
WHERE mg.group_id = 'grp-hub'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'role.add_to_group', 'seed-0007', jsonb_build_object('role', rg.role_id, 'group', rg.group_id)
FROM rbac.role_groups rg
WHERE rg.group_id = 'grp-hub'
ON CONFLICT DO NOTHING;

COMMIT;