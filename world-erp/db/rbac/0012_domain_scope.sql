-- World ERP — Per-(role, domain) scope
-- Run after 0011_domains.sql.
--
-- rbac.domain_scope overrides the role-wide rbac.roles.scope_kind on a
-- per-domain basis. This is the new source of truth for the visibility
-- matrix UI. The legacy rbac.roles.scope_kind stays as the default
-- fallback when a (role, domain) row is missing.
--
--   scope_kind ∈ { 'self' | 'department' | 'team' | 'all' | 'subtree' | 'deny' }
--
--   - 'self'      : only own rows
--   - 'department': all rows in the actor's department (users.dept_group_id)
--   - 'team'      : rows owned by users sharing one of the role's
--                   team groups (rbac.role_groups ∩ rbac.groups.kind='team')
--   - 'all'       : no scope filter
--   - 'subtree'   : same as lib/rbac/scope.ts: direct + recursive reports
--   - 'deny'      : explicit no-access (wins over inheritance)
--
-- Per-domain overrides are seeded here (per project decision: NOT mirroring
-- the role-wide scope_kind). L1 stays 'self' on every domain; L4 is
-- 'all' on every domain; L2A is 'self' for write-bearing domains and
-- 'department' for read-only ones; L2B and L3 vary per domain.
--
-- Idempotent: ON CONFLICT DO UPDATE so re-runs converge to the seed map.

BEGIN;

CREATE TABLE IF NOT EXISTS rbac.domain_scope (
  role_id     text REFERENCES rbac.roles(id)  ON DELETE CASCADE,
  domain_id   text REFERENCES rbac.domains(id) ON DELETE CASCADE,
  scope_kind  text NOT NULL
    CHECK (scope_kind IN ('self','department','team','all','subtree','deny')),
  updated_by  text NOT NULL DEFAULT 'system',
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, domain_id)
);

CREATE INDEX IF NOT EXISTS domain_scope_domain_idx ON rbac.domain_scope (domain_id);

DO $$ BEGIN
  ALTER TYPE rbac.audit_kind ADD VALUE 'domain_scope.set';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DROP TRIGGER IF EXISTS domain_scope_touch ON rbac.domain_scope;
CREATE TRIGGER domain_scope_touch BEFORE UPDATE ON rbac.domain_scope
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

INSERT INTO rbac.domain_scope (role_id, domain_id, scope_kind, updated_by) VALUES
  -- L1 (intern / guest): see nothing of substance, allow self view of their own user record only
  ('L1', 'expenses',      'self',  'seed-0012'),
  ('L1', 'pr',            'deny',  'seed-0012'),
  ('L1', 'po',            'deny',  'seed-0012'),
  ('L1', 'slips',         'self',  'seed-0012'),
  ('L1', 'users',         'self',  'seed-0012'),
  ('L1', 'departments',   'deny',  'seed-0012'),
  ('L1', 'audit',         'deny',  'seed-0012'),
  ('L1', 'ai_settings',   'deny',  'seed-0012'),
  ('L1', 'notifications', 'self',  'seed-0012'),

  -- L2A (staff / accountant / account_supervisor / hr / hr_manager):
  --   - expenses: self (write), department (review own dept's)
  --   - pr:       self (write), department (manager view)
  --   - po:       self only
  --   - slips:    self only (own receipts)
  --   - users:    self (write own profile) + read-department
  --   - departments: deny
  --   - audit:    deny
  --   - ai_settings: deny
  --   - notifications: self
  ('L2A', 'expenses',      'department', 'seed-0012'),
  ('L2A', 'pr',            'self',       'seed-0012'),
  ('L2A', 'po',            'self',       'seed-0012'),
  ('L2A', 'slips',         'self',       'seed-0012'),
  ('L2A', 'users',         'department', 'seed-0012'),
  ('L2A', 'departments',   'deny',       'seed-0012'),
  ('L2A', 'audit',         'deny',       'seed-0012'),
  ('L2A', 'ai_settings',   'deny',       'seed-0012'),
  ('L2A', 'notifications', 'self',       'seed-0012'),

  -- L2B (supervisor / account_officer):
  --   - expenses: department (supervises a team's submissions)
  --   - pr:       department (subordinate PRs)
  --   - po:       department
  --   - slips:    department
  --   - users:    subtree (their reportees + themselves)
  --   - departments: deny
  --   - audit:    deny
  --   - ai_settings: deny
  --   - notifications: self
  ('L2B', 'expenses',      'department', 'seed-0012'),
  ('L2B', 'pr',            'department', 'seed-0012'),
  ('L2B', 'po',            'department', 'seed-0012'),
  ('L2B', 'slips',         'department', 'seed-0012'),
  ('L2B', 'users',         'subtree',    'seed-0012'),
  ('L2B', 'departments',   'deny',       'seed-0012'),
  ('L2B', 'audit',         'deny',       'seed-0012'),
  ('L2B', 'ai_settings',   'deny',       'seed-0012'),
  ('L2B', 'notifications', 'self',       'seed-0012'),

  -- L3 (manager / head_of_department / accounting_manager / account_supervisor):
  --   - expenses: department (head approves dept's expenses)
  --   - pr:       department
  --   - po:       department
  --   - slips:    department
  --   - users:    subtree
  --   - departments: read all
  --   - audit:    department
  --   - ai_settings: deny
  --   - notifications: self
  ('L3', 'expenses',      'department', 'seed-0012'),
  ('L3', 'pr',            'department', 'seed-0012'),
  ('L3', 'po',            'department', 'seed-0012'),
  ('L3', 'slips',         'department', 'seed-0012'),
  ('L3', 'users',         'subtree',    'seed-0012'),
  ('L3', 'departments',   'all',        'seed-0012'),
  ('L3', 'audit',         'department', 'seed-0012'),
  ('L3', 'ai_settings',   'deny',       'seed-0012'),
  ('L3', 'notifications', 'self',       'seed-0012'),

  -- L4 (admin / it / cfo / ceo):
  --   - everything is 'all' (or 'subtree' for users, which is the same
  --     effect for top-level roles whose subtree is the whole company)
  ('L4', 'expenses',      'all', 'seed-0012'),
  ('L4', 'pr',            'all', 'seed-0012'),
  ('L4', 'po',            'all', 'seed-0012'),
  ('L4', 'slips',         'all', 'seed-0012'),
  ('L4', 'users',         'all', 'seed-0012'),
  ('L4', 'departments',   'all', 'seed-0012'),
  ('L4', 'audit',         'all', 'seed-0012'),
  ('L4', 'ai_settings',   'all', 'seed-0012'),
  ('L4', 'notifications', 'all', 'seed-0012')
ON CONFLICT (role_id, domain_id) DO UPDATE SET
  scope_kind = EXCLUDED.scope_kind,
  updated_by = EXCLUDED.updated_by;

COMMIT;
