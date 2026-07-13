// lib/policy/registry.ts — single source of truth for all policies.
//
// Each entry is a Policy AST. Server actions, RSC pages, route handlers,
// SQL row filters, and client gates all reference this registry.
//
// Adding a new gate:
//   1. Add the entry here (use `p` builders).
//   2. Call `requirePolicy(POL.x, ctx)` from server, or `evalPolicy` from RSC.
//   3. Use `compilePolicyToSql(POL.x, ctx)` for row-level filters.
//   4. Surface in UI via the policy snapshot in `ActorProvider` or `<Gate>`.
//
// Do NOT reintroduce hasPermission / FINANCE_ROLES / role-string equality.

import type { Policy, PolicyResource } from './ast';
import { p } from './builders';

export const FINANCE_ROLES = ['account_officer', 'account_supervisor', 'accounting_manager', 'finance'] as const;
export const PRIVILEGED_ROLES = ['cfo', 'ceo', 'admin'] as const;

export function financeRole(...extra: string[]): Policy {
  return p.or(p.role([...FINANCE_ROLES]), p.role([...extra]));
}

export function expenseStagePolicy(currentStage: string, _amountTHB?: number): Policy {
  switch (currentStage) {
    case 'submission':
      return p.owner('submitter_id');
    case 'dept_verification':
      return p.and(
        p.dept('same'),
        p.levelAtMostColumn('submitter_level'),
        p.or(p.role('manager'), p.role('hr_manager')),
      );
    case 'accounting_verification':
      return p.and(
        p.perm('stage:accounting_verification:act:all'),
        p.role(['account_officer', 'account_supervisor', 'accounting_manager', 'finance']),
      );
    case 'accounting_supervision':
      return p.and(
        p.perm('stage:accounting_supervision:act:all'),
        p.role('account_supervisor'),
      );
    case 'accounting_authorization':
      return p.and(
        p.perm('stage:accounting_authorization:act:all'),
        p.role(['account_supervisor', 'accounting_manager']),
      );
    case 'awaiting_disbursement':
      return p.and(p.perm('stage:disbursement_authorization:act:all'), p.role('finance'));
    case 'gl_confirmed':
      return p.and(
        p.perm('stage:gl_confirmed:act:all'),
        p.role(['account_officer', 'account_supervisor', 'accounting_manager', 'finance']),
      );
    default:
      return p.or(p.admin(), p.role([...PRIVILEGED_ROLES]));
  }
}

export function procurementStagePolicy(currentStage: string, amountTHB?: number): Policy {
  switch (currentStage) {
    case 'submission':
      return p.owner('requester_id');
    case 'dept_authorization':
      return p.and(
        p.perm('stage:dept_authorization:act:dept'),
        p.dept('same'),
        p.role('manager'),
      );
    case 'accounting_authorization':
      return p.and(p.perm('stage:accounting_authorization:act:all'), p.role('accounting_manager'));
    case 'cfo_authorization': {
      const amount = amountTHB ?? 0;
      if (amount >= 200_000) {
        return p.and(
          p.perm('stage:cfo_authorization:act:all'),
          p.amountGte(200_000),
          p.role('cfo'),
        );
      }
      return p.or(
        p.admin(),
        p.and(p.perm('stage:cfo_authorization:act:all'), p.role(['cfo', 'accounting_manager'])),
      );
    }
    case 'disbursed':
      return p.and(p.perm('stage:disbursement_authorization:act:all'), p.role('finance'));
    default:
      return p.or(p.admin(), p.role([...PRIVILEGED_ROLES]));
  }
}

export function salesStagePolicy(currentStage: string, amountTHB?: number): Policy {
  switch (currentStage) {
    case 'so_draft':
      return p.and(
        p.perm('stage:so_draft:act:all'),
        p.role(['sales_rep', 'sales_supervisor', 'admin']),
      );
    case 'so_sales_review':
      return p.and(
        p.perm('stage:so_sales_review:act:all'),
        p.role(['sales_supervisor', 'admin']),
      );
    case 'so_credit_check':
      return p.and(
        p.perm('stage:so_credit_check:act:all'),
        p.role(['account_officer', 'account_supervisor', 'accounting_manager', 'sales_supervisor', 'admin']),
      );
    case 'so_invoiced':
      return p.and(
        p.perm('stage:so_invoiced:act:all'),
        p.role(['accounting_manager', 'admin']),
      );
    case 'so_paid':
      return p.and(
        p.perm('stage:so_paid:act:all'),
        p.role(['finance', 'admin']),
      );
    default:
      return p.or(p.admin(), p.role([...PRIVILEGED_ROLES]));
  }
}

