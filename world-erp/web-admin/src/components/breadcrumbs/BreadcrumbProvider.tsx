'use client';

import React, { createContext, useContext, useMemo, useState, useCallback } from 'react';
import type { Crumb } from '../Breadcrumb';

interface BreadcrumbCtx {
  crumbs: Crumb[];
  setCrumbs: (c: Crumb[]) => void;
  clear: () => void;
}

const Ctx = createContext<BreadcrumbCtx | null>(null);

export function BreadcrumbProvider({ children }: { children: React.ReactNode }) {
  const [crumbs, setCrumbsState] = useState<Crumb[]>([]);
  const setCrumbs = useCallback((c: Crumb[]) => setCrumbsState(Array.isArray(c) ? c : []), []);
  const clear = useCallback(() => setCrumbsState([]), []);
  const value = useMemo(() => ({ crumbs, setCrumbs, clear }), [crumbs, setCrumbs, clear]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useBreadcrumbContext(): BreadcrumbCtx {
  return useContext(Ctx) ?? { crumbs: [], setCrumbs: () => {}, clear: () => {} };
}