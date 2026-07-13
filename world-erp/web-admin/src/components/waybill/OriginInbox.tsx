import React from 'react';
import Link from 'next/link';
import { query } from '@/lib/db';
import { WaybillChip } from './WaybillChip';
import { ApproverChip } from './ApproverChip';
import type { ApproverSummary } from '@/lib/server/waybill';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import { stageRoles } from '@erp-lib/waybill/derive';
import { normalizeStage } from '@erp-lib/perm/stages';
import { roleDisplay } from './ui';
import { Bilingual } from '@/components/i18n/Bilingual';
import { getSecondaryLocale, type SecondaryLocale } from '@erp-lib/server/locale';

type Origin = 'expense' | 'pr' | 'po';
type Scope = 'mine' | 'queue' | 'all';

export interface OriginInboxProps {
  originFilter: Origin;
  pageTitle: string;
  pageSubtitle: string;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
  actorId: number;
  actorRole: string | null;
  newExpensePanel?: React.ReactNode;
}

const ORIGIN_LABEL: Record<Origin, string> = {
  expense: 'Expense',
  pr: 'PR',
  po: 'PO',
};

const ORIGIN_GLYPH: Record<Origin, string> = {
  expense: '🧾',
  pr: '📦',
  po: '🚚',
};

function asScope(v: string | string[] | undefined, fallback: Scope): Scope {
  const raw = Array.isArray(v) ? v[0] : v;
  return raw === 'mine' || raw === 'queue' || raw === 'all' ? raw : fallback;
}

interface InboxRow {
  id: string;
  origin: Origin;
  origin_id: number;
  vendor_name: string | null;
  total_amount: string | null;
  currency: string;
  current_stage: string;
  status: string;
  submitter_name: string | null;
  age_hours: number;
}

interface UserLite {
  id: number;
  fullname: string;
  role_id: string | null;
}

async function listInbox(
  origin: Origin,
  scope: Scope,
  actorId: number,
  isFinance: boolean,
  limit: number,
): Promise<InboxRow[]> {
  if (scope === 'mine') {
    const r = await query<InboxRow>(
      `SELECT w.id, w.origin, w.origin_id, w.vendor_name, w.total_amount, w.currency,
              w.current_stage, w.status, u.fullname AS submitter_name,
              EXTRACT(EPOCH FROM (now() - w.updated_at)) / 3600.0 AS age_hours
         FROM waybills w
    LEFT JOIN users u ON u.id = w.submitter_id
        WHERE w.submitter_id = $1
          AND w.origin = $2
          AND w.status NOT IN ('completed', 'reversed', 'superseded')
     ORDER BY w.updated_at DESC
        LIMIT $3`,
      [actorId, origin, limit],
    );
    return r.rows;
  }
  if (scope === 'queue') {
    const r = await query<InboxRow>(
      `SELECT w.id, w.origin, w.origin_id, w.vendor_name, w.total_amount, w.currency,
              w.current_stage, w.status, u.fullname AS submitter_name,
              EXTRACT(EPOCH FROM (now() - w.updated_at)) / 3600.0 AS age_hours
         FROM waybills w
    LEFT JOIN users u ON u.id = w.submitter_id
    LEFT JOIN users actor ON actor.id = $1
        WHERE w.origin = $2
          AND w.status NOT IN ('completed', 'reversed', 'superseded')
          AND (
            $4::bool = true
            OR (actor.dept_id IS NOT NULL
                AND u.dept_id = actor.dept_id
                AND w.current_stage IN ('submission','dept_verification','dept_authorization'))
          )
     ORDER BY w.updated_at DESC
        LIMIT $3`,
      [actorId, origin, limit, isFinance],
    );
    return r.rows;
  }
  const r = await query<InboxRow>(
    `SELECT w.id, w.origin, w.origin_id, w.vendor_name, w.total_amount, w.currency,
            w.current_stage, w.status, u.fullname AS submitter_name,
            EXTRACT(EPOCH FROM (now() - w.updated_at)) / 3600.0 AS age_hours
       FROM waybills w
  LEFT JOIN users u ON u.id = w.submitter_id
      WHERE w.origin = $1
        AND w.status NOT IN ('completed', 'reversed', 'superseded')
   ORDER BY w.updated_at DESC
      LIMIT $2`,
    [origin, limit],
  );
  return r.rows;
}

