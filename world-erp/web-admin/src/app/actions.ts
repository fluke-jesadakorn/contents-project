'use server';

import { revalidatePath } from 'next/cache';
import { query } from '@/lib/db';
import { requireActionFor } from '@/lib/server/requireActionFor';
import { loadActor } from '@/lib/server/guard';
import { canPerformAction } from '@/lib/permissions';
import { isAccessAllowed } from '@/lib/access/api.server';
import { evaluateStage } from '@/lib/rbac/stage';
import { getActorScope, assertInScope } from '@/lib/rbac/scope';
import { STAGE_TO_ROLE, APPROVER_TO_STAGE } from '@/lib/rbac/stage-types';
import { postExpenseToGL } from '@/lib/finance/postExpenseToGL';

async function requireActorOrNull() {
  return loadActor();
}
import { aiInvoke } from '@/lib/ai/router';
import { resolveDynamicChain } from '@/lib/policy/engine';
import { resolvePolicyForContext } from '@/lib/policy/resolver';
import { publish as publishEvent } from '@/lib/events';

async function semanticCoaMatch(description: string): Promise<{ code: string | null; score: number }> {
  if (!description || !description.trim()) return { code: null, score: 0 };
  const res = await aiInvoke('acct:coa-search', 'embed', { text: description });
  if (!res.ok || !res.embedding) return { code: null, score: 0 };
  const vectorStr = `[${res.embedding.join(',')}]`;
  const matchRes = await query(
    `SELECT code, (1 - (embedding <=> $1::vector)) AS similarity
     FROM chart_of_accounts
     ORDER BY similarity DESC LIMIT 1`,
    [vectorStr]
  );
  if (matchRes.rows.length === 0) return { code: null, score: 0 };
  return { code: matchRes.rows[0].code, score: matchRes.rows[0].similarity };
}

export async function getSemanticSuggestions(description: string) {
  // Anyone authenticated with read access to expenses may search COA.
  const actor = await requireActorOrNull();
  if (!actor) return { success: false, error: 'unauthorized' } as const;
  const hasRead = actor.rbac_role_id
    ? await isAccessAllowed(actor.rbac_role_id, 'tile-search-coa', 'read')
    : canPerformAction(actor.role_name as any, 'view_all_expenses');
  if (!hasRead) return { success: false, error: 'forbidden' } as const;

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
        similarity: parseFloat((r.similarity * 100).toFixed(1)),
      })),
    };
  } catch (error: any) {
    console.error('Semantic search error:', error);
    return { success: false, error: error.message };
  }
}

// Staff submits an expense by uploading a slip (image / PDF). The slip
// pipeline is in /api/upload; this action finalizes the expense row from
// the persisted slip's ocr_raw_json. See submitExpenseFromSlip() below.
export async function reviewAndCorrectExpense(
  expenseId: number,
  actorId: number,
  updates: {
    vendorName: string;
    transactionDate: string;
    subtotal: number;
    vatAmount: number;
    totalAmount: number;
    paymentMethod: string;
    isCorrupted: boolean;
    correctionNotes: string;
    items: Array<{ id: number; description: string; amount: number; code: string }>;
  }
) {
  try {
    await requireActionFor(actorId, 'review_expense', { rbacSection: 'core-operations', rbacAction: 'update' });
    await query('BEGIN');

    await query(`
      UPDATE expenses
      SET vendor_name = $1, transaction_date = $2, subtotal = $3, vat_amount = $4, total_amount = $5,
          payment_method = $6, is_corrupted = $7, correction_notes = $8, status = 'accountant_reviewed',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $9
    `, [
      updates.vendorName, updates.transactionDate, updates.subtotal, updates.vatAmount,
      updates.totalAmount, updates.paymentMethod, updates.isCorrupted,
      updates.correctionNotes, expenseId
    ]);

    for (const item of updates.items) {
      await query(`
        UPDATE expense_items
        SET description = $1, amount = $2, mapped_account_code = $3, confidence_score = 1.0
        WHERE id = $4 AND expense_id = $5
      `, [item.description, item.amount, item.code, item.id, expenseId]);
    }

    await query(`
      INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments)
      VALUES ($1, $2, 'ocr_extracted', 'accountant_reviewed', 'Accountant corrected values and confirmed accounts')
    `, [expenseId, actorId]);

    await query('COMMIT');
    revalidatePath('/');
    revalidatePath('/dashboard');
    revalidatePath('/');
    return { success: true };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('Failed to review expense:', error);
    return { success: false, error: error.message };
  }
}

