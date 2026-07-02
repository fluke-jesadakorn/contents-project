// Re-export from @erp-lib/server/actor.

import 'server-only';
import {
  loadActor as _loadActor,
  type ActorUser,
} from '@erp-lib/server/actor';

export type { ActorUser };

export async function getActor(): Promise<ActorUser | null> {
  return _loadActor();
}