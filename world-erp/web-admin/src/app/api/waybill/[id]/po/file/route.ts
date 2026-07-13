// web-admin/src/app/api/waybill/[id]/po/file/route.ts
//
// Returns a 10-minute presigned MinIO URL for the PO PDF tied to a waybill.
// Generates the PDF on-demand if missing. Gated by the viewWaybillPdf policy.

import { withApiPolicy } from '@erp-lib/policy/server';
import { POL } from '@erp-lib/policy';
import { NextResponse } from 'next/server';
import { poStorageKey, ensurePoPdf, loadPoRowFor } from '@erp-lib/finance/poPdf';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export const GET = withApiPolicy(POL.viewWaybillPdf, async (req, ctx) => {
  const m = req.url.match(/\/api\/waybill\/([^/]+)\/po\/file/);
  const id = m?.[1] ?? '';
  if (!id) {
    return NextResponse.json({ error: 'bad request' }, { status: 400 });
  }
  const row = await loadPoRowFor(id);
  if (!row) {
    return NextResponse.json({ error: 'PO not generated' }, { status: 404 });
  }
  const key = poStorageKey(id);
  try {
    return NextResponse.redirect(new URL(`/api/slips/file?key=${encodeURIComponent(key)}`, req.url), 302);
  } catch {
    await ensurePoPdf(id, ctx.actor.roleName ?? 'system');
    return NextResponse.redirect(new URL(`/api/slips/file?key=${encodeURIComponent(key)}`, req.url), 302);
  }
}, 'waybill.<id>.po.file');
