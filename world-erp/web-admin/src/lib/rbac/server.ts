// Thin shim around @erp-lib/rbac/server. Direct calls (no HTTP).

import 'server-only';
import {
  getOrg as _getOrg,
  getMatrix as _getMatrix,
  can as _can,
  canBatch as _canBatch,
  listModules as _listModules,
  getGroups as _getGroups,
  getGroupsTree as _getGroupsTree,
  listTiles as _listTiles,
  patchCells as _patchCells,
  getAudit as _getAudit,
  setModuleGroups as _setModuleGroups,
  createGroup as _createGroup,
  updateGroup as _updateGroup,
  deleteGroup as _deleteGroup,
  effectiveState as _effectiveState,
  isAccessAllowed as _isAccessAllowed,
  exportMatrix as _exportMatrix,
  ACTIONS as _ACTIONS,
  getSummarySlices as _getSummarySlices,
  type Action,
  type CellChange,
  type GroupRow,
  type TreeNode,
  type AuditEvent,
  type ExportPayload,
  type OrgResponse,
  type MatrixResponse,
  type ModuleRow,
  type RoleNode,
  type ColumnRole,
  type MatrixRow,
  type ResolvedCell,
  type EffectiveState,
  type Source,
  type TileRow,
} from '@erp-lib/rbac/server';

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
};

export interface OrgResponseT { roles: unknown[] }
export interface MatrixResponseT { modules: unknown[]; columns: unknown[]; rows: unknown[] }

export async function getOrg(): Promise<OrgResponseT> { return _getOrg() as unknown as OrgResponseT; }
export async function getMatrix(opts: { moduleIds?: string[]; roleIds?: string[] } = {}): Promise<MatrixResponseT> {
  return _getMatrix(opts) as unknown as MatrixResponseT;
}
export async function can(role: string, moduleId: string, action: 'create' | 'read' | 'update' | 'delete' = 'read') {
  return _can(role, moduleId, action);
}
export async function canBatch(role: string, modules: string[], action: 'create' | 'read' | 'update' | 'delete' = 'read'): Promise<Record<string, boolean>> {
  return _canBatch(role, modules, action);
}
export async function listModules(): Promise<unknown[]> { return _listModules() as unknown as unknown[]; }
export async function getGroups() { return _getGroups(); }
export async function getGroupsTree() { return _getGroupsTree(); }
export async function listTiles() { return _listTiles(); }
export async function getTileBySlug(slug: string): Promise<TileRow | null> {
  const all = (await _listTiles()) as TileRow[];
  return all.find((t) => t.href === '/' + slug) ?? null;
}
export async function patchCells(changes: CellChange[], actor = 'ui', reason?: string) {
  return _patchCells(changes as never, actor, reason);
}
export async function getAudit(opts: Parameters<typeof _getAudit>[0] = {}) {
  return _getAudit(opts);
}
export async function setModuleGroups(moduleId: string, groupIds: string[], actor: string) {
  return _setModuleGroups(moduleId, groupIds, actor);
}
export async function createGroup(input: Parameters<typeof _createGroup>[0]) {
  return _createGroup(input);
}
export async function updateGroup(id: string, patch: Parameters<typeof _updateGroup>[1], actor: string) {
  return _updateGroup(id, patch, actor);
}
export async function deleteGroup(id: string, actor: string) {
  return _deleteGroup(id, actor);
}
export async function effectiveState(rbacRoleId: string, moduleId: string, action: 'create' | 'read' | 'update' | 'delete') {
  return _effectiveState(rbacRoleId, moduleId, action);
}
export async function isAccessAllowed(rbacRoleId: string, moduleId: string, action: 'create' | 'read' | 'update' | 'delete' = 'read'): Promise<boolean> {
  return _isAccessAllowed(rbacRoleId, moduleId, action);
}
export async function exportMatrix(opts: Parameters<typeof _exportMatrix>[0] = {}) {
  return _exportMatrix(opts);
}
export const ACTIONS = _ACTIONS;
export async function getSummarySlices(): Promise<Record<string, unknown>> {
  return _getSummarySlices() as unknown as Record<string, unknown>;
}