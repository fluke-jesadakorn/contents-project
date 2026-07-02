'use client';

import React, { useEffect, useState } from 'react';
import { Modal } from '@/components/ui';
import { AutoWireTreeNode } from './AutoWireTreeNode';
import type { AutoWireProposal, WireEdge } from '@/lib/autoWire.server';

interface AutoWireDialogProps {
  open: boolean;
  actorId: number;
  onClose: () => void;
  onApplied: () => Promise<void> | void;
}

export const AutoWireDialog: React.FC<AutoWireDialogProps> = ({
  open,
  actorId: _actorId,
  onClose,
  onApplied,
}) => {
  const [proposal, setProposal] = useState<AutoWireProposal | null>(null);
  const [loading, setLoading] = useState(false);
  const [applying, setApplying] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setErr(null);
    setLoading(true);
    setProposal(null);
    fetch('/api/auto-wire/propose', { method: 'POST' })
      .then((r) => r.json())
      .then((r) => {
        if (r.error) setErr(r.error);
        else setProposal(r.proposal);
      })
      .catch((e) => setErr(String(e?.message || e)))
      .finally(() => setLoading(false));
  }, [open]);

  if (!open) return null;

  async function apply() {
    if (!proposal) return;
    setApplying(true);
    setErr(null);
    try {
      const wires: WireEdge[] = proposal.wires;
      const r = await fetch('/api/auto-wire/apply', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ wires }),
      }).then((res) => res.json());
      if (r.error) throw new Error(r.error);
      await onApplied();
      onClose();
    } catch (e: any) {
      setErr(String(e?.message || e));
    } finally {
      setApplying(false);
    }
  }

  return (
    <Modal
      open
      onClose={() => !applying && onClose()}
      width="2xl"
      tone="indigo"
      header={
        <div>
          <div className="text-[10px] font-mono uppercase tracking-widest text-indigo-300">
            🔗 Auto-Wire Organization Hierarchy
          </div>
          <h2 className="text-base font-black text-white mt-1">Tree Preview</h2>
          <p className="text-[11px] text-slate-400 mt-1">
            Review the proposed reporting lines. 🆕 marks new wires. The algorithm
            builds the tree top-down, preferring different departments and higher levels.
          </p>
        </div>
      }
      footer={
        <div className="flex items-center justify-between gap-2 w-full">
          <div className="text-[10px] font-mono text-slate-500">
            {proposal && (
              <>
                {proposal.stats.newWires} new wire
                {proposal.stats.newWires !== 1 ? 's' : ''} will be applied
                {proposal.stats.newWires === 0 && ' — no changes needed'}
              </>
            )}
          </div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onClose}
              disabled={applying}
              className="px-4 py-2 rounded-xl bg-slate-900 border border-slate-800 text-xs text-slate-300 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={apply}
              disabled={applying || !proposal || proposal.stats.newWires === 0}
              className="px-4 py-2 rounded-xl bg-indigo-600 text-white text-xs font-bold hover:bg-indigo-500 disabled:opacity-40"
            >
              {applying
                ? 'Applying…'
                : proposal
                  ? `Apply ${proposal.stats.newWires} change${proposal.stats.newWires !== 1 ? 's' : ''}`
                  : 'Apply'}
            </button>
          </div>
        </div>
      }
    >
      <div>
        {loading && (
          <div className="text-center text-slate-500 font-mono text-xs py-12 animate-pulse">
            ⏳ Computing proposed hierarchy…
          </div>
        )}
        {err && (
          <div className="px-3 py-2 rounded-xl bg-rose-950/40 border border-rose-500/30 text-[11px] text-rose-200 mb-3">
            {err}
          </div>
        )}
        {proposal && (
          <>
            <div className="mb-4 flex flex-wrap items-center gap-3 text-[10px] font-mono uppercase tracking-widest text-slate-400">
              <span className="px-2 py-1 rounded-md bg-slate-900 border border-slate-800">
                🌳 {proposal.stats.totalNodes} people
              </span>
              <span className="px-2 py-1 rounded-md bg-indigo-500/15 border border-indigo-500/30 text-indigo-200">
                {proposal.roots.length} root
              </span>
              <span className="px-2 py-1 rounded-md bg-slate-900 border border-slate-800">
                depth {proposal.stats.maxDepth}
              </span>
              <span className="px-2 py-1 rounded-md bg-slate-900 border border-slate-800">
                avg {proposal.stats.avgChildren.toFixed(1)} kids
              </span>
              <span className="px-2 py-1 rounded-md bg-emerald-500/15 border border-emerald-500/30 text-emerald-200">
                🆕 {proposal.stats.newWires} new
              </span>
              <span className="px-2 py-1 rounded-md bg-slate-900 border border-slate-800 text-slate-500">
                {proposal.stats.unchangedWires} unchanged
              </span>
            </div>

            <div className="overflow-x-auto pb-3">
              <div className="min-w-fit">
                {proposal.roots.map((root) => (
                  <AutoWireTreeNode key={root.user.id} node={root} depth={0} defaultExpanded={true} />
                ))}
              </div>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
};
