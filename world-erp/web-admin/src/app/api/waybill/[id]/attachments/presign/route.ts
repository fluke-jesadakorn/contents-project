import { NextResponse } from 'next/server';
import { presignedPutUrl, makeKey } from '@erp-lib/slips/storage';
import { apiGuard } from '@/lib/server/apiGuard';
import { loadWaybill } from '@/lib/server/waybill';
import { canActorAttachAt, isTerminalStage } from '@erp-lib/waybill/permissions';
import { allowedKindsFor, type WaybillAttachmentKind } from '@erp-lib/waybill/kinds';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const VALID_KINDS: ReadonlySet<string> = new Set([
  'slip','pr_doc','po_doc','payment_receipt','signoff_memo','invoice','wht_cert','photo','memo','other',
]);

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }): Promise<Response> {
  const guard = await apiGuard(req, { perm: 'finance:expense:view_own' });
  if (guard.response) {
    const alt = await apiGuard(req, { perm: 'finance:expense:view_all' });
    if (alt.response) return alt.response;
  }

  const { id } = await ctx.params;
  const waybillId = id;

  const body = (await req.json().catch(() => null)) as {
    filename?: string;
    contentType?: string;
    kind?: string;
  } | null;
  if (!body) return NextResponse.json({ error: 'body required' }, { status: 400 });

  const wb = await loadWaybill(waybillId);
  if (!wb) return NextResponse.json({ error: 'waybill not found' }, { status: 404 });

  if (isTerminalStage(wb.current_stage)) {
    return NextResponse.json(
      { error: `cannot attach to ${wb.current_stage}` },
      { status: 409 },
    );
  }

  const role = guard.actor.session?.user?.role ?? '';
  if (!canActorAttachAt(role, wb.current_stage)) {
    return NextResponse.json(
      { error: `role '${role}' cannot attach at stage '${wb.current_stage}'` },
      { status: 403 },
    );
  }

  if (!body.filename || !body.contentType || !body.kind) {
    return NextResponse.json(
      { error: 'filename, contentType, kind required' },
      { status: 400 },
    );
  }
  if (!VALID_KINDS.has(body.kind)) {
    return NextResponse.json({ error: `invalid kind '${body.kind}'` }, { status: 400 });
  }
  const kind = body.kind as WaybillAttachmentKind;
  if (!allowedKindsFor(wb.current_stage).includes(kind)) {
    return NextResponse.json(
      { error: `kind '${kind}' not allowed at stage '${wb.current_stage}'` },
      { status: 409 },
    );
  }

  const safeBase = body.filename.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 80);
  const random = makeKey(safeBase);
  const key = `waybill-attachments/${waybillId}/${wb.current_stage}/${random}`;

  const expires = 900;
  const putUrl = await presignedPutUrl(key, expires);

  return NextResponse.json({
    key,
    put_url: putUrl,
    expires,
    waybill_id: waybillId,
    stage_key: wb.current_stage,
    kind,
    content_type: body.contentType,
    filename: safeBase,
  });
}
