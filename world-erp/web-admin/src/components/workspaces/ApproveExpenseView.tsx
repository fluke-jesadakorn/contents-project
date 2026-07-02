'use client';

import React, { useState, useMemo } from 'react';
import { useCanBatch } from '@/lib/rbac/client';
import { STAGE_TO_MODULE, STAGE_TO_ROLE } from '@/lib/rbac/stage-types';
import { STATUS_LABELS } from '@/lib/policy/engine';
import { AccessDenied } from '@/components/AccessDenied';
import { useToast } from '@/components/ui';
import { ensureRejectReason } from './_rejectGuard';

const fmt = (n: any) => parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

const ACTIONABLE_STAGES = [
  'supervisor_review',
  'head_review',
  'account_officer_review',
  'account_supervisor_review',
  'accounting_review',
  'cfo_review',
  'ceo_review',
  'finance_review',
];

export interface ApproveExpenseViewProps {
  currentUser: any;
  expenses: any[];
  selectedExpense: any;
  onSelectExpense: (exp: any) => void;
  editForm?: any;
  setEditForm?: React.Dispatch<React.SetStateAction<any>>;
  coa: any[];
  suggestions: Record<number, any[]>;
  loadingSuggestion: Record<number, boolean>;
  onFetchCoaSuggestions?: (itemIndex: number, description: string) => Promise<void>;
  onAccountantSave?: () => Promise<void>;
  onStatusChange?: (status: string, customComment?: string) => Promise<void>;
  onAdvance?: (expenseId: number, decision: 'approve' | 'reject') => Promise<void>;
  onAdvancePr?: (prId: number, decision: 'approve' | 'reject', customComment?: string) => Promise<void>;
  prs?: any[];
  actionComment: string;
  setActionComment: React.Dispatch<React.SetStateAction<string>>;
  loading: boolean;
  getStatusBadge: (status: string) => React.ReactNode;
}

/**
 * Universal approval view. Stage-driven (not persona-driven): renders the
 * rows whose status the actor can act on, based on the RBAC matrix.
 * Action buttons are gated per-row by the stage-* module the actor holds.
 */
export const ApproveExpenseView: React.FC<ApproveExpenseViewProps> = (props) => {
  const rbacRoleId = props.currentUser?.rbac_role_id ?? null;
  const stageModules = ACTIONABLE_STAGES
    .map((s) => STAGE_TO_MODULE[s as keyof typeof STAGE_TO_MODULE] ?? '')
    .filter(Boolean);
  const allow = useCanBatch(rbacRoleId, stageModules, 'update');
  const role = props.currentUser?.role_name as string | undefined;
  const toast = useToast();
  const [busyId, setBusyId] = useState<number | null>(null);

  // Wait for the matrix before rendering. While null, treat every stage as
  // accessible (optimistic) — the server action will still enforce.
  const actionableStages = useMemo(() => {
    if (!allow) return new Set(ACTIONABLE_STAGES);
    return new Set(ACTIONABLE_STAGES.filter((s) => {
      const m = STAGE_TO_MODULE[s as keyof typeof STAGE_TO_MODULE] ?? null;
      return m ? allow[m] !== false : false;
    }));
  }, [allow]);

  const handleAdvance = async (expenseId: number, decision: 'approve' | 'reject') => {
    if (decision === 'reject') {
      const error = ensureRejectReason(props.actionComment);
      if (error) {
        toast.error(error, 'Reject');
        return;
      }
    }
    setBusyId(expenseId);
    try {
      await props.onAdvance?.(expenseId, decision);
    } finally {
      setBusyId(null);
    }
  };

  if (allow && !Object.values(allow).some((v) => v === true)) {
    return (
      <AccessDenied
        roleName={role}
        requiredAccess="one of: stage-supervisor-review, stage-head-review, stage-account-officer-review, stage-account-supervisor-review, stage-accounting-review, stage-cfo-review"
      />
    );
  }

  const rows = props.expenses.filter((e) => actionableStages.has(e.status));

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 sm:p-8 rounded-3xl border-cyan-500/20 bg-gradient-to-br from-cyan-950/20 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-cyan-400 block tracking-wider">
          ✅ Expense Approval
        </span>
        <h2 className="text-xl font-bold text-white">Your Approval Queue</h2>
        <p className="text-xs text-slate-400 mt-1">
          {rows.length} item{rows.length === 1 ? '' : 's'} awaiting your decision
        </p>
      </div>

      {rows.length === 0 ? (
        <div className="glass-panel p-6 rounded-2xl border-slate-800 text-center text-slate-500 text-sm">
          🎉 No items waiting on you.
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map((exp) => {
            const stageMeta = STATUS_LABELS[exp.status as keyof typeof STATUS_LABELS] ?? { en: exp.status, th: exp.status, emoji: '📄' };
            const stageRole = STAGE_TO_ROLE[exp.status as keyof typeof STAGE_TO_ROLE] ?? null;
            return (
              <div
                key={exp.id}
                className="glass-panel p-4 rounded-2xl border-slate-800 hover:border-cyan-500/40 transition-colors"
              >
                <div className="flex items-start gap-4 flex-wrap">
                  <div className="flex-1 min-w-[240px]">
                    <div className="flex items-center gap-2 mb-2">
                      <span className="text-2xl">{stageMeta.emoji}</span>
                      <div>
                        <div className="text-sm font-bold text-white">EXP-{exp.id}</div>
                        <div className="text-[10px] text-slate-500 font-mono">
                          {stageMeta.en}
                          {stageRole && ` · owner: ${stageRole}`}
                        </div>
                      </div>
                    </div>
                    <div className="text-xs text-slate-400 grid grid-cols-2 gap-x-4 gap-y-1 mt-2">
                      <div><span className="text-slate-500">Submitter:</span> {exp.submitter_name ?? `User #${exp.submitter_id}`}</div>
                      <div><span className="text-slate-500">Dept:</span> {exp.submitter_dept ?? '—'}</div>
                      <div><span className="text-slate-500">Amount:</span> <span className="text-white font-mono">{fmt(exp.total_amount)}</span></div>
                      <div><span className="text-slate-500">Created:</span> {new Date(exp.created_at).toLocaleString('th-TH')}</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => props.onSelectExpense(exp)}
                      className="px-3 py-1.5 rounded-lg text-[11px] font-mono border border-slate-700 text-slate-300 hover:bg-slate-800/60"
                    >
                      Inspect
                    </button>
                    <button
                      type="button"
                      disabled={busyId === exp.id || props.loading}
                      onClick={() => handleAdvance(exp.id, 'reject')}
                      className="px-3 py-1.5 rounded-lg text-[11px] font-mono border border-rose-500/40 text-rose-300 hover:bg-rose-500/10 disabled:opacity-50"
                    >
                      Reject
                    </button>
                    <button
                      type="button"
                      disabled={busyId === exp.id || props.loading}
                      onClick={() => handleAdvance(exp.id, 'approve')}
                      className="px-3 py-1.5 rounded-lg text-[11px] font-mono bg-emerald-500/20 border border-emerald-500/40 text-emerald-200 hover:bg-emerald-500/30 disabled:opacity-50"
                    >
                      {busyId === exp.id ? '…' : 'Approve'}
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default ApproveExpenseView;
