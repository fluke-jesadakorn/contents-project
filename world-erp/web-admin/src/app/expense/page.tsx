import { redirect } from 'next/navigation';
import { loadActor } from '@/lib/server/guard';

export const dynamic = 'force-dynamic';

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function ExpenseLanding({ searchParams }: PageProps) {
  const actor = await loadActor();
  if (!actor) redirect('/login');
  const sp = await searchParams;
  const tab = Array.isArray(sp.tab) ? sp.tab[0] : sp.tab;
  if (tab === 'approve' || tab === 'settle') {
    redirect('/my-waybills?scope=queue');
  }
  redirect('/my-waybills?scope=mine');
}