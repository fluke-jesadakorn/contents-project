// High-level RBAC server functions. Pure DB calls — no HTTP.
// Callable from server components, route handlers, and server actions.
//
// Mirrors what the Fastify rbac service exposed (now consolidated).

import { query } from '../db';
import {
  ACTIONS,
  resolveCellWithGroups,
  resolveBatch,
  resolveMatrix,
  clearParentCache,
  type Action,
  type ResolvedCell,
} from './inheritance';

export type {
  Action,
  EffectiveState,
  ResolvedCell,
  Source,
} from './inheritance';

export interface RoleNode {
  id: string;
  name: string;
  level: number;
  parent_id: string | null;
  sort_order: number;
  is_system: boolean;
  version: number;
  children: RoleNode[];
}

export interface ModuleRow {
  id: string;
  display_name: string;
  group_name: string;
  sort_order: number;
  allowed_actions: string[];
}

export interface ColumnRole {
  id: string;
  name: string;
  level: number;
  parent_id: string | null;
  sort_order: number;
  is_system: boolean;
}

export interface MatrixRow {
  module_id: string;
  cells: Record<string, Record<Action, ResolvedCell>>;
}

export interface OrgResponse {
  roles: RoleNode[];
}

export interface MatrixResponse {
  modules: ModuleRow[];
  columns: ColumnRole[];
  rows: MatrixRow[];
}

export interface CellChange {
  role_id: string;
  module_id: string;
  action: Action;
  state: 'allow' | 'deny' | 'inherit';
}

// --- Org tree ---------------------------------------------------------------

export async function getOrg(): Promise<OrgResponse> {
  const { rows } = await query<{
    id: string; name: string; level: number; parent_id: string | null;
    sort_order: number; is_system: boolean;
  }>(
    `SELECT id, name, level, parent_id, sort_order, is_system, version
       FROM rbac.roles
      ORDER BY level DESC, sort_order ASC`,
  );
  const byId = new Map<string, RoleNode>();
  for (const r of rows) byId.set(r.id, { ...r, version: 0, children: [] });
  const roots: RoleNode[] = [];
  for (const r of rows) {
    const node = byId.get(r.id)!;
    if (r.parent_id && byId.has(r.parent_id)) {
      byId.get(r.parent_id)!.children.push(node);
    } else {
      roots.push(node);
    }
  }
  return { roles: roots };
}

// --- Modules ----------------------------------------------------------------

export async function listModules(ids?: string[]): Promise<ModuleRow[]> {
  const sql = ids?.length
    ? `SELECT id, display_name, group_name, sort_order, allowed_actions
         FROM rbac.modules WHERE id = ANY($1) ORDER BY sort_order`
    : `SELECT id, display_name, group_name, sort_order, allowed_actions
         FROM rbac.modules ORDER BY sort_order`;
  const { rows } = await query<ModuleRow>(sql, ids?.length ? [ids] : undefined);
  return rows;
}

// --- Matrix -----------------------------------------------------------------

// --- Tiles (static catalog) -------------------------------------------------

export interface TileRow {
  id: string;
  display_name: string;
  subtitle: string;
  icon: string;
  accent: string;
  group_name: string;
  sub_view: string | null;
  href: string;
  module_id: string;
  request_target: string | null;
  sort_order: number;
  is_system: boolean;
  owner_group_id: string | null;
  default_perm: 'allow' | 'deny';
}

export async function listTiles(): Promise<TileRow[]> {
  const { rows } = await query<TileRow>(
    `SELECT id, display_name, subtitle, icon, accent, group_name, sub_view,
            href, module_id, request_target, sort_order, is_system,
            owner_group_id, default_perm::text AS default_perm
       FROM rbac.tiles
      ORDER BY sort_order ASC, id ASC`,
  );
  return rows;
}

