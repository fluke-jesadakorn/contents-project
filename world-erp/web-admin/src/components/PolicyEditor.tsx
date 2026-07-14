'use client';

import React, { useState } from 'react';
import { AiActionButton } from '@/components/ai/AiActionButton';
import { useDialog } from '@/components/ui';

const APPROVER_ROLES = [
  { value: 'head_of_department', label: 'Head of Department (Head of Dept)' },
  { value: 'accounting_manager', label: 'Accounting Manager (Accounting Mgr)' },
  { value: 'cfo', label: 'CFO' },
];

const NOTIFY_TARGETS = [
  { value: 'requester', label: 'Requester' },
  { value: 'head_of_department', label: 'Head of Department (HoD)' },
  { value: 'accounting_manager', label: 'Accounting Manager (Acct. Mgr)' },
  { value: 'cfo', label: 'CFO' },
  { value: 'ceo', label: 'CEO' },
];

const NOTIFY_TARGET_DOMAINS = [
  { domain: 'expenses',      role_id: 'L3',  label: 'Expenses · HoD-equivalent (L3)' },
  { domain: 'pr',            role_id: 'L3',  label: 'PR · HoD-equivalent (L3)' },
  { domain: 'po',            role_id: 'L3',  label: 'PO · HoD-equivalent (L3)' },
  { domain: 'expenses',      role_id: 'L4',  label: 'Expenses · All roles (L4)' },
  { domain: 'audit',         role_id: 'L4',  label: 'Audit · All roles (L4)' },
  { domain: 'notifications', role_id: 'L2A', label: 'Notifications · self (L2A)' },
];

const FIELDS = [
  { value: 'total_amount', label: 'Total Amount (total_amount)', kind: 'number' },
  { value: 'department', label: 'Department (department)', kind: 'string' },
  { value: 'category_code', label: 'Account Category Code (category_code)', kind: 'string' },
  { value: 'submitter_role', label: 'Submitter Role (submitter_role)', kind: 'string' },
  { value: 'is_recurring', label: 'Recurring Item (is_recurring)', kind: 'boolean' },
  { value: 'target_type', label: 'Document Type (target_type)', kind: 'string' },
];

const OPS_BY_KIND: Record<string, Array<{ value: string; label: string }>> = {
  number: [
    { value: 'eq', label: '= equals' },
    { value: 'neq', label: '≠ not equals' },
    { value: 'gt', label: '> greater than' },
    { value: 'gte', label: '≥ greater or equal' },
    { value: 'lt', label: '< less than' },
    { value: 'lte', label: '≤ less or equal' },
    { value: 'between', label: 'Between (between)' },
  ],
  string: [
    { value: 'eq', label: '= equals' },
    { value: 'neq', label: '≠ not equals' },
    { value: 'in', label: 'In (in)' },
    { value: 'nin', label: 'Not In (nin)' },
    { value: 'contains', label: 'Contains (contains)' },
  ],
  boolean: [
    { value: 'eq', label: '= equals' },
    { value: 'neq', label: '≠ not equals' },
  ],
};

const DEPT_PRESETS = ['Engineering', 'Sales', 'Marketing', 'Operations', 'HR', 'Finance'];
const ROLE_PRESETS = ['staff', 'head_of_department', 'accounting_manager', 'cfo', 'ceo', 'admin'];
const TARGET_PRESETS = ['expense', 'pr'];

const empty = () => ({
  id: undefined,
  name: '',
  priority: 100,
  is_active: true,
  target_type: 'both',
  conditions_json: { all_of: [] },
  action_json: { approver_chain: ['head_of_department', 'accounting_manager'], auto_approve: false, notify: [] },
});

const emptyCondition = (field: any = 'total_amount') => {
  const kind = FIELDS.find((f: any)=> f.value === field)?.kind || 'number';
  const op = kind === 'number' ? 'lte' : 'eq';
  return { field, op, value: kind === 'number' ? 0 : '' };
};

