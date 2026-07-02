'use client';

import React from 'react';
import type { Action, ModuleRow, MatrixResponse, ResolvedCell } from '@/lib/access/api';
import { PermCell } from './PermCell';
import type { DirtyApi } from './useDirty';

interface PermStripProps {
  matrix: MatrixResponse;
  modules: ModuleRow[];
  roleId: string;
  dirty: DirtyApi;
  isRoleHot: boolean;
  onClickCell: (cell: { role: string; module: string }) => void;
  onHoverCell: (cell: { role: string; module: string } | null) => void;
  hoveredCell: { role: string; module: string } | null;
}

export const PermStrip: React.FC<PermStripProps> = ({
  matrix,
  modules,
  roleId,
  dirty,
  isRoleHot,
  onClickCell,
  onHoverCell,
}) => {
  return (
    <div className="flex items-stretch divide-x divide-slate-800/60 border-l border-slate-800/60">
      {modules.map((mod) => {
        const mid = mod.id;
        const row = matrix.rows.find((r) => r.module_id === mid);
        const cell = row?.cells?.[roleId];
        if (!cell) return null;
        const optimistic: Record<Action, ResolvedCell> = {
          create: dirty.optimisticState(roleId, mid, 'create'),
          read: dirty.optimisticState(roleId, mid, 'read'),
          update: dirty.optimisticState(roleId, mid, 'update'),
          delete: dirty.optimisticState(roleId, mid, 'delete'),
        };
        const isHot =
          isRoleHot ||
          (optimistic.create.state === 'allow' ||
            optimistic.read.state === 'allow' ||
            optimistic.update.state === 'allow' ||
            optimistic.delete.state === 'allow');
        return (
          <div
            key={mid}
            className="min-w-[120px] flex-1"
            onMouseEnter={() => onHoverCell({ role: roleId, module: mid })}
            onMouseLeave={() => onHoverCell(null)}
          >
            <PermCell
              roleId={roleId}
              moduleId={mid}
              cell={cell}
              optimistic={optimistic}
              isDirty={(a) => dirty.isDirty(roleId, mid, a)}
              isHot={isHot}
              onToggleAction={(action, next) => {
                onClickCell({ role: roleId, module: mid });
                dirty.setCell(roleId, mid, action, next);
              }}
              onEnter={() => onClickCell({ role: roleId, module: mid })}
            />
          </div>
        );
      })}
    </div>
  );
};