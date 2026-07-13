import 'server-only';
import { cache } from 'react';
import { query } from '../db';
import {
  verifySession,
  sessionFromHeaders,
  type SessionPayload,
} from '../server/sessionToken';
import type { PolicyActor, PolicyContext, PolicyResource } from './ast';
import { parseRoleId } from '../perm/grammar';

export type { PolicyActor, PolicyContext, PolicyResource } from './ast';

export async function loadSubtreeIds(deptId: string | null): Promise<string[]> {
  if (!deptId) return [];
  const { rows } = await query<{ id: string }>(
    `WITH RECURSIVE tree AS (
       SELECT id FROM perm.roles WHERE id = $1
       UNION
       SELECT child.id FROM perm.roles child
         JOIN tree t ON child.parent_role_id = t.id
     )
     SELECT id FROM tree`,
    [deptId],
  );
  return rows.map((r) => r.id);
}

async function hydrate(payload: SessionPayload): Promise<PolicyActor | null> {
  const sess = await query<{ revoked_at: string | null; expires_at: string }>(
    `SELECT revoked_at, expires_at FROM auth.sessions WHERE id = $1`,
    [payload.id],
  );
  if (sess.rows.length === 0) return null;
  if (sess.rows[0].revoked_at !== null) return null;
  if (new Date(sess.rows[0].expires_at).getTime() < Date.now()) return null;

  void query(`UPDATE auth.sessions SET last_seen_at = now() WHERE id = $1`, [payload.id]).catch(
    () => {},
  );

  const profile = await query<{
    fullname: string;
    role_id: string | null;
    dept_perm: string | null;
    permissions: string[];
  }>(
    `SELECT u.fullname,
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
       (SELECT up.permission_id FROM perm.user_permissions up
          WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
            AND up.revoked_at IS NULL
            AND (up.ends_at IS NULL OR up.ends_at > now())
          ORDER BY up.permission_id LIMIT 1) AS dept_perm,
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
  if (profile.rows.length === 0) return null;
  const row = profile.rows[0];
  const permissions = new Set(row.permissions ?? []);
  const parsed = parseRoleId(row.role_id ?? 'officer::5');
  const deptId = row.dept_perm
    ? row.dept_perm.replace(/^user:dept:/, '').replace(/::allow$/, '')
    : null;
  const deptSubtreeIds = await loadSubtreeIds(deptId);
  return {
    id: payload.sub,
    roleName: parsed?.name ?? 'officer',
    roleId: row.role_id ?? 'officer::5',
    level: parsed?.level ?? 5,
    deptGroupId: deptId,
    deptSubtreeIds,
    permissions,
    bypassAll: permissions.has('admin:system:bypass::allow'),
  };
}

const cachedHydrate = cache(async (payload: SessionPayload) => hydrate(payload));

export async function buildPolicyContext(
  payload: SessionPayload | null,
): Promise<PolicyContext | null> {
  if (!payload) return null;
  const actor = await cachedHydrate(payload);
  if (!actor) return null;
  return { actor };
}

export async function buildPolicyContextFromHeaders(
  headers: Record<string, string | string[] | undefined> | Headers,
): Promise<PolicyContext | null> {
  const tok = sessionFromHeaders(headers);
  const payload = await verifySession(tok);
  if (!payload) return null;
  return buildPolicyContext(payload);
}

export async function buildPolicyContextFromCookieValue(
  value: string | null | undefined,
): Promise<PolicyContext | null> {
  const payload = await verifySession(value);
  if (!payload) return null;
  return buildPolicyContext(payload);
}