export async function changeExpenseStatus(
  expenseId: number,
  actorId: number,
  newStatus: string,
  comments: string
) {
  try {
    if (newStatus === 'approved' || newStatus === 'rejected') {
      await requireActionFor(actorId, 'approve_expense', { rbacSection: 'core-operations', rbacAction: 'update' });
    } else if (newStatus === 'paid') {
      await requireActionFor(actorId, 'settle_payment', { rbacSection: 'core-operations', rbacAction: 'update' });
    }

    if (newStatus === 'rejected') {
      const t = (comments || '').trim();
      if (t.length < 5) throw new Error('Rejection reason required, min 5 chars');
    }

    await query('BEGIN');

    const curRes = await query('SELECT status FROM expenses WHERE id = $1', [expenseId]);
    if (curRes.rows.length === 0) throw new Error('Expense not found.');
    const previousStatus = curRes.rows[0].status;

    // Stage-level enforcement: the actor's role must match the current approval stage
    // unless they're a CEO/admin who may override (audit row written by requireActionFor).
    if (newStatus === 'approved' || newStatus === 'rejected') {
      const stageRes = await requireActionFor(actorId, 'approve_expense', {
        rbacSection: 'core-operations',
        rbacAction: 'update',
        stage: previousStatus,
      });
      if (stageRes.override) {
        await query(
          `INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments)
           VALUES ($1, $2, $3, $4, $5)`,
          [expenseId, actorId, previousStatus, newStatus, `[stage_override] ${comments || ''}`.trim()],
        );
      }
    }

    if (newStatus === 'rejected') {
      await query(`
        UPDATE expenses
        SET status = $1, updated_at = CURRENT_TIMESTAMP,
            rejection_reason = $3, rejection_actor_id = $4, rejected_at = CURRENT_TIMESTAMP
        WHERE id = $2
      `, [newStatus, expenseId, (comments || '').trim(), actorId]);
    } else {
      await query(`
        UPDATE expenses SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2
      `, [newStatus, expenseId]);
    }

    await query(`
      INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments)
      VALUES ($1, $2, $3, $4, $5)
    `, [expenseId, actorId, previousStatus, newStatus, comments || `Status changed to ${newStatus}`]);

    if (newStatus === 'paid') {
      const expRes = await query('SELECT total_amount, vat_amount, vendor_name FROM expenses WHERE id = $1', [expenseId]);
      const exp = expRes.rows[0];
      await postExpenseToGL({
        expenseId,
        vendorName: exp.vendor_name,
        totalAmount: exp.total_amount,
        vatAmount: exp.vat_amount,
      });
    }

    await query('COMMIT');
    revalidatePath('/');
    revalidatePath('/dashboard');
    revalidatePath('/');
    return { success: true };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('Failed to change status:', error);
    return { success: false, error: error.message };
  }
}

export async function submitExpenseFromSlip(args: {
  slipId: number;
  actorId: number;
  overrides?: {
    vendorName?: string;
    transactionDate?: string;
    paymentMethod?: string;
  };
}) {
  try {
    await requireActionFor(args.actorId, 'submit_expense', { rbacSection: 'core-operations', rbacAction: 'create' });

    const slipRes = await query(`SELECT * FROM slips WHERE id = $1`, [args.slipId]);
    if (slipRes.rows.length === 0) throw new Error('Slip not found');
    const slip = slipRes.rows[0];
    const parsed = slip.ocr_raw_json || {};

    const vendor = args.overrides?.vendorName || parsed.vendorName || 'Unknown Vendor';
    const txnDate = args.overrides?.transactionDate || parsed.transactionDate || new Date().toISOString().split('T')[0];
    const subtotal = Number(parsed.subtotal ?? 0);
    const vatAmount = Number(parsed.vatAmount ?? 0);
    const totalAmount = Number(parsed.totalAmount ?? subtotal + vatAmount);
    const paymentMethod = args.overrides?.paymentMethod || parsed.paymentMethod || 'cash';
    const isCorrupted = !!parsed.isCorrupted;
    const correctionNotes = parsed.correctionNotes || '';

    await query('BEGIN');

    const headerRes = await query(
      `INSERT INTO expenses (
         submitter_id, vendor_name, transaction_date, subtotal, vat_amount, total_amount,
         payment_method, status, is_corrupted, correction_notes, ocr_raw_json, document_url
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,'ocr_extracted',$8,$9,$10,$11)
       RETURNING id`,
      [
        args.actorId, vendor, txnDate, subtotal, vatAmount, totalAmount, paymentMethod,
        isCorrupted, correctionNotes, JSON.stringify(parsed),
        `/api/slips/file?key=${encodeURIComponent(slip.file_path)}`,
      ]
    );
    const expenseId = headerRes.rows[0].id;

    await query(`UPDATE slips SET expense_id = $1 WHERE id = $2`, [expenseId, args.slipId]);

    const items = Array.isArray(parsed.items) ? parsed.items : [];
    for (const item of items) {
      let bestCode: string | null = null;
      let score = 0;
      try {
        const match = await semanticCoaMatch(item.description);
        if (match.code) { bestCode = match.code; score = match.score; }
      } catch {}
      await query(
        `INSERT INTO expense_items (expense_id, description, amount, mapped_account_code, confidence_score)
         VALUES ($1,$2,$3,$4,$5)`,
        [expenseId, item.description, Number(item.amount) || 0, bestCode, score]
      );
    }

    const submitterRes = await query(
      `SELECT u.department, u.dept_group_id, g.name AS dept_group_name, r.name AS role_name
       FROM users u
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN rbac.groups g ON g.id = u.dept_group_id
       WHERE u.id = $1`,
      [args.actorId]
    );
    const submitter = submitterRes.rows[0];
    const matched = await resolvePolicyForContext({
      targetType: 'expense',
      totalAmount,
      department: submitter?.department || null,
      submitterRole: submitter?.role_name || null,
      isRecurring: false,
    });

    let initialStatus = 'ocr_extracted';
    const chainIndex = 0;
    if (matched && matched.action.auto_approve) {
      initialStatus = 'approved';
    } else if (matched && matched.action.approver_chain.length > 0) {
      const first = matched.action.approver_chain[0];
      initialStatus = APPROVER_TO_STAGE[first] || 'head_review';
    }

    await query(`UPDATE expenses SET status = $1 WHERE id = $2`, [initialStatus, expenseId]);
    await query(
      `INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments, stage, chain_index)
       VALUES ($1, $2, NULL, $3, $4, $5, $6)`,
      [
        expenseId, args.actorId, initialStatus,
        matched ? `Matched policy #${matched.id} ${matched.name}` : 'No active policy matched (default chain)',
        initialStatus, chainIndex,
      ]
    );

    await query('COMMIT');
    await publishEvent('expense.submitted', { expenseId, status: initialStatus, policyId: matched?.id }, {
      actorId: args.actorId, refType: 'expense', refId: Number(expenseId),
      severity: 'info',
      message: `Submitted expense #EXP-${expenseId} initial status ${initialStatus}`,
    });
    revalidatePath('/');
    revalidatePath('/dashboard');
    revalidatePath('/');
    return { success: true, expenseId, status: initialStatus, policy: matched || null };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('submitExpenseFromSlip failed:', error);
    return { success: false, error: error.message };
  }
}

