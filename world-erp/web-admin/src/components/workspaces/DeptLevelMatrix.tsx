import React from 'react';
import { UserAvatar } from '../UserAvatar';
import type { OrgNode } from '@/lib/orgScope';
import type { DeptRow } from './UserEditModal';
import type { StaffLevel } from '@/lib/permissions';

export interface MatrixCell {
  deptCode: string;
  deptName: string;
  level: StaffLevel;
  nodes: OrgNode[];
}

interface DeptLevelMatrixProps {
  departments: DeptRow[];
  nodes: OrgNode[];
  selected: MatrixCell | null;
  onSelect: (cell: MatrixCell | null) => void;
}

const LEVEL_ORDER: StaffLevel[] = [1, 2, 3, 4, 5];

const LEVEL_LABEL: Record<StaffLevel, string> = {
  1: 'Executive',
  2: 'Senior Mgmt',
  3: 'Middle Mgmt',
  4: 'Senior Staff',
  5: 'Staff',
};

const LEVEL_TINT: Record<StaffLevel, string> = {
  1: 'bg-rose-500/10 border-rose-500/30 text-rose-200',
  2: 'bg-purple-500/10 border-purple-500/30 text-purple-200',
  3: 'bg-amber-500/10 border-amber-500/30 text-amber-200',
  4: 'bg-cyan-500/10 border-cyan-500/30 text-cyan-200',
  5: 'bg-emerald-500/10 border-emerald-500/30 text-emerald-200',
};

const MAX_AVATARS_IN_CELL = 3;

interface AggregatedData {
  rows: { code: string; name: string; isNoDept: boolean; cells: Record<number, OrgNode[]>; total: number }[];
  totals: Record<number, number>;
  grandTotal: number;
}

function aggregate(nodes: OrgNode[], departments: DeptRow[]): AggregatedData {
  const byDept = new Map<string, { code: string; name: string; isNoDept: boolean; cells: Record<number, OrgNode[]>; total: number }>();

  for (const d of departments) {
    byDept.set(d.code, { code: d.code, name: d.name, isNoDept: false, cells: {}, total: 0 });
  }
  byDept.set('(no dept)', { code: '(no dept)', name: 'No Department', isNoDept: true, cells: {}, total: 0 });

  for (const n of nodes) {
    const code = n.dept_code || '(no dept)';
    let row = byDept.get(code);
    if (!row) {
      row = { code, name: n.dept_name || code, isNoDept: true, cells: {}, total: 0 };
      byDept.set(code, row);
    }
    const lv = (n.staffLevel as StaffLevel) ?? 5;
    if (!row.cells[lv]) row.cells[lv] = [];
    row.cells[lv].push(n);
    row.total++;
  }

  const rows = Array.from(byDept.values())
    .filter((r) => r.total > 0)
    .sort((a, b) => {
      if (a.isNoDept !== b.isNoDept) return a.isNoDept ? 1 : -1;
      return a.code.localeCompare(b.code);
    });

  const totals: Record<number, number> = {};
  for (const lv of LEVEL_ORDER) totals[lv] = 0;
  let grandTotal = 0;
  for (const r of rows) {
    for (const lv of LEVEL_ORDER) {
      totals[lv] += (r.cells[lv] || []).length;
    }
    grandTotal += r.total;
  }

  return { rows, totals, grandTotal };
}

interface CellButtonProps {
  deptCode: string;
  deptName: string;
  level: StaffLevel;
  cellNodes: OrgNode[];
  active: boolean;
  onClick: () => void;
}

