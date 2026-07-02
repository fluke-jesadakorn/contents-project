import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'assign_role', 'read');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const r = await query(`SELECT id, name FROM roles ORDER BY id`);
  return NextResponse.json({ roles: r.rows });
}