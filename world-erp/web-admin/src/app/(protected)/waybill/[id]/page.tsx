import React, { Suspense } from 'react';
import { cookies } from 'next/headers';
import { notFound, redirect } from 'next/navigation';
import {
  loadWaybillRailContext,
  loadApproversByStage,
  loadActedUsersByStage,
  loadExpenseFullPicture,
} from '@/lib/server/waybill';
import { loadActor } from '@/lib/server/guard';
import { loadVisionModels } from '@/lib/ai/loadVisionModels';
import { verifySession } from '@erp-lib/server/sessionToken';
import { buildPolicyContext, evalPolicy, POL, type PolicyContext } from '@erp-lib/policy';
import { getSecondaryLocale } from '@erp-lib/server/locale';
import { pipsForDomain, pipIndex, domainForOrigin } from '@erp-lib/waybill/derive';
import { WaybillStepCards } from '@/components/waybill/WaybillStepCards';
import { WaybillTimelineBlock } from '@/components/waybill/WaybillTimelineBlock';
import { WaybillAuditSectionBlock } from '@/components/waybill/WaybillAuditSectionBlock';
import { WaybillHeader } from '@/components/waybill/WaybillHeader';
import { InlineActionForm } from '@/components/waybill/InlineActionForm';
import { ExportPdfButton } from '@/components/waybill/ExportPdfButton';
import { DecisionBar } from '@/components/waybill/DecisionBar';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function asString(v: string | string[] | undefined): string | null {
  if (Array.isArray(v)) return v[0] ?? null;
  return v ?? null;
}

