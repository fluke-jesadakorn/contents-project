-- 0025 — approval engine rebuild.
--
-- Drops the amount-bucketed approval_policies rows; extends scope_kind to
-- 'dept_tier' / 'override'; adds rbac.role_dept_assignments as the join
-- table that answers "who holds role X in dept Z"; backfills from the
-- existing user × dept bindings + dept heads; flips operational roles to
-- scope_kind='dept_tier' and CFO/CEO/admin to 'override'.

BEGIN;

DELETE FROM approval_policies;

ALTER TABLE rbac.roles DROP CONSTRAINT IF EXISTS roles_scope_kind_check;
ALTER TABLE rbac.roles ADD CONSTRAINT roles_scope_kind_check
  CHECK (scope_kind IN ('self','department','all','subtree','dept_tier','override'));

CREATE TABLE IF NOT EXISTS rbac.role_dept_assignments (
  role_id        text NOT NULL REFERENCES rbac.roles(id) ON DELETE CASCADE,
  dept_group_id  text NOT NULL REFERENCES rbac.groups(id) ON DELETE CASCADE,
  user_id        integer REFERENCES users(id) ON DELETE SET NULL,
  is_head        boolean NOT NULL DEFAULT false,
  granted_by     text NOT NULL DEFAULT 'system',
  granted_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, dept_group_id)
);
CREATE INDEX IF NOT EXISTS rbac_role_dept_assignments_user_idx
  ON rbac.role_dept_assignments (user_id) WHERE user_id IS NOT NULL;

INSERT INTO rbac.role_dept_assignments (role_id, dept_group_id, user_id, is_head)
SELECT role_id, dept_group_id, user_id, is_head FROM (
  SELECT u.rbac_role_id AS role_id, u.dept_group_id, u.id AS user_id,
         EXISTS (
           SELECT 1 FROM rbac.groups gg
           WHERE gg.head_user_id = u.id AND gg.id = u.dept_group_id
         ) AS is_head,
         ROW_NUMBER() OVER (
           PARTITION BY u.rbac_role_id, u.dept_group_id
           ORDER BY EXISTS (
             SELECT 1 FROM rbac.groups gg
             WHERE gg.head_user_id = u.id AND gg.id = u.dept_group_id
           ) DESC, u.id
         ) AS rn
    FROM users u
   WHERE u.dept_group_id IS NOT NULL
     AND u.rbac_role_id IS NOT NULL
     AND u.is_active = TRUE
) sub
WHERE rn = 1
ON CONFLICT (role_id, dept_group_id) DO UPDATE
  SET user_id = EXCLUDED.user_id,
      is_head = EXCLUDED.is_head;

UPDATE rbac.roles SET scope_kind = 'dept_tier'
  WHERE scope_kind IN ('department','subtree')
    AND id NOT IN ('cfo','ceo','admin');

UPDATE rbac.roles SET scope_kind = 'override'
  WHERE id IN ('cfo','ceo','admin');

INSERT INTO rbac.audit (kind, actor, target)
VALUES ('bulk.apply', 'system', '{"migration":"0025_approval_rebuild","note":"policies dropped, role_dept_assignments seeded"}');

COMMIT;