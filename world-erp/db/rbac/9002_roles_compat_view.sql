-- World ERP — backward-compat shim for the dropped rbac.roles columns.
-- Many legacy code paths (lib/rbac/scope.ts, lib/rbac/chain.ts, lib/rbac/userSort.ts,
-- app/actions.ts, app/api/users/*) used to read default_staff_level and scope_kind
-- from rbac.roles. Those columns are gone; the new sources are:
--   default_staff_level  -> perm.roles.level  (HR-editable on each role)
--   scope_kind           -> rbac.domain_scope.scope_kind  (per-(role,domain) override)
--                            falls back to a hardcoded default derived from role level:
--                              level <= 2 -> 'override' (CEO/CFO/admin)
--                              level 3-5  -> 'department'
--                              else       -> 'self'
-- This view lets existing code keep doing `SELECT default_staff_level FROM rbac.roles`
-- while the migration to perm.roles happens file-by-file.

BEGIN;

CREATE OR REPLACE VIEW rbac.roles_compat AS
SELECT
  r.id,
  r.name,
  r.sort_order,
  r.is_system,
  r.default_tab_id,
  COALESCE(pr.level, 5)::smallint                                  AS default_staff_level,
  CASE
    WHEN pr.level IS NULL THEN 'self'::text
    WHEN pr.level <= 2   THEN 'override'::text
    WHEN pr.level <= 5   THEN 'department'::text
    ELSE                      'self'::text
  END                                                              AS scope_kind,
  pr.level                                                         AS perm_level
FROM rbac.roles r
LEFT JOIN perm.roles pr ON pr.id = r.id;

-- Replace rbac.effective_staff_level with a perm-aware version.
-- 1 = highest authority (mirrors the new model); was 1 = highest before too.
CREATE OR REPLACE FUNCTION rbac.effective_staff_level(
  p_user_level smallint,
  p_role_level smallint
) RETURNS smallint LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN p_user_level BETWEEN 1 AND 10 THEN p_user_level
    WHEN p_role_level BETWEEN 1 AND 10 THEN p_role_level
    ELSE 5
  END;
$$;

COMMIT;