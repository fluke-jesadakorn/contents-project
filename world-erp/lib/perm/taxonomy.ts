// perm permissions constants.
//
// Permission id grammar: '<domain>:<subject>:<verb>[:<qualifier>]::<effect>'
//   domain    ∈ {rbac, user, org, finance, stage, tile, hook, ai, policy, access_request, admin}
//   subject   ∈ lowercase snake
//   verb      ∈ lowercase snake
//   qualifier ∈ optional: omitted or '*' = global; '<dept_id>' = dept-scoped
//   effect    ∈ {allow, deny}
//
// Use as: `hasPermission(session, PERM.finance.expense.approve)`
// (the constant already includes the '::allow' suffix).

import { buildPerm } from './grammar';

const allow = (d: string, s: string, v: string, q?: string) =>
  buildPerm({ domain: d, subject: s, verb: v, qualifier: q }, 'allow');

export const PERM = {
  rbac: {
    role:   { read: allow('rbac', 'role', 'read'), assign: allow('rbac', 'role', 'assign') },
    matrix: { view: allow('rbac', 'matrix', 'view'), edit: allow('rbac', 'matrix', 'edit') },
    audit:  { view: allow('rbac', 'audit', 'view') },
  },
  admin: {
    system: { bypass: allow('admin', 'system', 'bypass') },
  },
  user: {
    directory: { read: allow('user', 'directory', 'read') },
    profile:   {
      create: allow('user', 'profile', 'create'),
      update: allow('user', 'profile', 'update'),
      delete: allow('user', 'profile', 'delete'),
      deactivate: allow('user', 'profile', 'deactivate'),
    },
    role:    { assign: allow('user', 'role', 'assign') },
    manager: { set: allow('user', 'manager', 'set') },
    dept:    { edit: allow('user', 'dept', 'edit') },
    subtree: { edit: allow('user', 'subtree', 'edit') },
  },
  org: {
    tree:      { view: allow('org', 'tree', 'view') },
    dept:      { read: allow('org', 'dept', 'read'), assign_head: allow('org', 'dept', 'assign_head') },
    dept_role: { assign: allow('org', 'dept_role', 'assign'), revoke: allow('org', 'dept_role', 'revoke'), list: allow('org', 'dept_role', 'list') },
    auto_wire: { propose: allow('org', 'auto_wire', 'propose'), apply: allow('org', 'auto_wire', 'apply') },
    hook:      { read: allow('org', 'hook', 'read') },
  },
  finance: {
    expense: {
      view_own: allow('finance', 'expense', 'view_own'),
      view_all: allow('finance', 'expense', 'view_all'),
      create:   allow('finance', 'expense', 'create'),
      update:   allow('finance', 'expense', 'update'),
      delete:   allow('finance', 'expense', 'delete'),
      review:   allow('finance', 'expense', 'review'),
      approve:  allow('finance', 'expense', 'approve'),
      reject:   allow('finance', 'expense', 'reject'),
      settle:   allow('finance', 'expense', 'settle'),
      disburse: allow('finance', 'expense', 'disburse'),
      override: allow('finance', 'expense', 'override'),
      override_approve: allow('finance', 'expense', 'override_approve'),
      gl_confirm: allow('finance', 'expense', 'gl_confirm'),
    },
    pr: {
      create: allow('finance', 'pr', 'create'),
      update: allow('finance', 'pr', 'update'),
      delete: allow('finance', 'pr', 'delete'),
      approve: allow('finance', 'pr', 'approve'),
      reject: allow('finance', 'pr', 'reject'),
      override_approve: allow('finance', 'pr', 'override_approve'),
    },
    po: {
      approve: allow('finance', 'po', 'approve'),
      reject: allow('finance', 'po', 'reject'),
      attach_payslip: allow('finance', 'po', 'attach_payslip'),
      settle: allow('finance', 'po', 'settle'),
    },
    ledger:           { view: allow('finance', 'ledger', 'view') },
    reconciliation:   { view: allow('finance', 'reconciliation', 'view') },
    report:           { executive: allow('finance', 'report', 'executive') },
    budget:           { view: allow('finance', 'budget', 'view') },
    client_contracts: { view: allow('finance', 'client_contracts', 'view') },
    core_operations:  { view: allow('finance', 'core_operations', 'view') },
    project_tasks:    { view: allow('finance', 'project_tasks', 'view') },
  },
  stage: {
    submission:                 { act: allow('stage', 'submission', 'act') },
    dept_verification:          { act: allow('stage', 'dept_verification', 'act') },
    dept_authorization:         { act: allow('stage', 'dept_authorization', 'act') },
    accounting_verification:    { act: allow('stage', 'accounting_verification', 'act') },
    accounting_supervision:     { act: allow('stage', 'accounting_supervision', 'act') },
    accounting_authorization:   { act: allow('stage', 'accounting_authorization', 'act') },
    disbursement_authorization: { act: allow('stage', 'disbursement_authorization', 'act') },
    cfo_authorization:          { act: allow('stage', 'cfo_authorization', 'act') },
    ceo_authorization:          { act: allow('stage', 'ceo_authorization', 'act') },
    gl_confirmed:               { act: allow('stage', 'gl_confirmed', 'act') },
    po_pending:                 { act: allow('stage', 'po_pending', 'act') },
    po_cfo:                     { act: allow('stage', 'po_cfo', 'act') },
    so_draft:                   { act: allow('stage', 'so_draft', 'act') },
    so_sales_review:            { act: allow('stage', 'so_sales_review', 'act') },
    so_credit_check:            { act: allow('stage', 'so_credit_check', 'act') },
    so_invoiced:                { act: allow('stage', 'so_invoiced', 'act') },
    so_paid:                    { act: allow('stage', 'so_paid', 'act') },
    final_authorization:        { act: allow('stage', 'final_authorization', 'act') },
  },
  tile: {
    inbox:           { view: allow('tile', 'inbox', 'view') },
    expense:         { view: allow('tile', 'expense', 'view') },
    pr:              { view: allow('tile', 'pr', 'view') },
    po:              { view: allow('tile', 'po', 'view') },
    sales:           { view: allow('tile', 'sales', 'view') },
    customers:       { view: allow('tile', 'customers', 'view') },
    search_coa:      { view: allow('tile', 'search_coa', 'view') },
    reconciliation:  { view: allow('tile', 'reconciliation', 'view') },
    team_manage:     { view: allow('tile', 'team_manage', 'view') },
    cockpit:         { view: allow('tile', 'cockpit', 'view') },
    summary:         { view: allow('tile', 'summary', 'view') },
    ledger:          { view: allow('tile', 'ledger', 'view') },
    policy:          { view: allow('tile', 'policy', 'view') },
    settings:        { view: allow('tile', 'settings', 'view') },
    org_chart:       { view: allow('tile', 'org_chart', 'view') },
    roles:           { view: allow('tile', 'roles', 'view') },
    tile_gates:      { view: allow('tile', 'tile_gates', 'view') },
    directory:       { view: allow('tile', 'directory', 'view') },
    audit:           { view: allow('tile', 'audit', 'view') },
    departments:     { view: allow('tile', 'departments', 'view') },
    access_requests: { view: allow('tile', 'access_requests', 'view') },
    hook:            { view: allow('tile', 'hook', 'view') },
    hook_view:       { view: allow('tile', 'hook_view', 'view') },
    hook_inbox:      { view: allow('tile', 'hook_inbox', 'view') },
    permissions:     { view: allow('tile', 'permissions', 'view') },
    hub:             { view: allow('tile', 'hub', 'view') },
    ops_overview:    { view: allow('tile', 'ops_overview', 'view') },
    my_prs:          { view: allow('tile', 'my_prs', 'view') },
    dash_am:         { view: allow('tile', 'dash_am', 'view') },
    dash_exec:       { view: allow('tile', 'dash_exec', 'view') },
    dash_finance:    { view: allow('tile', 'dash_finance', 'view') },
    dash_hr:         { view: allow('tile', 'dash_hr', 'view') },
    dash_it:         { view: allow('tile', 'dash_it', 'view') },
    dash_manager:    { view: allow('tile', 'dash_manager', 'view') },
    dash_reviewer:   { view: allow('tile', 'dash_reviewer', 'view') },
    dash_staff:      { view: allow('tile', 'dash_staff', 'view') },
  },
  hook: {
    event: { view: allow('hook', 'event', 'view'), replay: allow('hook', 'event', 'replay') },
  },
  ai: {
    provider:   {
      read: allow('ai', 'provider', 'read'), create: allow('ai', 'provider', 'create'),
      update: allow('ai', 'provider', 'update'), delete: allow('ai', 'provider', 'delete'),
      test: allow('ai', 'provider', 'test'),
    },
    model: {
      read: allow('ai', 'model', 'read'), create: allow('ai', 'model', 'create'),
      update: allow('ai', 'model', 'update'), delete: allow('ai', 'model', 'delete'),
    },
    staff: {
      read: allow('ai', 'staff', 'read'), create: allow('ai', 'staff', 'create'),
      update: allow('ai', 'staff', 'update'), delete: allow('ai', 'staff', 'delete'),
      invoke: allow('ai', 'staff', 'invoke'),
    },
    assignment: {
      read: allow('ai', 'assignment', 'read'), create: allow('ai', 'assignment', 'create'),
      delete: allow('ai', 'assignment', 'delete'),
    },
    invocation:     { view: allow('ai', 'invocation', 'view') },
    section_health: { view: allow('ai', 'section_health', 'view') },
  },
  policy: {
    rbac: { view: allow('rbac', 'matrix', 'view'), edit: allow('rbac', 'matrix', 'edit') },
  },
  access_request: {
    request: {
      list: allow('access_request', 'request', 'list'),
      resolve: allow('access_request', 'request', 'resolve'),
    },
  },
} as const;

export { PERM_ID_REGEX } from './grammar';

export const DOMAINS = [
  'rbac', 'user', 'org', 'finance', 'stage', 'tile', 'hook', 'ai', 'policy', 'access_request', 'admin',
] as const;
export type Domain = (typeof DOMAINS)[number];
