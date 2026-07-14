'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { cookies } from 'next/headers';
import { z } from 'zod';
import { query, withTransaction, query as _query } from '@erp-lib/db';
import { recordEvent } from '@erp-lib/waybill/events';
import { recordAttachment, getAttachment } from '@erp-lib/waybill/attachments';
import {
  loadWaybill,
  domainOf,
  loadApproversByStage,
} from '@/lib/server/waybill';
import { allowedKindsFor, type WaybillAttachmentKind } from '@erp-lib/waybill/kinds';
import { addWatcher, removeWatcher } from '@erp-lib/waybill/watchers';
import { reCallWaybillAction } from '@erp-lib/waybill/recall';
import { resolveNextStage } from '@erp-lib/perm/server';
import { matchPerm } from '@erp-lib/perm';
import { requireActionFor } from '@/lib/server/requireActionFor';
import { loadActor, type ActorWithScope } from '@/lib/server/guard';
import { hasPermission, PERM, STAGE_TO_ROLE } from '@erp-lib/perm/server';
import type { StageName, ActorCtx, ResolverCtx } from '@erp-lib/perm/server';
import { resolveApprovalChain, canActOnStage, getApprovedStages } from '@erp-lib/perm/server';
import { postExpenseToGL } from '@erp-lib/finance/postExpenseToGL';
import {
  finalizeDraftJournal,
  setExpenseJournalEntry,
  upsertDraftJournal,
} from '@erp-lib/finance/postExpenseToGL';
import {
  upsertProcurementDraftAccrual,
  finalizeProcurementDraft,
} from '@erp-lib/finance/postProcurementToGL';
import { finalizeSalesDraft } from '@erp-lib/finance/postSalesToGL';
import { recordTransition } from '@erp-lib/approval/recordTransition';
import { appendWaybillEvent } from '@erp-lib/waybill/append';
import { recordOverride } from '@erp-lib/approval/recordOverride';
import {
  ensureGlForExpense,
  ensurePoForExpense as ensurePoForExpenseWithClient,
} from '@erp-lib/waybill/ensureArtifacts';
import { ensurePoPdf } from '@erp-lib/finance/poPdf';
import { remove as removeFromStorage } from '@erp-lib/slips/storage';
import { pipsForDomain } from '@erp-lib/waybill/derive';
import { aiInvoke } from '@/lib/ai/router';
import { publish as publishEvent } from '@/lib/events';

void recordEvent;

async function requireActorOrNull(): Promise<ActorWithScope | null> {
  return loadActor();
}

// ----- helpers (B: WbForCheck + perm checks) -----
interface WbForCheck {
  id: string;
  current_stage: string;
  origin: 'expense' | 'pr' | 'po' | 'so';
  submitter_id: number | null;
  status: string;
}

async function actorForWaybill(): Promise<ActorWithScope> {
  const actor = await loadActor();
  if (!actor) throw new Error('unauthorized');
  return actor;
}

function canActOnWaybillStage(actor: ActorWithScope, wb: WbForCheck): boolean {
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  const stage = wb.current_stage;
  if (matchPerm(actor.permissions, `stage:${stage}:act::allow`)) return true;
  if (matchPerm(actor.permissions, `stage:${stage}:act:all::allow`)) return true;
  if (actor.role_name === 'cfo' || actor.role_name === 'ceo' || actor.role_name === 'admin') {
    return true;
  }
  if (wb.origin === 'expense' || wb.origin === 'so') return false;
  if (actor.id === wb.submitter_id && stage === 'submission' && matchPerm(actor.permissions, 'finance:expense:create::allow')) {
    return true;
  }
  return false;
}

function canRecall(actor: ActorWithScope, wb: WbForCheck): boolean {
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  return ['cfo', 'ceo', 'finance', 'admin'].includes(actor.role_name) && !['disbursed', 'gl_confirmed', 'rejected'].includes(wb.current_stage);
}

function canRejectWaybill(actor: ActorWithScope, wb: WbForCheck): boolean {
  if (['disbursed', 'gl_confirmed', 'rejected'].includes(wb.current_stage)) return false;
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  return ['cfo', 'ceo', 'admin', 'finance', 'account_officer', 'account_supervisor', 'accounting_manager'].includes(actor.role_name);
}

function canFinalApproveExpense(actor: ActorWithScope, wb: WbForCheck): boolean {
  if (!['accounting_authorization', 'final_authorization'].includes(wb.current_stage)) return false;
  if (matchPerm(actor.permissions, 'finance:expense:approve::allow')) return true;
  if (matchPerm(actor.permissions, 'finance:expense:settle::allow')) {
    return ['finance', 'account_officer', 'account_supervisor', 'accounting_manager'].includes(actor.role_name);
  }
  return false;
}

function canResubmit(actor: ActorWithScope, wb: WbForCheck): boolean {
  return actor.id === wb.submitter_id
    && wb.current_stage === 'rejected'
    && matchPerm(actor.permissions, 'finance:expense:create::allow');
}

function canSettleExpense(actor: ActorWithScope, wb: WbForCheck): boolean {
  return wb.current_stage === 'awaiting_disbursement'
    && matchPerm(actor.permissions, 'finance:expense:settle::allow');
}

function canConfirmGl(actor: ActorWithScope, wb: WbForCheck): boolean {
  return wb.current_stage === 'disbursed'
    && matchPerm(actor.permissions, 'finance:gl:confirm::allow');
}

function canAttachAtStage(actor: ActorWithScope, wb: WbForCheck): boolean {
  if (['disbursed', 'gl_confirmed', 'rejected'].includes(wb.current_stage)) return false;
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  if (matchPerm(actor.permissions, 'finance:waybill:attach::allow')) return true;
  return actor.id === wb.submitter_id
    && wb.current_stage === 'submission'
    && matchPerm(actor.permissions, 'finance:expense:create::allow');
}

function canRemoveAttachment(actor: ActorWithScope): boolean {
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  return actor.role_name === 'cfo' || actor.role_name === 'ceo' || actor.role_name === 'admin';
}

function canSaveProcurementAccrual(actor: ActorWithScope): boolean {
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  if (matchPerm(actor.permissions, 'finance:pr:edit::allow')) return true;
  return ['finance', 'account_officer', 'account_supervisor', 'accounting_manager'].includes(actor.role_name);
}

function canPostGlAccrual(actor: ActorWithScope, wb: WbForCheck): boolean {
  return wb.current_stage === 'accounting_authorization'
    && (matchPerm(actor.permissions, 'finance:gl:post::allow')
      || (actor.role_name === 'accounting_manager'
        && matchPerm(actor.permissions, 'finance:gl:post::allow')));
}

function canPostGlSettlement(actor: ActorWithScope, wb: WbForCheck): boolean {
  return wb.current_stage === 'disbursed'
    && matchPerm(actor.permissions, 'finance:gl:post::allow')
    && ['finance', 'account_officer', 'account_supervisor', 'accounting_manager'].includes(actor.role_name);
}

function canPostSalesGlStep(actor: ActorWithScope, wb: WbForCheck, stage: string): boolean {
  if (wb.current_stage !== stage) return false;
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  if (matchPerm(actor.permissions, 'finance:gl:post::allow')) {
    return ['finance', 'account_officer', 'account_supervisor', 'accounting_manager'].includes(actor.role_name);
  }
  return false;
}

function canConfirmSalesGl(actor: ActorWithScope, wb: WbForCheck): boolean {
  if (wb.origin !== 'so') return false;
  if (matchPerm(actor.permissions, 'admin:system:bypass::allow')) return true;
  if (matchPerm(actor.permissions, 'finance:gl:confirm::allow')) {
    return ['finance', 'account_officer', 'account_supervisor', 'accounting_manager', 'cfo', 'ceo'].includes(actor.role_name);
  }
  return false;
}


// ----- helpers (A: actor/submitter context) -----
async function fetchActorCtx(userId: number): Promise<ActorCtx> {
  const r = await query<{
    role_id: string | null;
    dept_id: string | null;
    level: number;
  }>(
    `SELECT (SELECT up.permission_id FROM perm.user_permissions up
              WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                AND up.revoked_at IS NULL
                AND (up.ends_at IS NULL OR up.ends_at > now())
              ORDER BY up.permission_id LIMIT 1) AS dept_id,
            (SELECT ur.role_id FROM perm.user_roles ur
              WHERE ur.user_id = u.id
              ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
              LIMIT 1) AS role_id,
            COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int)
                       FROM perm.user_roles ur WHERE ur.user_id = u.id), 5)::int AS level
       FROM users u
      WHERE u.id = $1`,
    [userId],
  );
  const row = r.rows[0];
  const deptId = row?.dept_id
    ? row.dept_id.replace(/^user:dept:/, '').replace(/::allow$/, '')
    : null;
  return {
    userId,
    roleId: row?.role_id ?? '',
    deptId,
    deptGroupId: deptId,
    level: row?.level ?? 5,
  };
}

async function fetchSubmitterCtx(expenseId: number): Promise<ResolverCtx> {
  const r = await query<{
    submitter_id: number;
    dept_id: string | null;
    role_id: string | null;
    level: number;
  }>(
    `SELECT e.submitter_id,
            (SELECT up.permission_id FROM perm.user_permissions up
              WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                AND up.revoked_at IS NULL
                AND (up.ends_at IS NULL OR up.ends_at > now())
              ORDER BY up.permission_id LIMIT 1) AS dept_id,
            (SELECT ur.role_id FROM perm.user_roles ur
              WHERE ur.user_id = u.id
              ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
              LIMIT 1) AS role_id,
            COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int)
                       FROM perm.user_roles ur WHERE ur.user_id = u.id), 5)::int AS level
FROM expenses e
       JOIN users u ON u.id = e.submitter_id
       WHERE e.id = $1`,
    [expenseId],
  );
  const row = r.rows[0];
  const deptId = row?.dept_id
    ? row.dept_id.replace(/^user:dept:/, '').replace(/::allow$/, '')
    : null;
  return {
    submitterUserId: row?.submitter_id ?? 0,
    submitterDeptId: deptId,
    submitterRoleId: row?.role_id ?? '',
    submitterLevel: row?.level ?? 5,
    alreadyApproved: new Set<StageName>(),
  };
}

async function fetchPrSubmitterCtx(prId: number): Promise<ResolverCtx> {
  const r = await query<{
    requester_id: number;
    dept_id: string | null;
    role_id: string | null;
    level: number;
  }>(
    `SELECT pr.requester_id,
            (SELECT up.permission_id FROM perm.user_permissions up
              WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                AND up.revoked_at IS NULL
                AND (up.ends_at IS NULL OR up.ends_at > now())
              ORDER BY up.permission_id LIMIT 1) AS dept_id,
            (SELECT ur.role_id FROM perm.user_roles ur
              WHERE ur.user_id = u.id
              ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
              LIMIT 1) AS role_id,
            COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int)
                       FROM perm.user_roles ur WHERE ur.user_id = u.id), 5)::int AS level
       FROM purchase_requisitions pr
       JOIN users u ON u.id = pr.requester_id
      WHERE pr.id = $1`,
    [prId],
  );
  const row = r.rows[0];
  const deptId = row?.dept_id
    ? row.dept_id.replace(/^user:dept:/, '').replace(/::allow$/, '')
    : null;
  return {
    submitterUserId: row?.requester_id ?? 0,
    submitterDeptId: deptId,
    submitterRoleId: row?.role_id ?? '',
    submitterLevel: row?.level ?? 5,
    alreadyApproved: new Set<StageName>(),
  };
}

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

