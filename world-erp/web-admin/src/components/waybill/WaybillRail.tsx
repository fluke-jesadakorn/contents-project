import React from 'react';
import type { WaybillDomain, WaybillStagePip } from '@erp-lib/waybill/derive';
import { pipsForDomain, stageRoleLabel, stageRoles } from '@erp-lib/waybill/derive';

export interface PipActor {
  name: string;
  ts: string | number | Date;
  kind: string;
  actorId?: number | null;
}

interface Props {
  domain: WaybillDomain;
  currentStage: string;
  lang?: 'en' | 'th';
  activeActorName?: string | null;
  rejectionReason?: string | null;
  amountTHB?: number | null;
  compact?: boolean;
  onPipHref?: (pipKey: string) => string;
  actorRole?: string | null;
  pipActors?: Record<string, PipActor> | null;
}

interface PipStatus {
  pip: WaybillStagePip;
  index: number;
  state: 'passed' | 'active' | 'pending' | 'rejected' | 'skipped';
}

function fmtActorTs(ts: string | number | Date): string {
  try {
    return new Date(ts).toLocaleString('th-TH');
  } catch {
    return '';
  }
}

export function WaybillRail({
  domain,
  currentStage,
  lang = 'en',
  activeActorName = null,
  rejectionReason = null,
  amountTHB = null,
  compact = false,
  onPipHref,
  actorRole = null,
  pipActors = null,
}: Props) {
  const pips = pipsForDomain(domain);
  const idx = pips.findIndex((p) => p.key === currentStage);
  const isRejected = currentStage === 'rejected';
  const isClosed = currentStage === 'disbursed' || isRejected;
  const needCeo =
    domain === 'expense' && typeof amountTHB === 'number' && amountTHB >= 200_000;

  const rendered: PipStatus[] = pips.map((pip, i) => {
    if (isRejected) {
      return { pip, index: i, state: 'rejected' };
    }
    if (i < idx) return { pip, index: i, state: 'passed' };
    if (i === idx) return { pip, index: i, state: 'active' };
    if (domain === 'expense' && pip.key === 'ceo_authorization' && !needCeo) {
      return { pip, index: i, state: 'skipped' };
    }
    return { pip, index: i, state: 'pending' };
  });

  if (isRejected) {
    return (
      <div className="rounded-2xl border border-rose-500/40 bg-rose-950/30 p-4 font-sans">
        <div className="flex items-center gap-2 text-rose-300">
          <span className="text-2xl">❌</span>
          <span className="text-xs font-bold uppercase tracking-widest">
            Rejected · {lang === 'th' ? 'ปฏิเสธ' : 'Rejected'}
          </span>
        </div>
        {rejectionReason && (
          <p className="mt-2 text-xs text-rose-200 italic">&ldquo;{rejectionReason}&rdquo;</p>
        )}
      </div>
    );
  }

  if (compact) {
    return (
      <div className="flex items-center gap-1 overflow-x-auto py-1" dir="ltr">
        {rendered.map(({ pip, state }) => (
          <span
            key={pip.key}
            title={lang === 'th' ? pip.th : pip.en}
            className={
              state === 'passed'
                ? 'text-emerald-300 text-base'
                : state === 'active'
                ? 'text-cyan-300 text-lg animate-pulse'
                : state === 'skipped'
                ? 'text-slate-700 text-base'
                : 'text-slate-500 text-base'
            }
          >
            {state === 'passed' ? '✓' : pip.emoji}
          </span>
        ))}
        {rendered.length > 1 && (
          <span className="ml-2 text-[10px] font-mono text-slate-500">
            step {(idx === -1 ? rendered.length : idx + 1)} of {rendered.filter((r) => r.state !== 'skipped').length}
          </span>
        )}
      </div>
    );
  }

  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-950/60 p-4 font-sans">
      <div className="mb-3 flex items-center justify-between">
        <span className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
          {domain === 'procurement' ? 'Procurement Waybill' : 'Expense Waybill'}
        </span>
        <span className="text-[10px] font-mono text-slate-500">
          {isClosed ? 'Closed' : `Step ${idx + 1} of ${rendered.filter((r) => r.state !== 'skipped').length}`}
        </span>
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-5 xl:grid-cols-7">
        {rendered.map(({ pip, index, state }) => {
          const isCeoOptional = pip.key === 'ceo_authorization' && !needCeo;
          const approverLabel = stageRoleLabel(pip.key, lang);
          const stageRole = stageRoles(pip.key);
          const isYourRole = !!actorRole && stageRole.includes(actorRole);
          const actor = pipActors?.[pip.key] ?? null;
          return (
            <a
              key={pip.key}
              href={onPipHref ? onPipHref(pip.key) : undefined}
              className={
                'relative flex flex-col items-start gap-1 rounded-xl border p-2.5 overflow-hidden ' +
                (state === 'passed'
                  ? 'border-emerald-500/40 bg-emerald-950/30 text-emerald-200'
                  : state === 'active'
                  ? 'border-cyan-400 bg-cyan-950/40 text-white shadow-lg shadow-cyan-500/20 ring-1 ring-cyan-400/60'
                  : isCeoOptional
                  ? 'border-slate-900 bg-slate-950/40 text-slate-700'
                  : 'border-slate-800 bg-slate-950/40 text-slate-400') +
                (isYourRole ? ' ring-2 ring-purple-500/40' : '')
              }
            >
              {isYourRole && (
                <span className="absolute right-0 top-0 rounded-bl bg-purple-500/20 px-1.5 py-0.5 text-[8px] font-mono font-bold uppercase tracking-wider text-purple-300">
                  {lang === 'th' ? 'บทบาทคุณ' : 'Your role'}
                </span>
              )}
              <div className="flex w-full items-center justify-between">
                <span className="text-xl">{pip.emoji}</span>
                <span
                  className={
                    'rounded px-1.5 py-0.5 text-[9px] font-bold uppercase ' +
                    (state === 'passed'
                      ? 'bg-emerald-500/20 text-emerald-300'
                      : state === 'active'
                      ? 'bg-cyan-500 text-white animate-pulse'
                      : isCeoOptional
                      ? 'bg-slate-800 text-slate-600'
                      : 'bg-slate-800 text-slate-500')
                  }
                >
                  {state === 'passed'
                    ? '✓ ' + (lang === 'th' ? 'ผ่าน' : 'Done')
                    : state === 'active'
                    ? lang === 'th'
                      ? 'กำลังดำเนินการ'
                      : 'Active'
                    : isCeoOptional
                    ? lang === 'th'
                      ? 'ไม่บังคับ'
                      : 'Optional'
                    : lang === 'th'
                    ? 'รอ'
                    : 'Pending'}
                </span>
              </div>
              <h4 className="text-[11px] font-bold leading-tight">
                {lang === 'th' ? pip.th : pip.en}
              </h4>
              <p className="text-[10px] leading-tight text-slate-500">
                {lang === 'th' ? pip.description_th : pip.description_en}
              </p>

              <div className="mt-auto w-full border-t border-slate-800/60 pt-1.5">
                <div className="text-[9px] font-mono uppercase tracking-widest text-slate-500">
                  {lang === 'th' ? 'ผู้อนุมัติ' : 'Approver'}
                </div>
                <div
                  className={
                    'text-[11px] font-bold leading-tight ' +
                    (state === 'passed' || state === 'active'
                      ? 'text-amber-300'
                      : 'text-slate-300')
                  }
                >
                  👤 {approverLabel}
                </div>
                {actor && state === 'passed' && (
                  <div className="mt-1 text-[10px] font-mono leading-tight text-emerald-300">
                    ✓ {actor.name}
                    <span className="text-slate-500">
                      {' · ' + fmtActorTs(actor.ts)}
                    </span>
                  </div>
                )}
                {state === 'active' && activeActorName && (
                  <div className="mt-1 text-[10px] font-mono leading-tight text-cyan-300">
                    ⏱ {activeActorName}
                  </div>
                )}
              </div>

              {index < rendered.length - 1 && state === 'passed' && (
                <span className="pointer-events-none absolute -right-1 top-1/2 hidden -translate-y-1/2 text-slate-600 md:block">
                  ➔
                </span>
              )}
            </a>
          );
        })}
      </div>
    </div>
  );
}
