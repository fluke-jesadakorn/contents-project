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
import { appendWaybillEvent } from '@erp-lib/waybill/append';
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
