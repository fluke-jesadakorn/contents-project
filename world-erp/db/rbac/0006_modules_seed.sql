-- World ERP — RBAC consolidation seed
-- Run after 0005_consolidation.sql.
--
-- Adds 30 new rbac.modules (replaces the in-TS ROLE_PERMISSIONS matrix):
--   7 tab-*       (tab-workbench, tab-pr, tab-ledger, tab-cockpit, tab-policy, tab-settings, tab-hr)
--   8 stage-*     (the 6 expense stages + 2 PO stages)
--   7 dashboard-* (one per persona; replaces DASHBOARD_MATRIX)
--   2 admin       (rbac-admin, rbac-viewer)
--   6 perm        (cross-cutting permission modules)
--
-- Plus rbac.permissions rows so every legacy role gets exactly the
-- access it had in lib/permissions.ts. Going forward, new access
-- grants are made via the matrix editor (PATCH /api/cells) or
-- /api/modules/:id/groups.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Modules
-- ---------------------------------------------------------------------------

INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions) VALUES
  -- Tabs
  ('tab-workbench', 'Workbench Tab',    'Tabs',      10, ARRAY['read']::rbac.action[]),
  ('tab-pr',        'PR Tab',           'Tabs',      20, ARRAY['read']::rbac.action[]),
  ('tab-ledger',    'Ledger Tab',       'Tabs',      30, ARRAY['read']::rbac.action[]),
  ('tab-cockpit',   'Cockpit Tab',      'Tabs',      40, ARRAY['read']::rbac.action[]),
  ('tab-policy',    'Policy Tab',       'Tabs',      50, ARRAY['read']::rbac.action[]),
  ('tab-settings',  'Settings Tab',     'Tabs',      60, ARRAY['read']::rbac.action[]),
  ('tab-hr',        'HR Tab',           'Tabs',      70, ARRAY['read']::rbac.action[]),
  -- Stages (expense)
  ('stage-supervisor-review',        'Stage · Supervisor Review',        'Stages',     100, ARRAY['update']::rbac.action[]),
  ('stage-head-review',              'Stage · Head Review',              'Stages',     110, ARRAY['update']::rbac.action[]),
  ('stage-account-officer-review',   'Stage · Account Officer Review',   'Stages',     120, ARRAY['update']::rbac.action[]),
  ('stage-account-supervisor-review','Stage · Account Supervisor Review','Stages',     130, ARRAY['update']::rbac.action[]),
  ('stage-accounting-review',        'Stage · Accounting Review',        'Stages',     140, ARRAY['update']::rbac.action[]),
  ('stage-cfo-review',               'Stage · CFO Review',               'Stages',     150, ARRAY['update']::rbac.action[]),
  -- Stages (PO)
  ('stage-po-pending',               'Stage · PO Pending',               'Stages',     200, ARRAY['update']::rbac.action[]),
  ('stage-po-cfo',                   'Stage · PO CFO',                   'Stages',     210, ARRAY['update']::rbac.action[]),
  -- Dashboards
  ('dashboard-it',        'Dashboard · IT',         'Dashboards', 300, ARRAY['read']::rbac.action[]),
  ('dashboard-exec',      'Dashboard · Executive',   'Dashboards', 310, ARRAY['read']::rbac.action[]),
  ('dashboard-hod',       'Dashboard · Head of Dept','Dashboards', 320, ARRAY['read']::rbac.action[]),
  ('dashboard-am',        'Dashboard · Accounting Mgr','Dashboards',330, ARRAY['read']::rbac.action[]),
  ('dashboard-reviewer',  'Dashboard · Reviewer',    'Dashboards', 340, ARRAY['read']::rbac.action[]),
  ('dashboard-staff',     'Dashboard · Staff',       'Dashboards', 350, ARRAY['read']::rbac.action[]),
  ('dashboard-hr',        'Dashboard · HR',          'Dashboards', 360, ARRAY['read']::rbac.action[]),
  -- Admin meta
  ('rbac-admin',   'Admin · Manage Matrix', 'Admin', 400, ARRAY['create','read','update','delete']::rbac.action[]),
  ('rbac-viewer',  'Admin · View Audit',    'Admin', 410, ARRAY['read']::rbac.action[]),
  -- Cross-cutting permissions
  ('permission-edit-user-dept',     'Permission · Edit User Department', 'Perm', 500, ARRAY['update']::rbac.action[]),
  ('permission-edit-user-subtree',  'Permission · Edit User Subtree',    'Perm', 510, ARRAY['update']::rbac.action[]),
  ('rbac-view-matrix',              'Permission · View Org Matrix',      'Perm', 520, ARRAY['read']::rbac.action[]),
  ('rbac-edit-matrix',              'Permission · Edit Org Matrix',      'Perm', 530, ARRAY['update']::rbac.action[]),
  ('access-request-list',           'Permission · List Access Requests', 'Perm', 540, ARRAY['read']::rbac.action[]),
  ('access-request-resolve',        'Permission · Resolve Access Requests','Perm', 550, ARRAY['update']::rbac.action[])
ON CONFLICT (id) DO UPDATE SET
  display_name    = EXCLUDED.display_name,
  group_name      = EXCLUDED.group_name,
  sort_order      = EXCLUDED.sort_order,
  allowed_actions = EXCLUDED.allowed_actions;

-- ---------------------------------------------------------------------------
-- 2. Default tab + staff level + scope per role
--    (mirrors lib/permissions.ts ROLE_PERMISSIONS shape; the role_id
--     value is the rbac.roles.id, not the legacy roles.id)
-- ---------------------------------------------------------------------------

-- wipe existing per-role metadata so re-runs converge
UPDATE rbac.roles SET default_tab_id = NULL, default_staff_level = NULL WHERE TRUE;

