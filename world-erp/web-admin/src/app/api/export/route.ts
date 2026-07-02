import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { exportMatrix, ACTIONS } from '@/lib/rbac/server';
import { resolveMatrix } from '@/lib/rbac/inheritance';
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

interface ModuleRow { id: string; display_name?: string }
interface RoleRow { id: string; name?: string }

const csvEscape = (v: string) => /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;

export async function GET(req: Request) {
  const a = await requireAdmin();
  if (!a.ok) return NextResponse.json({ error: a.error }, { status: a.status });

  const url = new URL(req.url);
  const fmt = url.searchParams.get('format') ?? 'csv';
  const moduleIds = (url.searchParams.get('modules') ?? '').split(',').filter(Boolean);
  const roleIds = (url.searchParams.get('roles') ?? '').split(',').filter(Boolean);
  const effectiveRoleIds = roleIds.length ? roleIds : null;

  const modules = (moduleIds.length
    ? (await query<ModuleRow>(
        `SELECT id, display_name FROM rbac.modules WHERE id = ANY($1) ORDER BY sort_order`,
        [moduleIds],
      )).rows
    : (await query<ModuleRow>(
        `SELECT id, display_name FROM rbac.modules ORDER BY sort_order`,
      )).rows
  ) as ModuleRow[];

  const rolesQ = effectiveRoleIds
    ? await query<RoleRow>(
        `SELECT id, name FROM rbac.roles WHERE id = ANY($1) ORDER BY level DESC`,
        [effectiveRoleIds],
      )
    : await query<RoleRow>(
        `SELECT id, name FROM rbac.roles WHERE parent_id IS NOT NULL ORDER BY level DESC`,
      );

  const allRoleIds = rolesQ.rows.map((r) => r.id);
  const allModuleIds = modules.map((m) => m.id);
  const resolved = await resolveMatrix(allRoleIds, allModuleIds);

  if (fmt === 'json') {
    const payload = await exportMatrix({ moduleIds: allModuleIds, roleIds: allRoleIds });
    return new NextResponse(JSON.stringify(payload, null, 2), {
      headers: {
        'content-type': 'application/json',
        'content-disposition': `attachment; filename="rbac-matrix-${Date.now()}.json"`,
      },
    });
  }

  const header = ['module_id', 'module_name', 'role_id', 'role_name', ...ACTIONS];
  const lines = [header.map(csvEscape).join(',')];
  for (const mid of allModuleIds) {
    const mod = modules.find((m) => m.id === mid);
    for (const rid of allRoleIds) {
      const role = rolesQ.rows.find((r) => r.id === rid);
      const row = [
        mid,
        mod?.display_name ?? '',
        rid,
        role?.name ?? '',
        ...ACTIONS.map((a) => resolved[mid]?.[rid]?.[a]?.state ?? 'deny'),
      ];
      lines.push(row.map(csvEscape).join(','));
    }
  }
  const csv = lines.join('\n') + '\n';
  return new NextResponse(csv, {
    headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': `attachment; filename="rbac-matrix-${Date.now()}.csv"`,
    },
  });
}