// World ERP — RBAC permission type aliases + staff-level display helpers.
//
// This file is the LAST remaining legacy module from the consolidation.
// Its only remaining purposes:
//   1. Re-export the RoleName / TabName / ActionName / StaffLevel type
//      unions so existing imports keep working (these are display-only;
//      permission decisions come from rbac.* tables).
//   2. Provide staffLevelAccent / staffLevelBadge / staffLevelLabel
//      display helpers, which are kept here for back-compat with the
//      dozens of UI components that import them.
//
// All actual access control lives in lib/rbac/* and the rbac.* tables.
// See lib/roles/display.ts for the consolidated display map (preferred
// going forward).
//
// NOTE: This file must NOT import from '@/lib/access/api.server' or any
// 'server-only' module, because it is consumed by Client Components
// (e.g. HomeClient.tsx, NavTabs.tsx). Server-side callers should import
// the matrix helpers directly from '@/lib/rbac/server'.

export type RoleName =
  | 'staff'
  | 'accountant'
  | 'account_officer'
  | 'account_supervisor'
  | 'accounting_manager'
  | 'supervisor'
  | 'head_of_department'
  | 'admin'
  | 'cfo'
  | 'ceo'
  | 'it'
  | 'hr'
  | 'hr_manager';

export type TabName =
  | 'workbench'
  | 'pr'
  | 'ledger'
  | 'cockpit'
  | 'policy'
  | 'settings'
  | 'hr';

export type ActionName =
  | 'submit_expense'
  | 'submit_pr'
  | 'view_own_expenses'
  | 'view_all_expenses'
  | 'review_expense'
  | 'settle_payment'
  | 'approve_expense'
  | 'reject_expense'
  | 'approve_pr'
  | 'reject_pr'
  | 'view_po'
  | 'approve_po'
  | 'reject_po'
  | 'attach_po_payslip'
  | 'semantic_search'
  | 'view_executive_report'
  | 'view_ledger'
  | 'edit_policy'
  | 'view_policy'
  | 'ceo_override'
  | 'manage_ai_providers'
  | 'manage_ai_models'
  | 'manage_ai_staff'
  | 'edit_ai_assignments'
  | 'view_ai_invocations'
  | 'view_org_chart'
  | 'view_user_directory'
  | 'create_user'
  | 'update_user'
  | 'deactivate_user'
  | 'delete_user'
  | 'auto_wire_org'
  | 'assign_role'
  | 'set_user_manager'
  | 'assign_department_head';

export type StaffLevel = 1 | 2 | 3 | 4 | 5;

import { STAFF_LEVEL_LABEL, STAFF_LEVEL_ACCENT, STAFF_LEVEL_BADGE, ROLE_LEVEL } from '@/lib/roles/display';

export function staffLevelLabel(level: number | null | undefined): string {
  if (level === 1 || level === 2 || level === 3 || level === 4 || level === 5) {
    return STAFF_LEVEL_LABEL[level];
  }
  return '—';
}

export function staffLevelAccent(level: number | null | undefined): string {
  if (level === 1 || level === 2 || level === 3 || level === 4 || level === 5) {
    return STAFF_LEVEL_ACCENT[level];
  }
  return 'from-slate-500 to-slate-700';
}

export function staffLevelBadge(level: number | null | undefined): string {
  if (level === 1 || level === 2 || level === 3 || level === 4 || level === 5) {
    return STAFF_LEVEL_BADGE[level];
  }
  return 'bg-slate-700 text-slate-300 border-slate-600';
}

export function isStaffLevel(value: unknown): value is StaffLevel {
  return value === 1 || value === 2 || value === 3 || value === 4 || value === 5;
}

export function getDefaultStaffLevel(roleName: RoleName | string | undefined): StaffLevel {
  return ROLE_LEVEL[roleName as keyof typeof ROLE_LEVEL] ?? 5;
}

export function getEffectiveStaffLevel(input: {
  staff_level?: number | null;
  role_name?: string | null;
}): StaffLevel {
  const override = input.staff_level;
  if (override === 1 || override === 2 || override === 3 || override === 4 || override === 5) {
    return override;
  }
  return getDefaultStaffLevel(input.role_name as RoleName | undefined);
}

// --- DEPRECATED sync stubs (UI hints only) -----------------------------------
// These were the legacy tab/action gates from the pre-RBAC matrix era.
// They are kept only because UI components (NavTabs, TilePage) still call
// them synchronously. Real access control is per-tile via the rbac matrix
// (lib/rbac/inheritance.ts) and server-side guards (lib/server/guard.ts).
// They now default to allow so the UI doesn't pessimistically hide tabs
// that the user can actually access.

/** @deprecated Use rbac.permissions / rbac.group_permissions cascade. */
export function canAccessTab(_roleName: RoleName | string | undefined, _tab: TabName): boolean {
  return true;
}

/** @deprecated Use rbac.permissions / rbac.group_permissions cascade. */
export function canPerformAction(_roleName: RoleName | string | undefined, _action: ActionName): boolean {
  return true;
}

/** @deprecated Use rbac.permissions / rbac.group_permissions cascade. */
export function getAllowedTabs(_roleName: RoleName | string | undefined): TabName[] {
  return ['workbench', 'pr', 'ledger', 'cockpit', 'policy', 'settings', 'hr'];
}

export function getDefaultTab(_roleName: RoleName | string | undefined): TabName {
  return 'workbench';
}

export function getRoleScope(_roleName: RoleName | string | undefined): 'self' | 'department' | 'all' {
  return 'all';
}

export function getChainStages(_roleName: RoleName | string | undefined): string[] {
  return [];
}

// --- helpers ---