// ----- exports (A: object-arg actions) -----
export async function getSemanticSuggestions(description: string) {
  // Anyone authenticated with read access to expenses may search COA.
  const actor = await requireActorOrNull();
  if (!actor) return { success: false, error: 'unauthorized' } as const;
  if (!hasPermission(actor, PERM.tile.search_coa.view)) {
    return { success: false, error: 'forbidden' } as const;
  }

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
    await requireActionFor(actorId, 'review_expense', { perm: PERM.finance.expense.review });
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

    await recordTransition({
      entityType: 'expense',
      entityId: expenseId,
      actorId,
      previousStatus: 'submission',
      newStatus: 'accountant_reviewed',
      comments: 'Accountant corrected values and confirmed accounts',
    });

    await query('COMMIT');
    revalidatePath('/');
    revalidatePath('/');
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
      await requireActionFor(actorId, 'approve_expense', { perm: 'finance:expense:approve:all' });
    } else if (newStatus === 'paid') {
      await requireActionFor(actorId, 'settle_payment', { perm: PERM.finance.expense.settle });
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
        perm: 'finance:expense:approve:all',
        stage: previousStatus,
        entityCtx: { entityType: 'expense', entityId: expenseId },
      });
      if (stageRes.override) {
        await recordTransition({
          entityType: 'expense',
          entityId: expenseId,
          actorId,
          previousStatus,
          newStatus,
          comments: `[stage_override] ${comments || ''}`.trim(),
          stage: previousStatus,
        });
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

    await recordTransition({
      entityType: 'expense',
      entityId: expenseId,
      actorId,
      previousStatus,
      newStatus,
      comments: comments || `Status changed to ${newStatus}`,
    });

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
    revalidatePath('/');
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
  draftWaybillId?: string;
  overrides?: {
    vendorName?: string;
    vendorAddress?: string;
    createdTo?: string;
    createdToAddress?: string;
    transactionDate?: string;
    paymentMethod?: string;
    bookBankSlipId?: number;
    bookBankFields?: {
      bankName?: string;
      bankBranch?: string;
      accountNumber?: string;
      accountName?: string;
    };
    items?: Array<{ qty?: number; unitPrice?: number; amount?: number; description: string }>;
  };
}) {
  try {
    await requireActionFor(args.actorId, 'submit_expense', { perm: PERM.finance.expense.create });

    const slipRes = await query(`SELECT * FROM slips WHERE id = $1`, [args.slipId]);
    if (slipRes.rows.length === 0) throw new Error('Slip not found');
    const slip = slipRes.rows[0];
    if (slip.kind === 'book_bank') {
      throw new Error('Book bank slips are confirmed together with a receipt slip');
    }
    const parsed = slip.ocr_raw_json || {};

    let draftContext: { waybillId: string; expenseId: number } | null = null;
    if (args.draftWaybillId) {
      const wbRes = await query<{ id: string; submitter_id: number; origin_id: number; current_stage: string }>(
        `SELECT id, submitter_id, origin_id, current_stage
           FROM waybills WHERE id = $1`,
        [args.draftWaybillId],
      );
      const wb = wbRes.rows[0];
      if (!wb) throw new Error('Draft waybill not found');
      if (wb.submitter_id !== args.actorId) throw new Error('Not your draft');
      if (wb.current_stage !== 'draft') throw new Error('Draft already finalized');
      draftContext = { waybillId: wb.id, expenseId: wb.origin_id };
    }

    const bookBankSlipId = args.overrides?.bookBankSlipId;
    const bookBankFields = args.overrides?.bookBankFields;
    let bookBankSlip: any = null;
    if (bookBankSlipId) {
      if (!bookBankFields || !bookBankFields.bankName || !bookBankFields.accountNumber || !bookBankFields.accountName) {
        throw new Error('Transfer expenses require bank name, account number, and account name');
      }
      if (String(args.overrides?.paymentMethod ?? parsed.paymentMethod ?? 'cash') !== 'transfer') {
        throw new Error('Book bank slip is only valid with payment_method=transfer');
      }
      const bbRes = await query(`SELECT * FROM slips WHERE id = $1`, [bookBankSlipId]);
      if (bbRes.rows.length === 0) throw new Error('Book bank slip not found');
      bookBankSlip = bbRes.rows[0];
      if (bookBankSlip.kind !== 'book_bank') {
        throw new Error('Slip is not a book bank slip');
      }
      if (bookBankSlip.uploaded_by !== args.actorId) {
        throw new Error('Only the uploader can attach a book bank slip');
      }
      if (bookBankSlip.status !== 'pending' || bookBankSlip.expense_id != null) {
        throw new Error('Book bank slip is already attached to another expense');
      }
    }

    const vendor = args.overrides?.vendorName || parsed.vendorName || 'Unknown Vendor';
    const vendorAddress = args.overrides?.vendorAddress || parsed.vendorAddress || '';
    const createdTo = args.overrides?.createdTo || parsed.createdTo || '';
    const createdToAddress = args.overrides?.createdToAddress || parsed.createdToAddress || '';
    const txnDate = args.overrides?.transactionDate || parsed.transactionDate || new Date().toISOString().split('T')[0];
    const subtotal = Number(parsed.subtotal ?? 0);
    const vatAmount = Number(parsed.vatAmount ?? 0);
    const totalAmount = Number(parsed.totalAmount ?? subtotal + vatAmount);
    const paymentMethod = args.overrides?.paymentMethod || parsed.paymentMethod || 'cash';
    const isCorrupted = !!parsed.isCorrupted;
    const correctionNotes = parsed.correctionNotes || '';
    const preExistingExpenseId = draftContext ? null : (slip.expense_id ?? null);

    await query('BEGIN');

    let expenseId: number;
    let previousStatus: string | null = null;
    if (draftContext) {
      expenseId = draftContext.expenseId;
      previousStatus = 'draft';
      await query(
        `UPDATE expenses
            SET vendor_name = $1, transaction_date = $2, subtotal = $3, vat_amount = $4, total_amount = $5,
                payment_method = $6, is_corrupted = $7, correction_notes = $8, ocr_raw_json = $9,
                document_url = $10, status = 'submission', created_to = $12, vendor_address = $13, created_to_address = $14, updated_at = CURRENT_TIMESTAMP
          WHERE id = $11`,
        [
          vendor, txnDate, subtotal, vatAmount, totalAmount, paymentMethod,
          isCorrupted, correctionNotes, JSON.stringify(parsed),
          `/api/slips/file?key=${encodeURIComponent(slip.file_path)}`,
          expenseId,
          createdTo || null,
          vendorAddress || null,
          createdToAddress || null,
        ],
      );
      await query(`DELETE FROM expense_items WHERE expense_id = $1`, [expenseId]);
      await query(
        `UPDATE slips
            SET expense_id = $1, status = 'confirmed', confirmed_at = CURRENT_TIMESTAMP
          WHERE id = $2`,
        [expenseId, args.slipId],
      );
      await query(
        `UPDATE waybills
            SET vendor_name = $1, total_amount = $2, current_stage = 'submission',
                created_to = $4, vendor_address = $5, created_to_address = $6, currency = 'THB', updated_at = now()
          WHERE id = $3`,
        [vendor, totalAmount, draftContext.waybillId, createdTo || null, vendorAddress || null, createdToAddress || null],
      );
    } else if (preExistingExpenseId) {
      expenseId = preExistingExpenseId;
      const cur = await query(`SELECT status FROM expenses WHERE id = $1`, [expenseId]);
      previousStatus = cur.rows[0]?.status ?? null;
      await query(
        `UPDATE expenses
            SET vendor_name = $1, transaction_date = $2, subtotal = $3, vat_amount = $4, total_amount = $5,
                payment_method = $6, is_corrupted = $7, correction_notes = $8, ocr_raw_json = $9,
                document_url = $10, created_to = $12, vendor_address = $13, created_to_address = $14, updated_at = CURRENT_TIMESTAMP
          WHERE id = $11`,
        [
          vendor, txnDate, subtotal, vatAmount, totalAmount, paymentMethod,
          isCorrupted, correctionNotes, JSON.stringify(parsed),
          `/api/slips/file?key=${encodeURIComponent(slip.file_path)}`,
          expenseId,
          createdTo || null,
          vendorAddress || null,
          createdToAddress || null,
        ],
      );
      await query(`DELETE FROM expense_items WHERE expense_id = $1`, [expenseId]);
    } else {
      const headerRes = await query(
        `INSERT INTO expenses (
           submitter_id, vendor_name, transaction_date, subtotal, vat_amount, total_amount,
           payment_method, status, is_corrupted, correction_notes, ocr_raw_json, document_url, created_to, vendor_address, created_to_address
         )
         VALUES ($1,$2,$3,$4,$5,$6,$7,'submission',$8,$9,$10,$11,$12,$13,$14)
         RETURNING id`,
        [
          args.actorId, vendor, txnDate, subtotal, vatAmount, totalAmount, paymentMethod,
          isCorrupted, correctionNotes, JSON.stringify(parsed),
          `/api/slips/file?key=${encodeURIComponent(slip.file_path)}`,
          createdTo || null,
          vendorAddress || null,
          createdToAddress || null,
        ]
      );
      expenseId = headerRes.rows[0].id;

      await query(
        `UPDATE slips
            SET expense_id = $1, status = 'confirmed', confirmed_at = CURRENT_TIMESTAMP
          WHERE id = $2`,
        [expenseId, args.slipId],
      );
    }

    if (bookBankSlip) {
      const accountNumber = bookBankFields!.accountNumber!.replace(/[^\d]/g, '');
      const bankBranch = bookBankFields!.bankBranch?.trim() || null;
      await query(
        `UPDATE slips
            SET expense_id      = $1,
                status          = 'confirmed',
                confirmed_at    = CURRENT_TIMESTAMP,
                bank_name       = $2,
                bank_branch     = $3,
                account_number  = $4,
                account_name    = $5
          WHERE id = $6`,
        [
          expenseId,
          bookBankFields!.bankName,
          bankBranch,
          accountNumber,
          bookBankFields!.accountName,
          bookBankSlip.id,
        ],
      );
    }

    const items = args.overrides?.items ?? (Array.isArray(parsed.items) ? parsed.items : []);
    for (const item of items) {
      let bestCode: string | null = null;
      let score = 0;
      try {
        const match = await semanticCoaMatch(item.description);
        if (match.code) { bestCode = match.code; score = match.score; }
      } catch {}
      const qty = Number(item.qty ?? 1.00);
      const unitPrice = Number(item.unitPrice ?? item.amount ?? 0.00);
      await query(
        `INSERT INTO expense_items (expense_id, description, qty, unit_price, amount, mapped_account_code, confidence_score)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [expenseId, item.description, qty, unitPrice, Number(item.amount) || 0, bestCode, score]
      );
    }

    const submitterRes = await query(
      `SELECT (SELECT up.permission_id FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS dept_perm,
              (SELECT ur.role_id FROM perm.user_roles ur
                WHERE ur.user_id = u.id
                ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
                LIMIT 1) AS role_id,
              COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int)
                          FROM perm.user_roles ur WHERE ur.user_id = u.id), 5)::int AS level
       FROM users u
       WHERE u.id = $1`,
      [args.actorId]
    );
    const submitter = submitterRes.rows[0];

    let initialStatus: string;
    if (preExistingExpenseId) {
      initialStatus = previousStatus || 'submission';
    } else {
      initialStatus = 'submission';
    }
    const chainIndex = 0;

    if (!preExistingExpenseId) {
      const submitterCtx: ResolverCtx = {
        submitterUserId: args.actorId,
        submitterDeptId: submitter?.dept_group_id ?? null,
        submitterRoleId: submitter?.role_id ?? '',
        submitterLevel: submitter?.level ?? 5,
        alreadyApproved: new Set<StageName>(),
      };
      const resolution = await resolveApprovalChain(submitterCtx, totalAmount);
      if (resolution.nextStage) initialStatus = resolution.nextStage;
    }

    if (!preExistingExpenseId || initialStatus !== previousStatus) {
      await query(`UPDATE expenses SET status = $1 WHERE id = $2`, [initialStatus, expenseId]);
      await recordTransition({
        entityType: 'expense',
        entityId: expenseId,
        actorId: args.actorId,
        previousStatus,
        newStatus: initialStatus,
        comments: 'Submitted → initial stage',
        stage: initialStatus,
        chainIndex,
      });
    }

    await query('COMMIT');
    const waybillId = await appendWaybillEvent({
      origin: 'expense',
      originId: expenseId,
      kind: 'submitted',
      stageFrom: draftContext ? 'draft' : null,
      stageTo: initialStatus,
      actorId: args.actorId,
      payload: { vendor, totalAmount, vatAmount },
    });
    if (waybillId && bookBankSlip) {
      const caption = bookBankFields!.bankName
        ? `Book bank · ${bookBankFields!.bankName}${bookBankFields!.accountNumber ? ' · ' + bookBankFields!.accountNumber : ''}`
        : 'Book bank slip';
      await recordAttachment({
        waybillId,
        stageKey: 'submission',
        kind: 'slip',
        storageKey: bookBankSlip.file_path,
        filename: bookBankSlip.file_path.split('/').pop() || 'book-bank',
        contentType: bookBankSlip.mime_type || 'application/octet-stream',
        byteSize: bookBankSlip.file_size || 0,
        actorId: bookBankSlip.uploaded_by,
        actorRole: 'staff',
        caption,
      });
    }
    await publishEvent('expense.submitted', { expenseId, status: initialStatus }, {
      actorId: args.actorId, refType: 'expense', refId: Number(expenseId),
      severity: 'info',
      message: `Submitted expense #EXP-${expenseId} initial status ${initialStatus}`,
    });
    revalidatePath('/');
    return { success: true, expenseId, waybillId, status: initialStatus, policy: null, slipStatus: 'confirmed' };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('submitExpenseFromSlip failed:', error);
    return { success: false, error: error.message };
  }
}

