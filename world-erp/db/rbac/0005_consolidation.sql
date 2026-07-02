-- World ERP — RBAC consolidation
-- Adds per-role metadata so the new RBAC system can absorb all the
-- persona, tab, action, scope, and staff-level data that used to live
-- in lib/permissions.ts (TypeScript).
--
--   default_tab_id      : which tab-* module to open on first login
--   default_staff_level : 1..5 fallback when users.staff_level is null
--   scope_kind          : 'self' | 'department' | 'all' | 'subtree'
--
-- All three columns are nullable for backward compatibility; the
-- consolidation seed (0006) fills them in.

BEGIN;

ALTER TABLE rbac.roles
  ADD COLUMN IF NOT EXISTS default_tab_id     text REFERENCES rbac.modules(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS default_staff_level smallint
    CHECK (default_staff_level BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS scope_kind         text NOT NULL DEFAULT 'self'
    CHECK (scope_kind IN ('self','department','all','subtree'));

CREATE INDEX IF NOT EXISTS roles_scope_idx ON rbac.roles (scope_kind);

COMMIT;
