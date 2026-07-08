import React from 'react';
import Link from 'next/link';
import type { WaybillDomain, WaybillStagePip } from '@erp-lib/waybill/derive';
import { findPip, pipIndex, bucketLabel } from '@erp-lib/waybill/derive';
import type { WaybillEventRow } from '@erp-lib/waybill/events';
import { stageLabel } from '@erp-lib/waybill/labels';

interface Props {
  waybillId: string;
  domain: WaybillDomain;
  pipKey: string;
  currentStage: string;
  lang?: 'en' | 'th';
  events: WaybillEventRow[];
  amountTHB?: number | null;
}

export function WaybillDetailDrawer({
  waybillId,
  domain,
  pipKey,
  currentStage,
  lang = 'en',
  events,
  amountTHB,
}: Props) {
  const pip = findPip(domain, pipKey);
  if (!pip) {
    return (
      <DrawerShell waybillId={waybillId} heading="Unknown stage">
        <p className="text-xs text-rose-300">No pip matches {pipKey}.</p>
      </DrawerShell>
    );
  }

  const idx = pipIndex(domain, pipKey);
  const curIdx = pipIndex(domain, currentStage);
  const state = computeState(pip, idx, curIdx, currentStage);

  const passedEvents = events.filter((e) => e.stage_to === pipKey).slice(-3);

  const bucketKind = bucketLabel(pip.bucket, lang);

  return (
    <DrawerShell
      waybillId={waybillId}
      heading={`${pip.emoji} ${lang === 'th' ? pip.th : pip.en}`}
      subheading={`${bucketKind} · pip #${idx + 1}`}
    >
      <div className="space-y-4 text-sm text-slate-200">
        <p className="italic text-slate-300">
          {lang === 'th' ? pip.description_th : pip.description_en}
        </p>

        <div className="rounded-lg border border-slate-800 bg-slate-950/50 p-3">
          <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
            State
          </div>
          <div className="mt-1 flex items-center gap-2 text-sm">
            <StateBadge state={state} lang={lang} />
            <span className="text-slate-400">
              {explainState(state, lang, amountTHB, pip)}
            </span>
          </div>
        </div>

        <div>
          <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
            Recent events touching this pip
          </div>
          {passedEvents.length === 0 ? (
            <p className="mt-1 text-xs text-slate-500">No events recorded yet.</p>
          ) : (
            <ol className="mt-2 space-y-1.5">
              {passedEvents.map((e) => (
                <li key={e.id} className="text-xs">
                  <span className="font-mono text-cyan-300">#{e.sequence}</span>{' '}
                  <span className="font-mono text-slate-400">{e.kind}</span>{' '}
                  <span className="text-slate-500">
                    {e.stage_from ?? '—'} → <span className="text-emerald-300">{e.stage_to ?? '—'}</span>
                  </span>
                  <span className="ml-2 text-slate-500">
                    {formatTime(e.occurred_at)}
                  </span>
                </li>
              ))}
            </ol>
          )}
        </div>

        <div className="rounded-lg border border-cyan-500/30 bg-cyan-950/20 p-3 text-xs">
          <div className="text-[10px] font-mono uppercase tracking-widest text-cyan-300">
            Acting now?
          </div>
          <div className="mt-1 text-slate-200">
            {currentStage === pipKey
              ? actionPrompt(lang, pip)
              : `Pipeline is on ${stageLabel(currentStage, domain, lang).label}`}
          </div>
          {currentStage === pipKey && (
            <div className="mt-2 flex flex-wrap gap-2">
              <Link
                href={`/waybill/${waybillId}?action=approve&stage=${pipKey}`}
                className="rounded bg-emerald-500/20 px-2.5 py-1 font-mono text-[11px] text-emerald-200 hover:bg-emerald-500/30"
              >
                ✓ Approve
              </Link>
              <Link
                href={`/waybill/${waybillId}?action=reject&stage=${pipKey}`}
                className="rounded bg-rose-500/20 px-2.5 py-1 font-mono text-[11px] text-rose-200 hover:bg-rose-500/30"
              >
                ✗ Reject
              </Link>
            </div>
          )}
        </div>
      </div>
    </DrawerShell>
  );
}

type PipState = 'passed' | 'active' | 'pending' | 'rejected' | 'skipped';

