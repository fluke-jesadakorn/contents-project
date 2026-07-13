import 'server-only';
import { query } from '../db';
import type { EvalResult } from './ast';

export type Surface = 'rsc' | 'api' | 'action' | 'sql' | 'client';

export interface RecordDecisionInput {
  actorId: number | null;
  policyId: string | null;
  surface: Surface;
  target: string;
  decision: 'allow' | 'deny';
  reasons: unknown;
  resource: unknown;
}

export async function recordDecision(input: RecordDecisionInput): Promise<void> {
  try {
    await query(
      `INSERT INTO perm.policy_decisions
         (actor_id, policy_id, surface, target, decision, reasons, resource)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)`,
      [
        input.actorId,
        input.policyId,
        input.surface,
        input.target,
        input.decision,
        JSON.stringify(input.reasons ?? []),
        JSON.stringify(input.resource ?? {}),
      ],
    );
  } catch {
    /* swallow — audit failure never blocks business */
  }
}

export async function recordResult(
  result: EvalResult,
  input: Omit<RecordDecisionInput, 'decision'>,
): Promise<void> {
  await recordDecision({
    ...input,
    decision: result.allow ? 'allow' : 'deny',
    reasons: result.reasons,
  });
}