import { NextResponse } from 'next/server';
import { getMatrix } from '@/lib/rbac/server';
import { listModules } from '@erp-lib/rbac/server';

export async function GET(req: Request) {
  const url = new URL(req.url);
  const modulesParam = url.searchParams.get('modules')?.split(',').filter(Boolean);
  const roles = url.searchParams.get('roles')?.split(',').filter(Boolean);
  const scope = url.searchParams.get('scope');

  let moduleIds = modulesParam;
  if (scope === 'tiles') {
    const all = await listModules();
    moduleIds = all.filter((m) => m.id.startsWith('tile-')).map((m) => m.id);
  }

  const matrix = await getMatrix({ moduleIds, roleIds: roles });
  return NextResponse.json(matrix);
}