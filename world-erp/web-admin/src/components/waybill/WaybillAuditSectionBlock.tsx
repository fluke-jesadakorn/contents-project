import React from 'react';
import { loadWaybillEvents } from '@/lib/server/waybill';
import { verifyEventChain } from '@erp-lib/waybill/events';
import { getSecondaryLocale } from '@erp-lib/server/locale';
import { WaybillAuditSection } from './WaybillAuditSection';

interface Props {
  waybillId: string;
}

export async function WaybillAuditSectionBlock({ waybillId }: Props) {
  const [[events, integrity], locale] = await Promise.all([
    Promise.all([loadWaybillEvents(waybillId), verifyEventChain(waybillId)]),
    getSecondaryLocale(),
  ]);
  return <WaybillAuditSection waybillId={waybillId} events={events} integrity={integrity} locale={locale} />;
}
