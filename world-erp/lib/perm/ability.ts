// perm/ability.ts — CASL ability builder.
// Builds a single CASL AppAbility per (user) using the permission grants
// from perm.role_permissions and perm.effective_user_perms.
//
// Object-level conditions are derived from the 4th perm segment (scope):
//   :self    → { owner_field: userId }
//   :dept    → { dept_group_id: <user's dept(s)> }
//   :subtree → { dept_group_id: <user's dept + descendants> }
//   :all     → no row constraint
//
// (Replaces the old perm.acl_rules lookup. Scope is declarative in the
// perm key, so no separate rules table is needed.)

import 'server-only';
import { AbilityBuilder, createMongoAbility, type MongoAbility } from '@casl/ability';
import { query } from '../db';

export type Actions = string;
export type Subjects = string | { [k: string]: any };
export type AppAbility = MongoAbility<[Actions, Subjects]>;
export const createAppAbility = () => createMongoAbility();

export async function loadUserRoleIds(userId: number): Promise<string[]> {
  const { rows } = await query<{ role_id: string }>(
    `SELECT role_id FROM perm.user_roles WHERE user_id = $1`,
    [userId],
  );
  return rows.map((r) => r.role_id);
}

export async function loadRoleGrants(roleIds: string[]): Promise<{ allow: Set<string>; deny: Set<string> }> {
  const allow = new Set<string>();
  const deny = new Set<string>();
  if (roleIds.length === 0) return { allow, deny };
  const { rows } = await query<{ permission_id: string; effect: 'allow' | 'deny' }>(
    `SELECT permission_id, effect FROM perm.role_permissions WHERE role_id = ANY($1)`,
    [roleIds],
  );
  for (const r of rows) {
    if (r.effect === 'allow') allow.add(r.permission_id);
    else deny.add(r.permission_id);
  }
  return { allow, deny };
}

function permScope(perm: string): 'self' | 'dept' | 'subtree' | 'all' | null {
  const parts = perm.split(':');
  if (parts.length < 4) return null;
  const s = parts[3];
  if (s === 'self' || s === 'dept' || s === 'subtree' || s === 'all') return s;
  return null;
}

async function loadUserDepts(userId: number): Promise<{ primary: string | null; all: string[] }> {
  const { rows } = await query<{ role_id: string }>(
    `SELECT role_id FROM perm.user_roles ur
      JOIN perm.roles r ON r.id = ur.role_id
     WHERE ur.user_id = $1 AND r.kind = 'department'`,
    [userId],
  );
  const all = rows.map((r) => r.role_id);
  return { primary: all[0] ?? null, all };
}

async function loadDeptSubtree(deptId: string): Promise<string[]> {
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

export async function buildAbilityFor(userId: number, deptGroupId: string | null): Promise<AppAbility> {
  const { can, cannot, build } = new AbilityBuilder<AppAbility>(createMongoAbility);

  const roleIds = await loadUserRoleIds(userId);
  const { allow, deny } = await loadRoleGrants(roleIds);

  const permissions = Array.from(allow);
  if (roleIds.includes('admin') || permissions.includes('admin:system:bypass:all')) can('manage', 'all');

  for (const p of allow) {
    const domain = p.split(':', 1)[0];
    can(p, domain);
  }
  for (const p of deny) {
    const domain = p.split(':', 1)[0];
    cannot(p, domain);
  }

  // Object-level conditions from scope
  const depts = await loadUserDepts(userId);
  const userDeptIds = depts.all;
  const subtreeDepts = depts.primary ? new Set(await loadDeptSubtree(depts.primary)) : new Set<string>();

  for (const p of allow) {
    const scope = permScope(p);
    if (!scope) continue;
    const domain = p.split(':', 1)[0];
    const subject = domain === 'rbac' ? 'User' : domain.charAt(0).toUpperCase() + domain.slice(1);

    if (scope === 'self') {
      can(p, subject, { submitter_id: userId });
      can(p, subject, { requester_id: userId });
      can(p, subject, { owner_id: userId });
    } else if (scope === 'dept') {
      for (const d of userDeptIds) {
        can(p, subject, { dept_group_id: d });
      }
    } else if (scope === 'subtree') {
      for (const d of subtreeDepts) {
        can(p, subject, { dept_group_id: d });
      }
    }
  }

  return build();
}