// Static tile types + thin re-exports.
//
// The catalog itself lives in rbac.tiles (db/rbac/0008_static_tile_catalog.sql).
// This file exists only for:
//   - TileDef / TileWithMeta type aliases (consumed by tile-config consumers)
//   - tileHref() slug parser (used in client navigation)
//   - tileFromRow() DB row → TileDef mapper (single source of truth)
//   - GROUP_LABEL / GROUP_ORDER (consumed by TileHub)
//   - targetLabel() request-target → display-name (consumed by Tile, TileHub)
//
// All access decisions go through rbac.permissions / rbac.group_permissions
// via the cascade in lib/rbac/inheritance.ts → resolved by tileAccess.ts.
// There is no TS-side role / department gating.

export type TileGroup =
  | 'hub'
  | 'workflow'
  | 'workflow-approval'
  | 'workflow-procurement'
  | 'finance'
  | 'cockpit'
  | 'policy'
  | 'it'
  | 'hr';

export interface TileAccessMeta {
  min_level: number | null;
  dept_id: string | null;
  dept_name: string | null;
  group_id: string | null;
  group_name: string | null;
  group_is_specific: boolean;
}

export interface TileDef {
  id: string;
  display_name: string;
  subtitle: string;
  icon: string;
  accent: string;
  group: TileGroup;
  sub_view: string | null;
  href: string;
  module_id: string;
  request_target: string | null;
  sort_order: number;
  requestAccessTarget?: 'hr_manager' | 'cfo' | 'admin';
}

export interface TileWithMeta extends TileDef {
  count?: number | string;
  countLabel?: string;
  access_meta?: TileAccessMeta | null;
}

export function tileHref(id: string): string {
  return '/' + id;
}

export const GROUP_LABEL: Record<TileGroup, { label: string; icon: string }> = {
  hub:                    { label: 'Hub',                    icon: '🗂️' },
  workflow:               { label: 'Workflow',               icon: '🧰' },
  'workflow-approval':    { label: 'Workflow · Approval',    icon: '✅' },
  'workflow-procurement': { label: 'Workflow · Procurement', icon: '🛒' },
  finance:                { label: 'Finance',                icon: '📒' },
  cockpit:                { label: 'Cockpit',                icon: '👑' },
  policy:                 { label: 'Policy',                 icon: '⚙️' },
  it:                     { label: 'IT',                     icon: '🛠️' },
  hr:                     { label: 'HR',                     icon: '👥' },
};

export const GROUP_ORDER: TileGroup[] = [
  'hub',
  'workflow',
  'workflow-approval',
  'workflow-procurement',
  'finance',
  'cockpit',
  'policy',
  'it',
  'hr',
];

export function targetLabel(t: { request_target?: string | null }): string {
  switch (t.request_target) {
    case 'cfo': return 'CFO';
    case 'admin': return 'Admin';
    case 'hr_manager':
    default: return 'HR Manager';
  }
}

export function requestAccessTargetToEnum(
  rt: string | null | undefined,
): 'hr_manager' | 'cfo' | 'admin' | undefined {
  if (rt === 'cfo') return 'cfo';
  if (rt === 'admin') return 'admin';
  if (rt === 'hr_manager') return 'hr_manager';
  return undefined;
}

export interface TileRow {
  id: string;
  display_name: string;
  subtitle: string;
  icon: string;
  accent: string;
  group_name: string;
  sub_view: string | null;
  href: string;
  module_id: string;
  request_target: string | null;
  sort_order: number;
  access_meta?: TileAccessMeta | null;
}

export function tileFromRow(t: TileRow): TileWithMeta {
  return {
    id: t.id,
    display_name: t.display_name,
    subtitle: t.subtitle,
    icon: t.icon,
    accent: t.accent,
    group: t.group_name as TileGroup,
    sub_view: t.sub_view,
    href: t.href,
    module_id: t.module_id,
    request_target: t.request_target,
    sort_order: t.sort_order,
    requestAccessTarget: requestAccessTargetToEnum(t.request_target),
    access_meta: t.access_meta ?? null,
  };
}