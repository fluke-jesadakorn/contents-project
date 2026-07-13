// Single polymorphic INSERT into approval_transitions.
// Replaces all 15 bespoke INSERTs that previously hit approval_logs,
// pr_approval_logs, and po_approval_logs.
//
// Use this from any server action that flips an expense / PR / PO
// between approval statuses.

import 'server-only';
import { query } from '../db';
import type { ApprovalEntityType } from './types';

export interface RecordTransitionArgs {
  entityType: ApprovalEntityType;
  entityId: number;
  actorId: number | null;
  previousStatus: string | null;
  newStatus: string | null;
  comments?: string | null;
  stage?: string | null;
  chainIndex?: number | null;
}

export async function recordTransition(args: RecordTransitionArgs): Promise<void> {
  await query(
    `INSERT INTO approval_transitions
       (target_type, target_id, actor_id, previous_status, new_status,
        comments, stage, chain_index)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [
      args.entityType,
      args.entityId,
      args.actorId,
      args.previousStatus,
      args.newStatus,
      args.comments ?? null,
      args.stage ?? null,
      args.chainIndex ?? null,
    ],
  );
}