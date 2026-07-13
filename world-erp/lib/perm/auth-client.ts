// lib/perm/auth-client.ts — client-safe permission check helpers.
// Pure functions, no DB / no 'server-only'. Safe to import from client components.

import { ADMIN_PERM, matchPerm, parseDeptFromPerms, parseLevelFromRoles, parseRoleId, type PermSession } from './grammar';

export function hasPermission(session: PermSession | null, permission: string): boolean {
  if (!session) return false;
  return matchPerm(session.permissions, permission);
}

export interface OwnedResource {
  ownerId: number;
  deptId?: string | null;
}

export function canManageResource(
  session: PermSession | null,
  permission: string,
  resource: OwnedResource,
): boolean {
  if (!session) return false;
  if (session.permissions.includes(ADMIN_PERM)) return true;
  if (!matchPerm(session.permissions, permission)) return false;
  if (resource.ownerId === session.user.id) return true;
  const actorDept = parseDeptFromPerms(session.permissions);
  if (resource.deptId && actorDept && resource.deptId === actorDept) return true;
  return false;
}

export function sessionDept(session: PermSession | null): string | null {
  return session ? parseDeptFromPerms(session.permissions) : null;
}

export function sessionLevel(session: PermSession | null): number {
  if (!session) return 10;
  const lv = parseRoleId(session.user.role)?.level;
  return lv ?? 10;
}

export function sessionRoleName(session: PermSession | null): string | null {
  if (!session) return null;
  return parseRoleId(session.user.role)?.name ?? null;
}

export { ADMIN_PERM };
export { parseLevelFromRoles as levelFromRoles };