import { NextRequest, NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'view_org_chart', 'read');
  if (!allowed && !actor.rbac_role_id) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const r = await query(
    `SELECT d.id, d.code, d.name, d.monthly_budget, d.head_user_id,
            u.fullname AS head_fullname, u.employee_code AS head_code,
            (SELECT COUNT(*)::int FROM users m WHERE m.department_id=d.id AND m.is_active=TRUE) AS active_members
     FROM departments d
     LEFT JOIN users u ON d.head_user_id=u.id
     ORDER BY d.code`,
  );
  return NextResponse.json({ departments: r.rows });
}

export async function PATCH(req: NextRequest) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'assign_department_head', 'update');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const body = await req.json();
  if (!body.department_id) {
    return NextResponse.json({ error: 'department_id is required' }, { status: 400 });
  }
  if (body.head_user_id !== null) {
    const head = await query(`SELECT 1 FROM users WHERE id=$1`, [body.head_user_id]);
    if (head.rows.length === 0) return NextResponse.json({ error: 'Invalid head_user_id' }, { status: 400 });
  }
  await query(`UPDATE departments SET head_user_id=$1 WHERE id=$2`, [body.head_user_id, body.department_id]);
  return NextResponse.json({ ok: true });
}