-- World ERP — rename tile to point at /roles instead of /permissions.
-- Tile id stays 'permissions' (stable PK; many internal lookups use it).
-- Only display_name, subtitle, href, sub_view change.
-- Sub_view + href are matched in SlugTile.tsx getTileBySlugPerm(), so all three
-- (id, href, sub_view) must be updated together to avoid duplicate matches.

BEGIN;

UPDATE rbac.tiles
   SET display_name = 'Roles',
       subtitle     = 'User → Role → Permission',
       href         = '/roles',
       sub_view     = 'roles'
 WHERE id = 'permissions';

COMMIT;