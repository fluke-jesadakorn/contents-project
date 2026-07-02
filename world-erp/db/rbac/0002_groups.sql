-- World ERP — RBAC groups (Linux-style ACL with module groups + departments)
-- Self-contained: re-runnable.
--
-- Adds:
--   rbac.groups          : organizational units (module-group | department | team)
--   rbac.module_groups   : module ↔ group membership (M:N)
--   rbac.role_groups     : role ↔ group membership (M:N)
--   rbac.group_permissions : rwx at group level (cascades to member modules)
--   users.dept_group_id  : FK from user to a department group
--
-- Resolution algorithm (see rbac/src/lib/inheritance.ts):
--   For (role, module, action):
--     1. Direct module ACL via rbac.permissions.
--     2. Group cascade: find module's groups → role's memberships → group_permissions.
--     3. Walk parent_id chain of each matching group.
--     4. Default deny.

BEGIN;

-- Groups ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rbac.groups (
  id          text PRIMARY KEY,
  name        text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('module-group','department','team')),
  parent_id   text REFERENCES rbac.groups(id) ON DELETE SET NULL,
  sort_order  int  NOT NULL DEFAULT 0,
  is_system   boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS groups_parent_idx ON rbac.groups (parent_id);
CREATE INDEX IF NOT EXISTS groups_kind_idx   ON rbac.groups (kind);
CREATE INDEX IF NOT EXISTS groups_sort_idx   ON rbac.groups (sort_order);

-- Module ↔ Group membership --------------------------------------------------

CREATE TABLE IF NOT EXISTS rbac.module_groups (
  module_id  text REFERENCES rbac.modules(id) ON DELETE CASCADE,
  group_id   text REFERENCES rbac.groups(id)  ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (module_id, group_id)
);
CREATE INDEX IF NOT EXISTS module_groups_group_idx ON rbac.module_groups (group_id);

-- Role ↔ Group membership ----------------------------------------------------

CREATE TABLE IF NOT EXISTS rbac.role_groups (
  role_id   text REFERENCES rbac.roles(id)  ON DELETE CASCADE,
  group_id  text REFERENCES rbac.groups(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, group_id)
);
CREATE INDEX IF NOT EXISTS role_groups_group_idx ON rbac.role_groups (group_id);

-- Group-level rwx ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rbac.group_permissions (
  role_id    text REFERENCES rbac.roles(id)  ON DELETE CASCADE,
  group_id   text REFERENCES rbac.groups(id) ON DELETE CASCADE,
  action     rbac.action,
  state      rbac.cell_state NOT NULL,
  updated_by text NOT NULL DEFAULT 'system',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, group_id, action)
);
CREATE INDEX IF NOT EXISTS group_perms_group_idx ON rbac.group_permissions (group_id);

-- User → department group ----------------------------------------------------

ALTER TABLE users ADD COLUMN IF NOT EXISTS dept_group_id text REFERENCES rbac.groups(id);
CREATE INDEX IF NOT EXISTS users_dept_group_idx ON users (dept_group_id);

-- Sync trigger: when users.department changes, point dept_group_id at the
-- matching department group (if one exists). Keeps the legacy string column
-- as the source of truth for display while the FK drives row-level scope.

CREATE OR REPLACE FUNCTION rbac.sync_user_dept_group() RETURNS trigger AS $$
BEGIN
  IF NEW.department IS DISTINCT FROM OLD.department THEN
    SELECT id INTO NEW.dept_group_id
      FROM rbac.groups
     WHERE kind = 'department' AND name = NEW.department
     LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_dept_sync ON users;
CREATE TRIGGER users_dept_sync BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION rbac.sync_user_dept_group();

-- Also handle INSERT (e.g. seed scripts)
CREATE OR REPLACE FUNCTION rbac.init_user_dept_group() RETURNS trigger AS $$
BEGIN
  IF NEW.department IS NOT NULL AND NEW.dept_group_id IS NULL THEN
    SELECT id INTO NEW.dept_group_id
      FROM rbac.groups
     WHERE kind = 'department' AND name = NEW.department
     LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_dept_sync_ins ON users;
CREATE TRIGGER users_dept_sync_ins BEFORE INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION rbac.init_user_dept_group();

-- Touch trigger for groups ----------------------------------------------------

DROP TRIGGER IF EXISTS groups_touch ON rbac.groups;
CREATE TRIGGER groups_touch BEFORE UPDATE ON rbac.groups
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

DROP TRIGGER IF EXISTS group_perms_touch ON rbac.group_permissions;
CREATE TRIGGER group_perms_touch BEFORE UPDATE ON rbac.group_permissions
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

-- Audit kinds ----------------------------------------------------------------

DO $$ BEGIN
  ALTER TYPE rbac.audit_kind ADD VALUE 'group.create';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TYPE rbac.audit_kind ADD VALUE 'group.update';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TYPE rbac.audit_kind ADD VALUE 'group.delete';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TYPE rbac.audit_kind ADD VALUE 'module.add_to_group';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TYPE rbac.audit_kind ADD VALUE 'role.add_to_group';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMIT;