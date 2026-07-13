import { evalPolicy } from '@erp-lib/policy';
import { buildPolicyContext } from '@erp-lib/policy/context';
import type { Policy, PolicyResource } from '@erp-lib/policy';
import { cookies } from 'next/headers';
import { verifySession } from '@erp-lib/server/sessionToken';
import type { ReactNode } from 'react';

export interface GateProps {
  policy: Policy;
  resource?: PolicyResource;
  fallback?: ReactNode;
  children: ReactNode;
}

export async function Gate({ policy, resource, fallback = null, children }: GateProps) {
  const tok = (await cookies()).get('erp_session')?.value ?? null;
  const payload = await verifySession(tok);
  const ctx = await buildPolicyContext(payload);
  if (!ctx) return <>{fallback}</>;
  const result = await evalPolicy(policy, { ...ctx, resource: { ...(ctx.resource ?? {}), ...resource } });
  return <>{result.allow ? children : fallback}</>;
}
