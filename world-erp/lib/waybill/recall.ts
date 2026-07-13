import 'server-only';
import { evalPolicy, POL } from '../policy';
import { buildPolicyContextFromCookieValue } from '../policy/context';

export const ALLOW_RECALL = new Set(['cfo', 'ceo', 'admin']);

export async function canActorReCall(actorRole: string | null): Promise<boolean> {
  const ctx = await buildPolicyContextFromCookieValue(null);
  if (!ctx) {
    return !!actorRole && ALLOW_RECALL.has(actorRole);
  }
  const r = await evalPolicy(POL.recallWaybill, ctx);
  return r.allow;
}

export interface ReCallInput {
  waybillId: string;
  targetStage: string;
  actorId: number;
  actorRole: string;
  reason?: string;
}

export async function reCallWaybillAction(_input: ReCallInput): Promise<{ ok: boolean; error?: string }> {
  return { ok: false, error: 'deprecated: use requirePolicy(POL.recallWaybill, ctx)' };
}