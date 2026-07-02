// Type re-exports for client + server use. Mirrors @erp-lib/access/types.

export type Action = 'create' | 'read' | 'update' | 'delete';
export type CellState = 'allow' | 'deny' | 'inherit';
export type EffectiveState = 'allow' | 'deny';
export type Source =
  | 'explicit'
  | 'inherited_from_parent'
  | 'inherited_from_tenant'
  | 'group_cascade'
  | 'default'
  | 'admin_override';

export interface ResolvedCell {
  state: EffectiveState;
  source: Source;
  inheritedFrom?: string;
}

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

export interface GroupRow {
  id: string;
  name: string;
  kind: 'module-group' | 'department' | 'team';
  parent_id: string | null;
  sort_order: number;
  is_system: boolean;
}

export interface TreeNode extends GroupRow {
  children: TreeNode[];
  modules: { id: string; display_name: string }[];
  roles: { id: string; name: string }[];
}

export interface AuditEvent {
  id: number;
  kind: string;
  actor: string;
  target: any;
  occurred_at: string;
}

export interface ExportPayload {
  generated_at: string;
  modules: ModuleRow[];
  roles: ColumnRole[];
  matrix: { module_id: string; cells: Record<string, Record<Action, ResolvedCell>> }[];
}

export type DomainRow = { id: string; name: string };
export type DomainModule = { id: string; name: string };
export type DomainVisibility = { state: 'allow' | 'deny' };
export type RoleColumn = { id: string; name: string };
export type VisibilityMatrixResponse = { domains: unknown[]; roles: unknown[]; cells: unknown[] };
export type DomainScopeChange = { role_id: string; domain_id: string; state: 'allow' | 'deny' };
export type ScopeKind = 'self' | 'department' | 'all' | 'subtree';