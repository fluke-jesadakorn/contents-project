'use client';

import React from 'react';
import type { OrgNode } from '@/lib/orgScope';
import { OrgChartView } from './OrgChartView';
import { OrgChart } from '@/components/org-chart/OrgChart';
import type { DeptRow } from './UserEditModal';
import type { OrgResponse, MatrixResponse } from '@/lib/access/api';
import { useCan } from '@/lib/rbac/client';
import type { OrgChartView as OrgChartViewKind } from './OrgChartHR';

interface OrgChartHRClientProps {
  currentUser: any;
  view?: OrgChartViewKind;
  tree: OrgNode[];
  treeError: string | null;
  departments: DeptRow[];
  orgData: OrgResponse | null;
  matrix: MatrixResponse | null;
  canSeePermissions: boolean;
}

export const OrgChartHRClient: React.FC<OrgChartHRClientProps> = ({
  currentUser,
  view = 'people',
  tree,
  treeError,
  departments,
  orgData,
  matrix,
  canSeePermissions,
}) => {
  const rbacRoleId = currentUser?.rbac_role_id ?? null;
  const canEditFlag = useCan(rbacRoleId, 'rbac-edit-matrix', 'update');
  const canEdit = canEditFlag !== false;
  const serviceOk = !!orgData && !!matrix;

  if (view === 'permissions' && canSeePermissions) {
    return (
      <div className="space-y-3">
        <div className="glass-panel p-3 rounded-2xl border-slate-800 flex items-center justify-end">
          <span className="text-[10px] font-mono text-slate-500">
            {orgData
              ? `${countRoles(orgData.roles)} roles · ${matrix?.modules?.length ?? 0} modules`
              : ''}
          </span>
        </div>
        <div className="glass-panel rounded-2xl border-slate-800 overflow-hidden min-h-[60vh]">
          {orgData && matrix ? (
            <OrgChart org={orgData} matrix={matrix} serviceOk={serviceOk} rbacRoleId={currentUser?.rbac_role_id} />
          ) : (
            <div className="p-8 text-center text-slate-500 font-mono text-xs">
              ⏳ Loading permission matrix…
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="glass-panel p-3 rounded-2xl border-slate-800 flex items-center justify-end">
        <span className="text-[10px] font-mono text-slate-500">
          {countPeople(tree)} people · {departments.length} dept{departments.length === 1 ? '' : 's'}
        </span>
      </div>
      <div className="space-y-2">
        {treeError && tree.length === 0 && (
          <div className="glass-panel p-4 rounded-2xl border-amber-500/40 bg-amber-500/5 text-amber-200 text-[11px] font-mono flex items-center gap-3 flex-wrap">
            <span>⚠ {treeError}</span>
          </div>
        )}
        <div className="glass-panel p-4 rounded-2xl border-slate-800 min-w-0">
          <OrgChartView
            tree={tree}
            departments={departments}
            currentUserId={currentUser.id}
            canEdit={canEdit}
          />
        </div>
      </div>
    </div>
  );
};

function countPeople(tree: OrgNode[]): number {
  let n = 0;
  const walk = (x: OrgNode) => {
    n += 1;
    x.children.forEach(walk);
  };
  tree.forEach(walk);
  return n;
}

function countRoles(roles: any[]): number {
  let n = 0;
  const walk = (r: any) => {
    n += 1;
    if (r.children) r.children.forEach(walk);
  };
  roles.forEach(walk);
  return n;
}