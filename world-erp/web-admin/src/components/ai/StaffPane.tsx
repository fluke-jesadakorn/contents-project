'use client';

import React, { useEffect, useState } from 'react';
import { useDialog, useToast } from '@/components/ui';

interface Staff {
  id: number;
  name: string;
  role_label: string | null;
  description: string | null;
  system_prompt: string;
  capabilities: string[];
  default_provider_id: number | null;
  default_model_id: number | null;
  enabled: boolean;
}

interface Provider { id: number; name: string; type: string }
interface Model { id: number; provider_id: number; name: string; capabilities: string[] }

export const StaffPane: React.FC = () => {
  const dialog = useDialog();
  const toast = useToast();
  const [staff, setStaff] = useState<Staff[]>([]);
  const [providers, setProviders] = useState<Provider[]>([]);
  const [models, setModels] = useState<Model[]>([]);
  const [editing, setEditing] = useState<Staff | null>(null);
  const [creating, setCreating] = useState(false);
  const [testRunning, setTestRunning] = useState(false);
  const [testOutput, setTestOutput] = useState<any>(null);
  const [testInput, setTestInput] = useState('');

  async function load() {
    const [s, p, m] = await Promise.all([
      fetch('/api/ai/staff').then(r => r.json()),
      fetch('/api/ai/providers').then(r => r.json()),
      fetch('/api/ai/models').then(r => r.json()),
    ]);
    setStaff(s.staff || []);
    setProviders(p.providers || []);
    setModels(m.models || []);
  }
  useEffect(() => { load(); }, []);

  async function remove(s: Staff) {
    const ok = await dialog.confirm({
      title: `Delete AI Staff "${s.name}"?`,
      message: 'The agent and its assignments will be permanently removed.',
      confirmLabel: 'Delete',
      tone: 'rose',
      variant: 'danger',
    });
    if (!ok) return;
    const r = await fetch(`/api/ai/staff/${s.id}`, { method: 'DELETE' });
    if (r.ok) toast.success(`AI Staff "${s.name}" deleted`, 'AI Staff');
    else toast.error('Delete failed', 'Error');
    load();
  }

  async function runTest() {
    if (!editing || !testInput) return;
    setTestRunning(true); setTestOutput(null);
    try {
      const res = await fetch(`/api/ai/staff/${editing.id}/invoke`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: testInput, task: 'chat', temperature: 0.3 }),
      });
      setTestOutput(await res.json());
    } finally { setTestRunning(false); }
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <div>
          <h3 className="text-sm font-black text-white uppercase tracking-wider font-mono">AI Staff</h3>
          <p className="text-[11px] text-slate-400 mt-0.5">Agent with a defined system prompt + default provider/model</p>
        </div>
        {!creating && !editing && (
          <button onClick={() => { setCreating(true); setEditing(null); }}
            className="text-xs px-3 py-1.5 rounded-lg bg-indigo-600 text-white font-bold hover:bg-indigo-500">
            + Add Staff
          </button>
        )}
      </div>

      {(creating || editing) && (
        <StaffEditor
          initial={editing || undefined}
          providers={providers}
          models={models}
          onSaved={() => { setCreating(false); setEditing(null); setTestOutput(null); setTestInput(''); load(); }}
          onCancel={() => { setCreating(false); setEditing(null); setTestOutput(null); }}
          onTest={editing ? runTest : undefined}
          testRunning={testRunning}
          testInput={testInput}
          setTestInput={setTestInput}
          testOutput={testOutput}
        />
      )}

      {!creating && !editing && (
        loading(staff) || (
          staff.length === 0 ? (
            <p className="text-xs text-slate-500 italic">No AI Staff yet</p>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {staff.map(s => (
                <div key={s.id} className="bg-slate-950 border border-slate-800 rounded-2xl p-4 space-y-2">
                  <div className="flex items-start justify-between">
                    <div>
                      <h4 className="text-sm font-bold text-white">{s.name}</h4>
                      {s.role_label && <p className="text-[10px] text-indigo-300 font-mono uppercase">{s.role_label}</p>}
                    </div>
                    {!s.enabled && <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-slate-800 text-slate-500 border border-slate-700 font-bold">DISABLED</span>}
                  </div>
                  {s.description && <p className="text-[10px] text-slate-400">{s.description}</p>}
                  <div className="flex flex-wrap gap-1">
                    {(s.capabilities || []).map(c => (
                      <span key={c} className="text-[9px] px-1.5 py-0.5 rounded bg-indigo-900/40 text-indigo-300 border border-indigo-700/40 font-mono">{c}</span>
                    ))}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    Default: {providers.find(p => p.id === s.default_provider_id)?.name || '—'} / {models.find(m => m.id === s.default_model_id)?.name || '—'}
                  </div>
                  <pre className="text-[10px] text-slate-400 bg-slate-900 rounded-lg p-2 line-clamp-3 font-mono whitespace-pre-wrap">{s.system_prompt}</pre>
                  <div className="flex gap-1">
                    <button onClick={() => { setEditing(s); setCreating(false); setTestOutput(null); setTestInput(''); }} className="text-[10px] px-2 py-1 rounded bg-slate-800 text-slate-300 hover:text-white">Edit / Test</button>
                    <button onClick={() => remove(s)} className="text-[10px] px-2 py-1 rounded bg-rose-950/40 text-rose-300 border border-rose-900/40">Delete</button>
                  </div>
                </div>
              ))}
            </div>
          )
        )
      )}
    </div>
  );
};

