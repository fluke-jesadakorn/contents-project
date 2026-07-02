-- World ERP — Domain registry for the cross-domain visibility matrix.
-- Run after 0010_seed_role_groups.sql.
--
-- A "domain" is a business surface (expenses, PR, PO, slips, users, ...).
-- Each domain groups one or more existing rbac.modules so the visibility
-- matrix can answer "who can see expenses" at a glance rather than walking
-- every tile-* row.
--
--   rbac.domains          : the registry (9 seed domains)
--   rbac.domain_modules   : M:N mapping to existing rbac.modules
--
-- The per-(role, domain) scope lives in rbac.domain_scope (0012).
--
-- Idempotent: re-runnable.

BEGIN;

CREATE TABLE IF NOT EXISTS rbac.domains (
  id           text PRIMARY KEY,
  display_name text NOT NULL,
  description  text NOT NULL DEFAULT '',
  sort_order   int  NOT NULL DEFAULT 0,
  is_system    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS domains_sort_idx ON rbac.domains (sort_order);

DROP TRIGGER IF EXISTS domains_touch ON rbac.domains;
CREATE TRIGGER domains_touch BEFORE UPDATE ON rbac.domains
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

INSERT INTO rbac.domains (id, display_name, description, sort_order) VALUES
  ('expenses',     'Expenses',             'Slip-based expense submissions, review queues and approval flow',   100),
  ('pr',           'Purchase Requisitions','PR drafting, approval, status tracking',                            110),
  ('po',           'Purchase Orders',      'PO approval, payslip settlement, GL posting',                       120),
  ('slips',        'Slip Storage',         'Receipt file library, OCR raw payloads, search',                     130),
  ('users',        'Users & Directory',    'User records, role assignment, supervisor links, line_user_id',    200),
  ('departments',  'Departments',          'Department CRUD, head assignment, monthly budgets',                 210),
  ('audit',        'Audit Log',            'rbac.audit, stage overrides, ceo_overrides, policy_audit',          300),
  ('ai_settings',  'AI Settings',          'AI providers, models, staff, section coverage',                     310),
  ('notifications','Inbox & Events',       'Per-user notification inbox, domain_events audit log',              320)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description  = EXCLUDED.description,
  sort_order   = EXCLUDED.sort_order;

CREATE TABLE IF NOT EXISTS rbac.domain_modules (
  domain_id  text REFERENCES rbac.domains(id) ON DELETE CASCADE,
  module_id  text REFERENCES rbac.modules(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (domain_id, module_id)
);

CREATE INDEX IF NOT EXISTS domain_modules_module_idx ON rbac.domain_modules (module_id);

INSERT INTO rbac.domain_modules (domain_id, module_id) VALUES
  -- expenses: submit + review + approve + the 6 expense stages
  ('expenses', 'tile-submit-expense'),
  ('expenses', 'tile-my-history'),
  ('expenses', 'tile-review-queue'),
  ('expenses', 'tile-approve-expense'),
  ('expenses', 'stage-supervisor-review'),
  ('expenses', 'stage-head-review'),
  ('expenses', 'stage-account-officer-review'),
  ('expenses', 'stage-account-supervisor-review'),
  ('expenses', 'stage-accounting-review'),
  ('expenses', 'stage-cfo-review'),
  -- pr: pr workspace tiles + head_review + po_pending
  ('pr', 'tile-my-prs'),
  ('pr', 'tile-subordinate-prs'),
  ('pr', 'tile-all-prs'),
  ('pr', 'stage-head-review'),
  ('pr', 'stage-po-pending'),
  -- po: po & payslip tile + po stages
  ('po', 'tile-po'),
  ('po', 'stage-po-pending'),
  ('po', 'stage-po-cfo'),
  -- slips: file-level tiles (search slips, ops overview)
  ('slips', 'tile-search-slips'),
  ('slips', 'tile-ops-overview'),
  -- users: directory + team manage
  ('users', 'tile-directory'),
  ('users', 'tile-team-manage'),
  ('users', 'permission-edit-user-dept'),
  ('users', 'permission-edit-user-subtree'),
  -- departments: HR dept management
  ('departments', 'tile-departments'),
  -- audit: rbac-admin, rbac-viewer, all-approvals, override-queue, access-requests
  ('audit', 'rbac-admin'),
  ('audit', 'rbac-viewer'),
  ('audit', 'tile-all-approvals'),
  ('audit', 'tile-override-queue'),
  ('audit', 'tile-access-requests'),
  -- ai_settings: AI settings tile + section coverage
  ('ai_settings', 'tile-settings'),
  -- notifications: cockpit + view-hub (homepage surfaces the bell)
  ('notifications', 'tile-cockpit'),
  ('notifications', 'view-hub')
ON CONFLICT DO NOTHING;

COMMIT;
