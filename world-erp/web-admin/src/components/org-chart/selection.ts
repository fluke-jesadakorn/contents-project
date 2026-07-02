'use client';

import { useCallback, useMemo, useState } from 'react';
import type {
  ColumnRole,
  MatrixResponse,
  OrgResponse,
  RoleNode,
} from '@/lib/access/api';

export interface ChartSelection {
  selectedRoles: Set<string>;
  hoveredRole: string | null;
  hoveredCell: { role: string; module: string } | null;
  focusedCell: { role: string; module: string } | null;
}

export function useChart(matrix: MatrixResponse, _org: OrgResponse) {
  const [sel, setSel] = useState<ChartSelection>({
    selectedRoles: new Set(),
    hoveredRole: null,
    hoveredCell: null,
    focusedCell: null,
  });

  const flatRoles = useMemo(
    () =>
      [...matrix.columns].sort(
        (a, b) => b.level - a.level || a.sort_order - b.sort_order,
      ),
    [matrix.columns],
  );

  const isRoleHot = useCallback(
    (id: string) =>
      sel.selectedRoles.has(id) ||
      sel.hoveredRole === id ||
      sel.hoveredCell?.role === id ||
      sel.focusedCell?.role === id,
    [sel],
  );

  const isCellHot = useCallback(
    (role: string, module: string) =>
      sel.hoveredCell?.role === role && sel.hoveredCell?.module === module,
    [sel.hoveredCell],
  );

  const toggleRole = useCallback((id: string, additive: boolean) => {
    setSel((s) => {
      const next = new Set(additive ? s.selectedRoles : []);
      if (additive && s.selectedRoles.has(id)) next.delete(id);
      else next.add(id);
      return { ...s, selectedRoles: next };
    });
  }, []);

  const setHoveredRole = useCallback((id: string | null) => {
    setSel((s) => ({ ...s, hoveredRole: id }));
  }, []);

  const setHoveredCell = useCallback(
    (cell: { role: string; module: string } | null) => {
      setSel((s) => ({ ...s, hoveredCell: cell }));
    },
    [],
  );

  const setFocusedCell = useCallback(
    (cell: { role: string; module: string } | null) => {
      setSel((s) => ({ ...s, focusedCell: cell }));
    },
    [],
  );

  return {
    sel,
    flatRoles,
    isRoleHot,
    isCellHot,
    toggleRole,
    setHoveredRole,
    setHoveredCell,
    setFocusedCell,
  };
}

export type { ColumnRole, RoleNode };