import React, { useState } from 'react';
import { ExecutiveWorkspace } from './ExecutiveWorkspace';
import { ExecutiveNarrative } from '@/components/ai/ExecutiveNarrative';
import { Modal } from '@/components/ui';
import { ensureRejectReason } from './_rejectGuard';
import { useToast } from '@/components/ui';

const fmt = (n: any) => parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

type SubView = 'main' | 'override' | 'all';
type OverrideTarget = { type: 'expense' | 'pr'; id: number; status?: string } | null;

export const CEOWorkspace = ({
  currentUser: _currentUser, execReport, activeSubTab, setActiveSubTab,
  expenses, prs: _prs, onSelectExpense: _onSelectExpense, onAdvance, onOverride, actionComment, setActionComment,
  loading, getStatusBadge,
  initialSubView,
}: {
  currentUser: any;
  execReport: any;
  activeSubTab: any;
  setActiveSubTab: any;
  expenses: any[];
  prs?: any[];
  onSelectExpense: (e: any) => void;
  onAdvance?: (id: number, decision: 'approve' | 'reject') => Promise<any> | void;
  onOverride: (targetType: 'expense' | 'pr', targetId: number, decision: 'approved' | 'rejected' | 'paid', reason: string) => Promise<any> | void;
  actionComment?: string;
  setActionComment?: (s: string) => void;
  loading: boolean;
  getStatusBadge: (s: string) => React.ReactNode;
  initialSubView?: SubView;
}) => {
  const [overrideTarget, setOverrideTarget] = useState<OverrideTarget>(null);
  const [subView, setSubView] = useState<SubView>(initialSubView || 'main');

  const stuck = expenses.filter((e: any) => {
    if (['approved', 'paid', 'rejected'].includes(e.status)) return false;
    const age = (Date.now() - new Date(e.created_at).getTime()) / 86400000;
    return age > 1;
  });
  const ceoQueue = expenses.filter((e: any) => e.status === 'ceo_review');
  const recent = expenses.filter((e: any) => ['approved', 'paid', 'rejected'].includes(e.status)).slice(0, 15);
  const inFlight = expenses.filter((e: any) =>
    ['head_review', 'accounting_review', 'cfo_review', 'ceo_review', 'finance_review'].includes(e.status)
  );

  return (
    <div className="space-y-8 animate-fade-in">
      <div className="glass-panel p-6 sm:p-8 rounded-3xl bg-gradient-to-br from-rose-950/40 via-slate-950 to-purple-950/40 border-rose-500/20 relative overflow-hidden shadow-2xl">
        <div className="absolute top-0 right-0 w-80 h-80 bg-rose-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10">
          <span className="px-3 py-1 rounded-full bg-rose-500/20 text-rose-300 text-[10px] font-mono font-black uppercase border border-rose-500/30">
            👑 CEO Read-Only Cockpit
          </span>
          <h2 className="text-2xl font-black text-white tracking-tight mt-2">
            Executive Command Center — with Override Rights
          </h2>
          <p className="text-xs text-slate-300 mt-1 max-w-2xl font-sans">
            You see the same overview as the CFO, but you cannot edit policies. You can use Override to force approve/reject any item with proper justification.
          </p>
        </div>
      </div>

      {ceoQueue.length > 0 && (
        <CEOReviewQueue
          queue={ceoQueue}
          onAdvance={onAdvance}
          actionComment={actionComment}
          setActionComment={setActionComment}
          loading={loading}
          getStatusBadge={getStatusBadge}
          fmt={fmt}
        />
      )}

      {/* In-page sub-view tabs */}
      <div className="flex gap-2 flex-wrap">
        {[
          { key: 'main',     icon: '👑', label: 'Cockpit' },
          { key: 'override', icon: '⚡', label: `Override Queue (${stuck.length})` },
          { key: 'all',      icon: '🛡️', label: `All Approvals (${inFlight.length})` },
        ].map((t: any) => (
          <button
            key={t.key}
            onClick={() => setSubView(t.key)}
            className={`px-4 py-2 rounded-2xl text-xs font-bold transition-all ${
              subView === t.key
                ? 'bg-rose-500/20 text-rose-300 border border-rose-500/40'
                : 'bg-slate-900/60 text-slate-400 border border-slate-800 hover:border-slate-700'
            }`}
          >
            <span className="mr-1.5">{t.icon}</span>{t.label}
          </button>
        ))}
      </div>

      {/* Two columns swap content per subView */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* LEFT column */}
        <div className="glass-panel p-6 rounded-3xl border-amber-500/30">
          <h3 className="text-base font-bold text-white mb-3">
            {subView === 'main'     && `⚠ Items Stuck in Pipeline (${stuck.length})`}
            {subView === 'override' && `⚠ Items Stuck in Pipeline (${stuck.length})`}
            {subView === 'all'      && `🔄 In-Flight Approvals (${inFlight.length})`}
          </h3>
          {subView === 'all' ? (
            <div className="space-y-2 max-h-[500px] overflow-y-auto">
              {inFlight.length === 0 ? (
                <p className="text-center text-xs text-slate-500 font-mono py-6">None</p>
              ) : inFlight.slice(0, 30).map((e: any) => (
                <div key={e.id} className="p-3 rounded-2xl border border-slate-900 bg-slate-950/40">
                  <div className="flex justify-between text-xs font-mono">
                    <span className="text-white font-bold">EXP-{e.id}</span>
                    {getStatusBadge(e.status)}
                  </div>
                  <div className="text-[10px] text-slate-500 truncate">{e.vendor_name}</div>
                  <div className="flex justify-between items-center">
                    <span className="text-[10px] text-slate-500">{e.submitter_dept}</span>
                    <span className="text-slate-400 font-mono text-[11px]">{fmt(e.total_amount)} THB</span>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <>
                <p className="text-[10px] text-slate-400 mb-2 font-mono">
                  Items still unfinished and in the system for more than 1 day
                </p>
              <div className="space-y-2 max-h-[500px] overflow-y-auto">
                {stuck.length === 0 ? (
                  <p className="text-center text-xs text-slate-500 font-mono py-6">No stuck items</p>
                ) : stuck.map((e: any) => (
                  <div key={e.id} className="p-3 rounded-2xl border border-amber-500/30 bg-amber-950/10">
                    <div className="flex justify-between text-xs font-mono">
                      <span className="text-white font-bold">EXP-{e.id}</span>
                      {getStatusBadge(e.status)}
                    </div>
                    <div className="text-[11px] text-slate-300 truncate">{e.vendor_name}</div>
                    <div className="flex justify-between items-center mt-1">
                      <span className="text-[10px] text-slate-500">{e.submitter_dept}</span>
                      <span className="text-amber-400 font-mono text-xs">{fmt(e.total_amount)} THB</span>
                    </div>
                    <div className="flex gap-2 mt-2">
                      <button
                        onClick={() => setOverrideTarget({ type: 'expense', id: e.id })}
                        className="flex-1 text-[10px] font-mono font-bold bg-rose-500/20 text-rose-300 border border-rose-500/40 rounded-lg py-1">
                        ⚡ Override
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        {/* RIGHT column */}
        <div className="glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-3">
            {subView === 'main'     && `✅ Recent Decisions (${recent.length})`}
            {subView === 'override' && `🔥 All Stuck (${stuck.length})`}
            {subView === 'all'      && `✅ Recent Decisions (${recent.length})`}
          </h3>
          <div className="space-y-2 max-h-[500px] overflow-y-auto">
            {subView === 'main' && (recent.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">None yet</p>
            ) : recent.map((e: any) => (
              <div key={e.id} className="p-3 rounded-2xl border border-slate-900 bg-slate-950/40">
                <div className="flex justify-between text-xs font-mono">
                  <span className="text-white font-bold">EXP-{e.id}</span>
                  {getStatusBadge(e.status)}
                </div>
                <div className="text-[10px] text-slate-500 truncate">{e.vendor_name}</div>
                <div className="text-right text-slate-400 font-mono text-[11px]">
                  {fmt(e.total_amount)} THB
                </div>
              </div>
            )))}
            {subView === 'override' && (stuck.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">None</p>
            ) : stuck.slice(0, 30).map((e: any) => (
              <div key={e.id} className="p-3 rounded-2xl border border-amber-500/30 bg-amber-950/10">
                <div className="flex justify-between text-xs font-mono">
                  <span className="text-white font-bold">EXP-{e.id}</span>
                  {getStatusBadge(e.status)}
                </div>
                <div className="text-[10px] text-slate-500 truncate">{e.vendor_name}</div>
                <div className="flex justify-between items-center">
                  <span className="text-[10px] text-slate-500">{e.submitter_dept}</span>
                  <span className="text-amber-400 font-mono text-[11px]">{fmt(e.total_amount)} THB</span>
                </div>
              </div>
            )))}
            {subView === 'all' && (recent.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">None yet</p>
            ) : recent.map((e: any) => (
              <div key={e.id} className="p-3 rounded-2xl border border-slate-900 bg-slate-950/40">
                <div className="flex justify-between text-xs font-mono">
                  <span className="text-white font-bold">EXP-{e.id}</span>
                  {getStatusBadge(e.status)}
                </div>
                <div className="text-[10px] text-slate-500 truncate">{e.vendor_name}</div>
                <div className="text-right text-slate-400 font-mono text-[11px]">
                  {fmt(e.total_amount)} THB
                </div>
              </div>
            )))}
          </div>
        </div>
      </div>

      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <h3 className="text-base font-bold text-white mb-3">📊 Cockpit (read-only)</h3>
        <div className="mb-4">
          <ExecutiveNarrative execReport={execReport} audience="ceo" />
        </div>
        <ExecutiveWorkspace execReport={execReport} activeSubTab={activeSubTab} setActiveSubTab={setActiveSubTab} />
      </div>

      <Modal
        open={!!overrideTarget}
        onClose={() => setOverrideTarget(null)}
        title={overrideTarget ? `CEO Override — ${overrideTarget.type.toUpperCase()}-${overrideTarget.id}` : ''}
        subtitle="Select terminal status and provide reason (≥ 5 characters)"
        tone="rose"
        footer={
          overrideTarget && (
            <>
              <button
                onClick={() => setOverrideTarget(null)}
                className="px-4 py-2 rounded-lg bg-slate-800 text-slate-300 text-xs font-bold hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={async () => { await onOverride(overrideTarget.type, overrideTarget.id, 'rejected', 'CEO override'); setOverrideTarget(null); }}
                className="px-4 py-2 rounded-lg bg-rose-600 text-white text-xs font-bold hover:bg-rose-500"
              >
                Force Reject
              </button>
              <button
                onClick={async () => { await onOverride(overrideTarget.type, overrideTarget.id, 'approved', 'CEO override'); setOverrideTarget(null); }}
                className="px-4 py-2 rounded-lg bg-emerald-600 text-white text-xs font-bold hover:bg-emerald-500"
              >
                Force Approve
              </button>
            </>
          )
        }
      >
        {overrideTarget && (
          <div className="text-[12px] text-slate-200 font-sans">
            You are about to force a terminal status on this item. The action is logged in <code className="text-rose-300">ceo_overrides</code> with your reason.
          </div>
        )}
      </Modal>
    </div>
  );
};

interface CEOReviewQueueProps {
  queue: any[];
  onAdvance?: (id: number, decision: 'approve' | 'reject') => Promise<any> | void;
  actionComment?: string;
  setActionComment?: (s: string) => void;
  loading: boolean;
  getStatusBadge: (s: string) => React.ReactNode;
  fmt: (n: any) => string;
}

const CEOReviewQueue: React.FC<CEOReviewQueueProps> = ({
  queue,
  onAdvance,
  actionComment = '',
  setActionComment = () => {},
  loading,
  getStatusBadge: _getStatusBadge,
  fmt: _fmt,
}) => {
  const toast = useToast();
  const [busyId, setBusyId] = useState<number | null>(null);

  const handle = async (id: number, decision: 'approve' | 'reject') => {
    if (decision === 'reject') {
      const err = ensureRejectReason(actionComment);
      if (err) {
        toast.warning(err, 'Invalid reason');
        return;
      }
    }
    if (!onAdvance) return;
    setBusyId(id);
    try {
      await onAdvance(id, decision);
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="glass-panel p-6 rounded-3xl border-amber-500/30 bg-gradient-to-br from-amber-950/10 to-slate-950">
      <div className="flex items-baseline justify-between mb-4">
        <div>
          <span className="text-[10px] font-mono font-black uppercase text-amber-400 block tracking-wider">
            🦅 CEO Strategic Approval
          </span>
          <h2 className="text-xl font-bold text-white">
            Items Awaiting CEO Sign-off ({queue.length})
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Resolved by amount &gt; 500k THB or Marketing/Rental &gt; 200k THB
          </p>
        </div>
      </div>

      <div className="space-y-2">
        {queue.map((e: any) => (
          <div
            key={e.id}
            className="p-4 rounded-2xl border border-amber-500/30 bg-amber-950/10"
          >
            <div className="flex items-start gap-4 flex-wrap">
              <div className="flex-1 min-w-[240px]">
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-2xl">🦅</span>
                  <div>
                    <div className="text-sm font-bold text-white">EXP-{e.id}</div>
                    <div className="text-[10px] text-amber-300 font-mono">
                      Awaiting CEO · forwarded by CFO
                    </div>
                  </div>
                </div>
                <div className="text-xs text-slate-400 grid grid-cols-2 gap-x-4 gap-y-1 mt-2">
                  <div>
                    <span className="text-slate-500">Submitter:</span> {e.submitter_name ?? `User #${e.submitter_id}`}
                  </div>
                  <div>
                    <span className="text-slate-500">Dept:</span> {e.submitter_dept ?? '—'}
                  </div>
                  <div>
                    <span className="text-slate-500">Vendor:</span> {e.vendor_name}
                  </div>
                  <div>
                    <span className="text-slate-500">Amount:</span>{' '}
                    <span className="text-amber-300 font-mono">{_fmt(e.total_amount)} THB</span>
                  </div>
                </div>
              </div>
              <div className="flex flex-col gap-2 min-w-[280px]">
                <textarea
                  value={actionComment}
                  onChange={(ev: any) => setActionComment(ev.target.value)}
                  placeholder="CEO comment (required when rejecting)"
                  rows={2}
                  className="w-full bg-slate-950/60 border border-slate-800 rounded-2xl p-3 text-xs text-white"
                />
                <div className="flex gap-2">
                  <button
                    onClick={() => handle(e.id, 'reject')}
                    disabled={loading || busyId === e.id}
                    className="flex-1 bg-rose-500/20 text-rose-300 border border-rose-500/30 rounded-2xl py-2 text-xs font-bold disabled:opacity-50"
                  >
                    ✗ Reject
                  </button>
                  <button
                    onClick={() => handle(e.id, 'approve')}
                    disabled={loading || busyId === e.id}
                    className="flex-1 bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 rounded-2xl py-2 text-xs font-bold disabled:opacity-50"
                  >
                    {busyId === e.id ? '…' : '✓ Approve → Finance'}
                  </button>
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default CEOWorkspace;
