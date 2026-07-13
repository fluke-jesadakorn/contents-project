-- World ERP — RBAC: normalize persona position labels to the tier pattern.
--
-- Tier pattern (lowest → highest authority):
--   P5 Officer    → "<Domain> Officer"
--   P4 Supervisor → "<Domain> Supervisor"
--   P3 Manager    → "<Domain> Manager"  (generic `manager` role interpolates dept)
--   P1–P2 C Level → role-specific executive titles (CEO / CFO / Admin / Finance)
--
-- Mirrors the canonical map in web-admin/src/lib/roles/display.ts ROLE_LABEL.
-- DB display_name is used by HR/Admin stats (queries.ts:663 GROUP BY pr.display_name)
-- so it must stay in sync with the UI labels.

BEGIN;

UPDATE perm.roles SET display_name = 'Staff Officer'         WHERE id = 'staff';
UPDATE perm.roles SET display_name = 'Accounting Officer'    WHERE id = 'accountant';
UPDATE perm.roles SET display_name = 'Accounting Officer'    WHERE id = 'account_officer';
UPDATE perm.roles SET display_name = 'HR Officer'            WHERE id = 'hr';
UPDATE perm.roles SET display_name = 'IT Officer'            WHERE id = 'it';

UPDATE perm.roles SET display_name = 'Accounting Supervisor' WHERE id = 'account_supervisor';
UPDATE perm.roles SET display_name = 'Supervisor'            WHERE id = 'supervisor';

UPDATE perm.roles SET display_name = 'Manager'               WHERE id = 'manager';
UPDATE perm.roles SET display_name = 'HR Manager'            WHERE id = 'hr_manager';
UPDATE perm.roles SET display_name = 'Accounting Manager'    WHERE id = 'accounting_manager';

UPDATE perm.roles SET display_name_th = 'เจ้าหน้าที่ทั่วไป'     WHERE id = 'staff';
UPDATE perm.roles SET display_name_th = 'เจ้าหน้าที่บัญชี'        WHERE id = 'accountant';
UPDATE perm.roles SET display_name_th = 'เจ้าหน้าที่บัญชี'        WHERE id = 'account_officer';
UPDATE perm.roles SET display_name_th = 'เจ้าหน้าที่ HR'          WHERE id = 'hr';
UPDATE perm.roles SET display_name_th = 'เจ้าหน้าที่ไอที'         WHERE id = 'it';

UPDATE perm.roles SET display_name_th = 'หัวหน้างานบัญชี'       WHERE id = 'account_supervisor';
UPDATE perm.roles SET display_name_th = 'หัวหน้าทีม'             WHERE id = 'supervisor';

UPDATE perm.roles SET display_name_th = 'ผู้จัดการ'              WHERE id = 'manager';
UPDATE perm.roles SET display_name_th = 'ผู้จัดการ HR'           WHERE id = 'hr_manager';
UPDATE perm.roles SET display_name_th = 'ผู้จัดการบัญชี'          WHERE id = 'accounting_manager';

UPDATE perm.roles SET display_name_th = 'ประธานเจ้าหน้าที่บริหาร'  WHERE id = 'ceo'    AND display_name_th IS NULL;
UPDATE perm.roles SET display_name_th = 'ประธานเจ้าหน้าที่ฝ่ายการเงิน' WHERE id = 'cfo' AND display_name_th IS NULL;
UPDATE perm.roles SET display_name_th = 'ผู้บริหาร'                WHERE id = 'admin' AND display_name_th IS NULL;
UPDATE perm.roles SET display_name_th = 'การเงิน'                  WHERE id = 'finance' AND display_name_th IS NULL;

COMMIT;