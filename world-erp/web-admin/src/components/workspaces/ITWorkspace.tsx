import React from 'react';
import { Kpi } from '@/components/ui';

const fmt = (n: any) =>
  parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

interface ITWorkspaceProps {
  currentUser: any;
  expenses: any[];
  prs: any[];
  selectedExpense: any;
  onSelectExpense: (exp: any) => void;
  getStatusBadge: (status: string) => React.ReactNode;
}

export const ITWorkspace: React.FC<ITWorkspaceProps> = ({
  currentUser: _currentUser,
  expenses,
  prs,
  selectedExpense,
  onSelectExpense,
  getStatusBadge,
}) => {
  const byStatus = expenses.reduce<Record<string, number>>((acc, e) => {
    acc[e.status] = (acc[e.status] || 0) + 1;
    return acc;
  }, {});

  const totalValue = expenses.reduce(
    (s, e) => s + (parseFloat(e.total_amount) || 0),
    0
  );

  const sortedExpenses = [...expenses].sort(
    (a, b) => new Date(b.created_at || b.transaction_date).getTime() -
              new Date(a.created_at || a.transaction_date).getTime()
  );

  return (
    <div className="space-y-8 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-slate-700/40 bg-gradient-to-br from-slate-900/40 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-slate-400 block tracking-wider">
          🧰 IT Operations Desk — Read Only
        </span>
        <h2 className="text-xl font-bold text-white">
          All Expenses (System-wide)
        </h2>
        <p className="text-xs text-slate-400 mt-1">
          Read-only view across the whole system for IT support, audits, and troubleshooting. You cannot approve or reject here.
        </p>
        <div className="grid grid-cols-4 gap-4 mt-4">
          <KPI label="Total Expenses" value={expenses.length} accent="slate" />
          <KPI label="Total Value" value={`${fmt(totalValue)} THB`} accent="slate" />
          <KPI label="Total PRs" value={prs.length} accent="slate" />
          <KPI label="Distinct Statuses" value={Object.keys(byStatus).length} accent="slate" />
        </div>
      </div>

      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <h3 className="text-base font-bold text-white mb-4">📊 Status Breakdown</h3>
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
          {Object.entries(byStatus)
            .sort((a, b) => b[1] - a[1])
            .map(([status, count]) => (
              <div
                key={status}
                className="bg-slate-950/60 border border-slate-900 rounded-2xl p-3"
              >
                <span className="text-[10px] font-mono uppercase text-slate-500 block">
                  {status}
                </span>
                <span className="text-xl font-black text-white font-mono mt-1 block">
                  {count}
                </span>
              </div>
            ))}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-4">
            📑 All Expenses ({sortedExpenses.length})
          </h3>
          <div className="space-y-2 max-h-[600px] overflow-y-auto">
            {sortedExpenses.length === 0 ? (
              <p className="text-center text-xs text-slate-500 font-mono py-6">
                No expenses in the system
              </p>
            ) : (
              sortedExpenses.map((e) => (
                <div
                  key={e.id}
                  onClick={() => onSelectExpense(e)}
                  className={`p-3 rounded-2xl border cursor-pointer transition-colors ${
                    selectedExpense?.id === e.id
                      ? 'bg-slate-700/30 border-slate-500'
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
                    <span className="text-slate-300 font-mono text-xs">
                      {fmt(e.total_amount)} THB
                    </span>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-3">🔍 Inspect</h3>
          {selectedExpense ? (
            <div className="space-y-3 text-xs">
              <KV k="ID" v={`EXP-${selectedExpense.id}`} />
              <KV k="Vendor" v={selectedExpense.vendor_name} />
              <KV k="Submitter" v={selectedExpense.submitter_name} />
              <KV k="Department" v={selectedExpense.submitter_dept} />
              <KV k="Status" v={selectedExpense.status} />
              <KV k="Date" v={selectedExpense.transaction_date ? new Date(selectedExpense.transaction_date).toLocaleDateString('en-GB') : '—'} />
              <KV k="Subtotal" v={`${fmt(selectedExpense.subtotal)} THB`} />
              <KV k="VAT" v={`${fmt(selectedExpense.vat_amount)} THB`} />
              <KV k="Total" v={`${fmt(selectedExpense.total_amount)} THB`} />
              <KV k="Payment" v={selectedExpense.payment_method || '—'} />
              <KV k="Math OK" v={selectedExpense.is_corrupted ? '⚠ mismatch' : '✓ ok'} />
              {selectedExpense.correction_notes && (
                <KV k="Notes" v={selectedExpense.correction_notes} />
              )}
              <div className="pt-3 border-t border-slate-900 text-[10px] text-slate-500 font-mono">
                🔒 Read-only mode. Use Cockpit → AI Settings for technical operations.
              </div>
            </div>
          ) : (
            <p className="text-center text-xs text-slate-500 font-mono py-6">
              Click an expense to inspect
            </p>
          )}
        </div>
      </div>
    </div>
  );
};

const KPI = Kpi;

const KV: React.FC<{ k: string; v: any }> = ({ k, v }) => (
  <div className="flex justify-between items-start gap-2">
    <span className="text-slate-500 font-mono text-[11px] shrink-0">{k}</span>
    <span className="text-slate-200 font-sans text-right break-words min-w-0">{String(v ?? '—')}</span>
  </div>
);

export default ITWorkspace;