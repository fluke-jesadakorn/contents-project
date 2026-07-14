'use client';

import React, { useMemo } from 'react';
import { usePathname } from 'next/navigation';
import { Breadcrumb, type Crumb } from './Breadcrumb';
import { ROOT_CRUMB, groupCrumb } from './breadcrumbs';
import { GROUP_LABEL, type TileGroup } from './tile-config';
import { useBreadcrumbContext } from './breadcrumbs/BreadcrumbProvider';

function isTileGroup(s: string | undefined): s is TileGroup {
  return !!s && s in GROUP_LABEL;
}

export const BreadcrumbBar: React.FC = () => {
  const pathname = usePathname() || '/';
  const { crumbs } = useBreadcrumbContext();

  const useDerived = crumbs.length === 0;

  const derived: Crumb[] = useMemo(() => {
    if (!useDerived) return [];
    if (pathname === '/' || pathname === '') return [ROOT_CRUMB];
    if (pathname.startsWith('/group/')) {
      const seg = pathname.split('/')[2] || '';
      if (isTileGroup(seg)) return [ROOT_CRUMB, groupCrumb(seg)];
      return [ROOT_CRUMB];
    }
    return [ROOT_CRUMB];
  }, [pathname, useDerived]);

  const finalCrumbs = useDerived ? derived : crumbs;

  return (
    <div className="max-w-6xl mx-auto px-3 sm:px-4 lg:px-6 -mt-4 mb-6">
      <Breadcrumb
        crumbs={finalCrumbs}
        className="!mb-0 !bg-transparent !border-0 !px-0 !py-0 !text-slate-500 text-xs font-mono"
      />
    </div>
  );
};

export default BreadcrumbBar;