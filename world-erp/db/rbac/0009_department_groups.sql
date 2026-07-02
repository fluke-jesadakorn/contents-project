-- World ERP — Department groups backfill
-- Run after 0008_static_tile_catalog.sql.
--
-- The seed in 0003_groups_seed.sql only declared 5 dept groups
-- (Engineering / Sales / Finance / HR / Operations). Users in other
-- departments (Development, Executive, Finance & Account, Marketing,
-- IT, Human Resource) had NULL dept_group_id, so dept-scoped tile
-- access via group cascade was incomplete. This migration:
--   1. Adds the missing department groups
--   2. Re-runs the user.dept_group_id link for any unmatched rows
--   3. The trigger from 0002_groups.sql keeps this in sync going forward

BEGIN;

INSERT INTO rbac.groups (id, name, kind, sort_order, is_system) VALUES
  ('dept-development',    'Development',        'department', 150, true),
  ('dept-executive',      'Executive',          'department', 160, true),
  ('dept-finance-2',      'Finance & Account',  'department', 170, true),
  ('dept-marketing',      'Marketing',          'department', 180, true),
  ('dept-it',             'IT',                 'department', 190, true),
  ('dept-hr-2',           'Human Resource',     'department', 200, true)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

UPDATE users u SET dept_group_id = g.id
  FROM rbac.groups g
 WHERE g.kind = 'department' AND g.name = u.department
   AND (u.dept_group_id IS NULL OR u.dept_group_id <> g.id);

COMMIT;