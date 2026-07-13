'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { cookies } from 'next/headers';
import { z } from 'zod';
import { query as _query, withTransaction } from '@erp-lib/db';
import { recordEvent } from '@erp-lib/waybill/events';
import { recordAttachment, getAttachment } from '@erp-lib/waybill/attachments';
import {
  loadWaybill,
  domainOf,
} from '@/lib/server/waybill';
import { allowedKindsFor, type WaybillAttachmentKind } from '@erp-lib/waybill/kinds';
import { addWatcher, removeWatcher } from '@erp-lib/waybill/watchers';
import { reCallWaybillAction } from '@erp-lib/waybill/recall';
import { resolveNextStage } from '@erp-lib/perm/server';
import {
  finalizeDraftJournal,
  setExpenseJournalEntry,
  upsertDraftJournal,
} from '@erp-lib/finance/postExpenseToGL';
import {
  upsertProcurementDraftAccrual,
  finalizeProcurementDraft,
} from '@erp-lib/finance/postProcurementToGL';
import {
  finalizeSalesDraft,
} from '@erp-lib/finance/postSalesToGL';
import {
  ensureGlForExpense,
  ensurePoForExpense,
} from '@erp-lib/waybill/ensureArtifacts';
import { ensurePoPdf } from '@erp-lib/finance/poPdf';
import { pipsForDomain } from '@erp-lib/waybill/derive';
import {
  POL,
  evalPolicy,
  type PolicyContext,
} from '@erp-lib/policy';
import {
  requirePolicy,
  PolicyError,
} from '@erp-lib/policy/server';
import { buildPolicyContextFromCookieValue } from '@erp-lib/policy/context';

void recordEvent;