export async function advanceApproval(args: {
  expenseId: number;
  actorId: number;
  decision: 'approve' | 'reject';
  comment?: string;
}) {
  try {
    await requireActionFor(args.actorId, 'approve_expense', { rbacSection: 'core-operations', rbacAction: 'update' });

    const expRes = await query(
      `SELECT e.*, u.department AS submitter_dept, u.department_id AS submitter_dept_id,
              u.dept_group_id AS submitter_dept_group_id,
              dg.name AS submitter_dept_group_name,
              r.name AS submitter_role
       FROM expenses e
       JOIN users u ON e.submitter_id = u.id
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
       WHERE e.id = $1`,
      [args.expenseId]
    );
    if (expRes.rows.length === 0) throw new Error('Expense not found');
    const exp = expRes.rows[0];

    const actorRes = await query(
      `SELECT u.id, u.department, u.department_id, u.dept_group_id, dg.name AS dept_group_name, r.name AS role_name
       FROM users u
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
       WHERE u.id = $1`,
      [args.actorId]
    );
    const actor = actorRes.rows[0];

    {
      const scope = await getActorScope(actor.rbac_role_id ?? null, actor.id);
      await assertInScope(scope, exp.submitter_id);
    }

    const policy = await resolvePolicyForContext({
      targetType: 'expense',
      totalAmount: Number(exp.total_amount),
      department: exp.submitter_dept,
      submitterRole: exp.submitter_role,
      isRecurring: false,
    });

    const rawChain = (policy?.action?.approver_chain && policy.action.approver_chain.length > 0)
      ? policy.action.approver_chain
      : ['head_of_department', 'accounting_manager'];

    const existingRoleRes = await query(
      `SELECT DISTINCT r.name FROM roles r JOIN users u ON u.role_id=r.id WHERE u.is_active=TRUE`
    );
    const existingRoles = new Set<string>(existingRoleRes.rows.map((r: any) => r.name));
    const mgrRes = await query(
      `SELECT r.name AS mgr_role FROM users u LEFT JOIN users m ON u.reports_to_user_id=m.id LEFT JOIN roles r ON m.role_id=r.id WHERE u.id=$1`,
      [exp.submitter_id]
    );
    const submitterManagerRole = mgrRes.rows[0]?.mgr_role || null;
    const { chain } = resolveDynamicChain({
      chain: rawChain, existingRoles,
      submitterRole: exp.submitter_role, submitterManagerRole,
    });

    const currentStage = exp.status;

    if (args.decision === 'reject') {
      const t = (args.comment || '').trim();
      if (t.length < 5) throw new Error('Rejection reason required, min 5 chars');
      await query('BEGIN');
      await query(
        `UPDATE expenses
         SET status = 'rejected', updated_at = CURRENT_TIMESTAMP,
             rejection_reason = $2, rejection_actor_id = $3, rejected_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [args.expenseId, t, args.actorId]
      );
      await query(
        `INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments, stage)
         VALUES ($1, $2, $3, 'rejected', $4, $5)`,
        [args.expenseId, args.actorId, currentStage, t, currentStage]
      );
      await query('COMMIT');
      await publishEvent('expense.rejected', { expenseId: args.expenseId, reason: t }, {
        actorId: args.actorId, refType: 'expense', refId: Number(args.expenseId),
        severity: 'warning',
        message: `Item #EXP-${args.expenseId} rejected: ${t}`,
      });
      revalidatePath('/');
      revalidatePath('/dashboard');
      revalidatePath('/');
      return { success: true, newStatus: 'rejected', rejectionReason: t };
    }

    const STAGE_TO_CHAIN_ROLE: Record<string, string | null> = STAGE_TO_ROLE;

    let nextIndex: number;
    let nextRole: string | null = null;
    if (currentStage in STAGE_TO_CHAIN_ROLE) {
      const stageRole = STAGE_TO_CHAIN_ROLE[currentStage];
      const idxInChain = chain.indexOf(stageRole as string);
      if (idxInChain < 0) {
        nextIndex = 0;
        nextRole = chain[0];
      } else {
        const stageAccess = await evaluateStage(actor.rbac_role_id, currentStage);
        if (!stageAccess.allow) {
          throw new Error(`Current stage "${currentStage}" requires role "${stageRole}", but actor is "${actor.role_name}"`);
        }
        nextIndex = idxInChain + 1;
        nextRole = chain[nextIndex] || null;
      }
    } else {
      nextIndex = 0;
      nextRole = chain[0] || null;
    }

    const final = nextIndex >= chain.length;
    let newStatus: string;
    if (final) newStatus = 'approved';
    else if (nextRole && APPROVER_TO_STAGE[nextRole]) newStatus = APPROVER_TO_STAGE[nextRole] as string;
    else newStatus = 'approved';

    await query('BEGIN');
    await query(`UPDATE expenses SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, [newStatus, args.expenseId]);
    await query(
      `INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments, stage, chain_index)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        args.expenseId, args.actorId, currentStage, newStatus,
        args.comment || `Approved by ${actor.role_name}`,
        currentStage, nextIndex,
      ]
    );
    await query('COMMIT');

    await publishEvent('expense.advanced', { expenseId: args.expenseId, newStatus, final }, {
      actorId: args.actorId, refType: 'expense', refId: Number(args.expenseId),
      severity: newStatus === 'rejected' ? 'warning' : 'success',
      message: `Item #EXP-${args.expenseId} → ${newStatus}${final ? ' (completed)' : ''}`,
    });

    revalidatePath('/');
    revalidatePath('/dashboard');
    revalidatePath('/');
    return {
      success: true,
      newStatus,
      policy: policy ? { id: policy.id, name: policy.name } : null,
      chainIndex: nextIndex,
      final,
    };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('advanceApproval failed:', error);
    return { success: false, error: error.message };
  }
}

