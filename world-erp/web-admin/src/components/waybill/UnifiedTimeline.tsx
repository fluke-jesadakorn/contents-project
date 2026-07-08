import React from 'react';
import type { WaybillEventRow } from '@erp-lib/waybill/events';
import type { WaybillAttachmentRow } from '@erp-lib/waybill/attachments';

interface Props {
  waybillId: string;
  merged: Array<{
    kind: 'event' | 'attachment';
    at: Date;
    event?: WaybillEventRow;
    attachment?: WaybillAttachmentRow;
  }>;
}

function fmt(t: Date | string): string {
  const d = t instanceof Date ? t : new Date(t);
  return d.toLocaleString();
}

function fmtSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

export function UnifiedTimeline({ waybillId, merged }: Props) {
  if (merged.length === 0) {
    return <p className="text-xs italic text-slate-500">No history yet.</p>;
  }
  return (
    <section className="space-y-3 rounded-2xl border border-slate-800 bg-slate-950/40 p-4 font-sans">
      <header className="flex items-center justify-between">
        <h3 className="text-sm font-bold text-white">
          ⏱ Unified Timeline
          <span className="ml-2 font-mono text-[10px] text-slate-400">
            ({merged.length} items · newest first)
          </span>
        </h3>
        <span className="font-mono text-[10px] text-slate-500">
          ✓ events · ✔ attachments
        </span>
      </header>
      <ol className="border-l-2 border-slate-800 pl-3">
        {merged.map((row, i) => {
          if (row.kind === 'event' && row.event) {
            const e = row.event;
            return (
              <li key={`e-${e.id}-${i}`} className="relative py-1.5">
                <span className="absolute -left-[15px] top-2 inline-block h-2 w-2 rounded-full bg-cyan-400" />
                <div className="text-[11px] font-mono">
                  <span className="rounded bg-cyan-500/15 px-1.5 py-0.5 text-cyan-200">
                    ✓ #{e.sequence}
                  </span>{' '}
                  <span className="font-bold text-slate-200">{e.kind}</span>{' '}
                  <span className="text-slate-400">
                    {e.stage_from && e.stage_to ? `${e.stage_from} → ${e.stage_to}` : ''}
                  </span>
                  {e.actor_id != null && (
                    <span className="ml-2 text-slate-500">actor: {e.actor_role ?? '?'} #{e.actor_id}</span>
                  )}
                  <span className="ml-2 text-slate-500">{fmt(e.occurred_at)}</span>
                </div>
              </li>
            );
          }
          const a = row.attachment!;
          const dl = `/api/waybill/${waybillId}/attachments/file?key=${encodeURIComponent(a.storage_key)}`;
          return (
            <li key={`a-${a.id}-${i}`} className="relative py-1.5">
              <span className="absolute -left-[15px] top-2 inline-block h-2 w-2 rounded-full bg-amber-300" />
              <div className="text-[11px] font-mono">
                <span className="rounded bg-amber-500/15 px-1.5 py-0.5 text-amber-200">✔ attachment</span>{' '}
                <a className="text-cyan-200 underline-offset-2 hover:underline" href={dl}>
                  {a.filename}
                </a>{' '}
                <span className="text-slate-400">{fmtSize(a.byte_size)}</span>{' '}
                <span className="text-slate-500">
                  · {a.kind} · stage: {a.stage_key} · {a.uploaded_role} #{a.uploaded_by}
                </span>
                <span className="ml-2 text-slate-500">{fmt(a.occurred_at)}</span>
              </div>
              {a.caption && (
                <p className="ml-3 mt-0.5 text-[10px] italic text-slate-400">“{a.caption}”</p>
              )}
            </li>
          );
        })}
      </ol>
    </section>
  );
}
