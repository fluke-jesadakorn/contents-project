-- World ERP — RBAC: ship rbac.effective_staff_level() function.
--
-- Migration 0023 defined the function and 0024/9002 re-defined it but neither
-- was ever applied. The PersonaMenu's bucketOf() falls back to `return 5` when
-- u.staff_level is missing, which silently drops users into P5. This function
-- is the authoritative rule for which P-bucket a user belongs to:
--   user.staff_level  (1..5)  >  persona.level (1..5)  >  fallback 5
--
-- The UI continues to own the visual mapping (colors/icons/labels) — this
-- function only decides the numeric bucket. Application-level categorization
-- stays in TS (display.ts STAFF_LEVEL_BUCKETS).

BEGIN;

CREATE OR REPLACE FUNCTION rbac.effective_staff_level(
  p_user_level  smallint,
  p_role_level  smallint
) RETURNS smallint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN p_user_level BETWEEN 1 AND 5 THEN p_user_level
    WHEN p_role_level BETWEEN 1 AND 5 THEN p_role_level
    ELSE 5
  END;
$$;

COMMENT ON FUNCTION rbac.effective_staff_level(smallint, smallint) IS
  'Resolves a user''s P-bucket: user.staff_level override wins, else perm.roles.level default, else 5.';

COMMIT;