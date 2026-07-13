// GET /api/policy/matrix — payload for the /policy RBAC matrix UI.
// Returns the stage-chain permissions (stage:*:act:all) plus the personas
// in `perm.roles` (kind='persona'), with the current grant set per role.
//
// Behind perm: rbac:matrix:view.

import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActivePermSession, hasPermission, STAGE_PERMS_BY_STAGE } from '@erp-lib/perm/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const STAGE_PERMS: string[] = [
  STAGE_PERMS_BY_STAGE.dept_verification,
  STAGE_PERMS_BY_STAGE.dept_authorization,
  STAGE_PERMS_BY_STAGE.accounting_verification,
  STAGE_PERMS_BY_STAGE.accounting_supervision,
  STAGE_PERMS_BY_STAGE.accounting_authorization,
  STAGE_PERMS_BY_STAGE.disbursement_authorization,
  STAGE_PERMS_BY_STAGE.cfo_authorization,
  STAGE_PERMS_BY_STAGE.ceo_authorization,
];

export async function GET(_req: Request) {
  const out = await loadActivePermSession(_req);
  if (!out) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  if (!hasPermission(out.session, 'rbac:matrix:view:all'))
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const personasRes = await query<{
    id: string;
    display_name: string;
    sort_order: number;
    level: number;
  }>(
    `SELECT id, display_name, sort_order, level
       FROM perm.roles
      WHERE kind = 'persona'
      ORDER BY sort_order, display_name`,
  );

  const grantsRes = await query<{ role_id: string; permission_id: string }>(
    `SELECT role_id, permission_id
       FROM perm.role_permissions
      WHERE permission_id = ANY($1::text[])
        AND effect = 'allow'`,
    [STAGE_PERMS],
  );

  const usersRes = await query<{ role_id: string; count: string }>(
    `SELECT ur.role_id, COUNT(*)::text AS count
       FROM perm.user_roles ur
      WHERE ur.role_id IN (SELECT id FROM perm.roles WHERE kind = 'persona')
      GROUP BY ur.role_id`,
  );

  const grantsByRole: Record<string, Set<string>> = {};
  for (const g of grantsRes.rows) {
    if (!grantsByRole[g.role_id]) grantsByRole[g.role_id] = new Set();
    grantsByRole[g.role_id].add(g.permission_id);
  }
  const userCountByRole: Record<string, number> = {};
  for (const r of usersRes.rows) userCountByRole[r.role_id] = Number(r.count);

  return NextResponse.json({
    stages: STAGE_PERMS.map((id) => {
      const [, stage] = id.match(/^stage:([^:]+):/) ?? [];
      return { perm: id, stage: stage ?? id };
    }),
    personas: personasRes.rows.map((p) => ({
      ...p,
      user_count: userCountByRole[p.id] ?? 0,
      grants: Array.from(grantsByRole[p.id] ?? []),
    })),
  });
}