import React from 'react';
import type { PipState, WaybillStagePip } from '@erp-lib/waybill/derive';
import { bucketLabel, stageRoleLabel } from '@erp-lib/waybill/derive';
import type { SecondaryLocale } from '@erp-lib/server/locale';
import { pipBadge, toneForPip } from '../ui';
import { T } from '@/components/i18n/T';

interface Props {
  pip: WaybillStagePip;
  state: PipState;
  locale?: SecondaryLocale;
}

export function PipHeader({ pip, state, locale }: Props) {
  const localeSafe: SecondaryLocale = locale ?? 'th';
  const tone = toneForPip(state);
  const roleText = stageRoleLabel(pip.key, localeSafe);
  const bucketKind = bucketLabel(pip.bucket, localeSafe);

  return (
    <>
      <header className="flex flex-wrap items-center gap-2 text-xs">
        <span
          className={
            'inline-flex items-center gap-1 rounded border px-1.5 py-0.5 font-mono uppercase tracking-wider ' +
            tone.badge
          }
        >
          <span className="h-1.5 w-1.5 rounded-full bg-current" />
          {pipBadge(state, localeSafe)}
        </span>
        <span className="rounded border border-slate-700/60 bg-slate-900/60 px-1.5 py-0.5 font-mono uppercase text-slate-400">
          {bucketKind}
        </span>
        <span className="inline-flex items-center gap-1 rounded-full border border-cyan-500/40 bg-cyan-500/15 px-2 py-0.5 font-mono font-bold uppercase tracking-widest text-cyan-200">
          <span className="text-cyan-300/80">role:</span>
          <span className="text-cyan-100">{roleText}</span>
        </span>
        <span className="ml-auto font-mono text-xs uppercase text-slate-500">
          <T value={{ en: pip.en, th: pip.th, de: pip.de }} />
        </span>
      </header>

      <p className="truncate text-xs italic text-slate-400">
        {localeSafe === 'th' ? pip.description_th : pip.description_en}
      </p>
    </>
  );
}
