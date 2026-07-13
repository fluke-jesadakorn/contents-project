'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { StepCard, StepBadge, fmtTime } from '@/components/StepCard';
import { CustomerCombobox, type CustomerComboboxOption } from '@/components/customer/CustomerCombobox';
import { CustomerArHistory, type CustomerArBucket } from '@/components/customer/CustomerArHistory';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';
import { Bilingual } from '@/components/i18n/Bilingual';
import salesDict from '@erp-lib/i18n/sales';

export interface SoItemDraft {
  key: string;
  description: string;
  qty: number;
  unitPrice: number;
  vatPct: number;
}

export interface NewSalesPanelProps {
  currentUserId: number;
  initialDraft?:
    | {
        waybillId: string;
        salesOrderId: number;
        customerId?: number | null;
        customerName?: string | null;
        paymentTerms?: string | null;
        dueDate?: string | null;
        items?: SoItemDraft[] | null;
        arBuckets?: CustomerArBucket[] | null;
        arTotalInvoiced?: number;
        arTotalPaid?: number;
        arCreditLimit?: number;
        savedAt?: string | null;
      }
    | null;
}

const AUTOSAVE_DEBOUNCE_MS = 10_000;

const PAYMENT_TERMS = ['Net 15', 'Net 30', 'Net 45', 'Net 60', 'Cash on delivery', 'Prepaid'];

type StepKey = 'customer' | 'items' | 'terms';

function uid(): string {
  return Math.random().toString(36).slice(2, 10);
}

function round2(n: number): number {
  return Math.round((Number(n) || 0) * 100) / 100;
}

function lineTotals(it: SoItemDraft): { subtotal: number; vat: number; total: number } {
  const subtotal = round2(it.qty * it.unitPrice);
  const vat = round2((subtotal * (it.vatPct || 0)) / 100);
  return { subtotal, vat, total: round2(subtotal + vat) };
}

function summarize(items: SoItemDraft[]): {
  subtotal: number;
  vat: number;
  total: number;
} {
  let subtotal = 0;
  let vat = 0;
  for (const it of items) {
    const t = lineTotals(it);
    subtotal += t.subtotal;
    vat += t.vat;
  }
  subtotal = round2(subtotal);
  vat = round2(vat);
  return { subtotal, vat, total: round2(subtotal + vat) };
}

