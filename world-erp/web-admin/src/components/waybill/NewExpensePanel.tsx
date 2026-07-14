'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  SlipUpload,
  type BookBankFields,
  type SlipDraftFields,
  type SlipKind,
  type SlipUploadHandle,
  type SubmitState,
} from '@/components/SlipUpload';
import type { VisionModel } from '@/lib/ai/loadVisionModels';
import {
  startExpenseDraft,
  saveDraftExpense,
  discardDraftExpense,
} from '@/app/actions';
import { StepCard, StepBadge } from '@/components/StepCard';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';
import { Bilingual } from '@/components/i18n/Bilingual';
import { NewWaybillPanel } from './NewWaybillPanel';

interface Props {
  currentUserId: number;
  initialModels: VisionModel[];
  initialDraft?: {
    waybillId: string;
    expenseId: number;
    savedAt?: string | null;
    parsed?: SlipDraftFields | null;
  } | null;
}

const EMPTY_BANK: BookBankFields = {
  bankName: '',
  bankBranch: '',
  accountNumber: '',
  accountName: '',
};

const AUTOSAVE_DEBOUNCE_MS = 10_000;

export function NewExpensePanel({ currentUserId, initialModels, initialDraft }: Props) {
  const locale = useSecondaryLocale();
  const [payment, setPayment] = useState<'cash' | 'credit_card' | 'transfer'>('cash');
  const [bookBankSlipId, setBookBankSlipId] = useState<number | null>(null);
  const [bookBankFields, setBookBankFields] = useState<BookBankFields>(EMPTY_BANK);
  const [submitState, setSubmitState] = useState<SubmitState | null>(null);
  const [draftWaybillId, setDraftWaybillId] = useState<string | null>(initialDraft?.waybillId ?? null);
  const [draftExpenseId, setDraftExpenseId] = useState<number | null>(initialDraft?.expenseId ?? null);
  const [lastSavedAt, setLastSavedAt] = useState<string | null>(initialDraft?.savedAt ?? null);
  const [autosavePending, setAutosavePending] = useState(false);
  const [discarding, setDiscarding] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const receiptRef = useRef<SlipUploadHandle>(null);
  const router = useRouter();
  const lastParsedRef = useRef<SlipDraftFields | null>(initialDraft?.parsed ?? null);

  const draftRef = useRef({ waybillId: draftWaybillId, expenseId: draftExpenseId });
  draftRef.current = { waybillId: draftWaybillId, expenseId: draftExpenseId };

  const parsed = submitState?.parsed ?? null;
  const receiptSlipId = submitState?.slipId ?? null;
  const receiptReady = submitState?.canConfirm === true;
  const receiptHasFile = submitState?.pendingFile === true;
  const needsBookBank = payment === 'transfer';
  const bookBankReady: boolean =
    !needsBookBank ||
    (bookBankSlipId != null &&
      bookBankFields.bankName.length > 0 &&
      bookBankFields.accountNumber.length > 0 &&
      bookBankFields.accountName.length > 0);
  const canSubmitAll = receiptReady && bookBankReady && !submitState?.confirming;

  const steps = [
    {
      key: 'upload' as const,
      n: 1,
      icon: '📤',
      title: 'Upload receipt & book bank',
      titleTh: 'อัพโหลดใบเสร็จและสมุดบัญชี',
      done: receiptReady && (needsBookBank ? bookBankReady : true),
      active: !receiptReady || (needsBookBank && !bookBankReady),
    },
    {
      key: 'review' as const,
      n: 2,
      icon: '🚀',
      title: 'Review & submit',
      titleTh: 'ตรวจสอบและส่ง',
      done: canSubmitAll,
      active: canSubmitAll,
    },
  ];

  const completedCount = steps.filter((s) => s.done).length;

  useEffect(() => {
    if (!parsed) {
      lastParsedRef.current = null;
      return;
    }
    const prev = lastParsedRef.current;
    const changed =
      !prev ||
      prev.vendorName !== parsed.vendorName ||
      prev.vendorAddress !== parsed.vendorAddress ||
      prev.createdTo !== parsed.createdTo ||
      prev.createdToAddress !== parsed.createdToAddress ||
      prev.transactionDate !== parsed.transactionDate ||
      prev.paymentMethod !== parsed.paymentMethod ||
      prev.subtotal !== parsed.subtotal ||
      prev.vatAmount !== parsed.vatAmount ||
      prev.totalAmount !== parsed.totalAmount;
    if (!changed) return;
    lastParsedRef.current = parsed;

    if (!draftRef.current.waybillId) return;

    const timer = setTimeout(async () => {
      setAutosavePending(true);
      const r = await saveDraftExpense({
        waybillId: draftRef.current.waybillId!,
        actorId: currentUserId,
        payload: {
          vendorName: parsed.vendorName,
          vendorAddress: parsed.vendorAddress,
          createdTo: parsed.createdTo,
          createdToAddress: parsed.createdToAddress,
          transactionDate: parsed.transactionDate,
          subtotal: parsed.subtotal,
          vatAmount: parsed.vatAmount,
          totalAmount: parsed.totalAmount,
          paymentMethod: parsed.paymentMethod,
        },
      });
      setAutosavePending(false);
      if (r.ok && r.savedAt) setLastSavedAt(r.savedAt);
    }, AUTOSAVE_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [parsed, currentUserId]);

  useEffect(() => {
    return () => {
      const waybillId = draftRef.current.waybillId;
      if (!waybillId) return;
      const fd = new FormData();
      fd.set('waybillId', waybillId);
      if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') {
        navigator.sendBeacon('/api/discard-draft', fd);
      }
    };
  }, []);

  useEffect(() => {
    if (!receiptSlipId || draftWaybillId) return;
    let cancelled = false;
    (async () => {
      const r = await startExpenseDraft(currentUserId);
      if (cancelled || !r || !r.waybillId) return;
      setDraftWaybillId(r.waybillId);
      setDraftExpenseId(r.expenseId ?? null);
      setLastSavedAt(new Date().toISOString());
    })();
    return () => {
      cancelled = true;
    };
  }, [receiptSlipId, draftWaybillId, currentUserId]);

  function onBookBankReady(slipId: number, kind: SlipKind) {
    if (kind !== 'book_bank') return;
    setBookBankSlipId(slipId);
  }

  function onBookBankDiscarded(slipId: number, kind: SlipKind) {
    if (kind !== 'book_bank') return;
    if (bookBankSlipId === slipId) {
      setBookBankSlipId(null);
      setBookBankFields(EMPTY_BANK);
    }
  }

  async function handleSubmitAll() {
    setSubmitError(null);
    if (!receiptRef.current) return;
    try {
      await receiptRef.current.submit();
    } catch (e: any) {
      setSubmitError(e?.message ?? 'Submit failed · ส่งไม่สำเร็จ');
    }
  }

  async function handleDiscard() {
    if (!draftWaybillId) return;
    const msg = 'Discard this draft? The waybill ID and any uploaded slips will be removed. · ลบร่างนี้? รหัส Waybill และสลิปที่อัปโหลดจะถูกลบ';
    if (!confirm(msg)) return;
    setDiscarding(true);
    const r = await discardDraftExpense({ waybillId: draftWaybillId, actorId: currentUserId });
    setDiscarding(false);
    if (!r.ok) {
      const errMsg = r.error ?? 'Could not discard draft · ลบร่างไม่สำเร็จ';
      alert(errMsg);
      return;
    }
    setDraftWaybillId(null);
    setDraftExpenseId(null);
    setLastSavedAt(null);
    lastParsedRef.current = null;
    router.refresh();
  }

  const hint = (
    <>
      <Bilingual
        en="Upload a receipt → AI reads the slip → pick a payment method → submit for approval. About 1–2 minutes."
        th="อัพโหลดใบเสร็จ → AI อ่านสลิป → เลือกวิธีชำระ → ส่งเพื่ออนุมัติ ใช้เวลาประมาณ 1–2 นาที"
        locale={locale}
      />
      {draftWaybillId && (
        <span className="ml-2 text-xs font-mono text-mute" data-testid="autosave-status">
          {autosavePending
            ? '· saving… · กำลังบันทึก…'
            : lastSavedAt
              ? `· saved · บันทึกเมื่อ`
              : '· unsaved · ยังไม่บันทึก'}
        </span>
      )}
    </>
  );

  const submitLabel = submitState?.confirming
    ? <Bilingual en="⏳ Saving…" th="⏳ กำลังบันทึก…" locale={locale} />
    : canSubmitAll
      ? <Bilingual en="✓ Submit expense for approval" th="✓ ส่งค่าใช้จ่ายเพื่ออนุมัติ" locale={locale} />
      : <Bilingual en="🔒 Submit (disabled)" th="🔒 ส่ง (ปิดอยู่)" locale={locale} />;

  const discardLabel = discarding
    ? 'Discarding… · กำลังลบ…'
    : '🗑 Discard draft · 🗑 ลบร่าง';

  return (
    <NewWaybillPanel
      domain="expense"
      currentUserId={currentUserId}
      initialDraft={initialDraft ?? null}
      title=""
      titleTh=""
      discardLabel={discardLabel}
      submitLabel={submitLabel}
      readyToSubmit={canSubmitAll}
      submitting={submitState?.confirming ?? false}
      onSubmit={handleSubmitAll}
      onDiscard={handleDiscard}
      hint={hint}
      draftWaybillId={draftWaybillId}
    >
      <ol
        className="grid grid-cols-1 sm:grid-cols-3 gap-2"
        aria-label="Progress steps"
      >
        {steps.map((s) => (
          <li
            key={s.key}
            className={[
              'flex items-center gap-3 rounded-xl border px-3 py-2.5 transition-colors',
              s.done
                ? 'glass-tint-positive border-positive/40'
                : s.active
                ? 'glass-tint-info border-info/40'
                : 'glass-panel border-rule',
            ].join(' ')}
          >
            <StepBadge n={s.n} done={s.done} active={s.active} />
            <div className="min-w-0">
              <div className="flex items-center gap-1.5">
                <span aria-hidden className="text-sm">{s.icon}</span>
                <p className="text-xs font-bold text-white truncate">{s.title}</p>
              </div>
              <p className="text-sm font-mono text-mute truncate">{s.titleTh}</p>
            </div>
          </li>
        ))}
      </ol>

      <div className="mt-3 flex items-center gap-3">
        <div className="glass-panel flex-1 h-1.5 rounded-full overflow-hidden">
          <div
            className="h-full bg-accent transition-[width] duration-500 ease-out"
            style={{ width: `${(completedCount / steps.length) * 100}%` }}
            aria-hidden
          />
        </div>
        <span className="text-sm font-mono text-ink-2 tabular-nums">
          {completedCount}/{steps.length}
        </span>
      </div>

      <StepCard
        n={1}
        icon="📸"
        title="Upload receipt & book bank"
        titleTh="อัพโหลดใบเสร็จและสมุดบัญชี"
        hint="Drop a photo, scan, or PDF of the receipt. For transfer payments, also drop a book bank slip."
        done={receiptReady && (needsBookBank ? bookBankReady : true)}
        active={!receiptReady || (needsBookBank && !bookBankReady)}
        tone="indigo"
        badge={
          receiptHasFile ? (
            <span className="glass-tint-info text-sm font-mono px-2 py-0.5 rounded-full text-info">
              {receiptReady
                ? '✓ OCR done · ✓ OCR เสร็จ'
                : 'OCR in progress… · OCR กำลังทำงาน…'}
            </span>
          ) : null
        }
      >
        <div className="space-y-6">
          <div>
            <h4 className="mb-2 flex items-center gap-2 text-xs font-bold text-ink-2 font-mono">
              <span>📄</span>
              Receipt · ใบเสร็จ
            </h4>
            <SlipUpload
              ref={receiptRef}
              kind="receipt"
              currentUserId={currentUserId}
              initialModels={initialModels}
              bookBankSlipId={needsBookBank ? bookBankSlipId : null}
              bookBankFields={needsBookBank ? bookBankFields : undefined}
              onPaymentChange={setPayment}
              onSubmitStateChange={setSubmitState}
              hideSubmitButton
              draftWaybillId={draftWaybillId}
              onConfirmed={({ expenseId, waybillId }) => {
                const target = waybillId ?? draftWaybillId ?? draftRef.current.waybillId;
                if (target) {
                  router.push(`/waybill/${target}`);
                } else {
                  router.push(`/waybill/by-expense/${expenseId}`);
                }
              }}
            />
          </div>
          {needsBookBank && (
            <div>
              <h4 className="mb-2 flex items-center gap-2 text-xs font-bold text-ink-2 font-mono">
                <span>🏦</span>
                Book bank · สมุดบัญชี
                {bookBankSlipId != null && (
                  <span className="glass-tint-positive px-2 py-0.5 rounded-full text-positive text-sm font-mono">
                    {`SLIP-${bookBankSlipId} attached`}
                  </span>
                )}
              </h4>
              <SlipUpload
                kind="book_bank"
                currentUserId={currentUserId}
                initialModels={initialModels}
                onSlipReady={onBookBankReady}
                onSlipDiscarded={onBookBankDiscarded}
                onBookBankFieldsChange={setBookBankFields}
                hideSubmitButton
              />
            </div>
          )}
        </div>
      </StepCard>

      {submitError && (
        <p className="glass-tint-critical mt-3 rounded-md px-3 py-2 text-sm text-critical">
          ⚠ {submitError}
        </p>
      )}
    </NewWaybillPanel>
  );
}

export default NewExpensePanel;