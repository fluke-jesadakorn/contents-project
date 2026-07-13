import React from 'react';
import Link from 'next/link';
import type {
  ExpenseJournalView,
  JournalLineRow,
  ProcurementJournalStepView,
  ProcurementJournalView,
  SalesJournalView,
  WaybillJournalView,
} from '@/lib/server/waybill';
import { fmtDate, fmtMoney, fmtTs } from './ui';
import { GlVisibilityGate } from './GlVisibilityGate';
import { Bilingual } from '@/components/i18n/Bilingual';
import {
  confirmGlRecordedAction,
  confirmProcurementGlAction,
  confirmSalesGlAction,
  finalApproveWaybillAction,
  postProcurementAccrualAction,
  postProcurementSettlementAction,
  postSalesGlAccrualAction,
  postSalesGlSettlementAction,
  postSalesGlVatAction,
  recomputeExpenseDraftGlAction,
  saveProcurementAccrualAction,
} from '@/app/(protected)/waybill/[id]/_actions';

type Locale = 'th' | 'de';

type Props = {
  waybillId: string;
  origin: 'expense' | 'pr' | 'po' | 'so';
  journal: WaybillJournalView;
  amountTHB?: number | null;
  actorRole: string | null;
  actorCanSeeLines: boolean;
  lang?: Locale;
  canFinalApprove?: boolean;
  canConfirmGl?: boolean;
  isFinalApproval?: boolean;
  isDisbursed?: boolean;
  hasPostedToGl?: boolean;
  hasGlConfirmed?: boolean;
  canSaveAccrual?: boolean;
  canPostAccrual?: boolean;
  canConfirmAccrual?: boolean;
  canPostSettlement?: boolean;
  canConfirmSettlement?: boolean;
  isAccountingAuthorization?: boolean;
  canPostSalesGlVat?: boolean;
  canPostSalesGlAccrual?: boolean;
  canPostSalesGlSettlement?: boolean;
  canConfirmSalesGl?: boolean;
};

function pickAccountName(
  account: { name: string | null; name_th: string | null },
  locale: Locale,
): string {
  const th = account.name_th ?? null;
  const en = account.name ?? null;
  if (locale === 'de') return th ?? en ?? '—';
  if (locale === 'th') return th ?? en ?? '—';
  return en ?? th ?? '—';
}

function LineRow({
  account,
  debit,
  credit,
  description,
  locale,
}: {
  account: { code: string; name: string | null; name_th: string | null };
  debit: number;
  credit: number;
  description: string | null;
  locale: Locale;
}) {
  return (
    <tr className="align-top font-mono text-slate-300">
      <td className="border-b border-slate-800/40 px-2 py-2 text-cyan-300">{account.code}</td>
      <td className="border-b border-slate-800/40 px-2 py-2 text-slate-200">
        {pickAccountName(account, locale)}
      </td>
      <td className="border-b border-slate-800/40 px-2 py-2 text-right text-emerald-200 tabular-nums">
        {debit > 0 ? fmtMoney(debit, '').trim() : ''}
      </td>
      <td className="border-b border-slate-800/40 px-2 py-2 text-right text-amber-200 tabular-nums">
        {credit > 0 ? fmtMoney(credit, '').trim() : ''}
      </td>
      <td className="border-b border-slate-800/40 px-2 py-2 text-slate-500">{description ?? ''}</td>
    </tr>
  );
}

function LinesTable({
  lines,
  locale,
}: {
  lines: JournalLineRow[];
  locale: Locale;
}) {
  if (lines.length === 0) {
    return (
      <p className="rounded-md border border-slate-800/60 bg-slate-950/40 p-3 text-sm italic text-slate-500">
        {<Bilingual en="no ledger lines" th="ไม่มีรายการบัญชี" de="keine Buchungszeilen" locale={locale} />}
      </p>
    );
  }
  const totalDebit = lines.reduce((s, l) => s + l.debit, 0);
  const totalCredit = lines.reduce((s, l) => s + l.credit, 0);
  const balanced = Math.abs(totalDebit - totalCredit) < 0.005;
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse text-xs">
        <thead>
          <tr className="text-left font-mono text-[10px] uppercase tracking-widest text-slate-500">
            <th className="border-b border-slate-800/60 px-2 py-1.5">code</th>
            <th className="border-b border-slate-800/60 px-2 py-1.5">
              {<Bilingual en="account" th="ชื่อบัญชี" de="Konto" locale={locale} />}
            </th>
            <th className="border-b border-slate-800/60 px-2 py-1.5 text-right">
              {<Bilingual en="debit" th="เดบิต" de="Soll" locale={locale} />}
            </th>
            <th className="border-b border-slate-800/60 px-2 py-1.5 text-right">
              {<Bilingual en="credit" th="เครดิต" de="Haben" locale={locale} />}
            </th>
            <th className="border-b border-slate-800/60 px-2 py-1.5">
              {<Bilingual en="description" th="รายละเอียด" de="Beschreibung" locale={locale} />}
            </th>
          </tr>
        </thead>
        <tbody>
          {lines.map((l, i) => (
            <LineRow
              key={i}
              account={{ code: l.account_code, name: l.account_name, name_th: l.account_name_th }}
              debit={l.debit}
              credit={l.credit}
              description={l.description}
              locale={locale}
            />
          ))}
        </tbody>
        <tfoot>
          <tr className="font-mono text-[11px] font-bold uppercase tracking-wider">
            <td className="border-t border-slate-700/60 px-2 py-2 text-slate-400" colSpan={2}>
              {<Bilingual en="total" th="รวม" de="Summe" locale={locale} />}
            </td>
            <td className="border-t border-slate-700/60 px-2 py-2 text-right text-emerald-200 tabular-nums">
              {fmtMoney(totalDebit, '').trim()}
            </td>
            <td className="border-t border-slate-700/60 px-2 py-2 text-right text-amber-200 tabular-nums">
              {fmtMoney(totalCredit, '').trim()}
            </td>
            <td className="border-t border-slate-700/60 px-2 py-2">
              {balanced ? (
                <span className="inline-flex items-center gap-1 rounded-full border border-emerald-500/40 bg-emerald-500/15 px-2 py-0.5 text-emerald-200">
                  <span aria-hidden>✓</span>
                  <span>
                    {<Bilingual en="balanced" th="สมดุล" de="ausgeglichen" locale={locale} />}
                  </span>
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 rounded-full border border-rose-500/40 bg-rose-500/15 px-2 py-0.5 text-rose-200">
                  <span aria-hidden>⚠</span>
                  <span>
                    {<Bilingual en="unbalanced" th="ไม่สมดุล" de="nicht ausgeglichen" locale={locale} />}
                  </span>
                </span>
              )}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}

