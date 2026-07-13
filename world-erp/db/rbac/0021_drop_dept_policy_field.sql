-- World ERP — Delete approval policies that filter by the removed `department` field
-- Run after 0020_rename_mod_role.sql.
--
-- The PolicyEditor used to expose `field: 'department'` as a string-match
-- condition, comparing against users.department (the legacy free-text column
-- dropped by 0018). The condition is being removed entirely; any saved policy
-- that still references it is silently broken now, so delete them here.
--
-- Each deleted policy's last `before_json` is preserved in policy_audit for
-- traceability.

BEGIN;

INSERT INTO public.policy_audit (policy_id, actor_id, before_json, after_json, changed_at)
SELECT ap.id, NULL, ap.conditions_json, NULL, now()
  FROM approval_policies ap
 WHERE ap.conditions_json::text LIKE '%"field":"department"%'
    OR ap.conditions_json::text LIKE '%"field": "department"%';

DELETE FROM approval_policies
 WHERE conditions_json::text LIKE '%"field":"department"%'
    OR conditions_json::text LIKE '%"field": "department"%';

COMMIT;