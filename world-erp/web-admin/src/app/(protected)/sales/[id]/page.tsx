import React from 'react';
import { Suspense } from 'react';
import { cookies } from 'next/headers';
import { redirect, notFound } from 'next/navigation';
import {
  loadWaybillRailContext,
  loadApproversByStage,
  loadActedUsersByStage,
  loadJournalForWaybill,
  loadSalesArtifacts,
} from '@/lib/server/waybill';
import { loadActor } from '@/lib/server/guard';
import { loadVisionModels } from '@/lib/ai/loadVisionModels';
import { verifySession } from '@erp-lib/server/sessionToken';
import { buildPolicyContext, evalPolicy, POL, type PolicyContext } from '@erp-lib/policy';
import { getSecondaryLocale } from '@erp-lib/server/locale';
import { pipsForDomain, pipIndex, domainForOrigin } from '@erp-lib/waybill/derive';
import { WaybillStepCards } from '@/components/waybill/WaybillStepCards';
import { WaybillGlSection } from '@/components/waybill/WaybillGlSection';
import { WaybillTimelineBlock } from '@/components/waybill/WaybillTimelineBlock';
import { WaybillAuditSectionBlock } from '@/components/waybill/WaybillAuditSectionBlock';
import { WaybillHeader } from '@/components/waybill/WaybillHeader';
import { InlineActionForm } from '@/components/waybill/InlineActionForm';
import { ExportPdfButton } from '@/components/waybill/ExportPdfButton';
import { DecisionBar } from '@/components/waybill/DecisionBar';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import { SalesPipPanel } from './_components/SalesPipPanel';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function asString(v: string | string[] | undefined): string | null {
  if (Array.isArray(v)) return v[0] ?? null;
  return v ?? null;
}

