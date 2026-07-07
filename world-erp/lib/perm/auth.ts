// perm/auth.ts — public guard helpers.
//
// Mirrors the user's sketch exactly:
//   hasPermission(session, 'finance:expense:approve')
//   canManageResource(session, 'finance:expense:update', { ownerId, deptGroupId })
//
// Plus thin wrappers for Next.js route handlers (read session from cookie).

import 'server-only';
import { query } from '../db';
import { SESSION_COOKIE, verifySession, sessionFromHeaders, type SessionPayload } from '../server/sessionToken';
import type { PermSession } from './session';

const ADMIN_PERM = 'admin:system:bypass:all';

export function hasPermission(session: PermSession | null, permission: string): boolean {
  if (!session) return false;
  if (session.permissions.includes(ADMIN_PERM)) return true;
  if (session.permissions.includes(permission)) return true;
  const parts = permission.split(':');
  if (parts.length === 3 && session.permissions.includes(permission + ':all')) return true;
  if (parts.length === 4) {
    const three = `${parts[0]}:${parts[1]}:${parts[2]}`;
    if (session.permissions.includes(three)) return true;
  }
  return false;
}

export interface OwnedResource {
  ownerId: number;
  deptGroupId?: string | null;
}

export function canManageResource(
  session: PermSession | null,
  permission: string,
  resource: OwnedResource,
): boolean {
  if (!session) return false;
  if (session.permissions.includes(ADMIN_PERM)) return true;
  if (!session.permissions.includes(permission)) return false;
  if (resource.ownerId === session.user.id) return true;
  if (resource.deptGroupId && resource.deptGroupId === session.user.deptGroupId) return true;
  return false;
}

// ── Session loading ──────────────────────────────────────────────────────────

export interface DecodedPermToken extends PermSession {
  iat: number;
  exp: number;
}

export interface ActivePermSession {
  session: PermSession;
  decoded: DecodedPermToken;
}

export async function loadPermSessionFromHeaders(
  headers: Record<string, string | string[] | undefined> | Headers,
): Promise<ActivePermSession | null> {
  const tok = sessionFromHeaders(headers);
  const payload = await verifySession(tok);
  if (!payload) return null;
  return await hydratePermSession(payload);
}

export async function loadPermSessionFromCookieValue(
  value: string | null | undefined,
): Promise<ActivePermSession | null> {
  const payload = await verifySession(value);
  if (!payload) return null;
  return await hydratePermSession(payload);
}

async function hydratePermSession(payload: SessionPayload): Promise<ActivePermSession | null> {
  const profile = await query<{ fullname: string; role_name: string | null; dept_group_id: string | null; staff_level: number | null; permissions: string[] }>(
    `SELECT u.fullname,
            u.staff_level,
            (SELECT pr.id FROM perm.user_roles ur
              JOIN perm.roles pr ON pr.id = ur.role_id AND pr.kind = 'persona'
             WHERE ur.user_id = u.id
             ORDER BY pr.level ASC NULLS LAST LIMIT 1) AS role_name,
            u.dept_group_id,
            COALESCE(
              (SELECT array_agg(DISTINCT permission_id ORDER BY permission_id)
                 FROM perm.effective_user_perms
                WHERE user_id = u.id),
              ARRAY[]::text[]
            ) AS permissions
       FROM users u
      WHERE u.id = $1`,
    [payload.sub],
  );
  if (profile.rows.length === 0) return null;
  const row = profile.rows[0];
  const session: PermSession = {
    user: {
      id: payload.sub,
      name: row.fullname,
      role: row.role_name ?? 'staff',
    },
    permissions: row.permissions ?? [],
  };
  const decoded: DecodedPermToken = {
    ...session,
    iat: payload.iat,
    exp: payload.exp,
  };
  // Attach dept-group and staff_level for tile-gate checks.
  session.user.deptGroupId = row.dept_group_id;
  session.user.staffLevel = row.staff_level ?? null;
  return { session, decoded };
}

export interface LoadPermSessionResult extends ActivePermSession {
  headers: Record<string, string | string[] | undefined>;
}

export async function loadActivePermSession(
  req: Request,
): Promise<ActivePermSession | null> {
  const headers = req.headers as unknown as Record<string, string | string[] | undefined>;
  return await loadPermSessionFromHeaders(headers);
}

export { SESSION_COOKIE };
