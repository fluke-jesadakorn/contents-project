import 'server-only';
import { query } from '@/lib/db';
import {
  getEffectiveStaffLevel,
  type StaffLevel,
} from '@/lib/permissions';
import { isAccessAllowed } from '@/lib/access/api.server';
import { getDefaultStaffLevelFromDB } from '@/lib/staffLevel.server';
import { type ActorScope } from '@/lib/rbac/scope';

export interface OrgNode {
  id: number;
  fullname: string;
  employee_code: string;
  role_name: string;
  dept_id: number | null;
  dept_code: string | null;
  dept_name: string | null;
  reports_to_user_id: number | null;
  is_active: boolean;
  level: number;
  staffLevel: StaffLevel;
  children: OrgNode[];
}

export interface UserScopeResult {
  actor: {
    id: number;
    role_name: string;
    department_id: number | null;
    department: string | null;
  };
  rbacRoleId: string | null;
  isHrManager: boolean;
  isHr: boolean;
  isHod: boolean;
  subtreeIds: number[];
}

async function fetchActor(actorId: number) {
  const r = await query(
    `SELECT u.id, u.reports_to_user_id, u.department_id, u.department, u.rbac_role_id, r.name AS role_name
     FROM users u JOIN roles r ON u.role_id=r.id
     WHERE u.id=$1`,
    [actorId]
  );
  if (r.rows.length === 0) throw new Error('Actor not found');
  return r.rows[0];
}

function descendantsFromMap(
  rootId: number,
  reportsTo: Map<number, number[]>
): number[] {
  const out: number[] = [];
  const stack = [rootId];
  while (stack.length) {
    const cur = stack.pop() as number;
    const kids = reportsTo.get(cur) || [];
    for (const k of kids) {
      out.push(k);
      stack.push(k);
    }
  }
  return out;
}

async function loadActorScope(actorId: number): Promise<UserScopeResult> {
  const actor = await fetchActor(actorId);
  const rbacRoleId = actor.rbac_role_id ?? null;

  // Derive role-equality booleans from the matrix (not from role_name strings)
  const [isHrManager, isHr, isHod, subtreeEdit] = await Promise.all([
    isAccessAllowed(rbacRoleId ?? 'L1', 'permission-edit-user-dept', 'update'),
    isAccessAllowed(rbacRoleId ?? 'L1', 'tile-directory', 'read'),
    isAccessAllowed(rbacRoleId ?? 'L1', 'permission-edit-user-subtree', 'update'),
    isAccessAllowed(rbacRoleId ?? 'L1', 'permission-edit-user-subtree', 'update'),
  ]);

  let subtreeIds: number[] = [];
  if (subtreeEdit) {
    const all = await query(
      `SELECT id, reports_to_user_id FROM users WHERE reports_to_user_id IS NOT NULL`
    );
    const map = new Map<number, number[]>();
    for (const row of all.rows) {
      const arr = map.get(row.reports_to_user_id) || [];
      arr.push(row.id);
      map.set(row.reports_to_user_id, arr);
    }
    subtreeIds = descendantsFromMap(actorId, map);
  }
  return {
    actor: {
      id: actor.id,
      role_name: actor.role_name,
      department_id: actor.department_id,
      department: actor.department,
    },
    rbacRoleId,
    isHrManager,
    isHr,
    isHod,
    subtreeIds,
  };
}

export async function resolveActorScope(actorId: number): Promise<UserScopeResult> {
  return loadActorScope(actorId);
}

export async function assertCanEditUser(
  scope: UserScopeResult,
  targetUserId: number
): Promise<void> {
  if (scope.isHrManager) return;
  if (scope.isHod) {
    if (scope.actor.id === targetUserId) {
      throw new Error('You cannot edit your own account');
    }
    if (!scope.subtreeIds.includes(targetUserId)) {
      throw new Error('Outside your chain of command');
    }
    return;
  }
  throw new Error('Permission denied: must be an HR Manager or Head of Department');
}