export async function getTileById(id: string): Promise<TileRow | null> {
  const { rows } = await query<TileRow>(
    `SELECT id, display_name, subtitle, icon, accent, group_name, sub_view,
            href, module_id, request_target, sort_order, is_system,
            owner_group_id, default_perm::text AS default_perm
       FROM rbac.tiles WHERE id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function getTileBySlug(slug: string): Promise<TileRow | null> {
  const { rows } = await query<TileRow>(
    `SELECT id, display_name, subtitle, icon, accent, group_name, sub_view,
            href, module_id, request_target, sort_order, is_system,
            owner_group_id, default_perm::text AS default_perm
       FROM rbac.tiles WHERE href = $1`,
    ['/' + slug],
  );
  return rows[0] ?? null;
}

export async function getMatrix(opts: {
  moduleIds?: string[];
  roleIds?: string[];
}): Promise<MatrixResponse> {
  const modules = await listModules(opts.moduleIds);
  const rolesQ = opts.roleIds?.length
    ? await query<ColumnRole>(
        `SELECT id, name, level, parent_id, sort_order, is_system
           FROM rbac.roles WHERE id = ANY($1)
          ORDER BY level DESC, sort_order ASC`,
        [opts.roleIds],
      )
    : await query<ColumnRole>(
        `SELECT id, name, level, parent_id, sort_order, is_system
           FROM rbac.roles
          ORDER BY level DESC, sort_order ASC`,
      );

  const allRoleIds = rolesQ.rows.map((r: ColumnRole) => r.id as string);
  const allModuleIds = modules.map((m) => m.id as string);
  const resolved = await resolveMatrix(allRoleIds, allModuleIds);

  const rows: MatrixRow[] = allModuleIds.map((mid) => {
    const cells: Record<string, Record<Action, ResolvedCell>> = {};
    for (const rid of allRoleIds) {
      cells[rid] = resolved[mid]?.[rid] ?? ({} as Record<Action, ResolvedCell>);
    }
    return { module_id: mid, cells };
  });

  return { modules, columns: rolesQ.rows, rows };
}

// --- Can (Linux-style) ------------------------------------------------------

export async function can(
  roleId: string,
  moduleId: string,
  action: Action = 'read',
): Promise<{ allow: boolean; source: string; inheritedFrom: string | null }> {
  const cell = await resolveCellWithGroups(roleId, moduleId, action);
  return {
    allow: cell.state === 'allow',
    source: cell.source,
    inheritedFrom: cell.inheritedFrom ?? null,
  };
}

export async function canBatch(
  roleId: string,
  modules: string[],
  action: Action = 'read',
): Promise<Record<string, boolean>> {
  return resolveBatch(roleId, modules, action);
}

// --- Cells (write) ----------------------------------------------------------

export async function patchCells(
  changes: CellChange[],
  actor: string,
  reason?: string,
): Promise<{ ok: boolean; applied: number }> {
  for (const c of changes) {
    if (c.state === 'inherit') {
      await query(
        `DELETE FROM rbac.permissions
          WHERE role_id = $1 AND module_id = $2 AND action = $3`,
        [c.role_id, c.module_id, c.action],
      );
    } else {
      await query(
        `INSERT INTO rbac.permissions (role_id, module_id, action, state, updated_by)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (role_id, module_id, action) DO UPDATE
           SET state = EXCLUDED.state, updated_by = EXCLUDED.updated_by`,
        [c.role_id, c.module_id, c.action, c.state, actor],
      );
    }
    await query(
      `INSERT INTO rbac.audit (kind, actor, target)
       VALUES ('cell.set', $1, $2)`,
      [actor, JSON.stringify({ ...c, reason })],
    );
  }
  clearParentCache();
  return { ok: true, applied: changes.length };
}

// --- Groups (Linux-style: module groups + departments) ---------------------

export interface GroupRow {
  id: string;
  name: string;
  kind: 'module-group' | 'department' | 'team';
  parent_id: string | null;
  sort_order: number;
  is_system: boolean;
}

export async function getGroups(): Promise<GroupRow[]> {
  const { rows } = await query<GroupRow>(
    `SELECT id, name, kind, parent_id, sort_order, is_system
       FROM rbac.groups
      ORDER BY kind, sort_order, name`,
  );
  return rows;
}

export interface TreeNode extends GroupRow {
  children: TreeNode[];
  modules: { id: string; display_name: string }[];
  roles: { id: string; name: string }[];
}

export async function getGroupsTree(filterId?: string): Promise<TreeNode[]> {
  const { rows: groups } = await query<GroupRow>(
    `SELECT id, name, kind, parent_id, sort_order, is_system FROM rbac.groups`,
  );
  const { rows: mods } = await query<{ group_id: string; id: string; display_name: string }>(
    `SELECT mg.group_id, m.id, m.display_name
       FROM rbac.module_groups mg
       JOIN rbac.modules m ON m.id = mg.module_id`,
  );
  const { rows: roles } = await query<{ group_id: string; id: string; name: string }>(
    `SELECT rg.group_id, r.id, r.name
       FROM rbac.role_groups rg
       JOIN rbac.roles r ON r.id = rg.role_id`,
  );

  const byId = new Map<string, TreeNode>();
  for (const g of groups) byId.set(g.id, { ...g, children: [], modules: [], roles: [] });
  const roots: TreeNode[] = [];
  for (const g of groups) {
    const node = byId.get(g.id)!;
    if (g.parent_id && byId.has(g.parent_id)) {
      byId.get(g.parent_id)!.children.push(node);
    } else {
      roots.push(node);
    }
  }
  for (const m of mods) {
    const n = byId.get(m.group_id);
    if (n) n.modules.push({ id: m.id, display_name: m.display_name });
  }
  for (const r of roles) {
    const n = byId.get(r.group_id);
    if (n) n.roles.push({ id: r.id, name: r.name });
  }
  if (filterId) {
    const flat = (nodes: TreeNode[], out: TreeNode[] = []): TreeNode[] => {
      for (const n of nodes) {
        if (n.id === filterId) out.push(n);
        flat(n.children, out);
      }
      return out;
    };
    return flat(roots);
  }
  return roots;
}

export async function createGroup(input: {
  id: string;
  name: string;
  kind: GroupRow['kind'];
  parent_id?: string | null;
  sort_order?: number;
  actor: string;
}): Promise<void> {
  await query(
    `INSERT INTO rbac.groups (id, name, kind, parent_id, sort_order)
     VALUES ($1, $2, $3, $4, $5)`,
    [input.id, input.name, input.kind, input.parent_id ?? null, input.sort_order ?? 0],
  );
  await query(
    `INSERT INTO rbac.audit (kind, actor, target)
     VALUES ('group.create', $1, $2)`,
    [input.actor, JSON.stringify({ id: input.id })],
  );
}

export async function updateGroup(
  id: string,
  patch: Partial<Pick<GroupRow, 'name' | 'kind' | 'parent_id' | 'sort_order'>>,
  actor: string,
): Promise<void> {
  await query(
    `UPDATE rbac.groups
        SET name = COALESCE($2, name),
            kind = COALESCE($3, kind),
            parent_id = $4,
            sort_order = COALESCE($5, sort_order)
      WHERE id = $1`,
    [
      id,
      patch.name ?? null,
      patch.kind ?? null,
      patch.parent_id === undefined ? null : patch.parent_id,
      patch.sort_order ?? null,
    ],
  );
  await query(
    `INSERT INTO rbac.audit (kind, actor, target)
     VALUES ('group.update', $1, $2)`,
    [actor, JSON.stringify({ id })],
  );
}

export async function deleteGroup(id: string, actor: string): Promise<{ deleted: boolean; system?: boolean }> {
  const { rows } = await query<{ is_system: boolean }>(
    `SELECT is_system FROM rbac.groups WHERE id = $1`,
    [id],
  );
  if (!rows[0]) return { deleted: false };
  if (rows[0].is_system) return { deleted: false, system: true };
  await query(`DELETE FROM rbac.groups WHERE id = $1`, [id]);
  await query(
    `INSERT INTO rbac.audit (kind, actor, target)
     VALUES ('group.delete', $1, $2)`,
    [actor, JSON.stringify({ id })],
  );
  return { deleted: true };
}

export async function setModuleGroups(
  moduleId: string,
  groupIds: string[],
  actor: string,
): Promise<void> {
  await query(`DELETE FROM rbac.module_groups WHERE module_id = $1`, [moduleId]);
  for (const g of groupIds) {
    await query(
      `INSERT INTO rbac.module_groups (module_id, group_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
      [moduleId, g],
    );
  }
  await query(
    `INSERT INTO rbac.audit (kind, actor, target)
     VALUES ('module.add_to_group', $1, $2)`,
    [actor, JSON.stringify({ module: moduleId, groups: groupIds })],
  );
}

