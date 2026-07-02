'use client';

import React, { useState } from 'react';
import { MINIMAX_PRESET } from '@/lib/ai/providers/minimax';

export interface Provider {
  id: number;
  name: string;
  type: 'ollama' | 'openai_compat' | 'minimax';
  base_url: string;
  has_api_key: boolean;
  enabled: boolean;
  preset?: string | null;
  notes?: string | null;
}

export interface ProviderFormProps {
  initial?: Partial<Provider>;
  onSaved: () => void;
  onCancel: () => void;
}

const TYPE_LABEL: Record<string, string> = {
  ollama: 'Ollama (local)',
  openai_compat: 'OpenAI-compatible (OpenAI / OpenRouter / custom)',
  minimax: 'MiniMax (preset)',
};

export const ProviderForm: React.FC<ProviderFormProps> = ({ initial, onSaved, onCancel }) => {
  const [name, setName] = useState(initial?.name || '');
  const [type, setType] = useState<Provider['type']>(initial?.type || 'ollama');
  const [baseUrl, setBaseUrl] = useState(initial?.base_url || '');
  const [apiKey, setApiKey] = useState('');
  const [enabled, setEnabled] = useState(initial?.enabled !== false);
  const [notes, setNotes] = useState(initial?.notes || '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [showKey, setShowKey] = useState(false);
  const [testResult, setTestResult] = useState<any>(null);

  const isEdit = !!initial?.id;

  function applyPreset() {
    setType('minimax');
    setBaseUrl(MINIMAX_PRESET.baseUrl);
    setNotes(MINIMAX_PRESET.notes);
  }

  async function test() {
    setBusy(true); setErr(null); setTestResult(null);
    try {
      const res = await fetch('/api/ai/providers/test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(initial?.id ? { id: initial.id } : { type, base_url: baseUrl, api_key: apiKey || null }),
      });
      const data = await res.json();
      setTestResult(data);
    } catch (e: any) { setErr(e.message); }
    finally { setBusy(false); }
  }

  async function save() {
    setBusy(true); setErr(null);
    try {
      const body: any = { name, type, base_url: baseUrl, enabled, notes };
      if (apiKey) body.api_key = apiKey;
      const url = isEdit ? `/api/ai/providers/${initial!.id}` : '/api/ai/providers';
      const method = isEdit ? 'PUT' : 'POST';
      const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || `HTTP ${res.status}`);
      }
      onSaved();
    } catch (e: any) { setErr(e.message); }
    finally { setBusy(false); }
  }

  return (
    <div className="bg-slate-950 border border-slate-800 rounded-2xl p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-black text-white uppercase tracking-wider font-mono">
          {isEdit ? 'Edit Provider' : 'Add Provider'}
        </h4>
        <button type="button" onClick={applyPreset} className="text-[10px] px-2 py-1 rounded-lg bg-gradient-to-r from-indigo-600 to-purple-600 text-white font-bold">
          ✨ Use MiniMax Preset
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label className="space-y-1">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Name</span>
          <input value={name} onChange={e => setName(e.target.value)} placeholder="local-ollama"
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
        </label>
        <label className="space-y-1">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Type</span>
          <select value={type} onChange={e => setType(e.target.value as any)}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white">
            {Object.entries(TYPE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </label>
        <label className="space-y-1 md:col-span-2">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Base URL</span>
          <input value={baseUrl} onChange={e => setBaseUrl(e.target.value)} placeholder="http://localhost:11434"
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white font-mono" />
        </label>
        {type !== 'ollama' && (
          <label className="space-y-1 md:col-span-2">
            <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">
              API Key {isEdit && '(leave blank to keep existing)'}
            </span>
            <div className="flex gap-2">
              <input type={showKey ? 'text' : 'password'} value={apiKey} onChange={e => setApiKey(e.target.value)}
                placeholder="sk-..."
                className="flex-1 bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white font-mono" />
              <button type="button" onClick={() => setShowKey(s => !s)} className="px-3 py-2 text-[10px] rounded-lg bg-slate-800 text-slate-300 hover:text-white">
                {showKey ? 'Hide' : 'Show'}
              </button>
            </div>
          </label>
        )}
        <label className="space-y-1 md:col-span-2">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Notes (optional)</span>
          <input value={notes} onChange={e => setNotes(e.target.value)}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
        </label>
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={enabled} onChange={e => setEnabled(e.target.checked)} />
          <span className="text-xs text-slate-300">Enabled</span>
        </label>
      </div>

      {err && <p className="text-[11px] text-rose-400">{err}</p>}
      {testResult && (
        <div className={`text-[11px] rounded-lg p-2 font-mono ${testResult.ok ? 'bg-emerald-950/40 text-emerald-300 border border-emerald-700/40' : 'bg-rose-950/40 text-rose-300 border border-rose-700/40'}`}>
          {testResult.ok
            ? `✓ ${testResult.modelCount} models reachable${testResult.latencyMs ? ` in ${testResult.latencyMs}ms` : ''} — sample: ${(testResult.sample || []).join(', ')}`
            : `✗ ${testResult.error}`}
        </div>
      )}

      <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
        <button type="button" onClick={onCancel} className="px-4 py-2 rounded-lg bg-slate-800 text-slate-300 text-xs font-bold hover:text-white">Cancel</button>
        <button type="button" onClick={test} disabled={busy} className="px-4 py-2 rounded-lg bg-slate-900 border border-slate-700 text-slate-200 text-xs font-bold hover:bg-slate-800">Test</button>
        <button type="button" onClick={save} disabled={busy} className="px-4 py-2 rounded-lg bg-indigo-600 text-white text-xs font-bold hover:bg-indigo-500">Save</button>
      </div>
    </div>
  );
};