export async function discardSlip(args: { slipId: number; actorId: number }) {
  try {
    const slipRes = await query(
      `SELECT id, uploaded_by, status, expense_id, pr_id, po_id, file_path
         FROM slips WHERE id = $1`,
      [args.slipId],
    );
    if (slipRes.rows.length === 0) {
      return { success: false, error: 'Slip not found' };
    }
    const slip = slipRes.rows[0];

    if (slip.uploaded_by !== args.actorId) {
      return { success: false, error: 'Only the uploader can remove this slip' };
    }

    let lockedExpenseId: number | null = null;
    if (slip.expense_id) {
      const lockedRes = await query(
        `SELECT 1
           FROM approval_transitions
          WHERE target_type = 'expense'
            AND target_id   = $1
            AND new_status IN ('approved', 'rejected')
          LIMIT 1`,
        [slip.expense_id],
      );
      if (lockedRes.rows.length > 0) {
        return {
          success: false,
          error: 'Slip is locked — the linked expense has already been approved or rejected.',
        };
      }
      lockedExpenseId = slip.expense_id;
    }

    await query('BEGIN');
    try {
      if (lockedExpenseId) {
        await query(`DELETE FROM expense_items WHERE expense_id = $1`, [lockedExpenseId]);
        await query(`DELETE FROM expenses WHERE id = $1`, [lockedExpenseId]);
      }

      await query(
        `UPDATE slips
            SET expense_id = NULL, pr_id = NULL, po_id = NULL,
                status = 'pending', discarded_at = CURRENT_TIMESTAMP,
                discarded_by = $2
          WHERE id = $1`,
        [args.slipId, args.actorId],
      );
      await query(`DELETE FROM slips WHERE id = $1`, [args.slipId]);
      await query('COMMIT');
    } catch (e) {
      await query('ROLLBACK');
      throw e;
    }

    try {
      await removeFromStorage(slip.file_path);
    } catch (e) {
      console.error('discardSlip: storage cleanup failed (file may already be missing):', e);
    }

    revalidatePath('/');
    revalidatePath('/');
    return { success: true, removedExpenseId: lockedExpenseId };
  } catch (error: any) {
    console.error('discardSlip failed:', error);
    return { success: false, error: error.message };
  }
}

export async function getSlipLockState(args: { slipId: number; actorId: number }): Promise<{
  exists: boolean;
  status: string | null;
  isUploader: boolean;
  approvedOrRejected: boolean;
  locked: boolean;
  reason: string | null;
}> {
  const empty = {
    exists: false,
    status: null,
    isUploader: false,
    approvedOrRejected: false,
    locked: false,
    reason: null,
  };
  const slipRes = await query(
    `SELECT id, uploaded_by, status, expense_id
       FROM slips WHERE id = $1`,
    [args.slipId],
  );
  if (slipRes.rows.length === 0) return empty;
  const slip = slipRes.rows[0];
  const isUploader = slip.uploaded_by === args.actorId;

  let approvedOrRejected = false;
  if (slip.expense_id) {
    const r = await query(
      `SELECT 1 FROM approval_transitions
        WHERE target_type = 'expense' AND target_id = $1
          AND new_status IN ('approved', 'rejected') LIMIT 1`,
      [slip.expense_id],
    );
    approvedOrRejected = r.rows.length > 0;
  }

  const locked = !isUploader || approvedOrRejected;
  return {
    exists: true,
    status: slip.status,
    isUploader,
    approvedOrRejected,
    locked,
    reason: !isUploader
      ? 'Only the uploader can remove this slip'
      : approvedOrRejected
        ? 'Linked expense has already been approved or rejected'
        : null,
  };
}

export async function advanceApproval(args: {
  expenseId: number;
  actorId: number;
  decision: 'approve' | 'reject';
  comment?: string;
}) {
  try {
    const { actor: actorSession } = await requireActionFor(args.actorId, 'approve_expense', { perm: 'finance:expense:approve:all' });
    const actorPerms = new Set(actorSession.permissions);

const expRes = await query(
      `SELECT e.*
       FROM expenses e
       WHERE e.id = $1`,
      [args.expenseId]
    );
    if (expRes.rows.length === 0) throw new Error('Expense not found');
    const exp = expRes.rows[0];

    const actorRes = await query<{ id: number; role_id: string | null }>(
      `SELECT u.id,
              (SELECT ur.role_id FROM perm.user_roles ur
                WHERE ur.user_id = u.id
                ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
                LIMIT 1) AS role_id
       FROM users u
       WHERE u.id = $1`,
      [args.actorId]
    );
    const actor = actorRes.rows[0];

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
      await recordTransition({
        entityType: 'expense',
        entityId: args.expenseId,
        actorId: args.actorId,
        previousStatus: currentStage,
        newStatus: 'rejected',
        comments: t,
        stage: currentStage,
      });
      await query('COMMIT');
      await appendWaybillEvent({
        origin: 'expense',
        originId: args.expenseId,
        kind: 'rejected',
        stageFrom: currentStage,
        stageTo: 'rejected',
        actorId: args.actorId,
        payload: { reason: t },
      });
      await publishEvent('expense.rejected', { expenseId: args.expenseId, reason: t }, {
        actorId: args.actorId, refType: 'expense', refId: Number(args.expenseId),
        severity: 'warning',
        message: `Item #EXP-${args.expenseId} rejected: ${t}`,
      });
      revalidatePath('/');
      revalidatePath('/');
      revalidatePath('/');
      return { success: true, newStatus: 'rejected', rejectionReason: t };
    }

    const submitterCtx = await fetchSubmitterCtx(args.expenseId);
    const alreadyApproved = await getApprovedStages('expense', args.expenseId);
    submitterCtx.alreadyApproved = alreadyApproved;

    const actorCtx = await fetchActorCtx(args.actorId);

    const stageToAct: StageName = (currentStage in STAGE_TO_ROLE ? currentStage : submitterCtx.submitterRoleId === ''
      ? 'manager_review'
      : currentStage) as StageName;

    const allowCheck = await canActOnStage(actorCtx, submitterCtx, stageToAct, alreadyApproved, actorPerms);
    if (!allowCheck.allow) {
      throw new Error(allowCheck.reason);
    }

    const totalAmount = Number(exp.total_amount || 0);
    const resolution = await resolveApprovalChain(submitterCtx, totalAmount);

    const newStatus: string = resolution.nextStage ?? 'approved';
    const final = resolution.completed;

    await query('BEGIN');
    await query(`UPDATE expenses SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, [newStatus, args.expenseId]);
    await recordTransition({
      entityType: 'expense',
      entityId: args.expenseId,
      actorId: args.actorId,
      previousStatus: currentStage,
      newStatus,
      comments: args.comment || `Approved by ${actor?.role_id ?? actorCtx.roleId} (${stageToAct})`,
      stage: stageToAct,
    });

    if (stageToAct === 'accounting_authorization' && newStatus === 'cfo_authorization') {
      await ensurePoForExpense(args.expenseId, args.actorId);
    }
    await query('COMMIT');

    await appendWaybillEvent({
      origin: 'expense',
      originId: args.expenseId,
      kind: 'advanced',
      stageFrom: currentStage,
      stageTo: newStatus,
      actorId: args.actorId,
      payload: { decision: 'approve', stage: stageToAct },
    });

    await publishEvent('expense.advanced', { expenseId: args.expenseId, newStatus, final }, {
      actorId: args.actorId, refType: 'expense', refId: Number(args.expenseId),
      severity: newStatus === 'rejected' ? 'warning' : 'success',
      message: `Item #EXP-${args.expenseId} → ${newStatus}${final ? ' (completed)' : ''}`,
    });

    revalidatePath('/');
    revalidatePath('/');
    revalidatePath('/');
    return {
      success: true,
      newStatus,
      chainIndex: resolution.chain.findIndex(c => c.stage === newStatus),
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
    await requireActionFor(args.actorId, 'ceo_override', { perm: PERM.finance.expense.override });
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
    await recordOverride({
      entityType: args.targetType,
      entityId: args.targetId,
      actorId: args.actorId,
      kind: 'granted',
      reason: reasonTrim,
    });
    await recordTransition({
      entityType: args.targetType,
      entityId: args.targetId,
      actorId: args.actorId,
      previousStatus,
      newStatus: args.newStatus,
      comments: `CEO OVERRIDE: ${reasonTrim}`,
      stage: 'ceo_override',
    });
    await query('COMMIT');
    await publishEvent('ceo.override', { targetType: args.targetType, targetId: args.targetId, newStatus: args.newStatus }, {
      actorId: args.actorId, refType: args.targetType, refId: Number(args.targetId),
      severity: 'warning',
      message: `CEO Override: ${args.targetType.toUpperCase()} #${args.targetId} → ${args.newStatus}`,
    });
    revalidatePath('/');
    revalidatePath('/');
    revalidatePath('/');
    return { success: true, newStatus: args.newStatus, rejectionReason: args.newStatus === 'rejected' ? reasonTrim : undefined };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('ceoForceDecision failed:', error);
    return { success: false, error: error.message };
  }
}

export async function upsertApprovalPolicy(_args: {
  id?: number;
  name: string;
  priority: number;
  is_active: boolean;
  target_type: 'expense' | 'pr' | 'both';
  conditions_json: any;
  action_json: any;
  actorId: number;
}) {
  return { success: false as const, error: 'approval_policies deprecated; manage stage grants via /policy' };
}

export async function deleteApprovalPolicy(_args: { id: number; actorId: number }) {
  return { success: false as const, error: 'approval_policies deprecated' };
}

