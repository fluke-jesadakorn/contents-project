-- World ERP — Static tile catalog
-- Run after 0007_groups_and_hub.sql.
--
-- Replaces the hard-coded UNIVERSAL_TILES array in web-admin/src/components/tile-config.ts.
-- The 25 tiles become rows in rbac.tiles; RBAC alone decides who can access each tile.
-- "Department" in the UI is the display name of the user's dept group
-- (users.dept_group_id → rbac.groups where kind='department'); no string columns
-- are read at access-check time.

BEGIN;

CREATE TABLE IF NOT EXISTS rbac.tiles (
  id              text PRIMARY KEY,                                       -- canonical slug, e.g. 'submit-expense'
  display_name    text NOT NULL,
  subtitle        text NOT NULL DEFAULT '',
  icon            text NOT NULL DEFAULT '🧾',
  accent          text NOT NULL DEFAULT 'slate',
  group_name      text NOT NULL,                                          -- display grouping (workflow / hr / ...)
  sub_view        text,
  href            text NOT NULL,                                          -- /<slug>
  module_id       text NOT NULL REFERENCES rbac.modules(id) ON DELETE CASCADE,
  request_target  text,                                                  -- 'hr_manager' | 'cfo' | 'admin'
  sort_order      int NOT NULL DEFAULT 0,
  is_system       boolean NOT NULL DEFAULT true,
  owner_group_id  text REFERENCES rbac.groups(id) ON DELETE SET NULL,    -- Unix-style owner (optional)
  default_perm    rbac.cell_state NOT NULL DEFAULT 'deny',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tiles_group_idx  ON rbac.tiles (group_name);
CREATE INDEX IF NOT EXISTS tiles_sort_idx   ON rbac.tiles (sort_order);
CREATE INDEX IF NOT EXISTS tiles_module_idx ON rbac.tiles (module_id);

DROP TRIGGER IF EXISTS tiles_touch ON rbac.tiles;
CREATE TRIGGER tiles_touch BEFORE UPDATE ON rbac.tiles
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

INSERT INTO rbac.tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, module_id, request_target, sort_order) VALUES
  ('submit-expense',    'Submit Slip',           'AI auto-extracts amount',     '🧾', 'emerald', 'workflow',              'submit',     '/submit-expense',    'tile-submit-expense',    'hr_manager', 100),
  ('my-history',        'My Submissions',        'Track and edit your expenses','📋', 'emerald', 'workflow',              'history',    '/my-history',        'tile-my-history',        'hr_manager', 110),
  ('my-prs',            'My PRs',                'Purchase requests you submitted','🛒','emerald','workflow-procurement',  NULL,         '/my-prs',            'tile-my-prs',            'hr_manager', 120),
  ('review-queue',      'Review Queue',          'AI-suggested COA',            '📑', 'indigo',  'workflow-approval',     'queue',      '/review-queue',      'tile-review-queue',      'hr_manager', 130),
  ('approve-expense',   'Expense Approval',      'Your current approval stage', '✅', 'cyan',    'workflow-approval',     'approve',    '/approve-expense',   'tile-approve-expense',   'hr_manager', 140),
  ('subordinate-prs',   'Pending Approvals',     'PRs awaiting your decision',  '🛒', 'amber',   'workflow-procurement',  NULL,         '/subordinate-prs',   'tile-subordinate-prs',   'hr_manager', 150),
  ('all-prs',           'All PRs',               'Read-only PR list',           '🛒', 'slate',   'workflow-procurement',  NULL,         '/all-prs',           'tile-all-prs',           'admin',      160),
  ('search-coa',        'Search COA',            'BGE-M3 semantic',             '🔍', 'indigo',  'workflow',              'coa-search', '/search-coa',        'tile-search-coa',        'hr_manager', 170),
  ('search-slips',      'Search Slips',          'Find receipts',               '🔎', 'indigo',  'workflow',              'slip-search','/search-slips',      'tile-search-slips',      'hr_manager', 180),
  ('reconciliation',    'Reconciliation',        'Check balances',              '📊', 'cyan',    'finance',               'recon',      '/reconciliation',    'tile-reconciliation',    'hr_manager', 190),
  ('team-manage',       'Team Management',       'Change subordinate permissions','👥','amber',  'workflow',              'team-manage','/team-manage',       'tile-team-manage',       'hr_manager', 200),
  ('ops-overview',      'Operations',            'All expenses',                '🏢', 'indigo',  'it',                    'ops',        '/ops-overview',      'tile-ops-overview',      'admin',      210),
  ('override-queue',    'Approval Override',     'Force approve / reject',      '⚡', 'rose',    'cockpit',               'override',   '/override-queue',    'tile-override-queue',    'admin',      220),
  ('all-approvals',     'All Approvals',         'In-flight status',            '🛡️', 'rose',    'cockpit',               'all',        '/all-approvals',     'tile-all-approvals',     'admin',      230),
  ('cockpit',           'Executive Cockpit',     'Cash · Income · Flow',        '👑', 'purple',  'cockpit',               'main',       '/cockpit',           'tile-cockpit',           'cfo',        240),
  ('ledger',            'General Ledger',        'Posted journals',             '📒', 'indigo',  'finance',               NULL,         '/ledger',            'tile-ledger',            'hr_manager', 250),
  ('po',                'PO & Payslip',          'Approve PO + attach slip',    '📎', 'cyan',    'finance',               NULL,         '/po',                'tile-po',                'hr_manager', 260),
  ('policy',            'Approval Policy',       'Edit policy rules',           '📜', 'amber',   'policy',                NULL,         '/policy',            'tile-policy',            'hr_manager', 270),
  ('settings',          'AI Settings',           'Manage AI providers',         '⚙️', 'slate',   'it',                    NULL,         '/settings',          'tile-settings',          'admin',      280),
  ('org-chart',         'Org Chart',             'Organization structure',      '🌳', 'cyan',    'hr',                    'org-chart',  '/org-chart',         'tile-org-chart',         'hr_manager', 290),
  ('permissions',       'Permissions',           'Role × Module matrix',        '🧮', 'cyan',    'hr',                    'permissions','/permissions',       'tile-org-chart',         'admin',      295),
  ('directory',         'User Directory',        'Search & manage users',       '📇', 'cyan',    'hr',                    'directory',  '/directory',         'tile-directory',         'hr_manager', 300),
  ('departments',       'Departments',           'Change department head',      '🏢', 'cyan',    'hr',                    'departments','/departments',       'tile-departments',       'hr_manager', 310),
  ('access-requests',   'Access Requests',       'Review tile-unlock requests', '✉',  'cyan',    'hr',                    'access-requests','/access-requests','tile-access-requests',  'hr_manager', 320),
  ('workbench',         'Read-Only View',        'All submissions',             '🧰', 'slate',   'it',                    NULL,         '/workbench',         'tile-workbench',         'admin',      330),
  ('hook-inbox',        'Hook Inbox',            'Replay inbound webhooks',     '🪝', 'slate',   'it',                    NULL,         '/hook-inbox',        'hook-replay',            'admin',      340),
  ('hub',               'Hub',                   'All accessible tiles',        '🗂️', 'indigo',  'hub',                   NULL,         '/',                  'view-hub',                NULL,         50)
ON CONFLICT (id) DO UPDATE SET
  display_name   = EXCLUDED.display_name,
  subtitle       = EXCLUDED.subtitle,
  icon           = EXCLUDED.icon,
  accent         = EXCLUDED.accent,
  group_name     = EXCLUDED.group_name,
  sub_view       = EXCLUDED.sub_view,
  href           = EXCLUDED.href,
  module_id      = EXCLUDED.module_id,
  request_target = EXCLUDED.request_target,
  sort_order     = EXCLUDED.sort_order;

COMMIT;