UPDATE rbac.roles SET default_tab_id = 'tab-workbench', default_staff_level = 5, scope_kind = 'self'         WHERE id = 'L2A';
UPDATE rbac.roles SET default_tab_id = 'tab-workbench', default_staff_level = 5, scope_kind = 'self'         WHERE id = 'L1';
UPDATE rbac.roles SET default_tab_id = 'tab-cockpit',   default_staff_level = 2, scope_kind = 'all'          WHERE id = 'L4';
UPDATE rbac.roles SET default_tab_id = 'tab-workbench', default_staff_level = 3, scope_kind = 'department'   WHERE id = 'L3';
UPDATE rbac.roles SET default_tab_id = 'tab-workbench', default_staff_level = 2, scope_kind = 'department'   WHERE id = 'L2B';

-- ---------------------------------------------------------------------------
-- 3. Per-role explicit permissions
--    (group cascade is the recommended path; this section seeds the
--     permissions for the new modules directly so they work out of the
--     box even if the seed_groups.sql is not re-run.)
-- ---------------------------------------------------------------------------

DELETE FROM rbac.permissions WHERE module_id LIKE 'tab-%'    AND updated_by = 'seed-0006';
DELETE FROM rbac.permissions WHERE module_id LIKE 'stage-%'  AND updated_by = 'seed-0006';
DELETE FROM rbac.permissions WHERE module_id LIKE 'dashboard-%' AND updated_by = 'seed-0006';
DELETE FROM rbac.permissions WHERE module_id IN ('rbac-admin','rbac-viewer') AND updated_by = 'seed-0006';
DELETE FROM rbac.permissions WHERE module_id LIKE 'permission-%' AND updated_by = 'seed-0006';
DELETE FROM rbac.permissions WHERE module_id IN ('rbac-view-matrix','rbac-edit-matrix','access-request-list','access-request-resolve') AND updated_by = 'seed-0006';

-- ----- L4 (admin / cfo / ceo / it) — everything -----
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L4', m.id, a, 'allow', 'seed-0006'
FROM rbac.modules m,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE m.id IN (
  'tab-workbench','tab-pr','tab-ledger','tab-cockpit','tab-policy','tab-settings','tab-hr',
  'stage-supervisor-review','stage-head-review','stage-account-officer-review',
  'stage-account-supervisor-review','stage-accounting-review','stage-cfo-review',
  'stage-po-pending','stage-po-cfo',
  'dashboard-it','dashboard-exec','dashboard-hod','dashboard-am','dashboard-reviewer',
  'dashboard-staff','dashboard-hr',
  'rbac-admin','rbac-viewer',
  'permission-edit-user-dept','permission-edit-user-subtree',
  'rbac-view-matrix','rbac-edit-matrix',
  'access-request-list','access-request-resolve'
)
ON CONFLICT DO NOTHING;

-- ----- L3 (manager / head_of_department / accounting_manager) -----
-- tabs: workbench, pr, ledger, hr
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L3', m.id, 'read', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('tab-workbench','tab-pr','tab-ledger','tab-hr','tab-cockpit')
ON CONFLICT DO NOTHING;

-- stages: own stage (per-persona — but at L3 we grant head_review + accounting_review + po_pending)
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L3', m.id, 'update', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('stage-head-review','stage-accounting-review','stage-po-pending')
ON CONFLICT DO NOTHING;

-- dashboards
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L3', m.id, 'read', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('dashboard-hod','dashboard-am','dashboard-exec')
ON CONFLICT DO NOTHING;

-- perms
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L3', m.id, a, 'allow', 'seed-0006'
FROM rbac.modules m,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE m.id IN ('permission-edit-user-subtree','rbac-view-matrix')
ON CONFLICT DO NOTHING;

-- ----- L2B (supervisor / account_officer) -----
-- tabs: workbench, pr
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2B', m.id, 'read', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('tab-workbench','tab-pr')
ON CONFLICT DO NOTHING;

-- stages: supervisor_review (supervisor) + account_officer_review (account_officer)
-- L2B holds both for simplicity — within the same row level the matrix can
-- differentiate via the role_name field if needed.
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2B', m.id, 'update', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('stage-supervisor-review','stage-account-officer-review')
ON CONFLICT DO NOTHING;

-- dashboards: reviewer
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2B', m.id, 'read', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('dashboard-reviewer')
ON CONFLICT DO NOTHING;

-- ----- L2A (staff / accountant / account_supervisor / hr / hr_manager) -----
-- tabs: workbench, pr, ledger (per role), hr
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, 'read', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('tab-workbench','tab-pr','tab-hr')
ON CONFLICT DO NOTHING;

-- stages: account_supervisor_review
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, 'update', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('stage-account-supervisor-review')
ON CONFLICT DO NOTHING;

-- dashboards: staff / hr
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, 'read', 'allow', 'seed-0006'
FROM rbac.modules m
WHERE m.id IN ('dashboard-staff','dashboard-hr','dashboard-reviewer')
ON CONFLICT DO NOTHING;

-- perms (hr_manager has more — the matrix editor can add person-specific rows)
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, a, 'allow', 'seed-0006'
FROM rbac.modules m,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE m.id IN ('permission-edit-user-dept','rbac-view-matrix','rbac-edit-matrix','access-request-list','access-request-resolve')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Audit one row per new module
-- ---------------------------------------------------------------------------

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'module.create', 'seed-0006', jsonb_build_object('id', m.id, 'name', m.display_name)
FROM rbac.modules m
WHERE m.group_name IN ('Tabs','Stages','Dashboards','Admin','Perm')
ON CONFLICT DO NOTHING;

COMMIT;
