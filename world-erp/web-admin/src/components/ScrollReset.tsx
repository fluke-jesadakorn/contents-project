'use client';

import { usePathname } from 'next/navigation';
import { useEffect } from 'react';

export const ScrollReset: React.FC = () => {
  const pathname = usePathname();
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: 'instant' as ScrollBehavior });
  }, [pathname]);
  return null;
};

export default ScrollReset;
