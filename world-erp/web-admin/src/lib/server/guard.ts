// Re-export from @erp-lib/server/guard (RBAC + AI guards merged).

import 'server-only';
export {
  GuardError,
  loadActor,
  requireActor,
  requireTab,
  requireAction,
  slipOwnership,
  listScope,
  aiGuardForRequest,
  type ActorWithScope,
  type RequireActionOpts,
  type RequireActionResult,
  type ScopeFilter,
  type AiGuardOk,
  type AiGuardFail,
} from '@erp-lib/server/guard';

export type { SessionActor } from '@erp-lib/server/guard';
export type { ActorScope } from '@erp-lib/server/guard';