import { NextResponse } from 'next/server';
import { loadWaybill, loadWaybillEvents, loadAttachmentsForWaybill } from '@/lib/server/waybill';
import { apiGuard } from '@/lib/server/apiGuard';
import { buildWaybillPdf } from '@erp-lib/waybill/exportPdf';
import { PERM } from '@erp-lib/perm';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }): Promise<Response> {
  const guard = await apiGuard(req, { perm: PERM.finance.expense.view_own });
  if (guard.response) {
    const alt = await apiGuard(req, { perm: PERM.finance.expense.view_all });
    if (alt.response) return alt.response;
  }

  const { id } = await ctx.params;
  const wb = await loadWaybill(id);
  if (!wb) return NextResponse.json({ error: 'not found' }, { status: 404 });

  const url = new URL(req.url);
  const rawInclude = url.searchParams.get('attachment_ids');
  const includeIds = rawInclude
    ? new Set(rawInclude.split(',').map((s) => s.trim()).filter(Boolean))
    : null;

  const [events, attachments] = await Promise.all([
    loadWaybillEvents(id),
    loadAttachmentsForWaybill(id),
  ]);

  const bytes = await buildWaybillPdf({
    waybill: wb,
    events,
    attachments,
    includeAttachmentIds: includeIds,
  });

  return new NextResponse(bytes as unknown as ArrayBuffer, {
    status: 200,
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${wb.id}_combined.pdf"`,
      'Cache-Control': 'private, no-store',
    },
  });
}

