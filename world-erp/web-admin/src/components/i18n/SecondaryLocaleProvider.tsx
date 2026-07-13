'use client';

import React, { createContext, useContext } from 'react';
import type { SecondaryLocale } from '@erp-lib/server/locale';

const Ctx = createContext<SecondaryLocale>('th');

export function SecondaryLocaleProvider({
  value,
  children,
}: {
  value: SecondaryLocale;
  children: React.ReactNode;
}) {
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSecondaryLocale(): SecondaryLocale {
  return useContext(Ctx);
}