export async function submitPurchaseRequisition(args: {
  requesterId: number;
  vendorName: string;
  deptGroupId: string;
  needByDate?: string;
  totalEstimate: number;
  currency?: string;
  justification: string;
  isRecurring?: boolean;
  items: Array<{ description: string; qty: number; unit_price: number; mapped_account_code?: string }>;
}) {
  try {
    await requireActionFor(args.requesterId, 'submit_pr', { perm: PERM.finance.pr.create });

const submitterRes = await query<{ dept_perm: string | null; role_id: string | null; level: number }>(
      `SELECT (SELECT up.permission_id FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS dept_perm,
              (SELECT ur.role_id FROM perm.user_roles ur
                WHERE ur.user_id = u.id
                ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
                LIMIT 1) AS role_id,
              COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int) FROM perm.user_roles ur WHERE ur.user_id = u.id), 5)::int AS level
       FROM users u
      WHERE u.id = $1`,
      [args.requesterId],
    );
    const submitter = submitterRes.rows[0];
    const submitterDept = submitter?.dept_perm
      ? submitter.dept_perm.replace(/^user:dept:/, '').replace(/::allow$/, '')
      : null;
    const submitterCtx: ResolverCtx = {
      submitterUserId: args.requesterId,
      submitterDeptId: submitterDept ?? args.deptGroupId ?? null,
      submitterRoleId: submitter?.role_id ?? '',
      submitterLevel: submitter?.level ?? 5,
      alreadyApproved: new Set<StageName>(),
    };
    const resolution = await resolveApprovalChain(submitterCtx);
    const initialStatus = resolution.nextStage ?? 'manager_review';

    await query('BEGIN');
    const r = await query(
      `INSERT INTO purchase_requisitions
       (requester_id, dept_group_id, vendor_name, need_by_date, status,
        total_estimate, currency, justification, is_recurring)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
      [args.requesterId, args.deptGroupId, args.vendorName, args.needByDate || null,
       initialStatus, Number(args.totalEstimate) || 0, args.currency || 'THB',
       args.justification, !!args.isRecurring]
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
    await appendWaybillEvent({
      origin: 'pr',
      originId: prId,
      kind: 'submitted',
      stageFrom: null,
      stageTo: initialStatus,
      actorId: args.requesterId,
      payload: { vendor: args.vendorName, totalAmount: Number(args.totalEstimate) || 0 },
    });
    await publishEvent('pr.submitted', { prId, status: initialStatus }, {
      actorId: args.requesterId, refType: 'pr', refId: Number(prId),
      severity: 'info',
      message: `Submitted purchase request #PR-${prId} initial status ${initialStatus}`,
    });
    revalidatePath('/');
    revalidatePath('/');
    return { success: true, prId, status: initialStatus, policy: null };
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
    const { actor: actorSession } = await requireActionFor(args.actorId, 'approve_pr', { perm: PERM.finance.pr.approve });
    const actorPerms = new Set(actorSession.permissions);
    const prRes = await query(
      `SELECT pr.*
         FROM purchase_requisitions pr
        WHERE pr.id = $1`,
      [args.prId]
    );
    if (prRes.rows.length === 0) throw new Error('PR not found');
    const pr = prRes.rows[0];

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
      await recordTransition({
        entityType: 'pr',
        entityId: args.prId,
        actorId: args.actorId,
        previousStatus: pr.status,
        newStatus: 'rejected',
        comments: t,
        stage: pr.status,
      });
      await query('COMMIT');
      await appendWaybillEvent({
        origin: 'pr',
        originId: args.prId,
        kind: 'rejected',
        stageFrom: pr.status,
        stageTo: 'rejected',
        actorId: args.actorId,
        payload: { reason: t },
      });
      await publishEvent('pr.rejected', { prId: args.prId, reason: t }, {
        actorId: args.actorId, refType: 'pr', refId: Number(args.prId),
        severity: 'warning',
        message: `Purchase request #PR-${args.prId} rejected: ${t}`,
      });
      revalidatePath('/');
      revalidatePath('/');
      return { success: true, newStatus: 'rejected', rejectionReason: t };
    }

    const submitterCtx = await fetchPrSubmitterCtx(args.prId);
    const alreadyApproved = await getApprovedStages('pr', args.prId);
    submitterCtx.alreadyApproved = alreadyApproved;

    const actorCtx = await fetchActorCtx(args.actorId);

    const stageToAct: StageName = (pr.status in STAGE_TO_ROLE ? pr.status : 'manager_review') as StageName;
    const allowCheck = await canActOnStage(actorCtx, submitterCtx, stageToAct, alreadyApproved, actorPerms);
    if (!allowCheck.allow) throw new Error(allowCheck.reason);

    const resolution = await resolveApprovalChain(submitterCtx);
    const newStatus: string = resolution.nextStage ?? 'approved';
    const final = resolution.completed;

    await query('BEGIN');
    await query(`UPDATE purchase_requisitions SET status=$1, updated_at=CURRENT_TIMESTAMP WHERE id=$2`, [newStatus, args.prId]);
    await recordTransition({
      entityType: 'pr',
      entityId: args.prId,
      actorId: args.actorId,
      previousStatus: pr.status,
      newStatus,
      comments: args.comment || `Approved by ${actorCtx.roleId} (${stageToAct})`,
      stage: stageToAct,
    });
    await query('COMMIT');
    await appendWaybillEvent({
      origin: 'pr',
      originId: args.prId,
      kind: 'advanced',
      stageFrom: pr.status,
      stageTo: newStatus,
      actorId: args.actorId,
      payload: { decision: 'approve', stage: stageToAct },
    });
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
    await requireActionFor(args.actorId, 'approve_pr', { perm: PERM.finance.pr.approve });

    const prRes = await query(
      `SELECT pr.*
         FROM purchase_requisitions pr
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

    const chain: string[] = ['accounting_manager', 'cfo'];

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
         pr.matched_policy_id || null,
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
    await recordTransition({
      entityType: 'po',
      entityId: poId,
      actorId: args.actorId,
      previousStatus: 'draft',
      newStatus: 'pending_approval',
      comments: 'Auto-created from PR',
      stage: 'po_pending',
      chainIndex: 0,
    });
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
    await requireActionFor(args.actorId, 'approve_po', { perm: PERM.finance.po.approve });

    const poRes = await query(
      `SELECT po.*, pr.is_recurring
       FROM purchase_orders po
       JOIN purchase_requisitions pr ON po.pr_id = pr.id
       WHERE po.id = $1`,
      [args.poId]
    );
    if (poRes.rows.length === 0) throw new Error('PO not found');
    const po = poRes.rows[0];

    const actorRes = await query<{ id: number; role_id: string | null }>(
      `SELECT u.id,
              (SELECT ur.role_id FROM perm.user_roles ur
                WHERE ur.user_id = u.id
                ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
                LIMIT 1) AS role_id
       FROM users u
       WHERE u.id = $1`,
      [args.actorId]
    );
    const actor = actorRes.rows[0];

    const chain: string[] = ['accounting_manager', 'cfo'];

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
      await recordTransition({
        entityType: 'po',
        entityId: args.poId,
        actorId: args.actorId,
        previousStatus: po.status,
        newStatus: 'rejected',
        comments: t,
        stage: 'po_reject',
      });
      await query('COMMIT');
      await appendWaybillEvent({
        origin: 'po',
        originId: args.poId,
        kind: 'rejected',
        stageFrom: po.status,
        stageTo: 'rejected',
        actorId: args.actorId,
        payload: { reason: t },
      });
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
    const PO_STAGE_REQUIRED_ROLE: Record<string, string> = {
      po_pending: 'accounting_manager',
      po_cfo:     'cfo',
    };
    if (po.status in PO_STAGE_REQUIRED_ROLE) {
      const requiredRole = PO_STAGE_REQUIRED_ROLE[po.status];
      if (actor?.role_id !== requiredRole && actor?.role_id !== 'cfo' && actor?.role_id !== 'ceo' && actor?.role_id !== 'admin') {
        throw new Error(`Current PO stage "${po.status}" requires role "${requiredRole}", actor has "${actor?.role_id}"`);
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
    await recordTransition({
      entityType: 'po',
      entityId: args.poId,
      actorId: args.actorId,
      previousStatus: po.status,
      newStatus,
      comments: args.comment || `Approved by ${actor?.role_id ?? 'system'}`,
      stage: newStatus,
      chainIndex: nextIdx,
    });
    await query('COMMIT');

    await appendWaybillEvent({
      origin: 'po',
      originId: args.poId,
      kind: 'advanced',
      stageFrom: po.status,
      stageTo: newStatus,
      actorId: args.actorId,
      payload: { decision: 'approve' },
    });

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
    await requireActionFor(args.actorId, 'attach_po_payslip', { perm: PERM.finance.po.attach_payslip });

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
    await recordTransition({
      entityType: 'po',
      entityId: args.poId,
      actorId: args.actorId,
      previousStatus: 'approved',
      newStatus: 'settled',
      comments: `Payslip slipId=${args.slipId} attached`,
      stage: 'po_settled',
    });
    await query('COMMIT');

    await appendWaybillEvent({
      origin: 'po',
      originId: args.poId,
      kind: 'settled',
      stageFrom: 'approved',
      stageTo: 'settled',
      actorId: args.actorId,
      payload: { slipId: args.slipId },
    });

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

export async function ensurePoForExpense(
  expenseId: number,
  actorId: number,
): Promise<{ poId: number; poNumber: string; reused: boolean } | null> {
  const existing = await query<{ id: number; po_number: string }>(
    `SELECT id, po_number
       FROM purchase_orders
      WHERE vendor_name = (SELECT vendor_name FROM expenses WHERE id = $1)
        AND total_amount = (SELECT total_amount FROM expenses WHERE id = $1)
        AND status NOT IN ('rejected')
      ORDER BY id DESC
      LIMIT 1`,
    [expenseId],
  );
  if (existing.rows.length > 0) {
    return { poId: existing.rows[0].id, poNumber: existing.rows[0].po_number, reused: true };
  }

  const expRes = await query<{ vendor_name: string; total_amount: number; currency: string }>(
    `SELECT vendor_name, total_amount, COALESCE(currency,'THB') AS currency
       FROM expenses WHERE id = $1`,
    [expenseId],
  );
  if (expRes.rows.length === 0) return null;
  const exp = expRes.rows[0];

  const year = new Date().getFullYear();
  const poNumber = `PO-${year}-EXP-${expenseId}`;

  const ins = await query<{ id: number }>(
    `INSERT INTO purchase_orders
       (pr_id, po_number, vendor_name, total_amount, currency, status, issued_by)
     VALUES (
       (SELECT COALESCE(MIN(id), 1) FROM purchase_requisitions WHERE status='approved' LIMIT 1),
       $1, $2, $3, $4, 'pending_disbursement', $5
     )
     RETURNING id`,
    [poNumber, exp.vendor_name || 'Unknown Vendor', Number(exp.total_amount) || 0, exp.currency, actorId],
  );
  const poId = ins.rows[0].id;

  await recordTransition({
    entityType: 'po',
    entityId: poId,
    actorId,
    previousStatus: 'draft',
    newStatus: 'pending_disbursement',
    comments: `Auto-set by Accounting Manager for EXP-${expenseId}`,
    stage: 'po_pending',
    chainIndex: 0,
  });

  return { poId, poNumber, reused: false };
}

export async function settleExpenseMock(args: {
  expenseId: number;
  actorId: number;
  paymentMethod: 'cash' | 'credit_card' | 'transfer';
}) {
  try {
    await requireActionFor(args.actorId, 'settle_expense', { perm: PERM.finance.expense.settle });

    const expRes = await query(
      `SELECT id, status, vendor_name, total_amount, vat_amount, submitter_id
         FROM expenses WHERE id = $1`,
      [args.expenseId],
    );
    if (expRes.rows.length === 0) throw new Error('Expense not found');
    const exp = expRes.rows[0];
    if (exp.status !== 'approved' && exp.status !== 'finance_review') {
      throw new Error(`Expense must be 'approved' or 'finance_review' (current: ${exp.status})`);
    }

    const po = await ensurePoForExpense(args.expenseId, args.actorId);
    const poNumber = po?.poNumber ?? null;

    await query('BEGIN');
    await query(
      `UPDATE expenses
          SET status='paid',
              updated_at=CURRENT_TIMESTAMP,
              payment_method=$1
        WHERE id=$2`,
      [args.paymentMethod, args.expenseId],
    );
    await recordTransition({
      entityType: 'expense',
      entityId: args.expenseId,
      actorId: args.actorId,
      previousStatus: exp.status,
      newStatus: 'paid',
      comments: `Mock payment slip generated · PO=${poNumber ?? 'n/a'} · method=${args.paymentMethod}`,
      stage: 'finance_review',
    });
    if (po) {
      await query(
        `UPDATE purchase_orders
            SET status='settled',
                settled_at=CURRENT_TIMESTAMP,
                settled_by=$1
          WHERE id=$2`,
        [args.actorId, po.poId],
      );
      await recordTransition({
        entityType: 'po',
        entityId: po.poId,
        actorId: args.actorId,
        previousStatus: 'pending_disbursement',
        newStatus: 'settled',
        comments: `Mock disbursement for EXP-${args.expenseId}`,
        stage: 'po_settled',
      });
    }

    await postExpenseToGL({
      expenseId: args.expenseId,
      vendorName: exp.vendor_name,
      totalAmount: exp.total_amount,
      vatAmount: exp.vat_amount,
    }).catch((e) => console.error('GL post failed (non-fatal):', e?.message));

    await query('COMMIT');

    await appendWaybillEvent({
      origin: 'expense',
      originId: args.expenseId,
      kind: 'settled',
      stageFrom: exp.status,
      stageTo: 'disbursed',
      actorId: args.actorId,
      payload: { paymentMethod: args.paymentMethod, poNumber },
    });
    if (po) {
      await appendWaybillEvent({
        origin: 'po',
        originId: po.poId,
        kind: 'settled',
        stageFrom: 'pending_disbursement',
        stageTo: 'settled',
        actorId: args.actorId,
        payload: { expenseId: args.expenseId },
      });
    }

    await publishEvent('expense.paid', {
      expenseId: args.expenseId,
      poNumber,
      paymentMethod: args.paymentMethod,
    }, {
      actorId: args.actorId, refType: 'expense', refId: Number(args.expenseId),
      severity: 'success',
      message: `EXP-${args.expenseId} settled via mock slip · PO=${poNumber ?? 'n/a'}`,
    });

    revalidatePath('/');
    revalidatePath('/');
    revalidatePath('/expense-claim');
    return { success: true, poNumber, paidAt: new Date().toISOString() };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('settleExpenseMock failed:', error);
    return { success: false, error: error.message };
  }
}

export async function getExpenseLifecycle(expenseId: number) {
  const r = await query(
    `SELECT at.id, at.previous_status, at.new_status, at.stage,
            at.comments, at.created_at,
            u.id AS actor_id, u.fullname AS actor_name,
            pr.id AS actor_role_id, pr.display_name AS actor_role_name
       FROM approval_transitions at
       LEFT JOIN users u ON u.id = at.actor_id
       LEFT JOIN perm.user_roles ur ON ur.user_id = u.id
       LEFT JOIN perm.user_roles ur
      WHERE at.target_type = 'expense' AND at.target_id = $1
      ORDER BY at.created_at ASC, at.id ASC`,
    [expenseId],
  );
  return r.rows;
}

export interface DraftPayload {
  vendorName?: string;
  vendorAddress?: string;
  createdTo?: string;
  createdToAddress?: string;
  transactionDate?: string;
  subtotal?: number;
  vatAmount?: number;
  totalAmount?: number;
  paymentMethod?: string;
  notes?: string;
}

export interface StartDraftResult {
  ok: boolean;
  waybillId?: string;
  expenseId?: number;
  error?: string;
}

export async function startExpenseDraft(actorId: number): Promise<StartDraftResult> {
  try {
    const existing = await query<{ id: string; origin_id: number }>(
      `SELECT id, origin_id
         FROM waybills
        WHERE submitter_id = $1
          AND origin = 'expense'
          AND current_stage = 'draft'
          AND status = 'open'
     ORDER BY created_at DESC
        LIMIT 1`,
      [actorId],
    );
    if (existing.rows[0]) {
      return { ok: true, waybillId: existing.rows[0].id, expenseId: existing.rows[0].origin_id };
    }

    const fiscalYear = new Date().getFullYear();
    const seqRes = await query<{ id: string }>(
      `SELECT next_waybill_number($1::smallint) AS id`,
      [fiscalYear],
    );
    const waybillId = seqRes.rows[0]?.id;
    if (!waybillId) return { ok: false, error: 'Failed to reserve waybill number' };

    const expRes = await query<{ id: number }>(
      `INSERT INTO expenses (submitter_id, status, payment_method)
       VALUES ($1, 'draft', 'cash')
       RETURNING id`,
      [actorId],
    );
    const expenseId = expRes.rows[0]?.id;
    if (!expenseId) return { ok: false, error: 'Failed to create expense draft' };

    await query(
      `INSERT INTO waybills
         (id, origin, origin_id, fiscal_year, waybill_kind,
          submitter_id, current_stage, status, created_at, updated_at)
       VALUES ($1, 'expense', $2, $3, 'reimbursement',
               $4, 'draft', 'open', now(), now())`,
      [waybillId, expenseId, fiscalYear, actorId],
    );

    await query(
      `INSERT INTO waybill_events
         (waybill_id, sequence, previous_event_id, kind, stage_from, stage_to,
          actor_id, actor_role, actor_signature, payload)
       VALUES (
         $1, 1, NULL, 'created', NULL, 'draft',
         $2, NULL, $3,
         $4::jsonb
       )`,
      [
        waybillId,
        actorId,
        Buffer.alloc(0),
        JSON.stringify({ reason: 'draft-created' }),
      ],
    );

    return { ok: true, waybillId, expenseId };
  } catch (e: any) {
    console.error('startExpenseDraft failed:', e);
    return { ok: false, error: e?.message ?? 'startExpenseDraft failed' };
  }
}

export async function saveDraftExpense(args: {
  waybillId: string;
  payload: DraftPayload;
  actorId: number;
}): Promise<{ ok: boolean; savedAt?: string; error?: string }> {
  try {
    const wbRes = await query<{ submitter_id: number; origin_id: number; current_stage: string }>(
      `SELECT submitter_id, origin_id, current_stage
         FROM waybills WHERE id = $1`,
      [args.waybillId],
    );
    const wb = wbRes.rows[0];
    if (!wb) return { ok: false, error: 'Waybill not found' };
    if (wb.submitter_id !== args.actorId) return { ok: false, error: 'Not your draft' };
    if (wb.current_stage !== 'draft') return { ok: false, error: 'Draft already finalized' };

    const p = args.payload ?? {};
    await query(
      `UPDATE expenses SET
         vendor_name        = COALESCE(NULLIF($1, ''), vendor_name),
         transaction_date   = COALESCE(NULLIF($2, '')::date, transaction_date),
         subtotal           = COALESCE($3::numeric, subtotal),
         vat_amount         = COALESCE($4::numeric, vat_amount),
         total_amount       = COALESCE($5::numeric, total_amount),
         payment_method     = COALESCE(NULLIF($6, ''), payment_method),
         correction_notes   = COALESCE(NULLIF($7, ''), correction_notes),
         created_to         = COALESCE(NULLIF($9, ''), created_to),
         vendor_address     = COALESCE(NULLIF($10, ''), vendor_address),
         created_to_address = COALESCE(NULLIF($11, ''), created_to_address),
         draft_updated_at   = now(),
         updated_at         = CURRENT_TIMESTAMP
       WHERE id = $8`,
      [
        p.vendorName ?? null,
        p.transactionDate ?? null,
        p.subtotal ?? null,
        p.vatAmount ?? null,
        p.totalAmount ?? null,
        p.paymentMethod ?? null,
        p.notes ?? null,
        wb.origin_id,
        p.createdTo ?? null,
        p.vendorAddress ?? null,
        p.createdToAddress ?? null,
      ],
    );

    await query(
      `UPDATE waybills SET
         vendor_name        = COALESCE(NULLIF($1, ''), vendor_name),
         total_amount       = COALESCE($2::numeric, total_amount),
         created_to         = COALESCE(NULLIF($3, ''), created_to),
         vendor_address     = COALESCE(NULLIF($5, ''), vendor_address),
         created_to_address = COALESCE(NULLIF($6, ''), created_to_address),
         updated_at         = now()
       WHERE id = $4`,
      [p.vendorName ?? null, p.totalAmount ?? null, p.createdTo ?? null, args.waybillId, p.vendorAddress ?? null, p.createdToAddress ?? null],
    );

    return { ok: true, savedAt: new Date().toISOString() };
  } catch (e: any) {
    console.error('saveDraftExpense failed:', e);
    return { ok: false, error: e?.message ?? 'saveDraftExpense failed' };
  }
}

export async function submitManualExpense(args: {
  waybillId: string;
  actorId: number;
  vendorName: string;
  transactionDate: string;
  paymentMethod: string;
  subtotal: number;
  vatAmount: number;
  totalAmount: number;
}): Promise<{ ok: boolean; error?: string; waybillId?: string }> {
  try {
    await requireActionFor(args.actorId, 'submit_expense', { perm: PERM.finance.expense.create });

    const wbRes = await query<{ submitter_id: number; origin_id: number; current_stage: string }>(
      `SELECT submitter_id, origin_id, current_stage
         FROM waybills WHERE id = $1`,
      [args.waybillId],
    );
    const wb = wbRes.rows[0];
    if (!wb) return { ok: false, error: 'Waybill not found' };
    if (wb.submitter_id !== args.actorId) return { ok: false, error: 'Not your draft' };
    if (wb.current_stage !== 'draft') return { ok: false, error: 'Draft already finalized' };

    const total = args.totalAmount;
    const vendor = args.vendorName.trim() || 'Unknown Vendor';

    await query('BEGIN');
    try {
      await query(
        `UPDATE expenses
            SET vendor_name = $1, transaction_date = $2, subtotal = $3,
                vat_amount = $4, total_amount = $5, payment_method = $6,
                status = 'submission', updated_at = CURRENT_TIMESTAMP
          WHERE id = $7`,
        [vendor, args.transactionDate, args.subtotal, args.vatAmount, total, args.paymentMethod, wb.origin_id],
      );

      await query(
        `UPDATE waybills
            SET vendor_name = $1, total_amount = $2,
                current_stage = 'submission', currency = 'THB', updated_at = now()
          WHERE id = $3`,
        [vendor, total, args.waybillId],
      );

      await query(
        `INSERT INTO waybill_events
           (waybill_id, sequence, previous_event_id, kind, stage_from, stage_to,
            actor_id, actor_role, actor_signature, payload)
         VALUES (
           $1, (SELECT COALESCE(MAX(sequence), 0) + 1 FROM waybill_events WHERE waybill_id = $1),
           (SELECT id FROM waybill_events WHERE waybill_id = $1 ORDER BY sequence DESC LIMIT 1),
           'submitted', 'draft', 'submission',
           $2, NULL, $3, $4::jsonb
         )`,
        [args.waybillId, args.actorId, Buffer.alloc(0), JSON.stringify({ vendor, totalAmount: total })],
      );

      await query('COMMIT');
    } catch (e) {
      await query('ROLLBACK');
      throw e;
    }

    revalidatePath('/expense');
    revalidatePath(`/waybill/${args.waybillId}`);
    return { ok: true, waybillId: args.waybillId };
  } catch (e: any) {
    console.error('submitManualExpense failed:', e);
    return { ok: false, error: e?.message ?? 'submitManualExpense failed' };
  }
}

export async function discardDraftExpense(args: {
  waybillId: string;
  actorId: number;
}): Promise<{ ok: boolean; error?: string }> {
  try {
    const wbRes = await query<{ submitter_id: number; origin_id: number; current_stage: string }>(
      `SELECT submitter_id, origin_id, current_stage
         FROM waybills WHERE id = $1`,
      [args.waybillId],
    );
    const wb = wbRes.rows[0];
    if (!wb) return { ok: false, error: 'Waybill not found' };
    if (wb.submitter_id !== args.actorId) return { ok: false, error: 'Not your draft' };
    if (wb.current_stage !== 'draft') return { ok: false, error: 'Draft already finalized' };

    await query('BEGIN');
    try {
      await query(`DELETE FROM waybill_events WHERE waybill_id = $1`, [args.waybillId]);
      await query(`DELETE FROM waybill_attachments WHERE waybill_id = $1`, [args.waybillId]);
      await query(`DELETE FROM slips WHERE expense_id = $1 AND status = 'pending'`, [wb.origin_id]);
      await query(`DELETE FROM expense_items WHERE expense_id = $1`, [wb.origin_id]);
      await query(`DELETE FROM expenses WHERE id = $1 AND status = 'draft'`, [wb.origin_id]);
      await query(`DELETE FROM waybills WHERE id = $1 AND current_stage = 'draft'`, [args.waybillId]);
      await query('COMMIT');
    } catch (e) {
      await query('ROLLBACK');
      throw e;
    }

    revalidatePath('/expense');
    return { ok: true };
  } catch (e: any) {
    console.error('discardDraftExpense failed:', e);
    return { ok: false, error: e?.message ?? 'discardDraftExpense failed' };
  }
}

// ----- exports (B: FormData actions) -----
const ApproveForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  stage: z.string().min(1).max(64).optional(),
});

export async function approveWaybillAction(formData: FormData): Promise<void> {
  const stageRaw = String(formData.get('stage') ?? '').trim();
  const parsed = ApproveForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    stage: stageRaw === '' ? undefined : stageRaw,
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.status !== 'open') throw new Error('Waybill is not open');

  const actor = await actorForWaybill();

  if (parsed.stage && parsed.stage !== wb.current_stage) {
    if (canRecall(actor, wb)) {
      const r = await reCallWaybillAction({
        waybillId: parsed.waybillId,
        targetStage: parsed.stage,
        actorId: actor.id,
        actorRole: actor.role_name,
        reason: 'cfo override',
      });
      if (!r.ok) throw new Error(r.error);
      revalidatePath(`/waybill/${parsed.waybillId}`);
      redirect(`/waybill/${parsed.waybillId}`);
    }
  }

  if (!canActOnWaybillStage(actor, wb)) {
    throw new Error('cannot act at this stage');
  }

  const currentStage = wb.current_stage as Parameters<typeof resolveNextStage>[0];
  const domain: 'expense' | 'procurement' | 'sales' =
    wb.origin === 'expense' ? 'expense'
      : wb.origin === 'so' ? 'sales'
        : 'procurement';
  const next = resolveNextStage(currentStage, actor.role_name, undefined, domain);
  if (!next) throw new Error(`No next stage from "${currentStage}"`);

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = $1, updated_at = now() WHERE id = $2`,
        [next.stage, wb.origin_id],
      );
    } else if (wb.origin === 'pr') {
      await q(
        `UPDATE purchase_requisitions SET status = $1, updated_at = now() WHERE id = $2`,
        [next.stage, wb.origin_id],
      );
    } else if (wb.origin === 'po') {
      await q(
        `UPDATE purchase_orders SET status = $1, updated_at = now() WHERE id = $2`,
        [next.stage, wb.origin_id],
      );
    } else if (wb.origin === 'so') {
      await q(
        `UPDATE sales_orders SET status = $1, updated_at = now() WHERE id = $2`,
        [next.stage, wb.origin_id],
      );
    }
    if (wb.origin === 'expense' && wb.current_stage === 'accounting_verification' && next.stage === 'accounting_authorization') {
      await ensurePoForExpenseWithClient(q, wb.origin_id);
      const expRow = await q<{ vendor_name: string | null }>(
        `SELECT vendor_name FROM expenses WHERE id = $1`,
        [wb.origin_id],
      );
      await upsertDraftJournal({
        expenseId: wb.origin_id,
        vendorName: expRow.rows[0]?.vendor_name ?? '',
      });
    }
    if (
      wb.origin === 'pr' &&
      wb.current_stage === 'accounting_verification' &&
      next.stage === 'accounting_authorization'
    ) {
      const prRow = await q<{ vendor_name: string | null }>(
        `SELECT vendor_name FROM purchase_requisitions WHERE id = $1`,
        [wb.origin_id],
      );
      await upsertProcurementDraftAccrual({
        origin: 'pr',
        originId: wb.origin_id,
        vendorName: prRow.rows[0]?.vendor_name ?? '',
      });
    }
    if (
      wb.origin === 'po' &&
      wb.current_stage === 'accounting_verification' &&
      next.stage === 'accounting_authorization'
    ) {
      const poRow = await q<{ vendor_name: string | null }>(
        `SELECT vendor_name FROM purchase_orders WHERE id = $1`,
        [wb.origin_id],
      );
      await upsertProcurementDraftAccrual({
        origin: 'po',
        originId: wb.origin_id,
        vendorName: poRow.rows[0]?.vendor_name ?? '',
      });
    }
    if (wb.origin === 'expense' && next.stage === 'final_authorization') {
      await ensureGlForExpense(q, wb.origin_id, actor.id);
    }
    await q(
      `UPDATE waybills SET current_stage = $1, current_owner_role = $2, updated_at = now()
        WHERE id = $3`,
      [next.stage, next.completed ? 'finance' : next.stage, wb.id],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'advanced',
      stageFrom: wb.current_stage,
      stageTo: next.stage,
      actorId: actor.id,
      actorRole: actor.role_name,
      payload: { decision: 'approve' },
      client: q as never,
    });

    if (
      wb.current_stage === 'accounting_verification' &&
      next.stage === 'accounting_authorization' &&
      (wb.origin === 'expense' || wb.origin === 'po' || wb.origin === 'pr')
    ) {
      const actorName = String(actor.role_name ?? 'system');
      const { rows: actorRows } = await q<{ fullname: string }>(
        `SELECT fullname FROM users WHERE id = $1`,
        [actor.id],
      );
      const fullname = actorRows[0]?.fullname ?? actorName;
      await ensurePoPdf(wb.id, fullname);
    }
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const RejectForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  reason: z.string().min(5).max(2000),
});

