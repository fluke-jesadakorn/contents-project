import { redirect } from 'next/navigation';
import { loadWaybillByOrigin } from '@/lib/server/waybill';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export default async function LookupByExpense({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const wb = await loadWaybillByOrigin('pr', Number(id));
  if (!wb) redirect('/my-waybills');
  redirect(`/waybill/${wb.id}`);
}
