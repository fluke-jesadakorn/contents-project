// perm/index.ts — public surface.
//
// One named import for everything perm.*:
//   import { hasPermission, canManageResource, PERM, loadActivePermSession } from '@erp-lib/perm';
//
// Client components should import the client-safe subset only:
//   import { PERM, STAGE_TO_ROLE } from '@erp-lib/perm';
// (taxonomy + stages are pure data, no 'server-only' in their transitive deps).

export * from './schema';
export * from './session';
export { PERM, PERM_ID_REGEX, DOMAINS, type Domain } from './taxonomy';
export { STAGE_ORDER, STAGE_TO_ROLE, STAGE_TO_PERM, type StageName } from './stages';
export {
  hasPermission,
  canManageResource,
  loadPermSessionFromHeaders,
  loadPermSessionFromCookieValue,
  loadActivePermSession,
  type OwnedResource,
  type ActivePermSession,
  type DecodedPermToken,
  SESSION_COOKIE,
} from './auth';
export {
  buildAbilityFor,
  loadUserRoleIds,
  loadRoleGrants,
  createAppAbility,
  type AppAbility,
  type Actions,
  type Subjects,
} from './ability';
export {
  resolveApprovalChain,
  canActOnStage,
  getApprovedStages,
  type ApproverCheck,
  type ResolverCtx,
  type ActorCtx,
} from './chain';
export {
  getEffectiveLevel,
  getEffectiveLevels,
  type Level,
} from './level';
export {
  type PermGrant,
  type UserPerm,
  type GrantSource,
  type CreateGrantInput,
  type UpsertUserGrantsInput,
  type UpsertUserPermsInput,
  createGrant,
  revokeGrant,
  listUserGrants,
  listActiveGrantsForPerm,
  expireOverdueGrants,
  grantActingBundle,
  listActiveUserPerms,
  revokeUserPerm,
  setUserPermanentPerms,
  setUserTemporaryGrants,
} from './grants';
export {
  getActorScope,
  scopeFilter,
  assertInScope,
  type ActorScope,
  type ScopeFilter,
  type ScopeKind,
} from './scope';
export type Action = 'create' | 'read' | 'update' | 'delete';
