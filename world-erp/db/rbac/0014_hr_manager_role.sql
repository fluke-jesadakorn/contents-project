-- World ERP — Promote hr_manager to a first-class RBAC role
-- Run after 0013_visibility_tile.sql.
--
-- Until now hr_manager shared the L2A tier with staff/accountant/account_supervisor/hr
-- (see migration_001_link_users.sql + 0003_groups_seed.sql). That bundle gave HR
-- Manager read-only on grp-hr and no individual column in the matrix.
--
-- This migration promotes hr_manager to its own rbac.roles row so:
--   1. The Org Chart permission matrix gets an explicit HR Manager column with
--      dedicated allow/deny cells instead of inheriting the L2A defaults.
--   2. HR Manager users get read+update on grp-hr (was read-only) so they can
--      actually use the 4 HR tiles: tile-org-chart, tile-directory,
--      tile-departments, tile-access-requests.
--   3. The org chart tree can show hr_manager as a distinct role.
--
-- The legacy mapping in migration_001_link_users.sql stays unchanged so re-runs
-- of old scripts keep working; this migration only re-points users that
-- currently point at L2A but whose roles.name is 'hr_manager'.

BEGIN;

-- 1. Register the role node (sibling of L2A under L2B at level 2).
INSERT INTO rbac.roles (id, name, parent_id, level, sort_order, is_system,
                        default_tab_id, default_staff_level, scope_kind)
VALUES
  ('hr_manager', 'HR Manager', 'L2B', 2, 65, true, 'tab-hr', 3, 'all')
ON CONFLICT (id) DO UPDATE SET
  name               = EXCLUDED.name,
  parent_id          = EXCLUDED.parent_id,
  level              = EXCLUDED.level,
  sort_order         = EXCLUDED.sort_order,
  default_tab_id     = EXCLUDED.default_tab_id,
  default_staff_level= EXCLUDED.default_staff_level,
  scope_kind         = EXCLUDED.scope_kind;

-- 2. Re-point existing HR Manager users from L2A → hr_manager.
--    Handles two scenarios:
--      a) already mapped to L2A by migration_001_link_users.sql
--      b) freshly inserted with rbac_role_id IS NULL (e.g. by add_hr.sql
--         after the link migration already ran)
UPDATE users u
   SET rbac_role_id = 'hr_manager'
  FROM roles r
 WHERE r.id = u.role_id
   AND r.name = 'hr_manager'
   AND (u.rbac_role_id = 'L2A' OR u.rbac_role_id IS NULL);

-- 3. Group cascade: grp-workflow (read+create), grp-hr (read+update),
--    grp-hub (read — every standard role gets Hub access in 0007).
--    L2A's group grants do NOT cascade to hr_manager because role_groups is
--    role-keyed, not hierarchy-walked, so we add explicit rows here.
INSERT INTO rbac.role_groups (role_id, group_id) VALUES
  ('hr_manager', 'grp-workflow'),
  ('hr_manager', 'grp-hr'),
  ('hr_manager', 'grp-hub')
ON CONFLICT DO NOTHING;

INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by) VALUES
  ('hr_manager', 'grp-workflow', 'read',   'allow', 'seed-0014'),
  ('hr_manager', 'grp-workflow', 'create', 'allow', 'seed-0014'),
  ('hr_manager', 'grp-hr',       'read',   'allow', 'seed-0014'),
  ('hr_manager', 'grp-hr',       'update', 'allow', 'seed-0014'),
  ('hr_manager', 'grp-hub',      'read',   'allow', 'seed-0014')
ON CONFLICT DO NOTHING;

-- 4. Cross-cutting permissions (mirrors what L2A already gets, so the matrix
--    shows the same shape for hr_manager).
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'hr_manager', m.id, a, 'allow', 'seed-0014'
  FROM rbac.modules m,
       unnest(ARRAY['read','update']::rbac.action[]) a
 WHERE m.id IN (
   'permission-edit-user-dept','permission-edit-user-subtree',
   'rbac-view-matrix','rbac-edit-matrix',
   'access-request-list','access-request-resolve',
   'rbac-visibility'
 )
ON CONFLICT DO NOTHING;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
VALUES ('hr_manager', 'rbac-visibility', 'read', 'allow', 'seed-0014')
ON CONFLICT DO NOTHING;

-- 5. Per-domain scope (mirrors L3 for HR-relevant domains so HR Manager can
--    actually read/write across departments).
INSERT INTO rbac.domain_scope (role_id, domain_id, scope_kind, updated_by) VALUES
  ('hr_manager', 'expenses',      'all', 'seed-0014'),
  ('hr_manager', 'pr',            'all', 'seed-0014'),
  ('hr_manager', 'po',            'all', 'seed-0014'),
  ('hr_manager', 'slips',         'all', 'seed-0014'),
  ('hr_manager', 'users',         'all', 'seed-0014'),
  ('hr_manager', 'departments',   'all', 'seed-0014'),
  ('hr_manager', 'audit',         'all', 'seed-0014'),
  ('hr_manager', 'ai_settings',   'deny','seed-0014'),
  ('hr_manager', 'notifications', 'all', 'seed-0014')
ON CONFLICT (role_id, domain_id) DO UPDATE SET
  scope_kind = EXCLUDED.scope_kind,
  updated_by = EXCLUDED.updated_by;

-- 6. Audit.
INSERT INTO rbac.audit (kind, actor, target)
SELECT 'role.create', 'seed-0014', jsonb_build_object('id', r.id, 'name', r.name)
  FROM rbac.roles r WHERE r.id = 'hr_manager'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'role.add_to_group', 'seed-0014',
       jsonb_build_object('role', rg.role_id, 'group', rg.group_id)
  FROM rbac.role_groups rg
 WHERE rg.role_id = 'hr_manager'
   AND NOT EXISTS (
     SELECT 1 FROM rbac.audit a
      WHERE a.kind = 'role.add_to_group'
        AND a.actor = 'seed-0014'
        AND a.target->>'role' = rg.role_id
        AND a.target->>'group' = rg.group_id
   );

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'cell.set', 'seed-0014',
       jsonb_build_object('role', p.role_id, 'module', p.module_id, 'action', p.action::text)
  FROM rbac.permissions p
 WHERE p.role_id = 'hr_manager'
   AND p.updated_by = 'seed-0014'
   AND NOT EXISTS (
     SELECT 1 FROM rbac.audit a
      WHERE a.kind = 'cell.set'
        AND a.actor = 'seed-0014'
        AND a.target->>'role' = p.role_id
        AND a.target->>'module' = p.module_id
        AND a.target->>'action' = p.action::text
   );

COMMIT;