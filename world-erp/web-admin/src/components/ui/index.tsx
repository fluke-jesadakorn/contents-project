'use client';

import React from 'react';
import { ToastProvider } from './Toast';
import { DialogProvider } from './Dialog';
import { SecondaryLocaleProvider } from '@/components/i18n/SecondaryLocaleProvider';

export const UIProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <SecondaryLocaleProvider>
    <ToastProvider>
      <DialogProvider>{children}</DialogProvider>
    </ToastProvider>
  </SecondaryLocaleProvider>
);

export { useToast } from './Toast';
export { useDialog } from './Dialog';
export { Modal, type ModalProps, type ModalTone } from './Modal';
export { Kpi, type KpiProps, type KpiAccent } from './Kpi';
export { Button, type ButtonProps } from './Button';
export { Skeleton, PanelSkeleton, KpiSkeleton, TileSkeleton, SkeletonGrid, HeaderSkeleton } from './Loading';
export { GlobalLoading } from './GlobalLoading';
