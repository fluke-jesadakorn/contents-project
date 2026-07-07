// lib/perm/scope.ts — derive actor visibility scope from session permissions.
//
// Replaces lib/rbac/scope.ts (which read rbac.roles.scope_kind + rbac.role_groups).
//
// Scope kinds:
//   - 'all'        : admin / system bypass
//   - 'department' : same-dept only
//   - 'subtree'    : self + all reports-to descendants
//   - 'self'       : just self
//
// Derived purely from session.permissions + a recursive CTE for subtree.

import 'server-only';
import { query } from '../db';

export type ScopeKind = 'self' | 'department' | 'all' | 'subtree';

export interface ActorScope {
  kind: ScopeKind;
  userId: number;
  deptGroupId: string | null;
  subtreeUserIds: number[];
}

const SYSTEM_PERMS = new Set(['admin:system:bypass:all', 'rbac:audit:view:all']);

function permScope(perm: string): 'self' | 'dept' | 'subtree' | 'all' | null {
  const parts = perm.split(':');
  if (parts.length < 4) return null;
  const s = parts[3];
  if (s === 'self' || s === 'dept' || s === 'subtree' || s === 'all') return s;
  return null;
}

export async function getActorScope(
  permSet: Set<string>,
  userId: number,
): Promise<ActorScope> {
  const u = await query<{ dept_group_id: string | null }>(
    `SELECT dept_group_id FROM users WHERE id = $1`,
    [userId],
  );
  const deptGroupId = u.rows[0]?.dept_group_id ?? null;

  let kind: ScopeKind = 'self';
  let hasAll = false;
  let hasSubtree = false;
  let hasDept = false;

  for (const perm of permSet) {
    if (SYSTEM_PERMS.has(perm)) {
      hasAll = true;
      break;
    }
    const s = permScope(perm);
    if (s === 'all') {
      hasAll = true;
    } else if (s === 'subtree') {
      hasSubtree = true;
    } else if (s === 'dept') {
      hasDept = true;
    }
  }

  if (hasAll) kind = 'all';
  else if (hasSubtree) kind = 'subtree';
  else if (hasDept) kind = 'department';
  else kind = 'self';

  let subtreeUserIds: number[] = [];
  if (kind === 'subtree') {
    subtreeUserIds = await computeSubtree(userId);
  }

  return { kind, userId, deptGroupId, subtreeUserIds };
}

async function computeSubtree(userId: number): Promise<number[]> {
  const r = await query<{ id: number }>(
    `WITH RECURSIVE down AS (
       SELECT id, reports_to_user_id FROM users WHERE id = $1
       UNION
       SELECT u.id, u.reports_to_user_id
         FROM users u JOIN down d ON u.reports_to_user_id = d.id
     )
     SELECT id FROM down WHERE id <> $1`,
    [userId],
  );
  return r.rows.map((row) => row.id);
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
        return { clause: `${userColumn} = $${1}`, params: [scope.userId] };
      }
      return { clause: `(${groupColumn} = $${1})`, params: [scope.deptGroupId] };
    case 'subtree':
      if (!scope.subtreeUserIds.length) {
        return { clause: `${userColumn} = $${1}`, params: [scope.userId] };
      }
      return { clause: `${userColumn} = ANY($${1})`, params: [scope.subtreeUserIds] };
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