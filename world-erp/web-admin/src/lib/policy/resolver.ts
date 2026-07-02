// DB-backed policy resolvers (imported by server actions).

import { query } from '../db';
import { pickPolicy, type Policy, type Context } from './engine';

export async function loadActivePolicies(targetType?: 'expense' | 'pr' | 'po' | 'both'): Promise<Policy[]> {
  const params: any[] = [];
  let where = 'WHERE is_active = TRUE';
  if (targetType) {
    if (targetType === 'both') {
      where += ` AND target_type = 'both'`;
    } else {
      params.push(targetType);
      where += ` AND (target_type = $1 OR target_type = 'both')`;
    }
  }
  const r = await query(
    `SELECT id, name, priority, is_active, target_type, conditions_json, action_json
     FROM approval_policies
     ${where}
     ORDER BY priority ASC`,
    params
  );
  return r.rows.map((row: any) => ({
    id: row.id,
    name: row.name,
    priority: row.priority,
    is_active: !!row.is_active,
    target_type: row.target_type,
    conditions_json: row.conditions_json || {},
    action_json: row.action_json || { approver_chain: [] },
  }));
}

export async function resolvePolicyForContext(ctx: Context): Promise<(Policy & { action: any }) | null> {
  const policies = await loadActivePolicies(ctx.targetType);
  const matched = pickPolicy(policies, ctx);
  if (!matched) return null;
  return { ...matched, action: matched.action_json };
}
