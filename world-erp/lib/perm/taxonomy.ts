// perm permissions constants.
//
// Permission id grammar: 'domain:subject:verb'
//   domain  ∈ {rbac, user, org, finance, stage, tile, hook, ai, policy, access_request}
//   subject ∈ lowercase snake, matches the entity the verb targets
//   verb    ∈ lowercase snake, action on the subject
//
// Use as the `permission` arg to `hasPermission(session, PERM.finance.expense.approve)`.

export const PERM = {
  rbac: {
    role:    { read: 'rbac:role:read', assign: 'rbac:role:assign' },
    matrix:  { view: 'rbac:matrix:view', edit: 'rbac:matrix:edit' },
    audit:   { view: 'rbac:audit:view' },
  },
  admin: {
    system: { bypass: 'admin:system:bypass' },
  },
  user: {
    directory: { read: 'user:directory:read' },
    profile:   { create: 'user:profile:create', update: 'user:profile:update', delete: 'user:profile:delete', deactivate: 'user:profile:deactivate' },
    role:      { assign: 'user:role:assign' },
    manager:   { set: 'user:manager:set' },
    dept:      { edit: 'user:dept:edit' },
    subtree:   { edit: 'user:subtree:edit' },
  },
  org: {
    tree:      { view: 'org:tree:view' },
    dept:      { read: 'org:dept:read', assign_head: 'org:dept:assign_head' },
    dept_role: { assign: 'org:dept_role:assign', revoke: 'org:dept_role:revoke', list: 'org:dept_role:list' },
    auto_wire: { propose: 'org:auto_wire:propose', apply: 'org:auto_wire:apply' },
    hook:      { read: 'org:hook:read' },
  },
  finance: {
    expense: {
      view_own: 'finance:expense:view_own', view_all: 'finance:expense:view_all',
      create:   'finance:expense:create',   update: 'finance:expense:update',
      delete:   'finance:expense:delete',   review: 'finance:expense:review',
      approve:  'finance:expense:approve',  reject: 'finance:expense:reject',
      settle:   'finance:expense:settle',   disburse: 'finance:expense:disburse',
      override: 'finance:expense:override',
      override_approve: 'finance:expense:override_approve',
    },
    pr: {
      create: 'finance:pr:create', update: 'finance:pr:update',
      delete: 'finance:pr:delete',
      approve: 'finance:pr:approve', reject: 'finance:pr:reject',
      override_approve: 'finance:pr:override_approve',
    },
    po: {
      approve: 'finance:po:approve', reject: 'finance:po:reject',
      attach_payslip: 'finance:po:attach_payslip', settle: 'finance:po:settle',
    },
    ledger:        { view: 'finance:ledger:view' },
    reconciliation:{ view: 'finance:reconciliation:view' },
    report:        { executive: 'finance:report:executive' },
    budget:        { view: 'finance:budget:view' },
    client_contracts: { view: 'finance:client_contracts:view' },
    core_operations:  { view: 'finance:core_operations:view' },
    project_tasks:    { view: 'finance:project_tasks:view' },
  },
  stage: {
    submission:                { act: 'stage:submission:act' },
    dept_verification:         { act: 'stage:dept_verification:act' },
    dept_authorization:        { act: 'stage:dept_authorization:act' },
    accounting_verification:   { act: 'stage:accounting_verification:act' },
    accounting_supervision:    { act: 'stage:accounting_supervision:act' },
    accounting_authorization:  { act: 'stage:accounting_authorization:act' },
    disbursement_authorization:{ act: 'stage:disbursement_authorization:act' },
    cfo_authorization:         { act: 'stage:cfo_authorization:act' },
    ceo_authorization:         { act: 'stage:ceo_authorization:act' },
    po_pending:                { act: 'stage:po_pending:act' },
    po_cfo:                    { act: 'stage:po_cfo:act' },
    // legacy aliases kept for caller compatibility during migration
    ocr_extracted:             { act: 'stage:submission:act' },
    supervisor_review:         { act: 'stage:dept_verification:act' },
    manager_review:            { act: 'stage:dept_authorization:act' },
    account_officer_review:    { act: 'stage:accounting_verification:act' },
    account_supervisor_review: { act: 'stage:accounting_supervision:act' },
    accounting_review:         { act: 'stage:accounting_authorization:act' },
    finance_review:            { act: 'stage:disbursement_authorization:act' },
    cfo_review:                { act: 'stage:cfo_authorization:act' },
    ceo_review:                { act: 'stage:ceo_authorization:act' },
  },
  tile: {
    workbench:      { view: 'tile:workbench:view' },
    pr:             { view: 'tile:pr:view' },
    ledger:         { view: 'tile:ledger:view' },
    cockpit:        { view: 'tile:cockpit:view' },
    policy:         { view: 'tile:policy:view' },
    settings:       { view: 'tile:settings:view' },
    hr:             { view: 'tile:hr:view' },
    submit_expense: { view: 'tile:submit_expense:view' },
    my_history:     { view: 'tile:my_history:view' },
    my_prs:         { view: 'tile:my_prs:view' },
    search_coa:     { view: 'tile:search_coa:view' },
    review_queue:   { view: 'tile:review_queue:view' },
    approve_expense:{ view: 'tile:approve_expense:view' },
    all_approvals:  { view: 'tile:all_approvals:view' },
    directory:      { view: 'tile:directory:view' },
    org_chart:      { view: 'tile:org_chart:view' },
    departments:    { view: 'tile:departments:view' },
    access_requests:{ view: 'tile:access_requests:view' },
    dash_it:        { view: 'tile:dash_it:view' },
    dash_exec:      { view: 'tile:dash_exec:view' },
    dash_manager:   { view: 'tile:dash_manager:view' },
    dash_am:        { view: 'tile:dash_am:view' },
    dash_reviewer:  { view: 'tile:dash_reviewer:view' },
    dash_staff:     { view: 'tile:dash_staff:view' },
    dash_hr:        { view: 'tile:dash_hr:view' },
    dash_finance:   { view: 'tile:dash_finance:view' },
    hook_view:      { view: 'tile:hook_view:view' },
  },
  hook: {
    event: { view: 'hook:event:view', replay: 'hook:event:replay' },
  },
  ai: {
    provider:   { read: 'ai:provider:read', create: 'ai:provider:create', update: 'ai:provider:update', delete: 'ai:provider:delete', test: 'ai:provider:test' },
    model:      { read: 'ai:model:read',    create: 'ai:model:create',    update: 'ai:model:update',    delete: 'ai:model:delete' },
    staff:      { read: 'ai:staff:read',    create: 'ai:staff:create',    update: 'ai:staff:update',    delete: 'ai:staff:delete', invoke: 'ai:staff:invoke' },
    assignment: { read: 'ai:assignment:read', create: 'ai:assignment:create', delete: 'ai:assignment:delete' },
    invocation:    { view: 'ai:invocation:view' },
    section_health:{ view: 'ai:section_health:view' },
  },
  policy: {
    rbac:  { view: 'rbac:matrix:view', edit: 'rbac:matrix:edit' },
  },
  access_request: {
    request: { list: 'access_request:request:list', resolve: 'access_request:request:resolve' },
  },
} as const;

export const PERM_ID_REGEX = /^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$/;

export const DOMAINS = [
  'rbac', 'user', 'org', 'finance', 'stage', 'tile', 'hook', 'ai', 'policy', 'access_request',
] as const;
export type Domain = typeof DOMAINS[number];
