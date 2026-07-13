-- World ERP — RBAC: user categorization primitives.
--
-- Single source of truth for the values that drive the PersonaMenu /
-- UserDirectoryView buckets:
--   * effective_staff_level = COALESCE(user override, role default, 5)
--   * pre-sorted VIEW that every API + SSR caller SELECTs from
--
-- No triggers: creation stays explicit at the API layer, but the
-- canonical sort/category expressions live here.

BEGIN;

CREATE OR REPLACE FUNCTION rbac.effective_staff_level(
  p_user_level    smallint,
  p_role_default  smallint
) RETURNS smallint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN p_user_level   BETWEEN 1 AND 5 THEN p_user_level
    WHEN p_role_default BETWEEN 1 AND 5 THEN p_role_default
    ELSE 5
  END;
$$;

CREATE OR REPLACE VIEW rbac.users_categorized AS
SELECT
  u.id,
  u.employee_code,
  u.fullname,
  u.dept_group_id,
  dg.name        AS department,
  dg.sort_order  AS dept_sort_order,
  u.rbac_role_id AS role_id,
  rr.name        AS role_name,
  rr.level       AS role_level,
  rr.sort_order  AS role_sort_order,
  rr.default_staff_level,
  u.staff_level,
  rbac.effective_staff_level(u.staff_level, rr.default_staff_level)
                 AS effective_staff_level,
  u.reports_to_user_id,
  u.is_active,
  u.created_at,
  u.line_user_id,
  m.fullname      AS manager_name,
  m.employee_code AS manager_code
FROM users u
LEFT JOIN rbac.roles  rr ON rr.id = u.rbac_role_id
LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id AND dg.kind = 'department'
LEFT JOIN users       m  ON m.id  = u.reports_to_user_id;

COMMENT ON VIEW rbac.users_categorized IS
  'Pre-categorized user rows. Use this in any listing that buckets by P1..P5 or sorts by hierarchy. Canonical ORDER BY: effective_staff_level ASC, role_sort_order ASC, dept_sort_order ASC, fullname ASC.';

COMMIT;
