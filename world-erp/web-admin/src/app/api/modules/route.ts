import { NextResponse } from 'next/server';
import { listModules } from '@/lib/rbac/server';
import { loadActor } from '@/lib/server/guard';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  return NextResponse.json({ modules: await listModules() });
}