-- World ERP — Role ↔ group memberships baseline
-- Run after 0009_department_groups.sql.
--
-- 0003_groups_seed.sql already binds each rbac.roles row to its module-group
-- ancestors (L4 → all groups, L3 → approval/procurement/finance/hr, etc.).
-- This migration adds the missing department-group side of the cascade so
-- dept-scoped tiles (rbac.tiles.owner_group_id) resolve without per-row
-- configuration.
--
--   * L4 (admin/it/cfo/ceo) → every department group: cross-dept visibility.
--   * L3 (head_of_department / accounting_manager / account_supervisor) →
--     every department group: managers can review across depts at the
--     approval stage, then narrow via scope_kind='department' at row level.
--   * L2A/L2B (staff/supervisor/accountant) → no dept-group grants here:
--     their scope is driven by users.dept_group_id via scope.ts, not via
--     group cascade.
--
-- Idempotent: ON CONFLICT DO NOTHING everywhere.

BEGIN;

-- L4 (admin, it, cfo, ceo) → every department group
INSERT INTO rbac.role_groups (role_id, group_id)
SELECT r.id, g.id
  FROM rbac.roles r
  JOIN rbac.groups g ON g.kind = 'department'
 WHERE r.id IN ('L4')
ON CONFLICT DO NOTHING;

-- L3 (manager / head_of_department / accounting_manager / account_supervisor)
INSERT INTO rbac.role_groups (role_id, group_id)
SELECT r.id, g.id
  FROM rbac.roles r
  JOIN rbac.groups g ON g.kind = 'department'
 WHERE r.id IN ('L3')
ON CONFLICT DO NOTHING;

-- Group-level rwx: read access for L4 / L3 across all departments
INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT r.id, g.id, a, 'allow', 'seed'
  FROM rbac.roles r
  JOIN rbac.groups g ON g.kind = 'department'
 CROSS JOIN unnest(ARRAY['read','update']::rbac.action[]) a
 WHERE r.id IN ('L4','L3')
ON CONFLICT DO NOTHING;

-- Audit one row per new membership for history
INSERT INTO rbac.audit (kind, actor, target)
SELECT 'role.add_to_group', 'seed-0010', jsonb_build_object('role', rg.role_id, 'group', rg.group_id)
  FROM rbac.role_groups rg
 WHERE NOT EXISTS (
   SELECT 1 FROM rbac.audit a
   WHERE a.kind = 'role.add_to_group'
     AND a.actor = 'seed-0010'
     AND a.target->>'role' = rg.role_id
     AND a.target->>'group' = rg.group_id
 );

COMMIT;