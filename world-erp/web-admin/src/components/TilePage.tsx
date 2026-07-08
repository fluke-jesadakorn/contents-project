'use client';

import React, { useState, useEffect, useRef } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  reviewAndCorrectExpense,
  changeExpenseStatus,
  getSemanticSuggestions,
  advanceApproval,
  ceoForceDecision,
  submitPurchaseRequisition,
  advancePurchaseRequisition,
  advancePurchaseOrder,
  attachDisbursementPayslip,
} from '../app/actions';
import { useToast, useDialog } from '@/components/ui';
import { MobileNav } from './MobileNav';
import { PageLayout } from './PageLayout';
import { GROUP_LABEL, type TileGroup } from './tile-config';
import { tileCrumbs } from './breadcrumbs';
import { BreadcrumbSetter } from './breadcrumbs/BreadcrumbSetter';
import { FeatureDispatch, type FeatureDispatchProps } from './FeatureDispatch';
import { WaybillRail } from './waybill/WaybillRail';

interface TilePageProps {
  tile: any;
  currentUser: any | null;
  users: any[];
  coa: any[];
  expenses: any[];
  journals: any[];
  execReport: any | null;
  prs: any[];
  pos: any[];
  canViewSubordinatePrs?: boolean;
  canApprovePO?: boolean;
  canSettlePO?: boolean;
  stageAllow?: Record<string, boolean>;
  history?: FeatureDispatchProps['history'];
}

export function TilePage({
  tile,
  currentUser: initialUser,
  users: initialUsers,
  coa: initialCoa,
  expenses: initialExpenses,
  journals: initialJournals,
  execReport: initialExec,
  prs: initialPrs,
  pos: initialPos,
  canViewSubordinatePrs = false,
  canApprovePO = false,
  canSettlePO = false,
  stageAllow,
  history,
}: TilePageProps) {
  const router = useRouter();
  const toast = useToast();
  const dialog = useDialog();
  const [loading, setLoading] = useState(false);
  const [activeSubTab, setActiveSubTab] = useState<'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses'>('income');

  const _users = initialUsers;
  const coa = initialCoa;
  const expenses = initialExpenses;
  const journals = initialJournals;
  const execReport = initialExec;
  const prs = initialPrs;
  const pos = initialPos;
  const currentUser = initialUser;

  const refresh = () => router.refresh();

  const [selectedExpense, setSelectedExpense] = useState<any>(null);
  const [editForm, setEditForm] = useState<any>(null);

  const [suggestions, setSuggestions] = useState<Record<number, any[]>>({});
  const [loadingSuggestion, setLoadingSuggestion] = useState<Record<number, boolean>>({});

  const [actionComment, setActionComment] = useState('');

  const [selectedPr, setSelectedPr] = useState<any | null>(null);
  const [selectedPo, setSelectedPo] = useState<any | null>(null);

  const searchParams = useSearchParams();
  const focusAppliedRef = useRef(false);
  useEffect(() => {
    if (focusAppliedRef.current) return;
    const focus = searchParams.get('focus');
    if (!focus) return;
    const sep = focus.indexOf(':');
    if (sep <= 0) return;
    const kind = focus.slice(0, sep);
    const id = Number(focus.slice(sep + 1));
    if (!Number.isFinite(id)) return;
    if (kind === 'expense') {
      const found = expenses.find((e: any) => Number(e.id) === id);
      if (found) setSelectedExpense(found);
    } else if (kind === 'pr') {
      const found = prs.find((p: any) => Number(p.id) === id);
      if (found) setSelectedPr(found);
    } else if (kind === 'po') {
      const found = pos.find((p: any) => Number(p.id) === id);
      if (found) setSelectedPo(found);
    }
    focusAppliedRef.current = true;
    const next = new URLSearchParams(Array.from(searchParams.entries()));
    next.delete('focus');
    const qs = next.toString();
    if (typeof window !== 'undefined') {
      router.replace(qs ? `${window.location.pathname}?${qs}` : window.location.pathname);
    }
  }, [searchParams, expenses, prs, pos, router]);

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
    setLoading(true);
    try {
      toast.success(
        `EXP-${result.expenseId} submitted · ${result.status}`,
        'Slip saved',
      );
      refresh();
    } finally {
      setLoading(false);
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
      message: 'Provide a reason for this override. It will be recorded in approval_override_audit and surfaced in the audit trail.',
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

  const dispatchProps: FeatureDispatchProps = {
    tile,
    activeSubView: tile?.sub_view ?? '',
    currentUser,
    expenses,
    prs,
    journals,
    execReport,
    coa,
    pos,
    selectedExpense,
    setSelectedExpense,
    editForm,
    setEditForm,
    suggestions,
    loadingSuggestion,
    fetchCoaSuggestions,
    handleAccountantSave,
    handleStatusChange,
    handleAdvance,
    handleAdvancePr,
    handleSubmitPr: handleSubmitPr as any,
    handleSlipUploaded,
    handleAdvancePo,
    handleAttachPayslip,
    handleCeoOverride,
    actionComment,
    setActionComment,
    loading,
    getStatusBadge,
    activeSubTab,
    setActiveSubTab,
    stageAllow,
    canViewSubordinatePrs,
    canApprovePO,
    canSettlePO,
    history,
  };

  return (
    <>
      <BreadcrumbSetter crumbs={tileCrumbs(tile)} />
      <MobileNav
        open={false}
        onClose={() => {}}
        role={currentUser?.role_name}
        currentUser={currentUser}
      />

      <PageLayout
        title={tile.display_name}
        subtitle={tileSubtitle}
        category={{
          label: GROUP_LABEL[tile.group as TileGroup].label,
          icon: GROUP_LABEL[tile.group as TileGroup].icon,
          href: `/group/${tile.group}`,
        }}
      >
        {(() => {
          const stepperPr = selectedPr || (selectedPo ? prs.find((p) => p.id === selectedPo.pr_id) : null);
          const stepperPo = selectedPo || (selectedPr ? pos.find((p) => p.id === selectedPo?.id) : null);
          if (stepperPr || stepperPo) {
            return (
              <WaybillRail
                domain="procurement"
                currentStage={
                  stepperPo?.status === 'settled'
                    ? 'disbursed'
                    : stepperPo?.status === 'approved'
                    ? 'cfo_authorization'
                    : stepperPo?.status === 'po_cfo' || stepperPo?.status === 'pending_approval'
                    ? 'accounting_authorization'
                    : 'submission'
                }
              />
            );
          }
          if (selectedExpense) {
            return (
              <WaybillRail
                domain="expense"
                currentStage={selectedExpense.status}
                rejectionReason={selectedExpense.rejection_reason}
                amountTHB={Number(selectedExpense.total_amount) || null}
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

        {currentUser && (
          <FeatureDispatch {...dispatchProps} />
        )}
      </PageLayout>
    </>
  );
}

export default TilePage;
