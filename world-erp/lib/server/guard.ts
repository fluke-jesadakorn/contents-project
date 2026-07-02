// Centralized server-side guard for the consolidated lib.
//
// Functions:
//   - loadActor():        reads session + returns full user row
//   - requireActor():     throws if no signed session
//   - requireAction():    actor's role + rbac matrix + optional stage check
//   - slipOwnership():    whether the actor may read a given slip key
//   - listScope():        self/department/all filter for list queries
//   - apiGuard (in @erp-lib/server/apiGuard): route-handler guard
//   - aiGuardForRequest(): deprecated — kept as a 401 stub; use apiGuard

import 'server-only';
import { query } from '../db';
import { sessionFromHeaders, verifySession, type SessionPayload } from './sessionToken';
import { isAccessAllowed, type Action as RbacAction } from '../access/api.server';
import { evaluateStage } from '../rbac/stage';
import { getActorScope, type ActorScope } from '../rbac/scope';

export interface SessionActor {
  id: number;
  employee_code: string;
  fullname: string;
  department: string | null;
  dept_group_id: string | null;
  dept_group_name: string | null;
  role_name: string;
  rbac_role_id: string | null;
}

export class GuardError extends Error {
  status: number;
  constructor(message: string, status = 403) {
    super(message);
    this.name = 'GuardError';
    this.status = status;
  }
}

export interface ActorWithScope extends SessionActor {
  isHod: boolean;
  isHr: boolean;
  isHrManager: boolean;
  isItOrAdmin: boolean;
  isCeoOrAdmin: boolean;
}

// Convert a Web Fetch Headers (or Node IncomingMessage headers) into the
// plain Record<string, string | string[] | undefined> shape our guards
// expect. Keys are lower-cased.
export function plainHeaders(headers: Headers | Record<string, string | string[] | undefined>): Record<string, string | string[] | undefined> {
  if (headers instanceof Headers) {
    const out: Record<string, string | string[] | undefined> = {};
    headers.forEach((v, k) => { out[k.toLowerCase()] = v; });
    return out;
  }
  const out: Record<string, string | string[] | undefined> = {};
  for (const [k, v] of Object.entries(headers)) out[k.toLowerCase()] = v;
  return out;
}

function enrichActor(a: SessionActor): ActorWithScope {
  const role = a.role_name;
  return {
    ...a,
    isHod: role === 'head_of_department',
    isHr: role === 'hr',
    isHrManager: role === 'hr_manager',
    isItOrAdmin: role === 'it' || role === 'admin',
    isCeoOrAdmin: role === 'ceo' || role === 'admin',
  };
}

export async function loadActor(): Promise<ActorWithScope | null> {
  const a = await loadActorRaw();
  if (!a) return null;
  return enrichActor(a);
}

export async function loadActorRaw(): Promise<SessionActor | null> {
  const payload = await currentSession();
  if (!payload) return null;

  const res = await query<SessionActor>(
    `SELECT u.id, u.employee_code, u.fullname, u.department,
            u.dept_group_id, dg.name AS dept_group_name,
            r.name AS role_name, u.rbac_role_id
     FROM users u
     JOIN roles r ON u.role_id = r.id
     LEFT JOIN rbac.groups dg ON dg.id = u.dept_group_id
     WHERE u.id = $1`,
    [payload.sub],
  );
  return res.rows[0] || null;
}

export async function requireActor(): Promise<ActorWithScope> {
  const a = await loadActor();
  if (!a) throw new GuardError('unauthorized', 401);
  return a;
}

export async function currentSession(): Promise<SessionPayload | null> {
  const token = await currentToken();
  return verifySession(token);
}

async function currentToken(): Promise<string | null> {
  try {
    const { cookies } = await import('next/headers');
    const c = await cookies();
    const cookieToken = c.get('erp_session')?.value ?? null;
    if (cookieToken) return cookieToken;
  } catch { /* not in a request context */ }
  return null;
}

export function requireTab(actor: ActorWithScope, tab: string): void {
  if (actor.role_name === 'it' || actor.role_name === 'admin') return;
  const allowed: Record<string, string[]> = {
    workbench: ['staff', 'accountant', 'account_officer', 'account_supervisor', 'accounting_manager', 'supervisor', 'head_of_department', 'cfo', 'ceo', 'hr', 'hr_manager'],
    pr:        ['staff', 'supervisor', 'head_of_department', 'accounting_manager', 'cfo', 'ceo'],
    ledger:    ['accountant', 'account_officer', 'account_supervisor', 'accounting_manager', 'cfo', 'ceo'],
    cockpit:   ['cfo', 'ceo', 'admin'],
    policy:    ['cfo', 'admin', 'accounting_manager'],
    settings:  ['admin', 'it'],
    hr:        ['hr', 'hr_manager'],
  };
  if (!allowed[tab]?.includes(actor.role_name)) {
    throw new GuardError(`role "${actor.role_name}" cannot access tab "${tab}"`, 403);
  }
}

