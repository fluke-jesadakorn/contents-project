-- World ERP — Rename "Head of Department" → "Manager of Department"
-- Idempotent. Touches every place a legacy name leaked into persisted data:
--   * roles.name                : 'head_of_department' → 'manager_of_department'
--   * status columns            : 'head_review' → 'manager_review' (expenses, purchase_requisitions, approval_logs, pr_approval_logs, po_approval_logs)
--   * approval_policies.action_json.approver_chain entries
--   * rbac.modules.id           : 'dashboard-hod' → 'dashboard-manager',
--                                'stage-head-review' → 'stage-manager-review'
--   * rbac.modules.display_name : 'Dashboard · Head of Dept' / 'Stage · Head Review'
--   * rbac.permissions / rbac.domain_modules : module_id references
--   * ai_sections.key           : 'hod:approve' → 'manager:approve'

BEGIN;

-- 1. roles.name ------------------------------------------------------------------------
UPDATE roles SET name = 'manager_of_department'
 WHERE name = 'head_of_department';

-- 2. Expense + PR status columns --------------------------------------------------------
UPDATE expenses               SET status = 'manager_review' WHERE status = 'head_review';
UPDATE purchase_requisitions  SET status = 'manager_review' WHERE status = 'head_review';
UPDATE purchase_orders        SET status = 'manager_review' WHERE status = 'head_review';

-- 3. Approval log tables ----------------------------------------------------------------
UPDATE approval_transitions SET previous_status = 'manager_review' WHERE previous_status = 'head_review';
UPDATE approval_transitions SET new_status      = 'manager_review' WHERE new_status      = 'head_review';
UPDATE approval_transitions SET stage           = 'manager_review' WHERE stage           = 'head_review';

-- 4. approval_policies.action_json.approver_chain ---------------------------------------
-- Walk the JSONB array and rewrite any 'head_of_department' entry to
-- 'manager_of_department'. Implemented via LATERAL subquery so the aggregate
-- sits at the right scope for jsonb_set.
UPDATE approval_policies
   SET action_json = jsonb_set(
         action_json,
         '{approver_chain}',
         new_chain.agg,
         false
       )
  FROM (
    SELECT id,
           COALESCE(jsonb_agg(
             CASE elem #>> '{}'
               WHEN 'head_of_department' THEN '"manager_of_department"'::jsonb
               ELSE elem
             END
             ORDER BY ord
           ), '[]'::jsonb) AS agg
      FROM approval_policies,
           LATERAL jsonb_array_elements(action_json->'approver_chain') WITH ORDINALITY AS x(elem, ord)
     WHERE action_json->'approver_chain' @> '"head_of_department"'::jsonb
     GROUP BY id
  ) AS new_chain
 WHERE approval_policies.id = new_chain.id;

-- 5. rbac.modules: rename module IDs + display labels -----------------------------------
-- rbac.permissions / domain_modules / tiles have FKs to rbac.modules(id), so we
-- cannot UPDATE the module PK in place. Strategy:
--   (a) insert the NEW module row (idempotent)
--   (b) point every dependent row at the new id
--   (c) delete the OLD module row (no dependents left → clean)
-- 5a. Insert new module rows (idempotent, harmless if already there)
INSERT INTO rbac.modules (id, display_name, group_name, sort_order, allowed_actions)
VALUES
  ('stage-manager-review', 'Stage · Manager Review', 'Stages', 110, ARRAY['update']::rbac.action[]),
  ('dashboard-manager',   'Dashboard · Manager of Dept', 'Dashboards', 320, ARRAY['read']::rbac.action[])
ON CONFLICT (id) DO UPDATE
  SET display_name    = EXCLUDED.display_name,
      group_name      = EXCLUDED.group_name,
      sort_order      = EXCLUDED.sort_order,
      allowed_actions = EXCLUDED.allowed_actions;

