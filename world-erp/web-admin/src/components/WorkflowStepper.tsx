import React from 'react';

interface WorkflowStepperProps {
  currentStatus: string;
  activeRole: string;
  expenseId?: number | string;
  rejectionReason?: string | null;
  rejectionActorName?: string | null;
  rejectedAt?: string | null;
  approvedActorName?: string | null;
  approvedAt?: string | null;
}

export const WorkflowStepper: React.FC<WorkflowStepperProps> = ({
  currentStatus,
  activeRole,
  expenseId,
  rejectionReason,
  rejectionActorName,
  rejectedAt,
  approvedActorName,
  approvedAt,
}) => {
  const steps = [
    { key: 'ocr_extracted', role: 'staff', position: 'Staff', label: '1. OCR Extracted', desc: 'Scan Slip via LINE OA', icon: '📸' },
    { key: 'supervisor_review', role: 'supervisor', position: 'Supervisor', label: '2. Supervisor Approved', desc: 'Direct manager signs off', icon: '👥' },
    { key: 'head_review', role: 'head_of_department', position: 'Head of Department (HoD)', label: '3. HoD Approved', desc: 'Department Authorization', icon: '🛡️' },
    { key: 'account_officer_review', role: 'account_officer', position: 'Account Officer (AO)', label: '4. Account Officer', desc: 'Audit & GL Mapping', icon: '🧾' },
    { key: 'account_supervisor_review', role: 'account_supervisor', position: 'Account Supervisor (AS)', label: '5. Account Supervisor', desc: 'Senior Accountant Sign-off', icon: '📊' },
    { key: 'accounting_review', role: 'accounting_manager', position: 'Accounting Manager (AM)', label: '6. Account Manager', desc: 'Books Closure', icon: '⚙️' },
    { key: 'cfo_review', role: 'cfo', position: 'CFO', label: '7. CFO Approved', desc: 'Final Authority', icon: '👑' },
    { key: 'ceo_review', role: 'ceo', position: 'CEO', label: '7b. CEO Approved', desc: 'Strategic / capex sign-off', icon: '🦅' },
    { key: 'finance_review', role: 'finance', position: 'Finance', label: '8. Finance Disbursement', desc: 'Release cash & post GL', icon: '💳' },
    { key: 'paid', role: 'admin', position: 'Disburse & Post', label: '9. Paid', desc: 'Disbursed', icon: '✅' }
  ];

  const order = [
    'draft',
    'ocr_extracted',
    'supervisor_review',
    'head_review',
    'account_officer_review',
    'account_supervisor_review',
    'accounting_review',
    'cfo_review',
    'ceo_review',
    'finance_review',
    'approved',
    'paid',
  ];
  const currentIndex = order.indexOf(currentStatus);

  if (currentStatus === 'rejected') {
    return (
      <div className="glass-panel p-5 rounded-3xl border-rose-500/30 bg-rose-950/10 mb-6 animate-fade-in">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="p-2.5 bg-rose-500/20 rounded-2xl text-rose-400 text-xl">❌</span>
            <div>
              <span className="text-[10px] font-mono font-black uppercase tracking-widest text-rose-400">Workflow Terminated</span>
              <h3 className="text-sm font-bold text-white">Reimbursement Claim Rejected</h3>
            </div>
          </div>
          <span className="text-xs font-mono text-slate-400">Status: REJECTED</span>
        </div>
        {rejectionReason && (
          <div className="mt-3 px-3 py-2 rounded-2xl bg-rose-950/40 border border-rose-500/30">
            <div className="text-[10px] uppercase font-mono tracking-widest text-rose-300 mb-1">
              Rejection reason
            </div>
            <p className="text-xs text-rose-100 italic">&quot;{rejectionReason}&quot;</p>
            {(rejectionActorName || rejectedAt) && (
              <div className="text-[10px] text-rose-300/70 mt-1.5 font-mono">
                {rejectionActorName ? `by ${rejectionActorName}` : ''}
                {rejectionActorName && rejectedAt ? ' · ' : ''}
                {rejectedAt ? new Date(rejectedAt).toLocaleString('th-TH') : ''}
              </div>
            )}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="glass-panel p-6 rounded-3xl border-slate-800/80 mb-8 animate-fade-in relative overflow-hidden">
      {/* STEPPER HEADER */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center pb-4 mb-5 border-b border-slate-800/80 gap-2">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 uppercase tracking-wider">
            Pipeline Stepper
          </span>
          <span className="text-xs text-slate-300 font-bold">
            {expenseId ? `Claim #EXP-${expenseId} Lifecycle` : 'Standard Reimbursement Process Guide'}
          </span>
        </div>
        <div className="text-[11px] text-slate-400 font-mono">
          <span>Active Persona Role: </span>
          <span className="text-indigo-300 font-bold uppercase">{activeRole === 'admin' ? 'CFO/CEO' : activeRole}</span>
        </div>
      </div>

      {/* 4-STEP GRID */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-3 relative">
        {steps.map((step, idx) => {
          const stepIndex = order.indexOf(step.key);
          const isPassed = currentIndex >= stepIndex;
          const isCurrent = currentIndex + 1 === stepIndex || (currentStatus === step.key);
          const isRoleMatch = activeRole === step.role || (activeRole === 'admin' && step.role === 'admin');

          let stepStyle = 'bg-slate-950/40 border-slate-900 text-slate-500';
          let badgeText = 'PENDING';
          let badgeColor = 'bg-slate-800 text-slate-500';

          if (isPassed) {
            stepStyle = 'bg-emerald-950/20 border-emerald-500/30 text-emerald-300 shadow-lg shadow-emerald-950/50';
            badgeText = 'COMPLETED';
            badgeColor = 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30';
          }
          if (isCurrent && !isPassed) {
            stepStyle = 'bg-indigo-950/30 border-indigo-500 text-white shadow-xl shadow-indigo-500/10 ring-1 ring-indigo-500/50';
            badgeText = 'ACTIVE STEP';
            badgeColor = 'bg-indigo-500 text-white animate-pulse';
          }

          return (
            <div
              key={step.key}
              className={`p-4 rounded-2xl border transition-all flex flex-col justify-between relative overflow-hidden ${stepStyle} ${
                isRoleMatch ? 'ring-2 ring-purple-500/40' : ''
              }`}
            >
              {isRoleMatch && (
                <div className="absolute top-0 right-0 bg-purple-500/20 text-purple-300 text-[8px] font-mono font-bold px-2 py-0.5 rounded-bl uppercase">
                  YOUR ROLE
                </div>
              )}

              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-2xl">{step.icon}</span>
                  <span className={`text-[9px] font-mono font-black px-1.5 py-0.5 rounded uppercase tracking-wider ${badgeColor}`}>
                    {badgeText}
                  </span>
                </div>
                <h4 className="text-xs font-bold leading-tight mt-1">{step.label}</h4>
                <p className="text-[10px] text-slate-400 mt-1 leading-normal font-sans">{step.desc}</p>

                <div className="mt-3 pt-2 border-t border-slate-800/60">
                  <div className="text-[9px] font-mono uppercase tracking-widest text-slate-500 leading-none mb-1">
                    Approver
                  </div>
                  <div className={`text-[11px] font-bold leading-tight ${isPassed || isCurrent ? 'text-amber-300' : 'text-slate-300'}`}>
                    👤 {step.position}
                  </div>
                  {step.key === 'approved' && (approvedActorName || approvedAt) && isPassed && (
                    <div className="mt-1.5 text-[10px] text-emerald-300 font-mono leading-tight">
                      ✓ {approvedActorName || 'Unnamed'}
                      {approvedAt ? ` · ${new Date(approvedAt).toLocaleString('th-TH')}` : ''}
                    </div>
                  )}
                </div>
              </div>

              {/* STEP CONNECTOR LINE ARROW FOR DESKTOP */}
              {idx < steps.length - 1 && (
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
