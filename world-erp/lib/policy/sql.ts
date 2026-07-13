import type { Policy } from './ast';
import type { PolicyContext } from './ast';

export interface SqlEmitResult {
  clause: string;
  params: unknown[];
}

interface EmitOpts {
  tableAlias?: string;
  skipAuth?: boolean;
}

function col(tableAlias: string | undefined, name: string): string {
  return tableAlias ? `${tableAlias}.${name}` : name;
}

function asArray<T>(v: T | T[]): T[] {
  return Array.isArray(v) ? v : [v];
}

function compile(stage: Policy, ctx: PolicyContext, params: unknown[], opts: EmitOpts): string {
  const a = ctx.actor;
  const r = ctx.resource ?? {};
  const alias = opts.tableAlias;

  switch (stage.kind) {
    case 'admin':
      return a.bypassAll ? 'TRUE' : 'FALSE';
    case 'perm':
      return opts.skipAuth ? 'TRUE' : 'TRUE';
    case 'role': {
      const roles = asArray(stage.role);
      params.push(roles);
      return `${col(alias, 'role_id')} = ANY($${params.length}::text[])`;
    }
    case 'levelAtMost':
      params.push(stage.n);
      return `${col(alias, 'effective_level')} <= $${params.length}`;
    case 'levelAtLeast':
      params.push(stage.n);
      return `${col(alias, 'effective_level')} >= $${params.length}`;
    case 'levelAtMostColumn':
      return 'FALSE';
    case 'dept': {
      const targetDept = (r.dept_group_id ?? null) as string | null;
      if (!targetDept) return 'FALSE';
      if (stage.mode === 'same') {
        params.push(a.deptGroupId);
        return `${col(alias, 'dept_group_id')} = $${params.length}`;
      }
      params.push(a.deptSubtreeIds.length ? a.deptSubtreeIds : [null]);
      return `${col(alias, 'dept_group_id')} = ANY($${params.length}::text[])`;
    }
    case 'owner': {
      const colName = stage.column;
      params.push(a.id);
      return `${colName} = $${params.length}`;
    }
    case 'stage': {
      const wanted = asArray(stage.stage);
      const cur = (r.current_stage ?? null) as string | null;
      if (cur != null) {
        params.push(cur);
        return `${col(alias, 'current_stage')} = $${params.length}`;
      }
      params.push(wanted);
      return `${col(alias, 'current_stage')} = ANY($${params.length}::text[])`;
    }
    case 'amountGte': {
      const c = stage.column ?? 'total_amount_thb';
      params.push(stage.thb);
      return `${c} >= $${params.length}`;
    }
    case 'amountLte': {
      const c = stage.column ?? 'total_amount_thb';
      params.push(stage.thb);
      return `${c} <= $${params.length}`;
    }
    case 'and':
    case 'intersect':
      return `(${stage.of.map((s) => compile(s, ctx, params, opts)).join(' AND ')})`;
    case 'or':
    case 'union':
      return `(${stage.of.map((s) => compile(s, ctx, params, opts)).join(' OR ')})`;
    case 'not':
      return `(NOT ${compile(stage.of, ctx, params, opts)})`;
    case 'ref':
      return '(FALSE)';
    default: {
      const _x: never = stage;
      void _x;
      return 'FALSE';
    }
  }
}

export function compilePolicyToSql(
  pol: Policy,
  ctx: PolicyContext,
  opts: EmitOpts = {},
): SqlEmitResult {
  const params: unknown[] = [];
  const clause = compile(pol, ctx, params, { ...opts, skipAuth: opts.skipAuth ?? true });
  return { clause, params };
}