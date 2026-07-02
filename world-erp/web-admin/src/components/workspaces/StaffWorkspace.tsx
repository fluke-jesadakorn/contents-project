import React, { useState } from 'react';
import { AiActionButton } from '@/components/ai/AiActionButton';

interface StaffWorkspaceProps {
  currentUser: any;
  expenses: any[];
  onSelectExpense: (exp: any) => void;
  selectedExpense?: any;
  loading: boolean;
  getStatusBadge: (status: string) => React.ReactNode;
}

export const StaffWorkspace: React.FC<StaffWorkspaceProps> = ({
  currentUser,
  expenses,
  onSelectExpense,
  selectedExpense,
  loading: _loading,
  getStatusBadge,
}) => {
  const userExpenses = expenses.filter(e => e.submitter_id === currentUser.id);

  const [draft, setDraft] = useState({ vendor: '', amount: '', note: '' });
  const helperInput = `Vendor: ${draft.vendor || '(not set)'}\nAmount: ${draft.amount || '0'} THB\nNote: ${draft.note || '(none)'}\nLanguage: Thai if vendor is Thai, English otherwise.`;

  return (
    <div className="space-y-8 animate-fade-in">
      <div className="glass-panel p-6 sm:p-8 rounded-3xl bg-gradient-to-br from-emerald-950/40 via-slate-950 to-slate-950 border-emerald-500/20 relative overflow-hidden shadow-2xl">
        <div className="absolute -right-10 -bottom-10 w-60 h-60 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none"></div>

        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 text-[10px] font-mono font-bold uppercase border border-emerald-500/30">
                Staff Requester
              </span>
              <span className="text-slate-400 text-xs">LINE OA Connected</span>
            </div>
            <h2 className="text-2xl font-black text-white tracking-tight">
              Hello, {currentUser.fullname} 👋
            </h2>
            <p className="text-xs text-slate-300 mt-1 max-w-xl font-sans leading-relaxed">
              Upload a receipt image above to extract vendor, items, and amount via the AI OCR pipeline. The system forwards your submission to the accountant for review.
            </p>
          </div>

          <div className="bg-slate-900/80 p-4 rounded-2xl border border-slate-800 text-center min-w-[160px]">
            <span className="text-[10px] text-slate-400 uppercase font-mono font-bold block">Requests In Progress</span>
            <span className="text-2xl font-black text-emerald-400 font-mono mt-1 block">
              {userExpenses.filter(e => e.status !== 'paid' && e.status !== 'rejected').length} items
            </span>
          </div>
        </div>

        <div className="mt-6 pt-6 border-t border-slate-800/80">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-3">
            <input
              value={draft.vendor}
              onChange={e => setDraft(d => ({ ...d, vendor: e.target.value }))}
              placeholder="Vendor (e.g. Starbucks)"
              className="bg-slate-900/60 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white"
            />
            <input
              value={draft.amount}
              onChange={e => setDraft(d => ({ ...d, amount: e.target.value }))}
              placeholder="Amount in THB"
              type="number"
              className="bg-slate-900/60 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white font-mono"
            />
            <input
              value={draft.note}
              onChange={e => setDraft(d => ({ ...d, note: e.target.value }))}
              placeholder="Quick context (e.g. client meeting)"
              className="bg-slate-900/60 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white"
            />
          </div>
          <AiActionButton
            sectionKey="staff:submit"
            task="chat"
            systemPrompt="You help employees write clean, professional expense descriptions for an accounting system. Output ONE short polished description (1-2 sentences) suitable for submission. Match the language to the vendor name (Thai vendor -> Thai, English vendor -> English). Include the amount. No bullet points, no commentary."
            input={helperInput}
            buttonLabel="Help me describe this expense"
            resultTitle="AI Description Suggestion"
            tone="emerald"
            glyph="✍️"
          />
        </div>
      </div>

      {/* ACTIVE SUBMISSIONS LIST */}
      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <div className="flex justify-between items-center mb-6 pb-4 border-b border-slate-800">
          <div>
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <span>⏳</span> My Reimbursements Tracker (My Reimbursements Tracker)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">Track accounting review, manager budget approval, and refund transfer status</p>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-mono">
                    <th className="py-3 px-4">Document No. / Date</th>
                    <th className="py-3 px-4">Vendor / Item</th>
                    <th className="py-3 px-4 text-right">Claim Amount (THB)</th>
                    <th className="py-3 px-4 text-center">Current Status</th>
                    <th className="py-3 px-4 text-center">Next Step</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-900/60">
              {userExpenses.length === 0 ? (
                <tr>
                  <td colSpan={5} className="text-center py-12 text-xs text-slate-500 font-mono">
                    No reimbursement entries yet. Please select a simulated receipt scan above to get started.
                  </td>
                </tr>
              ) : (
                userExpenses.map((exp) => {
                  const isSelected = selectedExpense?.id === exp.id;
                  return (
                    <tr
                      key={exp.id}
                      onClick={() => onSelectExpense(exp)}
                      className={`text-xs hover:bg-slate-900/50 cursor-pointer transition-all ${
                        isSelected ? 'bg-emerald-500/10 border-l-4 border-l-emerald-500 font-medium' : ''
                      }`}
                    >
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
                        {parseFloat(exp.total_amount).toLocaleString('th-TH', { minimumFractionDigits: 2 })}
                      </td>
                      <td className="py-4 px-4 text-center">
                        {getStatusBadge(exp.status)}
                      </td>
                      <td className="py-4 px-4 text-center text-[11px] text-slate-400 font-sans">
                        {exp.status === 'ocr_extracted' && 'Pending accounting review'}
                        {exp.status === 'accountant_reviewed' && 'Pending manager approval for payment'}
                        {exp.status === 'approved' && 'Pending refund transfer to your account'}
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
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
