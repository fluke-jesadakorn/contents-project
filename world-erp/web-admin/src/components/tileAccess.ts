// Tile access — pure RBAC resolution. No role-name allowlists, no
// department-string filters, no legacy tab/action fallbacks. The catalog is
// static (rbac.tiles); visibility for a given (user, tile) is determined
// entirely by the rbac.modules row referenced by the tile and the user's
// rbac_role_id walking the module_groups → role_groups → group_permissions
// cascade. See lib/rbac/inheritance.ts for the resolver.

import type { TileDef } from './tile-config';
import { access } from '@/lib/access/api';

export interface ActorLite {
  id: number;
  role_name: string;
  rbac_role_id?: string | null;
  department?: string | null;
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
  const allow = res.allow?.[tile.module_id] ?? true;
  return allow
    ? { state: 'open', reason: 'Allowed by your RBAC role.', source: res.source?.[tile.module_id] ?? 'rbac' }
    : { state: 'locked', reason: 'Restricted by your RBAC role.', source: res.source?.[tile.module_id] ?? 'rbac' };
}

const GROUP_LABEL: Record<string, string> = {
  staff: 'Staff',
  accountant: 'Accountant',
  account_officer: 'Account Officer',
  account_supervisor: 'Account Supervisor',
  accounting_manager: 'Accounting Manager',
  supervisor: 'Supervisor',
  head_of_department: 'Head of Department',
  admin: 'Executive / Admin',
  cfo: 'CFO',
  ceo: 'CEO',
  it: 'IT Staff',
  hr: 'HR Officer',
  hr_manager: 'HR Manager',
};

/** Synchronous optimistic evaluator: tile starts as `checking` until the
 * RBAC matrix refines it via `access.can()`. Same static state for everyone
 * (catalog is fixed; persona switching does not change the tile list, only
 * which tiles resolve to `open` vs `locked`). */
export function evaluateTileOptimistic(tile: TileDef, actor: ActorLite | null | undefined): TileAccess {
  return {
    state: actor ? 'checking' : 'locked',
    reason: actor ? 'Checking RBAC matrix…' : 'Sign in to view.',
  };
}

/** Async resolver. Single source of truth: rbac.modules.module_id → matrix. */
export async function evaluateTile(tile: TileDef, actor: ActorLite | null | undefined): Promise<TileAccess> {
  if (!actor?.rbac_role_id) {
    return { state: 'locked', reason: 'No RBAC role bound.' };
  }
  try {
    const cell = await access.can(actor.rbac_role_id, tile.module_id, 'read');
    if (!cell.allow) {
      return {
        state: 'locked',
        reason: 'Restricted by your RBAC role.',
        source: cell.source,
        inheritedFrom: cell.inheritedFrom,
      };
    }
    return {
      state: 'open',
      reason: 'You have access to this tile.',
      source: cell.source,
      inheritedFrom: cell.inheritedFrom,
    };
  } catch {
    return { state: 'checking', reason: 'RBAC service unavailable.' };
  }
}

/** Human label for a role name (English). */
export function roleLabel(role: keyof typeof GROUP_LABEL | string): string {
  return (GROUP_LABEL as Record<string, string>)[role] || role;
}