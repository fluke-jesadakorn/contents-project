import React from 'react';
import { loadWaybillEvents } from '@/lib/server/waybill';
import type { WaybillDomain } from '@erp-lib/waybill/derive';
import { WaybillTimeline } from './WaybillTimeline';

interface Props {
  waybillId: string;
  domain: WaybillDomain;
  currentStage: string;
  status: 'open' | 'completed' | 'rejected' | 'reversed' | 'superseded';
  activeActorName: string | null;
  activeRole: string | null;
  rejectionReason: string | null;
  rejectionActorName: string | null;
  rejectedAt: string | null;
}

export async function WaybillTimelineBlock({
  waybillId,
  domain,
  currentStage,
  status,
  activeActorName,
  activeRole,
  rejectionReason,
  rejectionActorName,
  rejectedAt,
}: Props) {
  const events = await loadWaybillEvents(waybillId);
  return (
    <WaybillTimeline
      waybillId={waybillId}
      domain={domain}
      currentStage={currentStage}
      status={status}
      events={events}
      activeActorName={activeActorName}
      activeRole={activeRole}
      rejectionReason={rejectionReason}
      rejectionActorName={rejectionActorName}
      rejectedAt={rejectedAt}
    />
  );
}
