import { Suspense } from 'react';
import { getActor } from '@/lib/server/actor';
import { canPerformAction } from '@/lib/permissions';
import { isAccessAllowed } from '@/lib/access/api.server';
import { SignInPanel } from '@/components/SignInPanel';
import { HomeTilesFetcher } from './_components/HomeTilesFetcher';
import { HomeTilesFallback } from './_components/HomeTilesFallback';

export const dynamic = 'force-dynamic';

export default async function TilesPage() {
  const actor = await getActor();
  if (!actor) {
    return <SignInPanel />;
  }

  const role = actor.role_name as any;
  const canViewPolicy = canPerformAction(role, 'view_policy');
  const canViewExec = canPerformAction(role, 'view_executive_report');
  const canViewHub = actor.rbac_role_id
    ? await isAccessAllowed(actor.rbac_role_id, 'view-hub', 'read')
    : false;

  return (
    <Suspense fallback={<HomeTilesFallback />}>
      <HomeTilesFetcher
        actor={actor as any}
        canViewHub={canViewHub}
        canViewPolicy={canViewPolicy}
        canViewExec={canViewExec}
      />
    </Suspense>
  );
}
