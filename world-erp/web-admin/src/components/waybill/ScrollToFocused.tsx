'use client';

import { useEffect } from 'react';

export function ScrollToFocused({ pipKey }: { pipKey: string | null }) {
  useEffect(() => {
    if (!pipKey) return;
    const tries = 4;
    let cancelled = false;
    let i = 0;
    const tryScroll = (): void => {
      if (cancelled) return;
      const el = document.getElementById(`pip-${pipKey}`);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
      i += 1;
      if (i >= tries) return;
      window.setTimeout(tryScroll, 80);
    };
    const t = window.setTimeout(tryScroll, 60);
    return () => {
      cancelled = true;
      window.clearTimeout(t);
    };
  }, [pipKey]);
  return null;
}
