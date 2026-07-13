'use client';

import React from 'react';
import Link from 'next/link';
import type { WaybillDomain, PipState } from '@erp-lib/waybill/derive';
import {
  pipsForDomain,
  pipIndex,
  computePipState,
  stageRoleLabel,
} from '@erp-lib/waybill/derive';
import type { WaybillEventRow } from '@erp-lib/waybill/events';
import { roleDisplay } from './ui';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';
import { Bilingual } from '@/components/i18n/Bilingual';
import { useFormatDate } from '@/components/i18n/formatters';

export interface WaybillTimelineProps {
  waybillId: string;
  domain: WaybillDomain;
  currentStage: string;
  status: 'open' | 'completed' | 'rejected' | 'reversed' | 'superseded';
  events: WaybillEventRow[];
  activeActorName?: string | null;
  activeRole?: string | null;
  rejectionReason?: string | null;
  rejectionActorName?: string | null;
  rejectedAt?: string | null;
}

const PIP_BADGE_EN: Record<PipState, string> = {
  passed: 'Done',
  active: 'Active',
  pending: 'Pending',
  rejected: 'Rejected',
  skipped: 'Optional',
};
const PIP_BADGE_TH: Record<PipState, string> = {
  passed: 'ผ่าน',
  active: 'กำลังดำเนินการ',
  pending: 'รอ',
  rejected: 'ปฏิเสธ',
  skipped: 'ไม่บังคับ',
};
const PIP_BADGE_DE: Record<PipState, string> = {
  passed: 'Erledigt',
  active: 'Aktiv',
  pending: 'Ausstehend',
  rejected: 'Abgelehnt',
  skipped: 'Optional',
};

const BULLET_GLYPH: Record<PipState, string> = {
  passed: '✓',
  active: '◉',
  pending: '○',
  rejected: '✗',
  skipped: '—',
};

function toneForState(state: PipState) {
  switch (state) {
    case 'passed':
      return {
        card: 'border-emerald-500/40 bg-emerald-950/30 text-emerald-100',
        bullet: 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.7)] text-emerald-200',
        badge: 'bg-emerald-500/20 text-emerald-300',
        title: 'text-emerald-300',
      };
    case 'active':
      return {
        card: 'border-cyan-400/80 bg-cyan-950/40 text-white shadow-lg shadow-cyan-500/30 ring-2 ring-cyan-400/70',
        bullet: 'bg-cyan-300 shadow-[0_0_10px_rgba(34,211,238,0.8)] animate-pulse text-cyan-100',
        badge: 'bg-cyan-500 text-slate-950 animate-pulse',
        title: 'text-cyan-300',
      };
    case 'skipped':
      return {
        card: 'border-slate-900 bg-slate-950/40 text-slate-700',
        bullet: 'bg-slate-800 text-slate-600',
        badge: 'bg-slate-800 text-slate-600',
        title: 'text-slate-700',
      };
    case 'rejected':
      return {
        card: 'border-rose-500/60 bg-rose-950/40 text-rose-100 ring-1 ring-rose-500/40',
        bullet: 'bg-rose-400 text-rose-100',
        badge: 'bg-rose-500/20 text-rose-300',
        title: 'text-rose-300',
      };
    case 'pending':
    default:
      return {
        card: 'border-slate-800 bg-slate-950/40 text-slate-400',
        bullet: 'bg-slate-700 text-slate-500',
        badge: 'bg-slate-800 text-slate-500',
        title: 'text-slate-400',
      };
  }
}

const DONE_KINDS = ['advanced', 'settled', 'posted-to-gl', 'gl-confirmed', 'signed-off', 'created'] as const;

