'use client';

import React, { useState } from 'react';
import { ProviderForm, type Provider } from './ProviderForm';
import { useDialog, useToast } from '@/components/ui';

export const ProvidersPane: React.FC = () => {
  const dialog = useDialog();
  const toast = useToast();
  const [providers, setProviders] = useState<Provider[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Provider | null>(null);
  const [creating, setCreating] = useState(false);

  async function load() {
    setLoading(true);
    try {
      const res = await fetch('/api/ai/providers');
      const data = await res.json();
      setProviders(data.providers || []);
    } finally { setLoading(false); }
  }
  React.useEffect(() => { load(); }, []);

  async function remove(p: Provider) {
    const ok = await dialog.confirm({
      title: `Delete provider "${p.name}"?`,
      message: 'All models and section assignments for this provider will be removed.',
      confirmLabel: 'Delete',
      tone: 'rose',
      variant: 'danger',
    });
    if (!ok) return;
    const r = await fetch(`/api/ai/providers/${p.id}`, { method: 'DELETE' });
    if (r.ok) toast.success(`Provider "${p.name}" deleted`, 'AI Provider');
    else toast.error('Delete failed', 'Error');
    load();
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <div>
          <h3 className="text-sm font-black text-white uppercase tracking-wider font-mono">Providers & Models</h3>
          <p className="text-sm text-slate-400 mt-0.5">Manage AI providers (Ollama, OpenAI-compat, MiniMax) and the models they use</p>
        </div>
        {!creating && !editing && (
          <button onClick={() => setCreating(true)} className="text-xs px-3 py-1.5 rounded-lg bg-indigo-600 text-white font-bold hover:bg-indigo-500">+ Add Provider</button>
        )}
      </div>

      {creating && <ProviderForm onSaved={() => { setCreating(false); load(); }} onCancel={() => setCreating(false)} />}
      {editing && <ProviderForm initial={editing} onSaved={() => { setEditing(null); load(); }} onCancel={() => setEditing(null)} />}

      {loading ? (
        <p className="text-xs text-slate-400">Loading…</p>
      ) : providers.length === 0 ? (
        <p className="text-xs text-slate-500 italic">No providers yet — add the first one to start using AI</p>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
          {providers.map(p => (
            <div key={p.id} className="bg-slate-950 border border-slate-800 rounded-2xl p-4 space-y-2">
              <div className="flex items-center justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className="text-sm font-bold text-white">{p.name}</h4>
                    {p.preset && <span className="text-xs px-1.5 py-0.5 rounded-full bg-indigo-900/40 text-indigo-300 border border-indigo-700/40 font-bold">{p.preset}</span>}
                    {!p.enabled && <span className="text-xs px-1.5 py-0.5 rounded-full bg-slate-800 text-slate-500 border border-slate-700 font-bold">DISABLED</span>}
                  </div>
                  <p className="text-xs text-slate-500 font-mono mt-0.5">{p.type} · {p.base_url}</p>
                </div>
                <div className="flex gap-1">
                  <button onClick={() => setEditing(p)} className="text-xs px-2 py-1 rounded bg-slate-800 text-slate-300 hover:text-white">Edit</button>
                  <button onClick={() => remove(p)} className="text-xs px-2 py-1 rounded bg-rose-950/40 text-rose-300 border border-rose-900/40 hover:bg-rose-900/60">Delete</button>
                </div>
              </div>
              <div className="text-xs text-slate-500">
                API Key: {p.has_api_key ? '•••••••• (encrypted)' : '—'}
              </div>
              {p.notes && <p className="text-xs text-slate-500 italic">{p.notes}</p>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};