'use client';

import { useEffect } from 'react';
import { useBreadcrumbContext } from './BreadcrumbProvider';
import type { Crumb } from '../Breadcrumb';

interface Props {
  crumbs: Crumb[];
}

export function BreadcrumbSetter({ crumbs }: Props) {
  const { setCrumbs, clear } = useBreadcrumbContext();
  useEffect(() => {
    setCrumbs(crumbs);
    return () => clear();
  }, [crumbs, setCrumbs, clear]);
  return null;
}

export default BreadcrumbSetter;