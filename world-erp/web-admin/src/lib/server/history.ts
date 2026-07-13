import 'server-only';
import { query } from '@/lib/db';

export async function getOverrideAudit(limit = 100) {
  const { rows } = await query(
    `SELECT a.*, u.fullname AS actor_name
       FROM approval_override_audit a
       LEFT JOIN users u ON a.actor_id = u.id
      ORDER BY a.created_at DESC
      LIMIT $1`,
    [limit],
  );
  return { success: true as const, entries: rows };
}

export async function getHookEventHistory(limit = 100) {
  const { rows } = await query(
    `SELECT id, provider_id, external_id, event_type, received_at, status,
            processed_at, processed_by, replay_count, error
       FROM hook_events
      ORDER BY received_at DESC
      LIMIT $1`,
    [limit],
  );
  return { success: true as const, events: rows };
}

export async function getPolicyAudit(limit = 200) {
  const { rows } = await query(
    `SELECT a.*, u.fullname AS actor_name
       FROM policy_audit a
       LEFT JOIN users u ON a.actor_id = u.id
      ORDER BY a.changed_at DESC
      LIMIT $1`,
    [limit],
  );
  return { success: true as const, entries: rows };
}

export async function getResolvedAccessRequests(limit = 200) {
  const { rows } = await query(
    `SELECT r.*, a.fullname AS actor_name, rv.fullname AS resolver_name
       FROM access_requests r
       LEFT JOIN users a ON r.actor_id = a.id
       LEFT JOIN users rv ON r.resolved_by_user_id = rv.id
      WHERE r.status <> 'pending'
      ORDER BY COALESCE(r.resolved_at, r.created_at) DESC
      LIMIT $1`,
    [limit],
  );
  return { success: true as const, requests: rows };
}

export async function getPastApprovals(actorId: number, limit = 200) {
  const { rows } = await query(
    `SELECT l.*, u.fullname AS actor_name,
            e.vendor_name, e.total_amount, e.id AS expense_id
       FROM approval_transitions l
       JOIN users u ON l.actor_id = u.id
       LEFT JOIN expenses e ON e.id = l.target_id AND l.target_type = 'expense'
      WHERE l.target_type = 'expense'
        AND l.actor_id = $1
        AND l.new_status IN ('awaiting_disbursement', 'rejected', 'disbursed', 'accounting_supervision')
      ORDER BY l.created_at DESC
      LIMIT $2`,
    [actorId, limit],
  );
  return { success: true as const, entries: rows };
}

export async function getPastPrActions(actorId: number, limit = 200) {
  const { rows } = await query(
    `SELECT l.*, u.fullname AS actor_name,
            pr.vendor_name, pr.total_estimate, pr.id AS pr_id
       FROM approval_transitions l
       JOIN users u ON l.actor_id = u.id
       LEFT JOIN purchase_requisitions pr
              ON pr.id = l.target_id AND l.target_type = 'pr'
      WHERE l.target_type = 'pr'
        AND l.actor_id = $1
        AND l.new_status IN ('awaiting_disbursement', 'rejected', 'dept_authorization', 'accounting_authorization', 'cfo_authorization')
      ORDER BY l.created_at DESC
      LIMIT $2`,
    [actorId, limit],
  );
  return { success: true as const, entries: rows };
}
