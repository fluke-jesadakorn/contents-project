// POST /api/actor  { id, pin? } — set the signed actor cookie.
// In production this route should be disabled entirely (real auth would set the cookie).
// In dev/non-prod, a DEV_ACTOR_PIN (if configured) must be supplied.

import { NextResponse } from 'next/server';
import { revalidatePath } from 'next/cache';
import { cookies } from 'next/headers';
import { query } from '@/lib/db';
import { signSession, SESSION_COOKIE } from '@/lib/server/sessionToken';
import { safeEqual } from '@/lib/server/sessionToken';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function prod(): boolean {
  return process.env.NODE_ENV === 'production';
}

export async function POST(req: Request) {
  if (prod()) {
    return NextResponse.json({ error: 'disabled in production' }, { status: 404 });
  }

  const body = await req.json().catch(() => ({}));
  const id = parseInt(body.id, 10);
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });

  const expectedPin = process.env.DEV_ACTOR_PIN;
  if (expectedPin) {
    const provided = String(body.pin || '');
    if (!safeEqual(provided, expectedPin)) {
      return NextResponse.json({ error: 'invalid pin' }, { status: 401 });
    }
  }

  const r = await query('SELECT id, fullname, role_id, rbac_role_id FROM users WHERE id = $1', [id]);
  if (!r.rows.length) return NextResponse.json({ error: 'user not found' }, { status: 404 });

  const roleRow = await query('SELECT name FROM roles WHERE id = $1', [r.rows[0].role_id]);
  const roleName = roleRow.rows[0]?.name || 'staff';
  const rbacRoleId = r.rows[0].rbac_role_id ?? null;

  const token = await signSession({ sub: id, role: roleName, rbacRoleId });

  const c = await cookies();
  c.set(SESSION_COOKIE, token, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    maxAge: 60 * 60 * 24 * 30,
  });

  revalidatePath('/', 'layout');

  return NextResponse.json({ ok: true, user: r.rows[0], role: roleName });
}

export async function DELETE() {
  if (prod()) {
    return NextResponse.json({ error: 'disabled in production' }, { status: 404 });
  }
  const c = await cookies();
  c.delete(SESSION_COOKIE);
  return NextResponse.json({ ok: true });
}