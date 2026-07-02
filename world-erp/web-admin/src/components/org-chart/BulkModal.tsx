'use client';

import React, { useMemo, useState } from 'react';
import type { Action, MatrixResponse } from '@/lib/access/api';
import { Modal } from '@/components/ui';

interface BulkModalProps {
  matrix: MatrixResponse;
  selectedRoleIds: string[];
  onCancel: () => void;
  onConfirm: (
    changes: Array<{
      role_id: string;
      module_id: string;
      action: Action;
      state: 'allow' | 'deny' | 'inherit';
    }>,
  ) => Promise<void>;
}

const ACTIONS: Action[] = ['create', 'read', 'update', 'delete'];
const GLYPH: Record<Action, string> = { create: 'C', read: 'R', update: 'U', delete: 'D' };
const STATE_COLOR: Record<'allow' | 'deny' | 'inherit', string> = {
  allow: 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40',
  deny: 'bg-rose-500/15 text-rose-200 border-rose-500/40',
  inherit: 'bg-indigo-500/15 text-indigo-200 border-indigo-500/40',
};

export const BulkModal: React.FC<BulkModalProps> = ({
  matrix,
  selectedRoleIds,
  onCancel,
  onConfirm,
}) => {
  const [actions, setActions] = useState<Set<Action>>(new Set(['read']));
  const [state, setState] = useState<'allow' | 'deny' | 'inherit'>('allow');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedRoles = useMemo(
    () => matrix.columns.filter((c) => selectedRoleIds.includes(c.id)),
    [matrix.columns, selectedRoleIds],
  );

  const moduleIds = matrix.modules.map((m) => m.id);

  const preview = useMemo(() => {
    const changes: Array<{
      role_id: string;
      module_id: string;
      action: Action;
      current: 'allow' | 'deny';
      next: 'allow' | 'deny' | 'inherit';
    }> = [];
    let identical = 0;
    for (const r of selectedRoles) {
      for (const mid of moduleIds) {
        const cell = matrix.rows.find((row) => row.module_id === mid)?.cells?.[r.id];
        if (!cell) continue;
        for (const a of actions) {
          const current = cell[a].state;
          if (current === state) {
            identical += 1;
            continue;
          }
          changes.push({ role_id: r.id, module_id: mid, action: a, current, next: state });
        }
      }
    }
    return { changes, identical, total: selectedRoles.length * moduleIds.length * actions.size };
  }, [matrix, moduleIds, selectedRoles, actions, state]);

  const toggleAction = (a: Action) => {
    setActions((prev) => {
      const next = new Set(prev);
      if (next.has(a)) next.delete(a);
      else next.add(a);
      return next;
    });
  };

  const handleConfirm = async () => {
    if (preview.changes.length === 0) {
      onCancel();
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await onConfirm(preview.changes.map((c) => ({
        role_id: c.role_id,
        module_id: c.module_id,
        action: c.action,
        state: c.next,
      })));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  };

  return (
    <Modal open title="Bulk policy editor" onClose={busy ? () => undefined : onCancel} tone="indigo" width="2xl">
      <div className="space-y-4">
        <div>
          <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1">Selected roles</div>
          <div className="flex flex-wrap gap-1.5">
            {selectedRoles.map((r) => (
              <span
                key={r.id}
                className="px-2 py-0.5 rounded-md bg-indigo-500/15 border border-indigo-500/40 text-indigo-200 text-[11px] font-mono font-bold"
              >
                {r.id}
              </span>
            ))}
          </div>
        </div>

        <div>
          <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1">Actions to set</div>
          <div className="flex gap-2">
            {ACTIONS.map((a) => {
              const on = actions.has(a);
              return (
                <button
                  key={a}
                  type="button"
                  onClick={() => toggleAction(a)}
                  className={[
                    'w-12 h-12 rounded-xl border text-base font-mono font-black transition-all',
                    on
                      ? 'bg-indigo-500/20 border-indigo-400/60 text-white'
                      : 'bg-slate-900/40 border-slate-700/60 text-slate-500 hover:bg-slate-800/60',
                  ].join(' ')}
                  title={a}
                >
                  {GLYPH[a]}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1">State</div>
          <div className="flex gap-2">
            {(['allow', 'deny', 'inherit'] as const).map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setState(s)}
                className={[
                  'flex-1 px-3 py-2 rounded-xl border text-[12px] font-mono font-bold uppercase tracking-wider transition-all',
                  state === s
                    ? STATE_COLOR[s]
                    : 'bg-slate-900/40 border-slate-700/60 text-slate-400 hover:bg-slate-800/60',
                ].join(' ')}
              >
                {s}
              </button>
            ))}
          </div>
        </div>

        <div className="px-3 py-2.5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-1">
          <div className="flex items-center justify-between text-[11px] font-mono">
            <span className="text-slate-400 uppercase tracking-wider">Cells affected</span>
            <span className="text-white font-bold text-base">{preview.changes.length}</span>
          </div>
          <div className="flex items-center justify-between text-[11px] font-mono">
            <span className="text-slate-500">Skipped (already {state})</span>
            <span className="text-slate-400">{preview.identical}</span>
          </div>
          <div className="flex items-center justify-between text-[11px] font-mono">
            <span className="text-slate-500">Total cells in scope</span>
            <span className="text-slate-400">{preview.total}</span>
          </div>
        </div>

        {preview.changes.length > 0 && preview.changes.length <= 16 && (
          <div>
            <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1">Preview</div>
            <div className="max-h-32 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950/40 divide-y divide-slate-800/60">
              {preview.changes.slice(0, 16).map((c, i) => (
                <div
                  key={`${c.role_id}-${c.module_id}-${c.action}-${i}`}
                  className="px-2.5 py-1.5 flex items-center gap-2 text-[11px] font-mono"
                >
                  <span className="text-indigo-300 font-bold">{c.role_id}</span>
                  <span className="text-slate-600">×</span>
                  <span className="text-slate-300">{c.module_id}</span>
                  <span className="text-slate-600">·</span>
                  <span className="text-slate-400">{c.action}</span>
                  <span className="text-slate-600 ml-auto">{c.current}</span>
                  <span className="text-slate-600">→</span>
                  <span className="text-emerald-300 font-bold">{c.next}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {error && (
          <div className="px-3 py-2 rounded-lg bg-rose-500/10 border border-rose-500/30 text-rose-200 text-[11px] font-mono">
            ⚠ {error}
          </div>
        )}

        <div className="flex items-center justify-end gap-2 pt-1">
          <button
            type="button"
            disabled={busy}
            onClick={onCancel}
            className="px-3 py-1.5 rounded-lg border border-slate-700 bg-slate-900/60 text-slate-300 text-[12px] font-mono font-bold uppercase tracking-wider hover:bg-slate-800 disabled:opacity-40"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy || preview.changes.length === 0}
            onClick={handleConfirm}
            className="px-3 py-1.5 rounded-lg border border-emerald-500/40 bg-emerald-500/15 text-emerald-200 text-[12px] font-mono font-bold uppercase tracking-wider hover:bg-emerald-500/25 disabled:opacity-40"
          >
            {busy ? 'Applying…' : `Apply to ${preview.changes.length} cells`}
          </button>
        </div>
      </div>
    </Modal>
  );
};