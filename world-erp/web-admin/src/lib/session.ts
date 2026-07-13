// Session helper for the web-admin.
// Reads the HMAC-signed `erp_session` cookie (or `x-erp-session` header). No fallback.
//
// Department and authority level are derived from session perms + role-id via
// lib/perm/grammar — no separate columns/views.

import { cookies } from 'next/headers';
import { query } from './db';
import { SESSION_COOKIE, verifySession } from './server/sessionToken';
import { parseDeptFromPerms, parseRoleId } from '@erp-lib/perm/server';

export interface SessionActor {
  id: number;
  employee_code: string;
  fullname: string;
  role_id: string;            // e.g. 'manager::3'
  role_name: string;          // e.g. 'manager'
  level: number;              // 1..10
  dept_id: string | null;     // e.g. 'finance-2'
  permissions: string[];
}

function tokenFromReq(req?: Request | null): string | null {
  if (req?.headers) {
    const h = req.headers.get('x-erp-session');
    if (h) return h;
  }
  return null;
}

export function sessionFromHeaders(headers: Record<string, string | string[] | undefined>): string | null {
  const raw = headers['x-erp-session'];
  if (typeof raw === 'string' && raw) return raw;
  const cookie = headers['cookie'];
  if (typeof cookie !== 'string') return null;
  const match = cookie.match(/(?:^|;\s*)erp_session=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

export async function getCurrentActor(req?: Request | null): Promise<SessionActor | null> {
  const token = tokenFromReq(req) ?? (await cookies()).get(SESSION_COOKIE)?.value ?? null;
  const payload = await verifySession(token);
  if (!payload) return null;

  const res = await query<{
    id: number;
    employee_code: string;
    fullname: string;
    role_id: string | null;
    permissions: string[];
  }>(
    `SELECT u.id, u.employee_code, u.fullname,
       COALESCE((
         SELECT ur.role_id FROM perm.user_roles ur
          WHERE ur.user_id = u.id
          ORDER BY (CASE WHEN ur.role_id LIKE '%::1' THEN 0
                         WHEN ur.role_id LIKE '%::2' THEN 1
                         WHEN ur.role_id LIKE '%::3' THEN 2
                         WHEN ur.role_id LIKE '%::4' THEN 3
                         WHEN ur.role_id LIKE '%::5' THEN 4
                         ELSE 5 END), ur.granted_at ASC
          LIMIT 1
       ), 'officer::5') AS role_id,
       COALESCE((
         SELECT array_agg(DISTINCT p_id ORDER BY p_id)
           FROM (
             SELECT rp.permission_id AS p_id
               FROM perm.user_roles ur
               JOIN perm.role_permissions rp ON rp.role_id = ur.role_id
              WHERE ur.user_id = u.id
              UNION
             SELECT permission_id AS p_id
               FROM perm.user_permissions
              WHERE user_id = u.id AND revoked_at IS NULL
                AND (ends_at IS NULL OR ends_at > now())
           ) t
       ), ARRAY[]::text[]) AS permissions
      FROM users u
     WHERE u.id = $1`,
    [payload.sub],
  );
  const row = res.rows[0];
  if (!row) return null;
  const parsed = parseRoleId(row.role_id ?? 'officer::5');
  return {
    id: row.id,
    employee_code: row.employee_code,
    fullname: row.fullname,
    role_id: row.role_id ?? 'officer::5',
    role_name: parsed?.name ?? 'officer',
    level: parsed?.level ?? 5,
    dept_id: parseDeptFromPerms(row.permissions ?? []),
    permissions: row.permissions ?? [],
  };
}

// Re-exports for callers that want the grammar helpers.
export { parseDeptFromPerms, parseRoleId } from '@erp-lib/perm/server';
