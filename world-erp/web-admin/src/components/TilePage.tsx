'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import {
  reviewAndCorrectExpense,
  changeExpenseStatus,
  getSemanticSuggestions,
  submitExpenseFromSlip,
  advanceApproval,
  ceoForceDecision,
  upsertApprovalPolicy,
  deleteApprovalPolicy,
  submitPurchaseRequisition,
  advancePurchaseRequisition,
  advancePurchaseOrder,
  attachDisbursementPayslip,
} from '../app/actions';

import { type TabName } from '@/lib/permissions';

const TAB_BY_TILE: Record<string, TabName> = {
  'submit-expense': 'workbench',
  'my-history': 'workbench',
  'review-queue': 'workbench',
  'approve-expense': 'workbench',
  'search-coa': 'workbench',
  'search-slips': 'workbench',
  'reconciliation': 'workbench',
  'team-manage': 'workbench',
  'ops-overview': 'workbench',
  'workbench': 'workbench',
  'override-queue': 'cockpit',
  'all-approvals': 'cockpit',
  'cockpit': 'cockpit',
  'my-prs': 'pr',
  'subordinate-prs': 'pr',
  'all-prs': 'pr',
  'po': 'pr',
  'ledger': 'ledger',
  'policy': 'policy',
  'settings': 'settings',
  'org-chart': 'hr',
  'directory': 'hr',
  'departments': 'hr',
  'access-requests': 'hr',
};

function tabForTile(tile: any): TabName {
  return TAB_BY_TILE[tile?.id ?? ''] ?? 'workbench';
}
import { useCan } from '@/lib/rbac/client';
import { AccessDenied } from './AccessDenied';
import { useToast, useDialog } from '@/components/ui';

import { MobileNav } from './MobileNav';
import { WorkflowStepper } from './WorkflowStepper';
import { ProcurementStepper } from './ProcurementStepper';
import { PRWorkspace } from './workspaces/PRWorkspace';
import { CEOWorkspace } from './workspaces/CEOWorkspace';
import { POWorkspace } from './workspaces/POWorkspace';
import { SubordinatePRsView } from './workspaces/SubordinatePRsView';
import { LedgerCommentaryView } from './workspaces/LedgerCommentaryView';
import { PolicyEditor } from './PolicyEditor';
import { PageLayout } from './PageLayout';
import { buildCrumbs } from './breadcrumbs';
import { BreadcrumbSetter } from './breadcrumbs/BreadcrumbSetter';
import { AISettingsView } from './workspaces/AISettingsView';
import { DirectoryHR } from './workspaces/DirectoryHR';
import { DepartmentsHR } from './workspaces/DepartmentsHR';
import { AccessRequestsHR } from './workspaces/AccessRequestsHR';
import { FeatureDispatch } from './FeatureDispatch';
import { ExecutiveWorkspace } from './workspaces/ExecutiveWorkspace';

interface TilePageProps {
  tile: any;
  currentUser: any | null;
  users: any[];
  coa: any[];
  expenses: any[];
  journals: any[];
  execReport: any | null;
  policies: any[];
  prs: any[];
  pos: any[];
}

