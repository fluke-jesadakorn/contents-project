'use client';

import React, { useEffect, useState } from 'react';
import { OrgChartHRClient } from './OrgChartHRClient';
import { canCheck } from '@/lib/rbac/client';
import type { OrgNode } from '@/lib/orgScope';
import type { DeptRow } from './UserEditModal';
import type { OrgResponse, MatrixResponse } from '@/lib/access/api';

export type OrgChartView = 'people' | 'permissions';

interface OrgChartHRProps {
  currentUser: any;
  view?: OrgChartView;
  scopeTilesOnly?: boolean;
}

export const OrgChartHR: React.FC<OrgChartHRProps> = ({ currentUser, view = 'people', scopeTilesOnly = false }) => {
  const rbacRoleId = currentUser?.rbac_role_id ?? null;
  const [canSeePermissions, setCanSeePermissions] = useState(false);
  const [tree, setTree] = useState<OrgNode[]>([]);
  const [treeError, setTreeError] = useState<string | null>(null);
  const [departments, setDepartments] = useState<DeptRow[]>([]);
  const [orgData, setOrgData] = useState<OrgResponse | null>(null);
  const [matrix, setMatrix] = useState<MatrixResponse | null>(null);

  useEffect(() => {
    let cancelled = false;
    canCheck(rbacRoleId, 'rbac-view-matrix', 'read')
      .then((r) => { if (!cancelled) setCanSeePermissions(r.allow); })
      .catch(() => { if (!cancelled) setCanSeePermissions(false); });
    return () => { cancelled = true; };
  }, [rbacRoleId]);

  useEffect(() => {
    let cancelled = false;
    Promise.all([
      fetch('/api/org-tree').then((r) => r.json()).catch(() => ({ tree: [], error: 'failed' })),
      fetch('/api/departments').then((r) => r.json()).catch(() => ({ departments: [], error: 'failed' })),
    ]).then(([treeRes, deptRes]) => {
      if (cancelled) return;
      setTree(treeRes.tree ?? []);
      setTreeError(treeRes.error ?? null);
      setDepartments(deptRes.departments ?? []);
    });
    return () => { cancelled = true; };
  }, [currentUser.id]);

  const scopeTiles = scopeTilesOnly === true;

  useEffect(() => {
    if (!canSeePermissions) {
      setOrgData(null);
      setMatrix(null);
      return;
    }
    let cancelled = false;
    const matrixUrl = scopeTiles ? '/api/matrix?scope=tiles' : '/api/matrix';
    Promise.all([
      fetch('/api/org').then((r) => r.json()).catch(() => null),
      fetch(matrixUrl).then((r) => r.json()).catch(() => null),
    ]).then(([orgRes, matrixRes]) => {
      if (cancelled) return;
      setOrgData(orgRes?.org ?? null);
      setMatrix(matrixRes ?? null);
    });
    return () => { cancelled = true; };
  }, [canSeePermissions, scopeTiles]);

  return (
    <OrgChartHRClient
      currentUser={currentUser}
      view={view}
      tree={tree}
      treeError={treeError}
      departments={departments}
      orgData={orgData}
      matrix={matrix}
      canSeePermissions={canSeePermissions}
    />
  );
};