-- World ERP — Fold the `departments` table into rbac.groups
-- Run after 0018_drop_users_department.sql.
--
-- The legacy `departments` table carried three pieces of metadata that
-- rbac.groups didn't have: code (DEV/ENG/...), head_user_id, monthly_budget.
-- Those columns now live on rbac.groups WHERE kind='department', and the
-- `departments` table is dropped entirely.
--
-- Steps:
--   1. Extend rbac.groups with code / head_user_id / monthly_budget.
--   2. Backfill from `departments` (matched by name).
--   3. Replace purchase_requisitions.department_id with dept_group_id.
--   4. Drop users.department_id.
--   5. Drop the `departments` table.

BEGIN;

-- 1. Extend rbac.groups.
ALTER TABLE rbac.groups
  ADD COLUMN IF NOT EXISTS code           VARCHAR(20),
  ADD COLUMN IF NOT EXISTS head_user_id   INT REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS monthly_budget DECIMAL(14, 2) NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS groups_code_unique
  ON rbac.groups (code) WHERE code IS NOT NULL;

-- 2. Backfill from the legacy departments table.
UPDATE rbac.groups g
   SET code           = d.code,
       head_user_id   = d.head_user_id,
       monthly_budget = d.monthly_budget
  FROM departments d
 WHERE g.kind = 'department'
   AND g.name = d.name
   AND (g.code IS NULL OR g.code <> d.code OR g.head_user_id IS DISTINCT FROM d.head_user_id);

-- 3. purchase_requisitions: rename department_id → dept_group_id.
ALTER TABLE purchase_requisitions
  ADD COLUMN IF NOT EXISTS dept_group_id text REFERENCES rbac.groups(id) ON DELETE SET NULL;

UPDATE purchase_requisitions pr
   SET dept_group_id = g.id
  FROM departments d
  JOIN rbac.groups g ON g.kind = 'department' AND g.name = d.name
 WHERE pr.department_id = d.id
   AND pr.dept_group_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_pr_dept_group ON purchase_requisitions(dept_group_id);

ALTER TABLE purchase_requisitions DROP CONSTRAINT IF EXISTS purchase_requisitions_department_id_fkey;
ALTER TABLE purchase_requisitions DROP COLUMN IF EXISTS department_id;

-- 4. users.department_id → no replacement; users.dept_group_id is the FK.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_department_id_fkey;
ALTER TABLE users DROP COLUMN IF EXISTS department_id;

-- 5. Drop the departments table.
DROP TABLE IF EXISTS departments CASCADE;

COMMIT;