'use client';

import React from 'react';
import { ToastProvider } from './Toast';
import { DialogProvider } from './Dialog';

export const UIProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <ToastProvider>
    <DialogProvider>{children}</DialogProvider>
  </ToastProvider>
);

export { useToast } from './Toast';
export { useDialog } from './Dialog';
export { Modal, type ModalProps, type ModalTone } from './Modal';
export { Kpi, type KpiProps, type KpiAccent } from './Kpi';
export { Skeleton, PanelSkeleton, KpiSkeleton, TileSkeleton, SkeletonGrid, HeaderSkeleton } from './Loading';
export { GlobalLoading } from './GlobalLoading';
