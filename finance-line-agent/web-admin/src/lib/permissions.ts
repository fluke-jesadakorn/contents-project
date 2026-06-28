// Role-Level Permission Configuration
// Single source of truth for all role-based access control in FinAgent ERP

export type RoleName = 'staff' | 'accountant' | 'manager' | 'admin';
export type TabName = 'workbench' | 'ledger' | 'cockpit';
export type ActionName =
  | 'submit_expense'
  | 'view_own_expenses'
  | 'view_all_expenses'
  | 'review_expense'
  | 'settle_payment'
  | 'approve_expense'
  | 'reject_expense'
  | 'semantic_search'
  | 'view_executive_report'
  | 'view_ledger';

interface RolePermission {
  tabs: TabName[];
  actions: ActionName[];
  defaultTab: TabName;
  label: string;
  labelTh: string;
}

export const ROLE_PERMISSIONS: Record<RoleName, RolePermission> = {
  staff: {
    tabs: ['workbench'],
    actions: ['submit_expense', 'view_own_expenses'],
    defaultTab: 'workbench',
    label: 'Staff Requester',
    labelTh: 'พนักงานผู้เบิกจ่าย',
  },
  accountant: {
    tabs: ['workbench', 'ledger'],
    actions: [
      'view_all_expenses',
      'review_expense',
      'settle_payment',
      'semantic_search',
      'view_ledger',
    ],
    defaultTab: 'workbench',
    label: 'Auditor / Accountant',
    labelTh: 'ผู้ตรวจสอบบัญชี',
  },
  manager: {
    tabs: ['workbench', 'ledger'],
    actions: [
      'view_all_expenses',
      'approve_expense',
      'reject_expense',
      'view_ledger',
    ],
    defaultTab: 'workbench',
    label: 'Authorizing Manager',
    labelTh: 'ผู้จัดการผู้อนุมัติ',
  },
  admin: {
    tabs: ['workbench', 'ledger', 'cockpit'],
    actions: [
      'view_all_expenses',
      'approve_expense',
      'reject_expense',
      'view_executive_report',
      'view_ledger',
    ],
    defaultTab: 'cockpit',
    label: 'Executive / CFO',
    labelTh: 'ผู้บริหารระดับสูง',
  },
};

/**
 * Check if a role has access to a specific tab
 */
export function canAccessTab(role: RoleName | undefined, tab: TabName): boolean {
  if (!role) return false;
  const perms = ROLE_PERMISSIONS[role];
  return perms ? perms.tabs.includes(tab) : false;
}

/**
 * Check if a role can perform a specific action
 */
export function canPerformAction(role: RoleName | undefined, action: ActionName): boolean {
  if (!role) return false;
  const perms = ROLE_PERMISSIONS[role];
  return perms ? perms.actions.includes(action) : false;
}

/**
 * Get the default tab for a role
 */
export function getDefaultTab(role: RoleName | undefined): TabName {
  if (!role) return 'workbench';
  const perms = ROLE_PERMISSIONS[role];
  return perms ? perms.defaultTab : 'workbench';
}

/**
 * Get allowed tabs for a role
 */
export function getAllowedTabs(role: RoleName | undefined): TabName[] {
  if (!role) return ['workbench'];
  const perms = ROLE_PERMISSIONS[role];
  return perms ? perms.tabs : ['workbench'];
}

/**
 * Server-side role name mapping for assertRole in actions.ts
 * Maps action identifiers to allowed role names for server-side validation
 */
export const SERVER_ACTION_ROLES: Record<string, RoleName[]> = {
  submit_expense: ['staff'],
  review_expense: ['accountant'],
  approve_reject: ['manager', 'admin'],
  settle_payment: ['accountant'],
  view_executive_report: ['admin'],
  view_ledger: ['accountant', 'manager', 'admin'],
};