function summarize(lines: JournalLineRow[]): { totalDebit: number; totalCredit: number; balanced: boolean } {
  const totalDebit = lines.reduce((s, l) => s + l.debit, 0);
  const totalCredit = lines.reduce((s, l) => s + l.credit, 0);
  return { totalDebit, totalCredit, balanced: Math.abs(totalDebit - totalCredit) < 0.005 };
}

function StepHeader({
  stepNo,
  emoji,
  title,
  subtitle,
  locale,
  badges,
  actions,
}: {
  stepNo: 1 | 2 | 3;
  emoji: string;
  title: React.ReactNode;
  subtitle: React.ReactNode;
  locale: Locale;
  badges: React.ReactNode;
  actions?: React.ReactNode;
}) {
  return (
    <header className="flex flex-wrap items-baseline justify-between gap-3 px-4 py-3">
      <div className="flex items-center gap-3">
        <span
          aria-hidden
          className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-amber-500/30 to-emerald-500/30 text-lg ring-1 ring-amber-400/40"
        >
          {emoji}
        </span>
        <div className="flex flex-col">
          <div className="flex items-center gap-2 text-base font-bold text-white">
            <span className="rounded-md border border-slate-700 bg-slate-900/60 px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-widest text-slate-300">
              {<Bilingual en={`Step ${stepNo}`} th={`ขั้นที่ ${stepNo}`} de={`Schritt ${stepNo}`} locale={locale} />}
            </span>
            <span>{title}</span>
          </div>
          <span className="font-mono text-[10px] uppercase tracking-widest text-slate-500">
            {subtitle}
          </span>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {badges}
        {actions}
      </div>
    </header>
  );
}

function StepCard({
  tone,
  header,
  children,
}: {
  tone: 'cyan' | 'emerald' | 'amber';
  header: React.ReactNode;
  children: React.ReactNode;
}) {
  const toneCls =
    tone === 'cyan'
      ? 'border-cyan-500/40 bg-cyan-950/15'
      : tone === 'amber'
        ? 'border-amber-500/40 bg-amber-950/15'
        : 'border-emerald-500/40 bg-emerald-950/15';
  return (
    <section className={'rounded-xl border ' + toneCls}>
      {header}
      <div className="space-y-3 border-t border-slate-800/60 px-4 py-3">{children}</div>
    </section>
  );
}

function EmptyState({
  message,
}: {
  message: React.ReactNode;
}) {
  return (
    <p className="rounded-md border border-slate-800/60 bg-slate-950/40 p-3 text-sm italic text-slate-500">
      {message}
    </p>
  );
}

function DraftChip() {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-cyan-500/40 bg-cyan-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-cyan-200">
      <span aria-hidden>📝</span>
      <span>DRAFT</span>
    </span>
  );
}

