export type Policy =
  | { kind: 'perm'; perm: string }
  | { kind: 'role'; role: string | string[] }
  | { kind: 'levelAtMost'; n: number }
  | { kind: 'levelAtLeast'; n: number }
  | { kind: 'levelAtMostColumn'; column: string }
  | { kind: 'dept'; mode: 'same' | 'any' | 'subtree' }
  | { kind: 'owner'; column: string }
  | { kind: 'stage'; stage: string | string[] }
  | { kind: 'amountGte'; thb: number; column?: string }
  | { kind: 'amountLte'; thb: number; column?: string }
  | { kind: 'admin' }
  | { kind: 'and'; of: Policy[] }
  | { kind: 'or'; of: Policy[] }
  | { kind: 'not'; of: Policy }
  | { kind: 'union'; of: Policy[] }
  | { kind: 'intersect'; of: Policy[] }
  | { kind: 'ref'; id: string };

export type ReasonKind =
  | 'perm'
  | 'role'
  | 'levelAtMost'
  | 'levelAtLeast'
  | 'levelAtMostColumn'
  | 'dept'
  | 'owner'
  | 'stage'
  | 'amountGte'
  | 'amountLte'
  | 'admin'
  | 'and'
  | 'or'
  | 'not'
  | 'union'
  | 'intersect'
  | 'ref'
  | 'short_circuit';

export interface Reason {
  kind: ReasonKind;
  ok: boolean;
  detail?: string;
  negated?: boolean;
  childReasons?: Reason[];
}

export interface PolicyResource {
  current_stage?: string;
  origin?: 'expense' | 'pr' | 'po' | 'so';
  submitter_id?: number | null;
  requester_id?: number | null;
  owner_id?: number | null;
  total_amount_thb?: number | null;
  status?: string;
  dept_group_id?: string | null;
  [k: string]: unknown;
}

export interface PolicyActor {
  id: number;
  roleName: string | null;
  level: number;
  deptGroupId: string | null;
  deptSubtreeIds: string[];
  permissions: Set<string>;
  bypassAll: boolean;
}

export interface PolicyContext {
  actor: PolicyActor;
  resource?: PolicyResource;
}

export interface EvalResult {
  allow: boolean;
  reasons: Reason[];
}