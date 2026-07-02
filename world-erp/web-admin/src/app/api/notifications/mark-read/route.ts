import { NextResponse } from 'next/server';
import { requireActor } from '@/lib/server/guard';
import { query } from '@/lib/db';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface MarkReadBody {
  ids?: Array<string | number>;
  all?: boolean;
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

  const body = (await req.json().catch(() => ({}))) as MarkReadBody;
  const all = body.all === true;
  const ids = parseIds(body.ids);

  let result;
  if (all) {
    result = await query(
      `UPDATE notifications SET read_at = NOW()
       WHERE user_id = $1 AND read_at IS NULL AND cleared_at IS NULL`,
      [actor.id]
    );
  } else if (ids.length > 0) {
    result = await query(
      `UPDATE notifications SET read_at = NOW()
       WHERE user_id = $1 AND id = ANY($2::bigint[]) AND read_at IS NULL AND cleared_at IS NULL`,
      [actor.id, ids]
    );
  } else {
    return NextResponse.json({ ok: true, updated: 0 });
  }

  return NextResponse.json({ ok: true, updated: result.rowCount ?? 0 });
}