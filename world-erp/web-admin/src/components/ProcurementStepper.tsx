import React from 'react';

export interface ProcurementStepperProps {
  pr?: any | null;
  po?: any | null;
  currentRole?: string;
  paidSlipPath?: string | null;
  paidSlipMime?: string | null;
  settledAt?: string | null;
  settledActorName?: string | null;
  prApprovedActorName?: string | null;
  prApprovedAt?: string | null;
  poApprovedActorName?: string | null;
  poApprovedAt?: string | null;
}

const STEPS = [
  { key: 'pr_submitted', label: '1. PR Submitted',  desc: 'Staff submits purchase request',            icon: '📝' },
  { key: 'pr_approved',  label: '2. PR Approved',   desc: 'Passes budget approval chain',        icon: '🛡️' },
  { key: 'po_issued',    label: '3. PO Issued',     desc: 'Issue purchase/service order',            icon: '📦' },
  { key: 'po_approved',  label: '4. PO Approved',   desc: 'Accounting/Manager signs PO approval', icon: '✅' },
  { key: 'payslip',      label: '5. Attach Payslip',desc: 'Attach transfer slip from expense',     icon: '💳📎' },
];

function stepIndexOf(pr: any | null | undefined, po: any | null | undefined): number {
  if (!pr) return 0;
  const prStatus = pr.status;
  const poStatus = po?.status;
  if (prStatus === 'rejected') return -1;
  if (poStatus === 'rejected') return -1;
  if (poStatus === 'settled') return 4;
  if (poStatus === 'approved') return 3;
  if (poStatus === 'pending_approval' || poStatus === 'po_cfo') return 2;
  if (prStatus === 'approved') return 1;
  return 0; // draft, head_review, accounting_review, cfo_review
}