const CellButton: React.FC<CellButtonProps> = ({
  deptCode,
  deptName: _deptName,
  level,
  cellNodes,
  active,
  onClick,
}) => {
  const count = cellNodes.length;
  const isEmpty = count === 0;

  const tooltip = isEmpty
    ? `${deptCode} × P${level} · empty`
    : `${deptCode} × P${level}\n` +
      cellNodes.map((n) => `  ${n.fullname} (${n.role_name})`).join('\n');

  return (
    <button
      type="button"
      onClick={onClick}
      title={tooltip}
      disabled={isEmpty}
      className={[
        'min-h-[64px] min-w-[88px] p-1.5 rounded-lg border text-left flex flex-col gap-1 transition-all',
        isEmpty
          ? 'bg-slate-950/30 border-slate-800/40 cursor-default'
          : 'bg-slate-900/60 border-slate-700/60 hover:border-indigo-500/60 hover:bg-slate-900 cursor-pointer',
        active ? 'ring-2 ring-indigo-400 border-indigo-400 bg-indigo-500/15 shadow-lg shadow-indigo-950' : '',
      ].join(' ')}
      aria-pressed={active}
    >
      {isEmpty ? (
        <div className="flex-1 flex items-center justify-center text-slate-600 font-mono text-sm">
          —
        </div>
      ) : (
        <>
          <div className="flex items-center -space-x-1.5">
            {cellNodes.slice(0, MAX_AVATARS_IN_CELL).map((n) => (
              <div key={n.id} className="ring-2 ring-slate-900 rounded-full">
                <UserAvatar fullname={n.fullname} role={n.role_name} size="xs" />
              </div>
            ))}
            {count > MAX_AVATARS_IN_CELL && (
              <div className="w-7 h-7 rounded-full bg-slate-800 ring-2 ring-slate-900 text-[9px] font-mono flex items-center justify-center text-slate-300">
                +{count - MAX_AVATARS_IN_CELL}
              </div>
            )}
          </div>
          <div className="flex items-center justify-between text-[9px] font-mono">
            <span className="text-slate-400">{count} {count === 1 ? 'person' : 'people'}</span>
            {active && <span className="text-indigo-300 font-bold">●</span>}
          </div>
        </>
      )}
    </button>
  );
};

