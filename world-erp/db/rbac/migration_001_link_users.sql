-- Add rbac_role_id column to public.users so we can link them to the new hierarchy.
-- Idempotent migration.

ALTER TABLE users ADD COLUMN IF NOT EXISTS rbac_role_id text REFERENCES rbac.roles(id);

-- Map existing users by their legacy role_id to the new RBAC hierarchy.
-- L4:   admin, cfo, ceo, it
-- L3:   manager, head_of_department, accounting_manager
-- L2B:  account_officer, supervisor
-- L2A:  staff, accountant, account_supervisor, hr, hr_manager
-- L1:   (none seeded — interns are ad-hoc)

UPDATE users SET rbac_role_id = 'L2A' WHERE role_id IN (1, 2, 11, 12, 14) AND rbac_role_id IS NULL;
UPDATE users SET rbac_role_id = 'L2B' WHERE role_id IN (9, 13)            AND rbac_role_id IS NULL;
UPDATE users SET rbac_role_id = 'L3'  WHERE role_id IN (3, 5, 6)           AND rbac_role_id IS NULL;
UPDATE users SET rbac_role_id = 'L4'  WHERE role_id IN (4, 7, 8, 10)       AND rbac_role_id IS NULL;