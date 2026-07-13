import { NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';
import { canManageResource, hasPermission } from '@erp-lib/perm/auth-client';
import { poStorageKey, ensurePoPdf, loadPoRowFor } from '@erp-lib/finance/poPdf';
import { query } from '@/lib/db';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  req: Request,
  ctx: { params: Promise<{ id: string }> | { id: string } },
) {
  const params = ctx.params instanceof Promise ? await ctx.params : ctx.params;
  const id = params?.id ?? '';
  if (!id) {
    return NextResponse.json({ error: 'bad request' }, { status: 400 });
  }

  const actor = await loadActor();
  if (!actor) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const session = {
    user: { id: actor.id, name: actor.fullname, role: actor.role_id ?? 'officer::5' },
    permissions: actor.permissions,
  };

  const row = await loadPoRowFor(id);
  if (!row) {
    return NextResponse.json({ error: 'PO not generated' }, { status: 404 });
  }

  const subRes = await query<{ submitter_id: number | null }>(
    `SELECT requester_id AS submitter_id FROM purchase_orders WHERE id = $1`,
    [id],
  );
  const submitterId = subRes.rows[0]?.submitter_id ?? null;

  const allowed = hasPermission(session, 'finance:po:view_all::allow')
    || (submitterId !== null && canManageResource(session, 'finance:po:view_own::allow', { ownerId: submitterId }));
  if (!allowed) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const key = poStorageKey(id);
  try {
    return NextResponse.redirect(new URL(`/api/slips/file?key=${encodeURIComponent(key)}`, req.url), 302);
  } catch {
    await ensurePoPdf(id, actor.role_name ?? 'system');
    return NextResponse.redirect(new URL(`/api/slips/file?key=${encodeURIComponent(key)}`, req.url), 302);
  }
}
