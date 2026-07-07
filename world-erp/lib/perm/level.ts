// lib/perm/level.ts — derive a user's effective level from granted perms.
//
// New model: authority level is encoded as `rbac:level:grant:min:N:all` perms.
// Lower N = higher authority (1 = CEO, 10 = lowest / read-only).
// A user's effective level = MIN(N) of all `:min:N` perms they hold.
// "Highest authority wins" — same semantics as before.
//
// Replaces the legacy rbac.roles.default_staff_level + users.staff_level
// cascade. perm.roles.level column still exists for now (legacy readers).

import 'server-only';
import { query } from '../db';

export type Level = number;

const LEVEL_PERM_RE = /^rbac:level:grant:min:(\d+):all$/;

function extractMinLevel(permId: string): number | null {
  const m = LEVEL_PERM_RE.exec(permId);
  return m ? parseInt(m[1], 10) : null;
}

export async function getEffectiveLevel(userId: number): Promise<Level> {
  const { rows } = await query<{ effective_level: number | null }>(
    `SELECT MIN(
       CAST(regexp_replace(rp.permission_id, '^rbac:level:grant:min:(\\d+):all$', '\\1') AS int)
     ) AS effective_level
       FROM perm.user_roles ur
       JOIN perm.role_permissions rp ON rp.role_id = ur.role_id
      WHERE ur.user_id = $1
        AND rp.effect = 'allow'
        AND rp.permission_id ~ '^rbac:level:grant:min:\\d+:all$'`,
    [userId],
  );
  return rows[0]?.effective_level ?? 10;
}

export async function getEffectiveLevels(
  userIds: number[],
): Promise<Map<number, Level>> {
  if (userIds.length === 0) return new Map();
  const { rows } = await query<{ user_id: number; effective_level: number | null }>(
    `SELECT ur.user_id,
            MIN(
              CAST(regexp_replace(rp.permission_id, '^rbac:level:grant:min:(\\d+):all$', '\\1') AS int)
            ) AS effective_level
       FROM perm.user_roles ur
       JOIN perm.role_permissions rp ON rp.role_id = ur.role_id
      WHERE ur.user_id = ANY($1::int[])
        AND rp.effect = 'allow'
        AND rp.permission_id ~ '^rbac:level:grant:min:\\d+:all$'
      GROUP BY ur.user_id`,
    [userIds],
  );
  const m = new Map<number, Level>();
  for (const r of rows) m.set(r.user_id, r.effective_level ?? 10);
  return m;
}