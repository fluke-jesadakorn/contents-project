// Single polymorphic INSERT into approval_override_audit.
// Replaces ceo_overrides (kind='granted') and stage_override_audit
// (kind='denied'). Fixes the pre-existing entity_id = 0 bug from the
// old stage_override_audit writer by requiring entityId.
//
// Use this from requireActionFor when override=true, and from
// ceoForceDecision for granted overrides.

import 'server-only';
import { query } from '../db';
import type { ApprovalEntityType, OverrideKind } from './types';

export interface RecordOverrideArgs {
  entityType: ApprovalEntityType;
  entityId: number;
  actorId: number;
  kind: OverrideKind;
  reason: string;
  attemptedStage?: string;
  requiredRole?: string;
  actorRole?: string;
}

export async function recordOverride(args: RecordOverrideArgs): Promise<void> {
  await query(
    `INSERT INTO approval_override_audit
       (target_type, target_id, actor_id, kind, attempted_stage,
        required_role, actor_role, reason)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [
      args.entityType,
      args.entityId,
      args.actorId,
      args.kind,
      args.attemptedStage ?? null,
      args.requiredRole ?? null,
      args.actorRole ?? null,
      args.reason,
    ],
  );
}