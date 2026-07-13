import type { Policy } from './ast';

function flatReasons(r: import('./ast').Reason[]): string {
  const lines: string[] = [];
  const walk = (rs: import('./ast').Reason[], depth: number): void => {
    for (const x of rs) {
      const indent = '  '.repeat(depth);
      const mark = x.ok ? '✓' : '✗';
      const neg = x.negated ? ' (negated)' : '';
      lines.push(`${indent}${mark} ${x.kind}${x.detail ? ` ${x.detail}` : ''}${neg}`);
      if (x.childReasons) walk(x.childReasons, depth + 1);
    }
  };
  walk(r, 0);
  return lines.join('\n');
}

export function explain(result: import('./ast').EvalResult): string {
  return flatReasons(result.reasons);
}