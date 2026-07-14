import React from 'react';
import type { WaybillAttachmentRow } from '@erp-lib/waybill/attachments';
import { findPip, bucketLabel } from '@erp-lib/waybill/derive';
import type { WaybillDomain } from '@erp-lib/waybill/derive';

import { AttachmentRow } from './AttachmentRow';
import { AttachmentUpload } from './AttachmentUpload';

export interface AttachmentListProps {
  waybillId: string;
  domain: WaybillDomain;
  currentStage: string;
  attachments: WaybillAttachmentRow[];
  canAttach: boolean;
  lang?: 'en' | 'th';
}

function fmtTime(t: Date | string): string {
  const d = t instanceof Date ? t : new Date(t);
  return Number.isFinite(d.getTime()) ? d.toLocaleString() : '—';
}

export function AttachmentList({
  waybillId,
  domain,
  currentStage,
  attachments,
  canAttach,
  lang = 'en',
}: AttachmentListProps) {
  const grouped = new Map<string, WaybillAttachmentRow[]>();
  for (const a of attachments) {
    const arr = grouped.get(a.stage_key) ?? [];
    arr.push(a);
    grouped.set(a.stage_key, arr);
  }

  const pips = (
    domain === 'expense'
      ? ['submission','dept_verification','dept_authorization','accounting_verification','accounting_supervision','accounting_authorization','disbursement_authorization','cfo_authorization','ceo_authorization','awaiting_disbursement','disbursed']
      : ['submission','dept_verification','accounting_authorization','cfo_authorization','disbursed']
  ) as string[];

  const groupOrder = pips.filter((p) => grouped.has(p));
  const total = attachments.length;

  return (
    <section className="space-y-3 rounded-2xl border border-slate-800 bg-slate-950/40 p-4 font-sans">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-bold text-white">
          📎 Attachments
          <span className="ml-2 font-mono text-xs text-slate-400">{total} total</span>
        </h3>
        <div className="text-xs font-mono text-slate-500">
          current stage: {currentStage}
        </div>
      </header>

      {canAttach && (
        <AttachmentUpload waybillId={waybillId} stage={currentStage} />
      )}

      {total === 0 && (
        <p className="text-xs italic text-slate-500">No documents attached yet.</p>
      )}

      {groupOrder.map((stageKey) => {
        const pip = findPip(domain, stageKey);
        const bucket = pip ? bucketLabel(pip.bucket, lang) : '';
        const items = grouped.get(stageKey)!;
        const stageHeading = pip
          ? `${pip.emoji} ${(lang === 'th' ? pip.th : pip.en)} — ${bucket}`
          : stageKey;
        const isCurrent = stageKey === currentStage;

        return (
          <details key={stageKey} open className="rounded-xl border border-slate-800/60 bg-slate-950/30">
            <summary className="flex cursor-pointer items-center justify-between gap-2 px-3 py-2 text-xs">
              <span className="font-bold text-white">
                {stageHeading}
                <span className="ml-2 font-mono text-xs text-slate-500">
                  ({items.length} file{items.length === 1 ? '' : 's'})
                </span>
              </span>
              <span className="font-mono text-xs text-slate-500">
                {isCurrent ? '★ current' : fmtTime(items[0]?.occurred_at ?? new Date())}
              </span>
            </summary>
            <div className="space-y-2 p-3">
              {items.map((a) => (
                <AttachmentRow key={a.id} waybillId={waybillId} attachment={a} />
              ))}
            </div>
          </details>
        );
      })}
    </section>
  );
}
