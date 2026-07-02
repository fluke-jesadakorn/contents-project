import { NextRequest, NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(_req: NextRequest) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'auto_wire_org', 'update');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const { proposeAutoWire } = await import('@/lib/autoWire.server');
  const proposal = await proposeAutoWire();
  return NextResponse.json({ proposal });
}