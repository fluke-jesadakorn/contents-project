import React from 'react';
import {
  UserAvatar,
  roleGlyph,
  roleLabel,
  roleBadge,
  staffLevelBadge,
} from '../UserAvatar';
import type { ProposedTreeNode } from '@/lib/autoWire.server';

interface AutoWireTreeNodeProps {
  node: ProposedTreeNode;
  depth?: number;
  defaultExpanded?: boolean;
}

export const AutoWireTreeNode: React.FC<AutoWireTreeNodeProps> = ({
  node,
  depth = 0,
  defaultExpanded = true,
}) => {
  const [expanded, setExpanded] = React.useState(defaultExpanded);
  const hasChildren = node.children.length > 0;
  const u = node.user;
  const isRoot = depth === 0;

  return (
    <div className="relative">
      <div className="flex items-start gap-2">
        {depth > 0 && (
          <div className="w-4 h-px bg-slate-700 mt-7 shrink-0" />
        )}
        <div className="flex flex-col items-stretch min-w-0">
          <div
            className={[
              'inline-flex items-center gap-2 px-2.5 py-1.5 rounded-lg border bg-slate-950/70 backdrop-blur-sm min-w-[220px] max-w-full transition-all',
              isRoot ? 'border-indigo-500/50 ring-1 ring-indigo-500/30' : 'border-slate-700/60',
              node.isNewWire ? 'shadow-[0_0_0_1px_rgba(34,197,94,0.4)]' : '',
            ].join(' ')}
          >
            <UserAvatar fullname={u.fullname} role={u.role_name} size="xs" />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-1.5 min-w-0">
                <span className="text-xs shrink-0" aria-hidden>{roleGlyph(u.role_name)}</span>
                <span className="text-[11px] font-bold text-white truncate">{u.fullname}</span>
                {node.isNewWire && (
                  <span className="text-[9px] font-mono px-1 py-0.5 rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 shrink-0">
                    🆕 new
                  </span>
                )}
                {!node.isNewWire && depth > 0 && (
                  <span className="text-[9px] font-mono px-1 py-0.5 rounded bg-slate-800 text-slate-500 shrink-0">
                    unchanged
                  </span>
                )}
                {isRoot && (
                  <span className="text-[9px] font-mono px-1 py-0.5 rounded bg-indigo-500/20 text-indigo-300 border border-indigo-500/40 shrink-0">
                    root
                  </span>
                )}
              </div>
              <div className="flex items-center gap-1 mt-0.5 flex-wrap">
                <span
                  className={`inline-flex items-center gap-1 px-1 py-0.5 rounded text-[9px] font-bold border ${roleBadge(u.role_name)}`}
                >
                  {roleLabel(u.role_name)}
                </span>
                <span
                  className={`inline-flex items-center gap-1 px-1 py-0.5 rounded text-[9px] font-mono border ${staffLevelBadge(u.staff_level)}`}
                >
                  P{u.staff_level}
                </span>
                {u.dept_code && (
                  <span className="text-[9px] font-mono text-slate-400">{u.dept_code}</span>
                )}
                <span className="text-[9px] font-mono text-slate-500">{u.employee_code}</span>
              </div>
            </div>
            {hasChildren && (
              <button
                type="button"
                onClick={() => setExpanded((v) => !v)}
                className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-slate-900 border border-slate-700 text-slate-300 hover:bg-slate-800 shrink-0"
                aria-label={expanded ? 'Collapse' : 'Expand'}
              >
                {expanded ? `−${node.children.length}` : `+${node.children.length}`}
              </button>
            )}
          </div>
        </div>
      </div>

      {hasChildren && expanded && (
        <div className="mt-1.5 ml-4 pl-4 relative">
          <div className="absolute left-[14px] top-0 bottom-3 w-px bg-slate-700/70" />
          <div className="space-y-2">
            {node.children.map((c) => (
              <AutoWireTreeNode
                key={c.user.id}
                node={c}
                depth={depth + 1}
                defaultExpanded={depth < 1}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
};