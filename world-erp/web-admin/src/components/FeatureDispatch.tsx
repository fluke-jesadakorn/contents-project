'use client';

import React from 'react';
import { SlipUpload } from './SlipUpload';
import { StaffWorkspace } from './workspaces/StaffWorkspace';
import { StaffHistoryView, COASearchView, SlipSearchView, TeamView, ReconciliationView } from './workspaces/SubViews';
import { ApproveExpenseView } from './workspaces/ApproveExpenseView';
import { ITWorkspace } from './workspaces/ITWorkspace';
import { ExecutiveWorkspace } from './workspaces/ExecutiveWorkspace';
import { HookReplayView } from './HookReplayView';
// canAccessTab from @/lib/permissions is no longer used here — feature
// dispatch is now driven by the RBAC matrix via the tile.requires.moduleId
// path, not by the legacy tab whitelist.

interface FeatureDispatchProps {
  tile: any;
  activeSubView: string;
  currentUser: any;
  expenses: any[];
  prs: any[];
  journals: any[];
  execReport: any;
  coa: any[];
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
  useMock: boolean;
  setUseMock: (b: boolean) => void;
  actionComment: string;
  setActionComment: React.Dispatch<React.SetStateAction<string>>;
  loading: boolean;
  getStatusBadge: (s: string) => React.ReactNode;
  activeSubTab: 'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses';
  setActiveSubTab: React.Dispatch<React.SetStateAction<any>>;
}

/**
 * Persona-neutral workbench dispatcher. Routes by `tile.id` (universal feature)
 * rather than by `currentUser.role_name`.
 *
 * The persona only resolves stage-specific UI inside the universal
 * `ApproveExpenseView`. All other tiles render the same UI regardless of role
 * (the RBAC matrix decides whether each tile is open or locked upstream).
 */
export function FeatureDispatch(props: FeatureDispatchProps) {
  const {
    tile,
    activeSubView: _activeSubView,
    currentUser,
    expenses,
    prs,
    journals,
    execReport,
    coa,
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
    handleSubmitPr: _handleSubmitPr,
    handleSlipUploaded,
    useMock,
    setUseMock,
    actionComment,
    setActionComment,
    loading,
    getStatusBadge,
    activeSubTab,
    setActiveSubTab,
  } = props;

  const tid = tile?.id ?? '';

  switch (tid) {
    case 'submit-expense':
      return (
        <div className="space-y-6 animate-fade-in">
          <SlipUpload
            onUploaded={handleSlipUploaded}
            useMock={useMock}
            onUseMockToggle={setUseMock}
          />
          <StaffWorkspace
            currentUser={currentUser}
            expenses={expenses}
            onSelectExpense={setSelectedExpense}
            selectedExpense={selectedExpense}
            loading={loading}
            getStatusBadge={getStatusBadge}
          />
        </div>
      );

    case 'my-history':
      return (
        <StaffHistoryView
          currentUser={currentUser}
          expenses={expenses}
          onSelectExpense={setSelectedExpense}
          selectedExpense={selectedExpense}
          getStatusBadge={getStatusBadge}
        />
      );

    case 'review-queue':
      return (
        <COASearchView
          coa={coa}
          onFetchSuggestions={fetchCoaSuggestions}
          suggestions={suggestions}
          loadingSuggestion={loadingSuggestion}
        />
      );

    case 'approve-expense':
      return (
        <ApproveExpenseView
          currentUser={currentUser}
          expenses={expenses}
          selectedExpense={selectedExpense}
          onSelectExpense={setSelectedExpense}
          editForm={editForm}
          setEditForm={setEditForm}
          coa={coa}
          suggestions={suggestions}
          loadingSuggestion={loadingSuggestion}
          onFetchCoaSuggestions={fetchCoaSuggestions}
          onAccountantSave={handleAccountantSave}
          onStatusChange={handleStatusChange}
          onAdvance={handleAdvance}
          onAdvancePr={handleAdvancePr}
          prs={prs}
          actionComment={actionComment}
          setActionComment={setActionComment}
          loading={loading}
          getStatusBadge={getStatusBadge}
        />
      );

    case 'search-coa':
      return (
        <COASearchView
          coa={coa}
          onFetchSuggestions={fetchCoaSuggestions}
          suggestions={suggestions}
          loadingSuggestion={loadingSuggestion}
        />
      );

    case 'search-slips':
      return (
        <SlipSearchView
          expenses={expenses}
          onSelectExpense={setSelectedExpense}
          getStatusBadge={getStatusBadge}
        />
      );

    case 'reconciliation':
      return <ReconciliationView expenses={expenses} journals={journals} />;

    case 'team-manage':
      return <TeamView currentUser={currentUser} />;

    case 'ops-overview':
      return (
        <ITWorkspace
          currentUser={currentUser}
          expenses={expenses}
          prs={prs}
          selectedExpense={selectedExpense}
          onSelectExpense={setSelectedExpense}
          getStatusBadge={getStatusBadge}
        />
      );

    case 'workbench':
      return (
        <ITWorkspace
          currentUser={currentUser}
          expenses={expenses}
          prs={prs}
          selectedExpense={selectedExpense}
          onSelectExpense={setSelectedExpense}
          getStatusBadge={getStatusBadge}
        />
      );

    case 'hook-inbox':
      return <HookReplayView currentUser={currentUser} />;

    case 'override-queue':
      // Falls through to cockpit branch (handled by activeTab === 'cockpit').
      return (
        <ExecutiveWorkspace
          execReport={execReport}
          activeSubTab={activeSubTab}
          setActiveSubTab={setActiveSubTab}
        />
      );

    case 'all-approvals':
      return (
        <ExecutiveWorkspace
          execReport={execReport}
          activeSubTab={activeSubTab}
          setActiveSubTab={setActiveSubTab}
        />
      );

    default:
      return (
        <ITWorkspace
          currentUser={currentUser}
          expenses={expenses}
          prs={prs}
          selectedExpense={selectedExpense}
          onSelectExpense={setSelectedExpense}
          getStatusBadge={getStatusBadge}
        />
      );
  }
}