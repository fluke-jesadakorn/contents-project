import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await params;
  const r = await query(
    `SELECT u.id, u.fullname, u.employee_code
     FROM users u
     WHERE u.rbac_role_id = $1
     ORDER BY u.id`,
    [id],
  );
  return NextResponse.json({ members: r.rows });
}