-- World ERP — Drop users.department (legacy free-text column)
-- Run after 0017_view_slip_detail.sql.
--
-- users.department was the original source-of-truth string for the dept name.
-- rbac.groups WHERE kind='department' is now the only canonical source.
-- users.dept_group_id (FK to rbac.groups) is what every read path joins against.
--
-- Steps:
--   1. Backfill dept_group_id for any user whose legacy string still has a match
--      in rbac.groups (covers seed data + future inserts that didn't go through
--      the sync triggers any more).
--   2. Drop the two sync triggers installed by 0002_groups.sql that read
--      users.department.
--   3. Drop the trigger functions.
--   4. Drop the column itself.

BEGIN;

-- 1. Backfill any stragglers (no-op if users already have dept_group_id set).
UPDATE users u
   SET dept_group_id = g.id
  FROM rbac.groups g
 WHERE g.kind = 'department'
   AND g.name = u.department
   AND u.dept_group_id IS NULL;

-- 2. Drop sync triggers (no longer needed once users.department is gone).
DROP TRIGGER IF EXISTS users_dept_sync     ON users;
DROP TRIGGER IF EXISTS users_dept_sync_ins ON users;

-- 3. Drop the trigger functions that referenced the legacy column.
DROP FUNCTION IF EXISTS rbac.sync_user_dept_group();
DROP FUNCTION IF EXISTS rbac.init_user_dept_group();

-- 4. Drop the column.
ALTER TABLE users DROP COLUMN IF EXISTS department;

COMMIT;