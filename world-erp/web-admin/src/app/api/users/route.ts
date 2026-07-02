import { NextRequest, NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const { searchParams } = new URL(req.url);
  const filterRole = searchParams.get('role') ?? undefined;
  const filterDeptId = searchParams.get('department_id')
    ? Number(searchParams.get('department_id'))
    : undefined;
  const includeInactive = searchParams.get('include_inactive') === 'true';

  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'tile-directory', 'read');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const where: string[] = [];
  const params: any[] = [];
  if (filterRole) {
    params.push(filterRole);
    where.push(`r.name=$${params.length}`);
  }
  if (filterDeptId) {
    params.push(filterDeptId);
    where.push(`u.department_id=$${params.length}`);
  }
  if (!includeInactive) where.push('u.is_active=TRUE');
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const r = await query(
    `SELECT u.id, u.employee_code, u.fullname, u.department, u.department_id,
            u.reports_to_user_id, u.is_active, u.line_user_id, u.created_at,
            u.staff_level, u.dept_group_id, dg.name AS dept_group_name,
            r.name AS role_name, d.code AS dept_code, d.name AS dept_name,
            m.fullname AS manager_name, m.employee_code AS manager_code
     FROM users u
     JOIN roles r ON u.role_id=r.id
     LEFT JOIN departments d ON u.department_id=d.id
     LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
     LEFT JOIN users m ON u.reports_to_user_id=m.id
     ${whereSql}
     ORDER BY u.id`,
    params,
  );
  return NextResponse.json({ users: r.rows });
}

export async function POST(req: NextRequest) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'create_user', 'update');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const body = await req.json();
  const code = (body.employee_code || '').trim();
  if (!code) return NextResponse.json({ error: 'Employee code is required' }, { status: 400 });
  if (!body.fullname?.trim()) return NextResponse.json({ error: 'Full name is required' }, { status: 400 });

  const roleRes = await query(`SELECT id FROM roles WHERE name=$1`, [body.role_name]);
  if (roleRes.rows.length === 0) return NextResponse.json({ error: `Role "${body.role_name}" not found` }, { status: 400 });

  let deptText: string | null = null;
  if (body.department_id) {
    const dRes = await query(`SELECT code FROM departments WHERE id=$1`, [body.department_id]);
    if (dRes.rows.length === 0) return NextResponse.json({ error: 'Invalid department_id' }, { status: 400 });
    deptText = dRes.rows[0].code;
  }

  if (body.staff_level != null && (body.staff_level < 1 || body.staff_level > 5)) {
    return NextResponse.json({ error: 'staff_level must be between 1 and 5' }, { status: 400 });
  }

  const dup = await query(`SELECT 1 FROM users WHERE employee_code=$1`, [code]);
  if (dup.rows.length > 0) return NextResponse.json({ error: 'Duplicate employee code' }, { status: 400 });

  const ins = await query(
    `INSERT INTO users (employee_code, fullname, role_id, department, department_id, reports_to_user_id, is_active, staff_level)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
    [
      code,
      body.fullname.trim(),
      roleRes.rows[0].id,
      deptText,
      body.department_id || null,
      body.reports_to_user_id || null,
      body.is_active === false ? false : true,
      body.staff_level ?? null,
    ],
  );
  return NextResponse.json({ id: ins.rows[0].id });
}