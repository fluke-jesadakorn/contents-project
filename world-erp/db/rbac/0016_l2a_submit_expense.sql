-- World ERP — Grant L2A create on core-operations
-- Run after 0015_hook_tile.sql.
--
-- submitExpenseFromSlip() in app/actions.ts:229 calls
--   requireActionFor(actorId, 'submit_expense', { rbacSection: 'core-operations', rbacAction: 'create' })
-- but the original rbac/seed.sql only gave L2A 'read' on core-operations. That made
-- expense submission fail with "access matrix disallows create on core-operations"
-- for every staff member. L2B / L3 / L4 were already seeded with create.
--
-- This migration closes the gap so operational staff can submit their own expenses.

BEGIN;

INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
VALUES ('L2A', 'core-operations', 'create', 'allow', 'seed-0016')
ON CONFLICT DO NOTHING;

INSERT INTO rbac.audit (kind, actor, target)
VALUES ('cell.set', 'seed-0016',
        jsonb_build_object('role_id', 'L2A', 'module_id', 'core-operations', 'action', 'create', 'state', 'allow'))
ON CONFLICT DO NOTHING;

COMMIT;
