'use client';

import React, { useEffect, useMemo, useState } from 'react';

type Bucket = 'ACTIVE' | 'DORMANT' | 'NEVER_CALLED' | 'UNCONFIGURED' | 'ORPHAN';

interface HealthRow {
  bucket: Bucket;
  section_key: string;
  label: string;
  label_th: string;
  task: string;
  provider_name: string | null;
  model_name: string | null;
  ok_calls: number;
  err_calls: number;
  total_calls: number;
  last_invocation_at: string | null;
  first_invocation_at: string | null;
  assignment_enabled: boolean | null;
}

interface HealthResponse {
  generated_at: string;
  active_window_days: number;
  catalog_total: number;
  totals: Record<Bucket, number>;
  coverage_pct: number;
  sections: HealthRow[];
}

const BUCKET_ORDER: Bucket[] = ['NEVER_CALLED', 'UNCONFIGURED', 'DORMANT', 'ORPHAN', 'ACTIVE'];

const BUCKET_STYLE: Record<Bucket, { label: string; glyph: string; cls: string }> = {
  NEVER_CALLED: { label: 'NEVER_CALLED', glyph: '🔴', cls: 'bg-rose-950/40 text-rose-300 border-rose-700/40' },
  UNCONFIGURED: { label: 'UNCONFIGURED', glyph: '⚪', cls: 'bg-slate-800/60 text-slate-300 border-slate-700/40' },
  DORMANT:      { label: 'DORMANT',      glyph: '🟡', cls: 'bg-amber-950/40 text-amber-300 border-amber-700/40' },
  ORPHAN:       { label: 'ORPHAN',       glyph: '🟣', cls: 'bg-fuchsia-950/40 text-fuchsia-300 border-fuchsia-700/40' },
  ACTIVE:       { label: 'ACTIVE',       glyph: '🟢', cls: 'bg-emerald-950/40 text-emerald-300 border-emerald-700/40' },
};

const TASK_STYLE: Record<string, string> = {
  vision: 'bg-fuchsia-900/40 text-fuchsia-300 border-fuchsia-700/40',
  embed:  'bg-cyan-900/40 text-cyan-300 border-cyan-700/40',
  chat:   'bg-indigo-900/40 text-indigo-300 border-indigo-700/40',
};

function fmtDateTime(s: string | null) {
  if (!s) return '—';
  const d = new Date(s);
  return d.toLocaleString('en-GB', {
    year: 'numeric', month: 'short', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });
}

function ageLabel(s: string | null) {
  if (!s) return '—';
  const ms = Date.now() - new Date(s).getTime();
  const m = Math.floor(ms / 60000);
  if (m < 1) return 'just now';
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  if (d < 30) return `${d}d ago`;
  return `${Math.floor(d / 30)}mo ago`;
}

