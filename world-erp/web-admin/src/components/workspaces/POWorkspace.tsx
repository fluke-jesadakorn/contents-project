import React, { useState, useRef } from 'react';
import { ensureRejectReason } from './_rejectGuard';
import { useToast, Kpi } from '@/components/ui';
import { useCan } from '@/lib/rbac/client';

const fmt = (n: any) => parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

interface POWorkspaceProps {
  currentUser: any;
  pos: any[];
  selectedPo: any | null;
  onSelectPo: (po: any) => void;
  onAdvancePo: (poId: number, decision: 'approve' | 'reject', comment?: string) => Promise<any>;
  onAttachPayslip: (poId: number, slipId: number) => Promise<any>;
  actionComment: string;
  setActionComment: (c: string) => void;
  loading: boolean;
}

export const POWorkspace: React.FC<POWorkspaceProps> = ({
  currentUser,
  pos,
  selectedPo,
  onSelectPo,
  onAdvancePo,
  onAttachPayslip,
  actionComment,
  setActionComment,
  loading,
}) => {
  const toast = useToast();
  const fileRef = useRef<HTMLInputElement | null>(null);
  const [attachPoId, setAttachPoId] = useState<number | null>(null);
  const [uploading, setUploading] = useState(false);

  const rbacRoleId = currentUser?.rbac_role_id ?? null;
  const canApproveFlag = useCan(rbacRoleId, 'tile-po', 'update');
  const canSettleFlag = useCan(rbacRoleId, 'tile-po', 'create');

  const pending = pos.filter((p) => p.status === 'pending_approval' || p.status === 'po_cfo');
  const approved = pos.filter((p) => p.status === 'approved');
  const settled = pos.filter((p) => p.status === 'settled');
  const rejected = pos.filter((p) => p.status === 'rejected');
  const visible = pos.filter((p) => !['settled', 'rejected'].includes(p.status));

  // Default to true while the matrix is loading (optimistic). Once
  // canApproveFlag / canSettleFlag resolve, the actual RBAC answer wins.
  const canApprove = canApproveFlag !== false;
  const canSettle = canSettleFlag !== false;

  const handleUploadClick = (poId: number) => {
    setAttachPoId(poId);
    fileRef.current?.click();
  };

  const handleFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !attachPoId) return;
    setUploading(true);
    try {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('target_type', 'po');
      fd.append('target_id', String(attachPoId));
      const up = await fetch('/api/upload', { method: 'POST', body: fd });
      const upRes = await up.json();
      if (!upRes?.slipId) {
        toast.error(`Slip upload failed: ${upRes?.error || 'unknown'}`, 'Upload');
        return;
      }
      const r = await onAttachPayslip(attachPoId, upRes.slipId);
      if (!(r as any)?.success) {
        toast.error(`Failed to attach slip: ${(r as any)?.error || 'unknown'}`, 'Error');
      }
    } finally {
      setUploading(false);
      setAttachPoId(null);
      if (fileRef.current) fileRef.current.value = '';
    }
  };

  return (
    <div className="space-y-8 animate-fade-in">
      <input ref={fileRef} type="file" accept="image/*,application/pdf" hidden onChange={handleFile} />

      <div className="glass-panel p-6 sm:p-8 rounded-3xl border-cyan-500/20 bg-gradient-to-br from-cyan-950/20 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-cyan-400 block tracking-wider">
          📦 Purchase Orders (PO)
        </span>
        <h2 className="text-xl font-bold text-white">PO Queue & Payment Slip Attachment</h2>
        <p className="text-xs text-slate-400 mt-1">
          POs are auto-generated once the PR is fully approved, and are closed by attaching the payment slip
        </p>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mt-5">
          <KPI label="Pending Approval"   value={pending.length}  accent="amber"  />
          <KPI label="Approved (Awaiting Slip)" value={approved.length} accent="cyan" />
          <KPI label="Closed"  value={settled.length}  accent="emerald" />
          <KPI label="Rejected"   value={rejected.length} accent="rose"   />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <Queue
          title={`📥 POs Awaiting Approval (${pending.length})`}
          items={pending}
          selectedPo={selectedPo}
          onSelectPo={onSelectPo}
          canApprove={canApprove}
          onAdvance={(poId: number, dec: 'approve' | 'reject') => {
            if (dec === 'reject') {
              const err = ensureRejectReason(actionComment);
              if (err) { toast.warning(err, "Invalid reason"); return; }
              onAdvancePo(poId, dec, actionComment);
            } else {
              onAdvancePo(poId, dec);
            }
          }}
          loading={loading}
        />

        <Queue
          title={`📎 Approved POs Awaiting Slip (${approved.length})`}
          items={approved}
          selectedPo={selectedPo}
          onSelectPo={onSelectPo}
          canSettle={canSettle}
          onAttach={handleUploadClick}
          uploading={uploading}
        />
      </div>

      {selectedPo && (
        <div className="glass-panel p-6 rounded-3xl border-cyan-500/30">
          <h3 className="text-base font-bold text-white mb-3">
            PO Details #{selectedPo.id} — {selectedPo.vendor_name}
          </h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-3 text-[11px] font-mono">
            <Field label="PR" value={`PR-${selectedPo.pr_id}`} />
            <Field label="Status" value={selectedPo.status} />
            <Field label="Amount" value={`${fmt(selectedPo.total_amount)} THB`} />
            <Field label="Policy" value={selectedPo.policy_name || 'default'} />
          </div>

          {selectedPo.items?.length > 0 && (
            <div className="overflow-x-auto mt-3">
              <table className="w-full text-left text-xs border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-mono">
                    <th className="py-2 px-2">Item</th>
                    <th className="py-2 px-2 text-right">Qty</th>
                    <th className="py-2 px-2 text-right">Unit Price</th>
                    <th className="py-2 px-2 text-right">Total</th>
                    <th className="py-2 px-2">Account</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-900/60 font-mono">
                  {selectedPo.items.map((it: any) => (
                    <tr key={it.id}>
                      <td className="py-2 px-2 text-slate-200 font-sans">{it.description}</td>
                      <td className="py-2 px-2 text-right">{parseFloat(it.qty).toLocaleString('th-TH')}</td>
                      <td className="py-2 px-2 text-right">{fmt(it.unit_price)}</td>
                      <td className="py-2 px-2 text-right text-emerald-300 font-bold">
                        {fmt(parseFloat(it.qty) * parseFloat(it.unit_price))}
                      </td>
                      <td className="py-2 px-2 text-indigo-300">[{it.mapped_account_code || '-'}]</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {canApprove && (selectedPo.status === 'pending_approval' || selectedPo.status === 'po_cfo') && (
            <div className="mt-4 border-t border-slate-800 pt-4">
              <textarea
                value={actionComment}
                onChange={(e) => setActionComment(e.target.value)}
                placeholder="Comment (required ≥ 5 characters when Rejecting)"
                className="w-full bg-slate-950/60 border border-slate-800 rounded-2xl p-3 text-xs text-white"
                rows={2}
              />
              <div className="flex gap-2 mt-3">
                <button
                  onClick={() => onAdvancePo(selectedPo.id, 'approve')}
                  disabled={loading}
                  className="flex-1 bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 rounded-2xl py-2 text-sm font-bold"
                >
                  ✓ Approve
                </button>
                <button
                  onClick={() => {
                    const err = ensureRejectReason(actionComment);
                    if (err) { toast.warning(err, "Invalid reason"); return; }
                    onAdvancePo(selectedPo.id, 'reject', actionComment);
                  }}
                  disabled={loading}
                  className="flex-1 bg-rose-500/20 text-rose-300 border border-rose-500/30 rounded-2xl py-2 text-sm font-bold"
                >
                  ✗ Reject
                </button>
              </div>
            </div>
          )}

          {selectedPo.status === 'approved' && canSettle && (
            <div className="mt-4 border-t border-slate-800 pt-4">
              <button
                onClick={() => handleUploadClick(selectedPo.id)}
                disabled={uploading}
                className="w-full bg-cyan-500/20 text-cyan-300 border border-cyan-500/30 rounded-2xl py-2 text-sm font-bold"
              >
                {uploading ? '⏳ Uploading…' : '📎 Attach Payment Slip (Close PO)'}
              </button>
            </div>
          )}

          {selectedPo.status === 'settled' && (
            <div className="mt-4 px-3 py-2 rounded-2xl bg-emerald-950/30 border border-emerald-500/30">
              <span className="text-[10px] font-mono uppercase tracking-widest text-emerald-400 block">
                ✓ PO closed successfully
              </span>
              <span className="text-[11px] text-emerald-200 font-mono">
                by {selectedPo.settled_actor_name || 'accountant'}
                {selectedPo.settled_at ? ` · ${new Date(selectedPo.settled_at).toLocaleString('th-TH')}` : ''}
              </span>
              {selectedPo.paid_slip_path && (
                <a
                  href={`/api/slips/file?path=${encodeURIComponent(selectedPo.paid_slip_path)}`}
                  target="_blank"
                  rel="noreferrer"
                  className="block mt-1 text-[10px] font-mono text-cyan-300 underline"
                >
                  📎 {selectedPo.paid_slip_path.split('/').pop()}
                </a>
              )}
            </div>
          )}
        </div>
      )}

      {settled.length > 0 && (
        <div className="glass-panel p-6 rounded-3xl border-emerald-500/20">
          <h3 className="text-sm font-bold text-white mb-3">✅ Closed POs ({settled.length})</h3>
          <div className="space-y-2 max-h-[260px] overflow-y-auto">
            {settled.slice(0, 20).map((p) => (
              <div
                key={p.id}
                onClick={() => onSelectPo(p)}
                className="p-3 rounded-2xl border border-slate-900 bg-slate-950/40 cursor-pointer hover:border-emerald-500/40"
              >
                <div className="flex justify-between text-xs font-mono">
                  <span className="text-white font-bold">PO-{p.id} · PR-{p.pr_id}</span>
                  <span className="text-emerald-400">{fmt(p.total_amount)} THB</span>
                </div>
                <div className="text-[11px] text-slate-300 truncate">{p.vendor_name}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {visible.length === 0 && settled.length === 0 && (
        <div className="glass-panel p-6 rounded-3xl border-slate-800 text-center">
          <p className="text-xs text-slate-500 font-mono py-6">No POs in the system yet — POs are auto-generated once a PR is approved</p>
        </div>
      )}
    </div>
  );
};

const Queue = ({
  title, items, selectedPo, onSelectPo, canApprove, canSettle, onAdvance, onAttach, uploading, loading,
}: any) => (
  <div className="glass-panel p-6 rounded-3xl border-slate-800">
    <h3 className="text-base font-bold text-white mb-3">{title}</h3>
    <div className="space-y-2 max-h-[420px] overflow-y-auto">
      {items.length === 0 ? (
          <p className="text-center text-xs text-slate-500 font-mono py-6">None</p>
      ) : items.map((p: any) => (
        <div
          key={p.id}
          onClick={() => onSelectPo(p)}
          className={`p-3 rounded-2xl border cursor-pointer transition-all ${
            selectedPo?.id === p.id ? 'bg-cyan-600/15 border-cyan-500' : 'bg-slate-950/60 border-slate-900 hover:border-slate-800'
          }`}
        >
          <div className="flex justify-between text-xs font-mono">
            <span className="text-white font-bold">PO-{p.id} · PR-{p.pr_id}</span>
            <span className="text-cyan-400">{fmt(p.total_amount)} THB</span>
          </div>
          <div className="text-[11px] text-slate-300 truncate">{p.vendor_name}</div>

          {canApprove && (
            <div className="flex gap-2 mt-2">
              <button
                onClick={(e) => { e.stopPropagation(); onAdvance(p.id, 'approve'); }}
                disabled={loading}
                className="flex-1 text-[11px] bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 rounded-lg py-1"
              >
                ✓ Approve
              </button>
              <button
                onClick={(e) => { e.stopPropagation(); onAdvance(p.id, 'reject'); }}
                disabled={loading}
                className="flex-1 text-[11px] bg-rose-500/20 text-rose-300 border border-rose-500/30 rounded-lg py-1"
              >
                ✗ Reject
              </button>
            </div>
          )}

          {canSettle && onAttach && (
            <button
              onClick={(e) => { e.stopPropagation(); onAttach(p.id); }}
              disabled={uploading}
              className="mt-2 w-full text-[11px] bg-cyan-500/20 text-cyan-300 border border-cyan-500/30 rounded-lg py-1"
            >
              📎 Attach Payment Slip
            </button>
          )}
        </div>
      ))}
    </div>
  </div>
);

const KPI = (props: any) => <Kpi {...props} size="sm" />;

const Field = ({ label, value }: any) => (
  <div className="bg-slate-950/60 px-3 py-2 rounded-xl border border-slate-800">
    <span className="text-[9px] uppercase tracking-widest text-slate-500 font-mono block">{label}</span>
    <span className="text-[12px] text-white font-mono font-bold">{value}</span>
  </div>
);