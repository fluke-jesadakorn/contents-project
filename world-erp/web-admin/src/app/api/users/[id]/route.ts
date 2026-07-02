import { NextRequest, NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(_req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await ctx.params;
  const r = await query(
    `SELECT u.id, u.employee_code, u.fullname, u.department, u.department_id,
            u.reports_to_user_id, u.is_active, u.line_user_id, u.created_at,
            u.staff_level, u.role_id, r.name AS role_name
     FROM users u JOIN roles r ON u.role_id=r.id
     WHERE u.id=$1`,
    [id],
  );
  if (r.rows.length === 0) return NextResponse.json({ error: 'not found' }, { status: 404 });
  return NextResponse.json({ user: r.rows[0] });
}

export async function PATCH(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json();

  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'update_user', 'update');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const updates: string[] = [];
  const params: any[] = [];

  if (body.role_name !== undefined) {
    const roleRes = await query(`SELECT id FROM roles WHERE name=$1`, [body.role_name]);
    if (roleRes.rows.length === 0) return NextResponse.json({ error: `Role "${body.role_name}" not found` }, { status: 400 });
    params.push(roleRes.rows[0].id);
    updates.push(`role_id=$${params.length}`);
  }
  if (body.department_id !== undefined) {
    let deptCode: string | null = null;
    if (body.department_id) {
      const dRes = await query(`SELECT code FROM departments WHERE id=$1`, [body.department_id]);
      if (dRes.rows.length === 0) return NextResponse.json({ error: 'Invalid department_id' }, { status: 400 });
      deptCode = dRes.rows[0].code;
    }
    params.push(body.department_id);
    updates.push(`department_id=$${params.length}`);
    params.push(deptCode);
    updates.push(`department=$${params.length}`);
  }
  if (body.reports_to_user_id !== undefined) {
    if (body.reports_to_user_id === Number(id)) {
      return NextResponse.json({ error: 'A user cannot report to themselves' }, { status: 400 });
    }
    if (body.reports_to_user_id !== null) {
      const head = await query(`SELECT 1 FROM users WHERE id=$1`, [body.reports_to_user_id]);
      if (head.rows.length === 0) return NextResponse.json({ error: 'Invalid reports_to_user_id' }, { status: 400 });
      let cur: number | null = Number(body.reports_to_user_id);
      const seen = new Set<number>([Number(id)]);
      while (cur !== null) {
        if (seen.has(cur)) return NextResponse.json({ error: 'Cycle in org chart' }, { status: 400 });
        seen.add(cur);
        const res: { rows: Array<{ reports_to_user_id: number | null }> } = await query(
          `SELECT reports_to_user_id FROM users WHERE id=$1`,
          [cur],
        );
        cur = res.rows[0]?.reports_to_user_id ?? null;
      }
    }
    params.push(body.reports_to_user_id);
    updates.push(`reports_to_user_id=$${params.length}`);
  }
  if (body.staff_level !== undefined) {
    if (body.staff_level !== null && (body.staff_level < 1 || body.staff_level > 5)) {
      return NextResponse.json({ error: 'staff_level must be between 1 and 5' }, { status: 400 });
    }
    params.push(body.staff_level);
    updates.push(`staff_level=$${params.length}`);
  }
  if (body.is_active !== undefined) {
    if (body.is_active === false && Number(id) === actor.id) {
      return NextResponse.json({ error: 'You cannot deactivate your own account' }, { status: 400 });
    }
    params.push(body.is_active);
    updates.push(`is_active=$${params.length}`);
  }

  if (updates.length === 0) return NextResponse.json({ ok: true });

  params.push(id);
  await query(
    `UPDATE users SET ${updates.join(', ')} WHERE id=$${params.length}`,
    params,
  );
  return NextResponse.json({ ok: true });
}

export async function DELETE(_req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await ctx.params;
  if (Number(id) === actor.id) {
    return NextResponse.json({ error: 'You cannot remove your own account' }, { status: 400 });
  }
  const allowed = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'delete_user', 'update');
  if (!allowed) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const target = await query(`SELECT id, employee_code, fullname FROM users WHERE id=$1`, [id]);
  if (target.rows.length === 0) return NextResponse.json({ error: 'Target not found' }, { status: 404 });

  try {
    await query(`UPDATE departments SET head_user_id=NULL WHERE head_user_id=$1`, [id]);
    await query(`UPDATE users SET reports_to_user_id=NULL WHERE reports_to_user_id=$1`, [id]);
    await query(`DELETE FROM users WHERE id=$1`, [id]);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    const msg = String(e?.message || e);
    if (/foreign key|violates/i.test(msg)) {
      return NextResponse.json(
        { error: `Cannot remove ${target.rows[0].employee_code}: this employee still has expenses, approvals, or other history. Deactivate them instead.` },
        { status: 400 },
      );
    }
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}