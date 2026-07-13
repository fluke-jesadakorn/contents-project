import { NextResponse } from 'next/server';
import { withApiPolicy } from '@erp-lib/policy/server';
import { POL } from '@erp-lib/policy';
import { discardDraftExpense } from '@/app/actions';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export const POST = withApiPolicy(POL.canDiscardExpenseDraft, async (req, ctx) => {
  let waybillId: string | null = null;
  const ct = req.headers.get('content-type') ?? '';
  try {
    if (ct.includes('application/json')) {
      const body = await req.json();
      waybillId = typeof body?.waybillId === 'string' ? body.waybillId : null;
    } else {
      const fd = await req.formData();
      const v = fd.get('waybillId');
      waybillId = typeof v === 'string' ? v : null;
    }
  } catch {
    return NextResponse.json({ ok: false, error: 'bad_request' }, { status: 400 });
  }

  if (!waybillId) {
    return NextResponse.json({ ok: false, error: 'waybillId required' }, { status: 400 });
  }

  const r = await discardDraftExpense({ waybillId, actorId: ctx.actor.id });
  return NextResponse.json(r, { status: r.ok ? 200 : 400 });
}, 'waybill.discard-draft');