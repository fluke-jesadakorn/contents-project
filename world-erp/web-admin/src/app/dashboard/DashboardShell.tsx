'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { MobileNav } from '@/components/MobileNav';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import { ROOT_CRUMB } from '@/components/breadcrumbs';

interface DashboardShellProps {
  users: any[];
  currentUser: any | null;
  summary: any | null;
  kindLabel: string;
  tagline: string;
  breadcrumbCurrentRole?: string;
  breadcrumbFullname?: string;
}

export function DashboardShell({
  users: _users,
  currentUser,
  summary,
  kindLabel,
  tagline,
}: DashboardShellProps) {
  const [openMobile, setOpenMobile] = useState(false);

  return (
    <>
      <BreadcrumbSetter crumbs={[ROOT_CRUMB, { label: 'Dashboard' }]} />
      <MobileNav
        open={openMobile}
        onClose={() => setOpenMobile(false)}
        role={currentUser?.role_name}
        currentUser={currentUser}
      />

      <PageLayout
        title={kindLabel}
        subtitle={tagline}
      >
        <div className="flex items-center gap-3 mb-6 text-[12px] text-slate-400">
          <Link href="/" className="hover:text-white transition-colors">← Tiles</Link>
          <span className="text-slate-700">·</span>
          <Link href="/" className="hover:text-white transition-colors">Workspace</Link>
        </div>

        {!summary && (
          <div className="flex justify-center items-center py-10 glass-panel rounded-2xl border-amber-500/20">
            <span className="ml-3 text-xs font-mono text-slate-300">
              {currentUser ? 'No dashboard view for this role.' : 'Sign in to view a dashboard.'}
            </span>
          </div>
        )}

        {summary?.kind === 'it' && <ITDashboard summary={summary.summary} />}
        {summary?.kind === 'exec' && <ExecDashboard summary={summary.summary} />}
        {summary?.kind === 'hod' && <HODDashboard summary={summary.summary} />}
        {summary?.kind === 'am' && <AMDashboard summary={summary.summary} />}
        {summary?.kind === 'reviewer' && <ReviewerDashboard summary={summary.summary} />}
        {summary?.kind === 'hr' && <HRDashboard summary={summary.summary} />}
        {summary?.kind === 'finance' && <FinanceDashboard summary={summary.summary} />}
        {summary?.kind === 'staff' && <StaffDashboard summary={summary.summary} />}
      </PageLayout>
    </>
  );
}

const fmtTHB = (n: number | null | undefined) =>
  Number(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
const fmtTHB2 = (n: number | null | undefined) =>
  Number(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const STAGES_ORDER = [
  'ocr_extracted',
  'accountant_reviewed',
  'head_review',
  'accounting_review',
  'cfo_review',
  'ceo_review',
  'finance_review',
];
const STAGE_LABEL: Record<string, string> = {
  ocr_extracted: 'OCR',
  accountant_reviewed: 'Acct OK',
  head_review: 'HoD',
  accounting_review: 'AM',
  cfo_review: 'CFO',
  ceo_review: 'CEO',
  finance_review: 'Finance',
};

function Cell({
  tone,
  label,
  value,
  sub,
}: {
  tone: 'amber' | 'rose' | 'emerald' | 'indigo' | 'cyan';
  label: string;
  value: React.ReactNode;
  sub: string;
}) {
  const map: Record<string, string> = {
    amber:   'border-amber-500/30 from-amber-500/10 to-transparent',
    rose:    'border-rose-500/30 from-rose-500/10 to-transparent',
    emerald: 'border-emerald-500/30 from-emerald-500/10 to-transparent',
    indigo:  'border-indigo-500/30 from-indigo-500/10 to-transparent',
    cyan:    'border-cyan-500/30 from-cyan-500/10 to-transparent',
  };
  const dot: Record<string, string> = {
    amber: 'bg-amber-400',
    rose: 'bg-rose-400',
    emerald: 'bg-emerald-400',
    indigo: 'bg-indigo-400',
    cyan: 'bg-cyan-400',
  };
  return (
    <div
      className={`glass-panel rounded-2xl px-4 py-3 border bg-gradient-to-br ${map[tone]} flex items-start gap-3`}
    >
      <div className={`w-2 h-2 mt-1.5 rounded-full ${dot[tone]}`} />
      <div className="min-w-0 flex-1">
        <div className="text-[10px] uppercase tracking-widest font-mono text-slate-400 truncate">
          {label}
        </div>
        <div className="text-base font-bold text-white truncate">{value}</div>
        <div className="text-[10px] font-mono text-slate-500 truncate">{sub}</div>
      </div>
    </div>
  );
}

function HealthCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: React.ReactNode;
  sub: string;
  tone?: 'emerald' | 'amber' | 'rose' | 'indigo';
}) {
  return (
    <div className="rounded-2xl bg-slate-950/40 border border-slate-800/70 p-4">
      <div className="text-[10px] uppercase tracking-widest text-slate-400 font-mono">
        {label}
      </div>
      <div className="text-2xl font-black text-white mt-1 font-mono">{value}</div>
      <div className="text-[10px] font-mono text-slate-500 mt-1">{sub}</div>
    </div>
  );
}