export async function ceoForceDecision(args: {
  targetType: 'expense' | 'pr';
  targetId: number;
  actorId: number;
  newStatus: 'approved' | 'rejected' | 'paid';
  reason: string;
}) {
  try {
    await requireActionFor(args.actorId, 'ceo_override', { rbacSection: 'core-operations', rbacAction: 'update' });
    if (!args.reason || args.reason.trim().length < 5) {
      throw new Error('Override reason is required (min 5 chars)');
    }

    const table = args.targetType === 'pr' ? 'purchase_requisitions' : 'expenses';
    await query('BEGIN');
    const cur = await query(`SELECT status FROM ${table} WHERE id = $1`, [args.targetId]);
    if (cur.rows.length === 0) throw new Error('Target not found');
    const previousStatus = cur.rows[0].status;

    const reasonTrim = args.reason.trim();
    if (args.newStatus === 'rejected') {
      if (args.targetType === 'expense') {
        await query(
          `UPDATE expenses
           SET status = $1, updated_at = CURRENT_TIMESTAMP,
               rejection_reason = $3, rejection_actor_id = $4, rejected_at = CURRENT_TIMESTAMP
           WHERE id = $2`,
          [args.newStatus, args.targetId, reasonTrim, args.actorId]
        );
      } else {
        await query(
          `UPDATE purchase_requisitions
           SET status = $1, updated_at = CURRENT_TIMESTAMP,
               rejection_reason = $3, rejection_actor_id = $4, rejected_at = CURRENT_TIMESTAMP
           WHERE id = $2`,
          [args.newStatus, args.targetId, reasonTrim, args.actorId]
        );
      }
    } else {
      await query(`UPDATE ${table} SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, [args.newStatus, args.targetId]);
    }
    await query(
      `INSERT INTO ceo_overrides (target_type, target_id, actor_id, reason)
       VALUES ($1, $2, $3, $4)`,
      [args.targetType, args.targetId, args.actorId, reasonTrim]
    );
    if (args.targetType === 'expense') {
      await query(
        `INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments, stage)
         VALUES ($1, $2, $3, $4, $5, 'ceo_override')`,
        [args.targetId, args.actorId, previousStatus, args.newStatus, `CEO OVERRIDE: ${reasonTrim}`]
      );
    } else if (args.targetType === 'pr') {
      await query(
        `INSERT INTO pr_approval_logs (pr_id, actor_id, previous_status, new_status, comments, stage)
         VALUES ($1, $2, $3, $4, $5, 'ceo_override')`,
        [args.targetId, args.actorId, previousStatus, args.newStatus, `CEO OVERRIDE: ${reasonTrim}`, 'ceo_override']
      );
    }
    await query('COMMIT');
    await publishEvent('ceo.override', { targetType: args.targetType, targetId: args.targetId, newStatus: args.newStatus }, {
      actorId: args.actorId, refType: args.targetType, refId: Number(args.targetId),
      severity: 'warning',
      message: `CEO Override: ${args.targetType.toUpperCase()} #${args.targetId} → ${args.newStatus}`,
    });
    revalidatePath('/');
    revalidatePath('/dashboard');
    revalidatePath('/');
    return { success: true, newStatus: args.newStatus, rejectionReason: args.newStatus === 'rejected' ? reasonTrim : undefined };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('ceoForceDecision failed:', error);
    return { success: false, error: error.message };
  }
}

