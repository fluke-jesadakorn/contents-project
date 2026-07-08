'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { COASearchView, SlipSearchView, TeamView, ReconciliationView } from './workspaces/SubViews';
import { HookReplayView } from './HookReplayView';
import { AISettingsView } from './workspaces/AISettingsView';
import { DirectoryHR } from './workspaces/DirectoryHR';
import { DepartmentsHR } from './workspaces/DepartmentsHR';
import { AccessRequestsHR } from './workspaces/AccessRequestsHR';
import { TabStrip, type FeatureTab } from './TabStrip';
import {
  CockpitHistory,
  HookEventHistory,
  OverrideAuditHistory,
  PolicyAuditHistory,
  RecentSlipsHistory,
  ReconciliationHistory,
  ResolvedAccessRequestsHistory,
} from './workspaces/History';
import { LedgerHistory } from './workspaces/LedgerHistory';
import { CEOWorkspace } from './workspaces/CEOWorkspace';
import { ExecutiveWorkspace } from './workspaces/ExecutiveWorkspace';
import { ITWorkspace } from './workspaces/ITWorkspace';

export interface FeatureDispatchProps {
  tile: any;
  activeSubView: string;
  currentUser: any;
  expenses: any[];
  prs: any[];
  journals: any[];
  execReport: any;
  coa: any[];
  pos?: any[];
  selectedExpense: any;
  setSelectedExpense: (e: any) => void;
  editForm: any;
  setEditForm: React.Dispatch<React.SetStateAction<any>>;
  suggestions: Record<number, any[]>;
  loadingSuggestion: Record<number, boolean>;
  fetchCoaSuggestions: (idx: number, desc: string) => Promise<void>;
  handleAccountantSave: () => Promise<void>;
  handleStatusChange: (status: string, comment?: string) => Promise<void>;
  handleAdvance: (id: number, decision: 'approve' | 'reject') => Promise<void>;
  handleAdvancePr: (id: number, decision: 'approve' | 'reject', comment?: string) => Promise<any>;
  handleSubmitPr: (payload: any) => Promise<any>;
  handleSlipUploaded: (result: any) => Promise<void>;
  handleAdvancePo: (poId: number, decision: 'approve' | 'reject', customComment?: string) => Promise<any>;
  handleAttachPayslip: (poId: number, slipId: number) => Promise<any>;
  handleCeoOverride?: (targetType: 'expense' | 'pr', targetId: number, newStatus: 'approved' | 'paid' | 'rejected') => Promise<void>;
  actionComment: string;
  setActionComment: React.Dispatch<React.SetStateAction<string>>;
  loading: boolean;
  getStatusBadge: (s: string) => React.ReactNode;
  activeSubTab: 'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses';
  setActiveSubTab: React.Dispatch<React.SetStateAction<any>>;
  stageAllow?: Record<string, boolean>;
  canViewSubordinatePrs?: boolean;
  canApprovePO?: boolean;
  canSettlePO?: boolean;
  history?: {
    overrideAudit?: any[];
    hookEvents?: any[];
    policyAudit?: any[];
    resolvedAccessRequests?: any[];
    approvalLog?: any[];
    prActionLog?: any[];
    cockpitSnapshots?: any[];
    reconciliationSnapshots?: any[];
  };
}

type DispatchTab = FeatureTab<string>;

interface TabSpec {
  id: string;
  label: string;
  icon: string;
  tone?: 'neutral' | 'history';
  hidden?: (p: FeatureDispatchProps) => boolean;
  render: (p: FeatureDispatchProps) => React.ReactNode;
}

const isManagerRole = (role: string) =>
  ['manager', 'accounting_manager', 'cfo', 'ceo', 'admin'].includes(role);
const isAdminRole = (role: string) => ['admin', 'cfo', 'ceo'].includes(role);
const isFinanceRole = (role: string) =>
  ['accountant', 'accounting_manager', 'account_officer', 'account_supervisor', 'finance', 'cfo', 'ceo', 'admin'].includes(role);

