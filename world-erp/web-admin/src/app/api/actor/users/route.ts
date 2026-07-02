// GET /api/actor/users — dev-only list of seeded users for the sign-in panel.
// Returns 404 in production.

import { NextResponse } from 'next/server';
import { query } from '@/lib/db';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function prod(): boolean {
  return process.env.NODE_ENV === 'production';
}

export async function GET() {
  if (prod()) return NextResponse.json({ error: 'disabled' }, { status: 404 });

const r = await query(
    `SELECT u.id, u.employee_code, u.fullname, u.department,
            u.dept_group_id, dg.name AS dept_group_name,
            r.name AS role_name, r.id AS role_id
       FROM users u
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
      WHERE u.is_active = TRUE
      ORDER BY r.id, u.id`,
  );
  return NextResponse.json({ users: r.rows, pinRequired: !!process.env.DEV_ACTOR_PIN });
}