async function loadUserMap(): Promise<Map<number, UserLite>> {
  const r = await query<UserLite>(
    `SELECT u.id,
            u.fullname,
            (
              SELECT pr.id FROM perm.user_roles ur
                JOIN perm.roles pr ON pr.id = ur.role_id AND pr.kind = 'persona'
               WHERE ur.user_id = u.id
            ORDER BY pr.sort_order ASC LIMIT 1
            ) AS role_id
       FROM users u
      WHERE u.is_active = true`,
  );
  const out = new Map<number, UserLite>();
  for (const row of r.rows) out.set(row.id, row);
  return out;
}

function buildSummary(
  stage: string,
  users: Map<number, UserLite>,
  locale: SecondaryLocale,
): ApproverSummary | null {
  const roles = stageRoles(stage);
  if (roles.length === 0) return null;
  const roleKey = roles[0];
  const teamRoles = new Set([
    'account_officer',
    'account_supervisor',
    'accounting_manager',
    'finance',
  ]);
  const privacy: 'named' | 'team' = teamRoles.has(roleKey) ? 'team' : 'named';
  const names: string[] = [];
  for (const u of users.values()) {
    if (u.role_id != null && roles.includes(u.role_id)) names.push(u.fullname);
  }
  return {
    role: roleKey,
    role_label: roleDisplay(roleKey, locale),
    privacy,
    count: names.length,
    names: privacy === 'team' ? [] : names.slice(0, 1),
  };
}