export const ProcurementStepper: React.FC<ProcurementStepperProps> = ({
  pr,
  po,
  currentRole,
  paidSlipPath,
  paidSlipMime,
  settledAt,
  settledActorName,
  prApprovedActorName,
  prApprovedAt,
  poApprovedActorName,
  poApprovedAt,
}) => {
  const idx = stepIndexOf(pr, po);

  if (!pr) {
    return (
      <div className="glass-panel p-5 rounded-3xl border-slate-800/80 mb-6 animate-fade-in">
        <span className="text-[10px] font-mono font-black uppercase tracking-widest text-slate-500">
          Procurement Stepper (PR → PO → Approve → Payslip)
        </span>
        <p className="text-xs text-slate-500 mt-2 font-sans">
          Select a PR or PO from the list below to view the current step status
        </p>
      </div>
    );
  }

  if (idx === -1) {
    const reason = po?.rejection_reason || pr.rejection_reason;
    const actor = po?.rejection_actor_name || pr.rejection_actor_name;
    const when = po?.rejected_at || pr.rejected_at;
    return (
      <div className="glass-panel p-5 rounded-3xl border-rose-500/30 bg-rose-950/10 mb-6 animate-fade-in">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="p-2.5 bg-rose-500/20 rounded-2xl text-rose-400 text-xl">❌</span>
            <div>
              <span className="text-[10px] font-mono font-black uppercase tracking-widest text-rose-400">
                Procurement Terminated
              </span>
              <h3 className="text-sm font-bold text-white">
                {po ? `PO #${po.id} (from PR-${pr.id})` : `PR #${pr.id}`} was rejected
              </h3>
            </div>
          </div>
          <span className="text-xs font-mono text-slate-400">Status: REJECTED</span>
        </div>
        {reason && (
          <div className="mt-3 px-3 py-2 rounded-2xl bg-rose-950/40 border border-rose-500/30">
            <div className="text-[10px] uppercase font-mono tracking-widest text-rose-300 mb-1">
              Rejection reason
            </div>
            <p className="text-xs text-rose-100 italic">&quot;{reason}&quot;</p>
            {(actor || when) && (
              <div className="text-[10px] text-rose-300/70 mt-1.5 font-mono">
                {actor ? `by ${actor}` : ''}
                {actor && when ? ' · ' : ''}
                {when ? new Date(when).toLocaleString('th-TH') : ''}
              </div>
            )}
          </div>
        )}
      </div>
    );
  }

  const prId = pr?.id;
  const poId = po?.id;
  const headerLabel = poId
    ? `PO #${poId} ← PR-${prId}`
    : `PR-${prId}`;

  return (
    <div className="glass-panel p-6 rounded-3xl border-slate-800/80 mb-8 animate-fade-in relative overflow-hidden">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center pb-4 mb-5 border-b border-slate-800/80 gap-2">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-cyan-500/10 text-cyan-400 border border-cyan-500/20 uppercase tracking-wider">
            Procurement Stepper
          </span>
          <span className="text-xs text-slate-300 font-bold">
            {headerLabel} Lifecycle
          </span>
        </div>
        <div className="text-[11px] text-slate-400 font-mono">
          <span>Active Persona Role: </span>
          <span className="text-cyan-300 font-bold uppercase">
            {currentRole === 'admin' ? 'CFO/CEO' : currentRole || 'workspace'}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-5 gap-3 relative">
        {STEPS.map((step, i) => {
          const isPassed = i < idx;
          const isCurrent = i === idx;
          const isPayslip = i === 4;

          let stepStyle = 'bg-slate-950/40 border-slate-900 text-slate-500';
          let badgeText = 'PENDING';
          let badgeColor = 'bg-slate-800 text-slate-500';

          if (isPassed) {
            stepStyle = 'bg-emerald-950/20 border-emerald-500/30 text-emerald-300 shadow-lg shadow-emerald-950/50';
            badgeText = 'COMPLETED';
            badgeColor = 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30';
          }
          if (isCurrent && !isPassed) {
            stepStyle = 'bg-cyan-950/30 border-cyan-500 text-white shadow-xl shadow-cyan-500/10 ring-1 ring-cyan-500/50';
            badgeText = 'ACTIVE STEP';
            badgeColor = 'bg-cyan-500 text-white animate-pulse';
          }

          return (
            <div
              key={step.key}
              className={`p-4 rounded-2xl border transition-all flex flex-col justify-between relative overflow-hidden ${stepStyle}`}
            >
              <div className="flex items-center justify-between mb-2">
                <span className="text-2xl">{step.icon}</span>
                <span className={`text-[9px] font-mono font-black px-1.5 py-0.5 rounded uppercase tracking-wider ${badgeColor}`}>
                  {badgeText}
                </span>
              </div>
              <h4 className="text-xs font-bold leading-tight mt-1">{step.label}</h4>
              <p className="text-[10px] text-slate-400 mt-1 leading-normal font-sans">{step.desc}</p>

              {step.key === 'pr_approved' && isPassed && (prApprovedActorName || prApprovedAt) && (
                <div className="mt-2 text-[10px] text-emerald-300 font-mono leading-tight">
                  ✓ {prApprovedActorName || 'Unnamed'}
                  {prApprovedAt ? ` · ${new Date(prApprovedAt).toLocaleString('th-TH')}` : ''}
                </div>
              )}
              {step.key === 'po_approved' && isPassed && (poApprovedActorName || poApprovedAt) && (
                <div className="mt-2 text-[10px] text-emerald-300 font-mono leading-tight">
                  ✓ {poApprovedActorName || 'Unnamed'}
                  {poApprovedAt ? ` · ${new Date(poApprovedAt).toLocaleString('th-TH')}` : ''}
                </div>
              )}

              {isPayslip && isCurrent && paidSlipPath && (
                <a
                  href={`/api/slips/file?path=${encodeURIComponent(paidSlipPath)}`}
                  target="_blank"
                  rel="noreferrer"
                  className="mt-3 block"
                >
                  {paidSlipMime?.startsWith('image/') ? (
                    <img
                      src={`/api/slips/file?path=${encodeURIComponent(paidSlipPath)}`}
                      alt="payslip"
                      className="w-full h-20 object-cover rounded-xl border border-emerald-500/40"
                    />
                  ) : (
                    <div className="text-[10px] font-mono text-emerald-300 underline truncate">
                      📎 {paidSlipPath.split('/').pop()}
                    </div>
                  )}
                </a>
              )}
              {isPayslip && isPassed && paidSlipPath && (
                <div className="mt-2 text-[9px] font-mono text-emerald-300/80">
                  ✓ by {settledActorName || 'accountant'} · {settledAt ? new Date(settledAt).toLocaleString('th-TH') : ''}
                </div>
              )}

              {i < STEPS.length - 1 && (
                <div className="hidden md:block absolute -right-2 top-1/2 -translate-y-1/2 z-10 text-slate-700 font-black text-sm pointer-events-none">
                  ➔
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};