import { NextResponse } from 'next/server';
import { updateGroup, deleteGroup } from '@/lib/rbac/server';
import { loadActor } from '@/lib/server/guard';

export async function PUT(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  await updateGroup(id, body, String(actor.id));
  return NextResponse.json({ ok: true });
}

export async function DELETE(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await params;
  const result = await deleteGroup(id, String(actor.id));
  return NextResponse.json(result);
}