function LedgerInline(p: FeatureDispatchProps) {
  const journals = p.journals ?? [];
  const totalDebit = journals.reduce(
    (s: number, j: any) => s + (j.lines ?? []).reduce((ls: number, l: any) => ls + (parseFloat(l.debit) || 0), 0),
  );
  const totalCredit = journals.reduce(
    (s: number, j: any) => s + (j.lines ?? []).reduce((ls: number, l: any) => ls + (parseFloat(l.credit) || 0), 0),
  );
  const isBalanced = Math.abs(totalDebit - totalCredit) < 0.01;
  return (
    <div className="space-y-8 animate-fade-in">
      <div className="flex flex-wrap gap-2 items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <span>📒</span> General Ledger
          </h2>
          <p className="text-[11px] text-slate-400 mt-0.5">Double-entry book of record</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="glass-panel p-6 rounded-3xl border-emerald-500/20 relative">
          <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Trial Balance Debits</span>
          <span className="text-3xl font-black text-emerald-400 font-mono mt-2 block">
            {totalDebit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
          </span>
        </div>
        <div className="glass-panel p-6 rounded-3xl border-indigo-500/20 relative">
          <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Trial Balance Credits</span>
          <span className="text-3xl font-black text-indigo-400 font-mono mt-2 block">
            {totalCredit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} THB
          </span>
        </div>
        <div className="glass-panel p-6 rounded-3xl flex flex-col justify-between">
          <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Ledger Verification</span>
          <div className="mt-3 flex items-center gap-2">
            {isBalanced ? (
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
            {journals.map((j: any) => (
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
                    <span>{j.entry_date ? new Date(j.entry_date).toLocaleDateString('en-GB') : '—'}</span>
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
                      {(j.lines ?? []).map((line: any) => (
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
  );
}

function WaybillGate() {
  React.useEffect(() => {
    window.location.href = '/my-waybills';
  }, []);
  return (
    <div className="text-center py-12 text-xs text-slate-500 font-mono animate-pulse">
      Loading <span className="text-cyan-400">My Waybills</span>…
    </div>
  );
}

const TABS: Record<string, TabSpec[]> = {
  'search-coa': [
    { id: 'coa', label: 'COA', icon: '🔍', render: (p) => (
      <COASearchView coa={p.coa} onFetchSuggestions={p.fetchCoaSuggestions} suggestions={p.suggestions} loadingSuggestion={p.loadingSuggestion} />
    ) },
    { id: 'slips', label: 'Receipts', icon: '🧾', render: (p) => (
      <SlipSearchView expenses={p.expenses} onSelectExpense={p.setSelectedExpense} getStatusBadge={p.getStatusBadge} />
    ) },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => {
      const role = p.currentUser?.role_name || 'staff';
      const scope: 'self' | 'dept' | 'all' = isFinanceRole(role) || isAdminRole(role) ? 'all' : isManagerRole(role) ? 'dept' : 'self';
      return <RecentSlipsHistory entries={p.expenses} currentUserId={p.currentUser.id} scope={scope} />;
    } },
  ],

  'team-manage': [
    { id: 'team-manage', label: 'Team', icon: '👥', render: (p) => <TeamView currentUser={p.currentUser} /> },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <PolicyAuditHistory entries={p.history?.policyAudit ?? []} /> },
  ],

  'expense': [
    { id: 'gate', label: 'My Waybills', icon: '📑', render: () => <WaybillGate /> },
  ],

  'pr': [
    { id: 'gate', label: 'My Waybills', icon: '📦', render: () => <WaybillGate /> },
  ],

  'po': [
    { id: 'gate', label: 'My Waybills', icon: '📎', render: () => <WaybillGate /> },
  ],

  'my-waybills': [
    { id: 'gate', label: 'My Waybills', icon: '🧾', render: () => <WaybillGate /> },
  ],

  'reconciliation': [
    { id: 'recon', label: 'Reconcile', icon: '📊', render: (p) => <ReconciliationView expenses={p.expenses} journals={p.journals} /> },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <ReconciliationHistory snapshots={p.history?.reconciliationSnapshots ?? []} /> },
  ],

  'ledger': [
    { id: 'ledger', label: 'Ledger', icon: '📒', render: (p) => <LedgerInline {...p} /> },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <LedgerHistory journals={p.journals ?? []} /> },
  ],

  'cockpit': [
    { id: 'main', label: 'Cockpit', icon: '👑', render: (p) =>
      p.currentUser?.role_name === 'ceo' ? (
        <CEOWorkspace currentUser={p.currentUser} execReport={p.execReport} activeSubTab={p.activeSubTab} setActiveSubTab={p.setActiveSubTab} expenses={p.expenses} prs={p.prs} onSelectExpense={p.setSelectedExpense} onAdvance={p.handleAdvance} onOverride={async (targetType, targetId, decision) => {
          if (p.handleCeoOverride) {
            const newStatus = decision === 'approved' ? 'approved' : decision === 'paid' ? 'paid' : 'rejected';
            await p.handleCeoOverride(targetType, targetId, newStatus);
          }
        }} actionComment={p.actionComment} setActionComment={p.setActionComment} loading={p.loading} getStatusBadge={p.getStatusBadge} initialSubView={p.activeSubView as any} />
      ) : (
        <ExecutiveWorkspace execReport={p.execReport} activeSubTab={p.activeSubTab} setActiveSubTab={p.setActiveSubTab} />
      ),
    },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <CockpitHistory snapshots={p.history?.cockpitSnapshots ?? []} /> },
  ],

  'override-queue': [
    { id: 'override', label: 'Override', icon: '⚡', render: (p) => (
      <CEOWorkspace currentUser={p.currentUser} execReport={p.execReport} activeSubTab={p.activeSubTab} setActiveSubTab={p.setActiveSubTab} expenses={p.expenses} prs={p.prs} onSelectExpense={p.setSelectedExpense} onAdvance={p.handleAdvance} onOverride={async (targetType, targetId, decision) => {
        if (p.handleCeoOverride) {
          const newStatus = decision === 'approved' ? 'approved' : decision === 'paid' ? 'paid' : 'rejected';
          await p.handleCeoOverride(targetType, targetId, newStatus);
        }
      }} actionComment={p.actionComment} setActionComment={p.setActionComment} loading={p.loading} getStatusBadge={p.getStatusBadge} initialSubView={'override' as any} />
    ) },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <OverrideAuditHistory entries={p.history?.overrideAudit ?? []} /> },
  ],

  'workbench': [
    { id: 'workbench', label: 'Workbench', icon: '🧰', render: (p) => (
      <ITWorkspace currentUser={p.currentUser} expenses={p.expenses} prs={p.prs} selectedExpense={p.selectedExpense} onSelectExpense={p.setSelectedExpense} getStatusBadge={p.getStatusBadge} />
    ) },
  ],

  'hook': [
    { id: 'hook', label: 'Inbox', icon: '🪝', render: (p) => <HookReplayView currentUser={p.currentUser} /> },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <HookEventHistory events={p.history?.hookEvents ?? []} /> },
  ],

  'directory': [
    { id: 'directory', label: 'Directory', icon: '📇', render: (p) => <DirectoryHR currentUser={p.currentUser} /> },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <PolicyAuditHistory entries={p.history?.policyAudit ?? []} /> },
  ],

  'departments': [
    { id: 'departments', label: 'Departments', icon: '🏢', render: (p) => <DepartmentsHR currentUser={p.currentUser} /> },
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <PolicyAuditHistory entries={p.history?.policyAudit ?? []} /> },
  ],

  'access-requests': [
    { id: 'active', label: 'Pending', icon: '✉', render: (p) => <AccessRequestsHR currentUser={p.currentUser} /> },
    { id: 'history', label: 'Resolved', icon: '🕓', tone: 'history', render: (p) => <ResolvedAccessRequestsHistory requests={p.history?.resolvedAccessRequests ?? []} /> },
  ],

  'audit': [
    { id: 'history', label: 'History', icon: '🕓', tone: 'history', render: (p) => <PolicyAuditHistory entries={p.history?.policyAudit ?? []} /> },
  ],

  'settings': [
    { id: 'settings', label: 'AI Settings', icon: '⚙️', render: () => <AISettingsView /> },
  ],

  'hub': [
    { id: 'hub', label: 'Hub', icon: '🗂️', render: () => (
      <div className="text-center text-xs text-slate-500 font-mono py-12">
        Hub is the root page. Use the navigation tiles to access features.
      </div>
    ) },
  ],

  'summary': [
    { id: 'summary', label: 'Summary', icon: '🧮', render: (p) => (
      <ExecutiveWorkspace execReport={p.execReport} activeSubTab={p.activeSubTab} setActiveSubTab={p.setActiveSubTab} />
    ) },
  ],

  'visibility': [
    { id: 'visibility', label: 'Visibility', icon: '🔐', render: () => (
      <div className="text-center text-xs text-slate-500 font-mono py-12">
        Visibility Matrix — see Policy Matrix page.
      </div>
    ) },
  ],

  'policy': [
    { id: 'policy', label: 'Policy', icon: '📜', render: () => (
      <div className="text-center text-xs text-slate-500 font-mono py-12">
        Policy Matrix — see /policy route.
      </div>
    ) },
  ],
};

