// Client-side access API. HTTP fetch only — no server imports.
// Server-side direct access lives in `@/lib/access/api.server`.
//
// Type re-exports here are erased at compile time, so the `pg` server
// chain never reaches the client bundle.

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
    getJson<{ ok: boolean; service: string }>('/health').catch(() => ({ ok: false, service: 'down' })),
};
