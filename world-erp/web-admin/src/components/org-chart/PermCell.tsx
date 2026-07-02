'use client';

import React from 'react';
import type { Action, ResolvedCell } from '@/lib/access/api';

interface PermCellProps {
  roleId: string;
  moduleId: string;
  cell: Record<Action, ResolvedCell>;
  optimistic: Record<Action, ResolvedCell>;
  isDirty: (action: Action) => boolean;
  isHot: boolean;
  onToggleAction: (action: Action, next: 'allow' | 'deny' | 'inherit') => void;
  onEnter: () => void;
}

const ACTIONS: Action[] = ['create', 'read', 'update', 'delete'];
const GLYPH: Record<Action, string> = {
  create: 'C',
  read: 'R',
  update: 'U',
  delete: 'D',
};
const LABEL: Record<Action, string> = {
  create: 'Create',
  read: 'Read',
  update: 'Update',
  delete: 'Delete',
};

export const PermCell: React.FC<PermCellProps> = ({
  roleId,
  moduleId,
  optimistic,
  isDirty,
  isHot,
  onToggleAction,
  onEnter,
}) => {
  const shortCode = ACTIONS.map((a) =>
    optimistic[a].state === 'allow' ? GLYPH[a] : '-',
  ).join('');

  return (
    <div
      onMouseDown={onEnter}
      className={[
        'px-1.5 py-1 text-center cursor-pointer transition-all align-top h-full',
        isHot ? 'bg-indigo-500/10' : '',
      ].join(' ')}
      title={`${roleId} × ${moduleId}`}
    >
      <div
        className={[
          'font-mono tabular-nums text-[11px] tracking-wider inline-block px-1.5 py-0.5 rounded',
          isHot
            ? 'bg-indigo-500/30 text-white'
            : 'text-slate-300',
        ].join(' ')}
      >
        {shortCode}
      </div>
      <div className="flex items-center justify-center gap-0.5 mt-1">
        {ACTIONS.map((a) => (
          <Pill
            key={a}
            action={a}
            cell={optimistic[a]}
            dirty={isDirty(a)}
            onClick={() => {
              const next = optimistic[a].state === 'allow' ? 'deny' : 'allow';
              onToggleAction(a, next);
            }}
            onContextMenu={(ev) => {
              ev.preventDefault();
              onToggleAction(a, 'inherit');
            }}
          />
        ))}
      </div>
    </div>
  );
};

const Pill: React.FC<{
  action: Action;
  cell: ResolvedCell;
  dirty: boolean;
  onClick: () => void;
  onContextMenu: (e: React.MouseEvent) => void;
}> = ({ action, cell, dirty, onClick, onContextMenu }) => {
  const allow = cell.state === 'allow';
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      onContextMenu={onContextMenu}
      title={`${LABEL[action]}: ${cell.state}${cell.inheritedFrom ? ` (from ${cell.inheritedFrom})` : ''}${
        dirty ? ' · unsaved' : ''
      } — click to toggle, right-click to set inherit`}
      className={[
        'relative w-4 h-4 rounded border text-[9px] font-mono font-black inline-flex items-center justify-center transition-all',
        allow
          ? 'bg-emerald-500/85 text-emerald-950 border-emerald-300 hover:bg-emerald-400'
          : 'bg-slate-800/40 text-slate-500 border-slate-700/50 hover:bg-slate-700/60',
        dirty ? 'ring-1 ring-amber-400 ring-offset-1 ring-offset-slate-950' : '',
      ].join(' ')}
    >
      {allow ? GLYPH[action] : '·'}
      {dirty && (
        <span className="absolute -top-0.5 -right-0.5 w-1 h-1 rounded-full bg-amber-400" />
      )}
    </button>
  );
};