function loading<T>(arr: T[]) { return arr.length === 0 ? <p className="text-xs text-slate-400">Loading…</p> : null; }

interface EditorProps {
  initial?: Staff;
  providers: Provider[];
  models: Model[];
  onSaved: () => void;
  onCancel: () => void;
  onTest?: () => void;
  testRunning: boolean;
  testInput: string;
  setTestInput: (v: string) => void;
  testOutput: any;
}

const StaffEditor: React.FC<EditorProps> = ({ initial, providers, models, onSaved, onCancel, onTest, testRunning, testInput, setTestInput, testOutput }) => {
  const toast = useToast();
  const [name, setName] = useState(initial?.name || '');
  const [roleLabel, setRoleLabel] = useState(initial?.role_label || '');
  const [description, setDescription] = useState(initial?.description || '');
  const [systemPrompt, setSystemPrompt] = useState(initial?.system_prompt || '');
  const [capabilities, setCapabilities] = useState<string[]>(initial?.capabilities || []);
  const [providerId, setProviderId] = useState<string>(initial?.default_provider_id?.toString() || '');
  const [modelId, setModelId] = useState<string>(initial?.default_model_id?.toString() || '');

  const availableModels = models.filter(m => !providerId || m.provider_id === parseInt(providerId, 10));

  async function save() {
    const body: any = { name, role_label: roleLabel, description, system_prompt: systemPrompt, capabilities, enabled: true };
    if (providerId) body.default_provider_id = parseInt(providerId, 10);
    if (modelId) body.default_model_id = parseInt(modelId, 10);
    const url = initial ? `/api/ai/staff/${initial.id}` : '/api/ai/staff';
    const method = initial ? 'PUT' : 'POST';
    const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    if (!res.ok) { toast.error('Save failed', 'Error'); return; }
    toast.success(`AI Staff "${body.name}" saved`, 'AI Staff');
    onSaved();
  }

  return (
    <div className="bg-slate-950 border border-slate-800 rounded-2xl p-5 space-y-4">
      <h4 className="text-sm font-black text-white uppercase tracking-wider font-mono">{initial ? 'Edit Staff' : 'Add Staff'}</h4>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label className="space-y-1">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Name</span>
          <input value={name} onChange={e => setName(e.target.value)} placeholder="OCR Clerk"
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
        </label>
        <label className="space-y-1">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Role label</span>
          <input value={roleLabel} onChange={e => setRoleLabel(e.target.value)} placeholder="Receipt OCR Specialist"
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
        </label>
        <label className="space-y-1 md:col-span-2">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Description</span>
          <input value={description} onChange={e => setDescription(e.target.value)}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
        </label>
        <label className="space-y-1 md:col-span-2">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">System prompt</span>
          <textarea value={systemPrompt} onChange={e => setSystemPrompt(e.target.value)} rows={6}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white font-mono whitespace-pre-wrap" />
        </label>
        <label className="space-y-1">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Default provider</span>
          <select value={providerId} onChange={e => { setProviderId(e.target.value); setModelId(''); }}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white">
            <option value="">— pick —</option>
            {providers.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className="space-y-1">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Default model</span>
          <select value={modelId} onChange={e => setModelId(e.target.value)} disabled={!providerId}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white disabled:opacity-40">
            <option value="">— pick —</option>
            {availableModels.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
          </select>
        </label>
        <label className="space-y-1 md:col-span-2">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Capabilities</span>
          <div className="flex gap-2">
            {['embed', 'chat', 'vision'].map(c => (
              <label key={c} className="flex items-center gap-1 text-xs text-slate-300">
                <input type="checkbox" checked={capabilities.includes(c)}
                  onChange={e => setCapabilities(p => e.target.checked ? [...p, c] : p.filter(x => x !== c))} />
                {c}
              </label>
            ))}
          </div>
        </label>
      </div>

      {onTest && (
        <div className="border-t border-slate-800 pt-4 space-y-2">
          <h5 className="text-[10px] text-slate-400 uppercase tracking-wider font-mono">Test run</h5>
          <textarea value={testInput} onChange={e => setTestInput(e.target.value)} rows={3} placeholder="Try sending a message to test this staff"
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white" />
          <div className="flex justify-end">
            <button onClick={onTest} disabled={testRunning || !testInput}
              className="px-3 py-1.5 rounded-lg bg-purple-600 text-white text-xs font-bold hover:bg-purple-500 disabled:opacity-40">
              {testRunning ? 'Running…' : '▶ Run Test'}
            </button>
          </div>
          {testOutput && (
            <pre className="text-[10px] bg-slate-900 rounded-lg p-3 text-slate-200 font-mono whitespace-pre-wrap max-h-64 overflow-auto">
              {JSON.stringify(testOutput, null, 2)}
            </pre>
          )}
        </div>
      )}

      <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
        <button onClick={onCancel} className="px-4 py-2 rounded-lg bg-slate-800 text-slate-300 text-xs font-bold">Cancel</button>
        <button onClick={save} className="px-4 py-2 rounded-lg bg-indigo-600 text-white text-xs font-bold">Save</button>
      </div>
    </div>
  );
};