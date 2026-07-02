'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Action, MatrixResponse, OrgResponse, RoleNode } from '@/lib/access/api';
import { RoleNodeRow } from './RoleNode';
import { Drawer } from './Drawer';
import { BulkModal } from './BulkModal';
import { MobileTabs, type MobilePanel } from './MobileTabs';
import { useChart } from './selection';
import { useDirty } from './useDirty';
import { findNode } from './treeOps';
import { useCan } from '@/lib/rbac/client';
import { GroupsPanel } from './GroupsPanel';

interface OrgChartProps {
  org: OrgResponse;
  matrix: MatrixResponse;
  serviceOk: boolean;
  rbacRoleId?: string | null;
}

export const OrgChart: React.FC<OrgChartProps> = ({ org, matrix, serviceOk, rbacRoleId }) => {
  const c = useChart(matrix, org);
  const parentMap = useMemo(() => {
    const m = new Map<string, string | null>();
    const walk = (n: RoleNode) => {
      m.set(n.id, n.parent_id);
      for (const ch of n.children) walk(ch);
    };
    for (const r of org.roles) walk(r);
    return m;
  }, [org.roles]);
  const dirty = useDirty(matrix, { parentMap });
  const router = useRouter();
  const [reparentError, setReparentError] = useState<string | null>(null);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [mobilePanel, setMobilePanel] = useState<MobilePanel>('chart');
  const [compareRoleId, setCompareRoleId] = useState<string | null>(null);
  const canManageGroups = useCan(rbacRoleId, 'rbac-manage-groups', 'read');

  useEffect(() => {
    if (c.sel.focusedCell) setMobilePanel('drawer');
  }, [c.sel.focusedCell]);

  useEffect(() => {
    if (!c.sel.focusedCell && mobilePanel === 'drawer') {
      setMobilePanel('chart');
    }
  }, [c.sel.focusedCell, mobilePanel]);

  const handleCommit = useCallback(async () => {
    try {
      await dirty.commit('admin', undefined);
    } catch {
      /* surfaced in banner */
    }
  }, [dirty]);

  const handleReparent = useCallback(
    async (movedId: string, newParentId: string) => {
      setReparentError(null);
      const res = await fetch(`/api/roles/${encodeURIComponent(movedId)}/reparent`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ new_parent_id: newParentId, actor: 'ui-drag' }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        const msg = body.error || `HTTP ${res.status}`;
        setReparentError(msg);
        throw new Error(msg);
      }
      router.refresh();
    },
    [router],
  );

  const handleBulkApply = useCallback(
    async (
      changes: Array<{ role_id: string; module_id: string; action: Action; state: 'allow' | 'deny' | 'inherit' }>,
    ) => {
      const res = await fetch('/api/cells', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ changes, actor: 'ui-bulk', reason: 'bulk-modal' }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `HTTP ${res.status}`);
      }
      setBulkOpen(false);
      router.refresh();
    },
    [router],
  );

  const handleExport = useCallback(
    (format: 'csv' | 'json') => {
      const roles = matrix.columns.map((c) => c.id).join(',');
      window.open(`/api/export?format=${format}&roles=${roles}`, '_blank');
    },
    [matrix.columns],
  );

  const isDescendantOfDragging = useCallback(
    (id: string): boolean => {
      if (!draggingId) return false;
      const dragged = findNode(org.roles, draggingId);
      if (!dragged) return false;
      return !!findNode(dragged.children, id);
    },
    [draggingId, org.roles],
  );

  return (
    <div className="flex flex-col gap-3 h-[calc(100vh-7rem)]">
      <TopBar
        matrix={matrix}
        org={org}
        serviceOk={serviceOk}
        dirtyCount={dirty.dirtyCount}
        isSaving={dirty.isSaving}
        canUndo={dirty.canUndo}
        lastError={dirty.lastError ?? reparentError}
        onCommit={handleCommit}
        onRevert={dirty.revert}
        onUndo={() => void dirty.undo()}
        selectionCount={c.sel.selectedRoles.size}
        onBulk={() => setBulkOpen(true)}
        compareRoleId={compareRoleId}
        onChangeCompareRoleId={setCompareRoleId}
        onExport={handleExport}
      />
      {canManageGroups && (
        <div className="hidden md:flex items-center justify-end">
          <button
            type="button"
            onClick={() => setMobilePanel(mobilePanel === 'groups' ? 'chart' : 'groups')}
            className={[
              'inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border text-[11px] font-mono font-bold uppercase tracking-wider',
              mobilePanel === 'groups'
                ? 'border-slate-700 bg-slate-900/60 text-slate-300 hover:bg-slate-800'
                : 'border-indigo-500/40 bg-indigo-500/10 text-indigo-200 hover:bg-indigo-500/20',
            ].join(' ')}
          >
            {mobilePanel === 'groups' ? '← Back to chart' : '🗂️ Groups'}
          </button>
        </div>
      )}
      <MobileTabs
        active={mobilePanel}
        onChange={setMobilePanel}
        hasFocus={!!c.sel.focusedCell}
        showGroups={!!canManageGroups}
      />
      <div
        className={[
          'glass-panel rounded-2xl border border-slate-800/80 flex flex-col flex-1 min-h-0 overflow-hidden',
          mobilePanel === 'chart' ? 'block' : 'hidden md:flex',
        ].join(' ')}
      >
        <ModuleHeader modules={matrix.modules} />
        <div className="flex-1 min-h-0 overflow-auto">
          <Branch
            nodes={org.roles}
            depth={0}
            matrix={matrix}
            modules={matrix.modules}
            org={org}
            dirty={dirty}
            selectedRoles={c.sel.selectedRoles}
            isRoleHot={c.isRoleHot}
            isCellHot={c.isCellHot}
            hoveredCell={c.sel.hoveredCell}
            onToggleRole={c.toggleRole}
            onHoverRole={c.setHoveredRole}
            onHoverCell={c.setHoveredCell}
            onClickCell={c.setFocusedCell}
            compareRoleId={compareRoleId}
            draggingId={draggingId}
            isDescendantOfDragging={isDescendantOfDragging}
            onDragStart={setDraggingId}
            onReparent={handleReparent}
            parentMap={parentMap}
          />
        </div>
        <Legend compareRoleId={compareRoleId} />
      </div>
      <div className={mobilePanel === 'drawer' ? 'block md:block' : 'hidden md:block'}>
        <Drawer
          org={org}
          matrix={matrix}
          focused={c.sel.focusedCell}
          onClose={() => c.setFocusedCell(null)}
        />
      </div>
      {mobilePanel === 'groups' && canManageGroups && (
        <GroupsPanel rbacRoleId={rbacRoleId} />
      )}
      {bulkOpen && c.sel.selectedRoles.size >= 1 && (
        <BulkModal
          matrix={matrix}
          selectedRoleIds={Array.from(c.sel.selectedRoles)}
          onCancel={() => setBulkOpen(false)}
          onConfirm={handleBulkApply}
        />
      )}
    </div>
  );
};

