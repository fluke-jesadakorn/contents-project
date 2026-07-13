-- World ERP — Collapse persona `accountant` into `account_officer`.
--
-- The two ids shared the same display label ("Accounting Officer") but
-- diverged in seeded perms: `accountant` had review-only access,
-- `account_officer` had approve/reject. Both target the same seat in
-- the receipt flow (accounting_verification stage) so we unify them.
--
-- Effect: the surviving `account_officer` row keeps the union of
-- both role permission sets; every `accountant` user_roles row is
-- re-pointed; the `accountant` role row + its role_permissions are
-- removed. The perm_rp_sync_level trigger fires automatically and
-- keeps levels consistent.

BEGIN;

INSERT INTO perm.role_permissions (role_id, permission_id, effect, granted_by)
SELECT 'account_officer', permission_id, effect, 'migration:0027-collapse-accountant'
  FROM perm.role_permissions
 WHERE role_id = 'accountant'
ON CONFLICT (role_id, permission_id) DO NOTHING;

UPDATE perm.user_roles
   SET role_id = 'account_officer'
 WHERE role_id = 'accountant';

DELETE FROM perm.role_permissions WHERE role_id = 'accountant';
DELETE FROM perm.roles WHERE id = 'accountant';

COMMIT;