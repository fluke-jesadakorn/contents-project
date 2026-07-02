// Stage-to-module mapping — pure data, no DB, no 'server-only'.
// Safe to import from Client Components and Server Components alike.

export type StageName =
  | 'supervisor_review'
  | 'head_review'
  | 'account_officer_review'
  | 'account_supervisor_review'
  | 'accounting_review'
  | 'cfo_review'
  | 'ceo_review'
  | 'finance_review'
  | 'po_pending'
  | 'po_cfo'
  | 'ocr_extracted'
  | 'accountant_reviewed'
  | 'approved'
  | 'paid'
  | 'rejected'
  | 'draft';

export const STAGE_TO_MODULE: Record<StageName, string | null> = {
  supervisor_review:         'stage-supervisor-review',
  head_review:               'stage-head-review',
  account_officer_review:    'stage-account-officer-review',
  account_supervisor_review: 'stage-account-supervisor-review',
  accounting_review:         'stage-accounting-review',
  cfo_review:                'stage-cfo-review',
  ceo_review:                'stage-ceo-review',
  finance_review:            'stage-finance-review',
  po_pending:                'stage-po-pending',
  po_cfo:                    'stage-po-cfo',
  ocr_extracted:             null,
  accountant_reviewed:       null,
  approved:                  null,
  paid:                      null,
  rejected:                  null,
  draft:                     null,
};

// Legacy alias: stage → legacy role name. Kept for components that still
// want a name for display or for the role_name string. The matrix is the
// authority; this map is presentation-only.
export const STAGE_TO_ROLE: Record<string, string | null> = {
  supervisor_review:         'supervisor',
  head_review:               'head_of_department',
  account_officer_review:    'account_officer',
  account_supervisor_review: 'account_supervisor',
  accounting_review:         'accounting_manager',
  cfo_review:                'cfo',
  ceo_review:                'ceo',
  finance_review:            'finance',
  po_pending:                'accounting_manager',
  po_cfo:                    'cfo',
};

export const STAGE_TO_ROLE_PO: Record<string, string | null> = {
  po_pending: 'accounting_manager',
  po_cfo:     'cfo',
};

export const APPROVER_TO_STAGE: Record<string, string | null> = {
  supervisor:         'supervisor_review',
  head_of_department: 'head_review',
  account_officer:    'account_officer_review',
  account_supervisor: 'account_supervisor_review',
  accounting_manager: 'accounting_review',
  cfo:                'cfo_review',
  ceo:                'ceo_review',
  finance:            'finance_review',
};