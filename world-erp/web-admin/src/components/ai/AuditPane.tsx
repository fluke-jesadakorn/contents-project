'use client';

import React, { useEffect, useState } from 'react';

interface Invocation {
  id: number;
  section_key: string;
  task_type: string;
  status: string;
  error: string | null;
  prompt_tokens: number | null;
  response_tokens: number | null;
  latency_ms: number | null;
  prompt_excerpt: string | null;
  response_excerpt: string | null;
  created_at: string;
  provider_name: string | null;
  model_name: string | null;
  staff_name: string | null;
  actor_name: string | null;
}

export const AuditPane: React.FC = () => {
  const [items, setItems] = useState<Invocation[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterSection, setFilterSection] = useState('');

  async function load() {
    setLoading(true);
    const qs = new URLSearchParams();
    if (filterSection) qs.set('section', filterSection);
    qs.set('limit', '100');
    const res = await fetch(`/api/ai/invocations?${qs}`);
    const data = await res.json();
    setItems(data.invocations || []);
    setLoading(false);
  }
  useEffect(() => { load(); }, [filterSection]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <div>
          <h3 className="text-sm font-black text-white uppercase tracking-wider font-mono">Audit Log</h3>
          <p className="text-[11px] text-slate-400 mt-0.5">Every AI invocation is logged here — inspect latency, errors, and token usage</p>
        </div>
        <div className="flex gap-2 items-center">
          <input value={filterSection} onChange={e => setFilterSection(e.target.value)} placeholder="filter section_key"
            className="bg-slate-900 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white font-mono w-48" />
          <button onClick={load} className="text-xs px-3 py-1.5 rounded-lg bg-slate-800 text-slate-300 hover:text-white">Refresh</button>
        </div>
      </div>

      {loading ? (
        <p className="text-xs text-slate-400">Loading…</p>
      ) : items.length === 0 ? (
        <p className="text-xs text-slate-500 italic">No logs yet</p>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-slate-800">
          <table className="w-full text-xs">
            <thead className="bg-slate-950 text-slate-400 uppercase tracking-wider font-mono">
              <tr>
                <th className="text-left px-3 py-2">When</th>
                <th className="text-left px-3 py-2">Section / Task</th>
                <th className="text-left px-3 py-2">Provider / Model</th>
                <th className="text-left px-3 py-2">Staff</th>
                <th className="text-left px-3 py-2">Tokens</th>
                <th className="text-left px-3 py-2">Latency</th>
                <th className="text-left px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {items.map(i => (
                <tr key={i.id} className="border-t border-slate-800/80 hover:bg-slate-950/40">
                  <td className="px-3 py-2 font-mono text-[10px] text-slate-400">{new Date(i.created_at).toLocaleString()}</td>
                  <td className="px-3 py-2">
                    <div className="font-mono text-slate-200 text-[10px]">{i.section_key}</div>
                    <div className="text-[9px] text-slate-500">{i.task_type}</div>
                  </td>
                  <td className="px-3 py-2">
                    <div className="text-[10px] text-slate-300">{i.provider_name || '—'}</div>
                    <div className="text-[9px] text-slate-500 font-mono">{i.model_name || '—'}</div>
                  </td>
                  <td className="px-3 py-2 text-[10px] text-slate-300">{i.staff_name || '—'}</td>
                  <td className="px-3 py-2 text-[10px] font-mono text-slate-400">
                    {(i.prompt_tokens || 0) + (i.response_tokens || 0)} <span className="text-slate-600">(p:{i.prompt_tokens || 0}, r:{i.response_tokens || 0})</span>
                  </td>
                  <td className="px-3 py-2 text-[10px] font-mono text-slate-400">{i.latency_ms ? `${i.latency_ms}ms` : '—'}</td>
                  <td className="px-3 py-2">
                    <span className={`text-[9px] px-1.5 py-0.5 rounded font-mono font-bold ${
                      i.status === 'ok' ? 'bg-emerald-950/40 text-emerald-300 border border-emerald-700/40' : 'bg-rose-950/40 text-rose-300 border border-rose-700/40'
                    }`}>{i.status}</span>
                    {i.error && <div className="text-[9px] text-rose-400 mt-1 max-w-xs truncate" title={i.error}>{i.error}</div>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};