// One-off rewrite of requireActionFor call sites.

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const PERM_FINANCE = {
  expense: {
    review:     'finance:expense:review',
    approve:    'finance:expense:approve',
    reject:     'finance:expense:reject',
    settle:     'finance:expense:settle',
    create:     'finance:expense:create',
    override:   'finance:expense:override',
  },
  pr: {
    create:    'finance:pr:create',
    approve:   'finance:pr:approve',
  },
  po: {
    approve:        'finance:po:approve',
    attach_payslip: 'finance:po:attach_payslip',
  },
};
const PERM_POLICY = {
  approval: { edit: 'policy:approval:edit' },
};

const MAP: Record<string, string> = {
  'review_expense|update':     PERM_FINANCE.expense.review,
  'approve_expense|update':    PERM_FINANCE.expense.approve,
  'reject_expense|update':     PERM_FINANCE.expense.reject,
  'settle_payment|update':     PERM_FINANCE.expense.settle,
  'submit_expense|create':     PERM_FINANCE.expense.create,
  'ceo_override|update':       PERM_FINANCE.expense.override,
  'edit_policy':               PERM_POLICY.approval.edit,
  'submit_pr|create':          PERM_FINANCE.pr.create,
  'approve_pr|update':         PERM_FINANCE.pr.approve,
  'approve_pr|create':         PERM_FINANCE.pr.create,
  'approve_po|update':         PERM_FINANCE.po.approve,
  'attach_po_payslip|update':  PERM_FINANCE.po.attach_payslip,
};

for (const file of [
  'web-admin/src/app/actions.ts',
  'web-admin/src/app/actions-finance.ts',
]) {
  const path = resolve('/Users/fluke/Desktop/Work/Contents/world-erp', file);
  let s = readFileSync(path, 'utf8');
  const before = s;

  // single-line form
  s = s.replace(
    /requireActionFor\(([^,]+),\s*'([a-z_]+)',\s*\{\s*rbacSection:\s*'[^']+',\s*rbacAction:\s*'(create|read|update|delete)'\s*\}\)/g,
    (_m: string, who: string, action: string, verb: string) => {
      const perm = MAP[`${action}|${verb}`];
      if (!perm) return _m;
      return `requireActionFor(${who}, '${action}', { perm: '${perm}' })`;
    }
  );

  // multi-line form  { rbacSection: '...', rbacAction: '...', stage: '...' }
  s = s.replace(
    /requireActionFor\(([^,]+),\s*'([a-z_]+)',\s*\{\s*rbacSection:\s*'([^']+)',\s*rbacAction:\s*'(create|read|update|delete)'([^}]*)\}\)/g,
    (_m: string, who: string, action: string, _section: string, verb: string, rest: string) => {
      const perm = MAP[`${action}|${verb}`];
      if (!perm) return _m;
      return `requireActionFor(${who}, '${action}', { perm: '${perm}'${rest} })`;
    }
  );

  // requireActionFor(... 'edit_policy')  →  { perm: 'policy:approval:edit' }
  s = s.replace(
    /requireActionFor\(([^,]+),\s*'edit_policy'\)/g,
    (_m: string, who: string) =>
      `requireActionFor(${who}, 'edit_policy', { perm: '${PERM_POLICY.approval.edit}' })`,
  );

  if (s !== before) {
    writeFileSync(path, s, 'utf8');
    console.log(`updated: ${file}`);
  } else {
    console.log(`no change: ${file}`);
  }
}
