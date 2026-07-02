-- World ERP — RBAC schema
-- Self-contained namespace: rbac.*
-- Idempotent: safe to re-run.

CREATE SCHEMA IF NOT EXISTS rbac;

-- Enums ----------------------------------------------------------------------

DO $$ BEGIN
  CREATE TYPE rbac.action AS ENUM ('create','read','update','delete');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE rbac.cell_state AS ENUM ('allow','deny','inherit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE rbac.audit_kind AS ENUM (
    'role.create',
    'role.update',
    'role.reparent',
    'role.delete',
    'cell.set',
    'cell.reset',
    'bulk.apply',
    'module.create',
    'module.update'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Modules --------------------------------------------------------------------
-- The horizontal axis of the matrix. Each module = one row.

CREATE TABLE IF NOT EXISTS rbac.modules (
  id              text PRIMARY KEY,
  display_name    text NOT NULL,
  group_name      text NOT NULL DEFAULT 'Core',
  sort_order      int  NOT NULL DEFAULT 0,
  allowed_actions rbac.action[] NOT NULL DEFAULT ARRAY['create','read','update','delete']::rbac.action[],
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Roles ----------------------------------------------------------------------
-- The vertical axis of the tree. parent_id is self-referential.

CREATE TABLE IF NOT EXISTS rbac.roles (
  id         text PRIMARY KEY,
  name       text NOT NULL,
  parent_id  text REFERENCES rbac.roles(id) ON DELETE RESTRICT,
  level      int  NOT NULL,
  sort_order int  NOT NULL DEFAULT 0,
  is_system  boolean NOT NULL DEFAULT false,
  version    bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (level BETWEEN 1 AND 10)
);
CREATE INDEX IF NOT EXISTS roles_parent_idx ON rbac.roles (parent_id);
CREATE INDEX IF NOT EXISTS roles_sort_idx   ON rbac.roles (sort_order);

-- Permissions ----------------------------------------------------------------
-- One row = (role, module, action). 'inherit' resolves to nearest ancestor.

CREATE TABLE IF NOT EXISTS rbac.permissions (
  role_id    text REFERENCES rbac.roles(id)   ON DELETE CASCADE,
  module_id  text REFERENCES rbac.modules(id) ON DELETE CASCADE,
  action     rbac.action,
  state      rbac.cell_state NOT NULL,
  updated_by text NOT NULL DEFAULT 'system',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, module_id, action)
);
CREATE INDEX IF NOT EXISTS perms_role_idx    ON rbac.permissions (role_id);
CREATE INDEX IF NOT EXISTS perms_module_idx  ON rbac.permissions (module_id);

-- Audit ----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rbac.audit (
  id          bigserial PRIMARY KEY,
  kind        rbac.audit_kind NOT NULL,
  actor       text NOT NULL DEFAULT 'system',
  target      jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_time_idx ON rbac.audit (occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_kind_idx ON rbac.audit (kind);
CREATE INDEX IF NOT EXISTS audit_target_gin ON rbac.audit USING gin (target);

-- Updated-at trigger ---------------------------------------------------------

CREATE OR REPLACE FUNCTION rbac.touch() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS roles_touch ON rbac.roles;
CREATE TRIGGER roles_touch BEFORE UPDATE ON rbac.roles
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

DROP TRIGGER IF EXISTS perms_touch ON rbac.permissions;
CREATE TRIGGER perms_touch BEFORE UPDATE ON rbac.permissions
  FOR EACH ROW EXECUTE FUNCTION rbac.touch();

-- Cycle prevention -----------------------------------------------------------
-- Used by the reparent endpoint to reject moves that would create a loop.

CREATE OR REPLACE FUNCTION rbac.is_descendant(
  p_candidate text,
  p_ancestor  text
) RETURNS boolean AS $$
  WITH RECURSIVE chain AS (
    SELECT id, parent_id FROM rbac.roles WHERE id = p_candidate
    UNION ALL
    SELECT r.id, r.parent_id FROM rbac.roles r JOIN chain c ON r.id = c.parent_id
  )
  SELECT EXISTS (SELECT 1 FROM chain WHERE id = p_ancestor);
$$ LANGUAGE sql STABLE;