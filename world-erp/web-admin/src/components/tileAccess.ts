// Tile access — resolved via the perm-string system.
//
// Each tile has a `view_perm_id` column (e.g. 'tile:expense:view::allow').
// A tile is `open` iff the actor's permission list satisfies that perm string.

import type { TileDef } from './tile-config';
import { matchPerm } from '@erp-lib/perm';

export interface ActorLite {
  id: number;
  role_id?: string | null;
  permissions?: string[] | null;
}

export type TileState = 'open' | 'locked' | 'checking';

export interface TileAccess {
  state: TileState;
  reason: string;
  source?: string;
  inheritedFrom?: string | null;
}

export interface BatchAllowResult {
  allow?: Record<string, boolean>;
  source?: Record<string, string>;
  inheritedFrom?: Record<string, string | null>;
}

export function tileAccessFromBatchResult(
  tile: TileDef,
  res: BatchAllowResult,
): TileAccess {
  const allow = res.allow?.[tile.id] ?? true;
  return allow
    ? { state: 'open', reason: 'Allowed by your role.', source: res.source?.[tile.id] ?? 'perm' }
    : { state: 'locked', reason: 'Restricted by your role.', source: res.source?.[tile.id] ?? 'perm' };
}

const GROUP_LABEL: Record<string, string> = {
  staff: 'Staff',
  officer: 'Officer',
  accountant: 'Accountant',
  account_officer: 'Account Officer',
  account_supervisor: 'Account Supervisor',
  accounting_manager: 'Accounting Manager',
  supervisor: 'Supervisor',
  manager: 'Manager',
  head_of_department: 'Head of Department',
  admin: 'Executive / Admin',
  cfo: 'CFO',
  ceo: 'CEO',
  it: 'IT Staff',
  hr: 'HR Officer',
  hr_manager: 'HR Manager',
  finance: 'Finance Lead',
  sales_rep: 'Sales Rep',
  sales_supervisor: 'Sales Supervisor',
};

// Synchronous optimistic evaluator: tile is `open` if the actor's perm list
// already grants the tile's view_perm_id (passed via tile.access_meta.viewPermId).
export function evaluateTileOptimistic(
  tile: TileDef,
  actor: ActorLite | null | undefined,
): TileAccess {
  if (!actor) return { state: 'locked', reason: 'Sign in to view.' };
  const viewPerm = (tile as any).view_perm_id ?? (tile as any).access_meta?.viewPermId;
  if (!viewPerm) return { state: 'checking', reason: 'No view permission on tile.' };
  const allowed = matchPerm(actor.permissions ?? [], viewPerm);
  return allowed
    ? { state: 'open', reason: 'Allowed by your role.', source: 'perm' }
    : { state: 'locked', reason: 'Restricted by your role.', source: 'perm' };
}

// Async resolver kept for backward-compat callers — delegates to optimistic eval.
export async function evaluateTile(
  tile: TileDef,
  actor: ActorLite | null | undefined,
): Promise<TileAccess> {
  return evaluateTileOptimistic(tile, actor);
}

export function roleLabel(role: keyof typeof GROUP_LABEL | string): string {
  return (GROUP_LABEL as Record<string, string>)[role] || role;
}