export const SectionHealthPane: React.FC = () => {
  const [data, setData] = useState<HealthResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<Bucket | 'ALL'>('ALL');

  async function load() {
    setLoading(true);
    try {
      const res = await fetch('/api/ai/sections/health');
      const json = await res.json();
      setData(json);
    } finally { setLoading(false); }
  }
  useEffect(() => { load(); }, []);

  const rows = useMemo(() => {
    if (!data) return [];
    const filtered = filter === 'ALL' ? data.sections : data.sections.filter(s => s.bucket === filter);
    return [...filtered].sort((a, b) => {
      const ai = BUCKET_ORDER.indexOf(a.bucket);
      const bi = BUCKET_ORDER.indexOf(b.bucket);
      if (ai !== bi) return ai - bi;
      return a.section_key.localeCompare(b.section_key);
    });
  }, [data, filter]);

  if (loading || !data) {
    return <p className="text-xs text-slate-400">Loading coverage report…</p>;
  }

  const t = data.totals;
  const healthy = t.NEVER_CALLED === 0 && t.UNCONFIGURED === 0;

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-1">
        <h3 className="text-sm font-black text-white uppercase tracking-wider font-mono">AI Coverage Audit</h3>
        <p className="text-sm text-slate-400">
          DB is the source of truth. ACTIVE = invoked within the last {data.active_window_days} days · NEVER_CALLED = configured but zero invocations · UNCONFIGURED = in catalog but no assignment row · ORPHAN = invoked but not in catalog or assignments.
        </p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {BUCKET_ORDER.map(b => {
          const s = BUCKET_STYLE[b];
          const n = t[b] || 0;
          return (
            <div key={b} className={`rounded-2xl border p-3 ${s.cls}`}>
              <div className="flex items-center gap-1.5 text-xs font-mono font-bold uppercase">
                <span>{s.glyph}</span>
                <span>{s.label}</span>
              </div>
              <div className="text-2xl font-black font-mono mt-1">{n}</div>
            </div>
          );
        })}
      </div>

      <div className="flex flex-wrap items-center gap-3 justify-between">
        <div className="text-xs font-mono">
          <span className="text-slate-400">Coverage: </span>
          <span className={healthy ? 'text-emerald-300 font-bold' : 'text-amber-300 font-bold'}>
            {t.ACTIVE} / {data.catalog_total} ({data.coverage_pct}%)
          </span>
        </div>
        <div className="flex flex-wrap gap-1">
          {(['ALL', ...BUCKET_ORDER] as const).map(b => {
            const active = filter === b;
            const label = b === 'ALL' ? `All (${data.sections.length})` : `${BUCKET_STYLE[b].glyph} ${b} (${t[b] || 0})`;
            return (
              <button
                key={b}
                type="button"
                onClick={() => setFilter(b)}
                className={[
                  'text-xs font-mono uppercase tracking-wider px-2 py-1 rounded-lg border',
                  active
                    ? 'bg-indigo-500/20 text-white border-indigo-400/40'
                    : 'bg-slate-900/60 text-slate-300 border-slate-800 hover:text-white',
                ].join(' ')}
              >
                {label}
              </button>
            );
          })}
        </div>
      </div>

      {healthy ? (
        <div className="rounded-2xl border border-emerald-700/40 bg-emerald-950/30 p-4 text-xs text-emerald-200 font-mono">
          All catalog sections are configured and have been invoked within the last {data.active_window_days} days.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-slate-800">
          <table className="w-full text-xs">
            <thead className="bg-slate-950 text-slate-400 uppercase tracking-wider font-mono">
              <tr>
                <th className="text-left px-3 py-2">Bucket</th>
                <th className="text-left px-3 py-2">Section</th>
                <th className="text-left px-3 py-2">Task</th>
                <th className="text-left px-3 py-2">Provider / Model</th>
                <th className="text-right px-3 py-2">OK</th>
                <th className="text-right px-3 py-2">Err</th>
                <th className="text-right px-3 py-2">Total</th>
                <th className="text-left px-3 py-2">Last call</th>
                <th className="text-left px-3 py-2">First call</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => {
                const bs = BUCKET_STYLE[r.bucket];
                const ts = TASK_STYLE[r.task] || 'bg-slate-800 text-slate-300 border-slate-700';
                const pm = r.provider_name && r.model_name ? `${r.provider_name} / ${r.model_name}` : '—';
                return (
                  <tr key={`${r.bucket}:${r.section_key}`} className="border-t border-slate-800/80 hover:bg-slate-950/40">
                    <td className="px-3 py-2">
                      <span className={`text-xs px-1.5 py-0.5 rounded font-mono font-bold border ${bs.cls}`}>
                        {bs.glyph} {bs.label}
                      </span>
                    </td>
                    <td className="px-3 py-2">
                      <div className="font-mono text-slate-200 text-sm">{r.section_key}</div>
                      <div className="text-xs text-slate-500">{r.label_th}</div>
                    </td>
                    <td className="px-3 py-2">
                      <span className={`text-xs px-1.5 py-0.5 rounded font-mono border ${ts}`}>{r.task}</span>
                    </td>
                    <td className="px-3 py-2">
                      <div className="text-sm text-slate-300">{pm}</div>
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-emerald-300">{r.ok_calls}</td>
                    <td className="px-3 py-2 text-right font-mono text-rose-300">{r.err_calls}</td>
                    <td className="px-3 py-2 text-right font-mono text-slate-200">{r.total_calls}</td>
                    <td className="px-3 py-2 font-mono text-xs text-slate-400" title={fmtDateTime(r.last_invocation_at)}>
                      {ageLabel(r.last_invocation_at)}
                    </td>
                    <td className="px-3 py-2 font-mono text-xs text-slate-500" title={fmtDateTime(r.first_invocation_at)}>
                      {r.first_invocation_at ? new Date(r.first_invocation_at).toLocaleDateString() : '—'}
                    </td>
                  </tr>
                );
              })}
              {rows.length === 0 && (
                <tr>
                  <td colSpan={9} className="px-3 py-6 text-center text-sm text-slate-500 font-mono italic">
                    No rows for this filter.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      <div className="text-xs text-slate-500 font-mono">
        Generated {fmtDateTime(data.generated_at)} · window {data.active_window_days}d
      </div>
    </div>
  );
};