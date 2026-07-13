-- World ERP — drop redundant role-hierarchy columns from rbac.roles.
-- The new model is flat: roles are a flat list of perm packs.
-- Hierarchy is encoded by perm.roles.level (1 = highest, 10 = lowest).
-- We keep the rbac.roles table itself for backward-compat reads
-- (many legacy queries still reference it) but the hierarchy columns go away.

BEGIN;

ALTER TABLE rbac.roles DROP CONSTRAINT IF EXISTS roles_level_check;

-- rbac.tile_access_meta VIEW depended on parent_id; cascade drops it too.
-- The view is unused by the new perm.* model (tile visibility uses
-- rbac.tiles.required_permission + session.permissions).
DROP VIEW IF EXISTS rbac.tile_access_meta CASCADE;

-- rbac.users_categorized depends on rbac.roles.level and
-- rbac.effective_staff_level(). Redefine without those columns.
DROP VIEW IF EXISTS rbac.users_categorized;
DROP FUNCTION IF EXISTS rbac.effective_staff_level(smallint, smallint);

CREATE OR REPLACE VIEW rbac.users_categorized AS
SELECT u.id, u.employee_code, u.fullname, u.dept_group_id,
       dg.name AS department, dg.sort_order AS dept_sort_order,
       u.rbac_role_id AS role_id, rr.name AS role_name,
       rr.sort_order AS role_sort_order,
       u.reports_to_user_id, u.is_active, u.created_at, u.line_user_id,
       m.fullname AS manager_name, m.employee_code AS manager_code,
       pr.level AS role_level
  FROM users u
  LEFT JOIN rbac.roles  rr ON rr.id = u.rbac_role_id
  LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id AND dg.kind = 'department'
  LEFT JOIN users       m  ON m.id  = u.reports_to_user_id
  LEFT JOIN perm.roles  pr ON pr.id = u.rbac_role_id;

ALTER TABLE rbac.roles
  DROP COLUMN IF EXISTS parent_id,
  DROP COLUMN IF EXISTS level,
  DROP COLUMN IF EXISTS default_staff_level,
  DROP COLUMN IF EXISTS scope_kind;

DROP INDEX IF EXISTS roles_parent_idx;
DROP INDEX IF EXISTS roles_scope_idx;

COMMIT;