// Shared AI route guard. Use at the top of each /api/ai/* handler.

import { NextResponse } from 'next/server';
import { loadActor, requireAction } from '@/lib/server/guard';
import type { ActionName } from '@/lib/permissions';

export async function aiGuard(opts: {
  action?: ActionName;
  rbacAction?: 'create' | 'read' | 'update' | 'delete';
}): Promise<{ ok: true } | { ok: false; response: Response }> {
  const actor = await loadActor();
  if (!actor) {
    return { ok: false, response: NextResponse.json({ error: 'unauthorized' }, { status: 401 }) };
  }
  if (opts.action) {
    try {
      await requireAction(actor, opts.action, opts.rbacAction ? { rbacAction: opts.rbacAction } : {});
    } catch (e: any) {
      return { ok: false, response: NextResponse.json({ error: e?.message || 'forbidden' }, { status: e?.status ?? 403 }) };
    }
  }
  return { ok: true };
}