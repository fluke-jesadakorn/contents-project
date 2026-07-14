'use client';

import React from 'react';
import type { DerivedUser } from '@/lib/orgTree';

export type DeptColorKey = 'emerald' | 'amber' | 'violet' | 'pink' | 'sky' | 'rose' | 'slate';

const ROLE_ACCENT_BORDER: Record<string, string> = {
  ceo:                'border-rose-500/40 bg-rose-500/10',
  cfo:                'border-purple-500/40 bg-purple-500/10',
  admin:              'border-purple-500/40 bg-purple-500/10',
  manager:            'border-amber-500/40 bg-amber-500/10',
  supervisor:         'border-amber-500/40 bg-amber-500/10',
  account_supervisor: 'border-cyan-500/40 bg-cyan-500/10',
  account_officer:    'border-cyan-500/40 bg-cyan-500/10',
  accounting_manager: 'border-cyan-500/40 bg-cyan-500/10',
  hr_manager:         'border-indigo-500/40 bg-indigo-500/10',
  hr:                 'border-indigo-500/40 bg-indigo-500/10',
  it:                 'border-slate-500/40 bg-slate-500/10',
  finance:            'border-emerald-500/40 bg-emerald-500/10',
  staff:              'border-emerald-500/40 bg-emerald-500/10',
};

