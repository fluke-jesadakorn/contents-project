'use client';

import React from 'react';

export type MobilePanel = 'chart' | 'drawer' | 'groups';

interface MobileTabsProps {
  active: MobilePanel;
  onChange: (panel: MobilePanel) => void;
  hasFocus: boolean;
  showGroups?: boolean;
}

export const MobileTabs: React.FC<MobileTabsProps> = ({ active, onChange, hasFocus, showGroups }) => (
  <nav
    className="flex md:hidden items-center gap-1 px-1 py-1 rounded-2xl bg-slate-950/60 border border-slate-800/80 shadow-inner shadow-black/40 mb-2"
    aria-label="Workspace panels"
  >
    {[
      { key: 'chart' as const, label: 'Chart', glyph: '📊' },
      { key: 'drawer' as const, label: 'Detail', glyph: '📋' },
      ...(showGroups ? [{ key: 'groups' as const, label: 'Groups', glyph: '🗂️' }] : []),
    ].map((t) => {
      const on = t.key === active;
      const disabled = t.key === 'drawer' && !hasFocus;
      return (
        <button
          key={t.key}
          type="button"
          onClick={() => !disabled && onChange(t.key)}
          disabled={disabled}
          aria-current={on ? 'page' : undefined}
          className={[
            'group relative flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-xl text-[11px] font-bold font-mono uppercase tracking-wider transition-all',
            on
              ? 'bg-indigo-500/20 text-white border border-indigo-400/40 shadow-sm shadow-indigo-900/40'
              : disabled
                ? 'text-slate-600 border border-transparent cursor-not-allowed'
                : 'text-slate-400 hover:text-white hover:bg-slate-900/60 border border-transparent',
          ].join(' ')}
          title={disabled ? `${t.label} (no focus)` : t.label}
        >
          <span className="text-[13px] leading-none">{t.glyph}</span>
          <span>{t.label}</span>
        </button>
      );
    })}
  </nav>
);