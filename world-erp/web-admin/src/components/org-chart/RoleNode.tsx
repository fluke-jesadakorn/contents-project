'use client';

import React, { useState } from 'react';
import type {
  MatrixResponse,
  ModuleRow,
  OrgResponse,
  RoleNode,
} from '@/lib/access/api';
import { PermStrip } from './PermStrip';
import type { DirtyApi } from './useDirty';
import { summarizeRow, type RowDeltaSummary } from './compare';
import {
  DndContext,
  PointerSensor,
  useSensor,
  useSensors,
  useDraggable,
  useDroppable,
  type DragEndEvent,
  type DragStartEvent,
} from '@dnd-kit/core';
import { findNode } from './treeOps';

interface RoleNodeRowProps {
  node: RoleNode;
  depth: number;
  matrix: MatrixResponse;
  modules: ModuleRow[];
  org: OrgResponse;
  dirty: DirtyApi;
  selectedRoles: Set<string>;
  isRoleHot: (id: string) => boolean;
  isCellHot: (role: string, module: string) => boolean;
  hoveredCell: { role: string; module: string } | null;
  onToggleRole: (id: string, additive: boolean) => void;
  onHoverRole: (id: string | null) => void;
  onHoverCell: (cell: { role: string; module: string } | null) => void;
  onClickCell: (cell: { role: string; module: string }) => void;
  compareRoleId: string | null;
  draggingId: string | null;
  isDescendantOfDragging: (id: string) => boolean;
  onDragStart: (id: string) => void;
  onReparent: (id: string, newParentId: string) => Promise<void>;
  parentMap: Map<string, string | null>;
}

const LEVEL_BADGE: Record<number, string> = {
  5: 'bg-rose-500/15 text-rose-200 border-rose-500/40',
  4: 'bg-purple-500/15 text-purple-200 border-purple-500/40',
  3: 'bg-amber-500/15 text-amber-200 border-amber-500/40',
  2: 'bg-cyan-500/15 text-cyan-200 border-cyan-500/40',
  1: 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40',
};

export const RoleNodeRow: React.FC<RoleNodeRowProps> = ({
  node,
  depth,
  matrix,
  modules,
  org,
  dirty,
  selectedRoles,
  isRoleHot,
  hoveredCell,
  onToggleRole,
  onHoverRole,
  onHoverCell,
  onClickCell,
  compareRoleId,
  draggingId,
  isDescendantOfDragging,
  onDragStart,
  onReparent,
}) => {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }));
  const [pending, setPending] = useState<{ movedId: string; newParentId: string } | null>(null);

  const { setNodeRef: setDropRef, isOver, active } = useDroppable({ id: `drop:${node.id}` });
  const draggingActiveId = active && String(active.id).startsWith('drag:')
    ? String(active.id).slice(5)
    : null;

  const isSelf = draggingActiveId === node.id;
  const isDescendant =
    draggingActiveId !== null &&
    draggingActiveId !== node.id &&
    isDescendantOfDragging(node.id);
  const isInvalidTarget = isOver && (isSelf || isDescendant);
  const isValidTarget = isOver && !isInvalidTarget && draggingActiveId !== null;
  const selected = selectedRoles.has(node.id);
  const hot = isRoleHot(node.id);

  const delta: RowDeltaSummary | null = compareRoleId
    ? summarizeRow(matrix, node.id, compareRoleId)
    : null;

  const handleDragEnd = (e: DragEndEvent) => {
    onDragStart('');
    if (!e.over) return;
    const overId = String(e.over.id);
    if (!overId.startsWith('drop:')) return;
    const newParentId = overId.slice(5);
    const movedId = String(e.active.id).slice(5);
    if (movedId === newParentId) return;
    if (findNode(org.roles, movedId)?.parent_id === newParentId) return;
    const candidate = findNode(org.roles, movedId);
    if (candidate && findNode(candidate.children, newParentId)) return;
    setPending({ movedId, newParentId });
  };

  const handleDragStart = (e: DragStartEvent) => {
    const id = String(e.active.id);
    if (id.startsWith('drag:')) onDragStart(id.slice(5));
  };

  return (
    <DndContext id="DndDescribedBy-0" sensors={sensors} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
      <div
        ref={setDropRef}
        className={[
          'transition-all',
          isValidTarget ? 'ring-2 ring-emerald-400/70 ring-inset' : '',
          isInvalidTarget ? 'ring-2 ring-rose-500/60 ring-inset' : '',
        ].join(' ')}
      >
        <div className="flex items-stretch border-b border-slate-800/60 transition-colors">
          <div
            className={[
              'sticky left-0 z-10 bg-slate-950/95 backdrop-blur flex items-center gap-2 py-2 pr-3 border-r border-slate-800/80 min-w-[260px] max-w-[260px]',
              selected
                ? 'bg-indigo-500/20 border-indigo-400/40'
                : hot
                  ? 'bg-indigo-500/10 border-indigo-500/30'
                  : 'hover:bg-slate-900/60',
              draggingId === node.id ? 'opacity-40' : '',
            ].join(' ')}
            style={{ paddingLeft: `${depth * 14 + 8}px` }}
            onClick={(e) => onToggleRole(node.id, e.shiftKey || e.metaKey || e.ctrlKey)}
            onMouseEnter={() => onHoverRole(node.id)}
            onMouseLeave={() => onHoverRole(null)}
          >
            <DragHandle id={node.id} onStart={() => onDragStart(node.id)} />
            <Identity node={node} delta={delta} />
          </div>
          <PermStrip
            matrix={matrix}
            modules={modules}
            roleId={node.id}
            dirty={dirty}
            isRoleHot={hot}
            onClickCell={onClickCell}
            onHoverCell={onHoverCell}
            hoveredCell={hoveredCell}
          />
        </div>
        {pending && (
          <ReparentInline
            org={org}
            pending={pending}
            onCancel={() => setPending(null)}
            onConfirm={async (m, np) => {
              await onReparent(m, np);
              setPending(null);
            }}
          />
        )}
      </div>
    </DndContext>
  );
};

