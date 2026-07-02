import { NextRequest, NextResponse } from 'next/server';
import { replayHookEvent } from '@/lib/hook/replay';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(_req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'hook-replay', 'update');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const { id } = await ctx.params;
  const eventId = Number(id);
  if (!Number.isFinite(eventId) || eventId <= 0) {
    return NextResponse.json({ error: 'invalid id' }, { status: 400 });
  }
  const out = await replayHookEvent(eventId, String(actor.id));
  return NextResponse.json(out);
}