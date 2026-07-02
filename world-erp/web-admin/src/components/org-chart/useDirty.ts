'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Action, MatrixResponse, ResolvedCell } from '@/lib/access/api';
import { access, type CellChange } from '@/lib/access/api';

export type CellKey = `${string}|${string}|${Action}`;

const keyOf = (role: string, mod: string, action: Action): CellKey =>
  `${role}|${mod}|${action}` as CellKey;

interface DirtyEntry {
  role: string;
  module: string;
  action: Action;
  next: 'allow' | 'deny' | 'inherit';
}

interface Snapshot {
  matrix: MatrixResponse;
  previous: Map<CellKey, ResolvedCell>;
}

export interface DirtyApi {
  dirtyCount: number;
  hasUnsaved: boolean;
  isDirty: (role: string, mod: string, action: Action) => boolean;
  optimisticState: (role: string, mod: string, action: Action) => ResolvedCell;
  setCell: (
    role: string,
    mod: string,
    action: Action,
    next: 'allow' | 'deny' | 'inherit',
  ) => void;
  commit: (actor?: string, reason?: string) => Promise<{ applied: number }>;
  revert: () => void;
  canUndo: boolean;
  undo: (actor?: string) => Promise<void>;
  isSaving: boolean;
  lastError: string | null;
}

export interface DirtyOptions {
  parentMap?: Map<string, string | null>;
}

export function useDirty(initial: MatrixResponse, options?: DirtyOptions): DirtyApi {
  const [matrix, setMatrix] = useState<MatrixResponse>(initial);
  const [dirty, setDirty] = useState<Map<CellKey, DirtyEntry>>(new Map());
  const [history, setHistory] = useState<Snapshot[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);
  const dirtyRef = useRef(dirty);
  dirtyRef.current = dirty;
  const parentMap = options?.parentMap;

  const optimisticState = useCallback(
    (role: string, mod: string, action: Action): ResolvedCell => {
      const k = keyOf(role, mod, action);
      const d = dirty.get(k);
      const live = matrix.rows.find((r) => r.module_id === mod)?.cells?.[role]?.[action];
      if (!d) {
        return live ?? { state: 'deny', source: 'default' };
      }
      if (d.next === 'allow' || d.next === 'deny') {
        return { state: d.next, source: 'explicit' };
      }
      if (parentMap) {
        let cursor: string | null = parentMap.get(role) ?? null;
        while (cursor) {
          const ancestorLive = matrix.rows.find((r) => r.module_id === mod)?.cells?.[cursor]?.[action];
          if (ancestorLive && (ancestorLive.state === 'allow' || ancestorLive.state === 'deny')) {
            return {
              state: ancestorLive.state,
              source: 'inherited_from_parent',
              inheritedFrom: cursor,
            };
          }
          cursor = parentMap.get(cursor) ?? null;
        }
      }
      return { state: 'deny', source: 'default' };
    },
    [dirty, matrix, parentMap],
  );

  const isDirty = useCallback(
    (role: string, mod: string, action: Action) =>
      dirty.has(keyOf(role, mod, action)),
    [dirty],
  );

  const setCell = useCallback<DirtyApi['setCell']>(
    (role, mod, action, next) => {
      setDirty((prev) => {
        const next_ = new Map(prev);
        const k = keyOf(role, mod, action);
        const live = matrix.rows.find((r) => r.module_id === mod)?.cells?.[role]?.[action];
        if (live?.state === next) {
          next_.delete(k);
        } else {
          next_.set(k, { role, module: mod, action, next });
        }
        return next_;
      });
    },
    [matrix],
  );

  const commit = useCallback<DirtyApi['commit']>(
    async (actor = 'ui', reason) => {
      const entries = Array.from(dirtyRef.current.values());
      if (entries.length === 0) return { applied: 0 };
      setIsSaving(true);
      setLastError(null);
      try {
        const changes: CellChange[] = entries.map((e) => ({
          role_id: e.role,
          module_id: e.module,
          action: e.action,
          state: e.next,
        }));
        const previous = new Map<CellKey, ResolvedCell>();
        for (const e of entries) {
          const k = keyOf(e.module, e.action, e.action);
          const live = matrix.rows.find((r) => r.module_id === e.module)?.cells?.[e.role]?.[e.action];
          if (live) previous.set(k, live);
        }
        const res = await access.patchCells(changes, actor, reason);
        setHistory((h) => [...h.slice(-9), { matrix, previous }]);
        setMatrix((m) => {
          const next: MatrixResponse = {
            ...m,
            rows: m.rows.map((row) => {
              const cells = { ...row.cells };
              for (const e of entries.filter((x) => x.module === row.module_id)) {
                const existing = cells[e.role] ?? ({} as Record<Action, ResolvedCell>);
                const nextCell: ResolvedCell =
                  e.next === 'allow' || e.next === 'deny'
                    ? { state: e.next, source: 'explicit' }
                    : { state: 'deny', source: 'default' };
                cells[e.role] = { ...existing, [e.action]: nextCell };
              }
              return { ...row, cells };
            }),
          };
          return next;
        });
        setDirty(new Map());
        return res;
      } catch (e) {
        setLastError(e instanceof Error ? e.message : String(e));
        throw e;
      } finally {
        setIsSaving(false);
      }
    },
    [matrix],
  );

  const revert = useCallback(() => {
    setDirty(new Map());
    setLastError(null);
  }, []);

  const undo = useCallback<DirtyApi['undo']>(
    async (actor = 'ui') => {
      const last = history[history.length - 1];
      if (!last) return;
      const inverse: CellChange[] = [];
      for (const [k, prev] of last.previous.entries()) {
        const [role_id, module_id, action] = k.split('|') as [string, string, Action];
        inverse.push({ role_id, module_id, action, state: prev.state });
      }
      if (inverse.length === 0) {
        setHistory((h) => h.slice(0, -1));
        return;
      }
      try {
        await access.patchCells(inverse, actor, 'undo');
        setMatrix(last.matrix);
        setHistory((h) => h.slice(0, -1));
      } catch (e) {
        setLastError(e instanceof Error ? e.message : String(e));
      }
    },
    [history],
  );

  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => {
      const isSaveCombo = (ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === 's';
      if (isSaveCombo) {
        ev.preventDefault();
        if (dirtyRef.current.size > 0) {
          void commit('ui', 'keyboard-save');
        }
      } else if (ev.key === 'Escape') {
        if (dirtyRef.current.size > 0) revert();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [commit, revert]);

  return useMemo<DirtyApi>(
    () => ({
      dirtyCount: dirty.size,
      hasUnsaved: dirty.size > 0,
      isDirty,
      optimisticState,
      setCell,
      commit,
      revert,
      canUndo: history.length > 0,
      undo,
      isSaving,
      lastError,
    }),
    [dirty.size, isDirty, optimisticState, setCell, commit, revert, history.length, undo, isSaving, lastError],
  );
}