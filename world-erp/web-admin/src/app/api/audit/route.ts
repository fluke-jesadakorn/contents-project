import { NextResponse } from 'next/server';
import { getAudit } from '@/lib/rbac/server';
import { loadActor } from '@/lib/server/guard';

async function requireAdmin() {
  const sess = await loadActor();
  if (!sess) return { ok: false as const, status: 401, error: 'unauthorized' };
  const isItOrAdmin = sess.role_name === 'it' || sess.role_name === 'admin';
  if (!isItOrAdmin && sess.rbac_role_id !== 'rbac-admin') {
    return { ok: false as const, status: 403, error: 'forbidden' };
  }
  return { ok: true as const };
}

export async function GET(req: Request) {
  const a = await requireAdmin();
  if (!a.ok) return NextResponse.json({ error: a.error }, { status: a.status });

  const url = new URL(req.url);
  const events = await getAudit({
    role_id: url.searchParams.get('role_id') ?? undefined,
    module_id: url.searchParams.get('module_id') ?? undefined,
    kind: url.searchParams.get('kind') ?? undefined,
    since: url.searchParams.get('since') ?? undefined,
    limit: url.searchParams.get('limit')
      ? Math.min(Number(url.searchParams.get('limit')), 500)
      : 100,
  });
  return NextResponse.json({ events });
}