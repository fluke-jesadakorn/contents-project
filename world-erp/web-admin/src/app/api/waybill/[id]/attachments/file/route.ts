import { NextResponse } from 'next/server';
import { presignedGetUrl } from '@erp-lib/slips/storage';
import { apiGuard } from '@/lib/server/apiGuard';
import { loadWaybill } from '@/lib/server/waybill';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }): Promise<Response> {
  const guard = await apiGuard(req, { perm: 'finance:expense:view_own' });
  if (guard.response) {
    const alt = await apiGuard(req, { perm: 'finance:expense:view_all' });
    if (alt.response) return alt.response;
  }
  const { id } = await ctx.params;
  const wb = await loadWaybill(id);
  if (!wb) return NextResponse.json({ error: 'not found' }, { status: 404 });

  const url = new URL(req.url);
  const key = url.searchParams.get('key');
  if (!key) return NextResponse.json({ error: 'key required' }, { status: 400 });
  if (!key.startsWith(`waybill-attachments/${id}/`)) {
    return NextResponse.json({ error: 'key does not belong to this waybill' }, { status: 403 });
  }

  try {
    const signed = await presignedGetUrl(key, 600);
    return NextResponse.redirect(signed, 302);
  } catch {
    return NextResponse.json({ error: 'not found' }, { status: 404 });
  }
}
