// lib/perm/stages.ts — pure data, no DB, no 'server-only'.
// Safe to import from client components.
//
// Stage names use finance-standard keys (per the Waybill / P2P & T&E
// canonical taxonomy). Legacy snake_case keys are accepted as alias lookups
// so existing callers continue to resolve during the migration window.

export type StageName =
  | 'submission'
  | 'dept_verification'
  | 'dept_authorization'
  | 'accounting_verification'
  | 'accounting_supervision'
  | 'accounting_authorization'
  | 'disbursement_authorization'
  | 'cfo_authorization'
  | 'ceo_authorization'
  | 'awaiting_disbursement'
  | 'disbursed'
  | 'rejected'
  | 'po_pending'
  | 'po_cfo';

const CANONICAL_STAGES = new Set<StageName>([
  'submission',
  'dept_verification',
  'dept_authorization',
  'accounting_verification',
  'accounting_supervision',
  'accounting_authorization',
  'disbursement_authorization',
  'cfo_authorization',
  'ceo_authorization',
  'awaiting_disbursement',
  'disbursed',
  'rejected',
  'po_pending',
  'po_cfo',
]);

const LEGACY_TO_NEW: Record<string, StageName> = {
  ocr_extracted:               'submission',
  supervisor_review:           'dept_verification',
  manager_review:              'dept_authorization',
  account_officer_review:      'accounting_verification',
  account_supervisor_review:   'accounting_supervision',
  accounting_review:           'accounting_authorization',
  finance_review:              'disbursement_authorization',
  cfo_review:                  'cfo_authorization',
  ceo_review:                  'ceo_authorization',
  approved:                    'awaiting_disbursement',
  paid:                        'disbursed',
  pending_approval:            'po_cfo',
};

export function normalizeStage(raw: string | null | undefined): StageName | null {
  if (!raw) return null;
  if (CANONICAL_STAGES.has(raw as StageName)) return raw as StageName;
  return LEGACY_TO_NEW[raw] ?? null;
}

export const STAGE_ORDER: StageName[] = [
  'submission',
  'dept_verification',
  'dept_authorization',
  'accounting_verification',
  'accounting_supervision',
  'accounting_authorization',
  'disbursement_authorization',
  'cfo_authorization',
  'ceo_authorization',
];

// Helper: full table; TS narrows on read but legacy keys must still resolve.
type RoleId =
  | 'supervisor'
  | 'manager'
  | 'account_officer'
  | 'account_supervisor'
  | 'accounting_manager'
  | 'finance'
  | 'cfo'
  | 'ceo'
  | 'admin';

const rawToRoleMap: Record<string, RoleId> = {
  submission:                    'supervisor',
  dept_verification:             'supervisor',
  dept_authorization:            'manager',
  accounting_verification:       'account_officer',
  accounting_supervision:        'account_supervisor',
  accounting_authorization:      'accounting_manager',
  disbursement_authorization:    'finance',
  cfo_authorization:             'cfo',
  ceo_authorization:             'ceo',
  awaiting_disbursement:         'finance',
  disbursed:                     'finance',
  // legacy aliases (DB migration renamed them; if anything reads old code-path)
  ocr_extracted:                 'supervisor',
  supervisor_review:             'supervisor',
  manager_review:                'manager',
  account_officer_review:        'account_officer',
  account_supervisor_review:     'account_supervisor',
  accounting_review:             'accounting_manager',
  finance_review:                'finance',
  cfo_review:                    'cfo',
  ceo_review:                    'ceo',
  approved:                      'finance',
  paid:                          'finance',
  // PO specifics (kept for legacy callers like ProcurementStepper)
  po_pending:                    'manager',
  po_cfo:                        'cfo',
  pending_approval:              'cfo',
};

export const STAGE_TO_ROLE: Record<string, RoleId> = rawToRoleMap;

const rawToPermMap: Record<string, string> = {
  submission:                    'stage:submission:act:all',
  dept_verification:             'stage:dept_verification:act:all',
  dept_authorization:            'stage:dept_authorization:act:all',
  accounting_verification:       'stage:accounting_verification:act:all',
  accounting_supervision:        'stage:accounting_supervision:act:all',
  accounting_authorization:      'stage:accounting_authorization:act:all',
  disbursement_authorization:    'stage:disbursement_authorization:act:all',
  cfo_authorization:             'stage:cfo_authorization:act:all',
  ceo_authorization:             'stage:ceo_authorization:act:all',
  awaiting_disbursement:         'stage:disbursement_authorization:act:all',
  disbursed:                     'stage:disbursement_authorization:act:all',
  // legacy aliases
  ocr_extracted:                 'stage:submission:act:all',
  supervisor_review:             'stage:dept_verification:act:all',
  manager_review:                'stage:dept_authorization:act:all',
  account_officer_review:        'stage:accounting_verification:act:all',
  account_supervisor_review:     'stage:accounting_supervision:act:all',
  accounting_review:             'stage:accounting_authorization:act:all',
  finance_review:                'stage:disbursement_authorization:act:all',
  cfo_review:                    'stage:cfo_authorization:act:all',
  ceo_review:                    'stage:ceo_authorization:act:all',
  approved:                      'stage:disbursement_authorization:act:all',
  paid:                          'stage:disbursement_authorization:act:all',
  // PO
  po_pending:                    'stage:po_pending:act:all',
  po_cfo:                        'stage:po_cfo:act:all',
  pending_approval:              'stage:po_cfo:act:all',
};

export const STAGE_TO_PERM: Record<string, string> = rawToPermMap;
