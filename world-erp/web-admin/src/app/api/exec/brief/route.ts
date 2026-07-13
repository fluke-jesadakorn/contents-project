import { NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';
import { loadExecutiveBrief } from '@erp-lib/server/execBrief';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  const brief = await loadExecutiveBrief(actor);
  return NextResponse.json({ ok: true, brief });
}