function byStatus(rows: any[], status: string): number {
  return Number(rows.find((r: any) => r.status === status)?.n ?? 0);
}

function ITDashboard({ summary }: { summary: any }) {
  const inv = summary.invocations24h;
  const t = summary.transport;
  const providers = summary.providers as any[];
  const models = summary.models as any[];
  const staff = summary.staff as any[];
  const recent = summary.recent as any[];

  const providersOnline = providers.filter((p) => p.enabled).length;
  const modelsTotal = models.length;
  const modelsEnabled = models.filter((m) => m.enabled).length;
  const staffActive = staff.filter((s) => s.enabled).length;
  const errRate = inv.calls > 0 ? Math.round((inv.errors / inv.calls) * 100) : 0;

  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
        <Cell tone="indigo" label="Providers" value={`${providersOnline} / ${providers.length}`} sub="online / total" />
        <Cell tone="emerald" label="Models enabled" value={`${modelsEnabled} / ${modelsTotal}`} sub="across all providers" />
        <Cell tone="amber" label="AI Staff" value={`${staffActive} / ${staff.length}`} sub="active agents" />
        <Cell
          tone={errRate > 5 ? 'rose' : 'emerald'}
          label={`Calls (24h)`}
          value={inv.calls.toLocaleString()}
          sub={`${inv.errors} errors · avg ${Math.round(inv.avg_latency)}ms · p95 ${inv.p95Latency}ms`}
        />
        <Cell tone="cyan" label="Coverage" value={`${providers.length + models.length} entries`} sub="providers + models" />
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">
            Config summary — AI providers & models
          </h2>
          <span className="text-[10px] font-mono text-slate-500">
            {providers.length} providers · {models.length} models · {staff.length} staff
          </span>
        </header>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="rounded-2xl bg-slate-950/50 border border-slate-800/70 p-4">
            <div className="text-[11px] uppercase tracking-wider font-mono text-slate-400 mb-3">Providers</div>
            <ul className="space-y-2">
              {providers.map((p) => (
                <li key={p.id} className="flex items-center gap-3 text-xs">
                  <span className={`w-1.5 h-1.5 rounded-full ${p.enabled ? 'bg-emerald-400' : 'bg-slate-600'}`} />
                  <span className="font-bold text-white w-28 truncate">{p.name}</span>
                  <span className="text-[10px] font-mono text-slate-500 w-20 truncate">{p.type}</span>
                  <span className="text-[10px] font-mono text-slate-400 flex-1 truncate" title={p.base_url}>
                    {p.base_url}
                  </span>
                  <span className="text-[10px] font-mono text-slate-300 w-20 text-right">
                    {p.models_enabled}/{p.models_total} models
                  </span>
                </li>
              ))}
              {providers.length === 0 && (
                <li className="text-xs text-slate-500 font-mono">no providers configured</li>
              )}
            </ul>
          </div>

          <div className="rounded-2xl bg-slate-950/50 border border-slate-800/70 p-4">
            <div className="text-[11px] uppercase tracking-wider font-mono text-slate-400 mb-3">AI Staff</div>
            <ul className="space-y-2">
              {staff.map((s) => (
                <li key={s.id} className="flex items-center gap-3 text-xs">
                  <span className={`w-1.5 h-1.5 rounded-full ${s.enabled ? 'bg-emerald-400' : 'bg-slate-600'}`} />
                  <span className="font-bold text-white truncate">{s.name}</span>
                  <span className="text-[10px] font-mono text-slate-500 truncate">{s.role_label || ''}</span>
                  <span className="ml-auto text-[10px] font-mono text-slate-300">
                    {s.active_assignments} active assignments
                  </span>
                </li>
              ))}
              {staff.length === 0 && (
                <li className="text-xs text-slate-500 font-mono">no AI staff registered</li>
              )}
            </ul>
          </div>
        </div>
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">
            System health
          </h2>
          <span className="text-[10px] font-mono text-slate-500">
            live snapshot
          </span>
        </header>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <HealthCard
            label="Database"
            value={`${t.dbLatencyMs} ms`}
            sub={`SELECT 1 round-trip`}
            tone={t.dbLatencyMs < 50 ? 'emerald' : t.dbLatencyMs < 200 ? 'amber' : 'rose'}
          />
          <HealthCard
            label="Domain events"
            value={`${t.events24h}`}
            sub="last 24h"
            tone="indigo"
          />
          <HealthCard
            label="Notifications backlog"
            value={`${t.notificationsBacklog}`}
            sub="unread rows"
            tone={t.notificationsBacklog > 50 ? 'amber' : 'emerald'}
          />
        </div>
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">
            Recent invocations
          </h2>
          <span className="text-[10px] font-mono text-slate-500">latest 20</span>
        </header>
        <div className="overflow-x-auto">
          <table className="min-w-[700px] w-full text-[11px] font-mono">
            <thead className="text-[9px] uppercase tracking-widest text-slate-500 border-b border-slate-800">
              <tr>
                <th className="text-left py-2 pr-3">section</th>
                <th className="text-left py-2 pr-3">task</th>
                <th className="text-left py-2 pr-3">provider / model</th>
                <th className="text-left py-2 pr-3">staff</th>
                <th className="text-right py-2 pr-3">latency</th>
                <th className="text-left py-2 pr-3">status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-900">
              {recent.map((r) => (
                <tr key={r.id} className="text-slate-200">
                  <td className="py-2 pr-3 text-indigo-300 font-bold">{r.section_key}</td>
                  <td className="py-2 pr-3 text-slate-400">{r.task_type}</td>
                  <td className="py-2 pr-3 truncate max-w-[200px]">
                    {r.provider_name || '—'} <span className="text-slate-500">/</span> {r.model_name || '—'}
                  </td>
                  <td className="py-2 pr-3 text-slate-400 truncate max-w-[120px]">{r.staff_name || '—'}</td>
                  <td className="py-2 pr-3 text-right">
                    {r.latency_ms != null ? `${r.latency_ms} ms` : '—'}
                  </td>
                  <td className="py-2 pr-3">
                    <span className={
                      'px-1.5 py-0.5 rounded text-[9px] font-bold border ' + (
                        r.status === 'error'
                          ? 'bg-rose-500/10 text-rose-300 border-rose-500/30'
                          : r.status === 'ok'
                          ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30'
                          : 'bg-slate-500/10 text-slate-300 border-slate-500/30'
                      )
                    }>
                      {r.status}
                    </span>
                  </td>
                </tr>
              ))}
              {recent.length === 0 && (
                <tr>
                  <td colSpan={6} className="py-6 text-center text-slate-500">
                    no invocations yet
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      {inv.bySection && inv.bySection.length > 0 && (
        <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
          <header className="flex items-baseline justify-between mb-4">
            <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">
              Calls per section (24h)
            </h2>
          </header>
          <ul className="space-y-2">
            {(inv.bySection as any[]).map((s) => {
              const max = inv.bySection[0]?.calls || 1;
              const pct = Math.round((s.calls / max) * 100);
              const errPct = s.calls > 0 ? Math.round((s.errors / s.calls) * 100) : 0;
              return (
                <li key={s.section_key} className="flex items-center gap-3 text-xs">
                  <span className="w-32 sm:w-44 font-mono text-indigo-300 truncate">{s.section_key}</span>
                  <div className="flex-1 h-2 rounded bg-slate-900 overflow-hidden">
                    <div
                      className="h-full bg-gradient-to-r from-indigo-500 to-purple-500"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span className="font-mono text-slate-200 w-20 text-right">{s.calls}</span>
                  <span className={
                    'font-mono w-16 text-right ' + (
                      errPct > 5 ? 'text-rose-300' : 'text-emerald-300'
                    )
                  }>
                    {errPct}% err
                  </span>
                  <span className="font-mono text-slate-500 w-24 text-right">{s.avg_latency}ms</span>
                </li>
              );
            })}
          </ul>
        </section>
      )}
    </>
  );
}

function ExecDashboard({ summary }: { summary: any }) {
  const k = summary.kpis || {};
  const cf = summary.cashflow || {};
  const tb = summary.trialBalance || { debit: 0, credit: 0, isBalanced: true };
  const pipeline = (summary.pipeline || []) as any[];

  const flowRows = [
    { label: 'Customer receipts', value: cf.customerReceipts || 0 },
    { label: 'Employee reimbursements (paid)', value: -(cf.employeeReimbursementsPaid || 0) },
    { label: 'Other inflows', value: cf.otherInflows || 0 },
    { label: 'Other outflows', value: -(cf.otherOutflows || 0) },
  ];
  const flowMax = Math.max(1, ...flowRows.map((r) => Math.abs(r.value)));

  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <Cell tone="indigo" label="Net cash" value={`${fmtTHB(cf.netCashFlow)} THB`} sub="MTD inflows − outflows" />
        <Cell tone="emerald" label="M.T.D. expenses" value={`${fmtTHB(k.mtdExpenses)} THB`} sub="expense accounts" />
        <Cell tone="amber" label="Outstanding liab." value={`${fmtTHB(k.outstandingLiabilities)} THB`} sub="accrued & payable" />
        <Cell tone={tb.isBalanced ? 'emerald' : 'rose'} label="Trial balance" value={tb.isBalanced ? 'BALANCED' : 'MISMATCH'} sub={`Dr ${fmtTHB(tb.debit)} · Cr ${fmtTHB(tb.credit)}`} />
      </section>

      <section className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <div className="glass-panel rounded-3xl p-5 sm:p-7 border-slate-800/80">
          <header className="flex items-baseline justify-between mb-4">
            <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Trial balance</h2>
            <span className="text-[10px] font-mono text-slate-500">double-entry check</span>
          </header>
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-2xl bg-slate-950/40 border border-slate-800/70 p-4">
              <div className="text-[10px] uppercase tracking-widest text-slate-400 font-mono">Debits</div>
              <div className="text-2xl font-black text-emerald-300 font-mono mt-1">{fmtTHB2(tb.debit)} THB</div>
            </div>
            <div className="rounded-2xl bg-slate-950/40 border border-slate-800/70 p-4">
              <div className="text-[10px] uppercase tracking-widest text-slate-400 font-mono">Credits</div>
              <div className="text-2xl font-black text-indigo-300 font-mono mt-1">{fmtTHB2(tb.credit)} THB</div>
            </div>
          </div>
          <div className="mt-4">
            {tb.isBalanced ? (
              <span className="px-3 py-1.5 inline-flex items-center gap-2 text-xs font-bold rounded-full bg-emerald-500/10 text-emerald-300 border border-emerald-500/30">
                <span>⚖️</span> Double-entry balanced
              </span>
            ) : (
              <span className="px-3 py-1.5 inline-flex items-center gap-2 text-xs font-bold rounded-full bg-rose-500/10 text-rose-300 border border-rose-500/30 animate-pulse">
                <span>🚨</span> Unbalanced discrepancy
              </span>
            )}
          </div>
        </div>

        <div className="glass-panel rounded-3xl p-5 sm:p-7 border-slate-800/80">
          <header className="flex items-baseline justify-between mb-4">
            <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Cash-flow (lifetime)</h2>
            <span className="text-[10px] font-mono text-slate-500">net {fmtTHB(cf.netCashFlow)} THB</span>
          </header>
          <ul className="space-y-2">
            {flowRows.map((r) => {
              const pct = Math.round((Math.abs(r.value) / flowMax) * 100);
              const tone = r.value >= 0 ? 'from-emerald-500 to-teal-500' : 'from-rose-500 to-pink-500';
              return (
                <li key={r.label} className="flex items-center gap-3 text-xs">
                  <span className="w-40 sm:w-56 font-sans text-slate-300 truncate">{r.label}</span>
                  <div className="flex-1 h-2 rounded bg-slate-900 overflow-hidden">
                    <div className={`h-full bg-gradient-to-r ${tone}`} style={{ width: `${pct}%` }} />
                  </div>
                  <span className="font-mono text-slate-200 w-24 text-right">{fmtTHB(r.value)} THB</span>
                </li>
              );
            })}
          </ul>
          <div className="mt-4 grid grid-cols-2 gap-2 text-[10px] font-mono text-slate-500">
            <div>Inflows · <span className="text-emerald-300 font-bold">{fmtTHB(cf.totalInflows)} THB</span></div>
            <div className="text-right">
              Outflows · <span className="text-rose-300 font-bold">{fmtTHB(cf.totalOutflows)} THB</span>
            </div>
          </div>
        </div>
      </section>

      {pipeline.length > 0 && (
        <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
          <header className="flex items-baseline justify-between mb-4">
            <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Approval pipeline</h2>
            <span className="text-[10px] font-mono text-slate-500">
              {pipeline.reduce((s, x) => s + Number(x.count), 0)} items open
            </span>
          </header>
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
            {STAGES_ORDER.map((stage) => {
              const row = pipeline.find((p) => p.status === stage);
              const n = row ? Number(row.count) : 0;
              return (
                <div key={stage} className="rounded-2xl bg-slate-950/40 border border-slate-800/70 p-3">
                  <div className="text-[9px] uppercase font-mono text-slate-500 tracking-widest">{STAGE_LABEL[stage]}</div>
                  <div className="text-2xl font-black text-white mt-1 font-mono">{n}</div>
                </div>
              );
            })}
          </div>
        </section>
      )}
    </>
  );
}

