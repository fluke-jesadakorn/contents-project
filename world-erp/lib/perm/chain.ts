// lib/perm/chain.ts — approval chain resolver.
//
// Stage → role_id mapping is static (see ./stages.ts); the approver for each
// stage is found by joining perm.user_roles + users WHERE dept_group_id =
// submitter.dept.
//
// (Replaces lib/rbac/chain.ts which used rbac.role_dept_assignments and
//  rbac.roles.default_staff_level.)

import 'server-only';
import { query } from '../db';
import type { StageName } from './stages';
import { STAGE_TO_ROLE, STAGE_ORDER, normalizeStage } from './stages';

export { STAGE_TO_ROLE, STAGE_TO_PERM, normalizeStage } from './stages';
export type { StageName } from './stages';
export { STAGE_ORDER } from './stages';

const OVERRIDE_ROLES = new Set(['cfo', 'ceo', 'admin']);
const CROSS_DEPT_STAGES = new Set<string>([
  // finance-standard keys
  'accounting_verification',
  'accounting_supervision',
  'accounting_authorization',
  'disbursement_authorization',
  'cfo_authorization',
  'ceo_authorization',
  // legacy aliases (during migration window)
  'accounting_review',
  'finance_review',
  'cfo_review',
  'ceo_review',
  'po_cfo',
]);
const ALREADY_APPROVED_DEPT_KEYS = new Set<string>([
  'manager_review',
  'supervisor_review',
  'dept_verification',
  'dept_authorization',
]);
const ADMIN_PERM = 'admin:system:bypass:all';

export interface ApproverCheck {
  stage: StageName;
  roleId: string;
  userId: number | null;
  approverLevel: number;
  source: 'perm_user_roles' | 'override';
}

export interface ResolverCtx {
  submitterUserId: number;
  submitterDeptId: string | null;
  submitterRoleId: string;
  submitterLevel: number;
  alreadyApproved: Set<StageName>;
}

export interface ActorCtx {
  userId: number;
  roleId: string;
  deptGroupId: string | null;
  level: number;
}

async function findApprover(
  roleId: string,
  deptGroupId: string,
): Promise<{ user_id: number | null; level: number } | null> {
  const r = await query<{ user_id: number | null; level: number }>(
    `SELECT ur.user_id,
            COALESCE(pr.level, 5) AS level
       FROM perm.user_roles ur
       LEFT JOIN perm.roles pr ON pr.id = ur.role_id
       JOIN users u ON u.id = ur.user_id
      WHERE ur.role_id = $1
        AND u.dept_group_id = $2
        AND u.is_active IS NOT FALSE
      ORDER BY pr.level ASC NULLS LAST, ur.granted_at ASC
      LIMIT 1`,
    [roleId, deptGroupId],
  );
  return r.rows[0] ?? null;
}

export const CEO_ESCALATION_THRESHOLD_THB = 200_000;

export async function resolveApprovalChain(
  ctx: ResolverCtx,
  totalAmount?: number,
): Promise<{
  chain: ApproverCheck[];
  nextStage: StageName | null;
  completed: boolean;
  injectedCeo: boolean;
}> {
  const chain: ApproverCheck[] = [];

  const hasAmount =
    typeof totalAmount === 'number' && Number.isFinite(totalAmount);

  const needCeo =
    hasAmount && (totalAmount as number) >= CEO_ESCALATION_THRESHOLD_THB;

  const skipCeo = hasAmount && !needCeo;

  const withCeo: StageName[] = needCeo
    ? STAGE_ORDER.flatMap((s) =>
        s === 'cfo_authorization' ? (['cfo_authorization', 'ceo_authorization'] as StageName[]) : [s],
      )
    : skipCeo
    ? STAGE_ORDER.filter((s) => s !== 'ceo_authorization')
    : STAGE_ORDER;

  const seen = new Set<StageName>();
  const dynamicOrder: StageName[] = [];
  for (const s of withCeo) {
    if (seen.has(s)) continue;
    seen.add(s);
    dynamicOrder.push(s);
  }

  for (const stage of dynamicOrder) {
    const roleId = STAGE_TO_ROLE[stage];
    if (!roleId) continue;

    let userId: number | null = null;
    let approverLevel = 5;
    if (ctx.submitterDeptId) {
      const assignee = await findApprover(roleId, ctx.submitterDeptId);
      userId = assignee?.user_id ?? null;
      approverLevel = assignee?.level ?? 5;
    }

    chain.push({ stage, roleId, userId, approverLevel, source: 'perm_user_roles' });
  }

  let nextStage: StageName | null = null;
  for (const c of chain) {
    if (!ctx.alreadyApproved.has(c.stage)) {
      nextStage = c.stage;
      break;
    }
  }

  return {
    chain,
    nextStage,
    completed: nextStage === null,
    injectedCeo: needCeo,
  };
}

export async function canActOnStage(
  actor: ActorCtx,
  submitter: ResolverCtx,
  stage: StageName,
  alreadyApproved: Set<StageName>,
  actorPerms?: Set<string>,
): Promise<{ allow: boolean; reason: string }> {
  const roleId = STAGE_TO_ROLE[stage];
  if (!roleId) return { allow: false, reason: `Unknown stage "${stage}"` };

  if (OVERRIDE_ROLES.has(actor.roleId)) {
    const approvedArr = Array.from(alreadyApproved) as string[];
    const deptApproved = approvedArr.some((s) => ALREADY_APPROVED_DEPT_KEYS.has(s));
    if (!deptApproved) {
      return {
        allow: false,
        reason: `${actor.roleId.toUpperCase()} override requires manager or supervisor approval first`,
      };
    }
    return { allow: true, reason: `Override by ${actor.roleId}` };
  }
  void ADMIN_PERM;

  const hasStagePerm =
    actorPerms?.has(`stage:${stage}:act:all`) === true ||
    actorPerms?.has(`stage:${stage}:act`) === true;

  if (!hasStagePerm && actor.roleId !== roleId) {
    return {
      allow: false,
      reason: `Stage "${stage}" requires role "${roleId}", actor is "${actor.roleId}"`,
    };
  }
  if (actor.roleId === roleId && !CROSS_DEPT_STAGES.has(stage)) {
    if (!actor.deptGroupId) {
      return { allow: false, reason: `Actor "${actor.roleId}" has no department binding` };
    }
    if (actor.deptGroupId !== submitter.submitterDeptId) {
      return {
        allow: false,
        reason: `Stage "${stage}" requires same department as submitter`,
      };
    }
  }
  if (actor.level > submitter.submitterLevel) {
    return {
      allow: false,
      reason: `Actor level ${actor.level} is below submitter level ${submitter.submitterLevel}`,
    };
  }
  return { allow: true, reason: hasStagePerm ? `Granted stage:${stage}:act` : 'Same-dept, sufficient tier' };
}

export async function getApprovedStages(
  entityType: 'expense' | 'pr',
  entityId: number,
): Promise<Set<StageName>> {
  const r = await query<{ stage: string }>(
    `SELECT DISTINCT stage FROM approval_transitions
       WHERE target_type = $1 AND target_id = $2
         AND stage IS NOT NULL
         AND new_status NOT IN ('rejected')`,
    [entityType, entityId],
  );
  const set = new Set<StageName>();
  for (const row of r.rows) {
    const norm = normalizeStage(row.stage);
    if (norm && STAGE_ORDER.includes(norm)) set.add(norm);
  }
  return set;
}