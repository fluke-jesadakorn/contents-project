-- World ERP — finalize the rename: tile id 'permissions' → 'roles'.
-- After this migration, slug='permissions' will 404 from the [slug] router
-- because getTileBySlugPerm matches by id/href/sub_view and none of them are
-- 'permissions' anymore.

BEGIN;

UPDATE rbac.tiles SET id = 'roles' WHERE id = 'permissions';

COMMIT;