export async function OriginInbox({
  originFilter,
  pageTitle,
  pageSubtitle,
  searchParams,
  actorId,
  actorRole,
  newExpensePanel,
}: OriginInboxProps) {
  const sp = await searchParams;
  const scope = asScope(sp.scope, originFilter === 'expense' ? 'mine' : 'queue');
  const locale = await getSecondaryLocale();

  const financeRoles = new Set([
    'account_officer',
    'account_supervisor',
    'accounting_manager',
    'finance',
  ]);
  const isFinance = !!actorRole && financeRoles.has(actorRole);

  const [rows, users] = await Promise.all([
    listInbox(originFilter, scope, actorId, isFinance, 100),
    loadUserMap(),
  ]);

  const summaries = new Map<string, ApproverSummary | null>();
  for (const row of rows) {
    const stage = normalizeStage(row.current_stage) ?? row.current_stage;
    summaries.set(row.id, buildSummary(stage, users, locale));
  }

  const tabHref = (s: Scope) => `?scope=${s}`;
  const originHref = (origin: Origin): string =>
    origin === 'expense' ? '/expense' : origin === 'pr' ? '/pr' : '/po';

  return (
    <>
      <BreadcrumbSetter
        crumbs={[
          { label: 'Hub', href: '/' },
          { label: ORIGIN_LABEL[originFilter], href: originHref(originFilter) },
        ]}
      />
      <PageLayout title={pageTitle} subtitle={pageSubtitle}>
        <nav className="mb-4 flex flex-wrap gap-2 text-xs font-mono">
          <Link
            href={tabHref('mine')}
            aria-current={scope === 'mine' ? 'page' : undefined}
            className={
              'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 transition-colors ' +
              (scope === 'mine'
                ? 'border-cyan-500 bg-cyan-500/15 text-cyan-200'
                : 'border-slate-700 text-slate-400 hover:border-slate-500 hover:text-slate-200')
            }
          >
            <span aria-hidden>📤</span>
            <Bilingual en="Mine" th="ของฉัน" de="Meine" locale={locale} />
            {rows.length > 0 && <span className="rounded-full bg-slate-800 px-1.5 text-[10px]">{rows.length}</span>}
          </Link>
          <Link
            href={tabHref('queue')}
            aria-current={scope === 'queue' ? 'page' : undefined}
            className={
              'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 transition-colors ' +
              (scope === 'queue'
                ? 'border-cyan-500 bg-cyan-500/15 text-cyan-200'
                : 'border-slate-700 text-slate-400 hover:border-slate-500 hover:text-slate-200')
            }
          >
            <span aria-hidden>✅</span>
            <Bilingual en="My queue" th="งานรอฉัน" de="Meine Warteschlange" locale={locale} />
          </Link>
          <Link
            href={tabHref('all')}
            aria-current={scope === 'all' ? 'page' : undefined}
            className={
              'inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 transition-colors ' +
              (scope === 'all'
                ? 'border-cyan-500 bg-cyan-500/15 text-cyan-200'
                : 'border-slate-700 text-slate-400 hover:border-slate-500 hover:text-slate-200')
            }
          >
            <span aria-hidden>🌐</span>
            <Bilingual en="All open" th="ทั้งหมดที่เปิดอยู่" de="Alle offenen" locale={locale} />
          </Link>
          <Link
            href="/inbox"
            className="ml-auto inline-flex items-center gap-1.5 rounded-lg border border-slate-700 px-3 py-1.5 font-mono text-slate-400 transition-colors hover:border-slate-500 hover:text-slate-200"
          >
            <span aria-hidden>📥</span>
            <Bilingual en="Inbox" th="กล่องขาเข้า" de="Posteingang" locale={locale} />
          </Link>
        </nav>

        {newExpensePanel && <div className="mb-8">{newExpensePanel}</div>}

        {rows.length > 0 && (
          <>
            <div className="mb-3 flex items-baseline justify-between">
              <h2 className="text-xs font-mono uppercase tracking-widest text-slate-500">
                {scope === 'mine' ? (
                  <Bilingual
                    en={`My other in-flight ${ORIGIN_LABEL[originFilter]} waybills`}
                    th={`${ORIGIN_LABEL[originFilter]} อื่น ๆ ที่กำลังดำเนินการ`}
                    de={`Weitere laufende ${ORIGIN_LABEL[originFilter]}-Belege`}
                    locale={locale}
                  />
                ) : (
                  <Bilingual
                    en={`Open waybills (${rows.length})`}
                    th={`Waybills ที่เปิดอยู่ (${rows.length})`}
                    de={`Offene Belege (${rows.length})`}
                    locale={locale}
                  />
                )}
              </h2>
              <span className="text-[10px] font-mono text-slate-500">
                <Bilingual en="click to open" th="คลิกเพื่อเปิด" de="zum Öffnen klicken" locale={locale} />
              </span>
            </div>
            <ul className="space-y-2">
              {rows.map((row) => {
                const displayStage = normalizeStage(row.current_stage) ?? row.current_stage;
                const domain: 'expense' | 'procurement' =
                  row.origin === 'expense' ? 'expense' : 'procurement';
                const amount = row.total_amount ? parseFloat(row.total_amount) : null;
                const originLabel =
                  row.origin === 'expense'
                    ? `EXP-${row.origin_id}`
                    : row.origin === 'pr'
                    ? `PR-${row.origin_id}`
                    : `PO-${row.origin_id}`;
                const summary = summaries.get(row.id) ?? null;
                const canAct = !!actorRole && stageRoles(displayStage).includes(actorRole);
                return (
                  <li
                    key={row.id}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-slate-800 bg-slate-950/60 p-4"
                  >
                    <div className="min-w-0 flex-1 space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-sm text-cyan-300">{row.id}</span>
                        <WaybillChip
                          domain={domain}
                          currentStage={displayStage}
                          amountTHB={amount}
                        />
                        <ApproverChip
                          summary={summary}
                          view={canAct ? 'can-act' : 'awaiting'}
                        />
                      </div>
                      <div className="text-[11px] text-slate-400">
                        <span aria-hidden className="mr-1">{ORIGIN_GLYPH[row.origin]}</span>
                        {originLabel} · {row.vendor_name ?? '—'} ·{' '}
                        {(amount ?? 0).toLocaleString('th-TH', { minimumFractionDigits: 2 })} {row.currency}
                      </div>
                      <div className="flex flex-wrap gap-x-3 gap-y-1 text-[10px] font-mono text-slate-500">
                        <span>
                          <Bilingual en="submitter:" th="ผู้ส่ง:" de="Einreicher:" locale={locale} />{' '}
                          {row.submitter_name ?? '—'}
                        </span>
                        <span>
                          <Bilingual en={`age ${Math.max(0, Math.floor(row.age_hours))}h`} th={`อายุ ${Math.max(0, Math.floor(row.age_hours))} ชม.`} de={`Alter ${Math.max(0, Math.floor(row.age_hours))} Std.`} locale={locale} />
                        </span>
                        {row.origin === 'expense' && (
                          <ExpenseArtifactsLine expenseId={row.origin_id} />
                        )}
                        {row.origin === 'pr' && <PrArtifactsLine prId={row.origin_id} />}
                        {row.origin === 'po' && <PoArtifactsLine poId={row.origin_id} />}
                      </div>
                    </div>
                    <Link
                      href={`/waybill/${row.id}`}
                      className="rounded-lg border border-cyan-500/40 bg-cyan-500/10 px-3 py-1.5 text-xs font-mono text-cyan-200 hover:bg-cyan-500/20"
                    >
                      <Bilingual en="Open →" th="เปิด →" de="Öffnen →" locale={locale} />
                    </Link>
                  </li>
                );
              })}
            </ul>
          </>
        )}

        {rows.length === 0 && (
          <div className="rounded-2xl border border-dashed border-slate-800 bg-slate-950/40 p-6 text-center text-sm text-slate-500">
            <Bilingual
              en={`No ${ORIGIN_LABEL[originFilter]} waybills in this scope.`}
              th={`ไม่มี ${ORIGIN_LABEL[originFilter]} ในขอบเขตนี้`}
              de={`Keine ${ORIGIN_LABEL[originFilter]}-Belege in diesem Bereich.`}
              locale={locale}
            />
          </div>
        )}
      </PageLayout>
    </>
  );
}

