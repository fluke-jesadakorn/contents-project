-- World ERP — RBAC seed (groups + tile-feature modules + memberships + perms)
-- Run after 0002_groups.sql.
--
-- Wipes existing rbac.tile-* modules, group seeds, and group_permissions, then
-- re-inserts the canonical Linux-style ACL.

BEGIN;

-- Clean slate for tile/groups artifacts --------------------------------------

DELETE FROM rbac.group_permissions
 WHERE group_id IN (SELECT id FROM rbac.groups);
DELETE FROM rbac.role_groups;
DELETE FROM rbac.module_groups;
DELETE FROM rbac.groups;
DELETE FROM rbac.permissions
 WHERE module_id IN (SELECT id FROM rbac.modules WHERE id LIKE 'tile-%');
DELETE FROM rbac.modules WHERE id LIKE 'tile-%';

-- Module groups (categories of tiles) ---------------------------------------

INSERT INTO rbac.groups (id, name, kind, sort_order, is_system) VALUES
  ('grp-workflow',          'Workflow',                'module-group', 100, true),
  ('grp-workflow-approval', 'Workflow · Approval',     'module-group', 110, true),
  ('grp-workflow-pr',       'Workflow · Procurement',  'module-group', 120, true),
  ('grp-finance',           'Finance',                 'module-group', 200, true),
  ('grp-cockpit',           'Cockpit',                 'module-group', 300, true),
  ('grp-hr',                'HR',                      'module-group', 400, true),
  ('grp-it',                'IT',                      'module-group', 500, true),
  ('grp-policy',            'Policy',                  'module-group', 600, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, kind = EXCLUDED.kind, sort_order = EXCLUDED.sort_order;

-- Departments ---------------------------------------------------------------

INSERT INTO rbac.groups (id, name, kind, sort_order, is_system) VALUES
  ('dept-engineering', 'Engineering', 'department', 100, true),
  ('dept-sales',       'Sales',       'department', 110, true),
  ('dept-finance',     'Finance',     'department', 120, true),
  ('dept-hr',          'HR',          'department', 130, true),
  ('dept-operations',  'Operations',  'department', 140, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, kind = EXCLUDED.kind, sort_order = EXCLUDED.sort_order;

-- Tile-feature modules ------------------------------------------------------

INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions) VALUES
  ('tile-submit-expense',    'Submit Expense',        'Workflow',                 100, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-my-history',        'My Submissions',        'Workflow',                 110, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-my-prs',            'My PRs',                'Workflow',                 120, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-review-queue',      'Review Queue',          'Workflow · Approval',      130, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-approve-expense',   'Approve Expense',       'Workflow · Approval',      140, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-subordinate-prs',   'Subordinate PRs',       'Workflow · Procurement',   150, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-all-prs',           'All PRs',               'Workflow · Procurement',   160, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-search-coa',        'Search COA',            'Workflow',                 170, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-search-slips',      'Search Slips',          'Workflow',                 180, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-reconciliation',    'Reconciliation',        'Finance',                  190, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-team-manage',       'Team Management',       'Workflow',                 200, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-ops-overview',      'Operations',            'IT',                       210, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-override-queue',    'Override Queue',        'Cockpit',                  220, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-all-approvals',     'All Approvals',         'Cockpit',                  230, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-cockpit',           'Executive Cockpit',     'Cockpit',                  240, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-ledger',            'General Ledger',        'Finance',                  250, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-po',                'PO & Payslip',          'Finance',                  260, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-policy',            'Approval Policy',       'Policy',                   270, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-settings',          'AI Settings',           'IT',                       280, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-org-chart',         'Org Chart',             'HR',                       290, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-directory',         'User Directory',        'HR',                       300, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-departments',       'Departments',           'HR',                       310, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-access-requests',   'Access Requests',       'HR',                       320, ARRAY['create','read','update','delete']::rbac.action[]),
  ('tile-workbench',         'Read-Only View',        'IT',                       330, ARRAY['create','read','update','delete']::rbac.action[])
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  group_name   = EXCLUDED.group_name,
  sort_order   = EXCLUDED.sort_order,
  allowed_actions = EXCLUDED.allowed_actions;

-- Module ↔ Group membership -------------------------------------------------

INSERT INTO rbac.module_groups (module_id, group_id)
SELECT m.id, g.id
FROM rbac.modules m
JOIN rbac.groups g ON g.kind = 'module-group'
WHERE m.id LIKE 'tile-%'
  AND (
    (g.id = 'grp-workflow'          AND m.group_name = 'Workflow')              OR
    (g.id = 'grp-workflow-approval' AND m.group_name = 'Workflow · Approval')   OR
    (g.id = 'grp-workflow-pr'       AND m.group_name = 'Workflow · Procurement') OR
    (g.id = 'grp-finance'           AND m.group_name = 'Finance')               OR
    (g.id = 'grp-cockpit'           AND m.group_name = 'Cockpit')               OR
    (g.id = 'grp-hr'                AND m.group_name = 'HR')                    OR
    (g.id = 'grp-it'                AND m.group_name = 'IT')                    OR
    (g.id = 'grp-policy'            AND m.group_name = 'Policy')
  )
ON CONFLICT DO NOTHING;

-- Role ↔ Group membership ---------------------------------------------------

-- L4 (admin, cfo, ceo, it): every module group
INSERT INTO rbac.role_groups (role_id, group_id)
SELECT 'L4', g.id FROM rbac.groups g WHERE g.kind = 'module-group'
ON CONFLICT DO NOTHING;

-- L3 (manager, head_of_department, accounting_manager)
INSERT INTO rbac.role_groups (role_id, group_id) VALUES
  ('L3', 'grp-workflow-approval'),
  ('L3', 'grp-workflow-pr'),
  ('L3', 'grp-finance'),
  ('L3', 'grp-hr')
ON CONFLICT DO NOTHING;

-- L2B (supervisor, account_officer)
INSERT INTO rbac.role_groups (role_id, group_id) VALUES
  ('L2B', 'grp-workflow'),
  ('L2B', 'grp-workflow-approval'),
  ('L2B', 'grp-workflow-pr'),
  ('L2B', 'grp-finance')
ON CONFLICT DO NOTHING;

-- L2A (staff, accountant, account_supervisor, hr, hr_manager)
INSERT INTO rbac.role_groups (role_id, group_id) VALUES
  ('L2A', 'grp-workflow'),
  ('L2A', 'grp-hr')
ON CONFLICT DO NOTHING;

-- L1 (intern / guest): none yet (read-only knowledge base kept legacy)

-- Group-level rwx ------------------------------------------------------------

-- L4: full rwx on every module group
INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT 'L4', g.id, a, 'allow', 'seed'
FROM rbac.groups g,
     unnest(ARRAY['create','read','update','delete']::rbac.action[]) a
WHERE g.kind = 'module-group'
ON CONFLICT DO NOTHING;

-- L3: read + update on its 4 groups
INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT 'L3', g.id, a, 'allow', 'seed'
FROM rbac.groups g,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE g.id IN ('grp-workflow-approval','grp-workflow-pr','grp-finance','grp-hr')
ON CONFLICT DO NOTHING;

-- L2B: read + update on its 4 groups
INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT 'L2B', g.id, a, 'allow', 'seed'
FROM rbac.groups g,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE g.id IN ('grp-workflow','grp-workflow-approval','grp-workflow-pr','grp-finance')
ON CONFLICT DO NOTHING;

-- L2A: read + create on grp-workflow; read on grp-hr
INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
SELECT 'L2A', g.id, a, 'allow', 'seed'
FROM rbac.groups g,
     unnest(ARRAY['read','create']::rbac.action[]) a
WHERE g.id = 'grp-workflow'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
VALUES ('L2A', 'grp-hr', 'read', 'allow', 'seed')
ON CONFLICT DO NOTHING;

-- Audit one row per new group for history -----------------------------------

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'group.create', 'seed', jsonb_build_object('id', g.id, 'name', g.name, 'kind', g.kind)
FROM rbac.groups g;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'module.add_to_group', 'seed', jsonb_build_object('module', mg.module_id, 'group', mg.group_id)
FROM rbac.module_groups mg;

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'role.add_to_group', 'seed', jsonb_build_object('role', rg.role_id, 'group', rg.group_id)
FROM rbac.role_groups rg;

COMMIT;