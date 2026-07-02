import 'server-only';
import { Suspense } from 'react';
import { notFound, redirect } from 'next/navigation';
import { getActor } from '@/lib/server/actor';
import { getDashboardData, listPurchaseRequisitions } from '@/lib/server/queries';
import { GROUP_LABEL, type TileGroup } from '@/components/tile-config';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import { ROOT_CRUMB, groupCrumb } from '@/components/breadcrumbs';
import { GroupHub } from './GroupHub';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: Promise<{ slug: string }>;
}

function isGroup(s: string | undefined): s is TileGroup {
  return !!s && s in GROUP_LABEL;
}

export default async function GroupPageRoute({ params }: PageProps) {
  const { slug } = await params;
  if (!isGroup(slug)) notFound();

  const actor = await getActor();
  if (!actor) redirect('/?login=1');

  const data = await getDashboardData();
  const prsRes = await listPurchaseRequisitions(actor.id).catch(() => ({ success: false as const, prs: [] }));
  const prs = (prsRes.success ? prsRes.prs : []) as any[];

  return (
    <>
      <BreadcrumbSetter
        crumbs={[ROOT_CRUMB, groupCrumb(slug)]}
      />
      <Suspense fallback={null}>
        <GroupHub
          actor={actor as any}
          group={slug}
          users={(data.users || []) as any[]}
          prs={prs}
        />
      </Suspense>
    </>
  );
}