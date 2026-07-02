import { NextResponse } from 'next/server';
import { getGroups, createGroup } from '@/lib/rbac/server';
import { loadActor } from '@/lib/server/guard';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  return NextResponse.json({ groups: await getGroups() });
}

export async function POST(req: Request) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const body = await req.json().catch(() => ({}));
  await createGroup({ ...body, actor: String(actor.id) });
  return NextResponse.json({ ok: true });
}