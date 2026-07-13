// /policy — RBAC policy management surface.
// Renders the stage-chain permission matrix. The chain order is sourced from
// STAGE_ORDER (single source of truth). Edits write via PUT
// /api/perm/roles/[id]/permissions (audit-logged server-side).
//
// Behind perm: rbac:matrix:view (gated server-side via session).

import 'server-only';
import { headers } from 'next/headers';
import { loadActivePermSession, hasPermission, STAGE_TO_PERM } from '@erp-lib/perm/server';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import { ROOT_CRUMB } from '@/components/breadcrumbs';
import { PolicyMatrixPage } from '@/components/PolicyMatrixPage';
import { NoPermissionView } from '@/components/NoPermissionView';
import { Bilingual } from '@/components/i18n/Bilingual';
import type { BilingualText } from '@erp-lib/i18n/types';
import { query } from '@/lib/db';

interface Persona {
  id: string;
  display_name: string;
  sort_order: number;
  level: number;
  user_count: number;
  grants: string[];
}

interface Stage {
  perm: string;
  stage: string;
}

export const dynamic = 'force-dynamic';

async function loadMatrix(): Promise<{ stages: Stage[]; personas: Persona[] }> {
  const STAGE_PERMS: string[] = [
    STAGE_TO_PERM.dept_verification,
    STAGE_TO_PERM.dept_authorization,
    STAGE_TO_PERM.accounting_verification,
    STAGE_TO_PERM.accounting_supervision,
    STAGE_TO_PERM.accounting_authorization,
    STAGE_TO_PERM.disbursement_authorization,
    STAGE_TO_PERM.cfo_authorization,
    STAGE_TO_PERM.ceo_authorization,
  ];

  const personasRes = await query<{
    id: string;
    display_name: string;
    display_name_th: string | null;
    display_name_de: string | null;
    sort_order: number;
    level: number;
  }>(
    `SELECT id, display_name, display_name_th, display_name_de, sort_order, level
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
       JOIN perm.roles r ON r.id = ur.role_id
      WHERE r.kind = 'persona'
      GROUP BY ur.role_id`,
  );

  const grantsByRole: Record<string, Set<string>> = {};
  for (const g of grantsRes.rows) {
    if (!grantsByRole[g.role_id]) grantsByRole[g.role_id] = new Set();
    grantsByRole[g.role_id].add(g.permission_id);
  }
  const userCountByRole: Record<string, number> = {};
  for (const r of usersRes.rows) userCountByRole[r.role_id] = Number(r.count);

  return {
    stages: STAGE_PERMS.map((id) => {
      const [, stage] = id.match(/^stage:([^:]+):/) ?? [];
      return { perm: id, stage: stage ?? id };
    }),
    personas: personasRes.rows.map((p) => ({
      ...p,
      user_count: userCountByRole[p.id] ?? 0,
      grants: Array.from(grantsByRole[p.id] ?? []),
    })),
  };
}

const B_POLICY_TITLE: BilingualText = { en: 'RBAC Policy', th: 'นโยบาย RBAC', de: 'RBAC-Richtlinie' };
const B_POLICY_SUBTITLE: BilingualText = {
  en: 'Stage chain matrix - persona x stage grants',
  th: 'เมทริกซ์สายขั้นตอน - สิทธิ์ของบุคคล x ขั้นตอน',
  de: 'Stufenkette-Matrix - Persona x Stufen-Berechtigungen',
};

export default async function PolicyPage() {
  const h = await headers();
  const req = new Request('http://internal/policy', { headers: h as unknown as HeadersInit });
  const out = await loadActivePermSession(req);

  if (!out) {
    return (
      <>
        <BreadcrumbSetter crumbs={[ROOT_CRUMB, { label: <Bilingual {...B_POLICY_TITLE} /> }]} />
        <PageLayout title={<Bilingual {...B_POLICY_TITLE} />} subtitle={<Bilingual {...B_POLICY_SUBTITLE} />}>
          <NoPermissionView
            kind="locked"
            actor={null}
            attemptedPath="/policy"
            reason="Sign in to view this page."
          />
        </PageLayout>
      </>
    );
  }

  if (!hasPermission(out.session, 'rbac:matrix:view:all')) {
    return (
      <>
        <BreadcrumbSetter crumbs={[ROOT_CRUMB, { label: <Bilingual {...B_POLICY_TITLE} /> }]} />
        <PageLayout title={<Bilingual {...B_POLICY_TITLE} />} subtitle={<Bilingual {...B_POLICY_SUBTITLE} />}>
          <NoPermissionView
            kind="locked"
            actor={out.session.user as any}
            attemptedPath="/policy"
            reason="rbac:matrix:view required."
          />
        </PageLayout>
      </>
    );
  }

  const matrix = await loadMatrix();
  const canEdit = hasPermission(out.session, 'rbac:matrix:edit:all');
  const actor = out.session.user;

  return (
    <>
      <BreadcrumbSetter crumbs={[ROOT_CRUMB, { label: <Bilingual {...B_POLICY_TITLE} /> }]} />
      <PageLayout title={<Bilingual {...B_POLICY_TITLE} />} subtitle={<Bilingual {...B_POLICY_SUBTITLE} />}>
        <PolicyMatrixPage
          stages={matrix.stages}
          personas={matrix.personas}
          canEdit={canEdit}
          actorName={(actor as any)?.fullname ?? (actor as any)?.id?.toString() ?? ''}
        />
      </PageLayout>
    </>
  );
}