export async function rejectWaybillAction(formData: FormData): Promise<void> {
  const parsed = RejectForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    reason: String(formData.get('reason') ?? '').trim(),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');

  const actor = await actorForWaybill();
  if (!canRejectWaybill(actor, wb)) {
    throw new Error('cannot reject at this stage');
  }

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = 'rejected',
                            rejection_reason = $2,
                            rejection_actor_id = $3,
                            rejected_at = now(),
                            updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, actor.id],
      );
      if (wb.current_stage === 'accounting_authorization') {
        await q(
          `UPDATE purchase_orders
              SET status = 'rejected',
                  rejection_reason = $2,
                  rejection_actor_id = $3,
                  rejected_at = now(),
                  updated_at = now()
            WHERE id = (SELECT po_id FROM expenses WHERE id = $1)`,
          [wb.origin_id, parsed.reason, actor.id],
        );
      }
    } else if (wb.origin === 'pr') {
      await q(
        `UPDATE purchase_requisitions SET status = 'rejected',
                                        rejection_reason = $2,
                                        rejection_actor_id = $3,
                                        rejected_at = now(),
                                        updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, actor.id],
      );
    } else if (wb.origin === 'po') {
      await q(
        `UPDATE purchase_orders SET status = 'rejected',
                                  rejection_reason = $2,
                                  rejection_actor_id = $3,
                                  rejected_at = now(),
                                  updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, actor.id],
      );
    }
    await q(
      `UPDATE waybills SET current_stage = 'rejected',
                          status = 'rejected',
                          updated_at = now()
        WHERE id = $1`,
      [wb.id],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'rejected',
      stageFrom: wb.current_stage,
      stageTo: 'rejected',
      actorId: actor.id,
      actorRole: actor.role_name,
      payload: { reason: parsed.reason },
      client: q as never,
    });
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const FinalApproveForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
});

