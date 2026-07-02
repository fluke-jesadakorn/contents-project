import { query } from '@/lib/db';
import type { RoleName } from '@/lib/permissions';
import { isAccessAllowed } from '@/lib/access/api.server';

type RbacAction = 'create' | 'read' | 'update' | 'delete';

/**
 * Server-side role assertion helper. Throws when actor's role is not in the
 * allowed list. Shared between actions.ts and actions-hr.ts — kept in a
 * plain (non-'use server') module so it is NOT exposed as an RPC endpoint.
 *
 * When `opts.rbacSection` is provided, also consults the DB-driven RBAC
 * matrix via users.rbac_role_id. Users without a linked rbac_role_id skip
 * the matrix check silently (preserves prior behavior).
 */
export async function assertRole(
  actorId: number,
  allowedRoles: RoleName[],
  opts?: { rbacSection?: string; rbacAction?: RbacAction }
): Promise<string> {
  const res = await query(
    'SELECT r.name, u.rbac_role_id FROM users u JOIN roles r ON u.role_id = r.id WHERE u.id = $1',
    [actorId]
  );
  if (res.rows.length === 0) {
    throw new Error('User not found');
  }
  const role = res.rows[0].name as string;
  if (!allowedRoles.includes(role as RoleName)) {
    throw new Error(
      `Permission denied: role "${role}" is not authorized to perform this action (required: ${allowedRoles.join(', ')})`
    );
  }
  if (opts?.rbacSection && opts.rbacAction) {
    const rbacRoleId = res.rows[0].rbac_role_id as string | null;
    if (rbacRoleId) {
      const allowed = await isAccessAllowed(rbacRoleId, opts.rbacSection, opts.rbacAction);
      if (!allowed) {
        throw new Error(
          `Permission denied: access matrix disallows ${opts.rbacAction} on ${opts.rbacSection} for role ${rbacRoleId}`
        );
      }
    }
  }
  return role;
}