export default async function WaybillDetail({ params, searchParams }: PageProps) {
  const { id } = await params;
  const sp = await searchParams;

  const actor = await loadActor();
  if (!actor) redirect('/login');

  const ctx = await loadWaybillRailContext(id);
  if (!ctx) notFound();

  const wb = ctx.waybill;
  if (wb.origin === 'so') redirect(`/sales/${wb.origin_id}`);

  const action = asString(sp.action);

  const cookieValue = (await cookies()).get('erp_session')?.value ?? null;
  const payload = await verifySession(cookieValue);
  if (!payload) redirect('/login');
  const baseCtx = await buildPolicyContext(payload);
  if (!baseCtx) redirect('/login');

  const policyCtx: PolicyContext = {
    ...baseCtx,
    resource: {
      current_stage: wb.current_stage,
      origin: wb.origin,
      submitter_id: wb.submitter_id,
      requester_id: wb.submitter_id,
      total_amount_thb: wb.total_amount != null ? Number(wb.total_amount) : null,
      status: wb.status,
    },
  };

  const [approversByStage, actedUsersByStage, visionModels, locale, expensePicture] = await Promise.all([
    loadApproversByStage(wb.id),
    loadActedUsersByStage(wb.id),
    loadVisionModels(),
    getSecondaryLocale(),
    wb.origin === 'expense' ? loadExpenseFullPicture(wb.origin_id) : Promise.resolve(null),
  ]);

  const canAct = (await evalPolicy(POL.canActOnWaybill, policyCtx)).allow;
  const canAttach = (await evalPolicy(POL.canAttachAtStage, policyCtx)).allow;
  const canSettle = (await evalPolicy(POL.canSettleExpense, policyCtx)).allow;
  const canFinalApprove = (await evalPolicy(POL.canFinalApproveExpense, policyCtx)).allow;
  const canConfirmGl = (await evalPolicy(POL.canConfirmGl, policyCtx)).allow;
  const canReCall = (await evalPolicy(POL.recallWaybill, policyCtx)).allow;
  const canSaveAccrual = (await evalPolicy(POL.canSaveProcurementAccrual, policyCtx)).allow;
  const canPostAccrual = (await evalPolicy(POL.canPostGlAccrual, policyCtx)).allow;
  const canPostSettlement = (await evalPolicy(POL.canPostGlSettlement, policyCtx)).allow;
  const canReject = (await evalPolicy(POL.rejectWaybill, policyCtx)).allow;
  const actorCanSeeGlLines = (await evalPolicy(POL.canSeeGlLines, policyCtx)).allow;

  const isRejected = wb.status === 'rejected';
  const rejectionEvent = ctx.events.find((e) => e.kind === 'rejected') ?? null;
  const rejectionReason =
    (rejectionEvent?.payload as { reason?: string } | null)?.reason ?? null;
  const rejectionActorName = rejectionEvent?.actor_id
    ? (ctx.pipActors['rejected']?.name ?? null)
    : null;

  const originLabel =
    wb.origin === 'expense' ? `Expense EXP-${wb.origin_id}`
      : wb.origin === 'pr' ? `PR-${wb.origin_id}`
      : `PO-${wb.origin_id}`;
  const originHref =
    wb.origin === 'expense' ? `/expense/${wb.origin_id}`
      : wb.origin === 'pr' ? `/pr/${wb.origin_id}`
      : `/po/${wb.origin_id}`;

  const pipsAll = pipsForDomain(domainForOrigin(wb.origin));
  const curIdxAll = pipIndex(domainForOrigin(wb.origin), wb.current_stage);
  const stepsDone = curIdxAll < 0 ? 0 : curIdxAll;
  const stepsTotal = pipsAll.filter((p) => p.key !== 'rejected').length;
  const progressPct =
    wb.status === 'completed' ? 100
      : stepsTotal > 0 ? Math.round((stepsDone / stepsTotal) * 100) : 0;

  const statusTone = wb.status === 'completed'
    ? { ring: 'from-emerald-500/50 to-cyan-500/40', chip: 'bg-emerald-500/15 text-emerald-200 border-emerald-400/50', dot: 'bg-emerald-400', label: 'Completed' }
    : wb.status === 'rejected'
      ? { ring: 'from-rose-500/60 to-rose-500/20', chip: 'bg-rose-500/15 text-rose-200 border-rose-400/50', dot: 'bg-rose-400', label: 'Rejected' }
      : { ring: 'from-cyan-500/60 to-indigo-500/40', chip: 'bg-cyan-500/15 text-cyan-200 border-cyan-400/50', dot: 'bg-cyan-400 animate-pulse', label: 'In progress' };

  return (
    <>
      <BreadcrumbSetter
        crumbs={[
          { label: 'Hub', href: '/' },
          { label: 'Waybills', href: '/my-waybills' },
          { label: wb.id, href: `/waybill/${wb.id}` },
        ]}
      />
      <PageLayout
        actions={
          <ExportPdfButton
            waybillId={wb.id}
            attachments={ctx.attachments}
            defaultSections={{ cover: true, rail: true, audit: true, attachments: true }}
          />
        }
      >
        <section className="space-y-6 font-sans">
          <WaybillHeader
            wb={wb}
            originLabel={originLabel}
            originHref={originHref}
            actor={actor}
            isRejected={isRejected}
            statusTone={statusTone}
            stepsDone={stepsDone}
            stepsTotal={stepsTotal}
            progressPct={progressPct}
            activeActorName={ctx.activeActorName}
            locale={locale}
          />

          <DecisionBar
            waybillId={wb.id}
            currentStage={wb.current_stage}
            status={wb.status}
            amount={wb.total_amount ?? null}
            vendorName={wb.vendor_name ?? null}
            canAct={canAct}
            canFinalApprove={canFinalApprove}
            canSettle={canSettle}
            canConfirmGl={canConfirmGl}
            isFinalApproval={wb.current_stage === 'accounting_authorization'}
            isAwaitingDisbursement={wb.current_stage === 'awaiting_disbursement'}
            isDisbursed={wb.current_stage === 'disbursed'}
            isRejected={isRejected}
            actorRole={actor.rbac_role_id ?? actor.role_name}
          />

          {action === 'reject' && canReject && !isRejected && wb.status === 'open' && (
            <InlineActionForm kind="reject" waybillId={wb.id} stage={wb.current_stage} locale={locale} />
          )}

          <Suspense fallback={<div className="h-32 animate-pulse rounded-2xl border border-slate-800/60 bg-slate-950/40" aria-hidden />}>
            <WaybillTimelineBlock
              waybillId={wb.id}
              domain={domainForOrigin(wb.origin)}
              currentStage={wb.current_stage}
              status={wb.status}
              activeActorName={ctx.activeActorName}
              activeRole={actor.rbac_role_id ?? actor.role_name}
              rejectionReason={rejectionReason}
              rejectionActorName={rejectionActorName}
              rejectedAt={null}
            />
          </Suspense>

          <Suspense fallback={
            <div className="space-y-4">
              {Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="h-48 animate-pulse rounded-2xl border border-slate-800/60 bg-slate-950/40" aria-hidden />
              ))}
            </div>
          }>
            <WaybillStepCards
              wb={wb}
              waybillId={wb.id}
              currentStage={wb.current_stage}
              status={wb.status}
              events={ctx.events}
              attachments={ctx.attachments}
              approversByStage={approversByStage}
              actedUsersByStage={actedUsersByStage}
              expensePicture={expensePicture}
              hasGlConfirmed={false}
              artifacts={null}
              actorCanSeeGlLines={actorCanSeeGlLines}
              originId={wb.origin_id}
              visionModels={visionModels}
              actions={{
                canAct,
                canAttach,
                canSettle,
                canFinalApprove,
                canConfirmGl,
                canReCall,
                canSaveAccrual,
                canPostAccrual,
                canConfirmAccrual: false,
                canPostSettlement,
                canConfirmSettlement: false,
              }}
              flags={{
                isSubmitter: actor.id === wb.submitter_id,
                isFinalApproval: wb.current_stage === 'accounting_authorization',
                isDisbursed: wb.current_stage === 'disbursed',
              }}
              rejection={{
                reason: rejectionReason,
                actor: rejectionEvent?.actor_id
                  ? { user_id: rejectionEvent.actor_id, fullname: rejectionActorName ?? `#${rejectionEvent.actor_id}`, role: rejectionEvent.actor_role }
                  : null,
              }}
              ui={{ action, actionStage: wb.current_stage, locale }}
            />
          </Suspense>

          <Suspense fallback={<div className="h-24 animate-pulse rounded-2xl border border-slate-800/60 bg-slate-950/40" aria-hidden />}>
            <WaybillAuditSectionBlock waybillId={wb.id} />
          </Suspense>
        </section>
      </PageLayout>
    </>
  );
}
