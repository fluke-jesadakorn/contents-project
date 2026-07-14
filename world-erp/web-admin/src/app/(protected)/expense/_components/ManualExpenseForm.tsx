'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  startExpenseDraft,
  saveDraftExpense,
  submitManualExpense,
  discardDraftExpense,
} from '@/app/actions';
import { Bilingual } from '@/components/i18n/Bilingual';

interface Props {
  currentUserId: number;
}

export function ManualExpenseForm({ currentUserId }: Props) {
  const router = useRouter();
  const [waybillId, setWaybillId] = useState<string | null>(null);
  const [vendorName, setVendorName] = useState('');
  const [txnDate, setTxnDate] = useState(new Date().toISOString().split('T')[0]);
  const [paymentMethod, setPaymentMethod] = useState('cash');
  const [subtotal, setSubtotal] = useState('');
  const [vatAmount, setVatAmount] = useState('');
  const [totalAmount, setTotalAmount] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const dirtyRef = useRef(false);

  const payMethods = [
    { value: 'cash', label: 'Cash · เงินสด', emoji: '💵' },
    { value: 'credit_card', label: 'Credit card · บัตรเครดิต', emoji: '💳' },
    { value: 'transfer', label: 'Transfer · โอน', emoji: '🏦' },
  ];

  useEffect(() => {
    if (waybillId) return;
    let cancelled = false;
    (async () => {
      const r = await startExpenseDraft(currentUserId);
      if (cancelled || !r.ok || !r.waybillId) return;
      setWaybillId(r.waybillId);
      setSavedAt(new Date().toISOString());
    })();
    return () => { cancelled = true; };
  }, [waybillId, currentUserId]);

  useEffect(() => {
    if (!waybillId || !dirtyRef.current) return;
    dirtyRef.current = false;
    const timer = setTimeout(async () => {
      const r = await saveDraftExpense({
        waybillId,
        actorId: currentUserId,
        payload: {
          vendorName: vendorName || undefined,
          transactionDate: txnDate || undefined,
          subtotal: subtotal ? Number(subtotal) : undefined,
          vatAmount: vatAmount ? Number(vatAmount) : undefined,
          totalAmount: totalAmount ? Number(totalAmount) : undefined,
          paymentMethod,
        },
      });
      if (r.ok && r.savedAt) setSavedAt(r.savedAt);
    }, 3000);
    return () => clearTimeout(timer);
  }, [waybillId, vendorName, txnDate, subtotal, vatAmount, totalAmount, paymentMethod, currentUserId]);

  function markDirty() { dirtyRef.current = true; }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!waybillId) return;
    const total = Number(totalAmount);
    if (!vendorName.trim() || !txnDate || total <= 0) {
      setError('Vendor name, date, and total amount are required.');
      return;
    }
    setSubmitting(true);
    setError(null);
    const r = await submitManualExpense({
      waybillId,
      actorId: currentUserId,
      vendorName: vendorName.trim(),
      transactionDate: txnDate,
      paymentMethod,
      subtotal: Number(subtotal) || 0,
      vatAmount: Number(vatAmount) || 0,
      totalAmount: total,
    });
    setSubmitting(false);
    if (!r.ok) {
      setError(r.error ?? 'Submit failed');
      return;
    }
    router.push(`/waybill/${r.waybillId}`);
  }

  async function handleDiscard() {
    if (!waybillId) return;
    if (!confirm('Discard this draft?')) return;
    await discardDraftExpense({ waybillId, actorId: currentUserId });
    setWaybillId(null);
    setVendorName('');
    setTxnDate(new Date().toISOString().split('T')[0]);
    setPaymentMethod('cash');
    setSubtotal('');
    setVatAmount('');
    setTotalAmount('');
    router.refresh();
  }

  const valid = vendorName.trim().length > 0 && txnDate.length > 0 && Number(totalAmount) > 0;

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {waybillId && (
        <div className="flex items-center gap-2 text-sm font-mono text-slate-500">
          <span className="text-cyan-300">{waybillId}</span>
          <span>·</span>
          {savedAt
            ? <Bilingual en={`saved`} th={`บันทึกแล้ว`} />
            : <Bilingual en={`unsaved`} th={`ยังไม่บันทึก`} />}
          <button
            type="button"
            onClick={handleDiscard}
            className="ml-auto rounded border border-rose-500/30 bg-rose-950/20 px-2 py-0.5 text-xs text-rose-200 hover:bg-rose-950/40"
          >
            🗑
          </button>
        </div>
      )}

      <div className="grid grid-cols-1 gap-x-4 gap-y-3 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-mono uppercase tracking-wider text-slate-400">
            <Bilingual en="Vendor *" th="ผู้ขาย *" />
          </label>
          <input
            type="text"
            value={vendorName}
            onChange={(e) => { setVendorName(e.target.value); markDirty(); }}
            placeholder="Vendor name"
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-white placeholder-slate-600 focus:border-cyan-500 focus:outline-none"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-mono uppercase tracking-wider text-slate-400">
            <Bilingual en="Date *" th="วันที่ *" />
          </label>
          <input
            type="date"
            value={txnDate}
            onChange={(e) => { setTxnDate(e.target.value); markDirty(); }}
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-white focus:border-cyan-500 focus:outline-none"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-mono uppercase tracking-wider text-slate-400">
            <Bilingual en="Payment" th="การชำระ" />
          </label>
          <select
            value={paymentMethod}
            onChange={(e) => { setPaymentMethod(e.target.value); markDirty(); }}
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-white focus:border-cyan-500 focus:outline-none"
          >
            {payMethods.map((m) => (
              <option key={m.value} value={m.value} className="bg-slate-900">{m.emoji} {m.label}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-sm font-mono uppercase tracking-wider text-slate-400">
            <Bilingual en="Subtotal" th="ยอดก่อน VAT" />
          </label>
          <input
            type="number"
            step="0.01"
            min="0"
            value={subtotal}
            onChange={(e) => { setSubtotal(e.target.value); markDirty(); }}
            placeholder="0.00"
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-white placeholder-slate-600 focus:border-cyan-500 focus:outline-none"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-mono uppercase tracking-wider text-slate-400">
            <Bilingual en="VAT" th="VAT" />
          </label>
          <input
            type="number"
            step="0.01"
            min="0"
            value={vatAmount}
            onChange={(e) => { setVatAmount(e.target.value); markDirty(); }}
            placeholder="0.00"
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-white placeholder-slate-600 focus:border-cyan-500 focus:outline-none"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-mono uppercase tracking-wider text-slate-400">
            <Bilingual en="Total *" th="รวม *" />
          </label>
          <input
            type="number"
            step="0.01"
            min="0"
            value={totalAmount}
            onChange={(e) => { setTotalAmount(e.target.value); markDirty(); }}
            placeholder="0.00"
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-white placeholder-slate-600 focus:border-cyan-500 focus:outline-none"
          />
        </div>
      </div>

      {error && (
        <p className="rounded-lg border border-rose-500/40 bg-rose-950/40 px-3 py-2 text-xs text-rose-200">{error}</p>
      )}

      <button
        type="submit"
        disabled={!waybillId || !valid || submitting}
        className="w-full rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-400 py-3 text-sm font-bold text-slate-950 shadow-lg shadow-emerald-500/30 transition-all hover:-translate-y-px hover:shadow-emerald-500/50 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:translate-y-0"
      >
        {submitting
          ? <Bilingual en="⏳ Submitting…" th="⏳ กำลังส่ง…" />
          : <Bilingual en="✓ Submit for approval" th="✓ ส่งเพื่ออนุมัติ" />}
      </button>
    </form>
  );
}
