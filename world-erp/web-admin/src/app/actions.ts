'use server';

import { revalidatePath } from 'next/cache';
import { query } from '@/lib/db';
import { requireActionFor } from '@/lib/server/requireActionFor';
import { loadActor } from '@/lib/server/guard';
import { hasPermission, PERM, STAGE_TO_ROLE } from '@erp-lib/perm/server';
import type { StageName, ActorCtx, ResolverCtx } from '@erp-lib/perm/server';
import { resolveApprovalChain, canActOnStage, getApprovedStages } from '@erp-lib/perm/server';
import { postExpenseToGL } from '@/lib/finance/postExpenseToGL';
import { recordTransition } from '@erp-lib/approval/recordTransition';
import { appendWaybillEvent } from '@erp-lib/waybill/append';
import { recordAttachment } from '@erp-lib/waybill/attachments';
import { recordOverride } from '@erp-lib/approval/recordOverride';
import { remove as removeFromStorage } from '@erp-lib/slips/storage';

async function requireActorOrNull() {
  return loadActor();
}
import { aiInvoke } from '@/lib/ai/router';
import { publish as publishEvent } from '@/lib/events';

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
    await requireActionFor(actorId, 'review_expense', { perm: 'finance:expense:review' });
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
      await requireActionFor(actorId, 'settle_payment', { perm: 'finance:expense:settle' });
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
    createdTo?: string;
    transactionDate?: string;
    paymentMethod?: string;
    bookBankSlipId?: number;
    bookBankFields?: {
      bankName?: string;
      bankBranch?: string;
      accountNumber?: string;
      accountName?: string;
    };
  };
}) {
  try {
    await requireActionFor(args.actorId, 'submit_expense', { perm: 'finance:expense:create' });

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
    await requireActionFor(args.actorId, 'ceo_override', { perm: 'finance:expense:override' });
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
    await requireActionFor(args.requesterId, 'submit_pr', { perm: 'finance:pr:create' });

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
    const { actor: actorSession } = await requireActionFor(args.actorId, 'approve_pr', { perm: 'finance:pr:approve:all' });
    const actorPerms = new Set(actorSession.permissions);
    const prRes = await query(
      `SELECT pr.*, dg.display_name AS dept_name, dg.id AS dept_group_id, dg.id AS dept_group_code
         FROM purchase_requisitions pr
         LEFT JOIN perm.roles dg ON dg.id = pr.dept_group_id AND dg.kind = 'department' AND dg.kind = 'department'
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
    await requireActionFor(args.actorId, 'approve_pr', { perm: 'finance:pr:create' });

    const prRes = await query(
      `SELECT pr.*, dg.display_name AS dept_name, dg.id AS dept_group_id, dg.id AS dept_group_code
         FROM purchase_requisitions pr
         LEFT JOIN perm.roles dg ON dg.id = pr.dept_group_id AND dg.kind = 'department' AND dg.kind = 'department'
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
    await requireActionFor(args.actorId, 'approve_po', { perm: 'finance:po:approve:all' });

    const poRes = await query(
      `SELECT po.*, dg.display_name AS dept_name,
              dg.id AS dept_group_id, dg.id AS dept_group_code, pr.is_recurring
       FROM purchase_orders po
       JOIN purchase_requisitions pr ON po.pr_id = pr.id
       LEFT JOIN perm.roles dg ON dg.id = pr.dept_group_id AND dg.kind = 'department' AND dg.kind = 'department'
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
    await requireActionFor(args.actorId, 'attach_po_payslip', { perm: 'finance:po:attach_payslip' });

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
    await requireActionFor(args.actorId, 'settle_expense', { perm: 'finance:expense:settle' });

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
    await requireActionFor(args.actorId, 'submit_expense', { perm: 'finance:expense:create' });

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
