'use client';

import React, { useEffect, useState } from 'react';
import { useDialog, useToast } from '@/components/ui';

export interface Model {
  id: number;
  provider_id: number;
  name: string;
  capabilities: string[];
  context_window: number | null;
  defaults_json: any;
  enabled: boolean;
}

interface Props {
  providers: { id: number; name: string }[];
}

const CAPABILITY_OPTIONS = ['embed', 'chat', 'vision'];

export const ModelsPane: React.FC<Props> = ({ providers }) => {
  const dialog = useDialog();
  const toast = useToast();
  const [models, setModels] = useState<Model[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Model | null>(null);
  const [creating, setCreating] = useState(false);
  const [providerId, setProviderId] = useState<number | ''>('');
  const [name, setName] = useState('');
  const [caps, setCaps] = useState<string[]>([]);
  const [context, setContext] = useState<string>('');
  const [temp, setTemp] = useState<string>('');
  const [maxTok, setMaxTok] = useState<string>('');

  async function load() {
    setLoading(true);
    try {
      const res = await fetch('/api/ai/models');
      const data = await res.json();
      setModels(data.models || []);
    } finally { setLoading(false); }
  }
  useEffect(() => { load(); }, []);

  function startCreate() {
    setCreating(true);
    setEditing(null);
    setProviderId(providers[0]?.id || '');
    setName(''); setCaps([]); setContext(''); setTemp(''); setMaxTok('');
  }

  function startEdit(m: Model) {
    setEditing(m);
    setCreating(false);
    setProviderId(m.provider_id);
    setName(m.name);
    setCaps(m.capabilities || []);
    setContext(m.context_window?.toString() || '');
    const d = m.defaults_json || {};
    setTemp(d.temperature?.toString() || '');
    setMaxTok(d.max_tokens?.toString() || '');
  }

  async function save() {
    const body: any = {
      provider_id: Number(providerId),
      name,
      capabilities: caps,
      enabled: true,
    };
    if (context) body.context_window = parseInt(context, 10);
    const d: any = {};
    if (temp) d.temperature = parseFloat(temp);
    if (maxTok) d.max_tokens = parseInt(maxTok, 10);
    body.defaults_json = d;
    const url = editing ? `/api/ai/models/${editing.id}` : '/api/ai/models';
    const method = editing ? 'PUT' : 'POST';
    const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    if (!res.ok) { toast.error('Save failed', 'Error'); return; }
    toast.success(`Model "${name}" saved`, 'AI Model');
    setEditing(null); setCreating(false); load();
  }

  async function remove(m: Model) {
    const ok = await dialog.confirm({
      title: `Delete model "${m.name}"?`,
      message: 'Section assignments pointing to this model will fall back to env defaults.',
      confirmLabel: 'Delete',
      tone: 'rose',
      variant: 'danger',
    });
    if (!ok) return;
    const r = await fetch(`/api/ai/models/${m.id}`, { method: 'DELETE' });
    if (r.ok) toast.success(`Model "${m.name}" deleted`, 'AI Model');
    else toast.error('Delete failed', 'Error');
    load();
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <div>
          <h3 className="text-sm font-black text-white uppercase tracking-wider font-mono">Models</h3>
          <p className="text-sm text-slate-400 mt-0.5">Each model has capabilities (embed/chat/vision) and default parameters</p>
        </div>
        {!creating && !editing && (
          <button onClick={startCreate} disabled={providers.length === 0} className="text-xs px-3 py-1.5 rounded-lg bg-indigo-600 text-white font-bold hover:bg-indigo-500 disabled:opacity-40">
            + Add Model
          </button>
        )}
      </div>

      {(creating || editing) && (
        <div className="bg-slate-950 border border-slate-800 rounded-2xl p-5 space-y-3">
          <h4 className="text-sm font-black text-white uppercase tracking-wider font-mono">{editing ? 'Edit Model' : 'Add Model'}</h4>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <label className="space-y-1">
              <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Provider</span>
              <select value={providerId} onChange={e => setProviderId(e.target.value as any)} className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white">
                {providers.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </label>
            <label className="space-y-1">
              <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Name</span>
              <input value={name} onChange={e => setName(e.target.value)} placeholder="gpt-4o-mini"
                className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white font-mono" />
            </label>
            <label className="space-y-1 md:col-span-2">
              <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Capabilities</span>
              <div className="flex gap-2">
                {CAPABILITY_OPTIONS.map(c => (
                  <label key={c} className="flex items-center gap-1 text-xs text-slate-300">
                    <input type="checkbox" checked={caps.includes(c)} onChange={e => setCaps(p => e.target.checked ? [...p, c] : p.filter(x => x !== c))} />
                    {c}
                  </label>
                ))}
              </div>
            </label>
            <label className="space-y-1">
              <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Context window</span>
              <input value={context} onChange={e => setContext(e.target.value)} placeholder="8192" type="number"
                className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
            </label>
            <label className="space-y-1">
              <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Default temperature</span>
              <input value={temp} onChange={e => setTemp(e.target.value)} placeholder="0.7" type="number" step="0.1"
                className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
            </label>
            <label className="space-y-1">
              <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Default max_tokens</span>
              <input value={maxTok} onChange={e => setMaxTok(e.target.value)} placeholder="1024" type="number"
                className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
            </label>
          </div>
          <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
            <button onClick={() => { setEditing(null); setCreating(false); }} className="px-4 py-2 rounded-lg bg-slate-800 text-slate-300 text-xs font-bold">Cancel</button>
            <button onClick={save} className="px-4 py-2 rounded-lg bg-indigo-600 text-white text-xs font-bold">Save</button>
          </div>
        </div>
      )}

      {loading ? (
        <p className="text-xs text-slate-400">Loading…</p>
      ) : models.length === 0 ? (
        <p className="text-xs text-slate-500 italic">No models yet</p>
      ) : (
        <div className="space-y-1.5">
          {models.map(m => {
            const pname = providers.find(p => p.id === m.provider_id)?.name || `#${m.provider_id}`;
            return (
              <div key={m.id} className="flex items-center gap-3 bg-slate-950/60 border border-slate-800/80 rounded-xl px-3 py-2">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono font-bold text-white truncate">{m.name}</span>
                    <span className="text-xs px-1.5 py-0.5 rounded bg-slate-800 text-slate-400">{pname}</span>
                  </div>
                  <div className="flex gap-1 mt-1">
                    {(m.capabilities || []).map(c => (
                      <span key={c} className="text-xs px-1.5 py-0.5 rounded bg-indigo-900/40 text-indigo-300 border border-indigo-700/40 font-mono">{c}</span>
                    ))}
                    {m.context_window && <span className="text-xs px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 font-mono">ctx {m.context_window}</span>}
                  </div>
                </div>
                <button onClick={() => startEdit(m)} className="text-xs px-2 py-1 rounded bg-slate-800 text-slate-300 hover:text-white">Edit</button>
                <button onClick={() => remove(m)} className="text-xs px-2 py-1 rounded bg-rose-950/40 text-rose-300 border border-rose-900/40">Delete</button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};