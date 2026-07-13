-- World ERP — tile catalog cleanup.
--   - "permissions" tile → display_name "Role", subtitle "Assign roles to users"
--   - "directory"   tile → display_name "User Management", subtitle "Edit profiles, departments, status"
--   - new "audit"   tile → display_name "Audit", subtitle "Permission & role change history"

BEGIN;

UPDATE rbac.tiles
   SET display_name = 'Role',
       subtitle     = 'Assign roles to users',
       icon         = '🧮',
       sort_order   = 290
 WHERE id = 'permissions';

UPDATE rbac.tiles
   SET display_name = 'User Management',
       subtitle     = 'Edit profiles, departments, status',
       icon         = '📇',
       sort_order   = 295
 WHERE id = 'directory';

INSERT INTO rbac.modules (id, display_name, group_name, sort_order)
VALUES ('tile-audit', 'Audit Tile', 'Core', 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO rbac.tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, module_id, request_target, sort_order, is_system, required_permission)
VALUES ('audit', 'Audit', 'Permission & role change history', '📜', 'cyan', 'hr', 'audit', '/audit', 'tile-audit', 'hr_manager', 300, true, 'tile:audit:view')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  subtitle     = EXCLUDED.subtitle,
  required_permission = EXCLUDED.required_permission;

INSERT INTO perm.permissions (id, domain, subject, verb, description)
VALUES ('tile:audit:view', 'tile', 'audit', 'view', 'View access for the Audit tile')
ON CONFLICT (id) DO NOTHING;

INSERT INTO perm.role_permissions (role_id, permission_id, effect, granted_by)
SELECT r.id, 'tile:audit:view', 'allow', 'seed-0014'
  FROM perm.roles r
 WHERE r.id IN ('ceo', 'cfo', 'admin', 'hr_manager')
ON CONFLICT DO NOTHING;

COMMIT;