// --- Audit ------------------------------------------------------------------

export interface AuditEvent {
  id: number;
  kind: string;
  actor: string;
  target: any;
  occurred_at: string;
}

export async function getAudit(opts: {
  role_id?: string;
  module_id?: string;
  kind?: string;
  since?: string;
  limit?: number;
}): Promise<AuditEvent[]> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (opts.role_id) {
    params.push(opts.role_id);
    where.push(`target->>'role_id' = $${params.length}`);
  }
  if (opts.module_id) {
    params.push(opts.module_id);
    where.push(`target->>'module_id' = $${params.length}`);
  }
  if (opts.kind) {
    params.push(opts.kind);
    where.push(`kind = $${params.length}::rbac.audit_kind`);
  }
  if (opts.since) {
    params.push(opts.since);
    where.push(`occurred_at >= $${params.length}::timestamptz`);
  }
  params.push(Math.min(opts.limit ?? 100, 500));
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const { rows } = await query<AuditEvent>(
    `SELECT id, kind, actor, target, occurred_at
       FROM rbac.audit
       ${whereSql}
      ORDER BY occurred_at DESC
      LIMIT $${params.length}`,
    params,
  );
  return rows;
}

// --- Legacy effectiveState helper (used by assertRole.ts / guard.ts) --------

