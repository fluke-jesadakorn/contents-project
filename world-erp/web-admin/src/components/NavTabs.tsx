'use client';

import React from 'react';
import { getAllowedTabs, type RoleName, type TabName } from '@/lib/permissions';

const TABS: { key: TabName; th: string; en: string; glyph: string }[] = [
  { key: 'workbench', th: 'Workbench', en: 'workbench', glyph: '🧰' },
  { key: 'pr',        th: 'PR',        en: 'pr',        glyph: '🛒' },
  { key: 'ledger',    th: 'Ledger',    en: 'ledger',    glyph: '📒' },
  { key: 'cockpit',   th: 'Cockpit',   en: 'cockpit',   glyph: '📊' },
  { key: 'policy',    th: 'Policy',    en: 'policy',    glyph: '⚙️' },
  { key: 'hr',        th: 'HR',        en: 'hr',        glyph: '👥' },
];

interface NavTabsProps {
  role: RoleName | undefined;
  activeTab: TabName;
  setActiveTab: (t: TabName) => void;
  countByTab?: Partial<Record<TabName, number>>;
}

export const NavTabs: React.FC<NavTabsProps> = ({ role, activeTab, setActiveTab, countByTab }) => {
  const allowed = new Set(getAllowedTabs(role));
  const visible = TABS.filter((t) => allowed.has(t.key));
  if (visible.length === 0) return null;

  return (
    <nav
      className="hidden md:flex items-center gap-1 mx-2 px-1 py-1 rounded-2xl bg-slate-950/60 border border-slate-800/80 shadow-inner shadow-black/40"
      aria-label="Primary"
    >
      {visible.map((t) => {
        const active = activeTab === t.key;
        const count = countByTab?.[t.key];
        return (
          <button
            key={t.key}
            type="button"
            onClick={() => setActiveTab(t.key)}
            aria-current={active ? 'page' : undefined}
            className={[
              'group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[11px] font-bold font-mono uppercase tracking-wider transition-all',
              active
                ? 'bg-indigo-500/20 text-white border border-indigo-400/40 shadow-sm shadow-indigo-900/40'
                : 'text-slate-400 hover:text-white hover:bg-slate-900/60 border border-transparent',
            ].join(' ')}
          >
            <span className="text-[13px] leading-none">{t.glyph}</span>
            <span>{t.th}</span>
            {typeof count === 'number' && count > 0 && (
              <span
                className={[
                  'min-w-[18px] px-1.5 h-4 inline-flex items-center justify-center rounded-full text-[9px] font-mono font-black',
                  active ? 'bg-indigo-400 text-indigo-950' : 'bg-slate-800 text-slate-300',
                ].join(' ')}
              >
                {count}
              </span>
            )}
          </button>
        );
      })}
    </nav>
  );
};

export type MobileTabsProps = NavTabsProps;

export const MobileTabs: React.FC<MobileTabsProps> = ({ role, activeTab, setActiveTab }) => {
  const allowed = new Set(getAllowedTabs(role));
  const visible = TABS.filter((t) => allowed.has(t.key));
  if (visible.length === 0) return null;
  return (
    <div className="flex flex-col gap-1">
      {visible.map((t) => {
        const active = activeTab === t.key;
        return (
          <button
            key={t.key}
            type="button"
            onClick={() => setActiveTab(t.key)}
            className={[
              'w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-bold transition-all',
              active
                ? 'bg-indigo-500/20 text-white border border-indigo-400/40'
                : 'text-slate-300 hover:text-white hover:bg-slate-900/60 border border-transparent',
            ].join(' ')}
          >
            <span className="text-lg leading-none">{t.glyph}</span>
            <span>{t.th}</span>
          </button>
        );
      })}
    </div>
  );
};
