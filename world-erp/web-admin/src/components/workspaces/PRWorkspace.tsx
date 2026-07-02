import React, { useState } from 'react';
import { ensureRejectReason } from './_rejectGuard';
import { useToast, useDialog } from '@/components/ui';

const fmt = (n: any)=> parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

const emptyItem = () => ({ description: '', qty: 1, unit_price: 0, mapped_account_code: '' });

export const PRWorkspace = ({ currentUser, prs, pos, coa, onSubmitPr, onAdvancePr, onSelectPr, selectedPr, loading }: { currentUser: any; prs: any; pos: any; coa: any; onSubmitPr: any; onAdvancePr: any; onSelectPr: any; selectedPr: any; loading: any })=> {
  const toast = useToast();
  const dialog = useDialog();
  const [vendor, setVendor] = useState('');
  const [needBy, setNeedBy] = useState('');
  const [justification, setJustification] = useState('');
  const [isRecurring, setIsRecurring] = useState(false);
  const [items, setItems] = useState([emptyItem()]);
  const [deptId, setDeptId] = useState(1);

  const total = items.reduce((s: any, it: any)=> s + (Number(it.qty) || 0) * (Number(it.unit_price) || 0), 0);

  const myPRs = prs.filter((p: any)=> p.requester_id === currentUser.id);
  const awaitingMe = prs.filter((p: any)=> {
    if (currentUser.role_name === 'head_of_department') {
      return p.requester_dept_group_id === currentUser.dept_group_id && p.status === 'head_review';
    }
    if (currentUser.role_name === 'accounting_manager') {
      return p.status === 'accounting_review';
    }
    if (currentUser.role_name === 'cfo') {
      return p.status === 'cfo_review';
    }
    return false;
  });

  const submit = async (e: any)=> {
    e.preventDefault();
    if (!vendor || items.length === 0 || items.every((i: any)=> !i.description)) {
      toast.warning('Please enter vendor and at least 1 item', 'Required fields');
      return;
    }
    const r = await onSubmitPr({
      vendorName: vendor,
      departmentId: deptId,
      needByDate: needBy || null,
      totalEstimate: total,
      justification,
      isRecurring,
      items: items.filter((i: any)=> i.description),
    });
    if (r?.success) {
      setVendor(''); setNeedBy(''); setJustification(''); setIsRecurring(false);
      setItems([emptyItem()]);
    }
  };

  return (
    <div className="space-y-8 animate-fade-in">
      <div className="glass-panel p-6 sm:p-8 rounded-3xl border-emerald-500/20 bg-gradient-to-br from-emerald-950/20 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-emerald-400 block tracking-wider">
          🛒 Purchase Requisition (PR)
        </span>
        <h2 className="text-xl font-bold text-white">Create Purchase / Service Request</h2>
        <p className="text-xs text-slate-400 mt-1">PRs follow the approval chain per Policy defined by the CFO</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <form onSubmit={submit} className="glass-panel p-6 rounded-3xl border-slate-800 space-y-3">
          <h3 className="text-base font-bold text-white mb-2">📝 Create New PR</h3>
          <Field label="Vendor Name">
            <input value={vendor} onChange={(e: any)=> setVendor(e.target.value)} required
                   className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white" />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Needed By">
              <input type="date" value={needBy} onChange={(e: any)=> setNeedBy(e.target.value)}
                     className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white" />
            </Field>
            <Field label="Department">
              <select value={deptId} onChange={(e: any)=> setDeptId(parseInt(e.target.value, 10))}
                      className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white">
                <option value={1}>Development</option>
                <option value={2}>Engineering</option>
                <option value={3}>Sales</option>
                <option value={4}>Marketing</option>
                <option value={5}>Human Resource</option>
                <option value={6}>Finance & Account</option>
                <option value={7}>Executive</option>
              </select>
            </Field>
          </div>
          <Field label="Justification">
            <textarea value={justification} onChange={(e: any)=> setJustification(e.target.value)} rows={2}
                      className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white" />
          </Field>
          <label className="flex items-center gap-2 text-xs text-slate-300">
            <input type="checkbox" checked={isRecurring} onChange={(e: any)=> setIsRecurring(e.target.checked)}
                   className="accent-emerald-500" />
            Recurring expense
          </label>

          <div className="border-t border-slate-800 pt-3">
            <h4 className="text-xs font-bold text-slate-300 mb-2">Items / Services</h4>
            {items.map((it: any, idx: any)=> (
              <div key={idx} className="grid grid-cols-12 gap-2 mb-2">
                <input value={it.description} placeholder="Item"
                       onChange={(e: any)=> updateItem(items, setItems, idx, { description: e.target.value })}
                       className="col-span-5 bg-slate-950/60 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white" />
                <input type="number" min="0" step="0.01" value={it.qty} placeholder="Qty"
                       onChange={(e: any)=> updateItem(items, setItems, idx, { qty: parseFloat(e.target.value) || 0 })}
                       className="col-span-2 bg-slate-950/60 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white" />
                <input type="number" min="0" step="0.01" value={it.unit_price} placeholder="Unit Price"
                       onChange={(e: any)=> updateItem(items, setItems, idx, { unit_price: parseFloat(e.target.value) || 0 })}
                       className="col-span-3 bg-slate-950/60 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white" />
                <button type="button" onClick={() => setItems(items.filter((_: any, i: any)=> i !== idx))}
                        className="col-span-2 text-[10px] bg-rose-500/10 text-rose-300 border border-rose-500/30 rounded-lg">
                  Remove
                </button>
                <select value={it.mapped_account_code}
                        onChange={(e: any)=> updateItem(items, setItems, idx, { mapped_account_code: e.target.value })}
                        className="col-span-12 bg-slate-950/60 border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-white">
                  <option value="">— Select Account —</option>
                  {coa.filter((c: any)=> c.account_type === 'expense').map((c: any)=> (
                    <option key={c.code} value={c.code}>[{c.code}] {c.name_th}</option>
                  ))}
                </select>
              </div>
            ))}
            <button type="button" onClick={() => setItems([...items, emptyItem()])}
                    className="text-[11px] text-emerald-300 font-mono">+ Add Item</button>
          </div>

          <div className="flex justify-between items-center pt-2 border-t border-slate-800">
            <span className="text-xs text-slate-400 font-mono">Total Estimate</span>
            <span className="text-lg font-black text-emerald-400 font-mono">{fmt(total)} THB</span>
          </div>
          <button type="submit" disabled={loading}
                  className="w-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 rounded-2xl py-2 text-sm font-bold">
            Submit PR to Approval Chain
          </button>
        </form>

        <div className="space-y-6">
          <div className="glass-panel p-6 rounded-3xl border-slate-800">
            <h3 className="text-base font-bold text-white mb-3">⏳ Awaiting My Approval ({awaitingMe.length})</h3>
            <div className="space-y-2 max-h-[300px] overflow-y-auto">
              {awaitingMe.length === 0 ? (
                <p className="text-center text-xs text-slate-500 font-mono py-4">None</p>
              ) : awaitingMe.map((p: any)=> (
                <div key={p.id} className="p-3 rounded-2xl border border-slate-900 bg-slate-950/60">
                  <div className="flex justify-between text-xs font-mono">
                    <span className="text-white font-bold">PR-{p.id}</span>
                    <span className="text-amber-400">{fmt(p.total_estimate)} THB</span>
                  </div>
                  <div className="text-[11px] text-slate-300 truncate">{p.vendor_name}</div>
                  <div className="flex gap-2 mt-2">
                    <button onClick={() => onAdvancePr(p.id, 'approve')}
                            className="flex-1 text-[11px] bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 rounded-lg py-1">
                      ✓ Approve
                    </button>
                    <button onClick={async () => {
                            const reason = await dialog.prompt({
                              title: `Reject PR-${p.id}`,
                              message: 'Provide a rejection reason. It will be visible to the requester.',
                              placeholder: 'Reason…',
                              minLength: 5,
                              confirmLabel: 'Reject',
                              tone: 'rose',
                            });
                            if (reason === null) return;
                            const err = ensureRejectReason(reason);
                            if (err) {
                              toast.warning(err, 'Invalid reason');
                              return;
                            }
                            await onAdvancePr(p.id, 'reject', reason.trim());
                          }}
                            className="flex-1 text-[11px] bg-rose-500/20 text-rose-300 border border-rose-500/30 rounded-lg py-1">
                      ✗ Reject
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="glass-panel p-6 rounded-3xl border-slate-800">
            <h3 className="text-base font-bold text-white mb-3">📦 My PRs ({myPRs.length})</h3>
            <div className="space-y-2 max-h-[300px] overflow-y-auto">
              {myPRs.length === 0 ? (
                <p className="text-center text-xs text-slate-500 font-mono py-4">None yet</p>
              ) : myPRs.slice(0, 20).map((p: any)=> {
                const linkedPo = (pos || []).find((x: any)=> x.pr_id === p.id);
                return (
                  <div
                    key={p.id}
                    onClick={() => onSelectPr && onSelectPr(p)}
                    className={`p-3 rounded-2xl border cursor-pointer transition-all ${
                      selectedPr?.id === p.id ? 'bg-cyan-600/15 border-cyan-500' : 'bg-slate-950/40 border-slate-900 hover:border-slate-800'
                    }`}
                  >
                    <div className="flex justify-between text-xs font-mono">
                      <span className="text-white font-bold">PR-{p.id}</span>
                      <span className={`px-2 py-0.5 rounded text-[9px] ${
                        p.status === 'approved' ? 'bg-emerald-500/20 text-emerald-300' :
                        p.status === 'rejected' ? 'bg-rose-500/20 text-rose-300' :
                        'bg-amber-500/20 text-amber-300'
                      }`}>
                        {p.status}
                      </span>
                    </div>
                    <div className="text-[11px] text-slate-300 truncate">{p.vendor_name}</div>
                    <div className="flex justify-between items-center mt-1">
                      <span className="text-[10px] text-slate-500">{p.requester_dept_group_name ?? p.dept_name ?? '—'}</span>
                      <span className="text-emerald-400 font-mono text-xs">{fmt(p.total_estimate)} THB</span>
                    </div>
                    {linkedPo && (
                      <div className="mt-1.5 flex gap-2 text-[10px] font-mono">
                        <span className="text-cyan-300">📦 PO-{linkedPo.id}</span>
                        <span className={
                          linkedPo.status === 'settled' ? 'text-emerald-300' :
                          linkedPo.status === 'approved' ? 'text-cyan-300' :
                          linkedPo.status === 'rejected' ? 'text-rose-300' :
                          'text-amber-300'
                        }>
                          {linkedPo.status}
                        </span>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const Field = ({ label, children }: { label: any; children: any })=> (
  <div>
    <label className="block text-[10px] uppercase tracking-wider text-slate-400 font-bold mb-1">{label}</label>
    {children}
  </div>
);

function updateItem(items: any, setItems: any, idx: any, patch: any) {
  const next = items.slice();
  next[idx] = { ...next[idx], ...patch };
  setItems(next);
}