export async function effectiveState(
  rbacRoleId: string,
  moduleId: string,
  action: Action,
): Promise<{ state: 'allow' | 'deny'; source: string } | null> {
  const cell = await resolveCellWithGroups(rbacRoleId, moduleId, action);
  return { state: cell.state, source: cell.source };
}

export async function isAccessAllowed(
  rbacRoleId: string,
  moduleId: string,
  action: Action = 'read',
): Promise<boolean> {
  const c = await resolveCellWithGroups(rbacRoleId, moduleId, action);
  return c.state === 'allow';
}

export async function isAdminMatrix(rbacRoleId: string | null): Promise<boolean> {
  if (!rbacRoleId) return false;
  return isAccessAllowed(rbacRoleId, 'rbac-admin', 'update');
}

export { ACTIONS };

// --- Export ----------------------------------------------------------------

export interface ExportPayload {
  generated_at: string;
  modules: ModuleRow[];
  roles: ColumnRole[];
  matrix: {
    module_id: string;
    cells: Record<string, Record<Action, ResolvedCell>>;
  }[];
}

export async function exportMatrix(opts: {
  moduleIds?: string[];
  roleIds?: string[];
}): Promise<ExportPayload> {
  const { modules, columns, rows } = await getMatrix(opts);
  return {
    generated_at: new Date().toISOString(),
    modules,
    roles: columns,
    matrix: rows.map((r) => ({ module_id: r.module_id, cells: r.cells })),
  };
}

// --- Summary slices ---------------------------------------------------------

export interface FeatureSlice {
  id: string;
  label: string;
  count: number;
}

export interface DepartmentSlice {
  id: string;
  name: string;
  users: number;
  expenses: number;
  expenses_total: number;
  slips: number;
  approvals: number;
}

export interface GroupSlice {
  id: string;
  name: string;
  kind: string;
  role_count: number;
  direct_users: number;
}

export interface PersonaSlice {
  id: number;
  fullname: string;
  department: string;
  rbac_role_id: string | null;
  expenses: number;
  slips: number;
  approvals: number;
  notifications: number;
}

export interface SummarySlices {
  features: FeatureSlice[];
  departments: DepartmentSlice[];
  groups: GroupSlice[];
  personas: PersonaSlice[];
}