function HODDashboard({ summary }: { summary: any }) {
  const c = summary.counts || {};
  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <Cell tone="amber" label={`Head review (${summary.dept_group_name ?? summary.department})`} value={c.head_review ?? 0} sub={`${c.total_in_dept ?? 0} total dept`} />
        <Cell tone="indigo" label="Upstream (AM/CFO)" value={c.upstream ?? 0} sub="waiting for upstream" />
        <Cell tone="emerald" label="Settled" value={c.settled ?? 0} sub="approved or paid" />
        <Cell tone="indigo" label="M.T.D. spend (dept)" value={`${fmtTHB(summary.mtdSpend)} THB`} sub={`${summary.dept_group_name ?? summary.department}`} />
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Department queue</h2>
          <Link href="/" className="text-[10px] font-mono text-indigo-300 hover:text-indigo-200">
            Open workspace →
          </Link>
        </header>
        <ul className="space-y-2">
          {(summary.queue as any[]).map((e) => (
            <li key={e.id} className="flex items-center gap-3 text-xs px-3 py-2.5 rounded-xl bg-slate-950/40 border border-slate-800/70">
              <span className="px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-300 border border-amber-500/30 text-[9px] font-mono font-bold">
                EXP-{e.id}
              </span>
              <span className="text-slate-200 truncate flex-1">{e.vendor_name}</span>
              <span className="font-mono text-emerald-300 w-24 text-right">{fmtTHB(e.total_amount)} THB</span>
              <span className="text-[10px] font-mono text-slate-500 w-24 text-right truncate">{e.submitter_name}</span>
            </li>
          ))}
          {summary.queue.length === 0 && (
            <li className="text-xs text-slate-500 font-mono py-6 text-center">nothing waiting at your department</li>
          )}
        </ul>
      </section>
    </>
  );
}