-- 5b. Repoint dependents to the new module ids
UPDATE rbac.permissions    SET module_id = 'stage-manager-review' WHERE module_id = 'stage-head-review';
UPDATE rbac.permissions    SET module_id = 'dashboard-manager'   WHERE module_id = 'dashboard-hod';
UPDATE rbac.domain_modules SET module_id = 'stage-manager-review' WHERE module_id = 'stage-head-review';
UPDATE rbac.domain_modules SET module_id = 'dashboard-manager'   WHERE module_id = 'dashboard-hod';
UPDATE rbac.tiles          SET module_id = 'stage-manager-review' WHERE module_id = 'stage-head-review';
UPDATE rbac.tiles          SET module_id = 'dashboard-manager'   WHERE module_id = 'dashboard-hod';

-- 5c. Now safe to remove the legacy module rows (no dependents remain)
DELETE FROM rbac.modules WHERE id = 'stage-head-review';
DELETE FROM rbac.modules WHERE id = 'dashboard-hod';

-- 6. ai_sections.key --------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ai_sections') THEN
    UPDATE ai_sections SET key = 'manager:approve' WHERE key = 'hod:approve';
  END IF;
END$$;
UPDATE ai_assignments SET section_key = 'manager:approve' WHERE section_key = 'hod:approve';
UPDATE ai_invocations SET section_key = 'manager:approve' WHERE section_key = 'hod:approve';
-- ai_section_health is a VIEW; will reflect updated ai_assignments automatically.

-- 7. JSONB payload columns may contain the legacy strings in audit trails --------
--    Replace any of the legacy substrings inside known JSONB payload columns
--    (best-effort string replace, no-op if not present). Uses both
--    case-sensitive and case-insensitive forms to catch 'Head of Dept'
--    (display label), 'head_of_department' (role name), 'head_review'
--    (status), 'stage-head-review' / 'dashboard-hod' (module ids).
UPDATE rbac.audit
   SET target = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(target::text,
     'stage-head-review', 'stage-manager-review'),
     'dashboard-hod',     'dashboard-manager'),
     'Head of Dept',      'Manager of Dept'),
     'Head of Department','Manager of Department'),
     'head_of_department','manager_of_department'),
     'head_review',       'manager_review')::jsonb
 WHERE target::text ~* 'head';

UPDATE public.policy_audit
   SET before_json = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(before_json::text,
     'stage-head-review', 'stage-manager-review'),
     'dashboard-hod',     'dashboard-manager'),
     'Head of Dept',      'Manager of Dept'),
     'Head of Department','Manager of Department'),
     'head_of_department','manager_of_department'),
     'head_review',       'manager_review')::jsonb
 WHERE before_json IS NOT NULL AND before_json::text ~* 'head';

UPDATE public.policy_audit
   SET after_json  = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(after_json::text,
     'stage-head-review', 'stage-manager-review'),
     'dashboard-hod',     'dashboard-manager'),
     'Head of Dept',      'Manager of Dept'),
     'Head of Department','Manager of Department'),
     'head_of_department','manager_of_department'),
     'head_review',       'manager_review')::jsonb
 WHERE after_json  IS NOT NULL AND after_json::text  ~* 'head';

UPDATE public.notifications
   SET payload_json = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(payload_json::text,
     'stage-head-review', 'stage-manager-review'),
     'dashboard-hod',     'dashboard-manager'),
     'Head of Dept',      'Manager of Dept'),
     'Head of Department','Manager of Department'),
     'head_of_department','manager_of_department'),
     'head_review',       'manager_review')::jsonb
 WHERE payload_json IS NOT NULL AND payload_json::text ~* 'head';

-- Run a second pass case-insensitively to catch 'Head of Dept' (mixed case) — REPLACE is case-sensitive
-- but the `Head of Dept` form above already covers that. Final pass for any straggler:
UPDATE rbac.audit
   SET target = REPLACE(REPLACE(target::text,
     'dashboard-hod', 'dashboard-manager'),
     'stage-head-review', 'stage-manager-review')::jsonb
 WHERE target::text LIKE '%dashboard-hod%' OR target::text LIKE '%stage-head-review%';

COMMIT;