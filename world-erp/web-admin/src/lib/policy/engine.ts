// World ERP v2 — Approval policy engine
// Pure functions: no DB, no side effects. Easy to unit-test and reuse.

export type Condition =
  | { field: string; op: 'eq' | 'neq'; value: any }
  | { field: string; op: 'in' | 'nin'; value: any[] }
  | { field: string; op: 'gt' | 'gte' | 'lt' | 'lte'; value: number }
  | { field: string; op: 'between'; value: [number, number] }
  | { field: string; op: 'contains'; value: string };

export type Conditions = { all_of?: Condition[]; any_of?: Condition[] };
export type Action = {
  approver_chain: string[]; // role names
  auto_approve?: boolean;
  notify?: string[];
};
export type Policy = {
  id: number;
  name: string;
  priority: number;
  is_active: boolean;
  target_type: 'expense' | 'pr' | 'po' | 'both';
  conditions_json: Conditions;
  action_json: Action;
};

export type Context = {
  targetType: 'expense' | 'pr' | 'po';
  totalAmount: number;
  department?: string | null;
  submitterRole?: string | null;
  isRecurring?: boolean;
  categoryCode?: string | null;
  // free-form extras, looked up by `field` in conditions
  [key: string]: any;
};

const FIELD_GETTERS: Record<string, (c: Context) => any> = {
  total_amount: c => Number(c.totalAmount ?? 0),
  department: c => c.department ?? null,
  submitter_role: c => c.submitterRole ?? null,
  is_recurring: c => !!c.isRecurring,
  category_code: c => c.categoryCode ?? null,
  target_type: c => c.targetType,
};

function getField(c: Context, name: string) {
  if (name in c) return c[name];
  if (FIELD_GETTERS[name]) return FIELD_GETTERS[name](c);
  return undefined;
}

function evalCondition(c: Context, cond: Condition): boolean {
  const v = getField(c, cond.field);
  switch (cond.op) {
    case 'eq':  return v === cond.value;
    case 'neq': return v !== cond.value;
    case 'in':  return Array.isArray(cond.value) && cond.value.includes(v);
    case 'nin': return Array.isArray(cond.value) && !cond.value.includes(v);
    case 'gt':  return Number(v) >  Number(cond.value);
    case 'gte': return Number(v) >= Number(cond.value);
    case 'lt':  return Number(v) <  Number(cond.value);
    case 'lte': return Number(v) <= Number(cond.value);
    case 'between': {
      const [lo, hi] = cond.value;
      return Number(v) >= Number(lo) && Number(v) <= Number(hi);
    }
    case 'contains': {
      return typeof v === 'string' && v.toLowerCase().includes(String(cond.value).toLowerCase());
    }
    default: return false;
  }
}

export function matches(policy: Policy, ctx: Context): boolean {
  if (!policy.is_active) return false;
  if (policy.target_type !== 'both' && policy.target_type !== ctx.targetType) return false;
  const c = policy.conditions_json || {};
  const all = Array.isArray(c.all_of) ? c.all_of : [];
  const any = Array.isArray(c.any_of) ? c.any_of : [];
  // any_of with no entries is treated as no restriction
  const anyOk = any.length === 0 || any.some(cond => evalCondition(ctx, cond));
  const allOk = all.every(cond => evalCondition(ctx, cond));
  return anyOk && allOk;
}

export function pickPolicy(policies: Policy[], ctx: Context): Policy | null {
  const eligible = policies.filter(p => matches(p, ctx));
  eligible.sort((a, b) => a.priority - b.priority);
  return eligible[0] || null;
}

export const APPROVER_TO_STAGE: Record<string, string> = {
  supervisor:         'supervisor_review',
  head_of_department: 'head_review',
  account_officer:    'account_officer_review',
  account_supervisor: 'account_supervisor_review',
  accounting_manager: 'accounting_review',
  cfo:                'cfo_review',
  ceo:                'ceo_review',
  finance:            'finance_review',
};

export { STAGE_TO_ROLE, STAGE_TO_ROLE_PO } from '@/lib/rbac/stage-types';

export function nextStageFromChain(chain: string[], currentIndex: number): {
  next: string | null;
  nextIndex: number;
  final: boolean;
} {
  if (currentIndex >= chain.length) {
    const lastRole = chain[chain.length - 1];
    const terminal = lastRole === 'finance' ? 'finance_review' : 'approved';
    return { next: terminal, nextIndex: currentIndex, final: true };
  }
  const role = chain[currentIndex];
  const stage = APPROVER_TO_STAGE[role] ?? null;
  if (!stage) return { next: null, nextIndex: currentIndex, final: false };
  const isLast = currentIndex + 1 >= chain.length;
  return { next: stage, nextIndex: currentIndex + 1, final: isLast };
}