export interface RequireActionOpts {
  rbacSection?: string;
  rbacAction?: RbacAction;
  stage?: string;
}

export interface RequireActionResult {
  allowed: boolean;
  override: boolean;
  reason?: string;
}

export async function requireAction(
  actor: ActorWithScope,
  _actionName: string,
  opts: RequireActionOpts = {},
): Promise<RequireActionResult> {
  if (opts.stage) {
    const stageAccess = await evaluateStage(actor.rbac_role_id ?? null, opts.stage);
    if (!stageAccess.allow) {
      throw new GuardError(`stage "${opts.stage}" is not allowed for role "${actor.role_name}"`, 409);
    }
    if (stageAccess.stageOverridable && stageAccess.source === 'admin_override') {
      return { allowed: true, override: true, reason: 'stage_override' };
    }
  }

  if (opts.rbacSection && opts.rbacAction) {
    if (actor.rbac_role_id) {
      const ok = await isAccessAllowed(actor.rbac_role_id, opts.rbacSection, opts.rbacAction);
      if (!ok) {
        throw new GuardError(
          `access matrix disallows ${opts.rbacAction} on ${opts.rbacSection}`,
          403,
        );
      }
    }
  }

  return { allowed: true, override: false };
}

export async function slipOwnership(key: string, actor: ActorWithScope): Promise<boolean> {
  const scope = await getActorScope(actor.rbac_role_id ?? null, actor.id);
  if (scope.kind === 'all') return true;

  const r = await query<{ uploaded_by: number | null }>(
    `SELECT uploaded_by FROM slips WHERE file_path = $1 LIMIT 1`,
    [key],
  );
  if (r.rows.length === 0) return false;
  const uploadedBy = r.rows[0].uploaded_by;
  if (!uploadedBy) return false;

  if (scope.kind === 'self') return uploadedBy === actor.id;

  if (scope.kind === 'department') {
    const u = await query<{ u_grp: string | null; a_grp: string | null; u_dept: string | null; a_dept: string | null }>(
      `SELECT
         (SELECT dept_group_id FROM users WHERE id = $1) AS u_grp,
         (SELECT dept_group_id FROM users WHERE id = $2) AS a_grp,
         (SELECT department FROM users WHERE id = $1) AS u_dept,
         (SELECT department FROM users WHERE id = $2) AS a_dept`,
      [uploadedBy, actor.id],
    );
    const row = u.rows[0];
    if (!row) return false;
    if (row.u_grp && row.a_grp && row.u_grp === row.a_grp) return true;
    return row.u_dept != null && row.u_dept === row.a_dept;
  }
  return false;
}

export interface ScopeFilter {
  kind: 'self' | 'department' | 'all';
  department?: string | null;
  userId: number;
}

export async function listScope(actor: ActorWithScope): Promise<ScopeFilter> {
  const scope = await getActorScope(actor.rbac_role_id ?? null, actor.id);
  const scopeKind: string = scope.kind;
  const narrowed: ScopeFilter['kind'] =
    scopeKind === 'subtree' || scopeKind === 'team' || scopeKind === 'deny'
      ? 'department'
      : (scopeKind === 'self' || scopeKind === 'all'
          ? scopeKind
          : 'self');
  return {
    kind: narrowed,
    department: scope.department,
    userId: actor.id,
  };
}

// --- AI guard (consolidated from ai-svc/src/lib/guard.ts) --------------------

export interface AiGuardOk {
  ok: true;
  actorId: number;
  role: string;
  rbacRoleId: string | null;
}
export interface AiGuardFail {
  ok: false;
  status: 401 | 403;
  error: string;
}
export async function aiGuardForRequest(
  _headers: Record<string, string | string[] | undefined>,
  _opts: { rbacSection?: string; rbacAction?: 'create' | 'read' | 'update' | 'delete' },
): Promise<AiGuardOk | AiGuardFail> {
  return { ok: false, status: 401, error: 'aiGuardForRequest is deprecated — use apiGuard from @erp-lib/server/apiGuard' };
}

export type { ActorScope };