export const DeptLevelMatrix: React.FC<DeptLevelMatrixProps> = ({
  departments,
  nodes,
  selected,
  onSelect,
}) => {
  const data = React.useMemo(() => aggregate(nodes, departments), [nodes, departments]);

  if (data.rows.length === 0) {
    return (
      <div className="glass-panel p-6 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-xs">
        🚧 No data for matrix
      </div>
    );
  }

  return (
    <div className="glass-panel p-4 sm:p-5 rounded-3xl border-slate-800 space-y-3">
      <header className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <span className="text-base text-indigo-300" aria-hidden>📊</span>
          <h3 className="text-[11px] font-mono uppercase tracking-widest font-black text-indigo-200">
            Dept × Level Matrix
          </h3>
        </div>
        <div className="flex items-center gap-2 text-[10px] font-mono text-slate-500">
          <span className="px-2 py-0.5 rounded bg-slate-900 border border-slate-800">
            {data.grandTotal} people
          </span>
          {selected && (
            <button
              type="button"
              onClick={() => onSelect(null)}
              className="px-2 py-0.5 rounded bg-indigo-500/20 border border-indigo-500/40 text-indigo-200 hover:bg-indigo-500/30"
            >
              ✕ Clear filter
            </button>
          )}
        </div>
      </header>

      <div className="overflow-x-auto">
        <div className="min-w-fit">
          <div
            className="grid gap-1.5"
            style={{ gridTemplateColumns: `120px repeat(${LEVEL_ORDER.length}, minmax(92px, 1fr))` }}
          >
            {/* Top-left empty cell */}
            <div />

            {/* Column headers: P1..P5 */}
            {LEVEL_ORDER.map((lv) => (
              <div
                key={`hdr-${lv}`}
                className={`px-2 py-1.5 rounded-md border text-center text-[9px] font-mono uppercase tracking-widest font-bold ${LEVEL_TINT[lv]}`}
              >
                P{lv} · {LEVEL_LABEL[lv]}
              </div>
            ))}

            {/* Rows: dept code · cells · dept totals */}
            {data.rows.map((row) => (
              <React.Fragment key={row.code}>
                <div
                  className={[
                    'px-2 py-2 rounded-lg border text-[10px] font-mono flex flex-col justify-center',
                    row.isNoDept
                      ? 'border-dashed border-slate-700 bg-slate-900/30 text-slate-400'
                      : 'border-slate-700 bg-slate-900/60 text-slate-200',
                  ].join(' ')}
                >
                  <span className="font-bold tracking-wider">{row.code}</span>
                  <span className="text-[9px] text-slate-500 truncate">{row.name}</span>
                  <span className="text-[9px] text-slate-600 mt-0.5">{row.total} total</span>
                </div>
                {LEVEL_ORDER.map((lv) => {
                  const cellNodes = row.cells[lv] || [];
                  const isActive =
                    selected !== null &&
                    selected.deptCode === row.code &&
                    selected.level === lv;
                  return (
                    <CellButton
                      key={`${row.code}-${lv}`}
                      deptCode={row.code}
                      deptName={row.name}
                      level={lv}
                      cellNodes={cellNodes}
                      active={isActive}
                      onClick={() =>
                        onSelect(
                          isActive
                            ? null
                            : { deptCode: row.code, deptName: row.name, level: lv, nodes: cellNodes },
                        )
                      }
                    />
                  );
                })}
              </React.Fragment>
            ))}

            {/* Column totals row */}
            <div className="px-2 py-2 rounded-lg border border-slate-800 bg-slate-950/60 text-[10px] font-mono text-slate-400 flex flex-col justify-center">
              <span className="font-bold tracking-wider text-slate-300">TOTAL</span>
              <span className="text-[9px] text-slate-500">all depts</span>
            </div>
            {LEVEL_ORDER.map((lv) => (
              <div
                key={`col-total-${lv}`}
                className={`px-2 py-2 rounded-lg border text-center ${LEVEL_TINT[lv]}`}
              >
                <div className="text-[9px] font-mono uppercase tracking-widest font-bold opacity-70">
                  P{lv}
                </div>
                <div className="text-base font-black">{data.totals[lv]}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="text-[10px] text-slate-500 font-mono leading-relaxed">
        Click a cell to filter the tree → non-matching nodes fade. Click again or
        use ✕ to clear.
      </div>
    </div>
  );
};

const STRIP_LEVEL_TINT: Record<StaffLevel, { border: string; text: string; muted: string }> = {
  1: { border: 'border-rose-500/40',   text: 'text-rose-200',   muted: 'border-slate-800/40 text-slate-600' },
  2: { border: 'border-purple-500/40', text: 'text-purple-200', muted: 'border-slate-800/40 text-slate-600' },
  3: { border: 'border-amber-500/40',  text: 'text-amber-200',  muted: 'border-slate-800/40 text-slate-600' },
  4: { border: 'border-cyan-500/40',   text: 'text-cyan-200',   muted: 'border-slate-800/40 text-slate-600' },
  5: { border: 'border-emerald-500/40',text: 'text-emerald-200',muted: 'border-slate-800/40 text-slate-600' },
};

interface DeptLevelStripProps {
  level: StaffLevel;
  levelLabel: string;
  departments: DeptRow[];
  nodes: OrgNode[];
}

export const DeptLevelStrip: React.FC<DeptLevelStripProps> = ({
  level,
  levelLabel,
  departments,
  nodes,
}) => {
  const tint = STRIP_LEVEL_TINT[level];

  const byDept = new Map<string, OrgNode[]>();
  for (const d of departments) byDept.set(d.code, []);
  byDept.set('(no dept)', []);
  for (const n of nodes) {
    const code = n.dept_code || '(no dept)';
    if (!byDept.has(code)) byDept.set(code, []);
    byDept.get(code)!.push(n);
  }

  const rows = Array.from(byDept.entries())
    .filter(([code]) => departments.some((d) => d.code === code) || code === '(no dept)')
    .map(([code, list]) => ({ code, list }));

  rows.sort((a, b) => a.code.localeCompare(b.code));

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <div className="text-[9px] font-mono uppercase tracking-widest text-slate-500 shrink-0 flex items-center gap-1.5 pr-1">
        <span aria-hidden>📊</span>
        <span className={tint.text}>Dept × P{level}</span>
        <span className="text-slate-600">·</span>
        <span>{levelLabel}</span>
      </div>
      {rows.map((r) => {
        const list = r.list;
        const isEmpty = list.length === 0;
        return (
          <div
            key={r.code}
            className={[
              'inline-flex items-center gap-1.5 px-2 py-1 rounded-lg border text-[10px] font-mono',
              isEmpty
                ? `${tint.muted} bg-slate-950/30`
                : `${tint.border} bg-slate-900/60 ${tint.text}`,
            ].join(' ')}
            title={isEmpty ? `${r.code} · empty` : `${r.code} · ${list.length} ${list.length === 1 ? 'person' : 'people'}`}
          >
            <span className="font-bold tracking-wider">{r.code}</span>
            {isEmpty ? (
              <span className="text-slate-600">—</span>
            ) : (
              <>
                <div className="flex items-center -space-x-1.5">
                  {list.slice(0, 3).map((n) => (
                    <div key={n.id} className="ring-2 ring-slate-900 rounded-full">
                      <UserAvatar fullname={n.fullname} role={n.role_name} size="xs" />
                    </div>
                  ))}
                  {list.length > 3 && (
                    <div className="w-5 h-5 rounded-full bg-slate-800 ring-2 ring-slate-900 text-[8px] font-mono flex items-center justify-center text-slate-300">
                      +{list.length - 3}
                    </div>
                  )}
                </div>
                <span className="text-slate-300">{list.length}</span>
              </>
            )}
          </div>
        );
      })}
    </div>
  );
};