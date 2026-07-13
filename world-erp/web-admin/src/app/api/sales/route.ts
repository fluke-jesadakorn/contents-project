import { NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';
import { listSalesOrders } from '@/lib/server/queries';
import { listMyWaybills } from '@/lib/server/waybill';

export const dynamic = 'force-dynamic';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  try {
    const [r, mine] = await Promise.all([listSalesOrders(actor.id), listMyWaybills(actor.id)]);
    const mySoIds = new Set<string>();
    for (const m of mine) {
      if (m.origin === 'so') mySoIds.add(m.id);
    }
    return NextResponse.json({
      ok: true,
      rows: r.rows.map((row: any) => ({
        ...row,
        mine: row.waybill_id ? mySoIds.has(row.waybill_id) : false,
      })),
    });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message ?? 'unknown' }, { status: 500 });
  }
}

