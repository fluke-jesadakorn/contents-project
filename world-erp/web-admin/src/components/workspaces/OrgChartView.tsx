import React, { useMemo, useState } from 'react';
import {
  UserAvatar,
  roleGlyph,
  roleLabel,
  roleBadge,
  staffLevelLabel,
  staffLevelBadge,
} from '../UserAvatar';
import { DeptLevelStrip } from './DeptLevelMatrix';
import { ROLE_RANK, type DisplayRoleName } from '@/lib/roles/display';
import type { OrgNode } from '@/lib/orgScope';
import type { StaffLevel } from '@/lib/permissions';
import type { DeptRow } from './UserEditModal';

interface OrgChartViewProps {
  tree: OrgNode[];
  departments: DeptRow[];
  currentUserId: number;
  canEdit: boolean;
  onSelectUser?: (userId: number) => void;
}

const LEVEL_ORDER: StaffLevel[] = [1, 2, 3, 4, 5];

const LEVEL_META: Record<StaffLevel, {
  bg: string;
  border: string;
  text: string;
  icon: string;
}> = {
  1: { bg: 'bg-rose-500/5',    border: 'border-rose-500/30',   text: 'text-rose-200',   icon: '👑' },
  2: { bg: 'bg-purple-500/5',  border: 'border-purple-500/30', text: 'text-purple-200', icon: '🛡️' },
  3: { bg: 'bg-amber-500/5',   border: 'border-amber-500/30',  text: 'text-amber-200',  icon: '🧭' },
  4: { bg: 'bg-cyan-500/5',    border: 'border-cyan-500/30',   text: 'text-cyan-200',   icon: '👥' },
  5: { bg: 'bg-emerald-500/5', border: 'border-emerald-500/30',text: 'text-emerald-200',icon: '📋' },
};

interface NodeCardProps {
  node: OrgNode;
  isCurrentUser: boolean;
}

const NodeCard: React.FC<NodeCardProps> = ({ node, isCurrentUser }) => {
  return (
    <div
      className={[
        'inline-flex items-center gap-3 px-3 py-2.5 rounded-xl border bg-slate-950/80 backdrop-blur-sm min-w-[260px] max-w-full transition-all',
        'border-slate-700/60',
        isCurrentUser ? 'ring-2 ring-indigo-400 shadow-lg shadow-indigo-950' : '',
        !node.is_active ? 'opacity-50 grayscale' : '',
      ].join(' ')}
    >
      <UserAvatar fullname={node.fullname} role={node.role_name} level={node.level} size="sm" />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5 min-w-0">
          <span className="text-sm shrink-0" aria-hidden>{roleGlyph(node.role_name)}</span>
          <span className="text-xs font-bold text-white truncate">{node.fullname}</span>
          {!node.is_active && (
            <span className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 uppercase shrink-0">
              off
            </span>
          )}
        </div>
        <div className="flex items-center gap-1 mt-1 flex-wrap">
          <span
            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[9px] font-bold border ${roleBadge(node.role_name)}`}
            title={node.role_name}
          >
            {roleLabel(node.role_name)}
          </span>
          <span
            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[9px] font-mono border ${staffLevelBadge(node.staffLevel)}`}
            title={`Staff grade P${node.staffLevel}`}
          >
            P{node.staffLevel}
          </span>
          <span
            className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[9px] font-mono bg-slate-800 border border-slate-700 text-slate-300"
            title={`Matrix coordinate: ${node.dept_code || '(no dept)'} × P${node.staffLevel}`}
          >
            {node.dept_code || '∅'} · P{node.staffLevel}
          </span>
          <span className="text-[9px] font-mono text-slate-500">{node.employee_code}</span>
          {node.level > 0 && (
            <span className="text-[9px] font-mono text-slate-600">·L{node.level}</span>
          )}
        </div>
      </div>
    </div>
  );
};

interface SubtreeProps {
  node: OrgNode;
  currentUserId: number;
  canEdit: boolean;
  onSelectUser?: (id: number) => void;
}