export async function loadOrgTree(actorId: number): Promise<OrgNode[]> {
  const scope = await loadActorScope(actorId);

  const userRows = await query(
    `SELECT u.id, u.fullname, u.employee_code, u.reports_to_user_id, u.department_id, u.is_active,
            u.staff_level,
            r.name AS role_name,
            d.code AS dept_code, d.name AS dept_name
     FROM users u
     JOIN roles r ON u.role_id=r.id
     LEFT JOIN departments d ON u.department_id=d.id
     ORDER BY u.id`
  );

  const allowedIds = new Set<number>();
  if (scope.isHrManager || scope.isHr) {
    for (const u of userRows.rows) allowedIds.add(u.id);
  } else if (scope.isHod) {
    allowedIds.add(scope.actor.id);
    for (const id of scope.subtreeIds) allowedIds.add(id);
  } else {
    for (const u of userRows.rows) allowedIds.add(u.id);
  }

  const nodes = new Map<number, OrgNode>();
  for (const u of userRows.rows) {
    if (!allowedIds.has(u.id)) continue;
    nodes.set(u.id, {
      id: u.id,
      fullname: u.fullname,
      employee_code: u.employee_code,
      role_name: u.role_name,
      dept_id: u.department_id,
      dept_code: u.dept_code,
      dept_name: u.dept_name,
      reports_to_user_id: u.reports_to_user_id,
      is_active: u.is_active,
      level: 0,
      staffLevel: getEffectiveStaffLevel({
        staff_level: u.staff_level,
        role_name: u.role_name,
      }),
      children: [],
    });
  }

  const ROLE_RANK_LOCAL: Record<string, number> = {
    ceo: 0, cfo: 1, admin: 2,
    hr_manager: 10, accounting_manager: 11, head_of_department: 12,
    account_supervisor: 20, supervisor: 21, account_officer: 22,
    accountant: 30, hr: 31, it: 32, staff: 33,
  };
  const tier = (role: string) => ROLE_RANK_LOCAL[role] ?? 99;

  const sortByHierarchy = (a: OrgNode, b: OrgNode) => {
    const tr = tier(a.role_name) - tier(b.role_name);
    if (tr !== 0) return tr;
    return (a.fullname || '').localeCompare(b.fullname || '');
  };

  for (const node of nodes.values()) {
    if (node.reports_to_user_id && nodes.has(node.reports_to_user_id)) {
      nodes.get(node.reports_to_user_id)!.children.push(node);
    }
  }
  for (const node of nodes.values()) {
    node.children.sort(sortByHierarchy);
  }

  const roots: OrgNode[] = [];
  for (const node of nodes.values()) {
    if (!node.reports_to_user_id || !nodes.has(node.reports_to_user_id)) {
      roots.push(node);
    }
  }
  roots.sort(sortByHierarchy);

  // DFS to assign level (depth from root). Orphans (no reports_to) get level=0.
  const stack: { node: OrgNode; depth: number }[] = roots.map((n) => ({ node: n, depth: 0 }));
  while (stack.length) {
    const { node, depth } = stack.pop() as { node: OrgNode; depth: number };
    node.level = depth;
    for (const child of node.children) {
      stack.push({ node: child, depth: depth + 1 });
    }
  }
  return roots;
}

export async function getUserLevels(): Promise<Map<number, number>> {
  const all = await query(
    `SELECT u.id, u.reports_to_user_id FROM users u WHERE u.reports_to_user_id IS NOT NULL`
  );
  const childrenByParent = new Map<number, number[]>();
  for (const row of all.rows) {
    const arr = childrenByParent.get(row.reports_to_user_id) || [];
    arr.push(row.id);
    childrenByParent.set(row.reports_to_user_id, arr);
  }
  const allUsers = await query(`SELECT id FROM users`);
  const allIds = new Set<number>(allUsers.rows.map((r) => r.id));
  const childOf = (id: number) => {
    for (const [parent, kids] of childrenByParent.entries()) {
      if (kids.includes(id)) return parent;
    }
    return null;
  };

  const levels = new Map<number, number>();
  for (const id of allIds) {
    if (levels.has(id)) continue;
    let depth = 0;
    let cur: number | null = id;
    const seen = new Set<number>();
    while (cur !== null && !levels.has(cur)) {
      if (seen.has(cur)) break;
      seen.add(cur);
      const parent = childOf(cur);
      if (parent === null) {
        levels.set(id, depth);
        break;
      }
      cur = parent;
      depth++;
    }
    if (cur !== null && levels.has(cur)) {
      levels.set(id, depth + (levels.get(cur) ?? 0));
    }
  }
  return levels;
}

export async function getUserStaffLevels(): Promise<Map<number, StaffLevel>> {
  const r = await query(
    `SELECT u.id, u.staff_level, r.name AS role_name
     FROM users u JOIN roles r ON u.role_id=r.id`
  );
  const out = new Map<number, StaffLevel>();
  for (const row of r.rows) {
    let eff = getEffectiveStaffLevel({
      staff_level: row.staff_level,
      role_name: row.role_name,
    });
    if (row.staff_level === null || row.staff_level === undefined) {
      const fromDb = await getDefaultStaffLevelFromDB(row.role_name);
      if (fromDb !== eff) eff = fromDb;
    }
    out.set(row.id, eff);
  }
  return out;
}

export type { ActorScope };
