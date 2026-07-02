// Scope resolver — replaces the legacy `scope: 'self'|'department'|'all'`
// field on lib/permissions.ts ROLE_PERMISSIONS and the hardcoded `isHrManager`
// / `isHr` / `isHod` booleans in lib/server/guard.ts + lib/orgScope.ts.
// Source of truth: rbac.roles.scope_kind + rbac.roles.default_staff_level.


import { query } from '../db';
import { canBatch } from './server';

export type ScopeKind = 'self' | 'department' | 'all' | 'subtree';

export interface ActorScope {
  kind: ScopeKind;
  userId: number;
  rbacRoleId: string | null;
  deptGroupId: string | null;
  department: string | null;
  subtreeUserIds: number[];
}

const SUBTREE_MODULES = ['permission-edit-user-subtree', 'rbac-view-matrix'];

export async function getActorScope(
  rbacRoleId: string | null,
  userId: number,
): Promise<ActorScope> {
  const { rows: userRows } = await query<{
    department: string | null;
    dept_group_id: string | null;
  }>(
    `SELECT department, dept_group_id FROM users WHERE id = $1`,
    [userId],
  );
  const department = userRows[0]?.department ?? null;
  const deptGroupId = userRows[0]?.dept_group_id ?? null;

  let kind: ScopeKind = 'self';
  if (rbacRoleId) {
    const { rows: roleRows } = await query<{ scope_kind: ScopeKind }>(
      `SELECT scope_kind FROM rbac.roles WHERE id = $1`,
      [rbacRoleId],
    );
    kind = roleRows[0]?.scope_kind ?? 'self';
  }

  let subtreeUserIds: number[] = [];
  if (kind === 'subtree' && rbacRoleId) {
    subtreeUserIds = await computeSubtree(rbacRoleId, userId);
  }

  return { kind, userId, rbacRoleId, deptGroupId, department, subtreeUserIds };
}

async function computeSubtree(
  rbacRoleId: string,
  userId: number,
): Promise<number[]> {
  const editable = await canBatch(rbacRoleId, SUBTREE_MODULES, 'read');
  if (!editable['permission-edit-user-subtree']) return [];
  const { rows } = await query<{ id: number }>(
    `WITH RECURSIVE down AS (
       SELECT id, reports_to_user_id FROM users WHERE id = $1
       UNION
       SELECT u.id, u.reports_to_user_id
         FROM users u JOIN down d ON u.reports_to_user_id = d.id
     )
     SELECT id FROM down WHERE id <> $1`,
    [userId],
  );
  return rows.map((r: { id: number }) => r.id);
}

export interface ScopeFilter {
  clause: string;
  params: unknown[];
}

export function scopeFilter(
  scope: ActorScope,
  userColumn: string = 'submitter_id',
  groupColumn: string = 'u.dept_group_id',
): ScopeFilter {
  switch (scope.kind) {
    case 'all':
      return { clause: '', params: [] };
    case 'department':
      if (!scope.deptGroupId) {
        throw new Error('Permission denied: department scope requires dept_group_id');
      }
      return {
        clause: `(${groupColumn} = $${1})`,
        params: [scope.deptGroupId],
      };
    case 'subtree':
      if (!scope.subtreeUserIds.length) {
        return { clause: `${userColumn} = $${1}`, params: [scope.userId] };
      }
      return {
        clause: `${userColumn} = ANY($${1})`,
        params: [scope.subtreeUserIds],
      };
    case 'self':
    default:
      return { clause: `${userColumn} = $${1}`, params: [scope.userId] };
  }
}

export async function assertInScope(
  scope: ActorScope,
  targetUserId: number,
): Promise<void> {
  if (scope.kind === 'all') return;
  if (scope.kind === 'self') {
    if (targetUserId !== scope.userId) {
      throw new Error('Permission denied: not in scope');
    }
    return;
  }
  if (scope.kind === 'subtree') {
    if (scope.subtreeUserIds.includes(targetUserId)) return;
    throw new Error('Permission denied: target not in subtree');
  }
  if (scope.kind === 'department') {
    if (!scope.deptGroupId) {
      throw new Error('Permission denied: department scope requires dept_group_id');
    }
    const { rows } = await query<{ dept_group_id: string | null }>(
      `SELECT dept_group_id FROM users WHERE id = $1`,
      [targetUserId],
    );
    const target = rows[0];
    if (!target) throw new Error('Permission denied: target user not found');
    if (target.dept_group_id === scope.deptGroupId) return;
    throw new Error('Permission denied: target not in department');
  }
}