export const PO_STAGES = ['po_pending', 'po_cfo', 'po_done'] as const;
export type POStage = (typeof PO_STAGES)[number];

// STAGE_TO_ROLE_PO is now defined in lib/rbac/stage.ts and re-exported
// above. The local declaration was removed to keep a single source of
// truth.

export function nextPoStageFromChain(
  chain: string[],
  currentIndex: number
): { next: POStage | 'approved' | null; nextIndex: number; final: boolean } {
  if (currentIndex >= chain.length) {
    return { next: 'approved', nextIndex: currentIndex, final: true };
  }
  const role = chain[currentIndex];
  const stage: POStage | null =
    role === 'accounting_manager' ? 'po_pending' :
    role === 'cfo' ? 'po_cfo' :
    null;
  if (!stage) return { next: null, nextIndex: currentIndex, final: false };
  const isLast = currentIndex + 1 >= chain.length;
  return { next: stage, nextIndex: currentIndex + 1, final: isLast };
}

/**
 * Dynamic chain resolver: returns the chain with roles skipped when:
 *   (a) the role is not present anywhere in the org ("if exists" semantics), OR
 *   (b) the submitter's direct manager is not of that role (per-stage guard).
 *
 * Returns { chain, skippedRoles } so callers can render a tooltip / hint.
 */
export function resolveDynamicChain(args: {
  chain: string[];
  existingRoles: Set<string>;
  submitterRole: string | null;
  submitterManagerRole: string | null;
}): { chain: string[]; skippedRoles: string[] } {
  const skipped: string[] = [];
  const out: string[] = [];
  for (const role of args.chain) {
    // Universal roles — always included
    if (['head_of_department', 'accounting_manager', 'cfo', 'ceo', 'finance'].includes(role)) {
      out.push(role);
      continue;
    }
    if (role === 'supervisor') {
      if (!args.existingRoles.has('supervisor')) {
        skipped.push(role);
        continue;
      }
      if (args.submitterManagerRole !== 'supervisor') {
        skipped.push(role);
        continue;
      }
      out.push(role);
      continue;
    }
    if (role === 'account_supervisor') {
      if (!args.existingRoles.has('account_supervisor')) {
        skipped.push(role);
        continue;
      }
      out.push(role);
      continue;
    }
    if (role === 'account_officer') {
      if (args.submitterRole === 'account_officer') {
        skipped.push(role);
        continue;
      }
      out.push(role);
      continue;
    }
    // Default — include
    out.push(role);
  }
  return { chain: out, skippedRoles: skipped };
}

export const STATUS_LABELS: Record<string, { th: string; en: string; emoji: string }> = {
  draft:                       { th: 'Draft',                  en: 'Draft',                  emoji: '📝' },
  ocr_extracted:               { th: 'Awaiting Accountant',              en: 'Awaiting Accountant',    emoji: '📸' },
  supervisor_review:           { th: 'Awaiting Supervisor',            en: 'Awaiting Supervisor',    emoji: '👥' },
  head_review:                 { th: 'Awaiting Head of Dept',           en: 'Awaiting Head of Dept',  emoji: '🛡️' },
  account_officer_review:      { th: 'Awaiting Account Officer',      en: 'Awaiting Account Officer', emoji: '🧾' },
  account_supervisor_review:   { th: 'Awaiting Account Supervisor',         en: 'Awaiting Account Supervisor', emoji: '📊' },
  accounting_review:           { th: 'Awaiting Accounting Manager',        en: 'Awaiting Accounting Mgr',emoji: '⚙️' },
  cfo_review:                  { th: 'Awaiting CFO Approval',          en: 'Awaiting CFO',           emoji: '👑' },
  ceo_review:                  { th: 'Awaiting CEO Approval',          en: 'Awaiting CEO',           emoji: '🦅' },
  finance_review:              { th: 'Awaiting Finance Disbursement',          en: 'Awaiting Finance',       emoji: '💳' },
  accountant_reviewed:         { th: 'Awaiting Approver (legacy)',   en: 'Accountant Reviewed',    emoji: '⚙️' },
  approved:                    { th: 'Approved',              en: 'Approved',               emoji: '✅' },
  paid:                        { th: 'Paid',              en: 'Paid',                  emoji: '💳' },
  rejected:                    { th: 'Rejected',                en: 'Rejected',              emoji: '❌' },
};
