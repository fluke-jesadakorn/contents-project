-- World ERP — Backfill users.dept_group_id from users.department
-- Run after seed_groups.sql so the department groups exist.
-- Idempotent: only touches rows where dept_group_id is NULL but department is set.

BEGIN;

UPDATE users u
   SET dept_group_id = g.id
  FROM rbac.groups g
 WHERE g.kind = 'department'
   AND g.name = u.department
   AND u.dept_group_id IS NULL;

COMMIT;