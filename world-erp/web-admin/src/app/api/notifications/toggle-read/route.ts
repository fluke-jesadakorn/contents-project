import { NextResponse } from 'next/server';
import { requireActor } from '@/lib/server/guard';
import { query } from '@/lib/db';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface Body {
  id?: string | number;
}

export async function POST(req: Request) {
  const actor = await requireActor().catch(() => null);
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const body = (await req.json().catch(() => ({}))) as Body;
  const raw = body.id;
  const id = typeof raw === 'string' ? parseInt(raw, 10) : typeof raw === 'number' ? raw : NaN;
  if (Number.isNaN(id) || id <= 0) {
    return NextResponse.json({ error: 'id required' }, { status: 400 });
  }

  const r = await query<{ id: number; read_at: string | null }>(
    `UPDATE notifications
     SET read_at = CASE WHEN read_at IS NULL THEN NOW() ELSE NULL END
     WHERE user_id = $1 AND id = $2 AND cleared_at IS NULL
     RETURNING id, read_at`,
    [actor.id, id]
  );
  if (r.rows.length === 0) return NextResponse.json({ error: 'not found' }, { status: 404 });
  const row = r.rows[0];
  return NextResponse.json({
    ok: true,
    id: String(row.id),
    readAt: row.read_at ? new Date(row.read_at).toISOString() : null,
  });
}