async function policyCtxForWaybill(wb: {
  current_stage: string;
  origin: 'expense' | 'pr' | 'po' | 'so';
  submitter_id: number | null;
  total_amount: string | null;
  status: string;
}): Promise<{ ctx: NonNullable<Awaited<ReturnType<typeof buildPolicyContextFromCookieValue>>>; policyCtx: PolicyContext }> {
  const cookieValue = (await cookies()).get('erp_session')?.value ?? null;
  const ctx = await buildPolicyContextFromCookieValue(cookieValue);
  if (!ctx) throw new PolicyError(401, 'unauthenticated');
  return {
    ctx,
    policyCtx: {
      ...ctx,
      resource: {
        current_stage: wb.current_stage,
        origin: wb.origin,
        submitter_id: wb.submitter_id,
        requester_id: wb.submitter_id,
        total_amount_thb: wb.total_amount != null ? Number(wb.total_amount) : null,
        status: wb.status,
      },
    },
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);

  if (parsed.stage && parsed.stage !== wb.current_stage) {
    const rRecall = await evalPolicy(POL.recallWaybill, policyCtx);
    if (rRecall.allow) {
      const r = await reCallWaybillAction({
        waybillId: parsed.waybillId,
        targetStage: parsed.stage,
        actorId: ctx.actor.id,
        actorRole: ctx.actor.roleName ?? '',
        reason: 'cfo override',
      });
      if (!r.ok) throw new Error(r.error);
      revalidatePath(`/waybill/${parsed.waybillId}`);
      redirect(`/waybill/${parsed.waybillId}`);
    }
  }

  await requirePolicy(POL.canActOnWaybill, policyCtx, { surface: 'action', target: 'approveWaybill' });

  const currentStage = wb.current_stage as Parameters<typeof resolveNextStage>[0];
  const domain: 'expense' | 'procurement' | 'sales' =
    wb.origin === 'expense' ? 'expense'
      : wb.origin === 'so' ? 'sales'
        : 'procurement';
  const next = resolveNextStage(currentStage, ctx.actor.roleName ?? '', undefined, domain);

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
      await ensurePoForExpense(q, wb.origin_id);
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
      await ensureGlForExpense(q, wb.origin_id, ctx.actor.id);
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
      actorId: ctx.actor.id,
      actorRole: ctx.actor.roleName ?? 'staff',
      payload: { decision: 'approve' },
      client: q as never,
    });

    if (
      wb.current_stage === 'accounting_verification' &&
      next.stage === 'accounting_authorization' &&
      (wb.origin === 'expense' || wb.origin === 'po' || wb.origin === 'pr')
    ) {
      const actorName = String(ctx.actor.roleName ?? 'system');
      const { rows: actorRows } = await q<{ fullname: string }>(
        `SELECT fullname FROM users WHERE id = $1`,
        [ctx.actor.id],
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.rejectWaybill, policyCtx, { surface: 'action', target: 'rejectWaybill' });

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = 'rejected',
                            rejection_reason = $2,
                            rejection_actor_id = $3,
                            rejected_at = now(),
                            updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, ctx.actor.id],
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
          [wb.origin_id, parsed.reason, ctx.actor.id],
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
        [wb.origin_id, parsed.reason, ctx.actor.id],
      );
    } else if (wb.origin === 'po') {
      await q(
        `UPDATE purchase_orders SET status = 'rejected',
                                  rejection_reason = $2,
                                  rejection_actor_id = $3,
                                  rejected_at = now(),
                                  updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, ctx.actor.id],
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
      actorId: ctx.actor.id,
      actorRole: 'staff',
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canFinalApproveExpense, policyCtx, { surface: 'action', target: 'finalApproveWaybill' });

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
      actorId: ctx.actor.id,
      actorRole: ctx.actor.roleName ?? 'finance',
      payload: { decision: 'final-approve', gl_will_post: true },
      client: q as never,
    });
  });

  let journalId: number;
  const draft = await finalizeDraftJournal({ expenseId: wb.origin_id, actorId: ctx.actor.id });
  if (draft) {
    journalId = draft.journalId;
  } else {
    const upsert = await upsertDraftJournal({
      expenseId: wb.origin_id,
      vendorName: exp.vendor_name,
    });
    journalId = upsert.journalId;
    const fin = await finalizeDraftJournal({ expenseId: wb.origin_id, actorId: ctx.actor.id });
    if (!fin) throw new Error('failed to finalize draft journal');
    journalId = fin.journalId;
  }
  await withTransaction(async (q) => {
    await setExpenseJournalEntry(q, wb.origin_id, journalId, ctx.actor.id);
  });

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl',
    stageFrom: 'final_authorization',
    stageTo: 'awaiting_disbursement',
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName ?? 'finance',
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.rejectWaybill, policyCtx, { surface: 'action', target: 'finalRejectWaybill' });

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = 'rejected',
                            rejection_reason = $2,
                            rejection_actor_id = $3,
                            rejected_at = now(),
                            updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, ctx.actor.id],
      );
    } else if (wb.origin === 'pr') {
      await q(
        `UPDATE purchase_requisitions SET status = 'rejected',
                                        rejection_reason = $2,
                                        rejection_actor_id = $3,
                                        rejected_at = now(),
                                        updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, ctx.actor.id],
      );
    } else if (wb.origin === 'po') {
      await q(
        `UPDATE purchase_orders SET status = 'rejected',
                                  rejection_reason = $2,
                                  rejection_actor_id = $3,
                                  rejected_at = now(),
                                  updated_at = now()
          WHERE id = $1`,
        [wb.origin_id, parsed.reason, ctx.actor.id],
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
      actorId: ctx.actor.id,
      actorRole: ctx.actor.roleName ?? 'finance',
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.resubmitExpense, policyCtx, { surface: 'action', target: 'resubmitWaybill' });

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
      actorId: ctx.actor.id,
      actorRole: 'staff',
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

  let ctx: NonNullable<Awaited<ReturnType<typeof buildPolicyContextFromCookieValue>>>;
  let policyCtx: PolicyContext;
  try {
    const r = await policyCtxForWaybill(wb);
    ctx = r.ctx;
    policyCtx = r.policyCtx;
    await requirePolicy(POL.canSettleExpense, policyCtx, { surface: 'action', target: 'attachPaymentSlip' });
  } catch (err) {
    if (err instanceof PolicyError) return { ok: false, error: err.message };
    throw err;
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
    const submitterId = submitterRes.rows.length > 0 ? wb.submitter_id : ctx.actor.id;
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
      [parsed.data.paymentMethod, ctx.actor.id, parsed.data.expenseId],
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
      actorId: ctx.actor.id,
      actorRole: ctx.actor.roleName ?? 'finance',
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
    actorId: ctx.actor.id,
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
      actorId: ctx.actor.id,
    });
    if (fin) journalId = fin.journalId;
  }

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl',
    stageFrom: 'awaiting_disbursement',
    stageTo: 'disbursed',
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName ?? 'finance',
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canConfirmGl, policyCtx, { surface: 'action', target: 'confirmGlRecorded' });

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
      [ctx.actor.id, parsed.expenseId],
    );
    await recordEvent({
      waybillId: wb.id,
      kind: 'gl-confirmed',
      stageFrom: 'disbursed',
      stageTo: 'disbursed',
      actorId: ctx.actor.id,
      actorRole: ctx.actor.roleName ?? 'finance',
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

  let policyCtx: PolicyContext;
  try {
    const r = await policyCtxForWaybill(wb);
    policyCtx = r.policyCtx;
    await requirePolicy(POL.canAttachAtStage, policyCtx, { surface: 'action', target: 'attachWaybillDocument' });
  } catch (err) {
    if (err instanceof PolicyError) return { ok: false, error: err.message };
    throw err;
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
    actorId: policyCtx.actor.id,
    actorRole: policyCtx.actor.roleName ?? 'officer',
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
    attachmentId: String(formData.get('attachmentId') ?? ''),
  });

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canRemoveAttachment, policyCtx, { surface: 'action', target: 'removeWaybillAttachment' });

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
      actorId: ctx.actor.id,
      actorRole: ctx.actor.roleName ?? 'officer',
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
  const ctx = await buildPolicyContextFromCookieValue(cookieValue);
  if (!ctx) return { ok: false, error: 'unauthenticated' };

  const wb = await loadWaybill(parsed.data.waybillId);
  if (!wb) return { ok: false, error: 'not found' };

  const domain = domainOf(wb);
  const pip = pipsForDomain(domain).find((p) => p.key === parsed.data.stageKey);
  if (!pip) return { ok: false, error: 'invalid stage' };

  const approvers = await loadApproversByStage(parsed.data.waybillId);
  const list = approvers[parsed.data.stageKey] ?? [];
  if (!list.some((a) => a.user_id === ctx.actor.id)) {
    return { ok: false, error: 'only listed approvers can subscribe' };
  }

  await addWatcher({
    waybillId: parsed.data.waybillId,
    stageKey: parsed.data.stageKey,
    userId: ctx.actor.id,
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

  const cookieValue = (await cookies()).get('erp_session')?.value ?? null;
  const ctx = await buildPolicyContextFromCookieValue(cookieValue);
  if (!ctx) return { ok: false, error: 'unauthenticated' };

  await removeWatcher({
    waybillId: parsed.data.waybillId,
    stageKey: parsed.data.stageKey,
    userId: ctx.actor.id,
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

  const { policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canSaveProcurementAccrual, policyCtx, { surface: 'action', target: 'recomputeExpenseDraftGl' });

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

  const { policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canSaveProcurementAccrual, policyCtx, { surface: 'action', target: 'saveProcurementAccrual' });

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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canPostGlAccrual, policyCtx, { surface: 'action', target: 'postProcurementAccrual' });

  const fin = await finalizeProcurementDraft({
    journalId: parsed.journalId,
    actorId: ctx.actor.id,
  });
  if (!fin) throw new Error('draft journal not found');

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl-accrual',
    stageFrom: 'accounting_authorization',
    stageTo: 'accounting_authorization',
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName,
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canPostGlSettlement, policyCtx, { surface: 'action', target: 'postProcurementSettlement' });

  const fin = await finalizeProcurementDraft({
    journalId: parsed.journalId,
    actorId: ctx.actor.id,
  });
  if (!fin) throw new Error('draft journal not found');

  await recordEvent({
    waybillId: wb.id,
    kind: 'posted-to-gl-settlement',
    stageFrom: 'disbursed',
    stageTo: 'disbursed',
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName,
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canConfirmGl, policyCtx, { surface: 'action', target: 'confirmProcurementGl' });

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
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName,
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
  policy: typeof POL.canPostSalesGlVat | typeof POL.canPostSalesGlAccrual | typeof POL.canPostSalesGlSettlement;
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(args.policy, policyCtx, {
    surface: 'action',
    target: `postSalesGl${args.stepLabel}`,
  });

  const fin = await finalizeSalesDraft({
    journalId: parsed.journalId,
    actorId: ctx.actor.id,
  });
  if (!fin) throw new Error('draft journal not found');

  await recordEvent({
    waybillId: wb.id,
    kind: args.postedKind,
    stageFrom: args.stage,
    stageTo: args.stage,
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName,
    payload: { journalId: fin.journalId, step: args.stepLabel },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

export async function postSalesGlVatAction(formData: FormData): Promise<void> {
  await postSalesGlStep({
    formData,
    expectedOrigin: 'so',
    policy: POL.canPostSalesGlVat,
    stage: 'so_invoiced',
    postedKind: 'posted-to-gl-sales-vat',
    stepLabel: 'vat',
  });
}

export async function postSalesGlAccrualAction(formData: FormData): Promise<void> {
  await postSalesGlStep({
    formData,
    expectedOrigin: 'so',
    policy: POL.canPostSalesGlAccrual,
    stage: 'so_invoiced',
    postedKind: 'posted-to-gl-sales-accrual',
    stepLabel: 'accrual',
  });
}

export async function postSalesGlSettlementAction(formData: FormData): Promise<void> {
  await postSalesGlStep({
    formData,
    expectedOrigin: 'so',
    policy: POL.canPostSalesGlSettlement,
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

  const { ctx, policyCtx } = await policyCtxForWaybill(wb);
  await requirePolicy(POL.canConfirmSalesGl, policyCtx, {
    surface: 'action',
    target: `confirmSalesGl${parsed.step}`,
  });

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
    actorId: ctx.actor.id,
    actorRole: ctx.actor.roleName,
    payload: { step: parsed.step },
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}
