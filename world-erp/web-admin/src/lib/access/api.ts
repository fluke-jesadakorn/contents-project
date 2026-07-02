// Client-side access API. HTTP fetch to the local Next.js /api/* routes
// (which now resolve in-process; the Fastify rbac-svc is gone).

export type {
  Action,
  EffectiveState,
  ResolvedCell,
  Source,
  RoleNode,
  ModuleRow,
  ColumnRole,
  MatrixRow,
  OrgResponse,
  MatrixResponse,
  CellChange,
  GroupRow,
  TreeNode,
  AuditEvent,
  ExportPayload,
  DomainRow,
  DomainModule,
  DomainVisibility,
  RoleColumn,
  VisibilityMatrixResponse,
  DomainScopeChange,
  ScopeKind,
} from './types';

import type {
  Action,
  CellChange,
  GroupRow,
  MatrixResponse,
  ModuleRow,
  OrgResponse,
  TreeNode,
  AuditEvent,
  VisibilityMatrixResponse,
  DomainScopeChange,
} from './types';

async function getJson<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, { cache: 'no-store', ...init });
  if (!res.ok) throw new Error(`${init?.method ?? 'GET'} ${path} → ${res.status}`);
  return (await res.json()) as T;
}

export const access = {
  org: () => getJson<OrgResponse>('/api/org'),
  matrix: (roleIds?: string[]) => {
    const q = roleIds?.length ? `?roles=${roleIds.join(',')}` : '';
    return getJson<MatrixResponse>(`/api/matrix${q}`);
  },
  modules: () =>
    getJson<{ modules: ModuleRow[] }>('/api/modules').then((r) => r.modules),
  patchCells: (changes: CellChange[], actor = 'ui', reason?: string) =>
    getJson<{ ok: boolean; applied: number }>('/api/cells', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ changes, actor, reason }),
    }),
  can: (role: string, moduleId: string, action: Action = 'read') => {
    const params = new URLSearchParams({ role, module: moduleId, action });
    return getJson<{ allow: boolean; source: string; inheritedFrom: string | null }>(
      `/api/can?${params.toString()}`,
    );
  },
  canBatch: (role: string, modules: string[], action: Action = 'read') =>
    getJson<{ role: string; action: Action; allow: Record<string, boolean> }>(
      '/api/can-batch',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ role, modules, action }),
      },
    ),
  groups: () =>
    getJson<{ groups: GroupRow[] }>('/api/groups').then((r) => r.groups),
  groupsTree: () =>
    getJson<{ tree: TreeNode[] }>('/api/groups/tree').then((r) => r.tree),
  setModuleGroups: (moduleId: string, groupIds: string[]) =>
    getJson<{ ok: boolean }>(`/api/modules/${moduleId}/groups`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ group_ids: groupIds }),
    }),
  audit: (opts: { role_id?: string; module_id?: string; kind?: string; since?: string; limit?: number } = {}) => {
    const params = new URLSearchParams();
    if (opts.role_id) params.set('role_id', opts.role_id);
    if (opts.module_id) params.set('module_id', opts.module_id);
    if (opts.kind) params.set('kind', opts.kind);
    if (opts.since) params.set('since', opts.since);
    if (opts.limit) params.set('limit', String(opts.limit));
    const q = params.toString();
    return getJson<{ events: AuditEvent[] }>(`/api/audit${q ? `?${q}` : ''}`).then((r) => r.events);
  },
  health: () =>
    fetch(`/api/health`).then((r) => r.ok ? { ok: true, service: 'up' as const } : { ok: false, service: 'down' as const }).catch(() => ({ ok: false, service: 'down' as const })),
  visibilityMatrix: (opts: { domains?: string[]; roles?: string[]; user_id?: number } = {}) => {
    const params = new URLSearchParams();
    if (opts.domains?.length) params.set('domains', opts.domains.join(','));
    if (opts.roles?.length) params.set('roles', opts.roles.join(','));
    if (opts.user_id) params.set('user_id', String(opts.user_id));
    const q = params.toString();
    return getJson<VisibilityMatrixResponse>(`/api/visibility${q ? `?${q}` : ''}`);
  },
  patchDomainScope: (changes: DomainScopeChange[], actor = 'ui', reason?: string) =>
    getJson<{ ok: boolean; applied: number }>('/api/visibility/scope', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ changes, actor, reason }),
    }),
  resetDomainScope: (roleId: string, domainId: string, actor = 'ui') =>
    getJson<{ ok: boolean; deleted: boolean }>('/api/visibility/scope', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ changes: [], actor, reset: { role_id: roleId, domain_id: domainId } }),
    }).catch(() => ({ ok: false, deleted: false })),
  roleTeams: (role: string) =>
    getJson<{ role: string; teams: { id: string; name: string }[] }>(
      `/api/visibility/teams?role=${encodeURIComponent(role)}`,
    ).then((r) => r.teams),
  teams: () =>
    getJson<{ teams: { id: string; name: string; parent_id: string | null; sort_order: number }[] }>(
      '/api/teams',
    ).then((r) => r.teams),
};