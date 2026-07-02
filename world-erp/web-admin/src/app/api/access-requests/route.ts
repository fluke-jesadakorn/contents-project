import { NextRequest, NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';
import { isAccessAllowed } from '@/lib/access/api.server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const RATE_LIMIT_MS = 60 * 60 * 1000;

export async function GET(req: NextRequest) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { searchParams } = new URL(req.url);
  const status = searchParams.get('status') ?? undefined;

  const canListAll = await isAccessAllowed(actor.rbac_role_id ?? 'L1', 'access-request-list', 'read');
  let where = '';
  const params: any[] = [];
  if (canListAll) {
    if (status) {
      params.push(status);
      where = `WHERE ar.status = $1`;
    }
  } else {
    params.push(actor.id);
    where = `WHERE ar.actor_id = $1`;
    if (status) {
      params.push(status);
      where += ` AND ar.status = $${params.length}`;
    }
  }
  const r = await query(
    `SELECT ar.id, ar.actor_id, u.fullname AS actor_name, u.department AS actor_department,
            u.dept_group_id AS actor_dept_group_id, dg.name AS actor_dept_group_name,
            ar.tile_id, ar.tile_title, ar.note, ar.status, ar.target_user_id,
            tu.fullname AS target_name, ar.target_role,
            ar.created_at, ar.resolved_at, ar.resolved_by_user_id,
            ru.fullname AS resolver_name, ar.resolved_note
     FROM access_requests ar
     JOIN users u ON u.id = ar.actor_id
     LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
     LEFT JOIN users tu ON tu.id = ar.target_user_id
     LEFT JOIN users ru ON ru.id = ar.resolved_by_user_id
     ${where}
     ORDER BY ar.created_at DESC
     LIMIT 200`,
    params,
  );
  return NextResponse.json({ requests: r.rows });
}

export async function POST(req: NextRequest) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const body = await req.json();
  const { tileId, tileTitle, target, note } = body as { tileId: string; tileTitle?: string; target: 'hr_manager' | 'cfo' | 'admin'; note?: string };
  if (!tileId || !target) return NextResponse.json({ error: 'tileId and target required' }, { status: 400 });

  const targetRes = await query(
    `SELECT u.id, u.fullname
     FROM users u JOIN roles r ON u.role_id = r.id
     WHERE r.name = $1 AND u.is_active = TRUE
     ORDER BY u.id LIMIT 1`,
    [target],
  );
  const targetUser = targetRes.rows[0];

  const existing = await query(
    `SELECT id, created_at FROM access_requests
     WHERE actor_id = $1 AND tile_id = $2 AND status = 'pending'
     LIMIT 1`,
    [actor.id, tileId],
  );
  if (existing.rows.length > 0) {
    const age = Date.now() - new Date(existing.rows[0].created_at).getTime();
    if (age < RATE_LIMIT_MS) {
      return NextResponse.json({ id: existing.rows[0].id });
    }
    await query(
      `UPDATE access_requests SET status = 'denied', resolved_at = NOW(),
         resolved_note = 'superseded by newer request'
       WHERE id = $1`,
      [existing.rows[0].id],
    );
  }

  const ins = await query(
    `INSERT INTO access_requests
       (actor_id, tile_id, tile_title, note, status, target_user_id, target_role)
     VALUES ($1, $2, $3, $4, 'pending', $5, $6)
     RETURNING id`,
    [actor.id, tileId, tileTitle || tileId, note || null, targetUser?.id || null, target],
  );
  return NextResponse.json({ id: ins.rows[0].id });
}