// Session helper for the web-admin.
// Reads the HMAC-signed `erp_session` cookie (or `x-erp-session` header). No fallback.

import { cookies } from 'next/headers';
import { query } from './db';
import { SESSION_COOKIE, verifySession } from './server/sessionToken';

export interface SessionActor {
  id: number;
  employee_code: string;
  fullname: string;
  department: string | null;
  dept_group_id: string | null;
  dept_group_name: string | null;
  role_name: string;
  rbac_role_id: string | null;
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

  const res = await query(
    `SELECT u.id, u.employee_code, u.fullname, u.department,
            u.dept_group_id, dg.name AS dept_group_name,
            r.name AS role_name, u.rbac_role_id
     FROM users u
     JOIN roles r ON u.role_id = r.id
     LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
     WHERE u.id = $1`,
    [payload.sub],
  );
  return (res.rows[0] as SessionActor) || null;
}