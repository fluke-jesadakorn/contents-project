// Stage gate resolver — server-only.
//
// Maps an approval status (e.g. 'head_review') to a stage module
// (e.g. 'stage-head-review') and asks the RBAC matrix whether the actor
// can act on it.
//
// The pure-data constants (STAGE_TO_MODULE / STAGE_TO_ROLE / etc.) live in
// ./stage-types.ts so Client Components can import them without pulling
// this 'server-only' module into the client bundle.


import { isAccessAllowed } from './server';
import type { Action } from './inheritance';
import {
  STAGE_TO_MODULE,
  STAGE_TO_ROLE,
  STAGE_TO_ROLE_PO,
  APPROVER_TO_STAGE,
  type StageName,
} from './stage-types';

export {
  STAGE_TO_MODULE,
  STAGE_TO_ROLE,
  STAGE_TO_ROLE_PO,
  APPROVER_TO_STAGE,
  type StageName,
};

export interface StageAccess {
  stage: string;
  module: string | null;
  allow: boolean;
  source: string;
  stageOverridable: boolean;
}

export async function evaluateStage(
  rbacRoleId: string | null,
  stage: string,
): Promise<StageAccess> {
  const moduleId = STAGE_TO_MODULE[stage as StageName] ?? null;
  if (!rbacRoleId || !moduleId) {
    const adminOverride = await isAccessAllowed(rbacRoleId ?? 'L1', 'rbac-admin', 'update');
    return {
      stage,
      module: moduleId,
      allow: adminOverride,
      source: adminOverride ? 'admin_override' : 'default',
      stageOverridable: adminOverride,
    };
  }
  const allow = await isAccessAllowed(rbacRoleId, moduleId, 'update');
  const admin = await isAccessAllowed(rbacRoleId, 'rbac-admin', 'update');
  return {
    stage,
    module: moduleId,
    allow: allow || admin,
    source: allow ? (admin ? 'admin_override' : 'stage') : (admin ? 'admin_override' : 'default'),
    stageOverridable: admin,
  };
}

export async function batchEvaluateStages(
  rbacRoleId: string | null,
  stages: string[],
): Promise<Record<string, StageAccess>> {
  const out: Record<string, StageAccess> = {};
  await Promise.all(
    stages.map(async (s) => {
      out[s] = await evaluateStage(rbacRoleId, s);
    }),
  );
  return out;
}

export function stageToAction(_stage: string): Action {
  return 'update';
}