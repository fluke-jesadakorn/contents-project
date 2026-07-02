'use client';

import React, { useEffect, useState } from 'react';
import type { Action, MatrixResponse, OrgResponse, ResolvedCell } from '@/lib/access/api';
import { findNode, pathToNode } from './treeOps';

interface DrawerProps {
  org: OrgResponse;
  matrix: MatrixResponse;
  focused: { role: string; module: string } | null;
  onClose: () => void;
}

type Tab = 'policy' | 'members' | 'audit' | 'diff';

interface AuditEvent {
  id: number;
  kind: string;
  actor: string;
  target: any;
  occurred_at: string;
}

interface Member {
  id: number;
  employee_code: string;
  fullname: string;
  department: string | null;
  dept_group_id?: string | null;
  dept_group_name?: string | null;
  role_name: string | null;
}

interface MembersResponse {
  role: { id: string; name: string };
  direct: Member[];
  inherited: Member[];
  total: number;
}

const ACTIONS: Action[] = ['create', 'read', 'update', 'delete'];
const GLYPH: Record<Action, string> = { create: 'C', read: 'R', update: 'U', delete: 'D' };

const ROLE_COLOR: Record<number, string> = {
  5: 'text-rose-300 border-rose-500/40',
  4: 'text-purple-300 border-purple-500/40',
  3: 'text-amber-300 border-amber-500/40',
  2: 'text-cyan-300 border-cyan-500/40',
  1: 'text-emerald-300 border-emerald-500/40',
};

export const Drawer: React.FC<DrawerProps> = ({ org, matrix, focused, onClose }) => {
  const [expanded, setExpanded] = useState(false);
  const [tab, setTab] = useState<Tab>('policy');

  useEffect(() => {
    setTab('policy');
  }, [focused?.role, focused?.module]);

  if (!focused) return null;
  const { role: roleId, module: moduleId } = focused;
  const role = matrix.columns.find((c) => c.id === roleId);
  const mod = matrix.modules.find((m) => m.id === moduleId);
  const cell = matrix.rows.find((r) => r.module_id === moduleId)?.cells?.[roleId];
  if (!role || !mod || !cell) return null;

  return (
    <aside
      className={[
        'glass-panel-heavy rounded-2xl border-t border-slate-800/80',
        'transition-[height] duration-200 ease-out',
        expanded ? 'h-[480px]' : 'h-[220px]',
      ].join(' ')}
    >
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-slate-800/80">
        <div className="flex items-center gap-3 min-w-0">
          <span className={`px-1.5 py-0.5 rounded-md border text-[10px] font-mono font-bold ${ROLE_COLOR[role.level] ?? ''}`}>
            {roleId}
          </span>
          <span className="text-[10px] font-mono text-slate-500">×</span>
          <span className="font-mono font-bold text-[12px] text-slate-200">{mod.display_name}</span>
          <span className="text-[10px] font-mono text-slate-500 truncate">
            {role.name} · {mod.group_name}
          </span>
        </div>

        <div className="flex items-center gap-1">
          <TabButton active={tab === 'policy'} onClick={() => setTab('policy')}>Policy</TabButton>
          <TabButton active={tab === 'members'} onClick={() => setTab('members')}>Members</TabButton>
          <TabButton active={tab === 'audit'} onClick={() => setTab('audit')}>Audit</TabButton>
          <TabButton active={tab === 'diff'} onClick={() => setTab('diff')}>Diff vs Parent</TabButton>
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className="ml-2 w-7 h-7 grid place-items-center rounded-lg text-slate-400 hover:text-white hover:bg-slate-800/60"
            aria-label={expanded ? 'Collapse' : 'Expand'}
          >
            {expanded ? '▼' : '▲'}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="w-7 h-7 grid place-items-center rounded-lg text-slate-400 hover:text-white hover:bg-slate-800/60"
            aria-label="Close"
          >
            ✕
          </button>
        </div>
      </div>

      <div className="overflow-y-auto px-4 py-3 h-[calc(100%-3rem)]">
        {tab === 'policy' && <PolicyTab cell={cell} />}
        {tab === 'members' && <MembersTab roleId={roleId} />}
        {tab === 'audit' && <AuditTab roleId={roleId} moduleId={moduleId} />}
        {tab === 'diff' && <DiffTab org={org} matrix={matrix} roleId={roleId} moduleId={moduleId} cell={cell} />}
      </div>
    </aside>
  );
};

const TabButton: React.FC<{ active: boolean; onClick: () => void; children: React.ReactNode }> = ({
  active,
  onClick,
  children,
}) => (
  <button
    type="button"
    onClick={onClick}
    className={[
      'px-2.5 py-1 rounded-md text-[10px] font-mono font-bold uppercase tracking-wider transition-colors',
      active
        ? 'bg-indigo-500/20 text-white border border-indigo-400/40'
        : 'text-slate-400 hover:text-white hover:bg-slate-800/60 border border-transparent',
    ].join(' ')}
  >
    {children}
  </button>
);

