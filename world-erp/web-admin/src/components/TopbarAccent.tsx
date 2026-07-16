'use client';

import React from 'react';
import { useChromeTone } from './ChromeTone';
import { TONE_VAR } from '@/lib/chromeTone';

export const TopbarAccent: React.FC = () => {
  const tone = useChromeTone();
  return (
    <span
      aria-hidden
      className="absolute bottom-0 left-0 right-0 h-[2px] pointer-events-none"
      style={{
        background: `linear-gradient(90deg, var(${TONE_VAR[tone]}) 0%, transparent 80%)`,
      }}
    />
  );
};

export default TopbarAccent;
