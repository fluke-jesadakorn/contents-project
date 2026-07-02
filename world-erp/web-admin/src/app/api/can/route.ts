import { NextResponse } from 'next/server';
import { can } from '@/lib/rbac/server';

export async function GET(req: Request) {
  const url = new URL(req.url);
  const role = url.searchParams.get('role');
  const moduleId = url.searchParams.get('module');
  const action = (url.searchParams.get('action') || 'read') as 'create' | 'read' | 'update' | 'delete';
  if (!role || !moduleId) return NextResponse.json({ error: 'role and module required' }, { status: 400 });
  const result = await can(role, moduleId, action);
  return NextResponse.json(result);
}