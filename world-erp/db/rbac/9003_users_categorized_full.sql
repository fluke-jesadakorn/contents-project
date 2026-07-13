-- World ERP — add missing columns to rbac.users_categorized
-- (effective_staff_level, dept_code, dept_name, staff_level, role_level,
-- default_staff_level, role_id, role_name). The previous rebuild dropped
-- columns the view still needs to expose.

BEGIN;

DROP VIEW IF EXISTS rbac.users_categorized;

CREATE OR REPLACE VIEW rbac.users_categorized AS
SELECT u.id, u.employee_code, u.fullname, u.dept_group_id,
       dg.name AS department, dg.sort_order AS dept_sort_order,
       dg.code AS dept_code, dg.name AS dept_name,
       u.rbac_role_id AS role_id, rr.name AS role_name,
       pr.level AS role_level, rr.sort_order AS role_sort_order,
       rc.default_staff_level,
       u.staff_level,
       rbac.effective_staff_level(u.staff_level, rc.default_staff_level) AS effective_staff_level,
       u.reports_to_user_id, u.is_active, u.created_at, u.line_user_id,
       m.fullname AS manager_name, m.employee_code AS manager_code
  FROM users u
  LEFT JOIN rbac.roles       rr ON rr.id = u.rbac_role_id
  LEFT JOIN rbac.roles_compat rc ON rc.id = u.rbac_role_id
  LEFT JOIN rbac.groups      dg ON dg.id = u.dept_group_id AND dg.kind = 'department'
  LEFT JOIN users            m  ON m.id  = u.reports_to_user_id
  LEFT JOIN perm.roles       pr ON pr.id = u.rbac_role_id;

COMMIT;