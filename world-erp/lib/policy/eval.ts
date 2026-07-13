import 'server-only';
import { query } from '../db';
import type { Policy, PolicyContext, EvalResult, Reason } from './ast';
import { p as bp } from './builders';
import { expenseStagePolicy, procurementStagePolicy, salesStagePolicy } from './registry';

type Registry = Record<string, Policy>;

let registry: Registry | null = null;

async function loadRegistry(): Promise<Registry> {
  if (registry) return registry;
  try {
    const { rows } = await query<{ id: string; ast: unknown }>(
      `SELECT id, ast FROM perm.policies WHERE enabled = true`,
    );
    const r: Registry = {};
    for (const row of rows) {
      r[row.id] = row.ast as Policy;
    }
    registry = r;
    return r;
  } catch {
    registry = {};
    return registry;
  }
}

export function setPolicyRegistry(r: Registry): void {
  registry = r;
}

function asArray<T>(v: T | T[]): T[] {
  return Array.isArray(v) ? v : [v];
}

function evalStage(stage: Policy, ctx: PolicyContext): EvalResult {
  const a = ctx.actor;
  const r = ctx.resource ?? {};
  const reasons: Reason[] = [];
  let allow = false;

  switch (stage.kind) {
    case 'admin':
      allow = a.bypassAll;
      reasons.push({ kind: 'admin', ok: allow });
      break;
    case 'perm': {
      const want = stage.perm;
      const permOk =
        a.bypassAll ||
        a.permissions.has(want) ||
        a.permissions.has(`${want}:all`) ||
        (want.split(':').length === 4 &&
          a.permissions.has(want.split(':').slice(0, 3).join(':')));
      allow = permOk;
      reasons.push({ kind: 'perm', ok: allow, detail: want });
      break;
    }
    case 'role': {
      const roles = asArray(stage.role);
      allow = a.roleName != null && roles.includes(a.roleName);
      reasons.push({ kind: 'role', ok: allow, detail: roles.join(',') });
      break;
    }
    case 'levelAtMost':
      allow = a.level <= stage.n;
      reasons.push({ kind: 'levelAtMost', ok: allow, detail: `<=${stage.n}` });
      break;
    case 'levelAtLeast':
      allow = a.level >= stage.n;
      reasons.push({ kind: 'levelAtLeast', ok: allow, detail: `>=${stage.n}` });
      break;
    case 'levelAtMostColumn': {
      const col = stage.column;
      const target = Number(r[col] ?? Number.POSITIVE_INFINITY);
      allow = a.level <= target;
      reasons.push({ kind: 'levelAtMostColumn', ok: allow, detail: `<=${col}` });
      break;
    }
    case 'dept': {
      const targetDept = (r.dept_group_id ?? null) as string | null;
      const mode = stage.mode;
      if (mode === 'same') {
        allow = !!targetDept && a.deptGroupId === targetDept;
      } else if (mode === 'any') {
        allow = !!targetDept && a.deptSubtreeIds.includes(targetDept);
      } else {
        allow = !!targetDept && a.deptSubtreeIds.includes(targetDept);
      }
      reasons.push({ kind: 'dept', ok: allow, detail: mode });
      break;
    }
    case 'owner': {
      const col = stage.column;
      const target = r[col] as number | null | undefined;
      allow = target != null && Number(target) === a.id;
      reasons.push({ kind: 'owner', ok: allow, detail: col });
      break;
    }
    case 'stage': {
      const wanted = asArray(stage.stage);
      const cur = (r.current_stage ?? null) as string | null;
      allow = cur != null && wanted.includes(cur);
      reasons.push({ kind: 'stage', ok: allow, detail: wanted.join(',') });
      break;
    }
    case 'amountGte': {
      const col = stage.column ?? 'total_amount_thb';
      const v = Number(r[col] ?? 0);
      allow = v >= stage.thb;
      reasons.push({ kind: 'amountGte', ok: allow, detail: `${col}>=${stage.thb}` });
      break;
    }
    case 'amountLte': {
      const col = stage.column ?? 'total_amount_thb';
      const v = Number(r[col] ?? 0);
      allow = v <= stage.thb;
      reasons.push({ kind: 'amountLte', ok: allow, detail: `${col}<=${stage.thb}` });
      break;
    }
    case 'and': {
      let ok = true;
      for (const child of stage.of) {
        const c = evalStage(child, ctx);
        reasons.push({ kind: 'and', ok: c.allow, childReasons: c.reasons });
        if (!c.allow) {
          ok = false;
          break;
        }
      }
      allow = ok;
      break;
    }
    case 'or': {
      let ok = false;
      for (const child of stage.of) {
        const c = evalStage(child, ctx);
        reasons.push({ kind: 'or', ok: c.allow, childReasons: c.reasons });
        if (c.allow) {
          ok = true;
          break;
        }
      }
      allow = ok;
      break;
    }
    case 'not': {
      const c = evalStage(stage.of, ctx);
      allow = !c.allow;
      reasons.push({ kind: 'not', ok: allow, childReasons: c.reasons, negated: true });
      break;
    }
    case 'union':
    case 'intersect': {
      const join = stage.kind === 'union' ? 'union' : 'intersect';
      const reduce = join === 'union' ? (a: boolean, b: boolean) => a || b : (a: boolean, b: boolean) => a && b;
      let ok = stage.kind === 'union' ? false : true;
      for (const child of stage.of) {
        const c = evalStage(child, ctx);
        reasons.push({ kind: join, ok: c.allow, childReasons: c.reasons });
        ok = reduce(ok, c.allow);
      }
      allow = ok;
      break;
    }
    case 'ref': {
      const reg = registry ?? {};
      const target = reg[stage.id];
      if (!target) {
        allow = false;
        reasons.push({ kind: 'ref', ok: false, detail: `unresolved:${stage.id}` });
      } else {
        const c = evalStage(target, ctx);
        allow = c.allow;
        reasons.push({ kind: 'ref', ok: allow, detail: stage.id, childReasons: c.reasons });
      }
      break;
    }
    default: {
      const _x: never = stage;
      void _x;
      allow = false;
      reasons.push({ kind: 'short_circuit', ok: false, detail: 'unknown' });
    }
  }

  return { allow, reasons };
}

export async function evalPolicy(
  pol: Policy,
  ctx: PolicyContext,
): Promise<EvalResult> {
  await loadRegistry();
  const resource = ctx.resource ?? {};
  const origin = (resource.origin ?? 'expense') as 'expense' | 'pr' | 'po' | 'so';
  const stage = resource.current_stage ?? '';
  const amount = resource.total_amount_thb ?? undefined;
  let stagePolicy: Policy;
  if (origin === 'expense') stagePolicy = expenseStagePolicy(stage, amount);
  else if (origin === 'so') stagePolicy = salesStagePolicy(stage, amount);
  else stagePolicy = procurementStagePolicy(stage, amount);
  return evalStage(stagePolicy, ctx);
}

export async function can(pol: Policy, ctx: PolicyContext): Promise<boolean> {
  const r = await evalPolicy(pol, ctx);
  return r.allow;
}

export function definePolicy(name: string, pol: Policy): { id: string; policy: Policy } {
  return { id: name, policy: pol };
}

export { bp as builders };