export async function upsertApprovalPolicy(args: {
  id?: number;
  name: string;
  priority: number;
  is_active: boolean;
  target_type: 'expense' | 'pr' | 'both';
  conditions_json: any;
  action_json: any;
  actorId: number;
}) {
  try {
    await requireActionFor(args.actorId, 'edit_policy');
    if (!args.name || args.name.trim().length < 3) {
      throw new Error('Policy name is required (≥ 3 chars)');
    }
    const before = args.id
      ? (await query('SELECT * FROM approval_policies WHERE id = $1', [args.id])).rows[0]
      : null;
    let row;
    if (args.id) {
      const r = await query(
        `UPDATE approval_policies
         SET name=$1, priority=$2, is_active=$3, target_type=$4,
             conditions_json=$5, action_json=$6, updated_at=CURRENT_TIMESTAMP
         WHERE id=$7 RETURNING *`,
        [args.name, args.priority, args.is_active, args.target_type,
         JSON.stringify(args.conditions_json), JSON.stringify(args.action_json), args.id]
      );
      row = r.rows[0];
    } else {
      const r = await query(
        `INSERT INTO approval_policies
         (name, priority, is_active, target_type, conditions_json, action_json, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
        [args.name, args.priority, args.is_active, args.target_type,
         JSON.stringify(args.conditions_json), JSON.stringify(args.action_json), args.actorId]
      );
      row = r.rows[0];
    }
    await query(
      `INSERT INTO policy_audit (policy_id, actor_id, before_json, after_json)
       VALUES ($1,$2,$3,$4)`,
      [row.id, args.actorId, JSON.stringify(before || {}), JSON.stringify(row)]
    );
    revalidatePath('/');
    revalidatePath('/');
    return { success: true, policy: row };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function deleteApprovalPolicy(args: { id: number; actorId: number }) {
  try {
    await requireActionFor(args.actorId, 'edit_policy');
    await query(
      `UPDATE approval_policies SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
      [args.id]
    );
    revalidatePath('/');
    revalidatePath('/');
    return { success: true };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function submitPurchaseRequisition(args: {
  requesterId: number;
  vendorName: string;
  departmentId: number;
  needByDate?: string;
  totalEstimate: number;
  currency?: string;
  justification: string;
  isRecurring?: boolean;
  items: Array<{ description: string; qty: number; unit_price: number; mapped_account_code?: string }>;
}) {
  try {
    await requireActionFor(args.requesterId, 'submit_pr', { rbacSection: 'core-operations', rbacAction: 'create' });

    const deptRes = await query(`SELECT name FROM departments WHERE id = $1`, [args.departmentId]);
    const departmentName = deptRes.rows[0]?.name || null;

    const matched = await resolvePolicyForContext({
      targetType: 'pr',
      totalAmount: Number(args.totalEstimate) || 0,
      department: departmentName,
      submitterRole: 'staff',
      isRecurring: !!args.isRecurring,
    });

    let initialStatus = 'draft';
    if (matched && matched.action.auto_approve) {
      initialStatus = 'approved';
    } else if (matched && matched.action.approver_chain.length > 0) {
      const first = matched.action.approver_chain[0];
      initialStatus = APPROVER_TO_STAGE[first] || 'head_review';
    }

    await query('BEGIN');
    const r = await query(
      `INSERT INTO purchase_requisitions
       (requester_id, department_id, vendor_name, need_by_date, status,
        total_estimate, currency, justification, is_recurring, matched_policy_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
      [args.requesterId, args.departmentId, args.vendorName, args.needByDate || null,
       initialStatus, Number(args.totalEstimate) || 0, args.currency || 'THB',
       args.justification, !!args.isRecurring, matched?.id || null]
    );
    const prId = r.rows[0].id;
    for (const item of args.items) {
      await query(
        `INSERT INTO pr_items (pr_id, description, qty, unit_price, mapped_account_code, confidence_score)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [prId, item.description, item.qty, item.unit_price,
         item.mapped_account_code || null, item.mapped_account_code ? 1.0 : 0.0]
      );
    }
    await query('COMMIT');
    await publishEvent('pr.submitted', { prId, status: initialStatus }, {
      actorId: args.requesterId, refType: 'pr', refId: Number(prId),
      severity: 'info',
      message: `Submitted purchase request #PR-${prId} initial status ${initialStatus}`,
    });
    revalidatePath('/');
    revalidatePath('/');
    return { success: true, prId, status: initialStatus, policy: matched || null };
  } catch (error: any) {
    await query('ROLLBACK');
    return { success: false, error: error.message };
  }
}

export async function advancePurchaseRequisition(args: {
  prId: number;
  actorId: number;
  decision: 'approve' | 'reject';
  comment?: string;
}) {
  try {
    await requireActionFor(args.actorId, 'approve_pr', { rbacSection: 'core-operations', rbacAction: 'update' });
    const prRes = await query(
      `SELECT pr.*, d.name AS dept_name, dg.id AS dept_group_id, dg.name AS dept_group_name
         FROM purchase_requisitions pr
         LEFT JOIN departments d ON pr.department_id = d.id
         LEFT JOIN rbac.groups dg ON dg.kind = 'department' AND dg.name = d.name
        WHERE pr.id = $1`,
      [args.prId]
    );
    if (prRes.rows.length === 0) throw new Error('PR not found');
    const pr = prRes.rows[0];

    const actorRes = await query(
      `SELECT u.id, u.department, u.department_id, u.dept_group_id, dg.name AS dept_group_name, r.name AS role_name
       FROM users u
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
       WHERE u.id = $1`,
      [args.actorId]
    );
    const actor = actorRes.rows[0];

    {
      const scope = await getActorScope(actor.rbac_role_id ?? null, actor.id);
      await assertInScope(scope, pr.requester_id);
    }

    const policy = await resolvePolicyForContext({
      targetType: 'pr',
      totalAmount: Number(pr.total_estimate),
      department: pr.dept_name,
      submitterRole: 'staff',
      isRecurring: !!pr.is_recurring,
    });
    const rawChain = (policy?.action?.approver_chain && policy.action.approver_chain.length > 0)
      ? policy.action.approver_chain
      : ['head_of_department', 'accounting_manager'];

    const existingRoleRes = await query(
      `SELECT DISTINCT r.name FROM roles r JOIN users u ON u.role_id=r.id WHERE u.is_active=TRUE`
    );
    const existingRoles = new Set<string>(existingRoleRes.rows.map((r: any) => r.name));
    const mgrRes = await query(
      `SELECT r.name AS mgr_role FROM users u LEFT JOIN users m ON u.reports_to_user_id=m.id LEFT JOIN roles r ON m.role_id=r.id WHERE u.id=$1`,
      [pr.requester_id]
    );
    const submitterManagerRole = mgrRes.rows[0]?.mgr_role || null;
    const submitterRoleRes = await query(
      `SELECT r.name AS s_role FROM users u JOIN roles r ON u.role_id=r.id WHERE u.id=$1`,
      [pr.requester_id]
    );
    const { chain } = resolveDynamicChain({
      chain: rawChain, existingRoles,
      submitterRole: submitterRoleRes.rows[0]?.s_role || 'staff',
      submitterManagerRole,
    });

    if (args.decision === 'reject') {
      const t = (args.comment || '').trim();
      if (t.length < 5) throw new Error('Rejection reason required, min 5 chars');
      await query('BEGIN');
      await query(
        `UPDATE purchase_requisitions
         SET status='rejected', updated_at=CURRENT_TIMESTAMP,
             rejection_reason=$2, rejection_actor_id=$3, rejected_at=CURRENT_TIMESTAMP
         WHERE id=$1`,
        [args.prId, t, args.actorId]
      );
      await query(
        `INSERT INTO pr_approval_logs (pr_id, actor_id, previous_status, new_status, comments, stage)
         VALUES ($1, $2, $3, 'rejected', $4, 'pr_review')`,
        [args.prId, args.actorId, pr.status, t]
      );
      await query('COMMIT');
      await publishEvent('pr.rejected', { prId: args.prId, reason: t }, {
        actorId: args.actorId, refType: 'pr', refId: Number(args.prId),
        severity: 'warning',
        message: `Purchase request #PR-${args.prId} rejected: ${t}`,
      });
      revalidatePath('/');
      revalidatePath('/');
      return { success: true, newStatus: 'rejected', rejectionReason: t };
    }

    const STAGE_INDEX: Record<string, number> = {
      supervisor_review: 0,
      head_review: 0,
      account_officer_review: 0,
      account_supervisor_review: 0,
      accounting_review: 1,
      cfo_review: 2,
      draft: 0,
    };
    const _idx = STAGE_INDEX[pr.status] ?? 0;
    let newStatus = 'approved';
    if (pr.status in STAGE_TO_ROLE) {
      const stageRole = STAGE_TO_ROLE[pr.status] as string | null;
      const prStageAccess = await evaluateStage(actor.rbac_role_id, pr.status);
      if (!prStageAccess.allow) {
        throw new Error(`Current stage "${pr.status}" requires role "${stageRole}", but actor is "${actor.role_name}"`);
      }
      const idxInChain = chain.indexOf(stageRole as string);
      const final =
        idxInChain < 0 ? chain.length === 0 : idxInChain + 1 >= chain.length;
      if (final) {
        newStatus = 'approved';
      } else {
        const nextIdx = idxInChain + 1;
        const nextRole = chain[nextIdx];
        newStatus = APPROVER_TO_STAGE[nextRole] || 'head_review';
      }
    } else {
      newStatus = APPROVER_TO_STAGE[chain[0]] || 'head_review';
    }
    const final = newStatus === 'approved';
    await query('BEGIN');
    await query(`UPDATE purchase_requisitions SET status=$1, updated_at=CURRENT_TIMESTAMP WHERE id=$2`, [newStatus, args.prId]);
    await query('COMMIT');
    await publishEvent('pr.advanced', { prId: args.prId, newStatus, final }, {
      actorId: args.actorId, refType: 'pr', refId: Number(args.prId),
      severity: newStatus === 'rejected' ? 'warning' : 'success',
      message: `Purchase request #PR-${args.prId} → ${newStatus}${final ? ' (completed)' : ''}`,
    });

    if (newStatus === 'approved') {
      try {
        await createPurchaseOrderFromPr({ prId: args.prId, actorId: args.actorId });
      } catch (e) {
        console.error('PO auto-create failed (non-fatal):', (e as any)?.message);
      }
    }

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, newStatus, final };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('advancePurchaseRequisition failed:', error);
    return { success: false, error: error.message };
  }
}

export async function createPurchaseOrderFromPr(args: {
  prId: number;
  actorId: number;
}) {
  try {
    await requireActionFor(args.actorId, 'approve_pr', { rbacSection: 'core-operations', rbacAction: 'create' });

    const prRes = await query(
      `SELECT pr.*, d.name AS dept_name, dg.id AS dept_group_id, dg.name AS dept_group_name
         FROM purchase_requisitions pr
         LEFT JOIN departments d ON pr.department_id = d.id
         LEFT JOIN rbac.groups dg ON dg.kind = 'department' AND dg.name = d.name
        WHERE pr.id = $1`,
      [args.prId]
    );
    if (prRes.rows.length === 0) throw new Error('PR not found');
    const pr = prRes.rows[0];

    const existing = await query(
      `SELECT id FROM purchase_orders WHERE pr_id = $1 LIMIT 1`,
      [args.prId]
    );
    if (existing.rows.length > 0) {
      return { success: true, poId: existing.rows[0].id, alreadyExists: true };
    }

    const itemsRes = await query(
      `SELECT description, qty, unit_price, mapped_account_code FROM pr_items WHERE pr_id = $1 ORDER BY id`,
      [args.prId]
    );

    const policy = await resolvePolicyForContext({
      targetType: 'po',
      totalAmount: Number(pr.total_estimate) || 0,
      department: pr.dept_name,
      submitterRole: 'staff',
      isRecurring: !!pr.is_recurring,
    });

    const chain = policy?.action?.approver_chain?.length
      ? policy.action.approver_chain
      : ['accounting_manager'];

    await query('BEGIN');
    const year = new Date().getFullYear();
    const poRes = await query(
      `INSERT INTO purchase_orders
       (pr_id, po_number, vendor_name, total_amount, currency, status, matched_policy_id, issued_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      [
        args.prId,
        `PO-${year}-DRAFT-${args.prId}-${Date.now().toString().slice(-4)}`,
        pr.vendor_name,
        Number(pr.total_estimate) || 0,
        pr.currency || 'THB',
        chain[0] === 'cfo' ? 'po_cfo' : 'pending_approval',
        policy?.id || pr.matched_policy_id || null,
        args.actorId,
      ]
    );
    const poId = poRes.rows[0].id;

    for (const it of itemsRes.rows) {
      await query(
        `INSERT INTO po_items (po_id, description, qty, unit_price, mapped_account_code)
         VALUES ($1,$2,$3,$4,$5)`,
        [poId, it.description, it.qty, it.unit_price, it.mapped_account_code]
      );
    }
    await query(
      `INSERT INTO po_approval_logs (po_id, actor_id, previous_status, new_status, comments, stage, chain_index)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [poId, args.actorId, 'draft', 'pending_approval', 'Auto-created from PR', 'po_pending', 0]
    );
    await query('COMMIT');

    await publishEvent('po.created', { poId, prId: args.prId, chain }, {
      actorId: args.actorId, refType: 'po', refId: Number(poId),
      severity: 'info',
      message: `Auto-created PO #${poId} from PR-${args.prId}`,
    });

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, poId };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('createPurchaseOrderFromPr failed:', error);
    return { success: false, error: error.message };
  }
}