function AMDashboard({ summary }: { summary: any }) {
  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <Cell tone="cyan" label="Accounting review" value={byStatus(summary.queueByStage, 'accounting_review')} sub="awaiting your action" />
        <Cell tone="indigo" label="CFO review" value={byStatus(summary.queueByStage, 'cfo_review')} sub="upstream" />
        <Cell tone="emerald" label="Accountant OK" value={byStatus(summary.queueByStage, 'accountant_reviewed')} sub="ready to settle" />
        <Cell tone={summary.corruptedOpen > 0 ? 'rose' : 'emerald'} label="Corrupted open" value={summary.corruptedOpen} sub="math mismatch flagged" />
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Reconciliation</h2>
          <Link href="/" className="text-[10px] font-mono text-indigo-300 hover:text-indigo-200">
            Open workspace →
          </Link>
        </header>
        <p className="text-xs text-slate-400 font-mono">
          Items that have passed accountant review and are ready for the next approval — verify the GL line numbers match before approving
        </p>
        <div className="mt-4 grid grid-cols-2 sm:grid-cols-5 gap-2">
          {STAGES_ORDER.map((s) => {
            const n = byStatus(summary.queueByStage, s);
            return (
              <div key={s} className="rounded-xl bg-slate-950/40 border border-slate-800/70 p-3">
                <div className="text-[9px] uppercase font-mono text-slate-500 tracking-widest">{STAGE_LABEL[s]}</div>
                <div className="text-xl font-black text-white mt-1 font-mono">{n}</div>
              </div>
            );
          })}
        </div>
      </section>
    </>
  );
}

