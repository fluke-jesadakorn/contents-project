import React from 'react';
import type { WaybillEventRow } from '@erp-lib/waybill/events';
import { loadWaybillEvents } from '@/lib/server/waybill';
import type { SecondaryLocale } from '@erp-lib/server/locale';
import { ZoneSection } from '../ZoneSection';
import { eventKindLabel } from '../ui';
import { formatDateServer } from '@/components/i18n/formattersServer';

function ActedPipEvents({ events, locale }: { events: WaybillEventRow[]; locale: SecondaryLocale }) {
  const sorted = events.slice().sort((a, b) => a.sequence - b.sequence);
  const visible = sorted.slice(0, 3);
  const rest = sorted.slice(3);
  if (sorted.length === 0) {
    return (
      <p className="text-sm italic text-slate-500">
        {locale === 'th' ? 'ยังไม่มีเหตุการณ์ที่ pip นี้' : 'no events recorded at this pip yet'}
      </p>
    );
  }
  return (
    <div>
      <ol className="space-y-1.5">
        {visible.map((e) => (
          <li key={e.id} className="text-xs font-mono text-slate-300">
            <span className="text-cyan-400">#{e.sequence}</span>
            <span className="mx-2 text-slate-700">·</span>
            <span className="font-bold text-white">{eventKindLabel(e.kind, locale)}</span>
            {e.stage_from || e.stage_to ? (
              <span className="ml-2 text-slate-400">
                {e.stage_from ?? '—'} →{' '}
                <span className="text-cyan-300">{e.stage_to ?? '—'}</span>
              </span>
            ) : null}
            {e.actor_id != null && (
              <span className="ml-2 text-slate-500">
                by {e.actor_role ?? '—'} <span className="text-slate-400">#{e.actor_id}</span>
              </span>
            )}
            <span className="ml-2 text-slate-500">{formatDateServer(e.occurred_at, locale)}</span>
          </li>
        ))}
      </ol>
      {rest.length > 0 && (
        <details className="mt-2">
          <summary className="cursor-pointer list-none text-[10px] font-mono uppercase tracking-widest text-cyan-300 hover:text-cyan-200 [&::-webkit-details-marker]:hidden">
            ▶ {locale === 'th' ? `แสดงทั้งหมด (+${rest.length})` : `Show all (+${rest.length} more)`}
          </summary>
          <ol className="mt-2 space-y-1.5">
            {rest.map((e) => (
              <li key={e.id} className="text-xs font-mono text-slate-300">
                <span className="text-cyan-400">#{e.sequence}</span>
                <span className="mx-2 text-slate-700">·</span>
                <span className="font-bold text-white">{eventKindLabel(e.kind, locale)}</span>
                {e.stage_from || e.stage_to ? (
                  <span className="ml-2 text-slate-400">
                    {e.stage_from ?? '—'} →{' '}
                    <span className="text-cyan-300">{e.stage_to ?? '—'}</span>
                  </span>
                ) : null}
                {e.actor_id != null && (
                  <span className="ml-2 text-slate-500">
                    by {e.actor_role ?? '—'} <span className="text-slate-400">#{e.actor_id}</span>
                  </span>
                )}
                <span className="ml-2 text-slate-500">{formatDateServer(e.occurred_at, locale)}</span>
              </li>
            ))}
          </ol>
        </details>
      )}
    </div>
  );
}

interface Props {
  waybillId: string;
  pipKey: string;
  locale?: SecondaryLocale;
}

export async function PipActivity({ waybillId, pipKey, locale }: Props) {
  const localeSafe: SecondaryLocale = locale ?? 'th';
  const all = await loadWaybillEvents(waybillId);
  const events = all.filter((e) => e.stage_to === pipKey);
  if (events.length === 0) return null;
  const latest = events.slice().sort((a, b) => a.sequence - b.sequence).slice(-1)[0];
  return (
    <ZoneSection
      icon={<span aria-hidden>⚡</span>}
      label={localeSafe === 'th' ? 'กิจกรรม' : 'Activity'}
      count={events.length}
      meta={
        events.length > 0
          ? `${localeSafe === 'th' ? 'ล่าสุด' : 'latest'} · ${formatDateServer(latest?.occurred_at ?? null, localeSafe)}`
          : undefined
      }
      tone="emerald"
    >
      <ActedPipEvents events={events} locale={localeSafe} />
    </ZoneSection>
  );
}
