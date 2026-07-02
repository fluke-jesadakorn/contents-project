import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { loadActor } from '@/lib/server/guard';

export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  const newParent = body.parent_id ?? null;
  const cycle = await query<{ ok: boolean }>(`SELECT rbac.is_descendant($1, $2) AS ok`, [newParent ?? '', id]);
  if (cycle.rows[0]?.ok) return NextResponse.json({ error: 'cycle detected' }, { status: 409 });
  await query(
    `UPDATE rbac.roles SET parent_id = $2 WHERE id = $1`,
    [id, newParent],
  );
  await query(
    `INSERT INTO rbac.audit (kind, actor, target) VALUES ('role.reparent', $1, $2)`,
    [String(actor.id), JSON.stringify({ id, parent_id: newParent })],
  );
  return NextResponse.json({ ok: true });
}