export async function finalApproveWaybillAction(formData: FormData): Promise<void> {
  const parsed = FinalApproveForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'expense') {
    throw new Error(`final approve currently limited to expense origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canFinalApproveExpense(actor, wb)) {
    throw new Error('cannot final approve at this stage');
  }

  const expRes = await _query<{ vendor_name: string; total_amount: string; vat_amount: string }>(
    `SELECT vendor_name, total_amount, vat_amount FROM expenses WHERE id = $1`,
    [wb.origin_id],
  );
  if (expRes.rows.length === 0) throw new Error('Expense not found');
  const exp = expRes.rows[0];

  await withTransaction(async (q) => {
    await q(
      `UPDATE expenses SET status = 'awaiting_disbursement', updated_at = now() WHERE id = $1`,
      [wb.origin_id],
    );
    await q(
      `UPDATE waybills SET current_stage = 'awaiting_disbursement',
                          current_owner_role = 'finance',
                          updated_at = now()
        WHERE id = $1`,
      [wb.id],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'advanced',
      stageFrom: 'final_authorization',
      stageTo: 'awaiting_disbursement',
      actorId: actor.id,
      actorRole: actor.role_name ?? 'finance',
      payload: { decision: 'final-approve', gl_will_post: true },
      client: q as never,
    });
  });

  let journalId: number;
  const draft = await finalizeDraftJournal({ expenseId: wb.origin_id, actorId: actor.id });
  if (draft) {
    journalId = draft.journalId;
  } else {
    const upsert = await upsertDraftJournal({
      expenseId: wb.origin_id,
      vendorName: exp.vendor_name,
    });
    journalId = upsert.journalId;
    const fin = await finalizeDraftJournal({ expenseId: wb.origin_id, actorId: actor.id });
    if (!fin) throw new Error('failed to finalize draft journal');
    journalId = fin.journalId;
  }
  await withTransaction(async (q) => {
    await setExpenseJournalEntry(q, wb.origin_id, journalId, actor.id);
  });

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl',
    stageFrom: 'final_authorization',
    stageTo: 'awaiting_disbursement',
    actorId: actor.id,
    actorRole: actor.role_name ?? 'finance',
    payload: { journalId, expenseId: wb.origin_id },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const FinalRejectForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  reason: z.string().min(5).max(2000),
});

export async function finalRejectWaybillAction(formData: FormData): Promise<void> {
  const parsed = FinalRejectForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    reason: String(formData.get('reason') ?? '').trim(),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.status !== 'open') throw new Error(`Waybill status is '${wb.status}', not open`);
  if (wb.current_stage !== 'final_authorization') {
    throw new Error(`final reject only at final_authorization (current: ${wb.current_stage})`);
  }

  const actor = await actorForWaybill();
  if (!canRejectWaybill(actor, wb)) {
    throw new Error('cannot reject at this stage');
  }

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = 'rejected',
                            rejection_reason = $2,
                            rejection_actor_id = $3,
                            rejected_at = now(),
                            updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, actor.id],
      );
    } else if (wb.origin === 'pr') {
      await q(
        `UPDATE purchase_requisitions SET status = 'rejected',
                                        rejection_reason = $2,
                                        rejection_actor_id = $3,
                                        rejected_at = now(),
                                        updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, actor.id],
      );
    } else if (wb.origin === 'po') {
      await q(
        `UPDATE purchase_orders SET status = 'rejected',
                                  rejection_reason = $2,
                                  rejection_actor_id = $3,
                                  rejected_at = now(),
                                  updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, actor.id],
      );
    }
    await q(
      `UPDATE waybills SET current_stage = 'rejected',
                          status = 'rejected',
                          updated_at = now()
        WHERE id = $1`,
      [wb.id],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'rejected',
      stageFrom: 'final_authorization',
      stageTo: 'rejected',
      actorId: actor.id,
      actorRole: actor.role_name ?? 'finance',
      payload: { decision: 'final-reject', reason: parsed.reason, gl_posted: false },
      client: q as never,
    });
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const ResubmitForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
});

export async function resubmitWaybillAction(formData: FormData): Promise<void> {
  const parsed = ResubmitForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb || wb.status !== 'rejected') throw new Error('Not in rejected state');

  const actor = await actorForWaybill();
  if (!canResubmit(actor, wb)) {
    throw new Error('cannot resubmit at this stage');
  }

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = 'submission',
                            rejection_reason = NULL,
                            rejection_actor_id = NULL,
                            rejected_at = NULL,
                            updated_at = now()
          WHERE id = $1`,
        [wb.origin_id],
      );
    } else if (wb.origin === 'pr') {
      await q(
        `UPDATE purchase_requisitions SET status = 'submission',
                                        rejection_reason = NULL,
                                        rejection_actor_id = NULL,
                                        rejected_at = NULL,
                                        updated_at = now()
          WHERE id = $1`,
        [wb.origin_id],
      );
    }
    await q(
      `UPDATE waybills SET current_stage = 'submission',
                          status = 'open',
                          current_owner_role = 'supervisor',
                          updated_at = now()
        WHERE id = $1`,
      [wb.id],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'resubmitted',
      stageFrom: 'rejected',
      stageTo: 'submission',
      actorId: actor.id,
      actorRole: actor.role_name,
      payload: { origin: wb.origin, origin_id: wb.origin_id },
      client: q as never,
    });
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const AttachPaymentSlipForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  expenseId: z.coerce.number().int().positive(),
  slipId: z.coerce.number().int().positive(),
  paymentMethod: z.enum(['cash', 'credit_card', 'transfer']),
});

