import { NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';
import { searchCustomers } from '@/lib/server/customer';

export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });

  const url = new URL(req.url);
  const q = (url.searchParams.get('q') ?? '').trim();
  const rawLimit = parseInt(url.searchParams.get('limit') ?? '10', 10);
  const limit = Math.min(Math.max(isFinite(rawLimit) ? rawLimit : 10, 1), 50);

  try {
    const rows = await searchCustomers(q, limit);
    return NextResponse.json({
      ok: true,
      results: rows.map((r) => ({
        id: r.id,
        code: r.code,
        name: r.name,
        name_th: r.name_th,
        credit_limit_thb: r.credit_limit_thb,
        payment_terms: r.payment_terms,
        blacklist: r.blacklist,
        is_active: r.is_active,
      })),
    });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message ?? 'unknown' }, { status: 500 });
  }
}