function initials(fullname: string): string {
  const parts = fullname.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function buildSubtreeMap(all: DerivedUser[]): Map<number, number | null> {
  const map = new Map<number, number | null>();
  const ceo = all.find((u) => u.effective_level === 1) ?? null;
  const execCandidates = all
    .filter((u) => u.dept_id === 'executive' && u.effective_level === 2)
    .sort((a, b) => (a.persona_sort ?? 999) - (b.persona_sort ?? 999) || a.id - b.id);
  const execLevel2 = execCandidates[0] ?? null;

  const norm = (d: string | null | undefined): string | null => {
    if (d == null) return null;
    const t = String(d).trim();
    return t === '' || t === 'null' || t === 'undefined' ? null : t;
  };

  const derive = (u: DerivedUser): number | null => {
    const dept = norm(u.dept_id);
    if (u.effective_level === 1) return null;
    if (dept === 'dept-executive') {
      if (u.effective_level === 2) return ceo?.id ?? null;
      const inExec = all.filter((m) => norm(m.dept_id) === 'executive');
      const cand = inExec
        .filter((m) => m.id !== u.id && m.effective_level < u.effective_level)
        .sort((a, b) =>
          a.effective_level - b.effective_level ||
          (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
          a.id - b.id,
        );
      return cand[0]?.id ?? ceo?.id ?? null;
    }
    if (dept == null) return ceo?.id ?? null;
    const deptUsers = all.filter((m) => norm(m.dept_id) === dept);
    const sortedDept = [...deptUsers].sort((a, b) =>
      a.effective_level - b.effective_level ||
      (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
      a.id - b.id,
    );
    if (sortedDept[0]?.id === u.id) return execLevel2?.id ?? ceo?.id ?? null;
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
    return cand[0]?.id ?? execLevel2?.id ?? ceo?.id ?? null;
  };

  for (const u of all) map.set(u.id, derive(u));
  return map;
}

interface SubtreeProps {
  members: DerivedUser[];
  allUsers: DerivedUser[];
  deptColor: DeptColorKey;
  onPick: (u: DerivedUser) => void;
  selectedId: number | null;
  busyId: number | null;
  query: string;
}

function NodeRow({
  u,
  onPick,
  selected,
  busy,
}: {
  u: DerivedUser;
  onPick: (u: DerivedUser) => void;
  selected: boolean;
  busy: boolean;
}): React.JSX.Element {
  const tone = ROLE_ACCENT_BORDER[u.primary_persona] ?? ROLE_ACCENT_BORDER.staff;
  return (
    <button
      type="button"
      disabled={busy}
      onClick={() => onPick(u)}
      className={`w-full text-left rounded-lg border ${
        selected
          ? 'border-indigo-400/80 ring-2 ring-indigo-400/40'
          : `${tone} hover:scale-[1.01]`
      } px-2.5 py-1.5 transition-all active:scale-[0.98] disabled:opacity-50`}
    >
      <div className="flex items-center gap-2">
        <div className="w-6 h-6 shrink-0 rounded-full bg-slate-950/70 border border-slate-800 flex items-center justify-center text-xs font-black text-white">
          {initials(u.fullname)}
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-sm sm:text-xs font-black text-white truncate leading-tight">{u.fullname}</div>
          <div className="text-[8px] sm:text-xs font-mono text-slate-300/80 mt-0.5 truncate">{u.employee_code}</div>
        </div>
        <span className={`text-[8px] font-mono uppercase tracking-wider px-1 py-0.5 rounded shrink-0 ${tone}`}>
          P{u.effective_level}
        </span>
      </div>
    </button>
  );
}

function SubNode({
  u,
  descendants,
  onPick,
  selectedId,
  busyId,
  query,
  allById,
  parentMap,
  hideRow,
}: {
  u: DerivedUser;
  descendants: DerivedUser[];
  onPick: (u: DerivedUser) => void;
  selectedId: number | null;
  busyId: number | null;
  query: string;
  allById: Map<number, DerivedUser>;
  parentMap: Map<number, number | null>;
  hideRow?: boolean;
}): React.JSX.Element {
  const matches = (user: DerivedUser): boolean => {
    if (!query) return true;
    return [user.fullname, user.employee_code, user.primary_persona]
      .join(' ')
      .toLowerCase()
      .includes(query);
  };
  const subtreeHasMatch = (user: DerivedUser): boolean => {
    if (matches(user)) return true;
    for (const [childId, parentId] of parentMap.entries()) {
      if (parentId !== user.id) continue;
      const child = allById.get(childId);
      if (child && subtreeHasMatch(child)) return true;
    }
    return false;
  };
  const dim = query !== '' && !subtreeHasMatch(u);
  if (dim) return <></>;
  return (
    <li>
      {hideRow ? (
        <div aria-hidden="true" className="h-1 w-full" />
      ) : (
        <NodeRow u={u} onPick={onPick} selected={selectedId === u.id} busy={busyId === u.id} />
      )}
      {descendants.length > 0 && (
        <ul>
          {descendants.map((c) => (
            <SubNode
              key={c.id}
              u={c}
              descendants={getChildren(c.id, allById, parentMap)}
              onPick={onPick}
              selectedId={selectedId}
              busyId={busyId}
              query={query}
              allById={allById}
              parentMap={parentMap}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

function getChildren(id: number, allById: Map<number, DerivedUser>, parentMap: Map<number, number | null>): DerivedUser[] {
  const out: DerivedUser[] = [];
  for (const [childId, parentId] of parentMap.entries()) {
    if (parentId === id) {
      const child = allById.get(childId);
      if (child) out.push(child);
    }
  }
  return out.sort(
    (a, b) =>
      a.effective_level - b.effective_level ||
      (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
      a.fullname.localeCompare(b.fullname),
  );
}

export const NestedTree: React.FC<SubtreeProps> = ({ members, allUsers, deptColor, onPick, selectedId, busyId, query }) => {
  if (members.length === 0) return <></>;
  const allById = new Map(allUsers.map((u) => [u.id, u]));
  const parentMap = buildSubtreeMap(allUsers);
  const sortedMembers = [...members].sort(
    (a, b) =>
      a.effective_level - b.effective_level ||
      (a.persona_sort ?? 999) - (b.persona_sort ?? 999) ||
      a.fullname.localeCompare(b.fullname),
  );
  return (
    <ul className={`org-tree org-tree--${deptColor}`}>
      {sortedMembers.map((m, idx) => (
        <SubNode
          key={m.id}
          u={m}
          descendants={getChildren(m.id, allById, parentMap)}
          onPick={onPick}
          selectedId={selectedId}
          busyId={busyId}
          query={query}
          allById={allById}
          parentMap={parentMap}
          hideRow={idx === 0}
        />
      ))}
    </ul>
  );
};