function ExpenseBody({
  props,
}: {
  props: Props;
}) {
  const {
    waybillId,
    actorRole: _actorRole,
    actorCanSeeLines,
    canFinalApprove = false,
    canConfirmGl = false,
    isFinalApproval = false,
    isDisbursed = false,
    hasPostedToGl = false,
    hasGlConfirmed = false,
    lang = 'th',
  } = props;
  const locale: Locale = lang;
  if (props.journal.kind !== 'expense') return null;
  const journal: ExpenseJournalView = props.journal;
  const { draft, posted, posted_event, confirmed_event } = journal;
  const empty = !draft && !posted;
  const liveLines = draft?.lines ?? posted?.lines ?? [];
  const totals = summarize(liveLines);

  const headerActions: React.ReactNode[] = [];
  if (draft && !posted) {
    headerActions.push(
      <form key="recompute" action={recomputeExpenseDraftGlAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <button
          type="submit"
          className="rounded-lg border border-cyan-500/40 bg-cyan-500/10 px-3 py-1.5 text-[11px] font-mono text-cyan-200 hover:bg-cyan-500/30"
        >
          ⟳{' '}
          {<Bilingual en="Recompute draft" th="คำนวณร่างใหม่" de="Entwurf neu berechnen" locale={locale} />}
        </button>
      </form>,
    );
  }
  if (canFinalApprove && isFinalApproval) {
    headerActions.push(
      <form key="final" action={finalApproveWaybillAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <button
          type="submit"
          className="inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-emerald-400 to-cyan-500 px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow shadow-emerald-500/30 hover:from-emerald-300"
        >
          <span aria-hidden>✓</span>
          <span>
            {<Bilingual en="Final approve → GL" th="อนุมัติขั้นสุดท้าย → GL" de="Endgültig freigeben → GL" locale={locale} />}
          </span>
        </button>
      </form>,
    );
    headerActions.push(
      <Link
        key="reject"
        href={`/waybill/${waybillId}?action=final-reject&stage=final_authorization`}
        className="inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-rose-400 to-rose-600 px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow shadow-rose-500/30"
      >
        <span aria-hidden>✗</span>
        <span>
          {<Bilingual en="Final reject" th="ปฏิเสธ" de="Endgültig ablehnen" locale={locale} />}
        </span>
      </Link>,
    );
  }
  if (canConfirmGl && isDisbursed) {
    headerActions.push(
      <form key="confirm" action={confirmGlRecordedAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <input
          type="hidden"
          name="expenseId"
          value={String(journal.draft?.journal_id ?? journal.posted?.journal_id ?? 0)}
        />
        <button
          type="submit"
          className="inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-amber-400 to-amber-500 px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow shadow-amber-500/30"
        >
          <span aria-hidden>✓</span>
          <span>
            {<Bilingual en="Confirm GL" th="ยืนยัน GL" de="GL bestätigen" locale={locale} />}
          </span>
        </button>
      </form>,
    );
  }

  const badges = (
    <>
      {draft && <DraftChip />}
      {!hasPostedToGl && !draft && (
        <span className="font-mono text-[10px] uppercase tracking-widest text-slate-500">
          {<Bilingual en="awaiting GL" th="รอ GL" de="wartet auf GL" locale={locale} />}
        </span>
      )}
      {hasPostedToGl && !hasGlConfirmed && !confirmed_event && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-amber-200">
          <span aria-hidden>⏳</span>
          <span>
            {<Bilingual en="AWAITING CONFIRM" th="รอยืนยัน" de="WARTET AUF BESTÄTIGUNG" locale={locale} />}
          </span>
        </span>
      )}
    </>
  );

  return (
    <>
      <StepHeader
        stepNo={1}
        emoji="📒"
        locale={locale}
        title={
          <Bilingual en="GL Journal" th="สมุดบัญชี (GL)" de="Hauptbuch (GL)" locale={locale} />
        }
        subtitle={
          <Bilingual en="draft + posted · debit/credit balance check" th="ร่าง + บันทึกแล้ว · ตรวจสอบเดบิต/เครดิต" de="Entwurf + gebucht · Soll/Haben Prüfung" locale={locale} />
        }
        badges={badges}
        actions={
          headerActions.length > 0 ? (
            <div className="flex flex-wrap items-center gap-2">{headerActions}</div>
          ) : null
        }
      />
      <div className="space-y-4 border-t border-slate-800/60 px-4 py-4">
        {empty && (
          <EmptyState
            message={
              <Bilingual en="No GL journal yet — will be created on submission" th="ยังไม่มีสมุดบัญชี — จะถูกสร้างเมื่อส่งเบิก" de="Noch kein Hauptbuch — wird beim Einreichen erstellt" locale={locale} />
            }
          />
        )}

        {draft && (
          <section className="space-y-2 rounded-xl border border-cyan-500/40 bg-cyan-950/15 p-3">
            <header className="flex flex-wrap items-baseline justify-between gap-2">
              <div className="flex items-center gap-2">
                <span className="rounded-md border border-cyan-400/40 bg-cyan-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase text-cyan-200">
                  📝 DRAFT
                </span>
                <span className="font-mono text-[10px] text-slate-500">
                  JE #{draft.journal_id}
                </span>
              </div>
              <span className="font-mono text-[10px] text-slate-500">
                entry_date: <span className="text-cyan-300">{fmtDate(draft.entry_date)}</span>
              </span>
            </header>
            {draft.description && <p className="text-sm text-slate-300">{draft.description}</p>}
            <GlVisibilityGate
              actorCanSeeLines={actorCanSeeLines}
              totalDebit={totals.totalDebit}
              totalCredit={totals.totalCredit}
              balanced={totals.balanced}
              lineCount={draft.lines.length}
            >
              <LinesTable lines={draft.lines} locale={locale} />
            </GlVisibilityGate>
          </section>
        )}

        {posted && (
          <section className="space-y-2 rounded-xl border border-emerald-500/40 bg-emerald-950/15 p-3">
            <header className="flex flex-wrap items-baseline justify-between gap-2">
              <div className="flex items-center gap-2">
                <span className="rounded-md border border-emerald-400/40 bg-emerald-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase text-emerald-200">
                  ✓ POSTED
                </span>
                <span className="font-mono text-[10px] text-slate-500">
                  JE #{posted.journal_id}
                </span>
              </div>
              <span className="font-mono text-[10px] text-slate-500">
                entry_date: <span className="text-emerald-300">{fmtDate(posted.entry_date)}</span>
              </span>
            </header>
            {posted.description && <p className="text-sm text-slate-300">{posted.description}</p>}
            <GlVisibilityGate
              actorCanSeeLines={actorCanSeeLines}
              totalDebit={totals.totalDebit}
              totalCredit={totals.totalCredit}
              balanced={totals.balanced}
              lineCount={posted.lines.length}
            >
              <LinesTable lines={posted.lines} locale={locale} />
            </GlVisibilityGate>
            <div className="grid gap-2 text-xs sm:grid-cols-2">
              <p className="rounded-md border border-emerald-500/40 bg-emerald-950/40 p-2 font-mono text-emerald-100">
                <span className="text-emerald-300">posted_by:</span>{' '}
                {posted.finalized_by_name ?? '—'}{' '}
                <span className="text-slate-500">#{posted.finalized_by ?? '—'}</span>
                {posted.finalized_at && (
                  <>
                    <span className="mx-1 text-slate-700">·</span>
                    <span className="text-emerald-300/80">
                      {fmtTs(posted.finalized_at, locale === 'de' ? 'en' as const : locale)}
                    </span>
                  </>
                )}
              </p>
              {posted_event && (
                <p className="rounded-md border border-emerald-500/40 bg-emerald-950/40 p-2 font-mono text-emerald-100">
                  <span className="text-emerald-300">posted_event:</span>{' '}
                  {posted_event.actor_name ?? '—'}{' '}
                  <span className="text-slate-500">#{posted_event.actor_id ?? '—'}</span>
                  <span className="mx-1 text-slate-700">·</span>
                  <span className="text-emerald-300/80">
                    {fmtTs(posted_event.occurred_at, locale === 'de' ? 'en' as const : locale)}
                  </span>
                </p>
              )}
              {confirmed_event && (
                <p className="rounded-md border border-cyan-500/40 bg-cyan-950/40 p-2 font-mono text-cyan-100 sm:col-span-2">
                  <span className="text-cyan-300">confirmed_event:</span>{' '}
                  {confirmed_event.actor_name ?? '—'}{' '}
                  <span className="text-slate-500">#{confirmed_event.actor_id ?? '—'}</span>
                  <span className="mx-1 text-slate-700">·</span>
                  <span className="text-cyan-300/80">
                    {fmtTs(confirmed_event.occurred_at, locale === 'de' ? 'en' as const : locale)}
                  </span>
                </p>
              )}
            </div>
          </section>
        )}
      </div>
    </>
  );
}

function ProcurementStepBody({
  waybillId,
  step,
  stepNo,
  emoji,
  title,
  subtitle,
  tone,
  actorCanSeeLines,
  canSave,
  canPost,
  canConfirm,
  blockedReason,
  locale,
}: {
  waybillId: string;
  step: ProcurementJournalStepView;
  stepNo: 1 | 2;
  emoji: string;
  title: React.ReactNode;
  subtitle: React.ReactNode;
  tone: 'cyan' | 'emerald' | 'amber';
  actorCanSeeLines: boolean;
  canSave: boolean;
  canPost: boolean;
  canConfirm: boolean;
  blockedReason: React.ReactNode;
  locale: Locale;
}) {
  const { draft, posted, posted_event, confirmed_event } = step;
  const empty = !draft && !posted;
  const liveLines = draft?.lines ?? posted?.lines ?? [];
  const totals = summarize(liveLines);

  const actions: React.ReactNode[] = [];
  if (canSave && draft && !posted) {
    actions.push(
      <form key="save" action={saveProcurementAccrualAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <button
          type="submit"
          className="rounded-lg border border-cyan-500/40 bg-cyan-500/10 px-3 py-1.5 text-[11px] font-mono text-cyan-200 hover:bg-cyan-500/30"
        >
          ⟳{' '}
          {<Bilingual en="Re-save draft" th="บันทึกร่างใหม่" de="Entwurf neu speichern" locale={locale} />}
        </button>
      </form>,
    );
  }
  if (canPost && draft && !posted) {
    const action = stepNo === 1 ? postProcurementAccrualAction : postProcurementSettlementAction;
    actions.push(
      <form key="post" action={action}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <input type="hidden" name="journalId" value={String(draft.journal_id)} />
        <button
          type="submit"
          className={
            'inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow ' +
            (tone === 'amber'
              ? 'bg-gradient-to-br from-amber-400 to-amber-500 shadow-amber-500/30 hover:from-amber-300'
              : 'bg-gradient-to-br from-emerald-400 to-cyan-500 shadow-emerald-500/30 hover:from-emerald-300')
          }
        >
          <span aria-hidden>✓</span>
          <span>
            {stepNo === 1
              ? <Bilingual en="Post accrual" th="บันทึกบัญชี (ก่อนจ่าย)" de="Buchen (vor Zahlung)" locale={locale} />
              : <Bilingual en="Post settlement" th="บันทึกบัญชี (หลังจ่าย)" de="Buchen (nach Zahlung)" locale={locale} />}
          </span>
        </button>
      </form>,
    );
  }
  if (canConfirm && posted && !confirmed_event) {
    actions.push(
      <form key="confirm" action={confirmProcurementGlAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <input type="hidden" name="step" value={stepNo === 1 ? 'accrual' : 'settlement'} />
        <button
          type="submit"
          className="inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-amber-400 to-amber-500 px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow shadow-amber-500/30 hover:from-amber-300"
        >
          <span aria-hidden>✓</span>
          <span>
            {<Bilingual en="Confirm GL" th="ยืนยัน GL" de="GL bestätigen" locale={locale} />}
          </span>
        </button>
      </form>,
    );
  }

  const badges = (
    <>
      {draft && <DraftChip />}
    </>
  );

  const accBlocked =
    <Bilingual en="No accrual draft yet — will be created at accounting_authorization" th="ยังไม่มีร่าง GL (ก่อนจ่าย) — จะถูกสร้างเมื่อบัญชีอนุมัติ" de="Noch kein Entwurf (vor Zahlung) — wird bei Buchhaltungsfreigabe erstellt" locale={locale} />;
  const setBlocked =
    <Bilingual en="No settlement draft yet — auto-created when payment slip attaches" th="ยังไม่มีร่าง GL (หลังจ่าย) — จะถูกสร้างเมื่อแนบสลิปจ่ายเงิน" de="Noch kein Entwurf (nach Zahlung) — wird beim Zahlschein erstellt" locale={locale} />;

  return (
    <StepCard
      tone={tone}
      header={
        <StepHeader
          stepNo={stepNo}
          emoji={emoji}
          locale={locale}
          title={title}
          subtitle={subtitle}
          badges={badges}
          actions={actions.length > 0 ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
        />
      }
    >
      {blockedReason && (
        <p className="rounded-md border border-slate-800/60 bg-slate-950/40 p-3 text-sm italic text-slate-500">
          {blockedReason}
        </p>
      )}
      {empty && !blockedReason && (
        <EmptyState message={stepNo === 1 ? accBlocked : setBlocked} />
      )}
      {draft && (
        <section className="space-y-2 rounded-lg border border-cyan-500/40 bg-cyan-950/15 p-3">
          <header className="flex flex-wrap items-baseline justify-between gap-2">
            <div className="flex items-center gap-2">
              <span className="rounded-md border border-cyan-400/40 bg-cyan-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase text-cyan-200">
                📝 DRAFT
              </span>
              <span className="font-mono text-[10px] text-slate-500">JE #{draft.journal_id}</span>
            </div>
            <span className="font-mono text-[10px] text-slate-500">
              entry_date: <span className="text-cyan-300">{fmtDate(draft.entry_date)}</span>
            </span>
          </header>
          {draft.description && <p className="text-sm text-slate-300">{draft.description}</p>}
          <GlVisibilityGate
            actorCanSeeLines={actorCanSeeLines}
            totalDebit={totals.totalDebit}
            totalCredit={totals.totalCredit}
            balanced={totals.balanced}
            lineCount={draft.lines.length}
          >
            <LinesTable lines={draft.lines} locale={locale} />
          </GlVisibilityGate>
        </section>
      )}
      {posted && (
        <section className="space-y-2 rounded-lg border border-emerald-500/40 bg-emerald-950/15 p-3">
          <header className="flex flex-wrap items-baseline justify-between gap-2">
            <div className="flex items-center gap-2">
              <span className="rounded-md border border-emerald-400/40 bg-emerald-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase text-emerald-200">
                ✓ POSTED
              </span>
              <span className="font-mono text-[10px] text-slate-500">JE #{posted.journal_id}</span>
            </div>
            <span className="font-mono text-[10px] text-slate-500">
              entry_date: <span className="text-emerald-300">{fmtDate(posted.entry_date)}</span>
            </span>
          </header>
          {posted.description && <p className="text-sm text-slate-300">{posted.description}</p>}
          <GlVisibilityGate
            actorCanSeeLines={actorCanSeeLines}
            totalDebit={totals.totalDebit}
            totalCredit={totals.totalCredit}
            balanced={totals.balanced}
            lineCount={posted.lines.length}
          >
            <LinesTable lines={posted.lines} locale={locale} />
          </GlVisibilityGate>
          <div className="grid gap-2 text-xs sm:grid-cols-2">
            <p className="rounded-md border border-emerald-500/40 bg-emerald-950/40 p-2 font-mono text-emerald-100">
              <span className="text-emerald-300">posted_by:</span>{' '}
              {posted.finalized_by_name ?? '—'}{' '}
              <span className="text-slate-500">#{posted.finalized_by ?? '—'}</span>
              {posted.finalized_at && (
                <>
                  <span className="mx-1 text-slate-700">·</span>
                  <span className="text-emerald-300/80">
                    {fmtTs(posted.finalized_at, locale === 'de' ? 'en' as const : locale)}
                  </span>
                </>
              )}
            </p>
            {posted_event && (
              <p className="rounded-md border border-emerald-500/40 bg-emerald-950/40 p-2 font-mono text-emerald-100">
                <span className="text-emerald-300">posted_event:</span>{' '}
                {posted_event.actor_name ?? '—'}{' '}
                <span className="text-slate-500">#{posted_event.actor_id ?? '—'}</span>
                <span className="mx-1 text-slate-700">·</span>
                <span className="text-emerald-300/80">
                  {fmtTs(posted_event.occurred_at, locale === 'de' ? 'en' as const : locale)}
                </span>
              </p>
            )}
            {confirmed_event && (
              <p className="rounded-md border border-cyan-500/40 bg-cyan-950/40 p-2 font-mono text-cyan-100 sm:col-span-2">
                <span className="text-cyan-300">confirmed_event:</span>{' '}
                {confirmed_event.actor_name ?? '—'}{' '}
                <span className="text-slate-500">#{confirmed_event.actor_id ?? '—'}</span>
                <span className="mx-1 text-slate-700">·</span>
                <span className="text-cyan-300/80">
                  {fmtTs(confirmed_event.occurred_at, locale === 'de' ? 'en' as const : locale)}
                </span>
              </p>
            )}
          </div>
        </section>
      )}
    </StepCard>
  );
}

function ProcurementBody({ props }: { props: Props }) {
  const {
    waybillId,
    actorCanSeeLines,
    canSaveAccrual = false,
    canPostAccrual = false,
    canConfirmAccrual = false,
    canPostSettlement = false,
    canConfirmSettlement = false,
    isAccountingAuthorization = false,
    isDisbursed = false,
    lang = 'th' as const,
  } = props;
  const locale: Locale = lang;
  if (props.journal.kind === 'expense' || props.journal.kind === 'so') return null;
  const journal: ProcurementJournalView = props.journal;

  const accrualPosted = !!journal.accrual.posted;
  const step2Blocked = !accrualPosted
    ? <Bilingual en="Locked until Step 1 (accrual) is posted" th="รอให้บันทึกขั้นที่ 1 (ก่อนจ่าย) ให้เสร็จก่อน" de="Gesperrt bis Schritt 1 (Rückstellung) gebucht ist" locale={locale} />
    : null;

  return (
    <div className="space-y-3 px-4 py-4">
      <ProcurementStepBody
        waybillId={waybillId}
        step={journal.accrual}
        stepNo={1}
        emoji="📒"
        locale={locale}
        title={
          <Bilingual en="Before pay (accrual)" th="ก่อนจ่าย (ตั้งหนี้)" de="vor Zahlung (Rückstellung)" locale={locale} />
        }
        subtitle={
          <Bilingual en="Dr expense/VAT · Cr accounts payable (210100)" th="Dr รายจ่าย/VAT · Cr เจ้าหนี้การค้า (210100)" de="Soll Aufwand/USt · Haben Verbindlichkeiten (210100)" locale={locale} />
        }
        tone="cyan"
        actorCanSeeLines={actorCanSeeLines}
        canSave={canSaveAccrual}
        canPost={canPostAccrual}
        canConfirm={canConfirmAccrual}
        blockedReason={null}
      />
      <div className={!accrualPosted ? 'pointer-events-none opacity-60' : ''}>
        <ProcurementStepBody
          waybillId={waybillId}
          step={journal.settlement}
          stepNo={2}
          emoji="💳"
          locale={locale}
          title={
            <Bilingual en="After pay (settlement)" th="หลังจ่าย (ชำระ)" de="nach Zahlung (Abrechnung)" locale={locale} />
          }
          subtitle={
            <Bilingual en="Dr accounts payable (210100) · Cr cash at bank (110200)" th="Dr เจ้าหนี้การค้า (210100) · Cr เงินสดธนาคาร (110200)" de="Soll Verbindlichkeiten (210100) · Haben Bankguthaben (110200)" locale={locale} />
          }
          tone="amber"
          actorCanSeeLines={actorCanSeeLines}
          canSave={false}
          canPost={canPostSettlement}
          canConfirm={canConfirmSettlement}
          blockedReason={step2Blocked}
        />
      </div>
      <p className="font-mono text-[10px] uppercase tracking-widest text-slate-500">
        {<Bilingual en="Step 2 is locked until Step 1 is posted" th="ขั้นที่ 2 จะล็อคจนกว่าขั้นที่ 1 จะถูกบันทึก" de="Schritt 2 ist gesperrt bis Schritt 1 gebucht ist" locale={locale} />}
        {!isAccountingAuthorization && journal.accrual.posted === null && (
          <>
            {' · '}
            <span className="text-slate-600">
              {<Bilingual en="accrual posts at accounting_authorization" th="ขั้น accrual จะโพสต์เมื่อถึงขั้น accounting_authorization" de="Rückstellung wird bei accounting_authorization gebucht" locale={locale} />}
            </span>
          </>
        )}
        {!isDisbursed && journal.accrual.posted !== null && journal.settlement.posted === null && (
          <>
            {' · '}
            <span className="text-slate-600">
              {<Bilingual en="settlement posts at disbursed" th="ขั้น settlement จะโพสต์เมื่อถึงขั้น disbursed" de="Abrechnung wird bei disbursed gebucht" locale={locale} />}
            </span>
          </>
        )}
      </p>
    </div>
  );
}

function SalesBody({ props }: { props: Props }) {
  const {
    waybillId,
    actorCanSeeLines,
    canPostSalesGlVat = false,
    canPostSalesGlAccrual = false,
    canPostSalesGlSettlement = false,
    canConfirmSalesGl = false,
    lang = 'th' as const,
  } = props;
  const locale: Locale = lang;
  if (props.journal.kind !== 'so') return null;
  const journal: SalesJournalView = props.journal;

  const vatPosted = !!journal.vat.posted;
  const accrualPosted = !!journal.accrual.posted;
  const settlementPosted = !!journal.settlement.posted;

  const step2Blocked = !vatPosted
    ? <Bilingual en="Locked until Step 1 (VAT) is posted" th="รอให้บันทึกขั้นที่ 1 (USt) ให้เสร็จก่อน" de="Gesperrt bis Schritt 1 (USt) gebucht ist" locale={locale} />
    : null;
  const step3Blocked = !accrualPosted
    ? <Bilingual en="Locked until Step 2 (Accrual) is posted" th="รอให้บันทึกขั้นที่ 2 (ตั้งหนี้) ให้เสร็จก่อน" de="Gesperrt bis Schritt 2 (Rückstellung) gebucht ist" locale={locale} />
    : null;

  const steps = [
    {
      stepNo: 1 as const,
      stepKey: 'vat' as const,
      emoji: '🧾',
      title:
        <Bilingual en="VAT" th="ภาษีมูลค่าเพิ่ม" de="USt" locale={locale} />,
      subtitle:
        <Bilingual en="Dr output VAT receivable · Cr output VAT payable" th="Dr ภาษีซื้อรอเรียกเก็บ · Cr ภาษีขาย" de="Soll Forderung USt · Haben Verbindlichkeit USt" locale={locale} />,
      tone: 'cyan' as const,
      step: journal.vat,
      canPost: canPostSalesGlVat,
      canConfirm: canConfirmSalesGl,
      postAction: postSalesGlVatAction,
      postLabel:
        <Bilingual en="Post VAT" th="บันทึกบัญชี (USt)" de="USt buchen" locale={locale} />,
      emptyMsg:
        <Bilingual en="No VAT draft yet — created at so_invoiced" th="ยังไม่มีร่าง USt — จะถูกสร้างที่ so_invoiced" de="Noch kein USt-Entwurf — wird bei so_invoiced erstellt" locale={locale} />,
      blockedReason: null,
    },
    {
      stepNo: 2 as const,
      stepKey: 'accrual' as const,
      emoji: '📒',
      title:
        <Bilingual en="Accrual (Revenue)" th="ตั้งหนี้ (รายได้)" de="Rückstellung (Erlöse)" locale={locale} />,
      subtitle:
        <Bilingual en="Dr AR · Cr sales revenue" th="Dr ลูกหนี้การค้า · Cr รายได้จากการขาย" de="Soll Forderungen · Haben Umsatzerlöse" locale={locale} />,
      tone: 'emerald' as const,
      step: journal.accrual,
      canPost: canPostSalesGlAccrual,
      canConfirm: canConfirmSalesGl,
      postAction: postSalesGlAccrualAction,
      postLabel:
        <Bilingual en="Post accrual" th="บันทึกบัญชี (ตั้งหนี้)" de="Rückstellung buchen" locale={locale} />,
      emptyMsg:
        <Bilingual en="No accrual draft yet — created at so_invoiced" th="ยังไม่มีร่างตั้งหนี้ — จะถูกสร้างที่ so_invoiced" de="Noch kein Rückstellungsentwurf — wird bei so_invoiced erstellt" locale={locale} />,
      blockedReason: step2Blocked,
    },
    {
      stepNo: 3 as const,
      stepKey: 'settlement' as const,
      emoji: '💳',
      title:
        <Bilingual en="Settlement (collection)" th="ชำระ (รับเงิน)" de="Abrechnung (Zahlung)" locale={locale} />,
      subtitle:
        <Bilingual en="Dr cash at bank · Cr AR" th="Dr เงินฝากธนาคาร · Cr ลูกหนี้การค้า" de="Soll Bankguthaben · Haben Forderungen" locale={locale} />,
      tone: 'amber' as const,
      step: journal.settlement,
      canPost: canPostSalesGlSettlement,
      canConfirm: canConfirmSalesGl,
      postAction: postSalesGlSettlementAction,
      postLabel:
        <Bilingual en="Post settlement" th="บันทึกบัญชี (ชำระ)" de="Abrechnung buchen" locale={locale} />,
      emptyMsg:
        <Bilingual en="No settlement draft yet — auto-created when AR receipt attaches" th="ยังไม่มีร่างชำระ — จะถูกสร้างเมื่อแนบหลักฐานรับเงิน" de="Noch kein Abrechnungsentwurf — wird beim Forderungseingang erstellt" locale={locale} />,
      blockedReason: step3Blocked,
    },
  ];

  return (
    <div className="space-y-3 px-4 py-4">
      {steps.map((s) => (
        <SalesStepBody
          key={s.stepKey}
          waybillId={waybillId}
          step={s.step}
          stepNo={s.stepNo}
          emoji={s.emoji}
          title={s.title}
          subtitle={s.subtitle}
          tone={s.tone}
          actorCanSeeLines={actorCanSeeLines}
          canPost={s.canPost}
          canConfirm={s.canConfirm}
          postAction={s.postAction}
          postLabel={s.postLabel}
          emptyMsg={s.emptyMsg}
          blockedReason={s.blockedReason}
          locale={locale}
        />
      ))}
      <p className="font-mono text-[10px] uppercase tracking-widest text-slate-500">
        {<Bilingual en="Each step locked until the previous is posted" th="ขั้นถัดไปจะล็อคจนกว่าขั้นก่อนหน้าจะถูกบันทึก" de="Nächster Schritt gesperrt bis vorheriger gebucht ist" locale={locale} />}
        {!settlementPosted && (
          <>
            {' · '}
            <span className="text-slate-600">
              {<Bilingual en="settlement posts at so_paid" th="ชำระจะโพสต์ที่ so_paid" de="Abrechnung wird bei so_paid gebucht" locale={locale} />}
            </span>
          </>
        )}
      </p>
    </div>
  );
}

function SalesStepBody({
  waybillId,
  step,
  stepNo,
  emoji,
  title,
  subtitle,
  tone,
  actorCanSeeLines,
  canPost,
  canConfirm,
  postAction,
  postLabel,
  emptyMsg,
  blockedReason,
  locale,
}: {
  waybillId: string;
  step: ProcurementJournalStepView;
  stepNo: 1 | 2 | 3;
  emoji: string;
  title: React.ReactNode;
  subtitle: React.ReactNode;
  tone: 'cyan' | 'emerald' | 'amber';
  actorCanSeeLines: boolean;
  canPost: boolean;
  canConfirm: boolean;
  postAction: (formData: FormData) => Promise<void>;
  postLabel: React.ReactNode;
  emptyMsg: React.ReactNode;
  blockedReason: React.ReactNode;
  locale: Locale;
}) {
  const { draft, posted, posted_event, confirmed_event } = step;
  const empty = !draft && !posted;
  const liveLines = draft?.lines ?? posted?.lines ?? [];
  const totals = summarize(liveLines);

  const actions: React.ReactNode[] = [];
  if (canPost && draft && !posted) {
    actions.push(
      <form key="post" action={postAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <input type="hidden" name="journalId" value={String(draft.journal_id)} />
        <button
          type="submit"
          className={
            'inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow ' +
            (tone === 'amber'
              ? 'bg-gradient-to-br from-amber-400 to-amber-500 shadow-amber-500/30 hover:from-amber-300'
              : 'bg-gradient-to-br from-emerald-400 to-cyan-500 shadow-emerald-500/30 hover:from-emerald-300')
          }
        >
          <span aria-hidden>✓</span>
          <span>{postLabel}</span>
        </button>
      </form>,
    );
  }
  if (canConfirm && posted && !confirmed_event) {
    actions.push(
      <form key="confirm" action={confirmSalesGlAction}>
        <input type="hidden" name="waybillId" value={waybillId} />
        <input type="hidden" name="step" value={stepNo === 3 ? 'settlement' : stepNo === 2 ? 'accrual' : 'vat'} />
        <button
          type="submit"
          className="inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-amber-400 to-amber-500 px-3 py-1.5 text-[11px] font-bold text-slate-950 shadow shadow-amber-500/30 hover:from-amber-300"
        >
          <span aria-hidden>✓</span>
          <span>
            {<Bilingual en="Confirm GL" th="ยืนยัน GL" de="GL bestätigen" locale={locale} />}
          </span>
        </button>
      </form>,
    );
  }

  const badges = (
    <>
      {draft && <DraftChip />}
    </>
  );

  return (
    <StepCard
      tone={tone}
      header={
        <StepHeader
          stepNo={stepNo}
          emoji={emoji}
          title={title}
          subtitle={subtitle}
          locale={locale}
          badges={badges}
          actions={actions.length > 0 ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
        />
      }
    >
      {blockedReason && (
        <p className="rounded-md border border-slate-800/60 bg-slate-950/40 p-3 text-sm italic text-slate-500">
          {blockedReason}
        </p>
      )}
      {empty && !blockedReason && <EmptyState message={emptyMsg} />}
      {draft && (
        <section className="space-y-2 rounded-lg border border-cyan-500/40 bg-cyan-950/15 p-3">
          <header className="flex flex-wrap items-baseline justify-between gap-2">
            <div className="flex items-center gap-2">
              <span className="rounded-md border border-cyan-400/40 bg-cyan-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase text-cyan-200">
                📝 DRAFT
              </span>
              <span className="font-mono text-[10px] text-slate-500">JE #{draft.journal_id}</span>
            </div>
            <span className="font-mono text-[10px] text-slate-500">
              entry_date: <span className="text-cyan-300">{fmtDate(draft.entry_date)}</span>
            </span>
          </header>
          {draft.description && <p className="text-sm text-slate-300">{draft.description}</p>}
          <GlVisibilityGate
            actorCanSeeLines={actorCanSeeLines}
            totalDebit={totals.totalDebit}
            totalCredit={totals.totalCredit}
            balanced={totals.balanced}
            lineCount={draft.lines.length}
          >
            <LinesTable lines={draft.lines} locale={locale} />
          </GlVisibilityGate>
        </section>
      )}
      {posted && (
        <section className="space-y-2 rounded-lg border border-emerald-500/40 bg-emerald-950/15 p-3">
          <header className="flex flex-wrap items-baseline justify-between gap-2">
            <div className="flex items-center gap-2">
              <span className="rounded-md border border-emerald-400/40 bg-emerald-500/15 px-2 py-0.5 text-[10px] font-mono font-bold uppercase text-emerald-200">
                ✓ POSTED
              </span>
              <span className="font-mono text-[10px] text-slate-500">JE #{posted.journal_id}</span>
            </div>
            <span className="font-mono text-[10px] text-slate-500">
              entry_date: <span className="text-emerald-300">{fmtDate(posted.entry_date)}</span>
            </span>
          </header>
          {posted.description && <p className="text-sm text-slate-300">{posted.description}</p>}
          <GlVisibilityGate
            actorCanSeeLines={actorCanSeeLines}
            totalDebit={totals.totalDebit}
            totalCredit={totals.totalCredit}
            balanced={totals.balanced}
            lineCount={posted.lines.length}
          >
            <LinesTable lines={posted.lines} locale={locale} />
          </GlVisibilityGate>
          <div className="grid gap-2 text-xs sm:grid-cols-2">
            <p className="rounded-md border border-emerald-500/40 bg-emerald-950/40 p-2 font-mono text-emerald-100">
              <span className="text-emerald-300">posted_by:</span>{' '}
              {posted.finalized_by_name ?? '—'}{' '}
              <span className="text-slate-500">#{posted.finalized_by ?? '—'}</span>
              {posted.finalized_at && (
                <>
                  <span className="mx-1 text-slate-700">·</span>
                  <span className="text-emerald-300/80">
                    {fmtTs(posted.finalized_at, locale === 'de' ? 'en' as const : locale)}
                  </span>
                </>
              )}
            </p>
            {posted_event && (
              <p className="rounded-md border border-emerald-500/40 bg-emerald-950/40 p-2 font-mono text-emerald-100">
                <span className="text-emerald-300">posted_event:</span>{' '}
                {posted_event.actor_name ?? '—'}{' '}
                <span className="text-slate-500">#{posted_event.actor_id ?? '—'}</span>
                <span className="mx-1 text-slate-700">·</span>
                <span className="text-emerald-300/80">
                  {fmtTs(posted_event.occurred_at, locale === 'de' ? 'en' as const : locale)}
                </span>
              </p>
            )}
            {confirmed_event && (
              <p className="rounded-md border border-cyan-500/40 bg-cyan-950/40 p-2 font-mono text-cyan-100 sm:col-span-2">
                <span className="text-cyan-300">confirmed_event:</span>{' '}
                {confirmed_event.actor_name ?? '—'}{' '}
                <span className="text-slate-500">#{confirmed_event.actor_id ?? '—'}</span>
                <span className="mx-1 text-slate-700">·</span>
                <span className="text-cyan-300/80">
                  {fmtTs(confirmed_event.occurred_at, locale === 'de' ? 'en' as const : locale)}
                </span>
              </p>
            )}
          </div>
        </section>
      )}
    </StepCard>
  );
}

export function WaybillGlSection(props: Props) {
  const lang = (props.lang ?? 'th') as Locale;
  const locale: Locale = lang;
  const isExpense = props.journal.kind === 'expense';
  const isSales = props.journal.kind === 'so';
  return (
    <details className="group rounded-2xl border border-slate-800/60 bg-slate-950/40" open>
      <summary className="cursor-pointer list-none px-4 py-3 [&::-webkit-details-marker]:hidden">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <span
              aria-hidden
              className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-amber-500/30 to-emerald-500/30 text-lg ring-1 ring-amber-400/40"
            >
              📒
            </span>
            <div className="flex flex-col">
              <span className="text-base font-bold text-white">
                {isExpense
                  ? <Bilingual en="GL Journal" th="สมุดบัญชี (GL)" de="Hauptbuch (GL)" locale={locale} />
                  : isSales
                    ? <Bilingual en="GL Journal — 3 steps" th="สมุดบัญชี (GL) — 3 ขั้น" de="Hauptbuch (GL) — 3 Schritte" locale={locale} />
                    : <Bilingual en="GL Journal — 2 steps" th="สมุดบัญชี (GL) — 2 ขั้น" de="Hauptbuch (GL) — 2 Schritte" locale={locale} />}
              </span>
              <span className="font-mono text-[10px] uppercase tracking-widest text-slate-500">
                {isExpense
                  ? <Bilingual en="draft + posted · debit/credit balance check" th="ร่าง + บันทึกแล้ว · ตรวจสอบเดบิต/เครดิต" de="Entwurf + gebucht · Soll/Haben Prüfung" locale={locale} />
                  : isSales
                    ? <Bilingual en="VAT · accrual · settlement · debit/credit" th="USt · ตั้งหนี้ · ชำระ · เดบิต/เครดิต" de="USt · Rückstellung · Abrechnung · Soll/Haben" locale={locale} />
                    : <Bilingual en="before pay · after pay · debit/credit" th="ก่อนจ่าย · หลังจ่าย · เดบิต/เครดิต" de="vor Zahlung · nach Zahlung · Soll/Haben" locale={locale} />}
                {' · '}
                <span className="text-cyan-300">{props.waybillId}</span>
              </span>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {isExpense ? (
              <ExpenseBodyInlineBadges j={props.journal as ExpenseJournalView} locale={locale} />
            ) : isSales ? (
              <SalesBodyInlineBadges j={props.journal as SalesJournalView} locale={locale} />
            ) : (
              <ProcurementBodyInlineBadges
                j={props.journal as ProcurementJournalView}
                locale={locale}
              />
            )}
            <span className="font-mono text-[10px] uppercase tracking-wider text-slate-500 group-open:hidden">
              ▶
            </span>
            <span className="font-mono text-[10px] uppercase tracking-wider text-slate-500 hidden group-open:inline">
              ▼
            </span>
          </div>
        </div>
      </summary>
      {isExpense ? (
        <ExpenseBody props={props} />
      ) : isSales ? (
        <SalesBody props={props} />
      ) : (
        <ProcurementBody props={props} />
      )}
    </details>
  );
}

function ExpenseBodyInlineBadges({ j, locale: _locale }: { j: ExpenseJournalView; locale: Locale }) {
  return (
    <>
      {j.draft && <DraftChip />}
    </>
  );
}

function ProcurementBodyInlineBadges({
  j,
  locale,
}: {
  j: ProcurementJournalView;
  locale: Locale;
}) {
  return (
    <>
      {j.accrual.draft && <DraftChip />}
      {j.settlement.draft && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-amber-200">
          <span aria-hidden>💳</span>
          <span>
            {<Bilingual en="SETTLE DRAFT" th="ร่างหลังจ่าย" de="ABRECHNUNG ENTWURF" locale={locale} />}
          </span>
        </span>
      )}
      {j.settlement.posted && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-amber-200">
          <span aria-hidden>💳</span>
          <span>
            {<Bilingual en="SETTLE POSTED" th="บันทึกหลังจ่าย" de="ABRECHNUNG GEBUCHT" locale={locale} />}
          </span>
        </span>
      )}
    </>
  );
}

function SalesBodyInlineBadges({ j, locale }: { j: SalesJournalView; locale: Locale }) {
  return (
    <>
      {j.vat.draft && <DraftChip />}
      {j.accrual.draft && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-emerald-500/40 bg-emerald-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-emerald-200">
          <span aria-hidden>📒</span>
          <span>
            {<Bilingual en="ACCRUAL DRAFT" th="ร่างตั้งหนี้" de="RÜCKSTELLUNG ENTWURF" locale={locale} />}
          </span>
        </span>
      )}
      {j.accrual.posted && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-emerald-500/40 bg-emerald-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-emerald-200">
          <span aria-hidden>📒</span>
          <span>
            {<Bilingual en="ACCRUAL POSTED" th="บันทึกตั้งหนี้" de="RÜCKSTELLUNG GEBUCHT" locale={locale} />}
          </span>
        </span>
      )}
      {j.settlement.draft && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-amber-200">
          <span aria-hidden>💳</span>
          <span>
            {<Bilingual en="SETTLE DRAFT" th="ร่างชำระ" de="ABRECHNUNG ENTWURF" locale={locale} />}
          </span>
        </span>
      )}
      {j.settlement.posted && (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-1 text-[10px] font-mono font-bold uppercase text-amber-200">
          <span aria-hidden>💳</span>
          <span>
            {<Bilingual en="SETTLE POSTED" th="บันทึกชำระ" de="ABRECHNUNG GEBUCHT" locale={locale} />}
          </span>
        </span>
      )}
    </>
  );
}
