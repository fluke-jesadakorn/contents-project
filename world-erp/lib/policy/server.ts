// lib/policy/server.ts — server-side enforcement.
//
// requirePolicy(policy, ctx, opts) — throws PolicyError on deny, writes audit.
// withApiPolicy(policy, handler)    — wrap a Next.js route handler.
// withActionPolicy(policy, factory) — wrap a server action factory.

import 'server-only';
import { NextResponse } from 'next/server';
import {
  evalPolicy,
  buildPolicyContextFromHeaders,
  buildPolicyContextFromCookieValue,
  recordResult,
  type Surface,
  type PolicyContext,
  type Policy,
  type PolicyResource,
} from '../policy';

export class PolicyError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = 'PolicyError';
  }
}

export interface RequirePolicyOpts {
  surface: Surface;
  target: string;
  resource?: PolicyResource;
  policyId?: string;
}

export async function requirePolicy(
  policy: Policy,
  ctx: PolicyContext,
  opts: RequirePolicyOpts,
): Promise<void> {
  const fullCtx: PolicyContext = { ...ctx, resource: { ...(ctx.resource ?? {}), ...(opts.resource ?? {}) } };
  const result = await evalPolicy(policy, fullCtx);
  await recordResult(result, {
    actorId: fullCtx.actor.id,
    policyId: opts.policyId ?? null,
    surface: opts.surface,
    target: opts.target,
    resource: fullCtx.resource ?? {},
    reasons: result.reasons,
  });
  if (!result.allow) {
    throw new PolicyError(403, `policy denied: ${opts.target}`);
  }
}

export async function requirePolicyFromHeaders(
  policy: Policy,
  headers: Record<string, string | string[] | undefined> | Headers,
  opts: RequirePolicyOpts,
): Promise<PolicyContext> {
  const ctx = await buildPolicyContextFromHeaders(headers);
  if (!ctx) throw new PolicyError(401, 'unauthorized');
  await requirePolicy(policy, ctx, opts);
  return ctx;
}

export async function requirePolicyFromCookie(
  policy: Policy,
  cookieValue: string | null | undefined,
  opts: RequirePolicyOpts,
): Promise<PolicyContext> {
  const ctx = await buildPolicyContextFromCookieValue(cookieValue);
  if (!ctx) throw new PolicyError(401, 'unauthorized');
  await requirePolicy(policy, ctx, opts);
  return ctx;
}

export function withApiPolicy(
  policy: Policy,
  handler: (req: Request, ctx: PolicyContext) => Promise<Response>,
  target: string,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    try {
      const ctx = await buildPolicyContextFromHeaders(
        req.headers as unknown as Record<string, string | string[] | undefined>,
      );
      if (!ctx) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
      await requirePolicy(policy, ctx, { surface: 'api', target, resource: undefined });
      return await handler(req, ctx);
    } catch (err) {
      if (err instanceof PolicyError) {
        return NextResponse.json({ error: err.message }, { status: err.status });
      }
      const message = err instanceof Error ? err.message : 'internal_error';
      return NextResponse.json({ error: message }, { status: 500 });
    }
  };
}

export interface ActionResult {
  ok: boolean;
  error?: string;
  [k: string]: unknown;
}

export function withActionPolicy<TArgs, TRes extends ActionResult>(
  policy: Policy,
  target: string,
  factory: (formData: FormData, ctx: PolicyContext) => Promise<TRes>,
): (formData: FormData) => Promise<TRes> {
  return async (formData: FormData) => {
    const cookieValue = formData.get('_session') as string | null;
    const ctx = cookieValue
      ? await buildPolicyContextFromCookieValue(cookieValue)
      : await readCookieContext();
    if (!ctx) {
      return { ok: false, error: 'unauthorized' } as TRes;
    }
    try {
      await requirePolicy(policy, ctx, { surface: 'action', target });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'forbidden';
      return { ok: false, error: message } as TRes;
    }
    return factory(formData, ctx);
  };
}

async function readCookieContext(): Promise<PolicyContext | null> {
  try {
    const { cookies } = await import('next/headers');
    const v = (await cookies()).get('erp_session')?.value ?? null;
    return buildPolicyContextFromCookieValue(v);
  } catch {
    return null;
  }
}

export async function apiGuardJson(
  req: Request,
  policy: Policy,
  target: string,
): Promise<{ ctx: PolicyContext } | { response: Response }> {
  try {
    const ctx = await requirePolicyFromHeaders(policy, req.headers, { surface: 'api', target });
    return { ctx };
  } catch (err) {
    if (err instanceof PolicyError) {
      return { response: NextResponse.json({ error: err.message }, { status: err.status }) };
    }
    throw err;
  }
}