const Subtree: React.FC<SubtreeProps> = ({
  node,
  currentUserId,
  canEdit,
  onSelectUser,
}) => {
  const hasChildren = node.children.length > 0;
  const childCount = node.children.length;

  return (
    <div className="flex flex-col items-center">
      <div className="flex items-center gap-2 flex-wrap justify-center">
        <NodeCard node={node} isCurrentUser={node.id === currentUserId} />
        {canEdit && onSelectUser && (
          <button
            type="button"
            onClick={() => onSelectUser(node.id)}
            className="text-[10px] font-mono px-2 py-1 rounded-lg bg-indigo-500/20 border border-indigo-500/30 text-indigo-200 hover:bg-indigo-500/30"
          >
            Edit
          </button>
        )}
        {hasChildren && (
          <span className="text-[9px] font-mono text-slate-500 px-1.5 py-0.5 rounded bg-slate-900/60 border border-slate-800">
            ↓ {childCount} report{childCount !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {hasChildren && (
        <>
          <div className="h-5 w-px bg-slate-600/70 mt-1" />
          <div className="flex relative items-start">
            {(() => {
              const n = childCount;
              const railStyle = {
                left: `${50 / n}%`,
                right: `${50 / n}%`,
              };
              return (
                <div
                  className="absolute top-0 h-px bg-slate-600/70"
                  style={railStyle}
                />
              );
            })()}
            {node.children.map((c) => (
              <div
                key={c.id}
                className="flex flex-col items-center px-3 sm:px-5 relative"
              >
                <div className="h-5 w-px bg-slate-600/70" />
                <Subtree
                  node={c}
                  currentUserId={currentUserId}
                  canEdit={canEdit}
                  onSelectUser={onSelectUser}
                />
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

function matchesFilter(node: OrgNode, q: string, showInactive: boolean): boolean {
  if (!showInactive && !node.is_active) return false;
  if (!q.trim()) return true;
  const needle = q.toLowerCase();
  return (
    (node.fullname || '').toLowerCase().includes(needle) ||
    (node.employee_code || '').toLowerCase().includes(needle) ||
    (node.dept_code || '').toLowerCase().includes(needle) ||
    (node.role_name || '').toLowerCase().includes(needle) ||
    (node.dept_name || '').toLowerCase().includes(needle)
  );
}

interface LevelBandProps {
  level: StaffLevel;
  nodes: OrgNode[];
  matchedCount: number;
  currentUserId: number;
  canEdit: boolean;
  onSelectUser?: (id: number) => void;
  departments: DeptRow[];
}

const LevelBand: React.FC<LevelBandProps> = ({
  level,
  nodes,
  matchedCount,
  currentUserId,
  canEdit,
  onSelectUser,
  departments,
}) => {
  const meta = LEVEL_META[level];
  const label = staffLevelLabel(level);

  return (
    <section
      className={`rounded-2xl border ${meta.border} ${meta.bg} p-4 sm:p-5`}
    >
      <header className="flex items-center justify-between mb-4 flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <span className={`text-base ${meta.text}`} aria-hidden>{meta.icon}</span>
          <h3 className={`text-[11px] font-mono uppercase tracking-widest font-black ${meta.text}`}>
            P{level} · {label}
          </h3>
        </div>
        <span className="text-[10px] font-mono text-slate-500">
          {matchedCount === nodes.length
            ? `${nodes.length} ${nodes.length === 1 ? 'person' : 'people'}`
            : `${matchedCount}/${nodes.length} match`}
        </span>
      </header>

      {matchedCount === 0 ? (
        <div className="text-center text-[11px] font-mono text-slate-600 py-6 border border-dashed border-slate-800 rounded-xl">
          (no one at this level matches your filter)
        </div>
      ) : (
        <div className="overflow-x-auto pb-2">
          <div className="flex flex-wrap gap-6 justify-center min-w-fit">
            {nodes.map((n) => (
              <Subtree
                key={n.id}
                node={n}
                currentUserId={currentUserId}
                canEdit={canEdit}
                onSelectUser={onSelectUser}
              />
            ))}
          </div>
        </div>
      )}

      <div className="mt-4 pt-3 border-t border-slate-800/60">
        <DeptLevelStrip
          level={level}
          levelLabel={label}
          departments={departments}
          nodes={nodes}
        />
      </div>
    </section>
  );
};

export const OrgChartView: React.FC<OrgChartViewProps> = ({
  tree,
  departments,
  currentUserId,
  canEdit,
  onSelectUser,
}) => {
  const [search, setSearch] = useState('');
  const [showInactive, setShowInactive] = useState(true);
  const filterActive = !!search.trim() || !showInactive;

  const all = useMemo(() => {
    const flat: OrgNode[] = [];
    const walk = (n: OrgNode) => {
      flat.push(n);
      n.children.forEach(walk);
    };
    tree.forEach(walk);
    return flat;
  }, [tree]);

  const matched = useMemo(
    () => all.filter((n) => matchesFilter(n, search, showInactive)),
    [all, search, showInactive]
  );

  if (all.length === 0) {
    return (
      <div className="glass-panel p-12 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-sm">
        🚧 No org chart data in your accessible scope
      </div>
    );
  }

  const byLevel: Record<StaffLevel, OrgNode[]> = { 1: [], 2: [], 3: [], 4: [], 5: [] };
  for (const n of matched) {
    const lv = (n.staffLevel as StaffLevel) ?? 5;
    if (byLevel[lv]) byLevel[lv].push(n);
  }
  for (const lv of LEVEL_ORDER) {
    byLevel[lv].sort((a, b) => {
      const ra = roleRank(a.role_name);
      const rb = roleRank(b.role_name);
      if (ra !== rb) return ra - rb;
      return (a.fullname || '').localeCompare(b.fullname || '');
    });
  }

  const totalRoots = tree.filter((r) => r.reports_to_user_id == null).length;
  const matchedTotal = matched.length;
  const activeCount = matched.filter((n) => n.is_active).length;

  return (
    <div className="space-y-3">
      <div className="glass-panel p-3 rounded-2xl border-slate-800">
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex-1 min-w-[200px] relative">
            <span
              aria-hidden
              className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500 text-xs"
            >
              🔍
            </span>
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Filter by name, code, role, or dept…"
              className="w-full bg-slate-950/80 border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white font-mono placeholder:text-slate-600"
            />
          </div>
          <label className="flex items-center gap-1.5 text-[11px] text-slate-300 shrink-0">
            <input
              type="checkbox"
              checked={showInactive}
              onChange={(e) => setShowInactive(e.target.checked)}
              className="accent-cyan-500"
            />
            <span>Show inactive</span>
          </label>
          {filterActive && (
            <button
              type="button"
              onClick={() => {
                setSearch('');
                setShowInactive(true);
              }}
              className="text-[10px] font-mono px-2 py-1 rounded-lg bg-slate-900 border border-slate-800 text-slate-300 hover:text-white shrink-0"
            >
              ✕ Clear filter
            </button>
          )}
          <div className="ml-auto text-[10px] font-mono text-slate-500 shrink-0">
            {matchedTotal}/{all.length} visible · {activeCount} active · {totalRoots} root{totalRoots !== 1 ? 's' : ''}
          </div>
        </div>
      </div>

      {matchedTotal === 0 ? (
        <div className="glass-panel p-12 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-sm">
          🚧 No users match your filter
        </div>
      ) : (
        <div className="space-y-3">
          {LEVEL_ORDER.map((lv) => {
            const nodes = byLevel[lv];
            if (nodes.length === 0 && matched.every((n) => (n.staffLevel as StaffLevel) !== lv)) {
              return null;
            }
            return (
              <LevelBand
                key={lv}
                level={lv}
                nodes={nodes}
                matchedCount={nodes.length}
                currentUserId={currentUserId}
                canEdit={canEdit}
                onSelectUser={onSelectUser}
                departments={departments}
              />
            );
          })}
        </div>
      )}
    </div>
  );
};

function roleRank(role: string): number {
  return ROLE_RANK[role as DisplayRoleName] ?? 99;
}