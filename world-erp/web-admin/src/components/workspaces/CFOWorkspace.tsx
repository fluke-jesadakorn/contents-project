import React from 'react';
import { ExecutiveWorkspace } from './ExecutiveWorkspace';
import { ExecutiveNarrative } from '@/components/ai/ExecutiveNarrative';
import { ensureRejectReason } from './_rejectGuard';
import { useToast, Kpi } from '@/components/ui';

const fmt = (n: any) => parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

interface CFOWorkspaceProps {
  currentUser: any;
  execReport: any;
  activeSubTab: any;
  setActiveSubTab: any;
  expenses: any[];
  selectedExpense: any;
  onSelectExpense: (e: any) => void;
  onAdvance: (id: number, decision: 'approve' | 'reject') => Promise<any> | void;
  actionComment: string;
  setActionComment: (s: string) => void;
  loading: boolean;
  getStatusBadge: (s: string) => React.ReactNode;
}

export const CFOWorkspace: React.FC<CFOWorkspaceProps> = ({
  currentUser: _currentUser,
  execReport,
  activeSubTab,
  setActiveSubTab,
  expenses,
  selectedExpense,
  onSelectExpense,
  onAdvance,
  actionComment,
  setActionComment,
  loading,
  getStatusBadge,
}) => {
  const toast = useToast();
  const cfoQueue = expenses.filter((e: any) => e.status === 'cfo_review');
  const recent = expenses.filter((e: any) =>
    ['approved', 'paid', 'rejected', 'cfo_review'].includes(e.status)
  );

  return (
    <div className="space-y-8 animate-fade-in">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 glass-panel p-6 rounded-3xl border-purple-500/30 bg-gradient-to-br from-purple-950/20 to-slate-950">
          <span className="text-[10px] font-mono font-black uppercase text-purple-400 block tracking-wider">
            💼 CFO Approval Center
          </span>
          <h2 className="text-xl font-bold text-white">Final Approval Queue (Forwarded by Accounting Manager)</h2>
          <p className="text-xs text-slate-400 mt-1">You approve when the amount exceeds the threshold, or the account category is high-risk</p>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <KPI label="Pending CFO" value={cfoQueue.length} accent="purple" />
            <KPI label="Value Pending Approval" value={fmt(cfoQueue.reduce((s, e) => s + parseFloat(e.total_amount || 0), 0)) + ' THB'} accent="purple" />
            <KPI label="Approved This Month" value={expenses.filter(e => e.status === 'approved' || e.status === 'paid').length} accent="slate" />
          </div>

          <div className="mt-6 space-y-2 max-h-[480px] overflow-y-auto">
            {cfoQueue.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">No requests pending CFO</p>
            ) : cfoQueue.map((e: any) => (
              <div key={e.id}
                   onClick={() => onSelectExpense(e)}
                   className={`p-3 rounded-2xl border cursor-pointer ${
                     selectedExpense?.id === e.id
                       ? 'bg-purple-600/15 border-purple-500'
                       : 'bg-slate-950/60 border-slate-900 hover:border-slate-800'
                   }`}>
                <div className="flex justify-between text-xs font-mono">
                  <span className="text-white font-bold">EXP-{e.id}</span>
                  {getStatusBadge(e.status)}
                </div>
                <div className="text-[11px] text-slate-300 truncate">{e.vendor_name}</div>
                <div className="flex justify-between mt-1">
                  <span className="text-[10px] text-slate-500">{e.submitter_dept}</span>
                  <span className="text-purple-400 font-mono text-xs">{fmt(e.total_amount)} THB</span>
                </div>
              </div>
            ))}
          </div>

          {selectedExpense && (
            <div className="mt-4 border-t border-slate-800 pt-4">
              <p className="text-xs text-slate-400 mb-2">
                EXP-{selectedExpense.id}: {selectedExpense.vendor_name} · {fmt(selectedExpense.total_amount)} THB
              </p>
              <textarea
                value={actionComment}
                onChange={(e: any) => setActionComment(e.target.value)}
                placeholder="CFO comment"
                className="w-full bg-slate-950/60 border border-slate-800 rounded-2xl p-3 text-xs text-white"
                rows={2}
              />
              <div className="flex gap-2 mt-3">
                <button onClick={() => onAdvance(selectedExpense.id, 'approve')} disabled={loading}
                        className="flex-1 bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 rounded-2xl py-2 text-sm font-bold">
                  ✓ Final Approve
                </button>
                <button onClick={() => {
                          const err = ensureRejectReason(actionComment);
                          if (err) { toast.warning(err, "Invalid reason"); return; }
                          onAdvance(selectedExpense.id, 'reject');
                        }} disabled={loading}
                        className="flex-1 bg-rose-500/20 text-rose-300 border border-rose-500/30 rounded-2xl py-2 text-sm font-bold">
                  ✗ Reject
                </button>
              </div>
            </div>
          )}
        </div>

        <div className="glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-3">📜 Recent Decisions</h3>
          <div className="space-y-2 max-h-[600px] overflow-y-auto">
            {recent.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">None yet</p>
            ) : recent.slice(0, 20).map((e: any) => (
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
            ))}
          </div>
        </div>
      </div>

      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <h3 className="text-base font-bold text-white mb-3">📊 Cockpit</h3>
        <div className="mb-4">
          <ExecutiveNarrative execReport={execReport} audience="cfo" />
        </div>
        <ExecutiveWorkspace execReport={execReport} activeSubTab={activeSubTab} setActiveSubTab={setActiveSubTab} />
      </div>
    </div>
  );
};

const KPI = Kpi;
