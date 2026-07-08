'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { query as _query, withTransaction } from '@erp-lib/db';
import { loadActor } from '@/lib/server/guard';
void _query;
import { recordEvent } from '@erp-lib/waybill/events';
import { recordAttachment, getAttachment } from '@erp-lib/waybill/attachments';
import { loadWaybill } from '@/lib/server/waybill';
import {
  canActorAttachAt,
  canActorRemoveAttachment,
  isTerminalStage,
} from '@erp-lib/waybill/permissions';
import { allowedKindsFor, type WaybillAttachmentKind } from '@erp-lib/waybill/kinds';

void recordEvent;

const ApproveForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
});

export async function approveWaybillAction(formData: FormData): Promise<void> {
  const parsed = ApproveForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
  });

  const actor = await loadActor();
  if (!actor) throw new Error('Unauthenticated');

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');

  await withTransaction(async (q) => {
    if (wb.origin === 'expense') {
      await q(
        `UPDATE expenses SET status = 'awaiting_disbursement', updated_at = now()
          WHERE id = $1`,
        [wb.origin_id],
      );
    } else if (wb.origin === 'pr') {
      await q(
        `UPDATE purchase_requisitions SET status = 'awaiting_disbursement', updated_at = now()
          WHERE id = $1`,
        [wb.origin_id],
      );
    } else if (wb.origin === 'po') {
      await q(
        `UPDATE purchase_orders SET status = 'awaiting_disbursement', updated_at = now()
          WHERE id = $1`,
        [wb.origin_id],
      );
    }
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
      stageFrom: wb.current_stage,
      stageTo: 'awaiting_disbursement',
      actorId: actor.id,
      actorRole: 'staff',
      payload: { decision: 'approve' },
      client: q as never,
    });
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

  const actor = await loadActor();
  if (!actor) throw new Error('Unauthenticated');

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');

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
      stageFrom: wb.current_stage,
      stageTo: 'rejected',
      actorId: actor.id,
      actorRole: 'staff',
      payload: { reason: parsed.reason },
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

  const actor = await loadActor();
  if (!actor) throw new Error('Unauthenticated');

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb || wb.status !== 'rejected') throw new Error('Not in rejected state');

  const submitterId = wb.submitter_id;
  if (!submitterId || submitterId !== actor.id) {
    throw new Error('Only original submitter can resubmit');
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
      actorRole: 'staff',
      payload: { origin: wb.origin, origin_id: wb.origin_id },
      client: q as never,
    });
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
}

const SettleForm = z.object({
  waybillId: z.string().regex(/^WB-\d{4}-\d{6}$/),
  paymentMethod: z.enum(['cash', 'credit_card', 'transfer']),
});

export async function settleWaybillAction(formData: FormData): Promise<void> {
  const parsed = SettleForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    paymentMethod: String(formData.get('paymentMethod') ?? 'transfer'),
  });

  const actor = await loadActor();
  if (!actor) throw new Error('Unauthenticated');

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');
  if (wb.origin !== 'expense') {
    throw new Error(`Settle only supported for expense origin (got ${wb.origin})`);
  }
  if (wb.current_stage !== 'awaiting_disbursement') {
    throw new Error(`Expense must be awaiting_disbursement (current: ${wb.current_stage})`);
  }

  const { settleExpenseMock } = await import('@/app/actions');
  const res = await settleExpenseMock({
    expenseId: wb.origin_id,
    actorId: actor.id,
    paymentMethod: parsed.paymentMethod,
  });
  if (!res.success) throw new Error((res as { error?: string }).error ?? 'settle failed');

  await withTransaction(async (q) => {
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
      actorRole: actor.role_name ?? 'staff',
      payload: { paymentMethod: parsed.paymentMethod },
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

export async function attachWaybillDocumentAction(formData: FormData): Promise<void> {
  const parsed = AttachForm.parse({
    waybillId: String(formData.get('waybillId') ?? ''),
    storageKey: String(formData.get('storageKey') ?? ''),
    filename: String(formData.get('filename') ?? ''),
    contentType: String(formData.get('contentType') ?? 'application/octet-stream'),
    byteSize: String(formData.get('byteSize') ?? '0'),
    kind: String(formData.get('kind') ?? 'other'),
    caption: String(formData.get('caption') ?? '').trim() || undefined,
  });

  const actor = await loadActor();
  if (!actor) throw new Error('Unauthenticated');

  const wb = await loadWaybill(parsed.waybillId);
  if (!wb) throw new Error('Waybill not found');

  if (isTerminalStage(wb.current_stage)) {
    throw new Error(`Cannot attach to terminal stage '${wb.current_stage}'`);
  }
  if (!canActorAttachAt(actor.role_name ?? '', wb.current_stage)) {
    throw new Error(
      `Role '${actor.role_name}' cannot attach at stage '${wb.current_stage}'`,
    );
  }
  if (!allowedKindsFor(wb.current_stage).includes(parsed.kind as WaybillAttachmentKind)) {
    throw new Error(`Kind '${parsed.kind}' not allowed at stage '${wb.current_stage}'`);
  }

  await recordAttachment({
    waybillId: wb.id,
    stageKey: wb.current_stage,
    kind: parsed.kind as WaybillAttachmentKind,
    storageKey: parsed.storageKey,
    filename: parsed.filename,
    contentType: parsed.contentType,
    byteSize: parsed.byteSize,
    actorId: actor.id,
    actorRole: actor.role_name ?? 'staff',
    caption: parsed.caption ?? null,
  });

  revalidatePath(`/waybill/${wb.id}`);
  redirect(`/waybill/${wb.id}`);
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

  const actor = await loadActor();
  if (!actor) throw new Error('Unauthenticated');
  if (!canActorRemoveAttachment({ id: actor.id, roleName: actor.role_name ?? '' })) {
    throw new Error('Only admin/CFO/CEO can remove attachments');
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
      actorRole: actor.role_name ?? 'staff',
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