function ReviewerDashboard({ summary }: { summary: any }) {
  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-3 gap-3 mb-6">
        <Cell tone="amber" label="OCR queue" value={summary.ocrQueue} sub="awaiting first review" />
        <Cell tone={summary.corruptedOpen > 0 ? 'rose' : 'emerald'} label="Corrupted open" value={summary.corruptedOpen} sub="math mismatch flagged" />
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Next steps</h2>
          <Link href="/" className="text-[10px] font-mono text-indigo-300 hover:text-indigo-200">
            Open workspace →
          </Link>
        </header>
        <ul className="text-xs text-slate-300 list-disc pl-5 space-y-1.5">
          <li>Review receipts in the OCR queue and map the chart of accounts using AI suggestions</li>
          <li>Fix corrupted items before approving</li>
          <li>Use COA Search (semantic) to find an account code matching the new description</li>
        </ul>
      </section>
    </>
  );
}

function HRDashboard({ summary }: { summary: any }) {
  const u = summary.users || {};
  const byRole = summary.byRole as Array<{ role: string; n: number }>;
  const max = byRole.reduce((m, r) => Math.max(m, r.n), 0) || 1;
  const hygieneTone = summary.unassigned > 0 || summary.deptless > 0 ? 'amber' : 'emerald';

  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <Cell tone="indigo" label="Users" value={u.total ?? 0} sub={`${u.active ?? 0} active · ${u.inactive ?? 0} inactive`} />
        <Cell tone="emerald" label="Active departments" value={summary.activeDepartments ?? 0} sub="currently in use" />
        <Cell tone={hygieneTone} label="Needs attention" value={(summary.unassigned ?? 0) + (summary.deptless ?? 0)} sub={`${summary.unassigned ?? 0} no manager · ${summary.deptless ?? 0} no dept`} />
        <Cell tone="indigo" label="Role coverage" value={byRole.length} sub="distinct roles with active users" />
      </section>

      <section className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <div className="glass-panel rounded-3xl p-5 sm:p-7 border-slate-800/80">
          <header className="flex items-baseline justify-between mb-4">
            <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Active users by role</h2>
            <Link href="/" className="text-[10px] font-mono text-indigo-300 hover:text-indigo-200">
              Open HR workspace →
            </Link>
          </header>
          <ul className="space-y-2">
            {byRole.map((r) => {
              const pct = Math.round((r.n / max) * 100);
              return (
                <li key={r.role} className="flex items-center gap-3 text-xs">
                  <span className="w-40 font-mono text-slate-300 truncate">{r.role}</span>
                  <div className="flex-1 h-2 rounded bg-slate-900 overflow-hidden">
                    <div
                      className="h-full bg-gradient-to-r from-indigo-500 to-purple-500"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span className="font-mono text-slate-200 w-10 text-right">{r.n}</span>
                </li>
              );
            })}
            {byRole.length === 0 && (
              <li className="text-xs text-slate-500 font-mono py-6 text-center">no users yet</li>
            )}
          </ul>
        </div>

        <div className="glass-panel rounded-3xl p-5 sm:p-7 border-slate-800/80">
          <header className="flex items-baseline justify-between mb-4">
            <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Recent user activity</h2>
          </header>
          <ul className="space-y-2">
            {(summary.recent as any[]).map((row) => (
              <li key={row.id} className="flex items-center gap-3 text-xs px-3 py-2.5 rounded-xl bg-slate-950/40 border border-slate-800/70">
                <span className="px-1.5 py-0.5 rounded bg-indigo-500/10 text-indigo-300 border border-indigo-500/30 text-[9px] font-mono font-bold">
                  {row.employee_code}
                </span>
                <span className="text-slate-200 truncate flex-1">{row.fullname}</span>
                <span className="text-[10px] font-mono text-slate-500 w-28 truncate text-right">{row.role_name}</span>
<span className="text-[10px] font-mono text-slate-500 w-20 truncate text-right">
                    {row.dept_group_name ?? row.department ?? '—'}
                  </span>
              </li>
            ))}
            {summary.recent.length === 0 && (
              <li className="text-xs text-slate-500 font-mono py-6 text-center">no users yet</li>
            )}
          </ul>
        </div>
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Next steps</h2>
        </header>
        <ul className="text-xs text-slate-300 list-disc pl-5 space-y-1.5">
          <li>Open the HR Workspace to manage users, roles, departments, and the org chart</li>
          <li>Reassign direct reports when employees change teams or leave</li>
          {summary.unassigned > 0 && (
            <li className="text-amber-300">
              {summary.unassigned} active user{summary.unassigned === 1 ? '' : 's'} {summary.unassigned === 1 ? 'has' : 'have'} no manager — assign one to unblock approvals
            </li>
          )}
          {summary.deptless > 0 && (
            <li className="text-amber-300">
              {summary.deptless} active user{summary.deptless === 1 ? '' : 's'} {summary.deptless === 1 ? 'is' : 'are'} missing a department — set one to enable scoping
            </li>
          )}
        </ul>
      </section>
    </>
  );
}

