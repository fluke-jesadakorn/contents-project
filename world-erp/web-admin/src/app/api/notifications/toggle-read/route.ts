import { NextResponse } from 'next/server';
import { requireActor } from '@/lib/server/guard';
import { toggleReadForUser } from '@/lib/server/queries';

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

  const result = await toggleReadForUser(actor.id, id);
  if (!result) return NextResponse.json({ error: 'not found' }, { status: 404 });
  return NextResponse.json({ ok: true, id: String(result.id), readAt: result.readAt });
}