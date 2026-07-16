'use client';

import React, { createContext, useContext, useMemo, type ReactNode } from 'react';
import { usePathname } from 'next/navigation';
import { type ChromeTone as ChromeToneType, toneForPathname } from '@/lib/chromeTone';

interface ChromeToneCtx {
  tone: ChromeToneType;
}

const ChromeToneContext = createContext<ChromeToneCtx | null>(null);

export function useChromeTone(): ChromeToneType {
  const ctx = useContext(ChromeToneContext);
  return ctx?.tone ?? 'accent';
}

interface ChromeToneProps {
  children: ReactNode;
}

export const ChromeTone: React.FC<ChromeToneProps> = ({ children }) => {
  const pathname = usePathname();
  const tone = toneForPathname(pathname);
  const value = useMemo<ChromeToneCtx>(() => ({ tone }), [tone]);

  return (
    <ChromeToneContext.Provider value={value}>
      <div data-chrome-tone={tone} className="contents">
        {children}
      </div>
    </ChromeToneContext.Provider>
  );
};

export default ChromeTone;