const PRIMARY = (tile: any): string => {
  const sv = tile?.sub_view;
  return sv && sv.length > 0 ? sv : 'main';
};

export function FeatureDispatch(props: FeatureDispatchProps) {
  const { tile } = props;
  const tid = tile?.id ?? '';
  const specList = TABS[tid] ?? TABS['workbench']!;

  const [activeTab, setActiveTab] = useState<string>(PRIMARY(tile));

  const visible = useMemo<DispatchTab[]>(
    () =>
      specList
        .filter((s) => !s.hidden || !s.hidden(props))
        .map<DispatchTab>((s) => ({ id: s.id, label: s.label, icon: s.icon, tone: s.tone })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [tid, props.currentUser?.id, props.currentUser?.role_name, props.expenses?.length, props.prs?.length, props.pos?.length],
  );

  useEffect(() => {
    if (visible.length === 0) return;
    if (visible.find((v) => v.id === activeTab)) return;
    setActiveTab(visible[0].id);
  }, [visible, activeTab]);

  const activeSpec = specList.find((s) => s.id === activeTab) ?? specList[0];

  if (visible.length <= 1) {
    return <>{activeSpec.render(props)}</>;
  }

  return (
    <div className="space-y-4 animate-fade-in">
      <TabStrip tabs={visible} active={activeTab} onChange={setActiveTab} className="w-fit max-w-full" />
      <div key={activeSpec.id}>{activeSpec.render(props)}</div>
    </div>
  );
}

export default FeatureDispatch;
