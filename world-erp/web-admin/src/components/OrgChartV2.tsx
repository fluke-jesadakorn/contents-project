'use client';

import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { DerivedUser } from '@/lib/orgTree';
// (reserved hook)
import { NestedTree, type DeptColorKey } from './NestedTree';

interface DeptInfo {
  key: string;
  name: string;
  color: DeptColorKey;
  head: DerivedUser;
  members: DerivedUser[];
}

interface ChainLink {
  user: DerivedUser;
  level: number;
}

const DEPT_COLORS: Record<string, DeptColorKey> = {
  'dept-executive': 'rose',
  'dept-finance-2': 'emerald',
  'dept-development': 'amber',
  'dept-marketing': 'violet',
  'dept-hr-2': 'pink',
  'dept-it': 'sky',
};

const DEFAULT_COLOR: DeptColorKey = 'slate';

const HOD_COLOR_RGB: Record<string, string> = {
  emerald: 'rgb(16 185 129 / 0.6)',
  amber:   'rgb(245 158 11 / 0.6)',
  violet:  'rgb(139 92 246 / 0.6)',
  pink:    'rgb(236 72 153 / 0.6)',
  sky:     'rgb(14 165 233 / 0.6)',
  rose:    'rgb(244 63 94 / 0.6)',
  slate:   'rgb(120 113 134 / 0.6)',
};

function deptColorFor(deptId: string | null | undefined): DeptColorKey {
  if (!deptId) return DEFAULT_COLOR;
  return DEPT_COLORS[deptId] ?? DEFAULT_COLOR;
}

function prettyDept(id: string): string {
  const map: Record<string, string> = {
    'dept-executive': 'Executive',
    'dept-finance-2': 'Finance & Account',
    'dept-development': 'Development',
    'dept-marketing': 'Marketing',
    'dept-hr-2': 'HR',
    'dept-it': 'IT',
  };
  return map[id] ?? id.replace('dept-', '').replace(/-/g, ' ');
}

