import React, { useState } from 'react';
import { ensureRejectReason } from './_rejectGuard';
import { disbursePayment, rejectDisbursement } from '@/app/actions-finance';
import { useToast, Modal, Kpi } from '@/components/ui';

const fmt = (n: any) =>
  parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

interface FinanceWorkspaceProps {
  currentUser: any;
  expenses: any[];
  selectedExpense: any;
  onSelectExpense: (exp: any) => void;
  actionComment: string;
  setActionComment: React.Dispatch<React.SetStateAction<string>>;
  loading: boolean;
  getStatusBadge: (status: string) => React.ReactNode;
}

export const FinanceWorkspace: React.FC<FinanceWorkspaceProps> = ({
  currentUser,
  expenses,
  selectedExpense,
  onSelectExpense,
  actionComment,
  setActionComment,
  loading,
  getStatusBadge,
}) => {
  const toast = useToast();
  const [busyId, setBusyId] = useState<number | null>(null);
  const [rejectTarget, setRejectTarget] = useState<{ id: number; comment: string } | null>(null);

  const pendingQueue = expenses.filter((e: any) => e.status === 'finance_review');
  const recentPaid = expenses
    .filter((e: any) => e.status === 'paid')
    .slice(0, 20);

  const totalValue = pendingQueue.reduce(
    (s, e: any) => s + (parseFloat(e.total_amount) || 0),
    0
  );

  const handleDisburse = async (expenseId: number) => {
    setBusyId(expenseId);
    try {
      const res = await disbursePayment({
        expenseId,
        actorId: currentUser?.id,
        comment: actionComment || undefined,
      });
      if (res.success) {
        toast.success('Payment released', `EXP-${expenseId} → paid`);
        onSelectExpense(null);
        setActionComment('');
      } else {
        toast.error(res.error || 'Failed to disburse', 'Disbursement');
      }
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="space-y-8 animate-fade-in">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 glass-panel p-6 rounded-3xl border-emerald-500/30 bg-gradient-to-br from-emerald-950/20 to-slate-950">
          <span className="text-[10px] font-mono font-black uppercase text-emerald-400 block tracking-wider">
            💳 Finance Disbursement Desk
          </span>
          <h2 className="text-xl font-bold text-white">
            Approved Expenses Awaiting Bank Transfer
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            When you disburse, the GL is posted (Dr expense + VAT, Cr cash at bank) and the
            submitter is notified in-app.
          </p>

          <div className="grid grid-cols-3 gap-4 mt-4">
            <KPI label="Pending Disbursement" value={pendingQueue.length} accent="emerald" />
            <KPI label="Value Pending" value={`${fmt(totalValue)} THB`} accent="emerald" />
            <KPI label="Disbursed Lifetime" value={recentPaid.length} accent="slate" />
          </div>

          <div className="mt-6 space-y-2 max-h-[480px] overflow-y-auto">
            {pendingQueue.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">
                🎉 Nothing waiting on you — disbursement queue is empty.
              </p>
            ) : (
              pendingQueue.map((e: any) => (
                <div
                  key={e.id}
                  onClick={() => onSelectExpense(e)}
                  className={`p-3 rounded-2xl border cursor-pointer transition-colors ${
                    selectedExpense?.id === e.id
                      ? 'bg-emerald-600/15 border-emerald-500'
                      : 'bg-slate-950/60 border-slate-900 hover:border-slate-800'
                  }`}
                >
                  <div className="flex justify-between text-xs font-mono">
                    <span className="text-white font-bold">EXP-{e.id}</span>
                    {getStatusBadge(e.status)}
                  </div>
                  <div className="text-[11px] text-slate-300 truncate">{e.vendor_name}</div>
                  <div className="flex justify-between mt-1">
                    <span className="text-[10px] text-slate-500">
                      {e.submitter_dept} · {e.submitter_name}
                    </span>
                    <span className="text-emerald-400 font-mono text-xs">
                      {fmt(e.total_amount)} THB
                    </span>
                  </div>
                </div>
              ))
            )}
          </div>

          {selectedExpense && (
            <div className="mt-4 border-t border-slate-800 pt-4">
              <p className="text-xs text-slate-400 mb-2">
                EXP-{selectedExpense.id}: {selectedExpense.vendor_name} ·{' '}
                {fmt(selectedExpense.total_amount)} THB
              </p>

              <div className="mb-3 grid grid-cols-3 gap-2 text-[10px] font-mono">
                <div className="bg-slate-950/40 border border-slate-800/70 p-2 rounded-lg">
                  <div className="text-slate-500 uppercase tracking-widest">Submitter</div>
                  <div className="text-slate-200 text-[11px] truncate">
                    {selectedExpense.submitter_name || `User #${selectedExpense.submitter_id}`}
                  </div>
                </div>
                <div className="bg-slate-950/40 border border-slate-800/70 p-2 rounded-lg">
                  <div className="text-slate-500 uppercase tracking-widest">Dept</div>
                  <div className="text-slate-200 text-[11px]">{selectedExpense.submitter_dept}</div>
                </div>
                <div className="bg-slate-950/40 border border-slate-800/70 p-2 rounded-lg">
                  <div className="text-slate-500 uppercase tracking-widest">Date</div>
                  <div className="text-slate-200 text-[11px]">{selectedExpense.transaction_date}</div>
                </div>
              </div>

              <textarea
                value={actionComment}
                onChange={(e) => setActionComment(e.target.value)}
                placeholder="Disbursement note (optional; required when rejecting)"
                className="w-full bg-slate-950/60 border border-slate-800 rounded-2xl p-3 text-xs text-white"
                rows={2}
              />
              <div className="flex gap-2 mt-3">
                <button
                  onClick={() => handleDisburse(selectedExpense.id)}
                  disabled={loading || busyId === selectedExpense.id}
                  className="flex-1 bg-gradient-to-r from-emerald-500 to-teal-500 text-white font-extrabold py-2 rounded-2xl text-sm disabled:opacity-50"
                >
                  {busyId === selectedExpense.id ? '⏳ Processing…' : '💳 Disburse & Post GL'}
                </button>
                <button
                  onClick={() => {
                    const err = ensureRejectReason(actionComment);
                    if (err) {
                      toast.warning(err, 'Invalid reason');
                      return;
                    }
                    setRejectTarget({ id: selectedExpense.id, comment: actionComment });
                  }}
                  disabled={loading}
                  className="flex-1 bg-rose-500/20 text-rose-300 border border-rose-500/30 rounded-2xl py-2 text-sm font-bold"
                >
                  ✗ Reject Disbursement
                </button>
              </div>
            </div>
          )}
        </div>

        <div className="glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-3">💸 Recently Disbursed</h3>
          <div className="space-y-2 max-h-[600px] overflow-y-auto">
            {recentPaid.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">None yet</p>
            ) : (
              recentPaid.map((e: any) => (
                <div
                  key={e.id}
                  className="p-3 rounded-2xl border border-slate-900 bg-slate-950/40"
                >
                  <div className="flex justify-between text-xs font-mono">
                    <span className="text-white font-bold">EXP-{e.id}</span>
                    {getStatusBadge(e.status)}
                  </div>
                  <div className="text-[10px] text-slate-500 truncate">{e.vendor_name}</div>
                  <div className="flex justify-between mt-1">
                    <span className="text-[10px] text-slate-500 truncate">
                      {e.submitter_name}
                    </span>
                    <span className="text-emerald-300 font-mono text-[11px]">
                      {fmt(e.total_amount)} THB
                    </span>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <Modal
        open={!!rejectTarget}
        onClose={() => setRejectTarget(null)}
        title="Reject Disbursement"
        subtitle="Provide a reason (≥ 5 characters)"
        tone="rose"
        footer={
          rejectTarget && (
            <>
              <button
                onClick={() => setRejectTarget(null)}
                className="px-4 py-2 rounded-lg bg-slate-800 text-slate-300 text-xs font-bold hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={async () => {
                  setBusyId(rejectTarget.id);
                  const res = await rejectDisbursement({
                    expenseId: rejectTarget.id,
                    actorId: currentUser?.id,
                    comment: rejectTarget.comment,
                  });
                  setBusyId(null);
                  setRejectTarget(null);
                  if (res.success) toast.success('Disbursement rejected', `EXP-${rejectTarget.id}`);
                  else toast.error(res.error || 'Failed', 'Reject');
                }}
                disabled={busyId !== null}
                className="px-4 py-2 rounded-lg bg-rose-600 text-white text-xs font-bold hover:bg-rose-500 disabled:opacity-50"
              >
                Confirm Reject
              </button>
            </>
          )
        }
      >
        {rejectTarget && (
          <div className="text-[12px] text-slate-200 font-sans">
            Reject disbursement for <strong>EXP-{rejectTarget.id}</strong>? The expense will
            be moved to <code className="text-rose-300">rejected</code> and the submitter
            will see a rejection notification.
          </div>
        )}
      </Modal>
    </div>
  );
};

const KPI = Kpi;

export default FinanceWorkspace;
