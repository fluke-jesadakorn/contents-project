import { NextResponse } from 'next/server';
import { requireActor } from '@/lib/server/guard';
import { setReadState } from '@/lib/server/queries';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface Body {
  ids?: Array<string | number>;
}

function parseIds(raw: unknown): number[] {
  if (!Array.isArray(raw)) return [];
  const out: number[] = [];
  for (const v of raw) {
    const n = typeof v === 'string' ? parseInt(v, 10) : typeof v === 'number' ? v : NaN;
    if (!Number.isNaN(n) && n > 0) out.push(n);
  }
  return out;
}

export async function POST(req: Request) {
  const actor = await requireActor().catch(() => null);
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const body = (await req.json().catch(() => ({}))) as Body;
  const ids = parseIds(body.ids);
  if (ids.length === 0) {
    return NextResponse.json({ ok: true, updated: 0 });
  }
  const result = await setReadState(actor.id, ids, 'unmark');
  return NextResponse.json({ ok: true, updated: result.updated });
}