export async function getSummarySlices(): Promise<SummarySlices> {
  const [featuresRes, departmentsRes, groupsRes, personasRes] = await Promise.all([
    query<{
      id: string;
      label: string;
      count: string;
    }>(`
      SELECT 'expenses' AS id, 'Expenses' AS label, COUNT(*)::text AS count FROM expenses
      UNION ALL SELECT 'slips', 'Slips', COUNT(*)::text FROM slips
      UNION ALL SELECT 'purchase_requisitions', 'Purchase Requisitions', COUNT(*)::text FROM purchase_requisitions
      UNION ALL SELECT 'purchase_orders', 'Purchase Orders', COUNT(*)::text FROM purchase_orders
      UNION ALL SELECT 'notifications', 'Notifications', COUNT(*)::text FROM notifications
      UNION ALL SELECT 'approval_logs', 'Approval Actions', COUNT(*)::text FROM approval_logs
      UNION ALL SELECT 'ceo_overrides', 'CEO Overrides', COUNT(*)::text FROM ceo_overrides
      UNION ALL SELECT 'access_requests', 'Access Requests', COUNT(*)::text FROM access_requests
      UNION ALL SELECT 'ai_invocations', 'AI Invocations', COUNT(*)::text FROM ai_invocations
      ORDER BY 1
    `),
    query<{
      id: string;
      name: string;
      users: string;
      expenses: string;
      expenses_total: string;
      slips: string;
      approvals: string;
    }>(`
      SELECT
        g.id::text AS id,
        g.name,
        (SELECT COUNT(*) FROM users u WHERE u.dept_group_id = g.id)::text AS users,
        (SELECT COUNT(*) FROM users u JOIN expenses e ON e.submitter_id = u.id WHERE u.dept_group_id = g.id)::text AS expenses,
        COALESCE((SELECT SUM(e.total_amount) FROM users u JOIN expenses e ON e.submitter_id = u.id WHERE u.dept_group_id = g.id), 0)::text AS expenses_total,
        (SELECT COUNT(*) FROM users u JOIN slips s ON s.uploaded_by = u.id WHERE u.dept_group_id = g.id)::text AS slips,
        (SELECT COUNT(*) FROM users u JOIN approval_logs a ON a.actor_id = u.id WHERE u.dept_group_id = g.id)::text AS approvals
      FROM rbac.groups g
      WHERE g.kind = 'department'
      ORDER BY g.name
    `),
    query<{
      id: string;
      name: string;
      kind: string;
      role_count: string;
      direct_users: string;
    }>(`
      SELECT
        g.id,
        g.name,
        g.kind,
        (SELECT COUNT(*) FROM rbac.role_groups rg WHERE rg.group_id = g.id)::text AS role_count,
        (SELECT COUNT(DISTINCT rg.role_id) FROM rbac.role_groups rg WHERE rg.group_id = g.id)::text AS direct_users
      FROM rbac.groups g
      WHERE g.kind = 'module-group'
      ORDER BY g.name
    `),
    query<{
      id: number;
      fullname: string;
      department: string;
      rbac_role_id: string;
      expenses: string;
      slips: string;
      approvals: string;
      notifications: string;
    }>(`
      SELECT
        u.id,
        u.fullname,
        COALESCE(u.department, '(none)') AS department,
        COALESCE(u.rbac_role_id, '') AS rbac_role_id,
        (SELECT COUNT(*) FROM expenses WHERE submitter_id = u.id)::text AS expenses,
        (SELECT COUNT(*) FROM slips WHERE uploaded_by = u.id)::text AS slips,
        (SELECT COUNT(*) FROM approval_logs WHERE actor_id = u.id)::text AS approvals,
        (SELECT COUNT(*) FROM notifications WHERE user_id = u.id)::text AS notifications
      FROM users u
      ORDER BY u.id
    `),
  ]);

  return {
    features: featuresRes.rows.map((r: { id: string; label: string; count: string }) => ({
      id: r.id,
      label: r.label,
      count: Number(r.count) || 0,
    })),
    departments: departmentsRes.rows.map((r: { id: string; name: string; users: string; expenses: string; expenses_total: string; slips: string; approvals: string }) => ({
      id: r.id,
      name: r.name,
      users: Number(r.users) || 0,
      expenses: Number(r.expenses) || 0,
      expenses_total: Number(r.expenses_total) || 0,
      slips: Number(r.slips) || 0,
      approvals: Number(r.approvals) || 0,
    })),
    groups: groupsRes.rows.map((r: { id: string; name: string; kind: string; role_count: string; direct_users: string }) => ({
      id: r.id,
      name: r.name,
      kind: r.kind,
      role_count: Number(r.role_count) || 0,
      direct_users: Number(r.direct_users) || 0,
    })),
    personas: personasRes.rows.map((r: { id: number | string; fullname: string; department: string; rbac_role_id: string; expenses: string; slips: string; approvals: string; notifications: string }) => ({
      id: Number(r.id),
      fullname: r.fullname,
      department: r.department,
      rbac_role_id: r.rbac_role_id,
      expenses: Number(r.expenses) || 0,
      slips: Number(r.slips) || 0,
      approvals: Number(r.approvals) || 0,
      notifications: Number(r.notifications) || 0,
    })),
  };
}