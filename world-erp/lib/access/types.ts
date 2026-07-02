// Re-exports of the public RBAC types so client and server can import
// them from `@/lib/access/api` (the client-facing entry) or
// `@/lib/access/types` (pure types, no server import).
//
// These are erased at compile time — no static dependency on the server
// module is created.

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
} from '../rbac/server';
