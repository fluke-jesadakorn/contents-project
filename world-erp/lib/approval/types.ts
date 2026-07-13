// Polymorphic approval transition + override helpers.
//
// Replaces the legacy per-entity INSERT sites that previously targeted
// approval_logs / pr_approval_logs / po_approval_logs (now unified into
// approval_transitions) and ceo_overrides / stage_override_audit (now
// unified into approval_override_audit).
//
// All helpers are server-only and consume the shared @erp-lib/db query.

export type ApprovalEntityType = 'expense' | 'pr' | 'po';
export type OverrideKind = 'granted' | 'denied';

export interface ApprovalTransition {
  id: number;
  target_type: ApprovalEntityType;
  target_id: number;
  actor_id: number | null;
  previous_status: string | null;
  new_status: string | null;
  comments: string | null;
  stage: string | null;
  chain_index: number | null;
  created_at: string;
}

export interface ApprovalOverride {
  id: number;
  target_type: ApprovalEntityType;
  target_id: number | null;
  actor_id: number | null;
  kind: OverrideKind;
  attempted_stage: string | null;
  required_role: string | null;
  actor_role: string | null;
  reason: string | null;
  created_at: string;
}

export interface EntityCtx {
  entityType: ApprovalEntityType;
  entityId: number;
}