export async function advancePurchaseOrder(args: {
  poId: number;
  actorId: number;
  decision: 'approve' | 'reject';
  comment?: string;
}) {
  try {
    await requireActionFor(args.actorId, 'approve_po', { rbacSection: 'core-operations', rbacAction: 'update' });

    const poRes = await query(
      `SELECT po.*, pr.department_id, d.name AS dept_name,
              dg.id AS dept_group_id, dg.name AS dept_group_name, pr.is_recurring
       FROM purchase_orders po
       JOIN purchase_requisitions pr ON po.pr_id = pr.id
       LEFT JOIN departments d ON pr.department_id = d.id
       LEFT JOIN rbac.groups dg ON dg.kind = 'department' AND dg.name = d.name
       WHERE po.id = $1`,
      [args.poId]
    );
    if (poRes.rows.length === 0) throw new Error('PO not found');
    const po = poRes.rows[0];

    const actorRes = await query(
      `SELECT u.id, u.department, u.department_id, u.dept_group_id, dg.name AS dept_group_name,
              r.name AS role_name, u.rbac_role_id
       FROM users u
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
       WHERE u.id = $1`,
      [args.actorId]
    );
    const actor = actorRes.rows[0];

    const policy = await resolvePolicyForContext({
      targetType: 'po',
      totalAmount: Number(po.total_amount) || 0,
      department: po.dept_name,
      submitterRole: 'staff',
      isRecurring: !!po.is_recurring,
    });
    const chain = policy?.action?.approver_chain?.length
      ? policy.action.approver_chain
      : ['accounting_manager'];

    if (args.decision === 'reject') {
      const t = (args.comment || '').trim();
      if (t.length < 5) throw new Error('Rejection reason required, min 5 chars');
      await query('BEGIN');
      await query(
        `UPDATE purchase_orders
         SET status='rejected', updated_at=CURRENT_TIMESTAMP,
             rejection_reason=$2, rejection_actor_id=$3, rejected_at=CURRENT_TIMESTAMP
         WHERE id=$1`,
        [args.poId, t, args.actorId]
      );
      await query(
        `INSERT INTO po_approval_logs (po_id, actor_id, previous_status, new_status, comments, stage)
         VALUES ($1, $2, $3, 'rejected', $4, 'po_reject')`,
        [args.poId, args.actorId, po.status, t]
      );
      await query('COMMIT');
      await publishEvent('po.rejected', { poId: args.poId, reason: t }, {
        actorId: args.actorId, refType: 'po', refId: Number(args.poId),
        severity: 'warning',
        message: `PO #${args.poId} rejected: ${t}`,
      });
      revalidatePath('/');
      revalidatePath('/');
      return { success: true, newStatus: 'rejected', rejectionReason: t };
    }

    const PO_STAGE_INDEX: Record<string, number> = {
      pending_approval: 0,
      po_pending: 0,
      po_cfo: 1,
      approved: chain.length,
    };
    const PO_STAGE_MODULE: Record<string, string | null> = {
      po_pending: 'stage-po-pending',
      po_cfo:     'stage-po-cfo',
    };
    if (po.status in PO_STAGE_MODULE) {
      const stageAccess = await evaluateStage(actor.rbac_role_id, po.status);
      if (!stageAccess.allow) {
        throw new Error(`Current PO stage "${po.status}" is not allowed for role "${actor.role_name}"`);
      }
    }
    const idx = PO_STAGE_INDEX[po.status] ?? 0;
    const nextIdx = idx + 1;
    const final = nextIdx >= chain.length;
    let newStatus: string;
    if (final) newStatus = 'approved';
    else {
      const r = chain[nextIdx];
      newStatus = r === 'cfo' ? 'po_cfo' : 'pending_approval';
    }

    await query('BEGIN');
    await query(
      `UPDATE purchase_orders SET status=$1, updated_at=CURRENT_TIMESTAMP WHERE id=$2`,
      [newStatus, args.poId]
    );
    await query(
      `INSERT INTO po_approval_logs (po_id, actor_id, previous_status, new_status, comments, stage, chain_index)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [args.poId, args.actorId, po.status, newStatus,
       args.comment || `Approved by ${actor.role_name}`, newStatus, nextIdx]
    );
    await query('COMMIT');

    await publishEvent('po.advanced', { poId: args.poId, newStatus, final }, {
      actorId: args.actorId, refType: 'po', refId: Number(args.poId),
      severity: 'success',
      message: `PO #${args.poId} → ${newStatus}${final ? ' (awaiting payslip)' : ''}`,
    });

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, newStatus, final };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('advancePurchaseOrder failed:', error);
    return { success: false, error: error.message };
  }
}

