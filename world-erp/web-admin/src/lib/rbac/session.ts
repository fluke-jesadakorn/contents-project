// Browser/server session helpers. Re-export from @erp-lib.

import 'server-only';
import { SESSION_COOKIE, verifySession, type SessionPayload } from '@/lib/server/sessionToken';

export type { SessionPayload };

export async function getSessionFromCookies(): Promise<SessionPayload | null> {
  const { cookies } = await import('next/headers');
  const c = await cookies();
  const token = c.get(SESSION_COOKIE)?.value;
  return verifySession(token);
}

export function unauthorized(): Response {
  return new Response(JSON.stringify({ error: 'unauthorized' }), {
    status: 401,
    headers: { 'content-type': 'application/json' },
  });
}

export function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'forbidden' }), {
    status: 403,
    headers: { 'content-type': 'application/json' },
  });
}

export async function requireSession(): Promise<SessionPayload | Response> {
  const s = await getSessionFromCookies();
  return s ?? unauthorized();
}

export function isAdmin(role: string | undefined | null): boolean {
  return role === 'it' || role === 'admin';
}

export async function isAdminMatrix(rbacRoleId: string | null): Promise<boolean> {
  if (!rbacRoleId) return false;
  const { isAccessAllowed } = await import('@/lib/access/api.server');
  return isAccessAllowed(rbacRoleId, 'rbac-admin', 'update');
}

export async function requireAdmin(): Promise<SessionPayload | Response> {
  const s = await getSessionFromCookies();
  if (!s) return unauthorized();
  if (isAdmin(s.role) || (await isAdminMatrix(s.rbacRoleId))) return s;
  return forbidden();
}

export async function requireModuleAccess(
  moduleId: string,
  action: 'create' | 'read' | 'update' | 'delete',
): Promise<SessionPayload | Response> {
  const s = await getSessionFromCookies();
  if (!s) return unauthorized();
  if (!s.rbacRoleId) return forbidden();
  const { isAccessAllowed } = await import('@/lib/access/api.server');
  const allow = await isAccessAllowed(s.rbacRoleId, moduleId, action);
  if (!allow) return forbidden();
  return s;
}