export function canActOnWaybillResource(resource: PolicyResource | undefined): Policy {
  if (!resource) return p.and(p.admin());
  const origin = (resource.origin ?? 'expense') as 'expense' | 'pr' | 'po' | 'so';
  const stage = resource.current_stage ?? '';
  const amount = resource.total_amount_thb ?? undefined;
  if (origin === 'expense') return expenseStagePolicy(stage, amount);
  if (origin === 'so') return salesStagePolicy(stage, amount);
  return procurementStagePolicy(stage, amount);
}

export const POL = {
  // ── View / list ──────────────────────────────────────────────────────────
  viewWaybill: p.or(
    p.perm('finance:expense:view:self'),
    p.perm('finance:expense:view:dept'),
    p.perm('finance:expense:view:subtree'),
    p.perm('finance:expense:view:all'),
    p.perm('finance:pr:view:self'),
    p.perm('finance:pr:view:dept'),
    p.perm('finance:pr:view:all'),
    p.perm('finance:po:view:all'),
    p.admin(),
  ),
  viewWaybillPdf: p.or(p.perm('finance:expense:view:all'), p.owner('submitter_id')),
  viewExpense: p.or(p.perm('finance:expense:view:all'), p.owner('submitter_id')),
  viewPr: p.or(
    p.perm('finance:pr:view:all'),
    p.perm('finance:pr:view:dept'),
    p.perm('finance:pr:view:self'),
    p.owner('requester_id'),
    p.admin(),
  ),
  viewPo: p.or(
    p.perm('finance:po:view:all'),
    p.perm('finance:po:view:dept'),
    p.perm('finance:po:view:self'),
    p.owner('requester_id'),
    p.admin(),
  ),
  viewSlipPayslip: p.or(
    p.owner('submitter_id'),
    p.admin(),
    financeRole(),
    p.role(['cfo', 'ceo', 'it']),
  ),

  // ── Stage transitions ────────────────────────────────────────────────────
  canActOnWaybill: p.and(),
  rejectWaybill: p.and(
    p.not(p.stage(['disbursed', 'gl_confirmed', 'rejected'])),
    p.or(
      p.admin(),
      p.role([...PRIVILEGED_ROLES]),
      financeRole(),
    ),
  ),
  resubmitExpense: p.and(
    p.owner('submitter_id'),
    p.stage('rejected'),
    p.perm('finance:expense:create:self'),
  ),
  recallWaybill: p.or(p.admin(), p.role(['cfo', 'ceo', 'finance'])),

  // ── GL ops ───────────────────────────────────────────────────────────────
  canSeeGlLines: p.or(
    p.admin(),
    financeRole(),
    p.role(['cfo', 'ceo']),
  ),
  canFinalApproveExpense: p.and(
    p.perm('finance:expense:settle:all'),
    p.stage(['accounting_authorization', 'final_authorization']),
    financeRole(),
  ),
  canSettleExpense: p.and(
    p.perm('finance:expense:settle:all'),
    p.stage('awaiting_disbursement'),
    p.role('finance'),
  ),
  canConfirmGl: p.and(
    p.perm('finance:gl:confirm:all'),
    p.stage('disbursed'),
    p.or(p.role(['account_officer','account_supervisor','accounting_manager','finance','cfo','ceo'])),
  ),
  canPostGlAccrual: p.and(
    p.perm('finance:gl:post:all'),
    p.stage('accounting_authorization'),
    p.role('accounting_manager'),
  ),
  canPostGlSettlement: p.and(
    p.perm('finance:gl:post:all'),
    p.stage('disbursed'),
    financeRole(),
  ),
  canSaveProcurementAccrual: p.and(
    p.perm('finance:pr:edit:all'),
    financeRole(),
  ),

  // ── Attachments ──────────────────────────────────────────────────────────
  canAttachAtStage: p.or(
    p.admin(),
    p.and(p.perm('finance:waybill:attach:all'), p.not(p.stage(['disbursed', 'rejected']))),
    p.and(
      p.owner('submitter_id'),
      p.stage('submission'),
      p.perm('finance:expense:create:self'),
    ),
  ),
  canRemoveAttachment: p.or(p.admin(), p.role([...PRIVILEGED_ROLES])),

  // ── PR / PO actions ──────────────────────────────────────────────────────
  canSubmitPr: p.perm('finance:pr:create:self'),
  canApprovePr: p.or(
    p.perm('finance:pr:approve:all'),
    p.and(
      p.perm('finance:pr:approve:dept'),
      p.dept('same'),
      p.role('manager'),
    ),
  ),
  canSubmitPo: p.perm('finance:po:create:all'),
  canApprovePo: p.perm('finance:po:approve:all'),
  canAttachPoPayslip: p.and(
    p.perm('finance:po:attach_payslip:all'),
    p.or(financeRole(), p.role(['cfo', 'ceo', 'admin'])),
  ),

  // ── Sales / SO actions ───────────────────────────────────────────────────
  viewSalesOrder: p.or(
    p.perm('finance:sales:view:all'),
    p.perm('finance:sales:create:self'),
    p.perm('finance:sales:approve:dept'),
    p.perm('finance:sales:approve:all'),
    p.perm('finance:sales:settle:all'),
    p.role(['sales_rep', 'sales_supervisor', 'admin']),
    p.admin(),
  ),
  canActOnSalesOrder: p.and(),
  canSubmitSalesOrder: p.and(
    p.perm('finance:sales:create:self'),
    p.role(['sales_rep', 'sales_supervisor', 'admin']),
  ),
  canApproveSalesAtReview: p.and(
    p.perm('finance:sales:approve:dept'),
    p.role(['sales_supervisor', 'admin']),
  ),
  canApproveSalesAtCredit: p.and(
    p.perm('finance:sales:approve:dept'),
    p.role(['account_officer', 'account_supervisor', 'accounting_manager', 'sales_supervisor', 'admin']),
  ),
  canIssueSalesInvoice: p.and(
    p.perm('stage:so_invoiced:act:all'),
    p.role(['accounting_manager', 'admin']),
  ),
  canSettleSales: p.and(
    p.perm('finance:sales:settle:all'),
    p.role(['finance', 'admin']),
  ),
  canPostSalesGlVat: p.and(
    p.perm('finance:sales:gl_confirm:all'),
    p.stage('so_invoiced'),
    p.role(['accounting_manager', 'admin']),
  ),
  canPostSalesGlAccrual: p.and(
    p.perm('finance:sales:gl_confirm:all'),
    p.stage('so_invoiced'),
    p.role(['accounting_manager', 'admin']),
  ),
  canPostSalesGlSettlement: p.and(
    p.perm('finance:sales:gl_confirm:all'),
    p.stage('so_paid'),
    p.or(financeRole(), p.role(['admin'])),
  ),
  canConfirmSalesGl: p.and(
    p.perm('finance:sales:gl_confirm:all'),
    p.or(financeRole(), p.role(['cfo', 'ceo', 'admin'])),
  ),

  // ── Customer master actions ──────────────────────────────────────────────
  viewCustomer: p.or(
    p.perm('finance:customer:view:all'),
    p.perm('finance:customer:view:self'),
    p.role(['sales_rep', 'sales_supervisor', 'admin']),
    p.admin(),
  ),
  canManageCustomer: p.or(
    p.perm('finance:customer:edit:all'),
    p.and(
      p.perm('finance:customer:edit:self'),
      p.or(p.role(['sales_rep', 'sales_supervisor']), p.admin()),
    ),
  ),

  // ── Draft lifecycle ──────────────────────────────────────────────────────
  canStartExpenseDraft: p.perm('finance:expense:create:self'),
  canSaveExpenseDraft: p.and(
    p.perm('finance:expense:create:self'),
    p.owner('submitter_id'),
    p.stage('draft'),
  ),
  canDiscardExpenseDraft: p.and(p.owner('submitter_id'), p.stage('draft')),

  // ── Misc ─────────────────────────────────────────────────────────────────
  canUseCoaSearch: p.perm('tile:search_coa:view'),
  canUploadSlip: p.perm('finance:slip:create:self'),
  // NOTE: policies that include `levelAtMostColumn(column)` (e.g.
  // expenseStagePolicy at `dept_verification`) cannot be used with
  // `compilePolicyToSql` — the SQL compile path returns FALSE for them
  // because the column reference needs a row context. These policies MUST
  // go through `requirePolicy` / `evalPolicy` (which has access to
  // resource rows), not through the SQL row-filter pipeline.
  deptHasManagerClass: p.admin(),
} as const satisfies Record<string, Policy>;

export type PolKey = keyof typeof POL;

export function policyByKey<K extends PolKey>(key: K): (typeof POL)[K] {
  return POL[key];
}