export async function attachDisbursementPayslip(args: {
  poId: number;
  actorId: number;
  slipId: number;
}) {
  try {
    await requireActionFor(args.actorId, 'attach_po_payslip', { rbacSection: 'core-operations', rbacAction: 'update' });

    const poRes = await query(`SELECT * FROM purchase_orders WHERE id = $1`, [args.poId]);
    if (poRes.rows.length === 0) throw new Error('PO not found');
    const po = poRes.rows[0];
    if (po.status !== 'approved') {
      throw new Error(`PO must be in 'approved' status before attaching payslip (current: ${po.status})`);
    }

    const slipRes = await query(`SELECT id, file_path, mime_type FROM slips WHERE id = $1`, [args.slipId]);
    if (slipRes.rows.length === 0) throw new Error('Slip not found');

    await query('BEGIN');
    await query(
      `UPDATE slips SET po_id = $1 WHERE id = $2 AND po_id IS NULL`,
      [args.poId, args.slipId]
    );
    await query(
      `UPDATE purchase_orders
       SET status='settled', settled_at=CURRENT_TIMESTAMP,
           settled_by=$2, settled_slip_id=$3, updated_at=CURRENT_TIMESTAMP
       WHERE id=$1`,
      [args.poId, args.actorId, args.slipId]
    );
    await query(
      `INSERT INTO po_approval_logs (po_id, actor_id, previous_status, new_status, comments, stage)
       VALUES ($1, $2, 'approved', 'settled', $3, 'po_settled')`,
      [args.poId, args.actorId, `Payslip slipId=${args.slipId} attached`]
    );
    await query('COMMIT');

    await publishEvent('po.settled', { poId: args.poId, slipId: args.slipId }, {
      actorId: args.actorId, refType: 'po', refId: Number(args.poId),
      severity: 'success',
      message: `PO #${args.poId} closed successfully (transfer slip attached)`,
    });

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, newStatus: 'settled', slipId: args.slipId };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('attachDisbursementPayslip failed:', error);
    return { success: false, error: error.message };
  }
}