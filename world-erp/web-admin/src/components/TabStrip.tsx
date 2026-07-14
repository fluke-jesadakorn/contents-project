'use client';

import React from 'react';

export interface FeatureTab<TId extends string = string> {
  id: TId;
  label: string;
  icon?: string;
  badge?: number | string;
  hidden?: boolean;
  tone?: 'neutral' | 'history';
}

interface TabStripProps<TId extends string> {
  tabs: FeatureTab<TId>[];
  active: TId;
  onChange: (id: TId) => void;
  className?: string;
}

export function TabStrip<TId extends string>({
  tabs,
  active,
  onChange,
  className = '',
}: TabStripProps<TId>) {
  const visible = tabs.filter((t) => !t.hidden);
  return (
    <div
      className={`flex flex-wrap items-center gap-1.5 p-1.5 rounded-2xl bg-slate-950/70 border border-slate-800/80 shadow-inner shadow-black/30 ${className}`}
      role="tablist"
    >
      {visible.map((t) => {
        const isActive = t.id === active;
        const isHistory = t.tone === 'history';
        return (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={isActive}
            onClick={() => onChange(t.id)}
            className={[
              'group flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-sm font-bold font-mono uppercase tracking-wider transition-all',
              isActive
                ? isHistory
                  ? 'bg-amber-500/20 text-white border border-amber-400/40 shadow-sm shadow-amber-900/40'
                  : 'bg-indigo-500/20 text-white border border-indigo-400/40 shadow-sm shadow-indigo-900/40'
                : isHistory
                  ? 'text-amber-300/70 hover:text-amber-200 hover:bg-amber-500/10 border border-transparent'
                  : 'text-slate-400 hover:text-white hover:bg-slate-900/60 border border-transparent',
            ].join(' ')}
          >
            {t.icon ? <span className="text-[13px] leading-none">{t.icon}</span> : null}
            <span>{t.label}</span>
            {typeof t.badge === 'number' && t.badge > 0 ? (
              <span
                className={[
                  'min-w-[18px] px-1.5 h-4 inline-flex items-center justify-center rounded-full text-xs font-mono font-black',
                  isActive
                    ? isHistory
                      ? 'bg-amber-400 text-amber-950'
                      : 'bg-indigo-400 text-indigo-950'
                    : 'bg-slate-800 text-slate-300',
                ].join(' ')}
              >
                {t.badge}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}

export default TabStrip;
