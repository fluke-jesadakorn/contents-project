// Inline compare deltas: when 2 roles are selected, compute the cell-level
// difference per (role, module, action) and render the changed ones.

import type { Action, MatrixResponse, ResolvedCell } from '@/lib/access/api';

export type DeltaKind = 'same' | 'added' | 'removed' | 'changed';

export interface CellDelta {
  action: Action;
  kind: DeltaKind;
  left: ResolvedCell;
  right: ResolvedCell;
}

export function diffRoles(
  matrix: MatrixResponse,
  leftId: string,
  rightId: string,
): CellDelta[] {
  const out: CellDelta[] = [];
  for (const row of matrix.rows) {
    for (const action of ['create', 'read', 'update', 'delete'] as Action[]) {
      const left = row.cells[leftId]?.[action];
      const right = row.cells[rightId]?.[action];
      if (!left || !right) continue;
      let kind: DeltaKind = 'same';
      if (left.state === right.state) {
        kind = 'same';
      } else if (left.state === 'deny' && right.state === 'allow') {
        kind = 'added';
      } else if (left.state === 'allow' && right.state === 'deny') {
        kind = 'removed';
      } else {
        kind = 'changed';
      }
      if (kind !== 'same') out.push({ action, kind, left, right });
    }
  }
  return out;
}

export interface RowDeltaSummary {
  totalChanged: number;
  added: number;
  removed: number;
  changed: number;
}

export function summarizeRow(
  matrix: MatrixResponse,
  rowRoleId: string,
  compareRoleId: string,
): RowDeltaSummary {
  const row = matrix.rows
    .map((r) => r.cells[rowRoleId])
    .filter(Boolean) as Array<Record<Action, ResolvedCell>>;
  const cmp = matrix.rows
    .map((r) => r.cells[compareRoleId])
    .filter(Boolean) as Array<Record<Action, ResolvedCell>>;
  let added = 0;
  let removed = 0;
  let changed = 0;
  for (const cell of row) {
    for (const action of ['create', 'read', 'update', 'delete'] as Action[]) {
      const a = cell[action];
      const cmpCell = cmp.find((c) => c[action]);
      const b = cmpCell ? cmpCell[action] : null;
      if (!b) continue;
      if (a.state === b.state) continue;
      if (a.state === 'allow' && b.state === 'deny') added += 1;
      else if (a.state === 'deny' && b.state === 'allow') removed += 1;
      else changed += 1;
    }
  }
  return { totalChanged: added + removed + changed, added, removed, changed };
}