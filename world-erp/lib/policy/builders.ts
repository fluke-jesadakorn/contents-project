import type { Policy } from './ast';

export const p = {
  perm: (perm: string): Policy => ({ kind: 'perm', perm }),
  role: (role: string | string[]): Policy => ({ kind: 'role', role }),
  levelAtMost: (n: number): Policy => ({ kind: 'levelAtMost', n }),
  levelAtLeast: (n: number): Policy => ({ kind: 'levelAtLeast', n }),
  levelAtMostColumn: (column: string): Policy => ({ kind: 'levelAtMostColumn', column }),
  dept: (mode: 'same' | 'any' | 'subtree' = 'same'): Policy => ({ kind: 'dept', mode }),
  owner: (column = 'submitter_id'): Policy => ({ kind: 'owner', column }),
  stage: (stage: string | string[]): Policy => ({ kind: 'stage', stage }),
  amountGte: (thb: number, column = 'total_amount_thb'): Policy => ({ kind: 'amountGte', thb, column }),
  amountLte: (thb: number, column = 'total_amount_thb'): Policy => ({ kind: 'amountLte', thb, column }),
  admin: (): Policy => ({ kind: 'admin' }),
  and: (...of: Policy[]): Policy => ({ kind: 'and', of }),
  or: (...of: Policy[]): Policy => ({ kind: 'or', of }),
  not: (of: Policy): Policy => ({ kind: 'not', of }),
  union: (...of: Policy[]): Policy => ({ kind: 'union', of }),
  intersect: (...of: Policy[]): Policy => ({ kind: 'intersect', of }),
  ref: (id: string): Policy => ({ kind: 'ref', id }),
};