function StaffDashboard({ summary }: { summary: any }) {
  const t = summary.totals || {};
  const bs = (summary.byStatus || []) as any[];
  const open = bs.filter((b) => !['paid', 'rejected'].includes(b.status)).reduce((s, x) => s + x.n, 0);
  const closed = bs.filter((b) => ['paid', 'approved'].includes(b.status)).reduce((s, x) => s + x.n, 0);
  const rejected = bs.find((b) => b.status === 'rejected')?.n ?? 0;

  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <Cell tone="indigo" label="Total submissions" value={t.total ?? 0} sub="lifetime" />
        <Cell tone="amber" label="Open" value={open} sub="still in pipeline" />
        <Cell tone="emerald" label="Settled" value={closed} sub="approved / paid" />
        <Cell tone="rose" label="Rejected" value={rejected} sub="declined" />
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Spending snapshot</h2>
          <Link href="/" className="text-[10px] font-mono text-indigo-300 hover:text-indigo-200">
            Open workspace →
          </Link>
        </header>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="rounded-2xl bg-slate-950/40 border border-slate-800/70 p-4">
            <div className="text-[10px] uppercase tracking-widest text-slate-400 font-mono">M.T.D.</div>
            <div className="text-3xl font-black text-emerald-300 font-mono mt-1">{fmtTHB(t.mtd_amount)} THB</div>
          </div>
          <div className="rounded-2xl bg-slate-950/40 border border-slate-800/70 p-4">
            <div className="text-[10px] uppercase tracking-widest text-slate-400 font-mono">Lifetime</div>
            <div className="text-3xl font-black text-indigo-300 font-mono mt-1">{fmtTHB(t.lifetime_amount)} THB</div>
          </div>
        </div>
      </section>
    </>
  );
}

