import React from 'react';
import type { SecondaryLocale } from '@erp-lib/server/locale';
import type {
  ExpenseFullPicture,
  WaybillSlip,
} from '@/lib/server/waybill';
import { fmtSize, statusPill } from './ui';
import { SlipThumbZoom } from './SlipThumbZoom';
import { formatDateServer, formatMoneyServer } from '@/components/i18n/formattersServer';
import { Bilingual } from '@/components/i18n/Bilingual';

interface Props {
  data: ExpenseFullPicture;
  waybillId: string;
  locale?: SecondaryLocale;
}

async function presignedOrHash(slip: WaybillSlip): Promise<string> {
  try {
    return `/api/slips/file?key=${encodeURIComponent(slip.file_path)}`;
  } catch {
    return '#';
  }
}

function SlipRow({
  emoji,
  label,
  slip,
  href,
  locale,
  bankFields,
}: {
  emoji: string;
  label: React.ReactNode;
  slip: WaybillSlip | null;
  href: string | null;
  locale: SecondaryLocale;
  bankFields?: {
    bankName: string | null;
    accountNumber: string | null;
    accountName: string | null;
    bankBranch: string | null;
  } | null;
}) {
  const showThumb = !!slip && !!href && href !== '#' && /^image\//.test(slip.mime_type);
  return (
    <div className="py-2">
      <div className="flex items-center gap-2">
        <span aria-hidden className="text-lg leading-none">
          {emoji}
        </span>
        <span className="text-sm font-bold text-white">{label}</span>
        {slip ? (
          <span className="ml-auto rounded-full border border-cyan-500/40 bg-cyan-500/15 px-2 py-0.5 text-[10px] font-mono uppercase tracking-widest text-cyan-200">
            ✓ {slip.status}
          </span>
        ) : (
          <span className="ml-auto rounded-full border border-slate-700 bg-slate-900/40 px-2 py-0.5 text-[10px] font-mono uppercase tracking-widest text-slate-500">
            <Bilingual en="none" th="ไม่มี" de="keine" locale={locale} />
          </span>
        )}
      </div>
      {slip && href ? (
        <div className="mt-1.5 flex items-start gap-3 text-xs">
          {showThumb && (
            <SlipThumbZoom
              href={href}
              alt={typeof label === 'string' ? label : 'slip'}
              title={slip.file_path.split('/').slice(-1)[0]}
              subtitle={`${fmtSize(slip.file_size)} · ${slip.mime_type}`}
              className="h-16 w-12"
            />
          )}
          <div className="min-w-0 flex-1 space-y-1">
            <a
              href={href}
              className="block break-all font-mono text-sm font-semibold text-cyan-300 underline-offset-2 hover:underline"
            >
              {slip.file_path.split('/').slice(-1)[0]}
            </a>
            <div className="text-xs font-mono text-slate-500">
              {fmtSize(slip.file_size)} · {slip.mime_type}
            </div>
            {bankFields && (bankFields.bankName || bankFields.accountNumber) && (
              <div className="text-xs font-mono text-slate-300">
                {bankFields.bankName && (
                  <span className="mr-3">
                    🏦 <span className="text-slate-100">{bankFields.bankName}</span>
                  </span>
                )}
                {bankFields.accountNumber && (
                  <span className="mr-3">
                    #<span className="text-cyan-300 font-bold">{bankFields.accountNumber}</span>
                  </span>
                )}
                {bankFields.accountName && (
                  <span>
                    👤 <span className="text-slate-100">{bankFields.accountName}</span>
                  </span>
                )}
              </div>
            )}
          </div>
        </div>
      ) : (
        <p className="mt-1.5 text-xs italic text-slate-500">
          <Bilingual en="not attached" th="ยังไม่ได้แนบ" de="nicht angehängt" locale={locale} />
        </p>
      )}
    </div>
  );
}

function Field({
  label,
  value,
  mono,
  accent,
  full,
}: {
  label: React.ReactNode;
  value: string;
  mono?: boolean;
  accent?: string;
  full?: boolean;
}) {
  return (
    <div className={full ? 'col-span-2' : ''}>
      <dt className="text-[10px] font-mono uppercase tracking-widest text-slate-500">{label}</dt>
      <dd
        className={
          'mt-0.5 text-sm text-slate-100' +
          (mono ? ' font-mono' : '') +
          (accent ? ' ' + accent : '')
        }
      >
        {value}
      </dd>
    </div>
  );
}