function defaultDueDate(paymentTerms: string): string {
  const days = paymentTerms.startsWith('Net ')
    ? parseInt(paymentTerms.slice(4), 10) || 30
    : paymentTerms === 'Cash on delivery' || paymentTerms === 'Prepaid'
    ? 0
    : 30;
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

function isDraftShape(x: unknown): x is { waybillId: string } {
  return !!x && typeof x === 'object' && typeof (x as any).waybillId === 'string';
}

function tKey(key: string, locale: 'th' | 'de'): string {
  const en = salesDict.en[key] ?? key;
  if (locale === 'de') return salesDict.de?.[key] ?? en;
  return salesDict.th?.[key] ?? en;
}

export function NewSalesPanel({ currentUserId, initialDraft }: NewSalesPanelProps) {
  void currentUserId;
  const locale = useSecondaryLocale();
  const initialItems = useMemo<SoItemDraft[]>(
    () =>
      initialDraft?.items && initialDraft.items.length > 0
        ? initialDraft.items.map((x) => ({ ...x, key: x.key || uid() }))
        : [{ key: uid(), description: '', qty: 1, unitPrice: 0, vatPct: 7 }],
    [initialDraft],
  );
  const safeInitial = isDraftShape(initialDraft ?? {}) ? initialDraft : null;

  const [open, setOpen] = useState(true);
  const [customer, setCustomer] = useState<CustomerComboboxOption | null>(
    initialDraft?.customerId
      ? {
          id: initialDraft.customerId,
          code: '',
          name: initialDraft.customerName ?? '',
        }
      : null,
  );
  const [items, setItems] = useState<SoItemDraft[]>(initialItems);
  const [paymentTerms, setPaymentTerms] = useState<string>(
    initialDraft?.paymentTerms ?? 'Net 30',
  );
  const [dueDate, setDueDate] = useState<string>(
    initialDraft?.dueDate ?? defaultDueDate(initialDraft?.paymentTerms ?? 'Net 30'),
  );
  const [draftWaybillId, setDraftWaybillId] = useState<string | null>(
    safeInitial?.waybillId ?? null,
  );
  const [lastSavedAt, setLastSavedAt] = useState<string | null>(
    safeInitial?.savedAt ?? null,
  );
  const [autosavePending, setAutosavePending] = useState<boolean>(false);
  const [submitting, setSubmitting] = useState<boolean>(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [arBuckets, setArBuckets] = useState<CustomerArBucket[] | null>(
    initialDraft?.arBuckets ?? null,
  );
  const [arTotalInvoiced, setArTotalInvoiced] = useState<number>(initialDraft?.arTotalInvoiced ?? 0);
  const [arTotalPaid, setArTotalPaid] = useState<number>(initialDraft?.arTotalPaid ?? 0);
  const [arCreditLimit, setArCreditLimit] = useState<number>(initialDraft?.arCreditLimit ?? 0);

  const router = useRouter();
  const draftRef = useRef({ waybillId: draftWaybillId });
  draftRef.current = { waybillId: draftWaybillId };

  const totals = useMemo(() => summarize(items), [items]);

  const customerReady = !!customer;
  const itemsReady =
    items.length > 0 &&
    items.every(
      (it) => it.description.trim().length > 0 && it.qty > 0 && it.unitPrice >= 0,
    );
  const termsReady = paymentTerms.length > 0 && dueDate.length === 10;
  const canSubmitAll = customerReady && itemsReady && termsReady && !submitting;

  const steps: Array<{ key: StepKey; n: number; icon: string; title: string; titleTh: string; done: boolean; active: boolean }> = [
    {
      key: 'customer',
      n: 1,
      icon: '🏢',
      title: 'Pick customer',
      titleTh: 'เลือกลูกค้า',
      done: customerReady,
      active: !customerReady,
    },
    {
      key: 'items',
      n: 2,
      icon: '📦',
      title: 'Line items',
      titleTh: 'รายการสินค้า',
      done: itemsReady,
      active: customerReady && !itemsReady,
    },
    {
      key: 'terms',
      n: 3,
      icon: '📅',
      title: 'Payment terms & due date',
      titleTh: 'เครดิต & กำหนดชำระ',
      done: termsReady,
      active: itemsReady && !termsReady,
    },
  ];
  const completedCount = steps.filter((s) => s.done).length;

  useEffect(() => {
    if (!customer) {
      setArBuckets(null);
      setArTotalInvoiced(0);
      setArTotalPaid(0);
      setArCreditLimit(0);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const r = await fetch(`/api/customers/${customer.id}/ar-history`, {
          credentials: 'include',
        });
        if (!r.ok) return;
        const data = await r.json().catch(() => null);
        if (cancelled) return;
        setArBuckets((data?.buckets ?? null) as CustomerArBucket[] | null);
        setArTotalInvoiced(Number(data?.totalInvoiced ?? data?.total_invoiced ?? 0));
        setArTotalPaid(Number(data?.totalPaid ?? data?.total_paid ?? 0));
        setArCreditLimit(Number(data?.creditLimit ?? data?.credit_limit ?? 0));
      } catch {
        if (cancelled) return;
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [customer]);

  useEffect(() => {
    return () => {
      const waybillId = draftRef.current.waybillId;
      if (!waybillId || !open) return;
      const fd = new FormData();
      fd.set('waybillId', waybillId);
      if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') {
        navigator.sendBeacon('/api/sales/discard-draft', fd);
      }
    };
  }, [open]);

  const seedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (!customerReady || draftWaybillId) return;
    if (seedTimerRef.current) clearTimeout(seedTimerRef.current);
    seedTimerRef.current = setTimeout(async () => {
      if (draftRef.current.waybillId) return;
      try {
        const r = await fetch('/api/sales/start-draft', {
          method: 'POST',
          credentials: 'include',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            customerId: customer?.id ?? null,
            paymentTerms,
            dueDate,
          }),
        });
        const data = await r.json().catch(() => null);
        if (!r.ok || !data?.waybillId) return;
        setDraftWaybillId(data.waybillId);
        setLastSavedAt(new Date().toISOString());
      } catch {
        return;
      }
    }, 1_500);
    return () => {
      if (seedTimerRef.current) clearTimeout(seedTimerRef.current);
    };
  }, [customerReady, customer, paymentTerms, dueDate, draftWaybillId]);

  useEffect(() => {
    if (!draftWaybillId) return;
    const timer = setTimeout(() => {
      if (autosavePending) return;
      void (async () => {
        setAutosavePending(true);
        try {
          const r = await fetch('/api/sales/save-draft', {
            method: 'POST',
            credentials: 'include',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              waybillId: draftWaybillId,
              customerId: customer?.id ?? null,
              paymentTerms,
              dueDate,
              items: items.map((it) => ({
                description: it.description,
                qty: it.qty,
                unitPrice: it.unitPrice,
                vatPct: it.vatPct,
              })),
              totals,
            }),
          });
          const data = await r.json().catch(() => null);
          if (r.ok && data?.savedAt) setLastSavedAt(data.savedAt);
        } finally {
          setAutosavePending(false);
        }
      })();
    }, AUTOSAVE_DEBOUNCE_MS);
    return () => clearTimeout(timer);
    // autosavePending intentionally read inside timer; we don't want it as a dep
    // (it would reset the debounce on every state flip)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draftWaybillId, customer, paymentTerms, dueDate, items, totals]);

  function changeItem(idx: number, patch: Partial<SoItemDraft>) {
    setItems((prev) =>
      prev.map((x, i) => (i === idx ? { ...x, ...patch } : x)),
    );
  }

  function addItem() {
    setItems((prev) => [
      ...prev,
      { key: uid(), description: '', qty: 1, unitPrice: 0, vatPct: 7 },
    ]);
  }

  function removeItem(idx: number) {
    setItems((prev) => prev.filter((_, i) => i !== idx));
  }

  async function handleSubmit() {
    if (!customer) {
      setSubmitError(tKey('sales.panel.pick_customer_first', locale));
      return;
    }
    setSubmitting(true);
    setSubmitError(null);
    try {
      const r = await fetch('/api/sales', {
        method: 'POST',
        credentials: 'include',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          draftWaybillId,
          customerId: customer.id,
          paymentTerms,
          dueDate,
          items: items.map((it) => ({
            description: it.description,
            qty: it.qty,
            unitPrice: it.unitPrice,
            vatPct: it.vatPct,
          })),
          totals,
        }),
      });
      const data = await r.json().catch(() => null);
      if (!r.ok) {
        setSubmitError(data?.error ?? `HTTP ${r.status}`);
        setSubmitting(false);
        return;
      }
      const target = data?.waybillId ?? draftRef.current.waybillId;
      if (target) {
        router.push(`/waybill/${target}`);
      } else {
        router.refresh();
      }
    } catch (e: any) {
      setSubmitError(e?.message ?? tKey('sales.panel.submit_failed', locale));
      setSubmitting(false);
    }
  }

  async function handleDiscard() {
    if (!draftWaybillId) return;
    if (!confirm(tKey('sales.panel.discard_confirm', locale))) return;
    try {
      const fd = new FormData();
      fd.set('waybillId', draftWaybillId);
      const url = '/api/sales/discard-draft';
      if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') {
        navigator.sendBeacon(url, fd);
      } else {
        await fetch(url, { method: 'POST', body: fd, credentials: 'include' });
      }
      setDraftWaybillId(null);
      setLastSavedAt(null);
      router.refresh();
    } catch {
      return;
    }
  }

  const headerLabel = useMemo(() => {
    if (!draftWaybillId) return tKey('sales.panel.new_so', locale);
    return `${tKey('sales.panel.draft_chip', locale)} · ${draftWaybillId}`;
  }, [draftWaybillId, locale]);

  const overCredit =
    arCreditLimit > 0 &&
    arTotalInvoiced - arTotalPaid >= arCreditLimit * 0.8;

  return (
    <section
      className="relative mb-8 overflow-hidden rounded-3xl border border-fuchsia-500/25 bg-gradient-to-br from-fuchsia-950/40 via-slate-900/55 to-cyan-950/40 shadow-2xl"
      aria-label={tKey('sales.panel.new_so', locale)}
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 -right-24 w-72 h-72 bg-fuchsia-500/20 rounded-full blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-32 -left-24 w-72 h-72 bg-cyan-500/15 rounded-full blur-3xl"
      />

      <header className="relative flex items-start gap-4 p-5 sm:p-6 border-b border-slate-800/70">
        <div className="shrink-0 w-12 h-12 sm:w-14 sm:h-14 rounded-2xl bg-gradient-to-br from-fuchsia-500 via-fuchsia-500 to-cyan-500 flex items-center justify-center text-2xl sm:text-3xl shadow-lg shadow-fuchsia-500/30">
          🛒
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <h2 className="text-lg sm:text-xl font-bold text-white leading-tight">
              {headerLabel}
            </h2>
            <span className="hidden sm:inline px-2 py-0.5 rounded-full text-[10px] font-mono uppercase tracking-wider bg-fuchsia-500/20 text-fuchsia-200 border border-fuchsia-500/30">
              {draftWaybillId ? tKey('sales.panel.draft_chip', locale) : tKey('sales.panel.not_started', locale)}
            </span>
            <span className="text-[12px] text-slate-400 font-mono">
              เปิดใบสั่งขายใหม่
            </span>
            {draftWaybillId && (
              <span className="text-[11px] font-mono text-slate-500" data-testid="autosave-status">
                {autosavePending
                  ? `· ${tKey('sales.panel.saving', locale)}`
                  : lastSavedAt
                  ? `· ${tKey('sales.panel.saved', locale)} ${fmtTime(lastSavedAt)}`
                  : `· ${tKey('sales.panel.unsaved', locale)}`}
              </span>
            )}
          </div>
          <p className="mt-1 text-[12px] sm:text-[13px] text-slate-400 leading-relaxed">
            <Bilingual
              en="Pick customer → add line items → set payment terms → submit for review. "
              th="เลือกลูกค้า → เพิ่มรายการ → ตั้งเครดิต → ส่งอนุมัติ "
              de="Kunde wählen → Positionen hinzufügen → Zahlungsbedingungen festlegen → zur Prüfung einreichen. "
              locale={locale}
            />
            <Bilingual
              en="sales_rep submits; sales_supervisor approves then accounting issues the invoice."
              th="sales_rep ส่ง, sales_supervisor อนุมัติ แล้วบัญชีออกใบแจ้งหนี้"
              de="sales_rep reicht ein, sales_supervisor genehmigt, Buchhaltung stellt die Rechnung aus."
              locale={locale}
            />
          </p>
          <div className="mt-3 flex items-center gap-3">
            <div className="flex-1 h-1.5 rounded-full bg-slate-800/80 overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-fuchsia-500 to-emerald-500 transition-[width] duration-500 ease-out"
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
              className="rounded-lg border border-rose-500/40 bg-rose-950/30 hover:bg-rose-950/50 hover:border-rose-500/60 px-3 py-1.5 text-[11px] font-mono text-rose-200 transition-colors"
            >
              <Bilingual en="🗑 Discard draft" th="🗑 ลบร่าง" de="🗑 Entwurf verwerfen" locale={locale} />
            </button>
          )}
          <button
            type="button"
            onClick={() => setOpen((o) => !o)}
            aria-expanded={open}
            aria-controls="new-sales-panel-body"
            className="shrink-0 inline-flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-900/60 hover:bg-slate-800/80 hover:border-slate-600 px-3 py-1.5 text-[11px] font-mono text-slate-300 transition-colors"
          >
            <span aria-hidden>{open ? '▾' : '▸'}</span>
            {open
              ? <Bilingual en="Hide" th="ซ่อน" de="Ausblenden" locale={locale} />
              : <Bilingual en="Open" th="เปิด" de="Öffnen" locale={locale} />}
          </button>
        </div>
      </header>

      {open && (
        <div id="new-sales-panel-body" className="relative p-5 sm:p-6 space-y-5">
          {overCredit && customer && (
            <div className="rounded-xl border border-amber-500/40 bg-amber-950/30 px-3 py-2 text-[11px] font-mono text-amber-200">
              <Bilingual
                en={`⚠ Customer ${customer.code} outstanding AR is at ≥ 80% of credit limit. Credit check is more likely to require manual review.`}
                th={`⚠ ลูกค้า ${customer.code} มี AR ค้างชำระ ≥ 80% ของวงเงินเครดิต — อาจต้องตรวจสอบเครดิตด้วยตนเอง`}
                de={`⚠ Kunde ${customer.code} hat offene Forderungen ≥ 80% des Kreditlimits — Bonitätsprüfung erfordert wahrscheinlich manuelle Prüfung.`}
                locale={locale}
              />
            </div>
          )}

          <ol className="grid grid-cols-1 sm:grid-cols-3 gap-2" aria-label="Progress steps">
            {steps.map((s) => (
              <li
                key={s.key}
                className={[
                  'flex items-center gap-3 rounded-xl border px-3 py-2.5 transition-colors',
                  s.done
                    ? 'border-emerald-500/30 bg-emerald-500/5'
                    : s.active
                    ? 'border-fuchsia-500/40 bg-fuchsia-500/5'
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
                      <Bilingual en={s.title} th={s.titleTh} locale={locale} />
                    </p>
                  </div>
                </div>
              </li>
            ))}
          </ol>

          <StepCard
            n={1}
            icon="🏢"
            title="Pick customer"
            titleTh="เลือกลูกค้า"
            hint={
              <Bilingual
                en="Search by code or name. Newer customers with high AR utilization will be flagged."
                th="ค้นหาจากรหัสหรือชื่อ ลูกค้าที่ใช้เครดิตสูงจะถูกแจ้งเตือน"
                de="Suche nach Code oder Name. Kunden mit hoher Kreditauslastung werden markiert."
                locale={locale}
              />
            }
            done={customerReady}
            active={!customerReady}
            tone="indigo"
          >
            <CustomerCombobox
              value={customer?.id ?? null}
              onChange={(id, c) => setCustomer(c ?? (id != null ? { id, code: '', name: '' } : null))}
            />
            {customer && (
              <div className="mt-4">
                <CustomerArHistory
                  data={arBuckets}
                  totalInvoiced={arTotalInvoiced}
                  totalPaid={arTotalPaid}
                  creditLimit={arCreditLimit}
                  customerName={customer.name}
                  locale={locale}
                />
              </div>
            )}
          </StepCard>

          <StepCard
            n={2}
            icon="📦"
            title="Add line items"
            titleTh="เพิ่มรายการสินค้า/บริการ"
            hint={
              <Bilingual
                en="Each line carries description, qty, unit price, and VAT %. Subtotal + VAT roll up to the invoice total."
                th="แต่ละบรรทัดมีรายละเอียด, จำนวน, ราคาต่อหน่วย และภาษี % ยอดรวมก่อนภาษี + ภาษี จะรวมเป็นยอดใบแจ้งหนี้"
                de="Jede Position enthält Beschreibung, Menge, Einzelpreis und USt.-%. Zwischensumme + USt. ergeben den Rechnungsbetrag."
                locale={locale}
              />
            }
            done={itemsReady}
            active={customerReady && !itemsReady}
            tone="cyan"
            badge={
              itemsReady ? (
                <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-200 border border-emerald-500/30">
                  {items.length} <Bilingual en="line" th="รายการ" de="Position" locale={locale} />{items.length === 1 ? '' : 's'}
                </span>
              ) : null
            }
          >
            <div className="space-y-2">
              <div className="grid grid-cols-12 gap-2 text-[10px] font-mono uppercase tracking-wider text-slate-500 px-1">
                <div className="col-span-6">
                  <Bilingual en="description" th="รายละเอียด" de="Beschreibung" locale={locale} />
                </div>
                <div className="col-span-2 text-right">
                  <Bilingual en="qty" th="จำนวน" de="Menge" locale={locale} />
                </div>
                <div className="col-span-2 text-right">
                  <Bilingual en="unit (THB)" th="หน่วย (THB)" de="Einheit (THB)" locale={locale} />
                </div>
                <div className="col-span-1 text-right">
                  <Bilingual en="VAT %" th="ภาษี %" de="USt. %" locale={locale} />
                </div>
                <div className="col-span-1 text-right">
                  <Bilingual en="line" th="รวม" de="Zeile" locale={locale} />
                </div>
              </div>
              {items.map((it, idx) => {
                const t = lineTotals(it);
                return (
                  <div
                    key={it.key}
                    className="grid grid-cols-12 gap-2 items-center rounded-lg border border-slate-800 bg-slate-950/50 px-2 py-2"
                  >
                    <input
                      type="text"
                      value={it.description}
                      onChange={(e) => changeItem(idx, { description: e.target.value })}
                      placeholder={tKey('sales.panel.item_description', locale)}
                      className="col-span-6 rounded-md border border-slate-700 bg-slate-900/70 px-2 py-1.5 text-sm text-white focus:border-fuchsia-500/60 focus:outline-none"
                    />
                    <input
                      type="number"
                      min={0}
                      step="0.01"
                      value={it.qty}
                      onChange={(e) =>
                        changeItem(idx, { qty: parseFloat(e.target.value) || 0 })
                      }
                      className="col-span-2 rounded-md border border-slate-700 bg-slate-900/70 px-2 py-1.5 text-right text-sm text-white tabular-nums focus:border-fuchsia-500/60 focus:outline-none"
                    />
                    <input
                      type="number"
                      min={0}
                      step="0.01"
                      value={it.unitPrice}
                      onChange={(e) =>
                        changeItem(idx, { unitPrice: parseFloat(e.target.value) || 0 })
                      }
                      className="col-span-2 rounded-md border border-slate-700 bg-slate-900/70 px-2 py-1.5 text-right text-sm text-white tabular-nums focus:border-fuchsia-500/60 focus:outline-none"
                    />
                    <input
                      type="number"
                      min={0}
                      max={100}
                      step="0.01"
                      value={it.vatPct}
                      onChange={(e) =>
                        changeItem(idx, { vatPct: parseFloat(e.target.value) || 0 })
                      }
                      className="col-span-1 rounded-md border border-slate-700 bg-slate-900/70 px-2 py-1.5 text-right text-sm text-white tabular-nums focus:border-fuchsia-500/60 focus:outline-none"
                    />
                    <div className="col-span-1 text-right">
                      <button
                        type="button"
                        onClick={() => removeItem(idx)}
                        disabled={items.length <= 1}
                        className="rounded-md border border-slate-700 bg-slate-900/60 px-1.5 py-1 text-[10px] font-mono text-slate-300 hover:border-rose-500/50 hover:text-rose-200 disabled:opacity-30"
                        aria-label={`Remove line ${idx + 1}`}
                        title={`Remove line ${idx + 1}`}
                      >
                        ✕
                      </button>
                    </div>
                    <div className="col-span-12 -mt-1 px-1 text-right text-[10px] font-mono text-slate-500">
                      <Bilingual en="line" th="รายการ" de="Position" locale={locale} /> {idx + 1} · {tKey('sales.panel.subtotal', locale)} {t.subtotal.toLocaleString('th-TH', { minimumFractionDigits: 2 })} · {tKey('sales.panel.vat', locale)} {t.vat.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ·{' '}
                      <span className="text-emerald-300">{t.total.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB</span>
                    </div>
                  </div>
                );
              })}
              <button
                type="button"
                onClick={addItem}
                className="w-full rounded-lg border border-dashed border-slate-700 bg-slate-950/30 py-2 text-[11px] font-mono text-slate-300 hover:border-fuchsia-500/60 hover:text-fuchsia-200"
              >
                <Bilingual en="+ add line" th="+ เพิ่มรายการ" de="+ Position hinzufügen" locale={locale} />
              </button>
            </div>

            <div className="mt-4 grid grid-cols-3 gap-2 text-[11px] font-mono">
              <div className="rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-2">
                <div className="text-slate-500 uppercase tracking-wider">
                  <Bilingual en="Subtotal" th="ก่อนภาษี" de="Zwischensumme" locale={locale} />
                </div>
                <div className="text-sm text-slate-200 tabular-nums">
                  {totals.subtotal.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
                </div>
              </div>
              <div className="rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-2">
                <div className="text-slate-500 uppercase tracking-wider">
                  <Bilingual en="VAT" th="ภาษี" de="USt." locale={locale} />
                </div>
                <div className="text-sm text-amber-200 tabular-nums">
                  {totals.vat.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
                </div>
              </div>
              <div className="rounded-lg border border-emerald-500/40 bg-emerald-950/30 px-3 py-2">
                <div className="text-slate-300 uppercase tracking-wider">
                  <Bilingual en="Total" th="รวมทั้งสิ้น" de="Gesamt" locale={locale} />
                </div>
                <div className="text-base font-bold text-emerald-300 tabular-nums">
                  {totals.total.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
                </div>
              </div>
            </div>
          </StepCard>

          <StepCard
            n={3}
            icon="📅"
            title="Payment terms & due date"
            titleTh="เครดิต & กำหนดชำระ"
            hint={
              <Bilingual
                en="sales_rep submits; auto-skips sales_review when total < 5,000 THB."
                th="sales_rep ส่ง; ข้าม sales_review อัตโนมัติเมื่อยอด < 5,000 THB"
                de="sales_rep reicht ein; sales_review wird automatisch übersprungen, wenn der Betrag < 5.000 THB ist."
                locale={locale}
              />
            }
            done={termsReady}
            active={itemsReady && !termsReady}
            tone="indigo"
          >
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <label className="block text-[11px] font-mono uppercase tracking-wider text-slate-400">
                <Bilingual en="Payment terms" th="เงื่อนไขการชำระ" de="Zahlungsbedingungen" locale={locale} />
                <select
                  value={paymentTerms}
                  onChange={(e) => {
                    const next = e.target.value;
                    setPaymentTerms(next);
                    setDueDate(defaultDueDate(next));
                  }}
                  className="mt-1 w-full rounded-md border border-slate-700 bg-slate-900/70 px-2 py-2 text-sm text-white focus:border-fuchsia-500/60 focus:outline-none"
                >
                  {PAYMENT_TERMS.map((term) => (
                    <option key={term} value={term}>
                      {term}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block text-[11px] font-mono uppercase tracking-wider text-slate-400">
                <Bilingual en="Due date" th="กำหนดชำระ" de="Fälligkeitsdatum" locale={locale} />
                <input
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                  className="mt-1 w-full rounded-md border border-slate-700 bg-slate-900/70 px-2 py-2 text-sm text-white focus:border-fuchsia-500/60 focus:outline-none"
                />
              </label>
            </div>
          </StepCard>

          <StepCard
            n={4}
            icon="🚀"
            title="Review and submit"
            titleTh="ตรวจสอบและส่งอนุมัติ"
            hint={
              submitting
                ? <Bilingual en="Submitting your sales order…" th="กำลังส่งใบสั่งขาย…" de="Verkaufsauftrag wird eingereicht…" locale={locale} />
                : !customerReady
                ? <Bilingual en="Pick a customer to enable submit." th="เลือกลูกค้าเพื่อเปิดใช้งานการส่ง" de="Kunde wählen, um Einreichen zu aktivieren." locale={locale} />
                : !itemsReady
                ? <Bilingual en="Each line needs a description, qty > 0, unit ≥ 0." th="แต่ละรายการต้องมีรายละเอียด, จำนวน > 0, ราคาต่อหน่วย ≥ 0" de="Jede Position braucht Beschreibung, Menge > 0, Einzelpreis ≥ 0." locale={locale} />
                : !termsReady
                ? <Bilingual en="Set payment terms and due date." th="ตั้งเงื่อนไขการชำระและกำหนดชำระ" de="Zahlungsbedingungen und Fälligkeitsdatum festlegen." locale={locale} />
                : canSubmitAll
                ? draftWaybillId
                  ? <Bilingual
                      en={`Everything looks good. Submit draft ${draftWaybillId} for sales supervisor review.`}
                      th={`ทุกอย่างพร้อมแล้ว ส่งร่าง ${draftWaybillId} ให้ sales supervisor ตรวจสอบ`}
                      de={`Alles bereit. Entwurf ${draftWaybillId} an Sales-Supervisor zur Prüfung senden.`}
                      locale={locale}
                    />
                  : <Bilingual
                      en="Everything looks good. Save and send it to your sales supervisor."
                      th="ทุกอย่างพร้อมแล้ว บันทึกและส่งให้ sales supervisor"
                      de="Alles bereit. Speichern und an Sales-Supervisor senden."
                      locale={locale}
                    />
                : <Bilingual
                    en="Complete the steps above to enable submit."
                    th="ทำตามขั้นตอนด้านบนให้ครบเพื่อเปิดใช้งานการส่ง"
                    de="Bitte die Schritte oben abschließen, um das Einreichen zu aktivieren."
                    locale={locale}
                  />
            }
            done={false}
            active={canSubmitAll}
            tone={canSubmitAll ? 'emerald' : 'amber'}
          >
            <button
              type="button"
              onClick={handleSubmit}
              disabled={!canSubmitAll}
              className={[
                'w-full py-3.5 rounded-xl text-sm font-bold font-mono inline-flex items-center justify-center gap-2 shadow-lg transition-all duration-200',
                'disabled:opacity-50 disabled:cursor-not-allowed',
                submitting
                  ? 'bg-slate-700 text-slate-300'
                  : canSubmitAll
                  ? 'bg-gradient-to-r from-emerald-500 to-emerald-400 hover:from-emerald-400 hover:to-emerald-300 text-slate-950 shadow-emerald-500/30 hover:shadow-emerald-500/50 hover:-translate-y-px'
                  : 'bg-slate-800 text-slate-500',
              ].join(' ')}
            >
              {submitting
                ? <Bilingual en="⏳ Saving…" th="⏳ กำลังบันทึก…" de="⏳ Speichern…" locale={locale} />
                : canSubmitAll
                ? <Bilingual en="✓ Submit sales order for approval" th="✓ ส่งใบสั่งขายเพื่ออนุมัติ" de="✓ Verkaufsauftrag zur Genehmigung einreichen" locale={locale} />
                : <Bilingual en="🔒 Submit (disabled)" th="🔒 ส่ง (ปิดใช้งาน)" de="🔒 Einreichen (deaktiviert)" locale={locale} />}
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

export default NewSalesPanel;
