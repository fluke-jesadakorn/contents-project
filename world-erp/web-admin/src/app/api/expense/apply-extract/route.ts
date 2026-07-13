import { NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';

export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });

  let body: any = {};
  try { body = await req.json(); } catch {}
  const { waybillId, fields } = body;
  if (!fields) return NextResponse.json({ ok: false, error: 'fields required' }, { status: 400 });

  const { startExpenseDraft, saveDraftExpense } = await import('@/app/actions');
  let id = waybillId as string | undefined;
  let createdNew = false;

  if (!id) {
    const r = await startExpenseDraft(actor.id);
    if (!r) return NextResponse.json({ ok: false, error: 'startExpenseDraft failed' });
    id = r.waybillId;
    createdNew = true;
  }

  const payload = {
    vendorName: fields.vendor || '',
    transactionDate: fields.transactionDate || '',
    totalAmount: typeof fields.amount === 'number' ? fields.amount : 0,
    paymentMethod: fields.paymentMethod || 'cash',
    notes: fields.description || '',
  };

  const saved = await saveDraftExpense({ waybillId: id!, payload, actorId: actor.id });
  if (!saved.ok) return NextResponse.json({ ok: false, error: saved.error || 'save failed' });

  return NextResponse.json({
    ok: true,
    waybillId: id,
    createdNew,
    savedAt: saved.savedAt,
  });
}