export function TilePage({
  tile,
  currentUser: initialUser,
  users: initialUsers,
  coa: initialCoa,
  expenses: initialExpenses,
  journals: initialJournals,
  execReport: initialExec,
  policies: initialPolicies,
  prs: initialPrs,
  pos: initialPos,
}: TilePageProps) {
  const router = useRouter();
  const toast = useToast();
  const dialog = useDialog();
  const [loading, setLoading] = useState(false);
  const [activeTab, _setActiveTab] = useState<TabName>(tabForTile(tile));
  const [activeSubView, setActiveSubView] = useState<string>(tile.sub_view ?? '');
  const [activeSubTab, setActiveSubTab] = useState<'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses'>('income');

  const _users = initialUsers;
  const coa = initialCoa;
  const expenses = initialExpenses;
  const journals = initialJournals;
  const execReport = initialExec;
  const policies = initialPolicies;
  const prs = initialPrs;
  const pos = initialPos;
  const currentUser = initialUser;

  const refresh = () => router.refresh();

  const [selectedExpense, setSelectedExpense] = useState<any>(null);
  const [editForm, setEditForm] = useState<any>(null);

  const [suggestions, setSuggestions] = useState<Record<number, any[]>>({});
  const [loadingSuggestion, setLoadingSuggestion] = useState<Record<number, boolean>>({});

  const [actionComment, setActionComment] = useState('');

  const [useMock, setUseMock] = useState(false);

  const [selectedPr, setSelectedPr] = useState<any | null>(null);
  const [selectedPo, setSelectedPo] = useState<any | null>(null);

  const rbacRoleId = currentUser?.rbac_role_id ?? null;
  const canLedger = useCan(rbacRoleId, 'tab-ledger');
  const canCockpit = useCan(rbacRoleId, 'tab-cockpit');
  const canPr = useCan(rbacRoleId, 'tab-pr');
  const canPolicy = useCan(rbacRoleId, 'tab-policy');
  const canSettings = useCan(rbacRoleId, 'tab-settings');
  const canHr = useCan(rbacRoleId, 'tab-hr');

  useEffect(() => {
    if (selectedExpense) {
      setEditForm({
        vendorName: selectedExpense.vendor_name || '',
        transactionDate: selectedExpense.transaction_date ? new Date(selectedExpense.transaction_date).toISOString().split('T')[0] : '',
        subtotal: parseFloat(selectedExpense.subtotal) || 0,
        vatAmount: parseFloat(selectedExpense.vat_amount) || 0,
        totalAmount: parseFloat(selectedExpense.total_amount) || 0,
        paymentMethod: selectedExpense.payment_method || 'cash',
        isCorrupted: selectedExpense.is_corrupted || false,
        correctionNotes: selectedExpense.correction_notes || '',
        items: selectedExpense.items ? selectedExpense.items.map((it: any) => ({
          id: it.id,
          description: it.description,
          amount: parseFloat(it.amount) || 0,
          code: it.mapped_account_code || ''
        })) : []
      });
      setSuggestions({});
    } else {
      setEditForm(null);
    }
  }, [selectedExpense]);

  const handleSlipUploaded = async (result: any) => {
    if (!currentUser) return;
    if (!result?.slipId) {
      toast.error(`Upload failed: ${result?.error || 'unknown'}`, 'Upload');
      return;
    }
    setLoading(true);
    const r = await submitExpenseFromSlip({
      slipId: result.slipId,
      actorId: currentUser.id,
    });
    setLoading(false);
    if (r.success) {
      const policyInfo = r.policy
        ? `Matched policy: #${r.policy.id} ${r.policy.name}`
        : 'No matching policy — using default chain';
      toast.success(
        `EXP-${r.expenseId} saved · ${r.status} · ${(result.confidence * 100).toFixed(0)}% confidence\n${policyInfo}`,
        'Slip saved'
      );
      refresh();
    } else {
      toast.error(`Save failed: ${r.error}`, 'Error');
    }
  };

  const fetchCoaSuggestions = async (itemIndex: number, description: string) => {
    if (!description) return;
    setLoadingSuggestion(prev => ({ ...prev, [itemIndex]: true }));
    const res = await getSemanticSuggestions(description);
    if (res.success) {
      setSuggestions(prev => ({ ...prev, [itemIndex]: res.suggestions || [] }));
    }
    setLoadingSuggestion(prev => ({ ...prev, [itemIndex]: false }));
  };

  const handleAdvance = async (expenseId: number, decision: 'approve' | 'reject') => {
    if (!currentUser) return;
    const r = await advanceApproval({
      expenseId,
      actorId: currentUser.id,
      decision,
      comment: actionComment,
    });
    if (r.success) {
      toast.success(`Expense ${decision}d`, 'Approval');
      setActionComment('');
      refresh();
    } else {
      toast.error(`Action failed: ${r.error}`, 'Error');
    }
  };

  const handleAdvancePr = async (prId: number, decision: 'approve' | 'reject', customComment?: string) => {
    if (!currentUser) return;
    const reason = (customComment !== undefined ? customComment : actionComment || '').trim();
    if (decision === 'reject' && reason.length < 5) {
      toast.warning('Rejection reason must be at least 5 characters', 'Reason required');
      return;
    }
    const r = await advancePurchaseRequisition({
      prId,
      actorId: currentUser.id,
      decision,
      comment: reason,
    });
    if (r.success) {
      toast.success(`PR ${decision}d`, 'Purchase Request');
      if (customComment === undefined) setActionComment('');
      refresh();
    } else {
      toast.error(`PR action failed: ${r.error}`, 'Error');
    }
  };

  const handleCeoOverride = async (targetType: 'expense' | 'pr', targetId: number, newStatus: 'approved' | 'paid' | 'rejected') => {
    if (!currentUser) return;
    const reason = await dialog.prompt({
      title: `CEO Override — ${targetType.toUpperCase()} #${targetId}`,
      message: 'Provide a reason for this override. It will be recorded in ceo_overrides and surfaced in the audit trail.',
      placeholder: 'Type the reason here…',
      minLength: 5,
      confirmLabel: 'Apply Override',
      tone: 'rose',
    });
    if (reason === null) return;
    const r = await ceoForceDecision({
      targetType, targetId,
      actorId: currentUser.id,
      newStatus,
      reason,
    });
    if (r.success) {
      toast.success(`Override applied: ${targetType.toUpperCase()} #${targetId} → ${newStatus}`, 'CEO Override');
      refresh();
    } else {
      toast.error(`Override failed: ${r.error}`, 'Error');
    }
  };

  const handleSubmitPr = async (payload: any) => {
    if (!currentUser) return { success: false };
    const r = await submitPurchaseRequisition({ ...payload, requesterId: currentUser.id });
    if (r.success) {
      toast.success(`PR #${r.prId} submitted`, 'Purchase Request');
      refresh();
    } else {
      toast.error(`PR submit failed: ${r.error}`, 'Error');
    }
    return r;
  };

  const handleSavePolicy = async (policy: any) => {
    const r = await upsertApprovalPolicy({ ...policy, actorId: currentUser.id });
    if (r.success) {
      toast.success(`Policy "${policy.name}" saved`, 'Approval Policy');
      refresh();
    } else {
      toast.error(`Save failed: ${r.error}`, 'Error');
    }
  };

  const handleDeletePolicy = async (id: number) => {
    const ok = await dialog.confirm({
      title: 'Disable policy?',
      message: 'The policy will be marked inactive. Existing in-flight expenses are not affected.',
      confirmLabel: 'Disable',
      tone: 'rose',
      variant: 'danger',
    });
    if (!ok) return;
    const r = await deleteApprovalPolicy({ id, actorId: currentUser.id });
    if (r.success) {
      toast.success('Policy disabled', 'Done');
      refresh();
    } else {
      toast.error(r.error || 'Failed to disable policy', 'Error');
    }
  };

  const handleAdvancePo = async (poId: number, decision: 'approve' | 'reject', customComment?: string) => {
    if (!currentUser) return { success: false };
    const r = await advancePurchaseOrder({
      poId,
      actorId: currentUser.id,
      decision,
      comment: customComment !== undefined ? customComment : actionComment,
    });
    if (r.success) {
      toast.success(`PO ${decision}d`, 'Purchase Order');
      refresh();
    } else {
      toast.error(`PO action failed: ${r.error}`, 'Error');
    }
    return r;
  };

  const handleAttachPayslip = async (poId: number, slipId: number) => {
    if (!currentUser) return { success: false, error: 'no user' };
    const r = await attachDisbursementPayslip({
      poId,
      actorId: currentUser.id,
      slipId,
    });
    if (r.success) {
      toast.success('Payslip attached — PO settled', 'Purchase Order');
      refresh();
    } else {
      toast.error(`Attach payslip failed: ${r.error}`, 'Error');
    }
    return r;
  };

  const handleAccountantSave = async () => {
    if (!selectedExpense || !currentUser) return;

    const sum = parseFloat((editForm.subtotal + editForm.vatAmount).toFixed(2));
    const total = parseFloat(editForm.totalAmount.toFixed(2));
    const matchesMath = Math.abs(sum - total) < 0.01;

    const payload = {
      vendorName: editForm.vendorName,
      transactionDate: editForm.transactionDate,
      subtotal: editForm.subtotal,
      vatAmount: editForm.vatAmount,
      totalAmount: editForm.totalAmount,
      paymentMethod: editForm.paymentMethod,
      isCorrupted: !matchesMath,
        correctionNotes: matchesMath
        ? (editForm.correctionNotes ? `[Corrected and confirmed numeric equation] ${editForm.correctionNotes}` : 'Verified and chart of accounts mapped successfully')
        : `[Numeric conflict detected] ${editForm.correctionNotes}`,
      items: editForm.items
    };

    setLoading(true);
    const res = await reviewAndCorrectExpense(selectedExpense.id, currentUser.id, payload);
    if (res.success) {
      toast.success('Saved and forwarded to manager for payment approval', 'Accountant review');
      setSelectedExpense(null);
      refresh();
    } else {
      toast.error(`An error occurred: ${res.error}`, 'Error');
    }
    setLoading(false);
  };

  const handleStatusChange = async (status: string, customComment?: string) => {
    if (!selectedExpense || !currentUser) return;
    setLoading(true);
    const comment = customComment !== undefined ? customComment : actionComment;
    const res = await changeExpenseStatus(selectedExpense.id, currentUser.id, status, comment);
    if (res.success) {
      toast.success(`Status: ${status.toUpperCase()}`, 'Transaction');
      setSelectedExpense(null);
      setActionComment('');
      refresh();
    } else {
      toast.error(`Unable to perform action: ${res.error}`, 'Error');
    }
    setLoading(false);
  };

  const getTrialBalance = () => {
    let totalDebit = 0;
    let totalCredit = 0;
    journals.forEach(j => {
      j.lines?.forEach((l: any) => {
        totalDebit += parseFloat(l.debit) || 0;
        totalCredit += parseFloat(l.credit) || 0;
      });
    });
    return {
      debit: totalDebit,
      credit: totalCredit,
      isBalanced: Math.abs(totalDebit - totalCredit) < 0.01
    };
  };

  const trialBalance = getTrialBalance();

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      ocr_extracted: 'bg-amber-500/10 text-amber-400 border border-amber-500/20',
      accountant_reviewed: 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20',
      approved: 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20',
      paid: 'bg-blue-500/10 text-blue-400 border border-blue-500/20',
      rejected: 'bg-rose-500/10 text-rose-400 border border-rose-500/20',
      draft: 'bg-slate-500/10 text-slate-400 border border-slate-500/20'
    };
    const labels: Record<string, string> = {
      ocr_extracted: 'Awaiting accountant review',
      accountant_reviewed: 'Accountant reviewed',
      approved: 'Approved for payment',
      paid: 'Paid (GL)',
      rejected: 'Transaction rejected',
      draft: 'Draft'
    };
    return (
      <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold tracking-wide uppercase font-mono ${badges[status] || badges.draft}`}>
        {labels[status] || status}
      </span>
    );
  };

  const roleName = (currentUser?.role_name || '').replace(/_/g, ' ') || 'workspace';
  const tileSubtitle = [roleName, currentUser?.fullname].filter(Boolean).join(' · ');

  return (
    <>
      <BreadcrumbSetter
        crumbs={buildCrumbs({
          group: tile.group,
          tile,
          subView: activeSubView || null,
        })}
      />
      <MobileNav
        open={false}
        onClose={() => {}}
        role={currentUser?.role_name}
        currentUser={currentUser}
      />

      <PageLayout
        title={tile.display_name}
        subtitle={tileSubtitle}
      >
        {(() => {
          const stepperPr = selectedPr || (selectedPo ? prs.find((p) => p.id === selectedPo.pr_id) : null);
          const stepperPo = selectedPo || (selectedPr ? pos.find((p) => p.pr_id === selectedPr.id) : null);
          const prApproveLog = (stepperPr?.logs || []).find((l: any) => l.new_status === 'approved');
          const poApproveLog = (stepperPo?.logs || []).find((l: any) => l.new_status === 'approved');
          if (stepperPr || stepperPo) {
            return (
              <ProcurementStepper
                pr={stepperPr}
                po={stepperPo}
                currentRole={currentUser?.role_name}
                paidSlipPath={stepperPo?.paid_slip_path}
                paidSlipMime={stepperPo?.paid_slip_mime}
                settledAt={stepperPo?.settled_at}
                settledActorName={stepperPo?.settled_actor_name}
                prApprovedActorName={prApproveLog?.actor_name}
                prApprovedAt={prApproveLog?.created_at}
                poApprovedActorName={poApproveLog?.actor_name}
                poApprovedAt={poApproveLog?.created_at}
              />
            );
          }
          if (selectedExpense) {
            const approvalLog = (selectedExpense.logs || []).find((l: any) => l.new_status === 'approved');
            return (
              <WorkflowStepper
                currentStatus={selectedExpense.status}
                activeRole={currentUser?.role_name || 'staff'}
                expenseId={selectedExpense.id}
                rejectionReason={selectedExpense.rejection_reason}
                rejectionActorName={selectedExpense.rejection_actor_name}
                rejectedAt={selectedExpense.rejected_at}
                approvedActorName={approvalLog?.actor_name}
                approvedAt={approvalLog?.created_at}
              />
            );
          }
          return null;
        })()}

        {loading && (
          <div className="flex justify-center items-center py-6 glass-panel rounded-2xl mb-8 border-indigo-500/20 animate-pulse">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-indigo-500"></div>
            <span className="ml-3 text-xs font-mono text-slate-300">Synchronising database ledgers...</span>
          </div>
        )}

        {activeTab === 'workbench' && currentUser && (
          <FeatureDispatch
            tile={tile}
            activeSubView={activeSubView}
            currentUser={currentUser}
            expenses={expenses}
            prs={prs}
            journals={journals}
            execReport={execReport}
            coa={coa}
            selectedExpense={selectedExpense}
            setSelectedExpense={setSelectedExpense}
            editForm={editForm}
            setEditForm={setEditForm}
            suggestions={suggestions}
            loadingSuggestion={loadingSuggestion}
            fetchCoaSuggestions={fetchCoaSuggestions}
            handleAccountantSave={handleAccountantSave}
            handleStatusChange={handleStatusChange}
            handleAdvance={handleAdvance}
            handleAdvancePr={handleAdvancePr}
            handleSubmitPr={handleSubmitPr}
            handleSlipUploaded={handleSlipUploaded}
            useMock={useMock}
            setUseMock={setUseMock}
            actionComment={actionComment}
            setActionComment={setActionComment}
            loading={loading}
            getStatusBadge={getStatusBadge}
            activeSubTab={activeSubTab}
            setActiveSubTab={setActiveSubTab}
          />
        )}

        {activeTab === 'ledger' && (
          canLedger === false ? (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="Accountant / Manager / Admin" />
          ) : canLedger === true ? (
          <div className="space-y-8 animate-fade-in">
            <div className="flex flex-wrap gap-2 items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-white flex items-center gap-2">
                  <span>📒</span> General Ledger
                </h2>
                <p className="text-[11px] text-slate-400 mt-0.5">Double-entry book of record</p>
              </div>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setActiveSubView(activeSubView === 'commentary' ? '' : 'commentary')}
                  className={`text-xs px-3 py-1.5 rounded-lg font-bold border transition-all ${
                    activeSubView === 'commentary'
                      ? 'bg-indigo-500/20 text-white border-indigo-500/40'
                      : 'bg-slate-900/60 text-slate-300 border-slate-800 hover:text-white'
                  }`}
                >
                  💬 {activeSubView === 'commentary' ? 'Hide AI Commentary' : 'Open AI Commentary'}
                </button>
              </div>
            </div>

            {activeSubView === 'commentary' && (
              <LedgerCommentaryView journals={journals} />
            )}

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div className="glass-panel p-6 rounded-3xl border-emerald-500/20 relative">
                <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Trial Balance Debits</span>
                <span className="text-3xl font-black text-emerald-400 font-mono mt-2 block">
                  {trialBalance.debit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
                </span>
              </div>
              <div className="glass-panel p-6 rounded-3xl border-indigo-500/20 relative">
                <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Trial Balance Credits</span>
                <span className="text-3xl font-black text-indigo-400 font-mono mt-2 block">
                  {trialBalance.credit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
                </span>
              </div>
              <div className="glass-panel p-6 rounded-3xl flex flex-col justify-between">
                <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Ledger Verification</span>
                <div className="mt-3 flex items-center gap-2">
                  {trialBalance.isBalanced ? (
                    <span className="px-4 py-1.5 bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 rounded-full font-bold text-xs flex items-center gap-2 shadow-lg shadow-emerald-950">
                      <span>⚖️</span> Double-Entry Balanced
                    </span>
                  ) : (
                    <span className="px-4 py-1.5 bg-rose-500/10 border border-rose-500/30 text-rose-300 rounded-full font-bold text-xs flex items-center gap-2 animate-pulse">
                      <span>🚨</span> Unbalanced Discrepancy
                    </span>
                  )}
                </div>
              </div>
            </div>

            <div className="glass-panel p-6 sm:p-8 rounded-3xl">
              <h2 className="text-xl font-bold text-white mb-6 flex items-center gap-2">
                <span>📒</span> General Journal (Double-Entry Ledger Book)
              </h2>

              {journals.length === 0 ? (
                <p className="text-center py-12 text-xs text-slate-500 font-mono">No journal entries recorded in the General Ledger yet</p>
              ) : (
                <div className="space-y-6">
                  {journals.map((j) => (
                    <div key={j.id} className="bg-slate-950/60 rounded-2xl border border-slate-900 overflow-hidden shadow-lg">
                      <div className="bg-slate-900/50 px-5 py-3.5 border-b border-slate-900 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 font-mono">
                        <div>
                          <span className="px-2.5 py-0.5 rounded bg-indigo-600/20 text-indigo-300 border border-indigo-500/30 text-[10px] font-black mr-3">
                            JRN-{j.id}
                          </span>
                          <span className="text-xs font-bold text-white font-sans">{j.description}</span>
                        </div>
                        <div className="text-[10px] text-slate-400">
                          <span>POSTED BY: {j.submitter_name || 'SYSTEM'}</span>
                          <span className="mx-2">•</span>
                          <span>{new Date(j.entry_date).toLocaleDateString('en-GB')}</span>
                        </div>
                      </div>

                      <div className="p-4 overflow-x-auto">
                        <div className="min-w-[600px]">
                          <div className="grid grid-cols-12 text-[10px] uppercase font-bold text-slate-500 pb-2 px-2 border-b border-slate-900 font-mono">
                            <div className="col-span-2">Account Code</div>
                            <div className="col-span-5">Account Description</div>
                            <div className="col-span-2">Memo</div>
                            <div className="col-span-1.5 text-right">Debit (Dr)</div>
                            <div className="col-span-1.5 text-right">Credit (Cr)</div>
                          </div>

                          <div className="divide-y divide-slate-900/30 font-mono">
                            {j.lines?.map((line: any) => (
                              <div key={line.id} className="grid grid-cols-12 text-xs py-3 px-2 hover:bg-slate-900/20">
                                <div className="col-span-2 text-indigo-400 font-bold">{line.account_code}</div>
                                <div className="col-span-5 text-slate-200 font-sans">
                                  <span className="block font-bold">{line.account_name_th}</span>
                                  <span className="text-[10px] text-slate-500 font-mono">{line.account_name_en} ({line.account_type})</span>
                                </div>
                                <div className="col-span-2 text-slate-500 truncate text-[11px] font-sans pr-2" title={line.description}>
                                  {line.description}
                                </div>
                                <div className="col-span-1.5 text-right font-bold text-emerald-400">
                                  {parseFloat(line.debit) > 0 ? parseFloat(line.debit).toLocaleString('th-TH', { minimumFractionDigits: 2 }) + ' THB' : '-'}
                                </div>
                                <div className="col-span-1.5 text-right font-bold text-purple-400">
                                  {parseFloat(line.credit) > 0 ? parseFloat(line.credit).toLocaleString('th-TH', { minimumFractionDigits: 2 }) + ' THB' : '-'}
                                </div>
                              </div>
                            ))}
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
          ) : (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="Accountant / Manager / Admin" />
          )
        )}

        {activeTab === 'cockpit' && (
          canCockpit === false ? (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="CFO / CEO / Admin" />
          ) : canCockpit === true ? (
            currentUser.role_name === 'ceo' ? (
              <CEOWorkspace
                currentUser={currentUser}
                execReport={execReport}
                activeSubTab={activeSubTab}
                setActiveSubTab={setActiveSubTab}
                expenses={expenses}
                prs={prs}
                onSelectExpense={setSelectedExpense}
                onAdvance={handleAdvance}
                onOverride={handleCeoOverride}
                actionComment={actionComment}
                setActionComment={setActionComment}
                loading={loading}
                getStatusBadge={getStatusBadge}
                initialSubView={activeSubView as any}
              />
            ) : (
              <ExecutiveWorkspace
                execReport={execReport}
                activeSubTab={activeSubTab}
                setActiveSubTab={setActiveSubTab}
              />
            )
          ) : (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="CFO / CEO / Admin" />
          )
        )}

        {activeTab === 'pr' && currentUser && (
          canPr === false ? (
            <AccessDenied roleName={currentUser.role_name} requiredAccess="PR workspace role required" />
          ) : canPr === true ? (
            activeSubView === 'po' ? (
              <POWorkspace
                currentUser={currentUser}
                pos={pos}
                selectedPo={selectedPo}
                onSelectPo={setSelectedPo}
                onAdvancePo={handleAdvancePo}
                onAttachPayslip={handleAttachPayslip}
                actionComment={actionComment}
                setActionComment={setActionComment}
                loading={loading}
              />
            ) : tile?.id === 'subordinate-prs' ? (
              <SubordinatePRsView
                currentUser={currentUser}
                prs={prs}
                pos={pos}
                coa={coa}
                onSubmitPr={handleSubmitPr}
                onAdvancePr={handleAdvancePr}
                onSelectPr={setSelectedPr}
                selectedPr={selectedPr}
                loading={loading}
              />
            ) : tile?.id === 'all-prs' ? (
              <PRWorkspace
                currentUser={currentUser}
                prs={prs}
                pos={pos}
                coa={coa}
                onSubmitPr={handleSubmitPr}
                onAdvancePr={handleAdvancePr}
                onSelectPr={setSelectedPr}
                selectedPr={selectedPr}
                loading={loading}
              />
            ) : (
              <PRWorkspace
                currentUser={currentUser}
                prs={prs}
                pos={pos}
                coa={coa}
                onSubmitPr={handleSubmitPr}
                onAdvancePr={handleAdvancePr}
                onSelectPr={setSelectedPr}
                selectedPr={selectedPr}
                loading={loading}
              />
            )
          ) : (
            <AccessDenied roleName={currentUser.role_name} requiredAccess="PR workspace role required" />
          )
        )}

        {activeTab === 'policy' && (
          canPolicy === false ? (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="CFO" />
          ) : canPolicy === true ? (
            <PolicyEditor
              policies={policies}
              onSave={handleSavePolicy}
              onDelete={handleDeletePolicy}
            />
          ) : (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="CFO" />
          )
        )}

        {activeTab === 'settings' && (
          canSettings === false ? (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="IT Staff" />
          ) : canSettings === true ? (
            <AISettingsView />
          ) : null
        )}

        {activeTab === 'hr' && currentUser && (
          canHr === false ? (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="HR / Head of Department" />
          ) : canHr === true ? (
            <div className="space-y-4 animate-fade-in">
              {activeSubView === 'directory' && (
                <DirectoryHR currentUser={currentUser} />
              )}
              {activeSubView === 'departments' && (
                <DepartmentsHR currentUser={currentUser} />
              )}
              {activeSubView === 'access-requests' && (
                <AccessRequestsHR currentUser={currentUser} />
              )}
            </div>
          ) : null
        )}
      </PageLayout>
    </>
  );
}

export default TilePage;