function lastDoneEventFor(
  pipKey: string,
  events: WaybillEventRow[],
): WaybillEventRow | null {
  const main = events
    .filter((e) => e.stage_to === pipKey && DONE_KINDS.includes(e.kind as (typeof DONE_KINDS)[number]))
    .sort((a, b) => b.sequence - a.sequence)[0] ?? null;
  if (main) return main;
  if (pipKey === 'submission') {
    const sub = events
      .filter((e) => e.kind === 'submitted' && (e.stage_from === null || e.stage_to === 'submission'))
      .sort((a, b) => b.sequence - a.sequence)[0] ?? null;
    return sub;
  }
  return null;
}

export function WaybillTimeline({
  waybillId,
  domain,
  currentStage,
  status,
  events,
  activeActorName = null,
  activeRole: _activeRole = null,
  rejectionReason = null,
  rejectionActorName = null,
  rejectedAt = null,
}: WaybillTimelineProps): React.JSX.Element {
  const locale = useSecondaryLocale();
  const fmtTs = useFormatDate();
  const pips = pipsForDomain(domain);
  const curIdx = pipIndex(domain, currentStage);
  const isRejected = status === 'rejected' || currentStage === 'rejected';

  if (isRejected) {
    return (
      <div className="rounded-3xl border border-rose-500/30 bg-rose-950/10 p-5 mb-6 font-sans">
        <div className="flex flex-wrap items-center gap-3">
          <span aria-hidden className="text-2xl">❌</span>
          <span className="text-sm font-bold uppercase tracking-widest text-rose-300">
            <Bilingual en="Workflow Terminated" th="ยุติขั้นตอน" de="Workflow beendet" locale={locale} />
          </span>
          <span className="text-xs font-mono text-rose-200/80">
            <Bilingual en="Reimbursement Claim Rejected" th="ใบเบิกถูกปฏิเสธ" de="Auslagenabrechnung abgelehnt" locale={locale} />
          </span>
          <span className="ml-auto inline-flex items-center rounded-full border border-rose-500/40 bg-rose-500/15 px-2.5 py-0.5 text-[10px] font-mono font-bold uppercase tracking-wider text-rose-200">
            <Bilingual en="Status: REJECTED" th="สถานะ: ปฏิเสธ" de="Status: ABGELEHNT" locale={locale} />
          </span>
        </div>
        {rejectionReason && (
          <div className="mt-4 rounded-2xl border border-rose-500/30 bg-rose-950/30 p-4">
            <div className="text-[10px] font-mono uppercase tracking-widest text-rose-300/80">
              <Bilingual en="Rejection reason" th="เหตุผลการปฏิเสธ" de="Ablehnungsgrund" locale={locale} />
            </div>
            <p className="mt-1.5 text-sm italic text-rose-100">&ldquo;{rejectionReason}&rdquo;</p>
            {(rejectionActorName || rejectedAt) && (
              <div className="mt-2 text-[11px] font-mono text-rose-300/80">
                {rejectionActorName && <span>{rejectionActorName}</span>}
                {rejectionActorName && rejectedAt && <span className="mx-1 text-rose-700">·</span>}
                {rejectedAt && <span>{fmtTs(rejectedAt)}</span>}
              </div>
            )}
          </div>
        )}
        <div className="mt-4">
          <Link
            href={`/waybill/${waybillId}#pip-rejected`}
            className="text-xs font-mono text-cyan-300 underline-offset-2 hover:underline"
          >
            <Bilingual en="View rejected step →" th="ดูขั้นตอนที่ถูกปฏิเสธ →" de="Abgelehnten Schritt ansehen →" locale={locale} />
          </Link>
        </div>
      </div>
    );
  }

  const items = pips.map((pip, idx) => {
    const state = computePipState(pip, idx, curIdx, currentStage, status);
    const lastDoneEv = lastDoneEventFor(pip.key, events);
    return { pip, idx, state, lastDoneEv };
  });

  const countable = pips.filter((p) => p.key !== 'rejected').length;
  const stepNumber = curIdx < 0 ? countable : curIdx + 1;

  return (
    <div className="rounded-3xl border border-slate-800/80 bg-slate-950/40 p-5 mb-6 overflow-hidden relative font-sans">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="bg-cyan-500/10 text-cyan-300 border border-cyan-500/30 text-xs font-mono font-bold px-2 py-0.5 rounded uppercase tracking-wider">
            <Bilingual en="Pipeline Stepper" th="ไทม์ไลน์ Waybill" de="Waybill-Zeitachse" locale={locale} />
          </span>
          <span className="text-[11px] font-mono uppercase tracking-widest text-slate-500">
            <Bilingual en="Approval flow" th="ลำดับอนุมัติ" de="Freigabereihenfolge" locale={locale} />
          </span>
        </div>
        <span className="text-[11px] font-mono text-slate-400">
          <Bilingual en="step" th="ขั้น" de="Schritt" locale={locale} /> {stepNumber}{' '}
          <Bilingual en="of" th="จาก" de="von" locale={locale} /> {countable}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-2 pb-2 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-7 auto-rows-auto">
        {items.map(({ pip, idx, state, lastDoneEv }) => {
          const tone = toneForState(state);
          const roleText = stageRoleLabel(pip.key, locale);
          const bullet = BULLET_GLYPH[state];
          const title = `${pip.en} · ${locale === 'de' ? pip.de : pip.th}`;
          const showActiveChip = state === 'active' && activeActorName;
          const showLastDone = state === 'passed' && lastDoneEv;

          return (
            <Link
              key={pip.key}
              href={`/waybill/${waybillId}#pip-${pip.key}`}
              className={
                'group flex min-w-0 flex-col gap-1.5 rounded-2xl border p-3 transition h-full min-h-[124px] overflow-hidden ' +
                tone.card
              }
              aria-label={`${title} · ${roleText ?? ''}`}
            >
                <div className="flex items-center gap-2">
                  <span
                    aria-hidden
                    className={'flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-bold ' + tone.bullet}
                  >
                    {bullet}
                  </span>
                  <span aria-hidden className="text-lg leading-none">{pip.emoji}</span>
                  <span className="font-mono text-[10px] uppercase tracking-wider text-slate-500">
                    #{idx + 1}
                  </span>
                  <span
                    className={
                      'ml-auto inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ' +
                      tone.badge
                    }
                  >
                    <Bilingual en={PIP_BADGE_EN[state]} th={PIP_BADGE_TH[state]} de={PIP_BADGE_DE[state]} locale={locale} />
                  </span>
                </div>

                <h4 className={'text-[12px] font-bold leading-tight ' + tone.title}>
                  <Bilingual en={pip.en} th={pip.th} de={pip.de} locale={locale} />
                </h4>

                <p className="text-[10px] italic leading-snug text-slate-400">
                  <Bilingual en={pip.description_en} th={pip.description_th} locale={locale} />
                </p>

                <div className="mt-1 flex flex-wrap items-center gap-1.5">
                  <span className="inline-flex items-center gap-1 rounded-full border border-cyan-500/40 bg-cyan-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase tracking-widest text-cyan-200">
                    <span className="text-cyan-300/80">role:</span>
                    <span className="text-cyan-100">{roleText}</span>
                  </span>
                  {showActiveChip && (
                    <span className="inline-flex items-center gap-1 rounded-md border border-cyan-400/40 bg-cyan-500/10 px-1.5 py-0.5 text-[10px] font-mono text-cyan-200">
                      ⏱ {activeActorName}
                    </span>
                  )}
                </div>

                {showLastDone && lastDoneEv && (
                  <div className="mt-1 text-[10px] font-mono text-emerald-300/80">
                    ✓ {roleDisplay(lastDoneEv.actor_role, locale)}
                    {lastDoneEv.actor_id != null && (
                      <span className="text-emerald-400/70"> #{lastDoneEv.actor_id}</span>
                    )}
                    <span className="mx-1 text-slate-700">·</span>
                    <span>{fmtTs(lastDoneEv.occurred_at)}</span>
                  </div>
                )}
            </Link>
          );
        })}
      </div>
    </div>
  );
}