export interface AttachPaymentSlipResult {
  ok: boolean;
  error?: string;
}

export async function attachPaymentSlipAction(formData: FormData): Promise<AttachPaymentSlipResult> {
  const parsed = AttachPaymentSlipForm.safeParse({
    waybillId: String(formData.get('waybillId') ?? ''),
    expenseId: String(formData.get('expenseId') ?? '0'),
    slipId: String(formData.get('slipId') ?? '0'),
    paymentMethod: String(formData.get('paymentMethod') ?? 'transfer'),
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? 'invalid input' };
  }

  const wb = await loadWaybill(parsed.data.waybillId);
  if (!wb) return { ok: false, error: 'waybill not found' };
  if (wb.origin !== 'expense') {
    return { ok: false, error: `attach-payment-slip only for expense origin (got ${wb.origin})` };
  }
  if (wb.current_stage !== 'awaiting_disbursement') {
    return { ok: false, error: `expense must be awaiting_disbursement (current: ${wb.current_stage})` };
  }

  const actor = await loadActor();
  if (!actor) return { ok: false, error: 'unauthorized' };
  if (!canSettleExpense(actor, wb)) {
    return { ok: false, error: 'cannot settle at this stage' };
  }

  const slipRes = await _query<{ id: number; uploaded_by: number; status: string; expense_id: number | null; ocr_raw_json: unknown }>(
    `SELECT id, uploaded_by, status, expense_id, ocr_raw_json FROM slips WHERE id = $1`,
    [parsed.data.slipId],
  );
  if (slipRes.rows.length === 0) return { ok: false, error: 'slip not found' };
  const slip = slipRes.rows[0];
  if (slip.status !== 'pending') return { ok: false, error: 'slip must be in pending state' };
  if (slip.expense_id != null && slip.expense_id !== parsed.data.expenseId) {
    return { ok: false, error: 'slip already attached to another expense' };
  }

  let exp: { vendor_name: string; total_amount: string; vat_amount: string };
  const expRes = await _query<{ vendor_name: string; total_amount: string; vat_amount: string }>(
    `SELECT vendor_name, total_amount, vat_amount FROM expenses WHERE id = $1`,
    [parsed.data.expenseId],
  );
  if (expRes.rows.length === 0) {
    const ocr = (slip.ocr_raw_json ?? {}) as Record<string, unknown>;
    const vendor = String(ocr.vendorName ?? wb.vendor_name ?? `Waybill ${wb.id}`).slice(0, 150);
    const total = Number(ocr.totalAmount ?? wb.total_amount ?? 0) || 0;
    const vat = Number(ocr.vatAmount ?? 0) || 0;
    const subtotal = Number(ocr.subtotal ?? Math.max(total - vat, 0)) || 0;
    const txDateRaw = ocr.transactionDate;
    const txDate =
      typeof txDateRaw === 'string' && /^\d{4}-\d{2}-\d{2}/.test(txDateRaw)
        ? txDateRaw.slice(0, 10)
        : null;
    const submitterRes = await _query<{ id: number }>(
      `SELECT id FROM users WHERE id = $1`,
      [wb.submitter_id],
    );
    const submitterId = submitterRes.rows.length > 0 ? wb.submitter_id : actor.id;
    await _query(
      `INSERT INTO expenses (id, submitter_id, vendor_name, transaction_date,
                              subtotal, vat_amount, total_amount,
                              payment_method, status, ocr_raw_json)
         OVERRIDING SYSTEM VALUE
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'transfer', 'awaiting_disbursement', $8)
       ON CONFLICT (id) DO NOTHING`,
      [
        parsed.data.expenseId,
        submitterId,
        vendor,
        txDate,
        subtotal,
        vat,
        total,
        JSON.stringify({ ...ocr, reconstructedFrom: 'waybill', waybillId: wb.id }),
      ],
    );
    const recheck = await _query<{ vendor_name: string; total_amount: string; vat_amount: string }>(
      `SELECT vendor_name, total_amount, vat_amount FROM expenses WHERE id = $1`,
      [parsed.data.expenseId],
    );
    if (recheck.rows.length === 0) {
      return { ok: false, error: 'expense not found and could not be reconstructed' };
    }
    exp = recheck.rows[0];
  } else {
    exp = expRes.rows[0];
  }

  await withTransaction(async (q) => {
    await q(
      `UPDATE slips SET expense_id = $1, status = 'confirmed', confirmed_at = now()
        WHERE id = $2`,
      [parsed.data.expenseId, parsed.data.slipId],
    );
    await q(
      `UPDATE expenses SET status = 'disbursed',
                          payment_method = $1,
                          disbursed_at = now(),
                          disbursed_by = $2,
                          updated_at = now()
        WHERE id = $3`,
      [parsed.data.paymentMethod, actor.id, parsed.data.expenseId],
    );
    await q(
      `UPDATE waybills SET current_stage = 'disbursed',
                          status = 'completed',
                          updated_at = now()
        WHERE id = $1`,
      [wb.id],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'settled',
      stageFrom: 'awaiting_disbursement',
      stageTo: 'disbursed',
      actorId: actor.id,
      actorRole: actor.role_name ?? 'finance',
      payload: {
        paymentMethod: parsed.data.paymentMethod,
        slipId: parsed.data.slipId,
      },
      client: q as never,
    });
  });

  let journalId: number | undefined;
  const draft = await finalizeDraftJournal({
    expenseId: parsed.data.expenseId,
    actorId: actor.id,
  });
  if (draft) {
    journalId = draft.journalId;
  } else {
    const upsert = await upsertDraftJournal({
      expenseId: parsed.data.expenseId,
      vendorName: exp.vendor_name,
    });
    journalId = upsert.journalId;
    const fin = await finalizeDraftJournal({
      expenseId: parsed.data.expenseId,
      actorId: actor.id,
    });
    if (fin) journalId = fin.journalId;
  }

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl',
    stageFrom: 'awaiting_disbursement',
    stageTo: 'disbursed',
    actorId: actor.id,
    actorRole: actor.role_name ?? 'finance',
    payload: {
      journalId,
      slipId: parsed.data.slipId,
      posted_by: 'attachPaymentSlipAction',
    },
  });

  revalidatePath(`/waybill/${wb.id}`);
  return { ok: true };
}

const ConfirmGlForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  expenseId: z.coerce.number().int().positive(),
});

export async function confirmGlRecordedAction(formData: FormData): Promise<void> {
  const parsed = ConfirmGlForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    expenseId: String(formData.get('expenseId') ?? '0'),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'expense') {
    throw new Error(`confirm-gl only for expense origin (got ${wb.origin})`);
  }
  if (wb.current_stage !== 'disbursed') {
    throw new Error(
      `GL can only be confirmed after disbursement (current: ${wb.current_stage})`,
    );
  }

  const actor = await actorForWaybill();
  if (!canConfirmGl(actor, wb)) {
    throw new Error('cannot confirm GL at this stage');
  }

  const postedRes = await _query<{ exists: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM waybill_events
        WHERE waybill_id = $1 AND kind = 'posted-to-gl'
     ) AS exists`,
    [wb.id],
  );
  if (!postedRes.rows[0]?.exists) {
    throw new Error('No posted-to-gl event on this waybill yet');
  }

  const expRes = await _query<{ gl_confirmed_at: string | null }>(
    `SELECT gl_confirmed_at FROM expenses WHERE id = $1`,
    [parsed.expenseId],
  );
  if (expRes.rows.length === 0) throw new Error('Expense not found');
  if (expRes.rows[0].gl_confirmed_at != null) {
    throw new Error('GL post already confirmed');
  }

  await withTransaction(async (q) => {
    await q(
      `UPDATE expenses SET gl_confirmed_at = now(),
                           gl_confirmed_by = $1,
                           updated_at = now()
        WHERE id = $2`,
      [actor.id, parsed.expenseId],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'gl-confirmed',
      stageFrom: 'disbursed',
      stageTo: 'disbursed',
      actorId: actor.id,
      actorRole: actor.role_name ?? 'finance',
      payload: { expenseId: parsed.expenseId },
      client: q as never,
    });
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const AttachForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  storageKey: z.string().min(1).max(500),
  filename: z.string().min(1).max(255),
  contentType: z.string().min(1).max(120),
  byteSize: z.coerce.number().int().min(0).max(50 * 1024 * 1024),
  kind: z.enum([
    'slip','pr_doc','po_doc','payment_receipt','signoff_memo',
    'invoice','wht_cert','photo','memo','other',
  ]),
  caption: z.string().max(2000).optional(),
});

export interface AttachActionResult {
  ok: boolean;
  error?: string;
}

export async function attachWaybillDocumentAction(formData: FormData): Promise<AttachActionResult> {
  const parsed = AttachForm.safeParse({
    waybillId: String(formData.get('waybillId') ?? ''),
    storageKey: String(formData.get('storageKey') ?? ''),
    filename: String(formData.get('filename') ?? ''),
    contentType: String(formData.get('contentType') ?? 'application/octet-stream'),
    byteSize: String(formData.get('byteSize') ?? '0'),
    kind: String(formData.get('kind') ?? 'other'),
    caption: String(formData.get('caption') ?? '').trim() || undefined,
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? 'invalid input' };
  }
  const data = parsed.data;

  const wb = await loadWaybill(data.waybillId);
  if (!wb) return { ok: false, error: 'waybill not found' };

  const actor = await loadActor();
  if (!actor) return { ok: false, error: 'unauthorized' };
  if (!canAttachAtStage(actor, wb)) {
    return { ok: false, error: 'cannot attach at this stage' };
  }

  if (!allowedKindsFor(wb.current_stage).includes(data.kind as WaybillAttachmentKind)) {
    return { ok: false, error: `kind '${data.kind}' not allowed at stage '${wb.current_stage}'` };
  }

  await recordAttachment({
    waybillId: wb.id,
    stageKey: wb.current_stage,
    kind: data.kind as WaybillAttachmentKind,
    storageKey: data.storageKey,
    filename: data.filename,
    contentType: data.contentType,
    byteSize: data.byteSize,
    actorId: actor.id,
    actorRole: actor.role_name ?? 'officer',
    caption: data.caption ?? null,
  });

  revalidatePath(`/waybill/${wb.id}`);
  return { ok: true };
}

const RemoveAttachForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  attachmentId: z.coerce.number().int().positive(),
});

export async function removeWaybillAttachmentAction(formData: FormData): Promise<void> {
  const parsed = RemoveAttachForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    attachmentId: String(formData.get('attachmentId') ?? '0'),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');

  const actor = await actorForWaybill();
  if (!canRemoveAttachment(actor)) {
    throw new Error('cannot remove attachment');
  }

  const att = await getAttachment(parsed.attachmentId);
  if (!att || att.waybill_id !== parsed.waybillId) {
    throw new Error('Attachment not found on this waybill');
  }

  await withTransaction(async (q) => {
    await q(
      `DELETE FROM waybill_attachments WHERE id = $1`,
      [parsed.attachmentId],
    );
    await recordEvent({
      waybillId: parsed.waybillId,
      kind: 'advanced',
      stageFrom: null,
      stageTo: null,
      actorId: actor.id,
      actorRole: actor.role_name ?? 'officer',
      payload: {
        decision: 'attachment_removed',
        attachment_id: parsed.attachmentId,
        filename: att.filename,
      },
      client: q as never,
    });
  });

  revalidatePath(`/waybill/${parsed.waybillId}`);
  redirect(`/waybill/${parsed.waybillId}`);
}

const SubscribeForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  stageKey: z.string().min(1).max(64),
});

export interface SubscribeActionResult {
  ok: boolean;
  error?: string;
}

export async function subscribeWaybillAction(formData: FormData): Promise<SubscribeActionResult> {
  const parsed = SubscribeForm.safeParse({
    waybillId: String(formData.get('waybillId') ?? ''),
    stageKey: String(formData.get('stageKey') ?? ''),
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? 'invalid input' };
  }

  const cookieValue = (await cookies()).get('erp_session')?.value ?? null;
  void cookieValue;
  const actor = await loadActor();
  if (!actor) return { ok: false, error: 'unauthenticated' };

  const wb = await loadWaybill(parsed.data.waybillId);
  if (!wb) return { ok: false, error: 'not found' };

  const domain = domainOf(wb);
  const pip = pipsForDomain(domain).find((p) => p.key === parsed.data.stageKey);
  if (!pip) return { ok: false, error: 'invalid stage' };

  const approvers = await loadApproversByStage(parsed.data.waybillId);
  const list = approvers[parsed.data.stageKey] ?? [];
  if (!list.some((a) => a.user_id === actor.id)) {
    return { ok: false, error: 'only listed approvers can subscribe' };
  }

  await addWatcher({
    waybillId: parsed.data.waybillId,
    stageKey: parsed.data.stageKey,
    userId: actor.id,
  });
  revalidatePath(`/waybill/${parsed.data.waybillId}`);
  return { ok: true };
}

export async function unsubscribeWaybillAction(formData: FormData): Promise<SubscribeActionResult> {
  const parsed = SubscribeForm.safeParse({
    waybillId: String(formData.get('waybillId') ?? ''),
    stageKey: String(formData.get('stageKey') ?? ''),
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? 'invalid input' };
  }

  const actor = await loadActor();
  if (!actor) return { ok: false, error: 'unauthenticated' };

  await removeWatcher({
    waybillId: parsed.data.waybillId,
    stageKey: parsed.data.stageKey,
    userId: actor.id,
  });
  revalidatePath(`/waybill/${parsed.data.waybillId}`);
  return { ok: true };
}

const RecomputeDraftGlForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
});

export async function recomputeExpenseDraftGlAction(formData: FormData): Promise<void> {
  const parsed = RecomputeDraftGlForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'expense') {
    throw new Error(`recompute-draft-gl only for expense origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canSaveProcurementAccrual(actor)) {
    throw new Error('cannot recompute expense draft GL');
  }

  const expRes = await _query<{ vendor_name: string | null }>(
    `SELECT vendor_name FROM expenses WHERE id = $1`,
    [wb.origin_id],
  );
  if (expRes.rows.length === 0) throw new Error('Expense not found');

  await upsertDraftJournal({
    expenseId: wb.origin_id,
    vendorName: expRes.rows[0].vendor_name ?? '',
  });
  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const SaveProcurementAccrualForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
});

