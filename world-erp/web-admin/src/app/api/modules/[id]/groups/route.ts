import { NextResponse } from 'next/server';
import { setModuleGroups } from '@/lib/rbac/server';
import { loadActor } from '@/lib/server/guard';

export async function PUT(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  await setModuleGroups(id, body.group_ids ?? [], String(actor.id));
  return NextResponse.json({ ok: true });
}