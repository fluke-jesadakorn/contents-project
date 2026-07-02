// Sub-views for the workbench workspace.
// Each view corresponds to a tile.subView value in tile-config.ts.

import React, { useState } from 'react';

const fmt = (n: any) => parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

type GetStatusBadge = (status: string) => React.ReactNode;

// ─── STAFF: history view (split off from the upload+history combined workspace) ───
export const StaffHistoryView = ({ currentUser, expenses, onSelectExpense, selectedExpense, getStatusBadge }: {
  currentUser: any;
  expenses: any[];
  onSelectExpense: (e: any) => void;
  selectedExpense: any;
  getStatusBadge: GetStatusBadge;
}) => {
  const userExpenses = expenses.filter((e) => e.submitter_id === currentUser.id);
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-emerald-500/20 bg-gradient-to-br from-emerald-950/30 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-emerald-400 block tracking-wider">
          📋 My Reimbursement History
        </span>
        <h2 className="text-xl font-bold text-white">All Reimbursement History for {currentUser.fullname?.split(' ')[0]}</h2>
        <p className="text-xs text-slate-400 mt-1">Track status at every step</p>
      </div>

      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        {userExpenses.length === 0 ? (
          <p className="text-center py-12 text-xs text-slate-500 font-mono">
            No items yet — go to &quot;Submit Slip / Request Reimbursement&quot; to get started
          </p>
        ) : (
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-mono">
                <th className="py-3 px-4">Document No.</th>
                <th className="py-3 px-4">Vendor</th>
                <th className="py-3 px-4 text-right">Amount (THB)</th>
                <th className="py-3 px-4 text-center">Status</th>
                <th className="py-3 px-4 text-center">Next Step</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-900/60">
              {userExpenses.map((exp) => {
                const isSelected = selectedExpense?.id === exp.id;
                return (
                  <tr key={exp.id} onClick={() => onSelectExpense(exp)}
                      className={`text-xs cursor-pointer transition-all ${
                        isSelected ? 'bg-emerald-500/10 border-l-4 border-l-emerald-500' : 'hover:bg-slate-900/50'
                      }`}>
                    <td className="py-4 px-4 font-mono">
                      <span className="text-white font-bold block">EXP-{exp.id}</span>
                      <span className="text-[10px] text-slate-500">
                        {new Date(exp.transaction_date).toLocaleDateString('th-TH', { day: '2-digit', month: 'short', year: 'numeric' })}
                      </span>
                    </td>
                    <td className="py-4 px-4">
                      <span className="text-slate-200 font-bold block truncate max-w-[200px]">{exp.vendor_name}</span>
                      <span className="text-[10px] text-slate-400 font-mono truncate max-w-[250px] block">
                        {exp.items ? exp.items.map((i: any) => i.description).join(', ') : ''}
                      </span>
                    </td>
                    <td className="py-4 px-4 text-right font-black text-white font-mono text-sm">
                      {fmt(exp.total_amount)}
                    </td>
                    <td className="py-4 px-4 text-center">{getStatusBadge(exp.status)}</td>
                    <td className="py-4 px-4 text-center text-[11px] text-slate-400 font-sans">
                        {exp.status === 'ocr_extracted' && 'Pending accounting review'}
                        {exp.status === 'head_review' && 'Pending department head'}
                        {exp.status === 'accounting_review' && 'Pending accounting manager'}
                        {exp.status === 'cfo_review' && 'Pending CFO'}
                        {exp.status === 'accountant_reviewed' && 'Pending approver'}
                        {exp.status === 'approved' && 'Pending refund transfer'}
                        {exp.status === 'paid' && <span className="text-emerald-400 font-bold">✨ Refund transferred successfully</span>}
                        {exp.status === 'rejected' && (
                          <div className="flex flex-col items-center gap-0.5">
                            <span className="text-rose-400 font-bold">Rejected</span>
                            {exp.rejection_reason ? (
                              <span
                                className="text-[10px] text-rose-300/80 max-w-[280px] italic"
                                title={exp.rejection_reason}
                              >
                                &quot;{exp.rejection_reason.length > 90 ? exp.rejection_reason.slice(0, 90) + '…' : exp.rejection_reason}&quot;
                              </span>
                            ) : (
                              <span className="text-[10px] text-slate-500">Please contact the accounting department</span>
                            )}
                          </div>
                        )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};

// ─── ACCOUNT OFFICER: COA search view ───
export const COASearchView = ({ coa, onFetchSuggestions, suggestions, loadingSuggestion }: {
  coa: any[];
  onFetchSuggestions: (idx: number, desc: string) => void;
  suggestions: Record<number, any[]>;
  loadingSuggestion: Record<number, boolean>;
}) => {
  const [query, setQuery] = useState('');
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-indigo-500/20 bg-gradient-to-br from-indigo-950/30 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-indigo-400 block tracking-wider">
          🔍 COA Semantic Search
        </span>
        <h2 className="text-xl font-bold text-white">Semantic Account Code Search (BGE-M3)</h2>
        <p className="text-xs text-slate-400 mt-1">Type an item description, e.g. &quot;taxi fare&quot; → the system auto-matches</p>
        <input
          type="text"
          value={query}
          onChange={(e: React.ChangeEvent<HTMLInputElement>) => { setQuery(e.target.value); onFetchSuggestions(0, e.target.value); }}
          placeholder="e.g. travel, office rent, AWS hosting…"
          className="mt-4 w-full bg-slate-950/60 border border-slate-800 rounded-2xl px-4 py-3 text-sm text-white"
        />
      </div>

      {(suggestions[0] || loadingSuggestion[0]) && (
        <div className="glass-panel p-6 rounded-3xl border-slate-800">
          <h3 className="text-base font-bold text-white mb-4">
            {loadingSuggestion[0] ? '🔄 Searching…' : '🎯 Top matches'}
          </h3>
          <div className="space-y-2">
            {(suggestions[0] || []).map((s) => (
              <div key={s.code} className="flex items-center justify-between p-3 rounded-2xl border border-slate-800 bg-slate-950/60">
                <div>
                  <div className="text-xs font-mono text-indigo-300">[{s.code}] {s.name_th}</div>
                  <div className="text-[10px] text-slate-500">{s.name}</div>
                </div>
                <div className="text-emerald-400 font-mono text-sm font-bold">
                  {(s.similarity ?? 0).toFixed(1)}%
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <h3 className="text-base font-bold text-white mb-3">📒 All Chart of Accounts ({coa.length})</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 max-h-[500px] overflow-y-auto">
          {coa.map((c) => (
            <div key={c.code} className="p-3 rounded-xl border border-slate-800 bg-slate-950/40">
              <div className="text-[10px] font-mono text-indigo-300">[{c.code}]</div>
              <div className="text-xs font-bold text-white">{c.name_th}</div>
              <div className="text-[10px] text-slate-500">{c.name}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ─── ACCOUNT OFFICER: slip search view ───
export const SlipSearchView = ({ expenses, onSelectExpense, getStatusBadge }: {
  expenses: any[];
  onSelectExpense: (e: any) => void;
  getStatusBadge: GetStatusBadge;
}) => {
  const [q, setQ] = useState('');
  const filtered = expenses.filter((e) => {
    if (!q) return true;
    const s = q.toLowerCase();
    return (e.vendor_name || '').toLowerCase().includes(s)
      || String(e.total_amount).includes(s)
      || `exp-${e.id}`.includes(s);
  });
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-indigo-500/20 bg-gradient-to-br from-indigo-950/30 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-indigo-400 block tracking-wider">
          🔎 Slip / Expense Search
        </span>
        <h2 className="text-xl font-bold text-white">Search Receipts / Reimbursements</h2>
        <input
          type="text"
          value={q}
          onChange={(e: React.ChangeEvent<HTMLInputElement>) => setQ(e.target.value)}
          placeholder="Search by vendor, amount, or EXP-XX"
          className="mt-3 w-full bg-slate-950/60 border border-slate-800 rounded-2xl px-4 py-3 text-sm text-white"
        />
      </div>
      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <p className="text-xs text-slate-500 font-mono mb-3">{filtered.length} results</p>
        <div className="space-y-2 max-h-[500px] overflow-y-auto">
          {filtered.map((e) => (
            <div key={e.id} onClick={() => onSelectExpense(e)}
                 className="p-3 rounded-2xl border border-slate-800 bg-slate-950/60 cursor-pointer hover:border-slate-700">
              <div className="flex justify-between text-xs font-mono">
                <span className="text-white font-bold">EXP-{e.id}</span>
                {getStatusBadge(e.status)}
              </div>
              <div className="text-[11px] text-slate-300 truncate">{e.vendor_name}</div>
              <div className="text-right text-emerald-400 font-mono text-xs mt-1">{fmt(e.total_amount)} THB</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ─── HEAD OF DEPT: team view ───
export const TeamView = ({ currentUser }: { currentUser: any }) => {
  const dept = currentUser?.dept_group_name ?? currentUser?.department ?? '—';
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-amber-500/20 bg-gradient-to-br from-amber-950/30 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-amber-400 block tracking-wider">
          👥 Team — {dept}
        </span>
        <h2 className="text-xl font-bold text-white">{dept} Department Members</h2>
        <p className="text-xs text-slate-400 mt-1">Your team data — to be connected with the API in the next step</p>
      </div>
      <div className="glass-panel p-6 rounded-3xl border-slate-800 text-center text-xs text-slate-500 font-mono py-12">
        🚧 Coming soon — directory API
      </div>
    </div>
  );
};

// ─── ACCOUNTING MANAGER: reconciliation view ───
export const ReconciliationView = ({ expenses, journals }: {
  expenses: any[];
  journals: any[];
}) => {
  const totalApproved = expenses
    .filter((e) => ['approved', 'paid'].includes(e.status))
    .reduce((s, e) => s + parseFloat(e.total_amount || 0), 0);
  const totalPending = expenses
    .filter((e) => !['approved', 'paid', 'rejected'].includes(e.status))
    .reduce((s, e) => s + parseFloat(e.total_amount || 0), 0);
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-cyan-500/20 bg-gradient-to-br from-cyan-950/30 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-cyan-400 block tracking-wider">
          📊 Reconciliation
        </span>
        <h2 className="text-xl font-bold text-white">Account Balance Reconciliation</h2>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Stat label="Approved + Paid" value={fmt(totalApproved) + ' THB'} accent="emerald" />
        <Stat label="Pending in pipeline" value={fmt(totalPending) + ' THB'} accent="amber" />
        <Stat label="Journal entries" value={String(journals.length)} accent="indigo" />
      </div>
      <div className="glass-panel p-6 rounded-3xl border-slate-800 text-center text-xs text-slate-500 font-mono py-12">
        🚧 Full reconciliation grid coming in next iteration
      </div>
    </div>
  );
};

const Stat = ({ label, value, accent }: { label: string; value: string; accent: string }) => (
  <div className={`glass-panel p-6 rounded-3xl border-${accent}-500/30`}>
    <span className="text-[10px] text-slate-400 uppercase font-mono font-black block">{label}</span>
    <span className={`text-2xl font-black font-mono mt-2 block text-${accent}-400`}>{value}</span>
  </div>
);
