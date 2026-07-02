// Inheritance resolution for the permissions matrix.
//
// Linux-style group cascade (matches the brief):
//   For each (role, module, action):
//     1. Direct module ACL via rbac.permissions.
//        - state='allow' → ALLOW (explicit)
//        - state='deny'  → DENY  (explicit)
//        - state='inherit' or no row → walk parent role chain, repeat.
//     2. Group cascade:
//        - Find all groups containing the module (rbac.module_groups).
//        - Walk parent_id to collect ancestor groups.
//        - For each ancestor group, check rbac.role_groups membership.
//        - For each (role, ancestor group, action), look up rbac.group_permissions.
//        - First matching 'allow' → ALLOW (group-cascaded).
//        - First matching 'deny'  → DENY  (group-cascaded).
//     3. Default deny.

import { query } from '../db';

export type Action = 'create' | 'read' | 'update' | 'delete';
export type CellState = 'allow' | 'deny' | 'inherit';
export type EffectiveState = 'allow' | 'deny';
export type Source =
  | 'explicit'
  | 'inherited_from_parent'
  | 'inherited_from_tenant'
  | 'group_cascade'
  | 'default';

export interface ResolvedCell {
  state: EffectiveState;
  source: Source;
  inheritedFrom?: string;
}

export const ACTIONS: Action[] = ['create', 'read', 'update', 'delete'];

interface RoleRow {
  id: string;
  parent_id: string | null;
}

interface PermRow {
  role_id: string;
  module_id: string;
  action: Action;
  state: CellState;
}

interface _GroupPermRow {
  group_id: string;
  state: CellState;
}

const parentCache = new Map<string, string | null>();

async function loadParentMap(): Promise<Map<string, string | null>> {
  if (parentCache.size > 0) return parentCache;
  const { rows } = await query<RoleRow>(`SELECT id, parent_id FROM rbac.roles`);
  for (const r of rows) parentCache.set(r.id, r.parent_id);
  return parentCache;
}

export function clearParentCache() {
  parentCache.clear();
}

/**
 * Resolve one cell via the explicit-permissions table alone.
 */
export async function resolveCell(
  roleId: string,
  moduleId: string,
  action: Action,
  explicit: PermRow[],
): Promise<ResolvedCell> {
  const parents = await loadParentMap();

  const explicitForAction = new Map<string, CellState>();
  for (const row of explicit) {
    if (row.module_id === moduleId && row.action === action) {
      explicitForAction.set(row.role_id, row.state);
    }
  }

  const own = explicitForAction.get(roleId);
  if (own === 'allow' || own === 'deny') {
    return { state: own, source: 'explicit' };
  }

  if (own === 'inherit') {
    let cursor: string | null = parents.get(roleId) ?? null;
    while (cursor !== null) {
      const p = explicitForAction.get(cursor);
      if (p === 'allow' || p === 'deny') {
        return {
          state: p,
          source: 'inherited_from_parent',
          inheritedFrom: cursor,
        };
      }
      cursor = parents.get(cursor) ?? null;
    }
    return { state: 'deny', source: 'default' };
  }

  return { state: 'deny', source: 'default' };
}

/**
 * Full Linux-style resolution (explicit → parent role chain → group cascade).
 */
export async function resolveCellWithGroups(
  roleId: string,
  moduleId: string,
  action: Action,
): Promise<ResolvedCell> {
  const { rows: directRows } = await query<PermRow>(
    `WITH RECURSIVE chain AS (
       SELECT id, parent_id FROM rbac.roles WHERE id = $3
       UNION ALL
       SELECT r.id, r.parent_id FROM rbac.roles r
       JOIN chain c ON r.id = c.parent_id
     )
     SELECT role_id, module_id, action, state::text AS state
       FROM rbac.permissions
      WHERE module_id = $1 AND action = $2
        AND role_id IN (SELECT id FROM rbac.roles WHERE id = $3
                        UNION ALL
                        SELECT id FROM chain)`,
    [moduleId, action, roleId],
  );

  const direct = await resolveCell(roleId, moduleId, action, directRows);
  if (direct.source === 'explicit' || direct.source === 'inherited_from_parent') {
    return direct;
  }

  const cascade = await query<{ group_id: string; state: CellState }>(
    `WITH RECURSIVE
       module_groups AS (
         SELECT g.id, g.parent_id
           FROM rbac.groups g
           JOIN rbac.module_groups mg ON mg.group_id = g.id
          WHERE mg.module_id = $1
         UNION
         SELECT g.id, g.parent_id
           FROM rbac.groups g
           JOIN module_groups m ON m.parent_id = g.id
       ),
       role_groups AS (
         SELECT group_id FROM rbac.role_groups WHERE role_id = $2
       )
     SELECT mg.id AS group_id, gp.state::text AS state
       FROM module_groups mg
       JOIN role_groups rg ON rg.group_id = mg.id
       JOIN rbac.group_permissions gp
         ON gp.group_id = mg.id AND gp.role_id = $2 AND gp.action = $3`,
    [moduleId, roleId, action],
  );

  for (const r of cascade.rows) {
    if (r.state === 'allow') {
      return { state: 'allow', source: 'group_cascade', inheritedFrom: r.group_id };
    }
    if (r.state === 'deny') {
      return { state: 'deny', source: 'group_cascade', inheritedFrom: r.group_id };
    }
  }

  return { state: 'deny', source: 'default' };
}

export async function resolveBatch(
  roleId: string,
  moduleIds: string[],
  action: Action = 'read',
): Promise<Record<string, boolean>> {
  const out: Record<string, boolean> = {};
  await Promise.all(
    moduleIds.map(async (m) => {
      const c = await resolveCellWithGroups(roleId, m, action);
      out[m] = c.state === 'allow';
    }),
  );
  return out;
}

/**
 * Resolve the legacy matrix (no group cascade) — used by the matrix editor view.
 */
export async function resolveMatrix(
  roleIds: string[],
  moduleIds: string[],
): Promise<Record<string, Record<string, Record<Action, ResolvedCell>>>> {
  if (roleIds.length === 0 || moduleIds.length === 0) return {};

  const { rows } = await query<PermRow>(
    `SELECT role_id, module_id, action, state::text AS state
       FROM rbac.permissions
      WHERE role_id = ANY($1) AND module_id = ANY($2)`,
    [roleIds, moduleIds],
  );

  const out: Record<string, Record<string, Record<Action, ResolvedCell>>> = {};
  for (const m of moduleIds) {
    out[m] = {};
    for (const r of roleIds) {
      out[m][r] = {} as Record<Action, ResolvedCell>;
      for (const a of ACTIONS) {
        out[m][r][a] = await resolveCell(r, m, a, rows);
      }
    }
  }
  return out;
}

export function renderShort(cell: Record<Action, ResolvedCell>): string {
  return ACTIONS.map((a) => (cell[a].state === 'allow' ? a[0]!.toUpperCase() : '-')).join('');
}