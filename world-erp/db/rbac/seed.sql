-- World ERP — RBAC seed
-- Mirrors the ASCII art: HQ → L4 + DEPT → L3 → L2B → L2A / L1
-- Only explicit ALLOW cells are stored. Anything not stored resolves to deny.
-- The 'inherit' state is reserved for future per-cell inheritance overrides.

BEGIN;

-- Modules (matrix rows) ------------------------------------------------------

INSERT INTO rbac.modules (id, display_name, group_name, sort_order) VALUES
  ('security-config',   '01. Security Config',  'Core',    10),
  ('budget-finance',    '02. Budget & Finance', 'Finance', 20),
  ('client-contracts',  '03. Client Contracts', 'Finance', 30),
  ('core-operations',   '04. Core Operations',  'Ops',     40),
  ('project-tasks',     '05. Project Tasks',    'Ops',     50),
  ('knowledge-base',    '06. Knowledge Base',   'General', 60)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  group_name   = EXCLUDED.group_name,
  sort_order   = EXCLUDED.sort_order;

-- Roles (tree nodes) ---------------------------------------------------------

INSERT INTO rbac.roles (id, name, parent_id, level, sort_order, is_system) VALUES
  ('HQ',     'HQ · Company Root',           NULL,    5, 10, true),
  ('L4',     'L4 · IT Security Admin',      'HQ',    4, 20, true),
  ('DEPT',   'DEPT · Core Business Units',  'HQ',    4, 30, true),
  ('L3',     'L3 · Department Manager',     'DEPT',  3, 40, true),
  ('L2B',    'L2B · Team Supervisor',       'L3',    2, 50, true),
  ('L2A',    'L2A · Operational Staff',     'L2B',   2, 60, true),
  ('L1',     'L1 · Intern / Guest',         'L3',    1, 70, true)
ON CONFLICT (id) DO UPDATE SET
  name       = EXCLUDED.name,
  parent_id  = EXCLUDED.parent_id,
  level      = EXCLUDED.level,
  sort_order = EXCLUDED.sort_order;

-- Permissions (explicit ALLOW only) ------------------------------------------

-- L4 — full CRU on every module (no D anywhere in the org)
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L4', m.id, a, 'allow', 'seed'
FROM rbac.modules m,
     unnest(ARRAY['create','read','update']::rbac.action[]) a
ON CONFLICT DO NOTHING;

-- L3 — read+update on Budget, CRU on the rest
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L3', m.id, a, 'allow', 'seed'
FROM rbac.modules m,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE m.id = 'budget-finance'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L3', m.id, a, 'allow', 'seed'
FROM rbac.modules m,
     unnest(ARRAY['create','read','update']::rbac.action[]) a
WHERE m.id IN ('client-contracts','core-operations','project-tasks','knowledge-base')
ON CONFLICT DO NOTHING;

-- L2B — read+update on Contracts, CRU on the rest (Core/Projects/Knowledge)
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2B', m.id, a, 'allow', 'seed'
FROM rbac.modules m,
     unnest(ARRAY['read','update']::rbac.action[]) a
WHERE m.id = 'client-contracts'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2B', m.id, a, 'allow', 'seed'
FROM rbac.modules m,
     unnest(ARRAY['create','read','update']::rbac.action[]) a
WHERE m.id IN ('core-operations','project-tasks','knowledge-base')
ON CONFLICT DO NOTHING;

-- L2A — read on Core Ops, CRU on Projects & Knowledge
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, 'read', 'allow', 'seed'
FROM rbac.modules m
WHERE m.id = 'core-operations'
ON CONFLICT DO NOTHING;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
SELECT 'L2A', m.id, a, 'allow', 'seed'
FROM rbac.modules m,
     unnest(ARRAY['create','read','update']::rbac.action[]) a
WHERE m.id IN ('project-tasks','knowledge-base')
ON CONFLICT DO NOTHING;

-- L1 — read on Knowledge Base only
INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
VALUES ('L1', 'knowledge-base', 'read', 'allow', 'seed')
ON CONFLICT DO NOTHING;

-- Audit one row per module to seed the history ------------------------------

INSERT INTO rbac.audit (kind, actor, target)
SELECT 'cell.set', 'seed', jsonb_build_object('module', m.id, 'note', 'seed allow rows')
FROM rbac.modules m;

COMMIT;