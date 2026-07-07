// lib/perm/grants.ts — CRUD for perm.user_permissions and rbac.perm_grants.
//
// Two persistence paths for direct user→perm assignment:
//   1. PERMANENT  → perm.user_permissions (no ends_at; survives sessions)
//   2. TEMPORARY  → rbac.perm_grants     (ends_at mandatory; revokes on expiry)
//
// Combined view perm.effective_user_perms (see 0035_user_permissions.sql)
// unions role perms + active grants + permanent perms.
//
// SCOPE NOTE: NEITHER grants NOR permanent user perms influence tile view access.
// As of 0031_tile_access_gates.sql, the tile gate is purely
// (user.staff_level <= tile.required_level) AND (user.dept_group_id = tile.required_dept_id).
// No perm (role, grant, permanent, or admin bypass) is consulted for tile visibility.
// Direct assignments are still used for mutation perms (e.g. head-of-department
// approvals, acting-as another role's workflow responsibilities, ad-hoc CFO
// review rights) and for the user deactivation cascade in /api/users/[id].
//
// Do NOT use these helpers to grant access to tiles. Edit perm.tiles.required_*
// instead via /tiles.

import 'server-only';
import { query } from '../db';

export type GrantSource = 'manual' | 'seed' | 'bulk' | 'access_request';

export interface PermGrant {
  id: number;
  user_id: number;
  permission_id: string;
  starts_at: string;
  ends_at: string;
  granted_by: string;
  reason: string | null;
  source: GrantSource;
  revoked_at: string | null;
  revoked_by: string | null;
}

export interface CreateGrantInput {
  user_id: number;
  permission_id: string;
  starts_at?: string;
  ends_at: string;
  granted_by: string;
  reason?: string;
  source?: GrantSource;
}

export async function createGrant(input: CreateGrantInput): Promise<PermGrant> {
  const { rows } = await query<PermGrant>(
    `INSERT INTO rbac.perm_grants
       (user_id, permission_id, starts_at, ends_at, granted_by, reason, source)
     VALUES ($1, $2, COALESCE($3, now()), $4, $5, $6, COALESCE($7, 'manual'))
     RETURNING *`,
    [
      input.user_id,
      input.permission_id,
      input.starts_at ?? null,
      input.ends_at,
      input.granted_by,
      input.reason ?? null,
      input.source ?? null,
    ],
  );
  return rows[0];
}

export async function revokeGrant(grantId: number, revokedBy: string): Promise<void> {
  await query(
    `UPDATE rbac.perm_grants
        SET revoked_at = now(), revoked_by = $2
      WHERE id = $1 AND revoked_at IS NULL`,
    [grantId, revokedBy],
  );
}

export async function listUserGrants(
  userId: number,
  options: { activeOnly?: boolean } = {},
): Promise<PermGrant[]> {
  const where = options.activeOnly
    ? 'WHERE user_id = $1 AND revoked_at IS NULL AND now() BETWEEN starts_at AND ends_at'
    : 'WHERE user_id = $1';
  const { rows } = await query<PermGrant>(
    `SELECT * FROM rbac.perm_grants ${where} ORDER BY starts_at DESC`,
    [userId],
  );
  return rows;
}

export async function listActiveGrantsForPerm(permissionId: string): Promise<PermGrant[]> {
  const { rows } = await query<PermGrant>(
    `SELECT * FROM rbac.perm_grants
      WHERE permission_id = $1
        AND revoked_at IS NULL
        AND now() BETWEEN starts_at AND ends_at
      ORDER BY ends_at ASC`,
    [permissionId],
  );
  return rows;
}

export async function expireOverdueGrants(): Promise<number> {
  const { rowCount } = await query(
    `UPDATE rbac.perm_grants
        SET revoked_at = now(), revoked_by = 'system.expiry'
      WHERE ends_at < now() AND revoked_at IS NULL`,
  );
  return rowCount ?? 0;
}

export interface ActingBundleInput {
  user_id: number;
  role_id: string;
  ends_at: string;
  granted_by: string;
  reason?: string;
}

