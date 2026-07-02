-- World ERP — Tile access meta view
-- Static per-tile Department / Group / Level derived from the RBAC matrix.
-- Persona-independent: values describe what the matrix grants, not the actor.
--
-- Department: rbac.module_groups ⋈ rbac.groups(kind='department'); fall back
--             to rbac.tiles.owner_group_id if the module has no department groups.
-- Group:      rbac.module_groups ⋈ rbac.groups(kind='module-group'); 'All' if
--             the module belongs to more than one module-group.
-- Level:      MIN(rbac.roles.default_staff_level) over the union of roles that
--             have 'read' = allow — direct (rbac.permissions) and inherited
--             via the group cascade (rbac.group_permissions ⋈ rbac.role_groups).
--             Inherits through parent_id on both rbac.groups and rbac.roles.

BEGIN;

CREATE OR REPLACE VIEW rbac.tile_access_meta AS
WITH RECURSIVE
group_chain AS (
  SELECT mg.module_id, g.id AS group_id, g.parent_id, g.kind
    FROM rbac.module_groups mg
    JOIN rbac.groups g ON g.id = mg.group_id
  UNION
  SELECT gc.module_id, g.id, g.parent_id, g.kind
    FROM rbac.groups g
    JOIN group_chain gc ON g.id = gc.parent_id
),
role_chain AS (
  SELECT id, parent_id FROM rbac.roles
),
allowed_roles AS (
  SELECT p.module_id, p.role_id
    FROM rbac.permissions p
   WHERE p.action = 'read' AND p.state = 'allow'
  UNION
  SELECT gc.module_id, rg.role_id
    FROM group_chain gc
    JOIN rbac.group_permissions gp ON gp.group_id = gc.group_id
    JOIN rbac.role_groups      rg ON rg.group_id  = gp.group_id
   WHERE gp.action = 'read' AND gp.state = 'allow'
),
role_with_ancestors AS (
  SELECT DISTINCT ar.module_id, rc.id AS role_id
    FROM allowed_roles ar
    JOIN role_chain rc ON rc.id = ar.role_id
                       OR EXISTS (
                         WITH RECURSIVE up AS (
                           SELECT id, parent_id FROM rbac.roles WHERE id = ar.role_id
                           UNION ALL
                           SELECT r.id, r.parent_id FROM rbac.roles r JOIN up ON r.id = up.parent_id
                         )
                         SELECT 1 FROM up WHERE up.id = rc.id
                       )
),
levels AS (
  SELECT rwa.module_id, MIN(r.default_staff_level) AS min_level
    FROM role_with_ancestors rwa
    JOIN rbac.roles r ON r.id = rwa.role_id
   WHERE r.default_staff_level IS NOT NULL
   GROUP BY rwa.module_id
),
dept_counts AS (
  SELECT gc.module_id,
         COUNT(*)        AS n,
         MIN(g.id)       AS dept_id,
         MIN(g.name)     AS dept_name
    FROM group_chain gc
    JOIN rbac.groups g ON g.id = gc.group_id
   WHERE g.kind = 'department'
   GROUP BY gc.module_id
),
group_counts AS (
  SELECT gc.module_id,
         COUNT(*)    AS n,
         MIN(g.id)   AS group_id,
         MIN(g.name) AS group_name
    FROM group_chain gc
    JOIN rbac.groups g ON g.id = gc.group_id
   WHERE g.kind = 'module-group'
   GROUP BY gc.module_id
),
owner_dept AS (
  SELECT t.id AS tile_id, g.id AS dept_id, g.name AS dept_name
    FROM rbac.tiles t
    JOIN rbac.groups g ON g.id = t.owner_group_id AND g.kind = 'department'
)
SELECT t.id AS tile_id,
       l.min_level,
       COALESCE(dc.dept_id, od.dept_id)     AS dept_id,
       COALESCE(dc.dept_name, od.dept_name) AS dept_name,
       gc.group_id,
       CASE
         WHEN gc.n IS NULL OR gc.n = 0 THEN NULL
         WHEN gc.n = 1 THEN gc.group_name
         ELSE 'All'
       END AS group_name,
       (gc.n IS NULL OR gc.n <= 1) AS group_is_specific
  FROM rbac.tiles t
  LEFT JOIN levels       l  ON l.module_id = t.module_id
  LEFT JOIN dept_counts  dc ON dc.module_id = t.module_id
  LEFT JOIN owner_dept   od ON od.tile_id   = t.id AND dc.dept_id IS NULL
  LEFT JOIN group_counts gc ON gc.module_id = t.module_id;

COMMIT;