import { NextResponse } from 'next/server';
import { canBatch } from '@/lib/rbac/server';

const ALLOWED_ACTIONS = ['create', 'read', 'update', 'delete'] as const;

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}));
  if (!body.role || !Array.isArray(body.modules)) {
    return NextResponse.json({ error: 'role and modules[] required' }, { status: 400 });
  }
  const action = (ALLOWED_ACTIONS as readonly string[]).includes(body.action ?? 'read')
    ? ((body.action ?? 'read') as 'create' | 'read' | 'update' | 'delete')
    : 'read';
  const allow = await canBatch(body.role, body.modules, action);
  return NextResponse.json({ role: body.role, action, allow });
}