'use server';

import { revalidatePath } from 'next/cache';
import { query } from '@/lib/db';
import { requireActionFor } from '@/lib/server/requireActionFor';
import { publish as publishEvent } from '@/lib/events';
import { postExpenseToGL } from '@/lib/finance/postExpenseToGL';

export async function disbursePayment(args: {
  expenseId: number;
  actorId: number;
  comment?: string;
}) {
  try {
    await requireActionFor(args.actorId, 'settle_payment', {
      rbacSection: 'core-operations',
      rbacAction: 'update',
      stage: 'finance_review',
    });

    const curRes = await query(
      `SELECT id, status, total_amount, vat_amount, vendor_name, submitter_id
       FROM expenses WHERE id = $1`,
      [args.expenseId],
    );
    if (curRes.rows.length === 0) throw new Error('Expense not found');
    const exp = curRes.rows[0];
    if (exp.status !== 'finance_review' && exp.status !== 'approved') {
      throw new Error(`Cannot disburse from status "${exp.status}" — must be finance_review`);
    }
    const previousStatus = exp.status;

    await query('BEGIN');

    await query(
      `UPDATE expenses SET status = 'paid', updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
      [args.expenseId],
    );

    await query(
      `INSERT INTO approval_transitions (target_type, target_id, actor_id, previous_status, new_status, comments, stage, chain_index)
       VALUES ('expense', $1, $2, $3, 'paid', $4, 'finance_review', 7)`,
      [args.expenseId, args.actorId, previousStatus, args.comment || 'Disbursed by Finance'],
    );

    const { journalId } = await postExpenseToGL({
      expenseId: args.expenseId,
      vendorName: exp.vendor_name,
      totalAmount: exp.total_amount,
      vatAmount: exp.vat_amount,
    });

    await query('COMMIT');

    const actorRes = await query(
      `SELECT fullname FROM users WHERE id = $1`,
      [args.actorId],
    );
    const actorName = actorRes.rows[0]?.fullname || 'Finance';

    const totalVal = parseFloat(String(exp.total_amount));
    await publishEvent(
      'expense.paid',
      {
        expenseId: args.expenseId,
        submitterId: exp.submitter_id,
        vendorName: exp.vendor_name,
        totalAmount: totalVal,
        currency: 'THB',
        financeActorName: actorName,
      },
      {
        actorId: args.actorId,
        refType: 'expense',
        refId: Number(args.expenseId),
        severity: 'success',
        message: `Payment released for EXP-${args.expenseId} (${exp.vendor_name}) · ${totalVal.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB`,
      },
    );

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, newStatus: 'paid', journalId };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('disbursePayment failed:', error);
    return { success: false, error: error.message };
  }
}

export async function rejectDisbursement(args: {
  expenseId: number;
  actorId: number;
  comment: string;
}) {
  try {
    const t = (args.comment || '').trim();
    if (t.length < 5) throw new Error('Rejection reason required, min 5 chars');

    await requireActionFor(args.actorId, 'settle_payment', {
      rbacSection: 'core-operations',
      rbacAction: 'update',
      stage: 'finance_review',
    });

    const curRes = await query(`SELECT status FROM expenses WHERE id = $1`, [args.expenseId]);
    if (curRes.rows.length === 0) throw new Error('Expense not found');
    const previousStatus = curRes.rows[0].status;
    if (previousStatus !== 'finance_review') {
      throw new Error(`Cannot reject from status "${previousStatus}" — must be finance_review`);
    }

    await query('BEGIN');
    await query(
      `UPDATE expenses
       SET status = 'rejected', updated_at = CURRENT_TIMESTAMP,
           rejection_reason = $2, rejection_actor_id = $3, rejected_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [args.expenseId, t, args.actorId],
    );
    await query(
      `INSERT INTO approval_transitions (target_type, target_id, actor_id, previous_status, new_status, comments, stage)
       VALUES ('expense', $1, $2, $3, 'rejected', $4, 'finance_review')`,
      [args.expenseId, args.actorId, previousStatus, t],
    );
    await query('COMMIT');

    await publishEvent(
      'expense.rejected',
      { expenseId: args.expenseId, reason: t, rejectedAt: 'finance_review' },
      {
        actorId: args.actorId,
        refType: 'expense',
        refId: Number(args.expenseId),
        severity: 'warning',
        message: `Disbursement rejected for EXP-${args.expenseId}: ${t}`,
      },
    );

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, newStatus: 'rejected', rejectionReason: t };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('rejectDisbursement failed:', error);
    return { success: false, error: error.message };
  }
}
