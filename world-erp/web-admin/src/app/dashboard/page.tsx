import { Suspense } from 'react';
import { redirect } from 'next/navigation';
import { getActor } from '@/lib/server/actor';
import { DashboardContent } from '../_components/DashboardContent';
import { DashboardFallback } from '../_components/DashboardFallback';

export const dynamic = 'force-dynamic';

export default async function Dashboard() {
  const actor = await getActor();
  if (!actor) redirect('/?login=1');
  return (
    <Suspense fallback={<DashboardFallback />}>
      <DashboardContent actor={actor as any} />
    </Suspense>
  );
}
