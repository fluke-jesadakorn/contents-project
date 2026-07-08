import React from 'react';
import { notFound, redirect } from 'next/navigation';
import { loadWaybillRailContext } from '@/lib/server/waybill';
import { loadActor } from '@/lib/server/guard';
import type { WaybillEventRow } from '@erp-lib/waybill/events';
import { WaybillRail } from '@/components/waybill/WaybillRail';
import { WaybillDetailDrawer } from '@/components/waybill/WaybillDetailDrawer';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import {
  approveWaybillAction,
  rejectWaybillAction,
  resubmitWaybillAction,
  settleWaybillAction,
} from './_actions';
import { verifyEventChain } from '@erp-lib/waybill/events';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function fmtAmount(amount: string | null, currency: string): string {
  if (!amount) return '—';
  const n = parseFloat(amount);
  if (!Number.isFinite(n)) return amount;
  return `${n.toLocaleString('th-TH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;
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
  const action = asString(sp.action);
  const stage = asString(sp.stage) ?? wb.current_stage;

  // linked-list integrity check
  const integrity = await verifyEventChain(wb.id);

  // Look up origin link for breadcrumb
  let originLabel = '';
  let originHref = '';
  if (wb.origin === 'expense') {
    originLabel = `Expense EXP-${wb.origin_id}`;
    originHref = `/expense/${wb.origin_id}`;
  } else if (wb.origin === 'pr') {
    originLabel = `PR-${wb.origin_id}`;
    originHref = `/pr/${wb.origin_id}`;
  } else if (wb.origin === 'po') {
    originLabel = `PO-${wb.origin_id}`;
    originHref = `/po/${wb.origin_id}`;
  }

  const isSubmitter = actor.id === wb.submitter_id;
  const isRejected = wb.status === 'rejected';

  // Active role gating (rough — a finance role can approve at disbursement_authorization)
  const actorRole = actor.role_name ?? 'staff';
  const actorAtStage =
    actorRole === wb.current_owner_role ||
    ['cfo', 'ceo', 'admin'].includes(actorRole);
  const canAct = actorAtStage && !isRejected && wb.status === 'open';

  // settle available only for expense claims at awaiting_disbursement
  const canSettle =
    wb.origin === 'expense' &&
    wb.current_stage === 'awaiting_disbursement' &&
    wb.status === 'open';

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
        title={`Waybill ${wb.id}`}
        subtitle={`${originLabel} · ${wb.vendor_name ?? '—'} · ${fmtAmount(wb.total_amount, wb.currency)}`}
      >
        <section className="space-y-4 font-sans">
          <header className="flex items-center justify-between rounded-2xl border border-slate-800 bg-slate-950/60 p-4">
            <div className="space-y-1">
              <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
                Origin
              </div>
              <div className="flex items-center gap-2 text-sm">
                <span aria-hidden>📦</span>
                <a className="font-mono text-cyan-300 underline" href={originHref}>
                  {originLabel}
                </a>
                <span className="text-slate-500">·</span>
                <span className="text-slate-300">
                  {wb.vendor_name ?? '—'}
                </span>
                <span className="text-slate-500">·</span>
                <span className="font-mono text-white">
                  {fmtAmount(wb.total_amount, wb.currency)}
                </span>
              </div>
              <div className="flex items-center gap-2 text-[11px] text-slate-500">
                <span>👤 {actor.fullname ?? `User ${actor.id}`}</span>
                {ctx.activeActorName && wb.status === 'open' && (
                  <>
                    <span>·</span>
                    <span>
                      Waiting:{' '}
                      <span className="font-mono text-cyan-300">{ctx.activeActorName}</span>
                    </span>
                  </>
                )}
              </div>
            </div>
            <div className="text-right">
              <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
                Status
              </div>
              <span
                className={
                  'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-mono font-bold uppercase ' +
                  (wb.status === 'completed'
                    ? 'bg-blue-500/15 text-blue-200 border border-blue-500/40'
                    : wb.status === 'rejected'
                    ? 'bg-rose-500/10 text-rose-300 border border-rose-500/40'
                    : 'bg-cyan-500/10 text-cyan-300 border border-cyan-500/30')
                }
              >
                {wb.status}
              </span>
            </div>
          </header>

          <WaybillRail
            domain={ctx.domain}
            currentStage={wb.current_stage}
            activeActorName={ctx.activeActorName}
            rejectionReason={
              wb.status === 'rejected'
                ? (ctx.events
                    .slice()
                    .reverse()
                    .find((e) => e.kind === 'rejected')?.payload as { reason?: string } | null)?.reason ??
                  null
                : null
            }
            amountTHB={wb.total_amount ? parseFloat(wb.total_amount) : null}
            onPipHref={(pipKey) => `/waybill/${wb.id}?pip=${pipKey}`}
          />

          {!integrity.ok && (
            <div className="rounded-xl border border-rose-500/40 bg-rose-950/40 p-3 text-xs text-rose-200">
              ⚠ Audit chain integrity check failed: {integrity.reason}
            </div>
          )}

          {action === 'approve' && canAct && (
            <form
              action={approveWaybillAction}
              className="rounded-2xl border border-emerald-500/40 bg-emerald-950/30 p-4"
            >
              <input type="hidden" name="waybillId" value={wb.id} />
              <input type="hidden" name="stage" value={stage} />
              <p className="text-xs text-emerald-100">
                Approve &amp; advance to <span className="font-mono">awaiting_disbursement</span>?
              </p>
              <button
                type="submit"
                className="mt-3 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-bold text-slate-950 hover:bg-emerald-400"
              >
                ✓ Confirm approve
              </button>
              <a
                href={`/waybill/${wb.id}`}
                className="ml-2 rounded-lg border border-slate-700 px-4 py-2 text-sm text-slate-300"
              >
                Cancel
              </a>
            </form>
          )}

          {action === 'reject' && canAct && (
            <form
              action={rejectWaybillAction}
              className="rounded-2xl border border-rose-500/40 bg-rose-950/30 p-4"
            >
              <input type="hidden" name="waybillId" value={wb.id} />
              <input type="hidden" name="stage" value={stage} />
              <label className="block text-xs text-rose-200">
                Reject reason (≥ 5 chars):
                <textarea
                  name="reason"
                  required
                  minLength={5}
                  className="mt-2 block w-full rounded bg-slate-950 p-2 text-sm text-white"
                  rows={3}
                />
              </label>
              <div className="mt-3 flex gap-2">
                <button
                  type="submit"
                  className="rounded-lg bg-rose-500 px-4 py-2 text-sm font-bold text-slate-950 hover:bg-rose-400"
                >
                  ✗ Confirm reject
                </button>
                <a
                  href={`/waybill/${wb.id}`}
                  className="rounded-lg border border-slate-700 px-4 py-2 text-sm text-slate-300"
                >
                  Cancel
                </a>
              </div>
            </form>
          )}

          {isRejected && isSubmitter && (
            <form
              action={resubmitWaybillAction}
              className="rounded-2xl border border-amber-500/40 bg-amber-950/30 p-4"
            >
              <input type="hidden" name="waybillId" value={wb.id} />
              <p className="text-xs text-amber-100">
                Rejected. Resubmit and route the chain again from the start?
              </p>
              <button
                type="submit"
                className="mt-3 rounded-lg bg-amber-400 px-4 py-2 text-sm font-bold text-slate-950 hover:bg-amber-300"
              >
                ↩ Resubmit
              </button>
            </form>
          )}

          {canAct && !action && !isRejected && (
            <div className="flex flex-wrap gap-2">
              <a
                href={`/waybill/${wb.id}?action=approve`}
                className="rounded-lg bg-emerald-500/20 px-3 py-1.5 text-xs font-mono text-emerald-200 hover:bg-emerald-500/30"
              >
                ✓ Approve
              </a>
              <a
                href={`/waybill/${wb.id}?action=reject`}
                className="rounded-lg bg-rose-500/20 px-3 py-1.5 text-xs font-mono text-rose-200 hover:bg-rose-500/30"
              >
                ✗ Reject
              </a>
            </div>
          )}

          {canSettle && !isRejected && (
            <form
              action={settleWaybillAction}
              className="rounded-2xl border border-cyan-500/40 bg-cyan-950/30 p-4"
            >
              <input type="hidden" name="waybillId" value={wb.id} />
              <p className="text-xs text-cyan-100">
                Settle this expense: mark as <span className="font-mono">disbursed</span> and post a mock payment.
              </p>
              <div className="mt-3 flex flex-wrap items-center gap-2">
                <select
                  name="paymentMethod"
                  defaultValue="transfer"
                  className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-1.5 text-xs text-white"
                >
                  <option value="transfer">Bank transfer</option>
                  <option value="cash">Cash</option>
                  <option value="credit_card">Credit card</option>
                </select>
                <button
                  type="submit"
                  className="rounded-lg bg-cyan-400 px-4 py-1.5 text-xs font-bold text-slate-950 hover:bg-cyan-300"
                >
                  💸 Confirm settlement
                </button>
              </div>
            </form>
          )}

          {!canAct && !isRejected && !action && (
            <div className="text-[10px] font-mono text-slate-500">
              You don&apos;t have approval rights for this Waybill stage.
            </div>
          )}

          <EventTimeline events={ctx.events} />
        </section>
      </PageLayout>

      {asString(sp.pip) && (
        <WaybillDetailDrawer
          waybillId={wb.id}
          domain={ctx.domain}
          pipKey={asString(sp.pip)!}
          currentStage={wb.current_stage}
          events={ctx.events}
          amountTHB={wb.total_amount ? parseFloat(wb.total_amount) : null}
        />
      )}
    </>
  );
}

function EventTimeline({ events }: { events: WaybillEventRow[] }) {
  if (events.length === 0) {
    return <p className="text-xs text-slate-500">No events recorded yet.</p>;
  }
  return (
    <ol className="space-y-1.5 border-l-2 border-slate-800 pl-4">
      {events.map((e) => (
        <li key={e.id} className="text-xs">
          <span className="font-mono text-cyan-300">#{e.sequence}</span>{' '}
          <span className="font-mono text-slate-400">{e.kind}</span>{' '}
          {e.stage_from && e.stage_to && (
            <span className="font-mono text-slate-500">
              {e.stage_from} → {e.stage_to}
            </span>
          )}
          <span className="ml-2 text-slate-500">
            {e.occurred_at instanceof Date
              ? e.occurred_at.toLocaleString()
              : new Date(e.occurred_at).toLocaleString()}
          </span>
          {e.payload && (
            <pre className="mt-1 overflow-auto rounded bg-slate-950 p-2 text-[10px] text-slate-300">
              {JSON.stringify(e.payload, null, 2)}
            </pre>
          )}
        </li>
      ))}
    </ol>
  );
}