function FinanceDashboard({ summary }: { summary: any }) {
  const pending = byStatus(summary.queueByStage, 'finance_review');
  const paidCount = byStatus(summary.queueByStage, 'paid');

  return (
    <>
      <section className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <Cell tone="emerald" label="Pending Disbursement" value={pending} sub="awaiting your action" />
        <Cell tone="indigo" label="Value Pending" value={`${fmtTHB(summary.valuePending)} THB`} sub="total in queue" />
        <Cell tone="emerald" label="Paid Today" value={summary.paidTodayCount ?? 0} sub={`${fmtTHB(summary.paidTodayValue)} THB`} />
        <Cell tone="cyan" label="Lifetime Paid" value={paidCount} sub="disbursed" />
      </section>

      <section className="glass-panel rounded-3xl p-5 sm:p-7 mb-8 border-slate-800/80">
        <header className="flex items-baseline justify-between mb-4">
          <h2 className="text-sm font-black text-white tracking-wide uppercase font-mono">Recent activity</h2>
          <Link href="/" className="text-[10px] font-mono text-indigo-300 hover:text-indigo-200">
            Open workspace →
          </Link>
        </header>
        <ul className="space-y-2">
          {(summary.recent as any[]).map((row) => (
            <li
              key={row.id}
              className="flex items-center gap-3 text-xs px-3 py-2.5 rounded-xl bg-slate-950/40 border border-slate-800/70"
            >
              <span className="px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-300 border border-emerald-500/30 text-[9px] font-mono font-bold">
                EXP-{row.id}
              </span>
              <span className="text-slate-200 truncate flex-1">{row.vendor_name}</span>
              <span className="font-mono text-emerald-300 w-24 text-right">{fmtTHB(row.total_amount)} THB</span>
              <span className="text-[10px] font-mono text-slate-500 w-24 text-right truncate">
                {row.submitter_name}
              </span>
            </li>
          ))}
          {summary.recent.length === 0 && (
            <li className="text-xs text-slate-500 font-mono py-6 text-center">nothing yet</li>
          )}
        </ul>
      </section>
    </>
  );
}
