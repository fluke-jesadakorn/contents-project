'use client';

import React, { useEffect, useState } from 'react';
import { SECTION_CATALOG, type AITask } from '@/lib/ai/sections';

interface Provider { id: number; name: string; type: string }
interface Model { id: number; provider_id: number; name: string; capabilities: string[] }
interface Assignment {
  id: number;
  section_key: string;
  task_type: string;
  priority: number;
  enabled: boolean;
  provider_id: number | null;
  model_id: number | null;
  params_json: any;
}

const TASK_LIST: AITask[] = ['embed', 'chat', 'vision'];

export const SectionsPane: React.FC = () => {
  const [providers, setProviders] = useState<Provider[]>([]);
  const [models, setModels] = useState<Model[]>([]);
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [busyKey, setBusyKey] = useState<string | null>(null);

  async function load() {
    const [p, m, a] = await Promise.all([
      fetch('/api/ai/providers').then(r => r.json()),
      fetch('/api/ai/models').then(r => r.json()),
      fetch('/api/ai/assignments').then(r => r.json()),
    ]);
    setProviders(p.providers || []);
    setModels(m.models || []);
    setAssignments(a.assignments || []);
  }
  useEffect(() => { load(); }, []);

  function current(sectionKey: string, task: string): Assignment | undefined {
    return assignments.find(a => a.section_key === sectionKey && a.task_type === task && a.enabled);
  }

  async function assign(sectionKey: string, task: string, providerId: number | null, modelId: number | null) {
    const k = `${sectionKey}::${task}`;
    setBusyKey(k);
    try {
      await fetch('/api/ai/assignments', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ section_key: sectionKey, task_type: task, provider_id: providerId, model_id: modelId, priority: 100, enabled: true }),
      });
      await load();
    } finally { setBusyKey(null); }
  }

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-black text-white uppercase tracking-wider font-mono">Section Matrix</h3>
        <p className="text-[11px] text-slate-400 mt-0.5">Choose provider+model per section — each part of the system can use a different model</p>
      </div>

      <div className="overflow-x-auto rounded-2xl border border-slate-800">
        <table className="w-full text-xs">
          <thead className="bg-slate-950 text-slate-400 uppercase tracking-wider font-mono">
            <tr>
              <th className="text-left px-3 py-2">Section</th>
              <th className="text-left px-3 py-2">Task</th>
              <th className="text-left px-3 py-2">Provider</th>
              <th className="text-left px-3 py-2">Model</th>
              <th className="text-left px-3 py-2">Current</th>
            </tr>
          </thead>
          <tbody>
            {SECTION_CATALOG.map(s => (
              TASK_LIST.includes(s.task) && (
                <SectionRow
                  key={s.key}
                  sectionKey={s.key}
                  label={s.labelTh || s.label}
                  task={s.task}
                  providers={providers}
                  models={models}
                  currentAssignment={current(s.key, s.task)}
                  onAssign={(pid, mid) => assign(s.key, s.task, pid, mid)}
                  busy={busyKey === `${s.key}::${s.task}`}
                />
              )
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

interface RowProps {
  sectionKey: string;
  label: string;
  task: string;
  providers: Provider[];
  models: Model[];
  currentAssignment?: Assignment;
  onAssign: (providerId: number | null, modelId: number | null) => void;
  busy: boolean;
}

const SectionRow: React.FC<RowProps> = ({ sectionKey, label, task, providers, models, currentAssignment, onAssign, busy }) => {
  const [providerId, setProviderId] = useState<string>(currentAssignment?.provider_id?.toString() || '');
  const [modelId, setModelId] = useState<string>(currentAssignment?.model_id?.toString() || '');
  const available = models.filter(m => (!providerId || m.provider_id === parseInt(providerId, 10)) && m.capabilities.includes(task));

  React.useEffect(() => {
    if (!available.find(m => m.id.toString() === modelId)) setModelId('');
  }, [providerId]); // eslint-disable-line

  const providerName = providers.find(p => p.id === currentAssignment?.provider_id)?.name || '?';
  const modelName = models.find(m => m.id === currentAssignment?.model_id)?.name || '?';
  const currentLabel = currentAssignment ? `${providerName} / ${modelName}` : 'fallback (env)';

  return (
    <tr className="border-t border-slate-800/80 hover:bg-slate-950/40">
      <td className="px-3 py-2.5">
        <div className="font-mono text-slate-300">{sectionKey}</div>
        <div className="text-[10px] text-slate-500">{label}</div>
      </td>
      <td className="px-3 py-2.5"><span className="text-[10px] px-1.5 py-0.5 rounded bg-indigo-900/40 text-indigo-300 border border-indigo-700/40 font-mono">{task}</span></td>
      <td className="px-3 py-2.5">
        <select value={providerId} onChange={e => setProviderId(e.target.value)}
          className="w-full bg-slate-900 border border-slate-800 rounded px-2 py-1 text-xs text-white">
          <option value="">— fallback —</option>
          {providers.map(p => <option key={p.id} value={p.id}>{p.name} ({p.type})</option>)}
        </select>
      </td>
      <td className="px-3 py-2.5">
        <select value={modelId} onChange={e => setModelId(e.target.value)} disabled={!providerId}
          className="w-full bg-slate-900 border border-slate-800 rounded px-2 py-1 text-xs text-white disabled:opacity-40">
          <option value="">— pick —</option>
          {available.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
        </select>
      </td>
      <td className="px-3 py-2.5">
        <div className="flex items-center gap-2">
          <span className="text-[10px] text-slate-500 font-mono">{currentLabel}</span>
          <button
            type="button"
            onClick={() => onAssign(providerId ? parseInt(providerId, 10) : null, modelId ? parseInt(modelId, 10) : null)}
            disabled={busy || (!providerId && !modelId)}
            className="text-[10px] px-2 py-1 rounded bg-indigo-600 text-white font-bold hover:bg-indigo-500 disabled:opacity-40"
          >
            {busy ? '…' : 'Save'}
          </button>
        </div>
      </td>
    </tr>
  );
};