import { NextResponse } from 'next/server';
import { loadActor } from '@/lib/server/guard';
import { loadOrgTree } from '@/lib/orgScope';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const tree = await loadOrgTree(actor.id);
  return NextResponse.json({ tree });
}