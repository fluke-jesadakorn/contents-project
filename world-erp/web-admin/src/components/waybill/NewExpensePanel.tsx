'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
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
import { StepCard, StepBadge, fmtTime } from '@/components/StepCard';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';
import { Bilingual } from '@/components/i18n/Bilingual';

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

type StepKey = 'upload' | 'review';

export function NewExpensePanel({ currentUserId, initialModels, initialDraft }: Props) {
  const locale = useSecondaryLocale();
  const [open, setOpen] = useState(true);
  const [payment, setPayment] = useState<'cash' | 'credit_card' | 'transfer'>('cash');
  const [bookBankSlipId, setBookBankSlipId] = useState<number | null>(null);
  const [bookBankFields, setBookBankFields] = useState<BookBankFields>(EMPTY_BANK);
  const [submitState, setSubmitState] = useState<SubmitState | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [draftWaybillId, setDraftWaybillId] = useState<string | null>(initialDraft?.waybillId ?? null);
  const [draftExpenseId, setDraftExpenseId] = useState<number | null>(initialDraft?.expenseId ?? null);
  const [lastSavedAt, setLastSavedAt] = useState<string | null>(initialDraft?.savedAt ?? null);
  const [autosavePending, setAutosavePending] = useState(false);
  const [discarding, setDiscarding] = useState(false);
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

  const steps: Array<{ key: StepKey; n: number; icon: string; title: string; titleTh: string; done: boolean; active: boolean }> = [
    {
      key: 'upload',
      n: 1,
      icon: '📤',
      title: 'Upload receipt & book bank',
      titleTh: 'อัพโหลดใบเสร็จและสมุดบัญชี',
      done: receiptReady && (needsBookBank ? bookBankReady : true),
      active: !receiptReady || (needsBookBank && !bookBankReady),
    },
    {
      key: 'review',
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
      if (!waybillId || !open) return;
      const fd = new FormData();
      fd.set('waybillId', waybillId);
      if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') {
        navigator.sendBeacon('/api/discard-draft', fd);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
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

  const headerLabel = useMemo(() => {
    if (!draftWaybillId) return 'New expense claim · เบิกค่าใช้จ่ายใหม่';
    return `Draft · ร่าง · ${draftWaybillId}`;
  }, [draftWaybillId]);

  return (
    <section
      className="relative mb-8 overflow-hidden rounded-3xl border border-indigo-500/25 bg-gradient-to-br from-indigo-950/55 via-slate-900/55 to-cyan-950/40 shadow-2xl"
      aria-label="New expense claim"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 -right-24 w-72 h-72 bg-indigo-500/20 rounded-full blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-32 -left-24 w-72 h-72 bg-cyan-500/15 rounded-full blur-3xl"
      />

      <header className="relative flex items-start gap-4 p-5 sm:p-6 border-b border-slate-800/70">
        <div className="shrink-0 w-12 h-12 sm:w-14 sm:h-14 rounded-2xl bg-gradient-to-br from-indigo-500 via-indigo-500 to-cyan-500 flex items-center justify-center text-2xl sm:text-3xl shadow-lg shadow-indigo-500/30">
          🧾
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <h2 className="text-lg sm:text-xl font-bold text-white leading-tight">
              {headerLabel}
            </h2>
            <span className="hidden sm:inline px-2 py-0.5 rounded-full text-[10px] font-mono uppercase tracking-wider bg-indigo-500/20 text-indigo-200 border border-indigo-500/30">
              <Bilingual
                en={draftWaybillId ? 'Draft' : 'Not started'}
                th={draftWaybillId ? 'ร่าง' : 'ยังไม่เริ่ม'}
                locale={locale}
              />
            </span>
            <span className="text-[12px] text-slate-400 font-mono">
              <Bilingual en="New expense claim" th="เบิกค่าใช้จ่ายใหม่" locale={locale} />
            </span>
            {draftWaybillId && (
              <span
                className="text-[11px] font-mono text-slate-500"
                data-testid="autosave-status"
              >
                {autosavePending
                  ? '· saving… · กำลังบันทึก…'
                  : lastSavedAt
                  ? `· saved ${fmtTime(lastSavedAt)} · บันทึกเมื่อ ${fmtTime(lastSavedAt)}`
                  : '· unsaved · ยังไม่บันทึก'}
              </span>
            )}
          </div>
          <p className="mt-1 text-[12px] sm:text-[13px] text-slate-400 leading-relaxed">
            <Bilingual
              en="Upload a receipt → AI reads the slip → pick a payment method → submit for approval. About 1–2 minutes."
              th="อัพโหลดใบเสร็จ → AI อ่านสลิป → เลือกวิธีชำระ → ส่งเพื่ออนุมัติ ใช้เวลาประมาณ 1–2 นาที"
              locale={locale}
            />
          </p>
          <div className="mt-3 flex items-center gap-3">
            <div className="flex-1 h-1.5 rounded-full bg-slate-800/80 overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-indigo-500 to-emerald-500 transition-[width] duration-500 ease-out"
                style={{ width: `${(completedCount / steps.length) * 100}%` }}
                aria-hidden
              />
            </div>
            <span className="text-[11px] font-mono text-slate-400 tabular-nums">
              {completedCount}/{steps.length}
            </span>
          </div>
        </div>
        <div className="flex flex-col gap-2 items-end">
          {draftWaybillId && (
            <button
              type="button"
              onClick={handleDiscard}
              disabled={discarding}
              data-testid="panel-discard-draft"
              className="rounded-lg border border-rose-500/40 bg-rose-950/30 hover:bg-rose-950/50 hover:border-rose-500/60 px-3 py-1.5 text-[11px] font-mono text-rose-200 transition-colors disabled:opacity-50"
            >
              {discarding
                ? 'Discarding… · กำลังลบ…'
                : '🗑 Discard draft · 🗑 ลบร่าง'}
            </button>
          )}
          <button
            type="button"
            onClick={() => setOpen((o) => !o)}
            aria-expanded={open}
            aria-controls="new-expense-panel-body"
            className="shrink-0 inline-flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-900/60 hover:bg-slate-800/80 hover:border-slate-600 px-3 py-1.5 text-[11px] font-mono text-slate-300 transition-colors"
          >
            <span aria-hidden>{open ? '▾' : '▸'}</span>
            {open ? 'Hide · ซ่อน' : 'Open · เปิด'}
          </button>
        </div>
      </header>

      {open && (
        <div id="new-expense-panel-body" className="relative p-5 sm:p-6 space-y-5">
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
                    ? 'border-emerald-500/30 bg-emerald-500/5'
                    : s.active
                    ? 'border-indigo-500/40 bg-indigo-500/5'
                    : 'border-slate-800 bg-slate-950/40',
                ].join(' ')}
              >
                <StepBadge n={s.n} done={s.done} active={s.active} />
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span aria-hidden className="text-sm">
                      {s.icon}
                    </span>
                    <p className="text-[12px] font-bold text-white truncate">
                      {s.title}
                    </p>
                  </div>
                  <p className="text-[10px] font-mono text-slate-500 truncate">
                    {s.titleTh}
                  </p>
                </div>
              </li>
            ))}
          </ol>

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
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-200 border border-indigo-500/30">
                    {receiptReady
                      ? '✓ OCR done · ✓ OCR เสร็จ'
                      : 'OCR in progress… · OCR กำลังทำงาน…'}
                  </span>
              ) : null
            }
          >
            <div className="space-y-6">
              <div>
                <h4 className="mb-2 flex items-center gap-2 text-xs font-bold text-slate-300 font-mono">
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
                  <h4 className="mb-2 flex items-center gap-2 text-xs font-bold text-slate-300 font-mono">
                    <span>🏦</span>
                    Book bank · สมุดบัญชี
                    {bookBankSlipId != null && (
                      <span className="px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-200 border border-emerald-500/30 text-[10px] font-mono">
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

          <StepCard
            n={2}
            icon="🚀"
            title="Review and submit"
            titleTh="ตรวจสอบและส่งอนุมัติ"
            hint={
              submitState?.confirming
                ? <Bilingual en="Submitting your expense…" th="กำลังส่งค่าใช้จ่าย…" locale={locale} />
                : !receiptReady
                ? <Bilingual
                    en="Receipt not ready yet. Fill vendor + date; subtotal + VAT must equal total."
                    th="ใบเสร็จยังไม่พร้อม กรอกชื่อร้าน + วันที่; ยอดก่อน VAT + VAT ต้องเท่ากับยอดรวม"
                    locale={locale}
                  />
                : needsBookBank && !bookBankReady
                ? <Bilingual
                    en="Transfer expenses need a book bank slip with bank name, account number, and account name."
                    th="รายจ่ายโอนต้องมีสลิปสมุดบัญชีพร้อมชื่อธนาคาร เลขบัญชี และชื่อบัญชี"
                    locale={locale}
                  />
                : canSubmitAll
                ? draftWaybillId
                  ? <Bilingual
                      en={`Everything looks good. Submit draft ${draftWaybillId} for approval.`}
                      th={`ทุกอย่างเรียบร้อย ส่งร่าง ${draftWaybillId} เพื่ออนุมัติ`}
                      locale={locale}
                    />
                  : <Bilingual
                      en="Everything looks good. Save and send it to your approver."
                      th="ทุกอย่างเรียบร้อย บันทึกและส่งให้ผู้อนุมัติ"
                      locale={locale}
                    />
                : <Bilingual
                    en="Complete the steps above to enable submit."
                    th="ทำขั้นตอนด้านบนให้ครบเพื่อเปิดให้ส่ง"
                    locale={locale}
                  />
            }
            done={false}
            active={canSubmitAll}
            tone={canSubmitAll ? 'emerald' : 'amber'}
            badge={
              canSubmitAll ? (
                <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-200 border border-emerald-500/30">
                  <Bilingual en="Ready" th="พร้อม" locale={locale} />
                </span>
              ) : (
                <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-amber-500/20 text-amber-200 border border-amber-500/30">
                  {needsBookBank
                    ? <Bilingual en="Almost there" th="เกือบแล้ว" locale={locale} />
                    : <Bilingual en="Awaiting receipt" th="รอใบเสร็จ" locale={locale} />}
                </span>
              )
            }
          >
            <button
              type="button"
              onClick={handleSubmitAll}
              disabled={!canSubmitAll}
              data-testid="panel-submit-all"
              className={[
                'w-full py-3.5 rounded-xl text-sm font-bold font-mono inline-flex items-center justify-center gap-2 shadow-lg transition-all duration-200',
                'disabled:opacity-50 disabled:cursor-not-allowed',
                submitState?.confirming
                  ? 'bg-slate-700 text-slate-300'
                  : canSubmitAll
                  ? 'bg-gradient-to-r from-emerald-500 to-emerald-400 hover:from-emerald-400 hover:to-emerald-300 text-slate-950 shadow-emerald-500/30 hover:shadow-emerald-500/50 hover:-translate-y-px'
                  : 'bg-slate-800 text-slate-500',
              ].join(' ')}
            >
              {submitState?.confirming
                ? <Bilingual en="⏳ Saving…" th="⏳ กำลังบันทึก…" locale={locale} />
                : canSubmitAll
                ? <Bilingual en="✓ Submit expense for approval" th="✓ ส่งค่าใช้จ่ายเพื่ออนุมัติ" locale={locale} />
                : <Bilingual en="🔒 Submit (disabled)" th="🔒 ส่ง (ปิดอยู่)" locale={locale} />}
            </button>
            {submitError && (
              <p className="mt-3 rounded-md border border-rose-500/40 bg-rose-950/40 px-3 py-2 text-[11px] text-rose-200">
                ⚠ {submitError}
              </p>
            )}
          </StepCard>
        </div>
      )}
    </section>
  );
}

export default NewExpensePanel;