const PolicyTab: React.FC<{ cell: Record<Action, ResolvedCell> }> = ({ cell }) => (
  <div className="space-y-3">
    <div>
      <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1.5">
        Effective cell
      </div>
      <div className="grid grid-cols-4 gap-2">
        {ACTIONS.map((a) => {
          const c = cell[a];
          return (
            <div
              key={a}
              className={[
                'px-3 py-2 rounded-lg border',
                c.state === 'allow'
                  ? 'bg-emerald-500/10 border-emerald-500/40 text-emerald-200'
                  : 'bg-slate-900/60 border-slate-800 text-slate-400',
              ].join(' ')}
            >
              <div className="text-[9px] font-mono uppercase tracking-wider text-slate-500">{a}</div>
              <div className="text-sm font-black">{c.state}</div>
              <div className="text-[9px] font-mono text-slate-500 mt-0.5">
                {c.source}{c.inheritedFrom ? ` ← ${c.inheritedFrom}` : ''}
              </div>
            </div>
          );
        })}
      </div>
    </div>
    <div>
      <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1.5">Raw</div>
      <pre className="text-[10px] font-mono text-slate-300 bg-slate-950/60 border border-slate-800 rounded-lg p-2 overflow-x-auto">
        {JSON.stringify(cell, null, 2)}
      </pre>
    </div>
  </div>
);

