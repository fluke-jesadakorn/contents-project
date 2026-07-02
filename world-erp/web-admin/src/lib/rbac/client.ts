// Browser-safe RBAC helper. Delegates to access/api.ts (HTTP to rbac-svc).

'use client';

import { useEffect, useState } from 'react';

export { access } from '@/lib/access/api';
export type { Action } from '@/lib/access/api';

export const canCheck = (
  rbacRoleId: string | null,
  moduleId: string,
  action: 'create' | 'read' | 'update' | 'delete' = 'read',
) => {
  if (!rbacRoleId) return Promise.resolve({ allow: false, source: 'default', inheritedFrom: null });
  return import('@/lib/access/api').then(({ access }) => access.can(rbacRoleId, moduleId, action));
};

export const canBatchCheck = (
  rbacRoleId: string | null,
  modules: string[],
  action: 'create' | 'read' | 'update' | 'delete' = 'read',
) => {
  if (!rbacRoleId) return Promise.resolve({} as Record<string, boolean>);
  return import('@/lib/access/api').then(({ access }) =>
    access.canBatch(rbacRoleId, modules, action).then((r) => r.allow),
  );
};

export function useCan(
  rbacRoleId: string | null | undefined,
  moduleId: string,
  action: 'create' | 'read' | 'update' | 'delete' = 'read',
): boolean | null {
  const [allow, setAllow] = useState<boolean | null>(null);
  useEffect(() => {
    let cancelled = false;
    canCheck(rbacRoleId ?? null, moduleId, action).then((r) => {
      if (!cancelled) setAllow(r.allow);
    }).catch(() => {
      if (!cancelled) setAllow(false);
    });
    return () => { cancelled = true; };
  }, [rbacRoleId, moduleId, action]);
  return allow;
}

export function useCanBatch(
  rbacRoleId: string | null | undefined,
  modules: string[],
  action: 'create' | 'read' | 'update' | 'delete' = 'read',
): Record<string, boolean> | null {
  const [allow, setAllow] = useState<Record<string, boolean> | null>(null);
  useEffect(() => {
    let cancelled = false;
    canBatchCheck(rbacRoleId ?? null, modules, action).then((r) => {
      if (!cancelled) setAllow(r);
    }).catch(() => {
      if (!cancelled) setAllow({});
    });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rbacRoleId, modules.join(','), action]);
  return allow;
}