const Branch: React.FC<{
  nodes: RoleNode[];
  depth: number;
  matrix: MatrixResponse;
  modules: any[];
  org: OrgResponse;
  dirty: any;
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
}> = ({ nodes, depth, ...rest }) => (
  <>
    {nodes.map((n) => (
      <RoleNodeRow key={n.id} node={n} depth={depth} {...rest} />
    ))}
  </>
);

const ModuleHeader: React.FC<{ modules: { id: string; display_name: string; group_name: string }[] }> = ({
  modules,
}) => (
  <div className="sticky top-0 z-20 flex items-stretch bg-slate-950/95 backdrop-blur border-b border-slate-800/80">
    <div className="sticky left-0 z-30 bg-slate-950/95 min-w-[260px] max-w-[260px] px-3 py-2 border-r border-slate-800/80 text-[10px] font-mono uppercase tracking-wider text-slate-400">
      Modules →
    </div>
    <div className="flex flex-1 divide-x divide-slate-800/60 border-l border-slate-800/60">
      {modules.map((m) => (
        <div key={m.id} className="flex-1 min-w-[120px] px-2 py-2">
          <div className="text-[9px] font-mono text-slate-500 uppercase tracking-wider">{m.group_name}</div>
          <div className="text-[11px] font-mono font-bold text-slate-200 truncate">{m.display_name}</div>
        </div>
      ))}
    </div>
  </div>
);

const Legend: React.FC<{ compareRoleId: string | null }> = ({ compareRoleId }) => (
  <div className="flex items-center gap-3 px-3 py-2 border-t border-slate-800/80 text-[10px] font-mono text-slate-500">
    <span className="inline-flex items-center gap-1">
      <span className="w-2.5 h-2.5 rounded-sm bg-emerald-500" /> allow
    </span>
    <span className="inline-flex items-center gap-1">
      <span className="w-2.5 h-2.5 rounded-sm bg-slate-700" /> deny
    </span>
    <span className="inline-flex items-center gap-1">
      <span className="w-2.5 h-2.5 rounded-sm bg-indigo-500/40 border border-indigo-300/60" /> inherited
    </span>
    <span className="inline-flex items-center gap-1">
      <span className="w-1.5 h-1.5 rounded-full bg-amber-400" /> unsaved
    </span>
    {compareRoleId && (
      <span className="inline-flex items-center gap-1 text-amber-300">
        ▲ <span className="font-bold">▲ N</span> = deltas vs {compareRoleId}
      </span>
    )}
    <span className="ml-auto">click cell → drawer · drag handle → reparent · right-click pill → inherit</span>
  </div>
);

interface TopBarProps {
  matrix: MatrixResponse;
  org: OrgResponse;
  serviceOk: boolean;
  dirtyCount: number;
  isSaving: boolean;
  canUndo: boolean;
  lastError: string | null;
  onCommit: () => void;
  onRevert: () => void;
  onUndo: () => void;
  selectionCount: number;
  onBulk: () => void;
  compareRoleId: string | null;
  onChangeCompareRoleId: (id: string | null) => void;
  onExport: (format: 'csv' | 'json') => void;
}