const DragHandle: React.FC<{ id: string; onStart: () => void }> = ({ id, onStart }) => {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `drag:${id}`,
  });
  return (
    <button
      type="button"
      ref={setNodeRef}
      {...attributes}
      {...listeners}
      onMouseDown={onStart}
      title="Drag to reparent"
      className={[
        'w-4 h-4 grid place-items-center text-slate-500 hover:text-white cursor-grab active:cursor-grabbing touch-none shrink-0',
        isDragging ? 'opacity-30' : '',
      ].join(' ')}
      aria-label="Drag handle"
      onClick={(e) => e.stopPropagation()}
    >
      <svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor" aria-hidden>
        <circle cx="3" cy="2" r="1" /><circle cx="7" cy="2" r="1" />
        <circle cx="3" cy="5" r="1" /><circle cx="7" cy="5" r="1" />
        <circle cx="3" cy="8" r="1" /><circle cx="7" cy="8" r="1" />
      </svg>
    </button>
  );
};

const Identity: React.FC<{ node: RoleNode; delta: RowDeltaSummary | null }> = ({ node, delta }) => {
  const hasDelta = delta && delta.totalChanged > 0;
  return (
    <>
      <span className="font-mono text-[10px] font-bold uppercase tracking-wider text-slate-300">
        {node.id}
      </span>
      <span
        className={`px-1.5 py-0.5 rounded-md text-[9px] font-mono font-bold border ${LEVEL_BADGE[node.level] ?? 'bg-slate-700 text-slate-300 border-slate-600'}`}
      >
        L{node.level}
      </span>
      <span className="text-[12px] text-slate-200 truncate flex-1">
        {node.name.replace(/^[^·]+·\s*/, '')}
      </span>
      {node.is_system && (
        <span className="text-[9px] font-mono text-slate-500 uppercase tracking-wider">sys</span>
      )}
      {hasDelta && (
        <span
          className="text-[9px] font-mono font-bold text-amber-300 border border-amber-500/40 rounded px-1.5 py-0.5"
          title={`${delta.added} added · ${delta.removed} removed · ${delta.changed} changed vs compare role`}
        >
          ▲ {delta.totalChanged}
        </span>
      )}
    </>
  );
};

const ReparentInline: React.FC<{
  org: OrgResponse;
  pending: { movedId: string; newParentId: string };
  onCancel: () => void;
  onConfirm: (movedId: string, newParentId: string) => Promise<void>;
}> = ({ org, pending, onCancel, onConfirm }) => {
  const moved = findNode(org.roles, pending.movedId);
  const np = findNode(org.roles, pending.newParentId);
  return (
    <div className="sticky left-0 z-30 px-4 py-2 bg-indigo-500/15 border-b border-indigo-500/40 flex items-center gap-3 text-[11px] font-mono">
      <span className="text-indigo-200">
        Move <span className="font-bold text-white">{pending.movedId}</span> ({moved?.name}) under{' '}
        <span className="font-bold text-white">{pending.newParentId}</span> ({np?.name})?
      </span>
      <button
        type="button"
        onClick={onCancel}
        className="ml-auto px-2.5 py-1 rounded border border-slate-700 text-slate-300 hover:bg-slate-800/60"
      >
        Cancel
      </button>
      <button
        type="button"
        onClick={() => onConfirm(pending.movedId, pending.newParentId)}
        className="px-2.5 py-1 rounded border border-emerald-500/40 bg-emerald-500/15 text-emerald-200 hover:bg-emerald-500/25"
      >
        Confirm move
      </button>
    </div>
  );
};