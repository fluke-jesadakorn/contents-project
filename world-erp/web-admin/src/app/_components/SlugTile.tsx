import 'server-only';
import {
  getDashboardData,
  getLedgerEntries,
  getExecutiveReport,
  listApprovalPolicies,
  listPurchaseRequisitions,
  listPurchaseOrders,
} from '@/lib/server/queries';
import { getTileBySlug } from '@/lib/rbac/server';
import { evaluateTile } from '@/components/tileAccess';
import { tileFromRow } from '@/components/tile-config';
import { TilePage } from '@/components/TilePage';
import { OrgChartHR } from '@/components/workspaces/OrgChartHR';
import { NoPermissionView } from '@/components/NoPermissionView';
import { PageLayout } from '@/components/PageLayout';
import { ROOT_CRUMB, buildCrumbs } from '@/components/breadcrumbs';

interface Props {
  slug: string;
  actor: {
    id: number;
    role_name: string;
    fullname?: string;
    rbac_role_id?: string | null;
    [k: string]: unknown;
  };
}

export async function SlugTile({ slug, actor }: Props) {
  const data = await getDashboardData();
  const ledger = await getLedgerEntries(actor.id).catch(() => ({ success: false as const, journals: [] }));
  const exec = await getExecutiveReport(actor.id).catch(() => ({ success: false as const, report: null }));
  const policiesRes = await listApprovalPolicies(actor.id).catch(() => ({ success: false as const, policies: [] }));
  const prsRes = await listPurchaseRequisitions(actor.id);
  const posRes = await listPurchaseOrders(actor.id);

  const expenses = (data.expenses || []) as any[];
  const prs = (prsRes.success ? prsRes.prs : []) as any[];
  const pos = (posRes.success ? posRes.pos : []) as any[];
  const policies = (policiesRes.success ? policiesRes.policies : []) as any[];

  const tileRow = await getTileBySlug(slug);
  if (!tileRow) {
    return (
      <PageLayout
        breadcrumbs={[ROOT_CRUMB, { label: `/${slug}` }]}
        title="Not found"
        subtitle="The feature you are looking for does not exist or has been renamed."
      >
        <NoPermissionView
          kind="not_found"
          actor={actor as any}
          attemptedPath={`/${slug}`}
          reason="The feature you are looking for does not exist or has been renamed."
        />
      </PageLayout>
    );
  }

  const tile = tileFromRow({
    id: tileRow.id,
    display_name: tileRow.display_name,
    subtitle: tileRow.subtitle,
    icon: tileRow.icon,
    accent: tileRow.accent,
    group_name: tileRow.group_name,
    sub_view: tileRow.sub_view,
    href: tileRow.href,
    module_id: tileRow.module_id,
    request_target: tileRow.request_target,
    sort_order: tileRow.sort_order,
  });

  const access = await evaluateTile(tile, actor);
  if (access.state === 'locked') {
    return (
      <PageLayout
        breadcrumbs={buildCrumbs({ group: tile.group, tile, record: { label: 'LOCKED' } })}
        title={tile.display_name}
        subtitle="Access restricted"
      >
        <NoPermissionView
          kind="locked"
          actor={actor as any}
          tile={tile as any}
          access={access as any}
          attemptedPath={`/${slug}`}
        />
      </PageLayout>
    );
  }

  if (slug === 'org-chart') {
    return (
      <PageLayout
        breadcrumbs={buildCrumbs({ group: tile.group, tile })}
        title={tile.display_name}
        subtitle={tile.subtitle}
      >
        <OrgChartHR currentUser={actor as any} view="people" />
      </PageLayout>
    );
  }

  if (slug === 'permissions') {
    return (
      <PageLayout
        breadcrumbs={buildCrumbs({ group: tile.group, tile })}
        title={tile.display_name}
        subtitle={tile.subtitle}
      >
        <OrgChartHR currentUser={actor as any} view="permissions" scopeTilesOnly />
      </PageLayout>
    );
  }

  return (
    <TilePage
      tile={tile as any}
      currentUser={actor as any}
      users={(data.users || []) as any[]}
      coa={(data.coa || []) as any[]}
      expenses={expenses}
      journals={(ledger.success ? ledger.journals : []) as any[]}
      execReport={exec.success ? exec.report : null}
      policies={policies}
      prs={prs}
      pos={pos}
    />
  );
}
