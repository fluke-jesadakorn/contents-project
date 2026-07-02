// Actor resolution. Reads the signed session and returns the full user row
// (joined with role + dept_group). Used everywhere a session actor is needed.

import { query } from '../db';
import { SESSION_COOKIE, verifySession, type SessionPayload } from './sessionToken';

export interface ActorUser {
  id: number;
  employee_code: string;
  fullname: string;
  department: string | null;
  dept_group_id: string | null;
  dept_group_name: string | null;
  role_name: string;
  rbac_role_id: string | null;
  staff_level: number | null;
}

export async function loadActor(): Promise<ActorUser | null> {
  const sess = await getSessionFromAnySource();
  if (!sess) return null;

  const res = await query<ActorUser>(
    `SELECT u.id, u.employee_code, u.fullname, u.department,
            u.dept_group_id, g.name AS dept_group_name,
            r.name AS role_name, u.rbac_role_id, u.staff_level
     FROM users u
     JOIN roles r ON u.role_id = r.id
     LEFT JOIN rbac.groups g ON g.id = u.dept_group_id
     WHERE u.id = $1`,
    [sess.sub],
  );
  return res.rows[0] || null;
}

export async function getSessionFromAnySource(reqHeaders?: Record<string, string | string[] | undefined>): Promise<SessionPayload | null> {
  const fromHeaders = reqHeaders ? sessionFromHeaders(reqHeaders) : null;
  if (fromHeaders) return verifySession(fromHeaders);
  try {
    const { cookies } = await import('next/headers');
    const c = await cookies();
    const token = c.get(SESSION_COOKIE)?.value ?? null;
    return verifySession(token);
  } catch {
    return null;
  }
}

export function sessionFromHeaders(headers: Record<string, string | string[] | undefined>): string | null {
  const raw = headers['x-erp-session'];
  if (typeof raw === 'string' && raw) return raw;
  const cookie = headers['cookie'];
  if (typeof cookie !== 'string') return null;
  const match = cookie.match(/(?:^|;\s*)erp_session=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}