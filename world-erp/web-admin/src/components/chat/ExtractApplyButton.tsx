'use client';
import { useState } from 'react';
import type { ExtractFields } from './extractContract';
import { useT } from '@/components/i18n/useT';
import { T, interpolate } from '@/components/i18n/T';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';
import chatDict from '@erp-lib/i18n/chat';
import type { BilingualText } from '@erp-lib/i18n/types';

export function ExtractApplyButton({
  waybillId,
  fields,
}: {
  waybillId?: string;
  fields: ExtractFields;
}) {
  const t = useT(chatDict);
  const locale = useSecondaryLocale();
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<BilingualText | null>(null);

  const pick = (k: string): BilingualText => t(k);

  const asStr = (b: BilingualText): string =>
    b[locale] ?? b.en;

  async function apply_() {
    setBusy(true);
    setResult(null);
    try {
      const r = await fetch('/api/expense/apply-extract', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ waybillId, fields }),
      });
      const data = await r.json();
      if (data.ok) {
        setResult(
          interpolate(pick('chat.extract.saved'), { id: data.waybillId, time: new Date(data.savedAt).toLocaleTimeString() }),
        );
      } else {
        setResult(interpolate(pick('chat.extract.fail'), { error: data.error ?? '' }));
      }
    } catch (e: any) {
      const errMsg = e?.message ?? asStr(pick('chat.extract.networkFail'));
      setResult(interpolate(pick('chat.extract.fail'), { error: errMsg }));
    }
    setBusy(false);
  }

  const lowConf = fields.confidence < 0.7;

  return (
    <div className="my-2 rounded-xl border border-emerald-700/40 bg-emerald-950/20 p-3">
      <div className="flex items-center justify-between gap-2 mb-1.5">
        <div className="text-[10px] font-mono font-bold uppercase tracking-wider text-emerald-300">
          <T value={interpolate(pick('chat.extract.title'), { pct: (fields.confidence * 100).toFixed(0) })} />
        </div>
        <button
          type="button"
          onClick={apply_}
          disabled={busy}
          className="text-[10px] px-2.5 py-1 rounded-lg bg-emerald-600 text-white font-bold hover:bg-emerald-500 disabled:opacity-50"
        >
          <T value={waybillId ? pick('chat.extract.applyActive') : pick('chat.extract.saveNew')} />
        </button>
      </div>
      {lowConf && (
        <div className="text-[10px] text-amber-300 mb-1.5">
          <T value={pick('chat.extract.lowConf')} />
        </div>
      )}
      <div className="grid grid-cols-2 gap-1 text-[11px] font-mono">
        {fields.vendor && (
          <>
            <span className="text-slate-500"><T value={pick('chat.extract.vendor')} /></span>
            <span className="text-white">{fields.vendor}</span>
          </>
        )}
        {fields.amount != null && (
          <>
            <span className="text-slate-500"><T value={pick('chat.extract.amount')} /></span>
            <span className="text-white">
              {fields.amount} {fields.currency || 'THB'}
            </span>
          </>
        )}
        {fields.transactionDate && (
          <>
            <span className="text-slate-500"><T value={pick('chat.extract.date')} /></span>
            <span className="text-white">{fields.transactionDate}</span>
          </>
        )}
        {fields.categoryCode && (
          <>
            <span className="text-slate-500"><T value={pick('chat.extract.category')} /></span>
            <span className="text-white">
              {fields.categoryLabel || fields.categoryCode}
            </span>
          </>
        )}
        {fields.description && (
          <>
            <span className="text-slate-500"><T value={pick('chat.extract.notes')} /></span>
            <span className="text-white truncate">{fields.description}</span>
          </>
        )}
      </div>
      {result && <div className="text-[10px] text-slate-300 mt-1.5"><T value={result} /></div>}
    </div>
  );
}