export async function grantActingBundle(input: ActingBundleInput): Promise<string[]> {
  const { rows: perms } = await query<{ permission_id: string }>(
    `SELECT permission_id FROM perm.role_permissions
      WHERE role_id = $1 AND effect = 'allow'`,
    [input.role_id],
  );
  if (perms.length === 0) return [];
  for (const p of perms) {
    await createGrant({
      user_id: input.user_id,
      permission_id: p.permission_id,
      ends_at: input.ends_at,
      granted_by: input.granted_by,
      reason: input.reason ?? `Acting as ${input.role_id}`,
      source: 'manual',
    });
  }
  return perms.map((p) => p.permission_id);
}

// ── Permanent direct user perms (perm.user_permissions) ──────────────────────

export interface UserPerm {
  id: number;
  user_id: number;
  permission_id: string;
  granted_by: string;
  reason: string | null;
  granted_at: string;
  revoked_at: string | null;
  revoked_by: string | null;
}

export async function listActiveUserPerms(userId: number): Promise<UserPerm[]> {
  const { rows } = await query<UserPerm>(
    `SELECT id, user_id, permission_id, granted_by, reason, granted_at, revoked_at, revoked_by
       FROM perm.user_permissions
      WHERE user_id = $1 AND revoked_at IS NULL
      ORDER BY granted_at DESC`,
    [userId],
  );
  return rows;
}

export async function revokeUserPerm(rowId: number, revokedBy: string): Promise<void> {
  await query(
    `UPDATE perm.user_permissions
        SET revoked_at = now(), revoked_by = $2
      WHERE id = $1 AND revoked_at IS NULL`,
    [rowId, revokedBy],
  );
}

export interface UpsertUserPermsInput {
  user_id: number;
  desired_perm_ids: string[]; // final allow set; absent rows are revoked, new rows inserted
  granted_by: string;
  reason?: string;
}

export async function setUserPermanentPerms(input: UpsertUserPermsInput): Promise<{
  added: string[];
  removed: number;
}> {
  const cur = await listActiveUserPerms(input.user_id);
  const before = new Set(cur.map((r) => r.permission_id));
  const after = new Set(input.desired_perm_ids);

  const added = [...after].filter((p) => !before.has(p));
  const removed = [...before].filter((p) => !after.has(p));
  const removedCount = removed.length;

  if (removedCount > 0) {
    await query(
      `UPDATE perm.user_permissions
          SET revoked_at = now(), revoked_by = $2
        WHERE user_id = $1 AND permission_id = ANY($3::text[]) AND revoked_at IS NULL`,
      [input.user_id, input.granted_by, removed],
    );
  }
  for (const pid of added) {
    await query(
      `INSERT INTO perm.user_permissions (user_id, permission_id, granted_by, reason)
       VALUES ($1, $2, $3, $4)`,
      [input.user_id, pid, input.granted_by, input.reason ?? null],
    );
  }
  return { added, removed: removedCount };
}

export interface UpsertUserGrantsInput {
  user_id: number;
  desired_perm_ids: string[];
  ends_at: string;
  granted_by: string;
  reason?: string;
}

export async function setUserTemporaryGrants(input: UpsertUserGrantsInput): Promise<{
  added: string[];
  removed: number;
}> {
  const cur = await listUserGrants(input.user_id, { activeOnly: true });
  const before = new Set(cur.map((g) => g.permission_id));
  const after = new Set(input.desired_perm_ids);

  const added = [...after].filter((p) => !before.has(p));
  const removed = [...before].filter((p) => !after.has(p));
  const removedCount = removed.length;

  for (const g of cur) {
    if (removed.includes(g.permission_id)) {
      await revokeGrant(g.id, input.granted_by);
    }
  }
  for (const pid of added) {
    await createGrant({
      user_id: input.user_id,
      permission_id: pid,
      ends_at: input.ends_at,
      granted_by: input.granted_by,
      reason: input.reason ?? 'direct assign from /roles UI',
      source: 'manual',
    });
  }
  return { added, removed: removedCount };
}
