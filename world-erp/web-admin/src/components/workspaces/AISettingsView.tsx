'use client';

import React, { useEffect, useState } from 'react';
import { ProvidersPane } from '@/components/ai/ProvidersPane';
import { ModelsPane } from '@/components/ai/ModelsPane';
import { SectionsPane } from '@/components/ai/SectionsPane';
import { StaffPane } from '@/components/ai/StaffPane';
import { AuditPane } from '@/components/ai/AuditPane';
import { SectionHealthPane } from '@/components/ai/SectionHealthPane';

type Tab = 'providers' | 'sections' | 'coverage' | 'staff' | 'audit';

const TABS: { key: Tab; label: string; labelTh: string; glyph: string }[] = [
  { key: 'providers', label: 'Providers & Models', labelTh: 'Providers & Models', glyph: '🔌' },
  { key: 'sections',  label: 'Section Matrix',     labelTh: 'Section Model Selection', glyph: '🧭' },
  { key: 'coverage',  label: 'Coverage',           labelTh: 'AI Coverage Audit', glyph: '🩺' },
  { key: 'staff',     label: 'AI Staff',           labelTh: 'AI Staff', glyph: '🤖' },
  { key: 'audit',     label: 'Audit Log',          labelTh: 'Invocation Log', glyph: '📜' },
];

export const AISettingsView: React.FC = () => {
  const [tab, setTab] = useState<Tab>('providers');
  const [providers, setProviders] = useState<{ id: number; name: string }[]>([]);

  async function loadProviders() {
    const res = await fetch('/api/ai/providers');
    const data = await res.json();
    setProviders((data.providers || []).map((p: any) => ({ id: p.id, name: p.name })));
  }
  useEffect(() => { loadProviders(); }, []);

  return (
    <div className="space-y-5 animate-fade-in">
      <div className="flex flex-col gap-1">
        <h2 className="text-2xl font-black tracking-tight text-white">AI Settings</h2>
        <p className="text-xs text-slate-400">
          Manage AI providers, select distinct models per section, create AI staff, and review the audit log
        </p>
      </div>

      <div className="flex gap-1 p-1 rounded-2xl bg-slate-950/60 border border-slate-800/80 w-fit">
        {TABS.map(t => (
          <button key={t.key} type="button" onClick={() => setTab(t.key)}
            className={[
              'flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[11px] font-bold font-mono uppercase tracking-wider transition-all',
              tab === t.key ? 'bg-indigo-500/20 text-white border border-indigo-400/40' : 'text-slate-400 hover:text-white hover:bg-slate-900/60 border border-transparent',
            ].join(' ')}>
            <span>{t.glyph}</span>
            <span>{t.labelTh}</span>
          </button>
        ))}
      </div>

      {tab === 'providers' && (
        <div className="space-y-6">
          <ProvidersPane />
          <div className="border-t border-slate-800/80 pt-6">
            <ModelsPane providers={providers} />
          </div>
        </div>
      )}
      {tab === 'sections' && <SectionsPane />}
      {tab === 'coverage' && <SectionHealthPane />}
      {tab === 'staff'    && <StaffPane />}
      {tab === 'audit'    && <AuditPane />}
    </div>
  );
};