export default async function SalesDetailPage({ params, searchParams }: PageProps) {
  const { id } = await params;
  const sp = await searchParams;

  const actor = await loadActor();
  if (!actor) redirect('/login');

  const ctx = await loadWaybillRailContext(id);
  if (!ctx || ctx.waybill.origin !== 'so') notFound();

  const wb = ctx.waybill;
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

  const salesArtifacts = await loadSalesArtifacts(wb);

  const [approversByStage, actedUsersByStage, visionModels, locale, salesJournal] = await Promise.all([
    loadApproversByStage(wb.id),
    loadActedUsersByStage(wb.id),
    loadVisionModels(),
    getSecondaryLocale(),
    loadJournalForWaybill(wb.id),
  ]);

  const actorCanSeeGlLines = (await evalPolicy(POL.canSeeGlLines, policyCtx)).allow;
  const canPostSalesGlVat = (await evalPolicy(POL.canPostSalesGlVat, policyCtx)).allow;
  const canPostSalesGlAccrual = (await evalPolicy(POL.canPostSalesGlAccrual, policyCtx)).allow;
  const canPostSalesGlSettlement = (await evalPolicy(POL.canPostSalesGlSettlement, policyCtx)).allow;
  const canConfirmSalesGl = (await evalPolicy(POL.canConfirmSalesGl, policyCtx)).allow;

  const rejectionEvent = ctx.events.find((e) => e.kind === 'so-rejected') ?? null;
  const rejectionReason = (rejectionEvent?.payload as { reason?: string } | null)?.reason ?? null;

  const pipsAll = pipsForDomain(domainForOrigin(wb.origin));
  const curIdxAll = pipIndex(domainForOrigin(wb.origin), wb.current_stage);
  const stepsDone = curIdxAll < 0 ? 0 : curIdxAll;
  const stepsTotal = pipsAll.filter((p) => p.key !== 'rejected').length;
  const progressPct = wb.status === 'completed' ? 100
    : stepsTotal > 0 ? Math.round((stepsDone / stepsTotal) * 100) : 0;
  const statusTone = wb.status === 'completed' ? { ring: 'from-emerald-500/50 to-cyan-500/40', chip: 'bg-emerald-500/15 text-emerald-200 border-emerald-400/50', dot: 'bg-emerald-400', label: 'Completed' }
    : wb.status === 'rejected' ? { ring: 'from-rose-500/60 to-rose-500/20', chip: 'bg-rose-500/15 text-rose-200 border-rose-400/50', dot: 'bg-rose-400', label: 'Rejected' }
      : { ring: 'from-cyan-500/60 to-indigo-500/40', chip: 'bg-cyan-500/15 text-cyan-200 border-cyan-400/50', dot: 'bg-cyan-400 animate-pulse', label: 'In progress' };

  const canAct = (await evalPolicy(POL.canActOnSalesOrder, policyCtx)).allow;

  return (
    <>
      <BreadcrumbSetter
        crumbs={[
          { label: 'Hub', href: '/' },
          { label: 'Sales', href: '/sales' },
          { label: wb.id, href: `/waybill/${wb.id}` },
        ]}
      />
      <PageLayout
        title={wb.id}
        subtitle={`SO · ${wb.vendor_name ?? '—'}`}
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
            originLabel={`SO-${wb.origin_id}`}
            originHref="/sales"
            actor={actor}
            isRejected={wb.status === 'rejected'}
            statusTone={statusTone}
            stepsDone={stepsDone}
            stepsTotal={stepsTotal}
            progressPct={progressPct}
            activeActorName={ctx.activeActorName}
          />

          <DecisionBar
            waybillId={wb.id}
            currentStage={wb.current_stage}
            status={wb.status}
            amount={wb.total_amount ?? null}
            vendorName={wb.vendor_name ?? null}
            canAct={canAct}
            canFinalApprove={false}
            canSettle={(await evalPolicy(POL.canSettleSales, policyCtx)).allow}
            canConfirmGl={(await evalPolicy(POL.canConfirmSalesGl, policyCtx)).allow}
            isFinalApproval={wb.current_stage === 'so_invoiced'}
            isAwaitingDisbursement={wb.current_stage === 'so_invoiced'}
            isDisbursed={wb.current_stage === 'so_paid'}
            isRejected={wb.status === 'rejected'}
            actorRole={actor.role_name ?? null}
          />

          {action === 'reject' && canAct && !rejectionReason && wb.status === 'open' && (
            <InlineActionForm kind="reject" waybillId={wb.id} stage={wb.current_stage} locale={locale} />
          )}

          <Suspense fallback={<div className="h-32 animate-pulse rounded-2xl border border-slate-800/60 bg-slate-950/40" aria-hidden />}>
            <WaybillTimelineBlock
              waybillId={wb.id}
              domain="sales"
              currentStage={wb.current_stage}
              status={wb.status as 'open' | 'completed' | 'rejected' | 'reversed' | 'superseded'}
              activeActorName={ctx.activeActorName}
              activeRole={actor.role_name ?? null}
              rejectionReason={rejectionReason}
              rejectionActorName={null}
              rejectedAt={null}
            />
          </Suspense>

          <Suspense fallback={<div className="space-y-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="h-48 animate-pulse rounded-2xl border border-slate-800/60 bg-slate-950/40" aria-hidden />
            ))}
          </div>}>
            <WaybillStepCards
              wb={wb}
              waybillId={wb.id}
              currentStage={wb.current_stage}
              status={wb.status}
              events={ctx.events}
              attachments={ctx.attachments}
              approversByStage={approversByStage}
              actedUsersByStage={actedUsersByStage}
              expensePicture={null}
              hasGlConfirmed={false}
              artifacts={salesArtifacts as never}
              actorCanSeeGlLines={(await evalPolicy(POL.canConfirmSalesGl, policyCtx)).allow}
              originId={wb.origin_id}
              visionModels={visionModels}
              actions={{
                canAct,
                canAttach: false,
                canSettle: (await evalPolicy(POL.canSettleSales, policyCtx)).allow,
                canFinalApprove: false,
                canConfirmGl: (await evalPolicy(POL.canConfirmSalesGl, policyCtx)).allow,
                canReCall: false,
                canSaveAccrual: false,
                canPostAccrual: (await evalPolicy(POL.canPostSalesGlVat, policyCtx)).allow,
                canConfirmAccrual: false,
                canPostSettlement: (await evalPolicy(POL.canPostSalesGlSettlement, policyCtx)).allow,
                canConfirmSettlement: (await evalPolicy(POL.canConfirmSalesGl, policyCtx)).allow,
              }}
              flags={{
                isSubmitter: actor.id === wb.submitter_id,
                isFinalApproval: wb.current_stage === 'so_invoiced',
                isDisbursed: wb.current_stage === 'so_paid',
              }}
              rejection={{ reason: rejectionReason, actor: null }}
              ui={{ action, actionStage: null, locale }}
            />
          </Suspense>

          {salesArtifacts ? (
            <SalesPipPanel
              waybillId={wb.id}
              artifacts={salesArtifacts}
              currentStage={wb.current_stage}
            />
          ) : null}

          <WaybillGlSection
            waybillId={wb.id}
            origin="so"
            journal={salesJournal}
            actorRole={actor.role_name ?? null}
            actorCanSeeLines={actorCanSeeGlLines}
            lang={locale}
            canPostSalesGlVat={canPostSalesGlVat}
            canPostSalesGlAccrual={canPostSalesGlAccrual}
            canPostSalesGlSettlement={canPostSalesGlSettlement}
            canConfirmSalesGl={canConfirmSalesGl}
          />

          <Suspense fallback={<div className="h-24 animate-pulse rounded-2xl border border-slate-800/60 bg-slate-950/40" aria-hidden />}>
            <WaybillAuditSectionBlock waybillId={wb.id} />
          </Suspense>
        </section>
      </PageLayout>
    </>
  );
}
