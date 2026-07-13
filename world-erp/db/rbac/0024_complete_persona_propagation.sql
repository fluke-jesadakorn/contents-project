-- World ERP — RBAC: complete partial 0022 persona propagation.
--
-- Migration 0022 was applied piecemeal:
--   * personas were created in rbac.roles (good)
--   * users.rbac_role_id was migrated to the new ids (good)
--   * but default_staff_level=NULL on every persona (the ON CONFLICT
--     DO UPDATE clause didn't persist for any row), so 4 users
--     (Sarah/David/Michael/Olivia) currently land in P5 STAFF instead of
--     P3 / P2 in the PersonaMenu
--   * role_groups + group_permissions propagation step was skipped, so
--     the 14 personas have empty cascades
--   * the legacy users_dept_sync / users_dept_sync_ins triggers plus
--     rbac.sync_user_dept_group / rbac.init_user_dept_group are still
--     attached to public.users and reference the dropped
--     users.department column — every INSERT/UPDATE on users blows up.
--
-- This migration closes all three gaps and anchors the floating users.

BEGIN;

-- 1. Drop orphaned triggers + functions from the old users.department column.
DROP TRIGGER IF EXISTS users_dept_sync      ON public.users;
DROP TRIGGER IF EXISTS users_dept_sync_ins  ON public.users;
DROP FUNCTION IF EXISTS rbac.sync_user_dept_group();
DROP FUNCTION IF EXISTS rbac.init_user_dept_group();

-- 2. Restore default_staff_level on every persona. Values follow the
--    PersonaMenu P1..P5 spec, not the legacy display.ts ROLE_LEVEL.
UPDATE rbac.roles SET default_staff_level = 5 WHERE id = 'staff';              -- P5
UPDATE rbac.roles SET default_staff_level = 5 WHERE id = 'accountant';         -- P5
UPDATE rbac.roles SET default_staff_level = 5 WHERE id = 'account_officer';    -- P5
UPDATE rbac.roles SET default_staff_level = 4 WHERE id = 'account_supervisor'; -- P4
UPDATE rbac.roles SET default_staff_level = 5 WHERE id = 'hr';                 -- P5
UPDATE rbac.roles SET default_staff_level = 5 WHERE id = 'it';                 -- P5 (NOT 2)
UPDATE rbac.roles SET default_staff_level = 5 WHERE id = 'finance';            -- P5 (NOT 2)
UPDATE rbac.roles SET default_staff_level = 4 WHERE id = 'supervisor';         -- P4
UPDATE rbac.roles SET default_staff_level = 3 WHERE id = 'manager';            -- P3
UPDATE rbac.roles SET default_staff_level = 3 WHERE id = 'accounting_manager'; -- P3
UPDATE rbac.roles SET default_staff_level = 3 WHERE id = 'hr_manager';         -- P3
UPDATE rbac.roles SET default_staff_level = 2 WHERE id = 'admin';              -- P2
UPDATE rbac.roles SET default_staff_level = 2 WHERE id = 'cfo';                -- P2
UPDATE rbac.roles SET default_staff_level = 1 WHERE id = 'ceo';                -- P1

-- 3. Re-run the parent-tier → persona cascade for role_groups and
--    group_permissions. Idempotent thanks to ON CONFLICT DO NOTHING.
INSERT INTO rbac.role_groups (role_id, group_id)
  SELECT p.id, rg.group_id
    FROM rbac.roles p
    JOIN rbac.roles parent ON parent.id = p.parent_id
    JOIN rbac.role_groups rg ON rg.role_id = parent.id
  ON CONFLICT DO NOTHING;

INSERT INTO rbac.group_permissions (role_id, group_id, action, state, updated_by)
  SELECT p.id, gp.group_id, gp.action, gp.state, 'migration-0024'
    FROM rbac.roles p
    JOIN rbac.roles parent ON parent.id = p.parent_id
    JOIN rbac.group_permissions gp ON gp.role_id = parent.id
  ON CONFLICT DO NOTHING;

-- 4. Fill the 5 headless departments with existing users.
UPDATE rbac.groups SET head_user_id = 15 WHERE id = 'dept-executive'; -- Charles Executive (CEO)
UPDATE rbac.groups SET head_user_id =  4 WHERE id = 'dept-finance-2'; -- Emily Manager (accounting_manager)
UPDATE rbac.groups SET head_user_id = 30 WHERE id = 'dept-hr-2';      -- Patricia Manager (hr_manager)
UPDATE rbac.groups SET head_user_id = 20 WHERE id = 'dept-it';        -- Alex Admin (it)
UPDATE rbac.groups SET head_user_id = 50 WHERE id = 'dept-marketing'; -- Karen Staff (staff)

-- 5. Anchor the 5 users without dept_group_id.
--    reports_to_user_id seeding REMOVED on 2026-07-04 (migration 2026-07-04-A-clear-reports-to.sql);
--    that column is now HR-managed via PATCH /api/users/[id] or direct SQL.
UPDATE users SET dept_group_id      = 'dept-development' WHERE id = 38; -- Sarah Approver (manager)
UPDATE users SET dept_group_id      = 'dept-finance-2'   WHERE id = 48; -- David Approver (manager)
UPDATE users SET dept_group_id      = 'dept-finance-2'   WHERE id = 52; -- Michael Manager (manager)
UPDATE users SET dept_group_id      = 'dept-development' WHERE id = 34; -- Steven Supervisor (supervisor)
UPDATE users SET dept_group_id      = 'dept-marketing'   WHERE id = 47; -- Lisa Staff

-- 6. Audit row.
INSERT INTO rbac.audit (kind, actor, target)
  VALUES ('role.update', 'migration-0024',
          jsonb_build_object(
            'note', 'complete partial 0022 propagation: drop orphaned triggers, restore default_staff_level, propagate role_groups/group_permissions, anchor floating managers + dept heads'
          ));

COMMIT;