function computeState(
  pip: WaybillStagePip,
  idx: number,
  curIdx: number,
  currentStage: string,
): PipState {
  if (currentStage === 'rejected') return 'rejected';
  if (curIdx < 0) {
    return pip.key === 'rejected' ? 'rejected' : 'pending';
  }
  if (idx < curIdx) return 'passed';
  if (idx === curIdx) return 'active';
  return 'pending';
}

function StateBadge({ state, lang }: { state: PipState; lang: 'en' | 'th' }) {
  const map: Record<PipState, string> = {
    passed: 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40',
    active: 'bg-cyan-500/20 text-cyan-200 border-cyan-500/40',
    pending: 'bg-slate-700/40 text-slate-400 border-slate-600',
    rejected: 'bg-rose-500/15 text-rose-200 border-rose-500/40',
    skipped: 'bg-slate-900 text-slate-600 border-slate-800',
  };
  const label: Record<PipState, { en: string; th: string }> = {
    passed: { en: 'Passed', th: 'ผ่านแล้ว' },
    active: { en: 'Active', th: 'กำลังดำเนินการ' },
    pending: { en: 'Pending', th: 'รอดำเนินการ' },
    rejected: { en: 'Rejected', th: 'ปฏิเสธ' },
    skipped: { en: 'Skipped', th: 'ข้าม' },
  };
  return (
    <span className={`rounded-full border px-2.5 py-0.5 font-mono text-[10px] font-bold uppercase ${map[state]}`}>
      {lang === 'th' ? label[state].th : label[state].en}
    </span>
  );
}

function explainState(
  state: PipState,
  lang: 'en' | 'th',
  amountTHB: number | null | undefined,
  pip: WaybillStagePip,
): string {
  if (state === 'skipped') {
    return lang === 'th'
      ? `ข้าม: จำนวนเงินต่ำกว่า 200,000 บาท (ไม่ต้องใช้ ${pip.th})`
      : `Skipped: amount under 200,000 THB (no ${pip.en} required)`;
  }
  if (state === 'active') {
    return lang === 'th' ? 'กำลังรอดำเนินการในขั้นตอนนี้' : 'Awaiting action at this stage';
  }
  if (state === 'passed') {
    return lang === 'th' ? 'เสร็จสิ้นแล้วและลงนาม' : 'Cleared and signed off';
  }
  if (state === 'rejected') {
    return lang === 'th' ? 'ถูกปฏิเสธ — ดูเหตุผลด้านล่าง' : 'Rejected — see reason below';
  }
  return lang === 'th' ? 'ยังไม่ถึงขั้นตอนนี้' : 'Not yet reached';
}

function actionPrompt(lang: 'en' | 'th', pip: WaybillStagePip): string {
  const approved = lang === 'th' ? `อนุมัติ ${pip.th}` : `Approve ${pip.en}`;
  return approved;
}

function formatTime(t: Date | string): string {
  const d = t instanceof Date ? t : new Date(t);
  if (!Number.isFinite(d.getTime())) return '—';
  return d.toLocaleString();
}

interface ShellProps {
  waybillId: string;
  heading: string;
  subheading?: string;
  children: React.ReactNode;
}

function DrawerShell({ waybillId, heading, subheading, children }: ShellProps) {
  return (
    <div
      className="fixed inset-0 z-50 flex justify-end font-sans"
      role="dialog"
      aria-modal="true"
      aria-label="Pip detail"
    >
      <Link
        href={`/waybill/${waybillId}`}
        className="absolute inset-0 bg-slate-950/70 backdrop-blur-sm"
        aria-label="Close"
      />
      <aside className="relative z-10 flex h-full w-full max-w-md flex-col overflow-y-auto border-l border-slate-800 bg-slate-900 shadow-2xl">
        <header className="flex items-start justify-between border-b border-slate-800 bg-slate-950/60 p-4">
          <div className="space-y-0.5">
            <h2 className="text-sm font-bold text-white">{heading}</h2>
            {subheading && (
              <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
                {subheading}
              </div>
            )}
          </div>
          <Link
            href={`/waybill/${waybillId}`}
            className="rounded-lg border border-slate-700 px-2.5 py-1 text-xs text-slate-300 hover:border-rose-500 hover:text-rose-200"
            aria-label="Close drawer"
          >
            ✕
          </Link>
        </header>
        <div className="flex-1 space-y-4 p-4">{children}</div>
      </aside>
    </div>
  );
}