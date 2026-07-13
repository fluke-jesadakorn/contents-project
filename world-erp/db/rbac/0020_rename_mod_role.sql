-- World ERP — Drop legacy role `manager_of_department` (alias for `manager`)
-- Run after 0019_departments_into_groups.sql.
--
-- 0022_unify_personas.sql introduced BOTH `manager` and `manager_of_department`
-- as sibling personas under L3. They're functionally identical (same scope_kind
-- `department`, same default_staff_level 3). Collapse them: any user still on
-- `manager_of_department` is moved to `manager`, and the duplicate role row is
-- deleted.
--
-- Also rewrites every persisted JSONB column that referenced the old role name
-- so the rename is end-to-end consistent.

BEGIN;

-- 1. Move any user still on manager_of_department → manager.
UPDATE users SET rbac_role_id = 'manager'
 WHERE rbac_role_id = 'manager_of_department';

-- 2. Drop the duplicate role row.
DELETE FROM rbac.roles WHERE id = 'manager_of_department';

-- 3. Drop stale rbac.role_groups / rbac.group_permissions rows for the gone role.
DELETE FROM rbac.role_groups      WHERE role_id = 'manager_of_department';
DELETE FROM rbac.group_permissions WHERE role_id = 'manager_of_department';
DELETE FROM rbac.permissions       WHERE role_id = 'manager_of_department';

-- 4. Rewrite persisted JSONB columns that embed the old role name.
UPDATE approval_policies
   SET action_json = jsonb_set(
         action_json,
         '{approver_chain}',
         COALESCE((
           SELECT jsonb_agg(
             CASE elem #>> '{}'
               WHEN 'manager_of_department' THEN '"manager"'::jsonb
               ELSE elem
             END
             ORDER BY ord
           )
           FROM jsonb_array_elements(action_json->'approver_chain') WITH ORDINALITY AS x(elem, ord)
         ), '[]'::jsonb),
         false
       )
 WHERE action_json->'approver_chain' @> '"manager_of_department"'::jsonb;

UPDATE approval_policies
   SET conditions_json = regexp_replace(conditions_json::text, 'manager_of_department', 'manager', 'g')::jsonb
 WHERE conditions_json::text LIKE '%manager_of_department%';

UPDATE rbac.audit
   SET target = regexp_replace(target::text, 'manager_of_department', 'manager', 'g')::jsonb
 WHERE target::text LIKE '%manager_of_department%';

UPDATE public.policy_audit
   SET before_json = regexp_replace(before_json::text, 'manager_of_department', 'manager', 'g')::jsonb
 WHERE before_json IS NOT NULL AND before_json::text LIKE '%manager_of_department%';

UPDATE public.policy_audit
   SET after_json = regexp_replace(after_json::text, 'manager_of_department', 'manager', 'g')::jsonb
 WHERE after_json IS NOT NULL AND after_json::text LIKE '%manager_of_department%';

UPDATE public.notifications
   SET payload_json = regexp_replace(payload_json::text, 'manager_of_department', 'manager', 'g')::jsonb
 WHERE payload_json IS NOT NULL AND payload_json::text LIKE '%manager_of_department%';

-- 5. Audit the collapse.
INSERT INTO rbac.audit (kind, actor, target)
VALUES ('role.update', 'migration-0020',
        jsonb_build_object('action','merge','from','manager_of_department','into','manager'));

COMMIT;