async function ExpenseArtifactsLine({ expenseId }: { expenseId: number }) {
  const r = await query<{
    pr_id: number | null;
    pr_number: string | null;
    po_id: number | null;
    po_number: string | null;
    jv_id: number | null;
  }>(
    `SELECT e.pr_id,
            pr.pr_number,
            e.po_id,
            po.po_number,
            e.journal_entry_id AS jv_id
       FROM expenses e
  LEFT JOIN purchase_requisitions pr ON pr.id = e.pr_id
  LEFT JOIN purchase_orders po ON po.id = e.po_id
      WHERE e.id = $1`,
    [expenseId],
  );
  const row = r.rows[0];
  if (!row) return null;
  return (
    <>
      {row.pr_number && (
        <span className="text-cyan-300">
          PR <Link href={`/pr/${row.pr_id}`} className="hover:underline">{row.pr_number}</Link>
        </span>
      )}
      {row.po_number && (
        <span className="text-cyan-300">
          PO <Link href={`/po/${row.po_id}`} className="hover:underline">{row.po_number}</Link>
        </span>
      )}
      {row.jv_id != null && (
        <span className="text-emerald-300">GL #{row.jv_id}</span>
      )}
    </>
  );
}

async function PrArtifactsLine({ prId }: { prId: number }) {
  const locale = await getSecondaryLocale();
  const r = await query<{ po_count: string }>(
    `SELECT COUNT(*)::text AS po_count FROM purchase_orders WHERE pr_id = $1`,
    [prId],
  );
  const c = r.rows[0]?.po_count ?? '0';
  return (
    <span>
      <Bilingual
        en={`${c} linked POs`}
        th={`${c} PO ที่เชื่อมโยง`}
        de={`${c} verknüpfte Bestellungen`}
        locale={locale}
      />
    </span>
  );
}

async function PoArtifactsLine({ poId }: { poId: number }) {
  const r = await query<{
    pr_id: number;
    pr_number: string | null;
    settled_slip_id: number | null;
    jv_id: number | null;
  }>(
    `SELECT po.pr_id,
            pr.pr_number,
            po.settled_slip_id,
            (SELECT id FROM journal_entries WHERE po_id = po.id ORDER BY id DESC LIMIT 1) AS jv_id
       FROM purchase_orders po
  LEFT JOIN purchase_requisitions pr ON pr.id = po.pr_id
      WHERE po.id = $1`,
    [poId],
  );
  const row = r.rows[0];
  if (!row) return null;
  return (
    <>
      {row.pr_number && (
        <span className="text-cyan-300">
          PR <Link href={`/pr/${row.pr_id}`} className="hover:underline">{row.pr_number}</Link>
        </span>
      )}
      {row.jv_id != null && <span className="text-emerald-300">GL #{row.jv_id}</span>}
      {row.settled_slip_id != null && (
        <span className="text-indigo-300">Slip #{row.settled_slip_id}</span>
      )}
    </>
  );
}