function initials(fullname: string): string {
  const parts = fullname.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

const ROLE_ACCENT_BORDER: Record<string, string> = {
  ceo:                'border-rose-500/40 bg-gradient-to-br from-rose-500/20 via-rose-700/10 to-rose-900/30',
  cfo:                'border-purple-500/40 bg-gradient-to-br from-purple-500/20 via-purple-700/10 to-purple-900/30',
  admin:              'border-purple-500/40 bg-gradient-to-br from-purple-500/20 via-purple-700/10 to-purple-900/30',
  manager:            'border-amber-500/40 bg-gradient-to-br from-amber-500/20 via-amber-700/10 to-amber-900/30',
  supervisor:         'border-amber-500/40 bg-gradient-to-br from-amber-500/20 via-amber-700/10 to-amber-900/30',
  account_supervisor: 'border-cyan-500/40 bg-gradient-to-br from-cyan-500/20 via-cyan-700/10 to-cyan-900/30',
  account_officer:    'border-cyan-500/40 bg-gradient-to-br from-cyan-500/20 via-cyan-700/10 to-cyan-900/30',
  accounting_manager: 'border-cyan-500/40 bg-gradient-to-br from-cyan-500/20 via-cyan-700/10 to-cyan-900/30',
  hr_manager:         'border-indigo-500/40 bg-gradient-to-br from-indigo-500/20 via-indigo-700/10 to-indigo-900/30',
  hr:                 'border-indigo-500/40 bg-gradient-to-br from-indigo-500/20 via-indigo-700/10 to-indigo-900/30',
  it:                 'border-slate-500/40 bg-gradient-to-br from-slate-500/20 via-slate-700/10 to-slate-900/30',
  finance:            'border-emerald-500/40 bg-gradient-to-br from-emerald-500/20 via-emerald-700/10 to-emerald-900/30',
  staff:              'border-emerald-500/40 bg-gradient-to-br from-emerald-500/20 via-emerald-700/10 to-emerald-900/30',
};

function buildAnchorForest(all: DerivedUser[]): { ceo: DerivedUser | null } {
  const ceo = all.find((u) => u.effective_level === 1) ?? null;
  return { ceo };
}

function buildAnchorCLevelChain(all: DerivedUser[]): DerivedUser[] {
  const execL2 = all
    .filter((u) => u.dept_id === 'executive' && u.effective_level === 2)
    .sort((a, b) => (a.persona_sort ?? 999) - (b.persona_sort ?? 999) || a.id - b.id);
  return execL2;
}

function buildChainFor(head: DerivedUser, all: DerivedUser[]): ChainLink[] {
  const byId = new Map(all.map((u) => [u.id, u]));
  const ceo = all.find((u) => u.effective_level === 1) ?? null;
  const execL2Sorted = all
    .filter((u) => u.dept_id === 'executive' && u.effective_level === 2)
    .sort((a, b) => (a.persona_sort ?? 999) - (b.persona_sort ?? 999) || a.id - b.id);
  const findParent = (u: DerivedUser): number | null => {
    const dept = u.dept_id;
    if (u.effective_level === 1) return null;
    if (dept === 'dept-executive') {
      if (u.effective_level === 2) return ceo?.id ?? null;
      const inExec = all
        .filter((m) => m.dept_id === 'executive' && m.effective_level < u.effective_level)
        .sort((a, b) =>
          a.effective_level - b.effective_level ||
          (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
          a.id - b.id,
        );
      return inExec[0]?.id ?? ceo?.id ?? null;
    }
    if (dept == null) return ceo?.id ?? null;
    const deptUsers = all.filter((m) => m.dept_id === dept);
    const sortedDept = [...deptUsers].sort((a, b) =>
      a.effective_level - b.effective_level ||
      (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
      a.id - b.id,
    );
    if (sortedDept[0]?.id === u.id) return execL2Sorted[0]?.id ?? ceo?.id ?? null;
    const targetLevel = u.effective_level - 1;
    if (targetLevel >= 1) {
      const direct = deptUsers
        .filter((m) => m.id !== u.id && m.effective_level === targetLevel)
        .sort((a, b) =>
          a.effective_level - b.effective_level ||
          (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
          a.id - b.id,
        );
      if (direct.length > 0) return direct[0].id;
    }
    const cand = deptUsers
      .filter((m) => m.id !== u.id && m.effective_level < u.effective_level)
      .sort((a, b) =>
        a.effective_level - b.effective_level ||
        (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
        a.id - b.id,
      );
    return cand[0]?.id ?? execL2Sorted[0]?.id ?? ceo?.id ?? null;
  };

  const chain: ChainLink[] = [];
  const seen = new Set<number>();
  let cur: DerivedUser | undefined = head;
  while (cur && !seen.has(cur.id)) {
    seen.add(cur.id);
    chain.unshift({ user: cur, level: cur.effective_level });
    const parentId = findParent(cur);
    if (parentId == null || parentId === cur.id) break;
    cur = byId.get(parentId);
  }
  return chain;
}

function AnchorNodeCard({
  u,
  selected,
  busy,
  onPick,
  compact,
}: {
  u: DerivedUser;
  selected: boolean;
  busy: boolean;
  onPick: (u: DerivedUser) => void;
  compact?: boolean;
}): React.JSX.Element {
  const accent = ROLE_ACCENT_BORDER[u.primary_persona] ?? ROLE_ACCENT_BORDER.staff;
  const ring = selected
    ? 'ring-2 ring-indigo-400/80 shadow-lg shadow-indigo-500/30'
    : 'hover:scale-[1.01]';
  return (
    <button
      type="button"
      disabled={busy}
      onClick={() => onPick(u)}
      className={`group w-full text-left rounded-xl border bg-gradient-to-br ${accent} ${ring} ${
        compact ? 'p-2' : 'p-3'
      } transition-all active:scale-[0.98] disabled:opacity-50 disabled:cursor-wait`}
    >
      <div className="flex items-center gap-2.5">
        <div
          className={`${
            compact ? 'w-7 h-7 text-xs' : 'w-9 h-9 text-sm'
          } shrink-0 rounded-full bg-slate-950/70 border border-slate-800 flex items-center justify-center font-black text-white`}
        >
          {initials(u.fullname)}
        </div>
        <div className="min-w-0 flex-1">
          <div className={`${compact ? 'text-xs' : 'text-sm'} font-black text-white truncate leading-tight`}>{u.fullname}</div>
          <div className="text-xs sm:text-xs font-mono text-slate-300/80 mt-0.5 truncate">{u.employee_code}</div>
        </div>
      </div>
    </button>
  );
}

interface OrgChartV2Props {
  users: DerivedUser[];
  onPick: (u: DerivedUser) => void;
  selectedId: number | null;
  busyId: number | null;
  query: string;
}

export const OrgChartV2: React.FC<OrgChartV2Props> = ({ users, onPick, selectedId, busyId, query }) => {
  const anchor = useMemo(() => buildAnchorForest(users), [users]);
  const cLevelRing = useMemo(() => buildAnchorCLevelChain(users), [users]);

  const depts = useMemo<DeptInfo[]>(() => {
    const byDept = new Map<string, DerivedUser[]>();
    for (const u of users) {
      const key = u.dept_id ?? '__no_dept__';
      if (key === 'dept-executive' || key === '__no_dept__') continue;
      if (!byDept.has(key)) byDept.set(key, []);
      byDept.get(key)!.push(u);
    }
    const out: DeptInfo[] = [];
    for (const [key, members] of byDept.entries()) {
      const sorted = [...members].sort(
        (a, b) =>
          a.effective_level - b.effective_level ||
          (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
          a.id - b.id,
      );
      out.push({ key, name: prettyDept(key), color: deptColorFor(key), head: sorted[0], members });
    }
    out.sort((a, b) => a.head.effective_level - b.head.effective_level || a.name.localeCompare(b.name));
    return out;
  }, [users]);

  const [currentDeptId, setCurrentDeptId] = useState<string | null>(null);
  const [chainKey, setChainKey] = useState(0);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const observedRef = useRef<Set<string>>(new Set());
  const prevDeptRef = useRef<string | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    if (depts.length === 0) return;

    const cleanup = () => {
      if (observerRef.current) {
        observerRef.current.disconnect();
        observerRef.current = null;
      }
      observedRef.current.clear();
    };

    const elementsByDept: Map<string, HTMLElement> = new Map();
    const tick = () => {
      for (const dept of depts) {
        const el = document.querySelector<HTMLElement>(`[data-dept-id="${dept.key}"]`);
        if (el && !observedRef.current.has(dept.key)) {
          observedRef.current.add(dept.key);
          elementsByDept.set(dept.key, el);
        }
      }
      if (elementsByDept.size === 0) {
        setTimeout(tick, 250);
        return;
      }

      const obs = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            const deptKey = (entry.target as HTMLElement).getAttribute('data-dept-id');
            if (!deptKey) continue;
            if (entry.isIntersecting) {
              if (prevDeptRef.current !== deptKey) {
                prevDeptRef.current = deptKey;
                setChainKey((k) => k + 1);
                setCurrentDeptId(deptKey);
              }
            }
          }
        },
        { rootMargin: '-220px 0px -50% 0px', threshold: 0 },
      );
      observerRef.current = obs;
      for (const [key, el] of elementsByDept) {
        if (depts.some((d) => d.key === key)) obs.observe(el);
      }
    };

    tick();
    return cleanup;
  }, [depts]);

  const currentDept = useMemo(() => depts.find((d) => d.key === currentDeptId) ?? null, [depts, currentDeptId]);
  const currentChain = useMemo(
    () => (currentDept ? buildChainFor(currentDept.head, users) : []),
    [currentDept, users],
  );

  const chainHasCeo = currentChain.some((c) => c.level === 1);
  const chainHasCLevel = currentChain.some((c) => c.level === 2);

  const fadeInStyle: React.CSSProperties = {
    opacity: 1,
    animation: 'fadeIn 0.28s ease-out forwards',
  };
  const dimmedSlotStyle: React.CSSProperties = {
    opacity: 0.35,
    filter: 'grayscale(0.5)',
    transition: 'opacity 0.3s ease-out, filter 0.3s ease-out',
  };

  const hodColor = HOD_COLOR_RGB[currentDept?.color ?? 'slate'];

  return (
    <div className={`org-chain ${chainHasCeo ? '' : 'broken'}`}>
      <div className="org-chain-rail" style={{ ['--hod-color' as string]: hodColor }} />
      <div className="org-chain-bridge" style={{ ['--hod-color' as string]: hodColor }} />

      <div className="org-anchor -mx-4 sm:-mx-6 px-4 sm:px-6 py-3 bg-slate-950/85 backdrop-blur supports-[backdrop-filter]:bg-slate-950/65 border-b border-slate-800">
        <div className="flex items-center justify-between gap-3">
          <div className="text-xs font-mono uppercase tracking-widest text-slate-500 shrink-0">CEO</div>
          {anchor.ceo && (
            <div className="flex-1 min-w-0">
              <AnchorNodeCard u={anchor.ceo} selected={selectedId === anchor.ceo.id} busy={busyId === anchor.ceo.id} onPick={onPick} />
            </div>
          )}
          {anchor.ceo && (
            <div className="text-xs font-mono text-slate-400 shrink-0 hidden sm:block">{anchor.ceo.employee_code}</div>
          )}
        </div>
      </div>

      {cLevelRing.length > 0 && (
        <div
          className="current-clevel-slot sticky -mx-4 sm:-mx-6 px-4 sm:px-6 py-2 bg-slate-950/65 backdrop-blur border-b border-slate-800/50"
          style={chainHasCeo ? undefined : dimmedSlotStyle}
        >
          <div className="flex items-center justify-between gap-3">
            <div className="text-xs font-mono uppercase tracking-widest text-slate-500 shrink-0">
              C-LEVEL {!chainHasCeo && currentDept && <span className="text-amber-400/80 ml-1">· OUT OF SCOPE</span>}
            </div>
            <div className="flex-1 min-w-0">
              {currentChain.find((c) => c.level === 2) ? (
                <div key={`clevel-${chainKey}`} style={chainHasCeo ? fadeInStyle : dimmedSlotStyle}>
                  <AnchorNodeCard
                    u={currentChain.find((c) => c.level === 2)!.user}
                    selected={selectedId === currentChain.find((c) => c.level === 2)!.user.id}
                    busy={busyId === currentChain.find((c) => c.level === 2)!.user.id}
                    onPick={onPick}
                    compact
                  />
                </div>
              ) : cLevelRing.length > 0 ? (
                <AnchorNodeCard u={cLevelRing[0]} selected={selectedId === cLevelRing[0].id} busy={busyId === cLevelRing[0].id} onPick={onPick} compact />
              ) : (
                <span className="text-sm text-slate-500 font-mono">—</span>
              )}
            </div>
            {currentChain.find((c) => c.level === 2) && (
              <div className="text-xs font-mono text-slate-400 shrink-0 hidden sm:block">
                {currentChain.find((c) => c.level === 2)!.user.employee_code}
              </div>
            )}
          </div>
        </div>
      )}

      <div className="current-hod-slot sticky -mx-4 sm:-mx-6 px-4 sm:px-6 py-2 bg-slate-950/60 backdrop-blur border-b border-slate-800/40">
        <div className="flex items-center gap-3">
          <div className="text-xs font-mono uppercase tracking-widest text-slate-500 shrink-0">HEAD</div>
          <div className="flex-1 min-w-0">
            {currentDept ? (
              <div
                key={`hod-${chainKey}`}
                style={chainHasCeo && chainHasCLevel ? fadeInStyle : dimmedSlotStyle}
                className="flex items-center gap-2"
              >
                <span className={`text-xs font-mono uppercase tracking-wider text-${currentDept.color}-200 shrink-0`}>
                  {currentDept.name}
                </span>
                <span className="text-slate-500">·</span>
                <AnchorNodeCard
                  u={currentDept.head}
                  selected={selectedId === currentDept.head.id}
                  busy={busyId === currentDept.head.id}
                  onPick={onPick}
                  compact
                />
              </div>
            ) : (
              <span className="text-sm text-slate-500 font-mono">
                scroll into a department to see its head
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="space-y-1">
        {depts.map((dept) => {
          const isCurrent = currentDeptId === dept.key;
          return (
            <div
              key={dept.key}
              data-dept-id={dept.key}
              data-current={isCurrent ? 'true' : undefined}
            >
              <NestedTree
                members={[dept.head]}
                allUsers={users}
                deptColor={dept.color}
                onPick={onPick}
                selectedId={selectedId}
                busyId={busyId}
                query={query}
              />
            </div>
          );
        })}
        {depts.length === 0 && (
          <div className="text-center text-sm text-slate-500 py-8">No department members yet.</div>
        )}
      </div>
    </div>
  );
};
