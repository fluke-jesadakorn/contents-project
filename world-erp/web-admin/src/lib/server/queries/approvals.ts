import { query } from '@/lib/db';
import { getActorScope, scopeFilter, PERM } from '@erp-lib/perm/server';
import { assertRole } from '@/lib/assertRole';
import { aiInvoke } from '@/lib/ai/router';
import { loadActor } from '@/lib/server/guard';

export async function getSemanticSuggestions(description: string) {
  if (!description || description.trim() === '') {
    return { success: true, suggestions: [] };
  }
  try {
    const ai = await aiInvoke('acct:coa-search', 'embed', { text: description });
    if (!ai.ok || !ai.embedding) {
      return { success: false, error: ai.error || 'Could not generate embedding.' };
    }
    const vectorStr = `[${ai.embedding.join(',')}]`;
    const suggestionsRes = await query(`
      SELECT code, name, name_th, account_type,
             (1 - (embedding <=> $1::vector)) as similarity
      FROM chart_of_accounts
      ORDER BY similarity DESC
      LIMIT 3
    `, [vectorStr]);
    return {
      success: true,
      suggestions: suggestionsRes.rows.map((r: any) => ({
        code: r.code,
        name: r.name,
        name_th: r.name_th,
        account_type: r.account_type,
        similarity: parseFloat((r.similarity * 100).toFixed(1))
      }))
    };
  } catch (error: any) {
    console.error('Semantic search error:', error);
    return { success: false, error: error.message };
  }
}

export async function listApprovalPolicies(actorId?: number) {
  try {
    if (actorId) {
      try { await assertRole(actorId, [], { perm: PERM.tile.policy.view }); }
      catch { return { success: false, error: 'forbidden', policies: [] }; }
    }
    const r = await query(
      `SELECT p.*, u.fullname AS created_by_name
       FROM approval_policies p
       LEFT JOIN users u ON p.created_by = u.id
       ORDER BY p.is_active DESC, p.priority ASC, p.id ASC`
    );
    return { success: true, policies: r.rows };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function listPurchaseRequisitions(actorId?: number) {
  try {
    let scopeSql = '';
    let params: any[] = [];
    if (actorId) {
      const actor = await loadActor();
      if (actor) {
        const scope = await getActorScope(new Set(actor.permissions ?? []), actor.id);
        const f = scopeFilter(scope, 'pr.requester_id');
        if (f.clause) {
          scopeSql = 'WHERE ' + f.clause;
          params = f.params;
        }
      }
    }
    const r = await query(
      `SELECT pr.*, u.fullname AS requester_name,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.active_user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_id,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.active_user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_name,
              d.display_name AS dept_name, p.display_name AS policy_name, p.priority AS policy_priority,
              ra.fullname AS rejection_actor_name
       FROM purchase_requisitions pr
       JOIN users u ON pr.requester_id = u.id
       LEFT JOIN perm.roles d ON pr.dept_group_id = d.id
       LEFT JOIN approval_policies p ON pr.matched_policy_id = p.id
       LEFT JOIN users ra ON ra.id = pr.rejection_actor_id
       ${scopeSql}
       ORDER BY pr.created_at DESC`,
      params,
    );
    const prs = r.rows;
    for (const pr of prs) {
      const items = await query(
        `SELECT i.*, c.name_th AS account_name_th FROM pr_items i
         LEFT JOIN chart_of_accounts c ON i.mapped_account_code = c.code
         WHERE i.pr_id = $1 ORDER BY i.id`, [pr.id]
      );
      pr.items = items.rows;
      const prLogs = await query(
        `SELECT l.*, u.fullname AS actor_name
         FROM approval_transitions l
         JOIN users u ON l.actor_id = u.id
         WHERE l.target_type = 'pr' AND l.target_id = $1
         ORDER BY l.created_at ASC`, [pr.id]
      );
      pr.logs = prLogs.rows;
    }
    return { success: true, prs };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function listPurchaseOrders(actorId?: number) {
  try {
    let scopeSql = '';
    let params: any[] = [];
    if (actorId) {
      const actor = await loadActor();
      if (actor) {
        const scope = await getActorScope(new Set(actor.permissions ?? []), actor.id);
        const f = scopeFilter(scope, 'pr.requester_id');
        if (f.clause) {
          scopeSql = 'WHERE ' + f.clause;
          params = f.params;
        }
      }
    }
    const r = await query(
      `SELECT po.*,
              u.fullname AS requester_name,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.active_user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_id,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.active_user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_name,
              d.display_name AS dept_name,
              p.display_name AS policy_name,
              p.priority AS policy_priority,
              s.file_path AS paid_slip_path,
              s.mime_type AS paid_slip_mime,
              su.fullname AS settled_actor_name,
              ra.fullname AS rejection_actor_name
       FROM purchase_orders po
       JOIN purchase_requisitions pr ON po.pr_id = pr.id
       JOIN users u ON pr.requester_id = u.id
       LEFT JOIN perm.roles d ON pr.dept_group_id = d.id
       LEFT JOIN approval_policies p ON po.matched_policy_id = p.id
       LEFT JOIN slips s ON po.settled_slip_id = s.id
       LEFT JOIN users su ON po.settled_by = su.id
       LEFT JOIN users ra ON ra.id = po.rejection_actor_id
       ${scopeSql}
       ORDER BY po.created_at DESC`,
      params,
    );
    const pos = r.rows;
    for (const po of pos) {
      const items = await query(
        `SELECT i.*, c.name_th AS account_name_th FROM po_items i
         LEFT JOIN chart_of_accounts c ON i.mapped_account_code = c.code
         WHERE i.po_id = $1 ORDER BY i.id`,
        [po.id]
      );
      po.items = items.rows;
      const poLogs = await query(
        `SELECT l.*, u.fullname AS actor_name
         FROM approval_transitions l
         JOIN users u ON l.actor_id = u.id
         WHERE l.target_type = 'po' AND l.target_id = $1
         ORDER BY l.created_at ASC`, [po.id]
      );
      po.logs = poLogs.rows;
    }
    return { success: true, pos };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function listSalesOrders(_actorId?: number): Promise<{ rows: any[] }> {
  try {
    const r = await query(
      `SELECT wb.id AS waybill_id,
              wb.origin,
              wb.current_stage,
              wb.total_amount,
              wb.currency,
              wb.created_at,
              wb.updated_at,
              u.fullname AS requester_name,
              wb.vendor_name
         FROM waybills wb
         LEFT JOIN users u ON u.id = wb.submitter_id
         WHERE wb.origin = 'so'
         ORDER BY wb.updated_at DESC NULLS LAST
         LIMIT 100`,
      [],
    );
    return { rows: r.rows };
  } catch (e: any) {
    return { rows: [] };
  }
}

export async function listPayslipsForPo(poId: number) {
  try {
    const r = await query(
      `SELECT id, file_path, mime_type, ocr_confidence, uploaded_at
       FROM slips WHERE po_id = $1 ORDER BY uploaded_at DESC`,
      [poId]
    );
    return { success: true, slips: r.rows };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}