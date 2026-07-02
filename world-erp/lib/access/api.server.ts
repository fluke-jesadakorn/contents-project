// Server-side access API. Direct calls into `@/lib/rbac/server`.
// Import from this file only in server components, route handlers,
// server actions, and middleware. Client code should use
// `@/lib/access/api` (HTTP fetch) instead.

import {
  getOrg,
  getMatrix,
  listModules,
  patchCells,
  can,
  canBatch,
  getGroups,
  getGroupsTree,
  setModuleGroups,
  getAudit,
  effectiveState,
  isAccessAllowed,
  type Action,
  type CellChange,
} from '../rbac/server';

export type { Action, CellChange };

export const access = {
  org: () => getOrg(),
  matrix: (roleIds?: string[]) => getMatrix({ roleIds }),
  modules: () => listModules(),
  patchCells: (changes: CellChange[], actor = 'ui', reason?: string) =>
    patchCells(changes, actor, reason),
  can: (role: string, moduleId: string, action: Action = 'read') =>
    can(role, moduleId, action),
  canBatch: (role: string, modules: string[], action: Action = 'read') =>
    canBatch(role, modules, action),
  groups: () => getGroups(),
  groupsTree: () => getGroupsTree(),
  setModuleGroups: (moduleId: string, groupIds: string[]) =>
    setModuleGroups(moduleId, groupIds, 'ui'),
  audit: (opts: { role_id?: string; module_id?: string; kind?: string; since?: string; limit?: number } = {}) =>
    getAudit(opts),
};

export { effectiveState, isAccessAllowed, canBatch };
