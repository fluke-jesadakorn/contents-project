import { NextResponse } from 'next/server';
import { patchCells } from '@/lib/rbac/server';
import { loadActor } from '@/lib/server/guard';

export async function PATCH(req: Request) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const body = await req.json().catch(() => ({}));
  const changes = Array.isArray(body.changes) ? body.changes : [];
  try {
    const result = await patchCells(changes, String(actor.id), body.reason);
    return NextResponse.json(result);
  } catch (e: unknown) {
    const err = e as { code?: string; message?: string };
    return NextResponse.json({ ok: false, error_code: err.code ?? 'patch_failed', error_message: err.message ?? String(e) }, { status: 500 });
  }
}