export async function WaybillExpenseCollapsible({
  data,
  waybillId,
  locale,
}: Props) {
  const localeSafe: SecondaryLocale = locale ?? 'th';
  const fmtDate = (d: Date | string | null) => formatDateServer(d, localeSafe);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, localeSafe);
  const { expense, items, slips, submitter_name } = data;
  const receiptSlip = slips.find((s) => (s as any).kind === 'receipt') ?? null;
  const bookBankSlip = slips.find((s) => (s as any).kind === 'book_bank' || (s as any).kind === 'book-bank') ?? null;
  const receiptHref = receiptSlip ? await presignedOrHash(receiptSlip) : null;
  const bookHref = bookBankSlip ? await presignedOrHash(bookBankSlip) : null;

  return (
    <details className="group rounded-2xl border border-slate-800/60 bg-slate-950/40">
      <summary className="cursor-pointer list-none px-4 py-3 [&::-webkit-details-marker]:hidden">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <span
              aria-hidden
              className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-indigo-500/30 to-cyan-500/30 text-lg ring-1 ring-indigo-400/30"
            >
              📦
            </span>
            <div className="flex flex-col">
              <span className="text-base font-bold text-white">
                <Bilingual en="Expense picture" th="ภาพรวมค่าใช้จ่าย" de="Auslagenübersicht" locale={localeSafe} />
              </span>
              <span className="font-mono text-[10px] uppercase tracking-widest text-slate-500">
                <Bilingual en="vendor · items · slips" th="ผู้ขาย · รายการ · สลิป" de="Lieferant · Positionen · Belege" locale={localeSafe} />:{' '}
                <span className="text-cyan-300">{waybillId}</span>
              </span>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {statusPill(expense.status, localeSafe)}
            <span className="font-mono text-[10px] uppercase tracking-wider text-slate-500 group-open:hidden">
              ▶
            </span>
            <span className="font-mono text-[10px] uppercase tracking-wider text-slate-500 hidden group-open:inline">
              ▼
            </span>
          </div>
        </div>
      </summary>

      <div className="space-y-6 border-t border-slate-800/60 px-4 py-4">
        <div className="grid gap-6 lg:grid-cols-2">
          <section className="space-y-4">
            <div className="flex items-center gap-2 text-xs font-mono uppercase tracking-widest text-slate-400">
              <span aria-hidden>📋</span>
              <span>
                <Bilingual en="Expense details" th="รายละเอียดค่าใช้จ่าย" de="Auslagendetails" locale={localeSafe} />
              </span>
            </div>
            <dl className="grid grid-cols-2 gap-x-4 divide-y divide-slate-800/40 text-sm">
              <Field label={<Bilingual en="Created by (Vendor)" th="ผู้ขาย (ผู้จัดทำ)" de="Aussteller" locale={localeSafe} />} value={expense.vendor_name ?? '—'} mono />
              <Field label={<Bilingual en="Vendor Address" th="ที่อยู่ผู้ขาย" de="Adresse des Ausstellers" locale={localeSafe} />} value={expense.vendor_address ?? '—'} mono />
              <Field label={<Bilingual en="Created to (Customer)" th="ลูกค้า (ผู้รับ)" de="Empfänger" locale={localeSafe} />} value={expense.created_to ?? '—'} mono />
              <Field label={<Bilingual en="Customer Address" th="ที่อยู่ลูกค้า" de="Adresse des Empfängers" locale={localeSafe} />} value={expense.created_to_address ?? '—'} mono />
              <Field
                label={<Bilingual en="Transaction date" th="วันที่" de="Transaktionsdatum" locale={localeSafe} />}
                value={fmtDate(expense.transaction_date)}
                mono
              />
              <Field
                label={<Bilingual en="Payment method" th="การชำระ" de="Zahlungsart" locale={localeSafe} />}
                value={expense.payment_method ?? '—'}
                mono
              />
              <Field
                label={<Bilingual en="Submitter" th="ผู้ส่ง" de="Einreicher" locale={localeSafe} />}
                value={
                  submitter_name
                    ? `${submitter_name} #${expense.submitter_id ?? '—'}`
                    : expense.submitter_id
                    ? `#${expense.submitter_id}`
                    : '—'
                }
              />
              <Field
                label={<Bilingual en="Subtotal" th="ยอดก่อน VAT" de="Zwischensumme" locale={localeSafe} />}
                value={fmtMoney(expense.subtotal)}
                mono
                accent="text-slate-200 text-base"
              />
              <Field
                label={<Bilingual en="VAT" th="VAT" de="USt." locale={localeSafe} />}
                value={fmtMoney(expense.vat_amount)}
                mono
                accent="text-slate-200 text-base"
              />
              <Field
                label={<Bilingual en="Total" th="รวม" de="Gesamt" locale={localeSafe} />}
                value={fmtMoney(expense.total_amount)}
                mono
                accent="text-2xl sm:text-3xl text-emerald-300 font-extrabold"
                full
              />
            </dl>
            {expense.rejection_reason && (
              <p className="rounded-lg border border-rose-500/40 bg-rose-950/40 px-3 py-2 text-sm italic text-rose-200">
                <span aria-hidden>✗</span>{' '}
                <Bilingual en="Rejection reason" th="เหตุผลที่ปฏิเสธ" de="Ablehnungsgrund" locale={localeSafe} />: &ldquo;{expense.rejection_reason}&rdquo;
              </p>
            )}
          </section>

          <section className="space-y-4">
            <div className="flex items-center gap-2 text-xs font-mono uppercase tracking-widest text-slate-400">
              <span aria-hidden>🧾</span>
              <span>
                <Bilingual en="Line items" th="รายการ" de="Positionen" locale={localeSafe} /> ({items.length})
              </span>
            </div>
            {items.length === 0 ? (
              <p className="text-sm italic text-slate-500">
                <Bilingual en="no line items" th="ไม่มีรายการ" de="keine Positionen" locale={localeSafe} />
              </p>
            ) : (
              <ul className="divide-y divide-slate-800/40">
                {items.map((it) => (
                  <li
                    key={it.id}
                    className="flex items-center justify-between gap-3 py-2 text-sm"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-slate-100 font-medium">{it.description}</div>
                      <div className="mt-0.5 flex flex-wrap gap-x-3 text-xs font-mono text-slate-500">
                        {it.qty && it.unit_price && (
                          <span>
                            {it.qty} × {fmtMoney(it.unit_price)}
                          </span>
                        )}
                        {it.mapped_account_code && (
                          <span>
                            acct: <span className="text-cyan-300">{it.mapped_account_code}</span>
                          </span>
                        )}
                      </div>
                    </div>
                    <div className="shrink-0 text-right font-mono text-lg font-semibold text-cyan-200">
                      {fmtMoney(it.amount)}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <section className="space-y-4">
          <div className="flex items-center gap-2 text-xs font-mono uppercase tracking-widest text-slate-400">
            <span aria-hidden>📎</span>
            <span>
              <Bilingual en="Slip attachments" th="สลิปที่แนบ" de="Beleganlagen" locale={localeSafe} />
            </span>
          </div>
          <div className="grid gap-x-6 gap-y-2 sm:grid-cols-2 divide-y divide-slate-800/40 sm:divide-y-0">
            <SlipRow
              emoji="🧾"
              label={
                <Bilingual en="Receipt" th="ใบเสร็จ" de="Beleg" locale={localeSafe} />
              }
              slip={receiptSlip}
              href={receiptHref}
              locale={localeSafe}
            />
            <SlipRow
              emoji="📖"
              label={
                <Bilingual en="Book bank" th="สมุดบัญชี" de="Kontoauszug" locale={localeSafe} />
              }
              slip={bookBankSlip}
              href={bookHref}
              locale={localeSafe}
              bankFields={
                bookBankSlip
                  ? {
                      bankName: bookBankSlip.bank_name,
                      accountNumber: bookBankSlip.account_number,
                      accountName: bookBankSlip.account_name,
                      bankBranch: bookBankSlip.bank_branch,
                    }
                  : null
              }
            />
          </div>
        </section>
      </div>
    </details>
  );
}
