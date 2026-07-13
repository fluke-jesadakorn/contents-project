-- World ERP — RBAC: unify personas.
--
-- Replaces the legacy `roles` table (users.role_id → roles.name) with
-- persona rows in rbac.roles. Each persona is a child of its old tier
-- (L1..L4) so the existing matrix continues to apply via parent_id
-- inheritance + a propagated role_groups membership.
--
-- After this migration:
--   * users.rbac_role_id stores the persona name directly
--     (e.g. 'manager', 'accountant', 'cfo').
--   * rbac.roles has rows for each persona + DEPT/HQ + L1..L4 (kept
--     as parent anchors for any module that still references them).
--   * The legacy `roles` table and `users.role_id` column are gone.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Insert persona rows as children of the existing tiers.
--    name = display label, default_staff_level + scope_kind mirror the tier.
-- ---------------------------------------------------------------------------

INSERT INTO rbac.roles (id, name, parent_id, level, sort_order, default_staff_level, scope_kind, is_system) VALUES
  ('staff',                 'Staff Requester',       'L2A', 4, 200, 5, 'self',       true),
  ('accountant',            'Accountant',            'L2A', 4, 201, 5, 'self',       true),
  ('hr',                    'HR Officer',            'L2A', 4, 202, 5, 'self',       true),
  ('account_supervisor',    'Account Supervisor',    'L2A', 4, 203, 4, 'department', true),
  ('account_officer',       'Account Officer',       'L2B', 3, 210, 5, 'department', true),
  ('supervisor',            'Supervisor',            'L2B', 3, 211, 4, 'department', true),
  ('manager',               'Manager',               'L3',  2, 220, 3, 'department', true),
  ('manager_of_department', 'Manager of Department', 'L3',  2, 221, 3, 'department', true),
  ('accounting_manager',    'Accounting Manager',    'L3',  2, 222, 3, 'department', true),
  ('admin',                 'Admin',                 'L4',  1, 230, 2, 'all',        true),
  ('cfo',                   'CFO',                   'L4',  1, 231, 2, 'all',        true),
  ('ceo',                   'CEO',                   'L4',  1, 232, 1, 'all',        true),
  ('it',                    'IT Staff',              'L4',  1, 233, 2, 'all',        true),
  ('finance',               'Finance',               'L4',  1, 234, 2, 'all',        true)
ON CONFLICT (id) DO UPDATE SET
  parent_id          = EXCLUDED.parent_id,
  level              = EXCLUDED.level,
  default_staff_level= EXCLUDED.default_staff_level,
  scope_kind         = EXCLUDED.scope_kind;

-- hr_manager already exists as its own row from the prior seed; leave it.

-- ---------------------------------------------------------------------------
-- 2. Propagate role_groups + group_permissions from parent tier → persona,
--    so the group cascade continues to resolve the same way.
-- ---------------------------------------------------------------------------

INSERT INTO rbac.role_groups (role_id, group_id)
SELECT p.id, rg.group_id
FROM rbac.roles p
JOIN rbac.roles parent ON parent.id = p.parent_id
JOIN rbac.role_groups rg ON rg.role_id = parent.id
ON CONFLICT DO NOTHING;

INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT p.id, gp.group_id, gp.action, gp.state, 'migration-0022'
FROM rbac.roles p
JOIN rbac.roles parent ON parent.id = p.parent_id
JOIN rbac.group_permissions gp ON gp.role_id = parent.id
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. Migrate users.rbac_role_id from tier → persona.
--    Users that still hold a tier (e.g. NULL legacy mapping) keep the tier
--    so we don't lose data; the cleanup below removes legacy `roles`.
-- ---------------------------------------------------------------------------

UPDATE users u
SET rbac_role_id = CASE r.name
  WHEN 'staff'                 THEN 'staff'
  WHEN 'accountant'            THEN 'accountant'
  WHEN 'hr'                    THEN 'hr'
  WHEN 'account_supervisor'    THEN 'account_supervisor'
  WHEN 'account_officer'       THEN 'account_officer'
  WHEN 'supervisor'            THEN 'supervisor'
  WHEN 'manager'               THEN 'manager'
  WHEN 'manager_of_department' THEN 'manager_of_department'
  WHEN 'accounting_manager'    THEN 'accounting_manager'
  WHEN 'admin'                 THEN 'admin'
  WHEN 'cfo'                   THEN 'cfo'
  WHEN 'ceo'                   THEN 'ceo'
  WHEN 'it'                    THEN 'it'
  WHEN 'finance'               THEN 'finance'
  WHEN 'hr_manager'            THEN 'hr_manager'
END
FROM roles r
WHERE u.role_id = r.id;

-- ---------------------------------------------------------------------------
-- 4. Drop the legacy FK + column, then the legacy table.
-- ---------------------------------------------------------------------------

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_id_fkey;
ALTER TABLE users DROP COLUMN IF EXISTS role_id;
DROP TABLE IF EXISTS roles CASCADE;

COMMIT;