export async function saveProcurementAccrualAction(formData: FormData): Promise<void> {
  const parsed = SaveProcurementAccrualForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'pr' && wb.origin !== 'po') {
    throw new Error(`accrual only for procurement origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canSaveProcurementAccrual(actor)) {
    throw new Error('cannot save procurement accrual');
  }

  let vendorName = '';
  if (wb.origin === 'pr') {
    const r = await _query<{ vendor_name: string | null }>(
      `SELECT vendor_name FROM purchase_requisitions WHERE id = $1`,
      [wb.origin_id],
    );
    vendorName = r.rows[0]?.vendor_name ?? '';
  } else {
    const r = await _query<{ vendor_name: string | null }>(
      `SELECT vendor_name FROM purchase_orders WHERE id = $1`,
      [wb.origin_id],
    );
    vendorName = r.rows[0]?.vendor_name ?? '';
  }

  await upsertProcurementDraftAccrual({
    origin: wb.origin,
    originId: wb.origin_id,
    vendorName,
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const PostProcurementAccrualForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  journalId: z.coerce.number().int().positive(),
});

export async function postProcurementAccrualAction(formData: FormData): Promise<void> {
  const parsed = PostProcurementAccrualForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    journalId: String(formData.get('journalId') ?? '0'),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'pr' && wb.origin !== 'po') {
    throw new Error(`accrual only for procurement origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canPostGlAccrual(actor, wb)) {
    throw new Error('cannot post GL accrual at this stage');
  }

  const fin = await finalizeProcurementDraft({
    journalId: parsed.journalId,
    actorId: actor.id,
  });
  if (!fin) throw new Error('draft journal not found');

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl-accrual',
    stageFrom: 'accounting_authorization',
    stageTo: 'accounting_authorization',
    actorId: actor.id,
    actorRole: actor.role_name,
    payload: { journalId: fin.journalId, step: 'accrual' },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const PostProcurementSettlementForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  journalId: z.coerce.number().int().positive(),
});

export async function postProcurementSettlementAction(formData: FormData): Promise<void> {
  const parsed = PostProcurementSettlementForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    journalId: String(formData.get('journalId') ?? '0'),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'pr' && wb.origin !== 'po') {
    throw new Error(`settlement only for procurement origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canPostGlSettlement(actor, wb)) {
    throw new Error('cannot post GL settlement at this stage');
  }

  const fin = await finalizeProcurementDraft({
    journalId: parsed.journalId,
    actorId: actor.id,
  });
  if (!fin) throw new Error('draft journal not found');

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl-settlement',
    stageFrom: 'disbursed',
    stageTo: 'disbursed',
    actorId: actor.id,
    actorRole: actor.role_name,
    payload: { journalId: fin.journalId, step: 'settlement' },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const ConfirmProcurementGlForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  step: z.enum(['accrual', 'settlement']),
});

export async function confirmProcurementGlAction(formData: FormData): Promise<void> {
  const parsed = ConfirmProcurementGlForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    step: String(formData.get('step') ?? ''),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'pr' && wb.origin !== 'po') {
    throw new Error(`confirm-gl only for procurement origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canConfirmGl(actor, wb)) {
    throw new Error('cannot confirm GL at this stage');
  }

  const kind = parsed.step === 'accrual' ? 'gl-confirmed-accrual' : 'gl-confirmed-settlement';

  const exists = await _query<{ exists: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM waybill_events
        WHERE waybill_id = $1 AND kind = $2
     ) AS exists`,
    [wb.id, kind === 'gl-confirmed-accrual' ? 'posted-to-gl-accrual' : 'posted-to-gl-settlement'],
  );
  if (!exists.rows[0]?.exists) {
    throw new Error(`No posted-to-gl-${parsed.step} event on this waybill yet`);
  }

  const already = await _query<{ exists: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM waybill_events
        WHERE waybill_id = $1 AND kind = $2
     ) AS exists`,
    [wb.id, kind],
  );
  if (already.rows[0]?.exists) {
    throw new Error(`GL ${parsed.step} already confirmed`);
  }

  await recordEvent({
    waybillId: wb.id,
    kind,
    stageFrom: wb.current_stage,
    stageTo: wb.current_stage,
    actorId: actor.id,
    actorRole: actor.role_name,
    payload: { step: parsed.step },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const PostSalesGlForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  journalId: z.coerce.number().int().positive(),
});

async function postSalesGlStep(args: {
  formData: FormData;
  expectedOrigin: 'so';
  stage: 'so_invoiced' | 'so_paid';
  postedKind: 'posted-to-gl-sales-vat' | 'posted-to-gl-sales-accrual' | 'posted-to-gl-sales-settlement';
  stepLabel: 'vat' | 'accrual' | 'settlement';
}): Promise<void> {
  const parsed = PostSalesGlForm.parse({
    waybillId: String(args.formData.get('waybillId') ?? ''),
    journalId: String(args.formData.get('journalId') ?? '0'),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== args.expectedOrigin) {
    throw new Error(`sales GL only for sales origin (got ${wb.origin})`);
  }
  if (wb.current_stage !== args.stage) {
    throw new Error(
      `sales GL ${args.stepLabel} only at ${args.stage} (current: ${wb.current_stage})`,
    );
  }

  const actor = await actorForWaybill();
  if (!canPostSalesGlStep(actor, wb, args.stage)) {
    throw new Error(`cannot post sales GL ${args.stepLabel} at this stage`);
  }

  const fin = await finalizeSalesDraft({
    journalId: parsed.journalId,
    actorId: actor.id,
  });
  if (!fin) throw new Error('draft journal not found');

  await recordEvent({
    waybillId: wb.id,
    kind: args.postedKind,
    stageFrom: args.stage,
    stageTo: args.stage,
    actorId: actor.id,
    actorRole: actor.role_name,
    payload: { journalId: fin.journalId, step: args.stepLabel },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

export async function postSalesGlVatAction(formData: FormData): Promise<void> {
  await postSalesGlStep({
    formData,
    expectedOrigin: 'so',
    stage: 'so_invoiced',
    postedKind: 'posted-to-gl-sales-vat',
    stepLabel: 'vat',
  });
}

export async function postSalesGlAccrualAction(formData: FormData): Promise<void> {
  await postSalesGlStep({
    formData,
    expectedOrigin: 'so',
    stage: 'so_invoiced',
    postedKind: 'posted-to-gl-sales-accrual',
    stepLabel: 'accrual',
  });
}

export async function postSalesGlSettlementAction(formData: FormData): Promise<void> {
  await postSalesGlStep({
    formData,
    expectedOrigin: 'so',
    stage: 'so_paid',
    postedKind: 'posted-to-gl-sales-settlement',
    stepLabel: 'settlement',
  });
}

const ConfirmSalesGlForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  step: z.enum(['vat', 'accrual', 'settlement']),
});

export async function confirmSalesGlAction(formData: FormData): Promise<void> {
  const parsed = ConfirmSalesGlForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    step: String(formData.get('step') ?? ''),
  });
  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'so') {
    throw new Error(`confirm-sales-gl only for sales origin (got ${wb.origin})`);
  }

  const actor = await actorForWaybill();
  if (!canConfirmSalesGl(actor, wb)) {
    throw new Error('cannot confirm sales GL at this stage');
  }

  const kind =
    parsed.step === 'vat'
      ? 'gl-confirmed-sales-vat'
      : parsed.step === 'accrual'
        ? 'gl-confirmed-sales-accrual'
        : 'gl-confirmed-sales-settlement';

  const postedKind =
    parsed.step === 'vat'
      ? 'posted-to-gl-sales-vat'
      : parsed.step === 'accrual'
        ? 'posted-to-gl-sales-accrual'
        : 'posted-to-gl-sales-settlement';

  const postedExists = await _query<{ exists: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM waybill_events
        WHERE waybill_id = $1 AND kind = $2
     ) AS exists`,
    [wb.id, postedKind],
  );
  if (!postedExists.rows[0]?.exists) {
    throw new Error(`No ${postedKind} event on this waybill yet`);
  }

  const already = await _query<{ exists: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM waybill_events
        WHERE waybill_id = $1 AND kind = $2
     ) AS exists`,
    [wb.id, kind],
  );
  if (already.rows[0]?.exists) {
    throw new Error(`GL ${parsed.step} already confirmed`);
  }

  await recordEvent({
    waybillId: wb.id,
    kind,
    stageFrom: wb.current_stage,
    stageTo: wb.current_stage,
    actorId: actor.id,
    actorRole: actor.role_name,
    payload: { step: parsed.step },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}