const TopBar: React.FC<TopBarProps> = ({
  matrix,
  org,
  serviceOk,
  dirtyCount,
  isSaving,
  canUndo,
  lastError,
  onCommit,
  onRevert,
  onUndo,
  selectionCount,
  onBulk,
  compareRoleId,
  onChangeCompareRoleId,
  onExport,
}) => {
  const rootCount = org.roles.length;
  const roleCount = matrix.columns.length;
  const moduleCount = matrix.modules.length;
  return (
    <div className="glass-panel rounded-2xl px-4 py-3 flex items-center justify-between flex-wrap gap-2">
      <div className="flex items-center gap-3 min-w-0 flex-wrap">
        <h1 className="text-base font-black text-white tracking-tight">
          <span className="mr-2" aria-hidden>📊</span>Org Chart
        </h1>
        <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider hidden sm:inline">
          {rootCount} root · {roleCount} roles · {moduleCount} modules
        </span>
        <span
          className={[
            'inline-flex items-center gap-1.5 px-2 py-1 rounded-md text-[10px] font-mono uppercase tracking-wider border',
            serviceOk
              ? 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40'
              : 'bg-rose-500/15 text-rose-200 border-rose-500/40',
          ].join(' ')}
        >
          <span className={`w-1.5 h-1.5 rounded-full ${serviceOk ? 'bg-emerald-400' : 'bg-rose-400'}`} />
          {serviceOk ? 'access service: live' : 'access service: down'}
        </span>
      </div>

      <div className="flex items-center gap-2 flex-wrap">
        <div className="inline-flex items-center gap-1 px-1 py-0.5 rounded-lg bg-slate-900/60 border border-slate-800">
          <span className="text-[9px] font-mono uppercase text-slate-500 px-1">compare</span>
          <select
            value={compareRoleId ?? ''}
            onChange={(e) => onChangeCompareRoleId(e.target.value || null)}
            className="bg-transparent text-[11px] font-mono font-bold text-indigo-200 px-1 py-0.5 outline-none"
          >
            <option value="" className="bg-slate-900">— off —</option>
            {matrix.columns.map((c) => (
              <option key={c.id} value={c.id} className="bg-slate-900">{c.id}</option>
            ))}
          </select>
        </div>

        <div className="inline-flex rounded-md overflow-hidden border border-slate-700">
          <button
            type="button"
            onClick={() => onExport('csv')}
            className="px-2 py-1.5 bg-slate-900/60 text-slate-300 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-slate-800 border-r border-slate-700"
          >
            CSV
          </button>
          <button
            type="button"
            onClick={() => onExport('json')}
            className="px-2 py-1.5 bg-slate-900/60 text-slate-300 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-slate-800"
          >
            JSON
          </button>
        </div>

        {selectionCount >= 1 && (
          <button
            type="button"
            onClick={onBulk}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-cyan-500/40 bg-cyan-500/10 text-cyan-200 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-cyan-500/20"
          >
            ⚡ Bulk ({selectionCount})
          </button>
        )}

<DirtyBanner
          dirtyCount={dirtyCount}
          isSaving={isSaving}
          canUndo={canUndo}
          lastError={lastError}
          onCommit={onCommit}
          onRevert={onRevert}
          onUndo={onUndo}
        />
      </div>
    </div>
  );
};

const DirtyBanner: React.FC<{
  dirtyCount: number;
  isSaving: boolean;
  canUndo: boolean;
  lastError: string | null;
  onCommit: () => void;
  onRevert: () => void;
  onUndo: () => void;
}> = ({ dirtyCount, isSaving, canUndo, lastError, onCommit, onRevert, onUndo }) => {
  if (lastError) {
    return (
      <div className="inline-flex items-center gap-2 px-2 py-1 rounded-md border border-rose-500/40 bg-rose-500/15 text-rose-200 text-[11px] font-mono">
        <span>⚠ {lastError}</span>
      </div>
    );
  }
  if (dirtyCount === 0) {
    if (canUndo) {
      return (
        <button
          type="button"
          onClick={onUndo}
          className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-indigo-500/40 bg-indigo-500/10 text-indigo-200 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-indigo-500/20"
        >
          ↶ Undo
        </button>
      );
    }
    return null;
  }
  return (
    <div className="inline-flex items-center gap-2">
      <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md border border-amber-500/40 bg-amber-500/10 text-amber-200 text-[11px] font-mono font-bold uppercase tracking-wider">
        <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
        {dirtyCount} unsaved
      </span>
      <button
        type="button"
        onClick={onRevert}
        disabled={isSaving}
        className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-slate-700 bg-slate-900/60 text-slate-300 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-slate-800 disabled:opacity-40"
      >
        Revert
      </button>
      <button
        type="button"
        onClick={onCommit}
        disabled={isSaving}
        className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-emerald-500/40 bg-emerald-500/15 text-emerald-200 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-emerald-500/25 disabled:opacity-40"
      >
        {isSaving ? 'Saving…' : `Save ${dirtyCount}`}
      </button>
    </div>
  );
};