const parseArray = (txt: string)=>
  txt
    .split(',')
    .map((s: string)=> s.trim())
    .filter(Boolean);

export const PolicyEditor = ({ policies, onSave, onDelete }: { policies: any; onSave: any; onDelete: any })=> {
  const dialog = useDialog();
  const [editing, setEditing] = useState<any>(null);

  const startNew = () => setEditing(empty());
  const startEdit = (p: any)=>
    setEditing({
      ...p,
      conditions_json:
        typeof p.conditions_json === 'string'
          ? JSON.parse(p.conditions_json)
          : p.conditions_json || { all_of: [] },
      action_json:
        typeof p.action_json === 'string'
          ? JSON.parse(p.action_json)
          : p.action_json || { approver_chain: [], auto_approve: false, notify: [] },
    });

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-purple-500/30 flex justify-between items-center">
        <div>
          <span className="text-xs font-mono font-black uppercase text-purple-400 block tracking-wider">
            ⚙️ Approval Policy Engine
          </span>
          <h2 className="text-xl font-bold text-white">CFO Policy Editor</h2>
          <p className="text-xs text-slate-400 mt-1">
            Define approval rules by amount, department, and account category. Policies with lower priority are evaluated first.
          </p>
        </div>
        <button
          onClick={startNew}
          className="px-4 py-2 bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 rounded-2xl text-sm font-bold"
        >
          + New Policy
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-3">📋 Active Policies ({policies.length})</h3>
          <div className="space-y-2 max-h-[700px] overflow-y-auto">
            {policies.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">No policies yet</p>
            ) : (
              policies.map((p: any)=> {
                const action =
                  typeof p.action_json === 'string' ? JSON.parse(p.action_json) : p.action_json;
                const chain = (action?.approver_chain || []).join(' → ') || '(auto)';
                return (
                  <div
                    key={p.id}
                    onClick={() => startEdit(p)}
                    className={`p-3 rounded-2xl border cursor-pointer ${
                      editing?.id === p.id
                        ? 'bg-purple-600/15 border-purple-500'
                        : 'bg-slate-950/60 border-slate-900 hover:border-slate-800'
                    }`}
                  >
                    <div className="flex justify-between items-center">
                      <span className="text-xs font-mono text-white font-bold">
                        #{p.priority} — {p.name}
                      </span>
                      <span
                        className={`text-xs font-mono px-2 py-0.5 rounded ${
                          p.is_active ? 'bg-emerald-500/20 text-emerald-300' : 'bg-slate-700 text-slate-400'
                        }`}
                      >
                        {p.is_active ? 'ACTIVE' : 'DISABLED'}
                      </span>
                    </div>
                    <div className="text-xs text-slate-400 mt-1 font-mono">
                      target: {p.target_type} · chain: {chain}
                    </div>
                    <div className="flex gap-2 mt-2">
                      <button
                        onClick={(e: any)=> {
                          e.stopPropagation();
                          (async () => {
                            const ok = await dialog.confirm({
                              title: `Disable policy "${p.name}"?`,
                              message: 'The policy will be marked inactive. In-flight expenses are not affected.',
                              confirmLabel: 'Disable',
                              tone: 'rose',
                              variant: 'danger',
                            });
                            if (ok) onDelete(p.id);
                          })();
                        }}
                        className="text-xs text-rose-300 font-mono"
                      >
                        Disable
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {editing && (
          <PolicyForm
            key={editing.id || 'new'}
            initial={editing}
            onCancel={() => setEditing(null)}
            onSave={async (p: any)=> {
              await onSave(p);
              setEditing(null);
            }}
          />
        )}
      </div>
    </div>
  );
};

const PolicyForm = ({ initial, onSave, onCancel }: { initial: any; onSave: any; onCancel: any })=> {
  const [form, setForm] = useState(initial);

  const updateConditions = (all_of: any)=>
    setForm({ ...form, conditions_json: { ...form.conditions_json, all_of } });

  const updateAction = (patch: any)=>
    setForm({ ...form, action_json: { ...form.action_json, ...patch } });

  const addCondition = () =>
    updateConditions([...(form.conditions_json?.all_of || []), emptyCondition()]);

  const updateCondition = (idx: any, patch: any)=> {
    const all_of = [...(form.conditions_json?.all_of || [])];
    all_of[idx] = { ...all_of[idx], ...patch };
    updateConditions(all_of);
  };

  const removeCondition = (idx: any)=> {
    const all_of = [...(form.conditions_json?.all_of || [])];
    all_of.splice(idx, 1);
    updateConditions(all_of);
  };

  const chain = form.action_json?.approver_chain || [];
  const notify = form.action_json?.notify || [];

  return (
    <form
      onSubmit={(e: any)=> {
        e.preventDefault();
        onSave(form);
      }}
      className="glass-panel p-6 rounded-3xl border-purple-500/30 space-y-4"
    >
      <h3 className="text-base font-bold text-white">
        {form.id ? `Edit #${form.id}` : 'New Policy'}
      </h3>

      <div className="grid grid-cols-3 gap-3">
        <Field label="Name">
          <input
            value={form.name}
            onChange={(e: any)=> setForm({ ...form, name: e.target.value })}
            required
            className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white"
          />
        </Field>
        <Field label="Priority (lower first)">
          <input
            type="number"
            value={form.priority}
            onChange={(e: any)=>
              setForm({ ...form, priority: parseInt(e.target.value, 10) || 100 })
            }
            className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white"
          />
        </Field>
        <Field label="Target Type">
          <select
            value={form.target_type}
            onChange={(e: any)=> setForm({ ...form, target_type: e.target.value })}
            className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white"
          >
            <option value="both">Both (expense + pr)</option>
            <option value="expense">Expense only</option>
            <option value="pr">PR only</option>
          </select>
        </Field>
      </div>

      <label className="flex items-center gap-2 text-xs text-slate-300">
        <input
          type="checkbox"
          checked={form.is_active}
          onChange={(e: any)=> setForm({ ...form, is_active: e.target.checked })}
          className="accent-emerald-500"
        />
        Active
      </label>

      <Section title="Conditions — All must be true" accent="emerald">
        <div className="space-y-2">
          {(form.conditions_json?.all_of || []).map((c: any, idx: any)=> (
            <ConditionRow
              key={idx}
              cond={c}
              onChange={(patch: any)=> updateCondition(idx, patch)}
              onRemove={() => removeCondition(idx)}
            />
          ))}
          {(form.conditions_json?.all_of || []).length === 0 && (
            <p className="text-sm text-slate-500 font-mono py-2">
              No conditions — policy will match all documents
            </p>
          )}
          <button
            type="button"
            onClick={addCondition}
            className="px-3 py-1.5 bg-emerald-500/15 text-emerald-300 border border-emerald-500/30 rounded-xl text-xs font-bold"
          >
            + Add condition
          </button>
        </div>
      </Section>

      <Section title="Approver Chain" accent="purple">
        <div className="space-y-2">
          {chain.map((role: any, idx: any)=> (
            <div
              key={idx}
              className="flex items-center gap-2 bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2"
            >
              <span className="text-xs font-mono text-slate-500 w-5">{idx + 1}.</span>
              <select
                value={role}
                onChange={(e: any)=> {
                  const next = [...chain];
                  next[idx] = e.target.value;
                  updateAction({ approver_chain: next });
                }}
                className="flex-1 bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
              >
                {APPROVER_ROLES.map((r: any)=> (
                  <option key={r.value} value={r.value}>
                    {r.label}
                  </option>
                ))}
              </select>
              <button
                type="button"
                onClick={() => updateAction({ approver_chain: chain.filter((_: any, i: any)=> i !== idx) })}
                className="text-rose-300 text-xs px-2"
                    title="Delete"
              >
                ✕
              </button>
              <div className="flex flex-col gap-0.5">
                <button
                  type="button"
                  disabled={idx === 0}
                  onClick={() => {
                    const next = [...chain];
                    [next[idx - 1], next[idx]] = [next[idx], next[idx - 1]];
                    updateAction({ approver_chain: next });
                  }}
                  className="text-slate-400 hover:text-white disabled:opacity-20 text-xs"
                >
                  ▲
                </button>
                <button
                  type="button"
                  disabled={idx === chain.length - 1}
                  onClick={() => {
                    const next = [...chain];
                    [next[idx + 1], next[idx]] = [next[idx], next[idx + 1]];
                    updateAction({ approver_chain: next });
                  }}
                  className="text-slate-400 hover:text-white disabled:opacity-20 text-xs"
                >
                  ▼
                </button>
              </div>
            </div>
          ))}
          {chain.length === 0 && (
            <p className="text-sm text-rose-300 font-mono py-1">
              ⚠ At least 1 approver required (or enable Auto Approve)
            </p>
          )}
          <button
            type="button"
            onClick={() =>
              updateAction({
                approver_chain: [...chain, APPROVER_ROLES[0].value],
              })
            }
            className="px-3 py-1.5 bg-purple-500/15 text-purple-300 border border-purple-500/30 rounded-xl text-xs font-bold"
          >
            + Add step
          </button>
        </div>
      </Section>

      <Section title="Additional Options" accent="slate">
        <label className="flex items-center gap-2 text-xs text-slate-300 mb-3">
          <input
            type="checkbox"
            checked={!!form.action_json?.auto_approve}
            onChange={(e: any)=> updateAction({ auto_approve: e.target.checked })}
            className="accent-emerald-500"
          />
          Auto Approve (auto-approve, no forwarding needed)
        </label>

        <div>
          <label className="block text-xs uppercase tracking-wider text-slate-400 font-bold mb-2">
            Notify
          </label>
          <div className="space-y-2">
            {notify.map((t: any, idx: any)=> (
              <div
                key={idx}
                className="flex items-center gap-2 bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2"
              >
                <select
                  value={typeof t === 'string' ? `legacy:${t}` : 'new:0'}
                  onChange={(e: any)=> {
                    const raw = e.target.value;
                    if (raw.startsWith('legacy:')) {
                      const next = [...notify];
                      next[idx] = raw.slice('legacy:'.length);
                      updateAction({ notify: next });
                    } else if (raw.startsWith('new:')) {
                      const idx2 = parseInt(raw.slice('new:'.length), 10);
                      if (!isNaN(idx2)) {
                        const next = [...notify];
                        next[idx] = NOTIFY_TARGET_DOMAINS[idx2];
                        updateAction({ notify: next });
                      }
                    }
                  }}
                  className="flex-1 bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
                >
                  {NOTIFY_TARGETS.map((n: any)=> (
                    <option key={`legacy-${n.value}`} value={`legacy:${n.value}`}>
                      [legacy] {n.label}
                    </option>
                  ))}
                  {NOTIFY_TARGET_DOMAINS.map((d: any, dIdx: any)=> (
                    <option key={`new-${dIdx}`} value={`new:${dIdx}`}>
                      [domain] {d.label}
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  onClick={() => updateAction({ notify: notify.filter((_: any, i: any)=> i !== idx) })}
                  className="text-rose-300 text-xs px-2"
                title="Delete"
                >
                  ✕
                </button>
              </div>
            ))}
            <button
              type="button"
              onClick={() => updateAction({ notify: [...notify, NOTIFY_TARGET_DOMAINS[0]] })}
              className="px-3 py-1.5 bg-slate-700/40 text-slate-200 border border-slate-700 rounded-xl text-xs font-bold"
            >
              + Add notification recipient
            </button>
            <p className="text-xs text-slate-500 mt-1">
              Domain targets fan out to every user whose (role × domain) visibility scope includes the event anchor. Legacy role names still work.
            </p>
          </div>
        </div>
      </Section>

      <div className="mt-4 p-3 bg-purple-950/20 border border-purple-500/30 rounded-2xl">
        <div className="text-xs font-mono font-bold uppercase text-purple-300 mb-2 tracking-wider">
          🤖 AI Policy Lint
        </div>
        <AiActionButton
          sectionKey="policy:editor"
          task="chat"
          systemPrompt="You review approval policies for an enterprise finance system. Given a policy in JSON form (name, conditions, action), find: contradictions (e.g. auto-approve AND approver chain both set), gaps (no notify list, no approver chain), unused fields, and inconsistencies between conditions and chain. Output a short bulleted list of issues (or 'No issues — looks good' if clean), then a 1-sentence overall verdict. Respond in English."
          input={`Policy name: ${form.name}\nTarget type: ${form.target_type}\nPriority: ${form.priority}\nActive: ${form.is_active}\nConditions (JSON):\n${JSON.stringify(form.conditions_json, null, 2)}\nAction (JSON):\n${JSON.stringify(form.action_json, null, 2)}`}
          buttonLabel="Lint this policy"
          resultTitle="AI Policy Review"
          tone="purple"
          glyph="🤖"
        />
      </div>

      <div className="flex gap-2 pt-2">
        <button
          type="submit"
          disabled={chain.length === 0 && !form.action_json?.auto_approve}
          className="flex-1 bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 rounded-2xl py-2 text-sm font-bold disabled:opacity-40"
        >
          💾 Save Policy
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 bg-slate-700/40 text-slate-300 border border-slate-700 rounded-2xl py-2 text-sm"
        >
          Cancel
        </button>
      </div>
    </form>
  );
};

const ConditionRow = ({ cond, onChange, onRemove }: { cond: any; onChange: any; onRemove: any })=> {
  const fieldDef = FIELDS.find((f: any)=> f.value === cond.field) || FIELDS[0];
  const ops = OPS_BY_KIND[fieldDef.kind] || OPS_BY_KIND.string;
  const opDef = ops.find((o: any)=> o.value === cond.op) || ops[0];

  const onFieldChange = (newField: any)=> {
    const newKind = FIELDS.find((f: any)=> f.value === newField)?.kind || 'number';
    const newOp = OPS_BY_KIND[newKind][0].value;
    const defaultVal = newKind === 'number' ? 0 : newKind === 'boolean' ? false : '';
    onChange({ field: newField, op: newOp, value: defaultVal });
  };

  const onOpChange = (newOp: any)=> {
    let newVal = cond.value;
    if (newOp === 'between') newVal = [0, 0];
    else if (newOp === 'in' || newOp === 'nin') newVal = [];
    else if (fieldDef.kind === 'number') newVal = 0;
    else if (fieldDef.kind === 'boolean') newVal = false;
    else newVal = '';
    onChange({ op: newOp, value: newVal });
  };

  const presets =
    cond.field === 'department' ? DEPT_PRESETS
      : cond.field === 'submitter_role' ? ROLE_PRESETS
      : cond.field === 'target_type' ? TARGET_PRESETS
      : [];

  return (
    <div className="grid grid-cols-12 gap-2 items-center bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2">
      <select
        value={cond.field}
        onChange={(e: any)=> onFieldChange(e.target.value)}
        className="col-span-3 bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
      >
        {FIELDS.map((f: any)=> (
          <option key={f.value} value={f.value}>
            {f.label}
          </option>
        ))}
      </select>
      <select
        value={cond.op}
        onChange={(e: any)=> onOpChange(e.target.value)}
        className="col-span-2 bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
      >
        {ops.map((o: any)=> (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
      <div className="col-span-6">
        <ValueEditor
          cond={cond}
          fieldDef={fieldDef}
          opDef={opDef}
          presets={presets}
          onChange={(v: any)=> onChange({ value: v })}
        />
      </div>
      <button
        type="button"
        onClick={onRemove}
        className="col-span-1 text-rose-300 text-xs"
        title="Delete condition"
      >
        ✕
      </button>
    </div>
  );
};

const ValueEditor = ({ cond, fieldDef, opDef, presets, onChange }: { cond: any; fieldDef: any; opDef: any; presets: any; onChange: any })=> {
  if (fieldDef.kind === 'boolean') {
    return (
      <select
        value={String(cond.value)}
        onChange={(e: any)=> onChange(e.target.value === 'true')}
        className="w-full bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
      >
        <option value="true">true</option>
        <option value="false">false</option>
      </select>
    );
  }

  if (opDef.value === 'between' && fieldDef.kind === 'number') {
    const [lo, hi] = Array.isArray(cond.value) ? cond.value : [0, 0];
    return (
      <div className="flex items-center gap-1.5">
        <input
          type="number"
          value={lo}
          onChange={(e: any)=> onChange([Number(e.target.value), hi])}
          className="flex-1 bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
          placeholder="min"
        />
        <span className="text-slate-500 text-xs">to</span>
        <input
          type="number"
          value={hi}
          onChange={(e: any)=> onChange([lo, Number(e.target.value)])}
          className="flex-1 bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
          placeholder="max"
        />
      </div>
    );
  }

  if (opDef.value === 'in' || opDef.value === 'nin') {
    const txt = Array.isArray(cond.value) ? cond.value.join(', ') : '';
    return (
      <div>
        <input
          type="text"
          value={txt}
          onChange={(e: any)=> onChange(parseArray(e.target.value))}
          placeholder="value1, value2, value3"
          className="w-full bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
        />
        {presets.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1.5">
            {presets.map((p: any)=> (
              <button
                key={p}
                type="button"
                onClick={() => {
                  const arr = Array.isArray(cond.value) ? [...cond.value] : [];
                  if (!arr.includes(p)) arr.push(p);
                  onChange(arr);
                }}
                className="text-xs font-mono px-1.5 py-0.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded"
              >
                + {p}
              </button>
            ))}
          </div>
        )}
      </div>
    );
  }

  if (fieldDef.kind === 'number') {
    return (
      <input
        type="number"
        value={cond.value ?? 0}
        onChange={(e: any)=> onChange(Number(e.target.value))}
        className="w-full bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
      />
    );
  }

  return (
    <div>
      <input
        type="text"
        value={cond.value ?? ''}
        onChange={(e: any)=> onChange(e.target.value)}
        className="w-full bg-slate-900 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white"
          placeholder={opDef.value === 'contains' ? 'search term' : 'value'}
      />
      {presets.length > 0 && opDef.value === 'eq' && (
        <div className="flex flex-wrap gap-1 mt-1.5">
          {presets.map((p: any)=> (
            <button
              key={p}
              type="button"
              onClick={() => onChange(p)}
              className="text-xs font-mono px-1.5 py-0.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded"
            >
              {p}
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

const Section = ({ title, accent = 'slate', children }: { title: any; accent: any; children: any })=> {
  const accents: Record<string, string> = {
    emerald: 'text-emerald-400 border-emerald-500/30 bg-emerald-500/5',
    purple: 'text-purple-400 border-purple-500/30 bg-purple-500/5',
    slate: 'text-slate-300 border-slate-700/50 bg-slate-900/40',
  };
  return (
    <div className={`rounded-2xl border p-3 ${accents[accent]}`}>
      <div className="text-xs font-mono font-black uppercase tracking-wider mb-2">
        {title}
      </div>
      {children}
    </div>
  );
};

const Field = ({ label, children }: { label: any; children: any })=> (
  <div>
    <label className="block text-xs uppercase tracking-wider text-slate-400 font-bold mb-1">
      {label}
    </label>
    {children}
  </div>
);