const MembersTab: React.FC<{ roleId: string }> = ({ roleId }) => {
  const [data, setData] = useState<MembersResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetch(`/api/roles/${encodeURIComponent(roleId)}/members`)
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      })
      .then((d: MembersResponse) => {
        if (!cancelled) setData(d);
      })
      .catch((e) => {
        if (!cancelled) setError(e.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [roleId]);

  if (loading) return <Loading />;
  if (error) return <ErrorPanel message={error} />;
  if (!data) return null;

  if (data.total === 0) {
    return (
      <div className="px-3 py-6 text-center text-slate-500 text-[12px]">
        No users currently assigned to role <span className="font-mono font-bold text-slate-300">{roleId}</span>.
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4 text-[11px] font-mono">
        <span className="text-slate-400">
          <span className="text-white font-bold text-base">{data.total}</span> total
        </span>
        <span className="text-indigo-300">
          <span className="text-white font-bold text-base">{data.direct.length}</span> direct
        </span>
        <span className="text-amber-300">
          <span className="text-white font-bold text-base">{data.inherited.length}</span> inherited
        </span>
      </div>
      {data.direct.length > 0 && <MemberTable caption="Direct" rows={data.direct} />}
      {data.inherited.length > 0 && <MemberTable caption="Inherited from descendants" rows={data.inherited} />}
    </div>
  );
};

const MemberTable: React.FC<{ caption: string; rows: Member[] }> = ({ caption, rows }) => (
  <div>
    <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mb-1">{caption}</div>
    <table className="w-full text-[11px] font-mono border-separate border-spacing-0">
      <thead>
        <tr className="text-slate-500">
          <th className="text-left px-2 py-1">Code</th>
          <th className="text-left px-2 py-1">Name</th>
          <th className="text-left px-2 py-1">Dept</th>
          <th className="text-left px-2 py-1">Legacy</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((m) => (
          <tr key={m.id} className="border-t border-slate-800/60 hover:bg-slate-900/40">
            <td className="px-2 py-1.5 text-slate-400">{m.employee_code}</td>
            <td className="px-2 py-1.5 text-slate-200">{m.fullname}</td>
            <td className="px-2 py-1.5 text-slate-400">{m.dept_group_name ?? m.department ?? '—'}</td>
            <td className="px-2 py-1.5 text-slate-400">{m.role_name ?? '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

const AuditTab: React.FC<{ roleId: string; moduleId: string }> = ({ roleId, moduleId }) => {
  const [events, setEvents] = useState<AuditEvent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetch(
      `/api/audit?role_id=${encodeURIComponent(roleId)}&module_id=${encodeURIComponent(moduleId)}&limit=20`,
    )
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      })
      .then((d) => {
        if (!cancelled) setEvents(d.events ?? []);
      })
      .catch((e) => {
        if (!cancelled) setError(e.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [roleId, moduleId]);

  if (loading) return <Loading />;
  if (error) return <ErrorPanel message={error} />;
  if (!events) return null;
  if (events.length === 0) {
    return <div className="px-3 py-6 text-center text-slate-500 text-[12px]">No audit events for this cell yet.</div>;
  }
  return (
    <div className="space-y-1.5">
      {events.map((e) => (
        <div key={e.id} className="px-2.5 py-2 rounded-lg bg-slate-950/60 border border-slate-800">
          <div className="flex items-center gap-2 text-[11px] font-mono">
            <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">
              {new Date(e.occurred_at).toLocaleString()}
            </span>
            <span className="px-1.5 py-0.5 rounded bg-indigo-500/15 text-indigo-200 text-[9px] font-mono font-bold uppercase">
              {e.kind}
            </span>
            <span className="text-slate-400">by {e.actor}</span>
          </div>
          <pre className="mt-1 text-[10px] font-mono text-slate-400 whitespace-pre-wrap break-all">
            {JSON.stringify(e.target)}
          </pre>
        </div>
      ))}
    </div>
  );
};

const DiffTab: React.FC<{
  org: OrgResponse;
  matrix: MatrixResponse;
  roleId: string;
  moduleId: string;
  cell: Record<Action, ResolvedCell>;
}> = ({ org, matrix, roleId, moduleId, cell }) => {
  const role = findNode(org.roles, roleId);
  const parentId = role?.parent_id ?? null;

  if (!parentId) {
    return (
      <div className="px-3 py-6 text-center text-slate-500 text-[12px]">
        This role is a root node — there is no parent to diff against.
      </div>
    );
  }

  const parentCell = matrix.rows.find((r) => r.module_id === moduleId)?.cells?.[parentId];
  if (!parentCell) {
    return (
      <div className="px-3 py-6 text-center text-slate-500 text-[12px]">
        Parent role has no resolved cell data.
      </div>
    );
  }

  const parent = findNode(org.roles, parentId);
  const changes = ACTIONS.filter((a) => cell[a].state !== parentCell[a].state);

  return (
    <div className="space-y-3">
      <div className="text-[11px] font-mono text-slate-400">
        <span className="text-indigo-300 font-bold">{roleId}</span> · {role?.name}
        <span className="text-slate-600 mx-2">vs</span>
        <span className="text-amber-300 font-bold">{parentId}</span> · {parent?.name}
      </div>

      <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500">Per-action delta</div>
      <table className="w-full text-[11px] font-mono border-separate border-spacing-0">
        <thead>
          <tr className="text-slate-500">
            <th className="text-left px-2 py-1">Action</th>
            <th className="text-center px-2 py-1">{parentId}</th>
            <th className="text-center px-2 py-1">{roleId}</th>
            <th className="text-center px-2 py-1">Δ</th>
          </tr>
        </thead>
        <tbody>
          {ACTIONS.map((a) => {
            const p = parentCell[a].state;
            const e = cell[a].state;
            const same = p === e;
            const delta = same ? '=' : e === 'allow' ? `+${GLYPH[a]}` : `-${GLYPH[a]}`;
            return (
              <tr key={a} className="border-t border-slate-800/60">
                <td className="px-2 py-1.5 text-slate-300">{a}</td>
                <td className="px-2 py-1.5 text-center"><StatePill state={p} /></td>
                <td className="px-2 py-1.5 text-center"><StatePill state={e} /></td>
                <td className={[
                  'px-2 py-1.5 text-center font-bold',
                  same ? 'text-slate-600' : delta[0] === '+' ? 'text-emerald-300' : 'text-rose-300',
                ].join(' ')}>
                  {delta}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {changes.length === 0 ? (
        <div className="px-3 py-2 rounded-lg bg-slate-900/60 border border-slate-800 text-[11px] text-slate-400">
          ✓ This role&apos;s cell is identical to its parent&apos;s — no override.
        </div>
      ) : (
        <div className="px-3 py-2 rounded-lg bg-amber-500/10 border border-amber-500/30 text-amber-200 text-[11px]">
          {changes.length} explicit override{changes.length === 1 ? '' : 's'} on this cell.

        </div>
      )}

      <details className="text-[10px] font-mono text-slate-500">
        <summary className="cursor-pointer hover:text-slate-300">Path from root</summary>
        <div className="mt-1.5 flex flex-wrap items-center gap-1">
          {pathToNode(org.roles, roleId).map((n, i) => (
            <React.Fragment key={`${n.id}-${i}`}>
              {i > 0 && <span className="text-slate-700">›</span>}
              <span className={[
                'px-1.5 py-0.5 rounded border',
                n.id === roleId
                  ? 'bg-indigo-500/20 border-indigo-400/40 text-white font-bold'
                  : n.id === parentId
                    ? 'bg-amber-500/15 border-amber-500/40 text-amber-200'
                    : 'bg-slate-900/60 border-slate-700 text-slate-400',
              ].join(' ')}>
                {n.id}
              </span>
            </React.Fragment>
          ))}
        </div>
      </details>
    </div>
  );
};

const StatePill: React.FC<{ state: 'allow' | 'deny' }> = ({ state }) => (
  <span
    className={[
      'inline-flex items-center justify-center min-w-[44px] px-1.5 py-0.5 rounded border text-[10px] font-mono font-bold',
      state === 'allow'
        ? 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40'
        : 'bg-rose-500/10 text-rose-200 border-rose-500/40',
    ].join(' ')}
  >
    {state}
  </span>
);

const Loading: React.FC = () => (
  <div className="px-3 py-6 text-center text-slate-500 text-[12px] font-mono animate-pulse">Loading…</div>
);

const ErrorPanel: React.FC<{ message: string }> = ({ message }) => (
  <div className="px-3 py-2 rounded-lg bg-rose-500/10 border border-rose-500/30 text-rose-200 text-[11px] font-mono">
    ⚠ {message}
  </div>
);