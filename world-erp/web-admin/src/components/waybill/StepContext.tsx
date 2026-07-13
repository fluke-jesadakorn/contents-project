import React from 'react';
import type { SecondaryLocale } from '@erp-lib/server/locale';
import type { ExpenseFullPicture, WaybillSlip } from '@/lib/server/waybill';
import { fmtSize } from './ui';
import { formatDateServer, formatMoneyServer } from '@/components/i18n/formattersServer';
import { Bilingual } from '@/components/i18n/Bilingual';

interface Props {
  pipKey: string;
  picture: ExpenseFullPicture | null;
  hasGlConfirmed: boolean;
  origin: 'expense' | 'pr' | 'po';
  locale?: SecondaryLocale;
}

async function safeUrl(key: string): Promise<string | null> {
  try {
    return `/api/slips/file?key=${encodeURIComponent(key)}`;
  } catch {
    return null;
  }
}

function isImage(mime: string): boolean {
  return /^image\//.test(mime);
}

function paymentLabel(method: string | null): string {
  if (!method) return '—';
  const m: Record<string, string> = {
    cash: 'Cash',
    credit_card: 'Credit card',
    transfer: 'Transfer',
  };
  return m[method] ?? method;
}

export function StepContext({
  pipKey,
  picture,
  hasGlConfirmed,
  origin,
  locale,
}: Props) {
  if (origin !== 'expense' || !picture) return null;
  const localeSafe: SecondaryLocale = locale ?? 'th';
  const { slips } = picture;
  const receipt = slips.find((s) => (s as any).kind === 'receipt') ?? null;
  const bookBank = slips.find((s) => (s as any).kind === 'book_bank' || (s as any).kind === 'book-bank') ?? null;

  const receiptPromise = receipt ? safeUrl(receipt.file_path) : Promise.resolve(null);
  const bookPromise = bookBank ? safeUrl(bookBank.file_path) : Promise.resolve(null);

  switch (pipKey) {
    case 'draft':
    case 'submission':
      return (
        <SubmissionContext
          picture={picture}
          receipt={receipt}
          receiptUrlPromise={receiptPromise}
          bookBank={bookBank}
          bookUrlPromise={bookPromise}
          locale={localeSafe}
        />
      );

    case 'dept_verification':
    case 'dept_authorization':
      return (
        <DeptContext
          picture={picture}
          receipt={receipt}
          receiptUrlPromise={receiptPromise}
          locale={localeSafe}
        />
      );

    case 'accounting_verification':
    case 'accounting_supervision':
    case 'accounting_authorization':
      return <AccountingContext picture={picture} locale={localeSafe} />;

    case 'final_authorization':
    case 'disbursement_authorization':
    case 'cfo_authorization':
    case 'ceo_authorization':
      return (
        <FinalContext
          picture={picture}
          bookBank={bookBank}
          bookUrlPromise={bookPromise}
          locale={localeSafe}
        />
      );

    case 'awaiting_disbursement':
      return (
        <AwaitingDisbursementContext
          picture={picture}
          bookBank={bookBank}
          bookUrlPromise={bookPromise}
          locale={localeSafe}
        />
      );

    case 'disbursed':
      return (
        <DisbursedContext
          picture={picture}
          receipt={receipt}
          receiptUrlPromise={receiptPromise}
          bookBank={bookBank}
          hasGlConfirmed={hasGlConfirmed}
          locale={localeSafe}
        />
      );

    default:
      return null;
  }
}

function ContextShell({
  tone,
  badge,
  hint,
  children,
}: {
  tone: 'cyan' | 'amber' | 'indigo' | 'emerald' | 'rose' | 'slate';
  badge: React.ReactNode;
  hint?: React.ReactNode;
  children: React.ReactNode;
}) {
  const toneCls: Record<typeof tone, string> = {
    cyan: 'border-cyan-500/30 bg-cyan-950/15',
    amber: 'border-amber-500/30 bg-amber-950/15',
    indigo: 'border-indigo-500/30 bg-indigo-950/15',
    emerald: 'border-emerald-500/30 bg-emerald-950/15',
    rose: 'border-rose-500/30 bg-rose-950/15',
    slate: 'border-slate-700/60 bg-slate-950/30',
  };
  const headerCls: Record<typeof tone, string> = {
    cyan: 'text-cyan-200',
    amber: 'text-amber-200',
    indigo: 'text-indigo-200',
    emerald: 'text-emerald-200',
    rose: 'text-rose-200',
    slate: 'text-slate-200',
  };
  return (
    <section
      className={
        'space-y-3 rounded-2xl border p-4 ' + toneCls[tone]
      }
    >
      <header className="flex flex-wrap items-center gap-2 text-[10px] font-mono uppercase tracking-widest">
        <span className={headerCls[tone]}>{badge}</span>
      </header>
      {hint && <p className="text-[11px] italic text-slate-400">{hint}</p>}
      {children}
    </section>
  );
}

async function ReceiptThumb({
  receipt,
  receiptUrlPromise,
  size,
}: {
  receipt: WaybillSlip | null;
  receiptUrlPromise: Promise<string | null>;
  size?: 'sm' | 'md';
}) {
  const url = await receiptUrlPromise;
  const dims = size === 'sm' ? 'h-20 w-20' : 'h-32 w-24';
  if (!receipt) {
    return (
      <div
        className={
          'flex shrink-0 items-center justify-center rounded-xl border border-dashed border-slate-700 bg-slate-950/40 ' +
          dims
        }
      >
        <span aria-hidden className="text-2xl text-slate-600">
          📄
        </span>
      </div>
    );
  }
  return (
    <a
      href={url ?? '#'}
      target="_blank"
      rel="noreferrer"
      className={
        'block shrink-0 overflow-hidden rounded-xl border border-slate-700/70 bg-slate-950/60 ' +
        dims
      }
      title={receipt.file_path.split('/').slice(-1)[0]}
    >
      {url && isImage(receipt.mime_type) ? (
        <img
          src={url}
          alt="receipt"
          className="h-full w-full object-cover"
        />
      ) : (
        <div className="grid h-full w-full place-items-center text-center text-[10px] font-mono text-slate-400">
          📄 {receipt.mime_type}
        </div>
      )}
    </a>
  );
}

async function BookBankThumb({
  bookBank,
  bookUrlPromise,
}: {
  bookBank: WaybillSlip | null;
  bookUrlPromise: Promise<string | null>;
}) {
  const url = await bookUrlPromise;
  const dims = 'h-24 w-20';
  if (!bookBank) {
    return (
      <div
        className={
          'flex shrink-0 items-center justify-center rounded-xl border border-dashed border-slate-700 bg-slate-950/40 ' +
          dims
        }
      >
        <span aria-hidden className="text-2xl text-slate-600">
          🏦
        </span>
      </div>
    );
  }
  return (
    <a
      href={url ?? '#'}
      target="_blank"
      rel="noreferrer"
      className={
        'block shrink-0 overflow-hidden rounded-xl border border-slate-700/70 bg-slate-950/60 ' +
        dims
      }
      title={bookBank.file_path.split('/').slice(-1)[0]}
    >
      {url && isImage(bookBank.mime_type) ? (
        <img
          src={url}
          alt="book bank"
          className="h-full w-full object-cover"
        />
      ) : (
        <div className="grid h-full w-full place-items-center text-center text-[10px] font-mono text-slate-400">
          🏦 {bookBank.mime_type}
        </div>
      )}
    </a>
  );
}

function Field({
  label,
  value,
  mono,
  accent,
}: {
  label: React.ReactNode;
  value: React.ReactNode;
  mono?: boolean;
  accent?: string;
}) {
  return (
    <div>
      <dt className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
        {label}
      </dt>
      <dd
        className={
          'mt-0.5 truncate text-sm text-slate-100' +
          (mono ? ' font-mono' : '') +
          (accent ? ' ' + accent : '')
        }
        title={typeof value === 'string' ? value : undefined}
      >
        {value}
      </dd>
    </div>
  );
}

async function SubmissionContext({
  picture,
  receipt,
  receiptUrlPromise,
  bookBank,
  bookUrlPromise,
  locale,
}: {
  picture: ExpenseFullPicture;
  receipt: WaybillSlip | null;
  receiptUrlPromise: Promise<string | null>;
  bookBank: WaybillSlip | null;
  bookUrlPromise: Promise<string | null>;
  locale: SecondaryLocale;
}) {
  const { expense, items } = picture;
  const thumb = await ReceiptThumb({ receipt, receiptUrlPromise });
  const bookThumb = await BookBankThumb({ bookBank, bookUrlPromise });
  const bookHref = await bookUrlPromise;
  const fmtDate = (d: Date | string | null) => formatDateServer(d, locale);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, locale);
  return (
    <ContextShell
      tone="cyan"
      badge="📤 Submission package"
      hint={<Bilingual en="Everything the submitter attached" th="ข้อมูลทั้งหมดที่ผู้ส่งแนบ" locale={locale} />}
    >
      <div className="flex flex-wrap items-start gap-4">
        {thumb}
        <dl className="grid flex-1 grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-4">
          <Field label={<Bilingual en="Created by (Vendor)" th="ผู้ขาย" locale={locale} />} value={expense.vendor_name ?? '—'} mono />
          <Field label={<Bilingual en="Vendor Address" th="ที่อยู่ผู้ขาย" locale={locale} />} value={expense.vendor_address ?? '—'} mono />
          <Field label={<Bilingual en="Created to (Customer)" th="ลูกค้า" locale={locale} />} value={expense.created_to ?? '—'} mono />
          <Field label={<Bilingual en="Customer Address" th="ที่อยู่ลูกค้า" locale={locale} />} value={expense.created_to_address ?? '—'} mono />
          <Field label={<Bilingual en="Date" th="วันที่" locale={locale} />} value={fmtDate(expense.transaction_date)} mono />
          <Field label={<Bilingual en="Payment" th="การชำระ" locale={locale} />} value={paymentLabel(expense.payment_method)} mono />
          <Field label={<Bilingual en="Items" th="รายการ" locale={locale} />} value={`${items.length}`} mono />
          <Field label={<Bilingual en="Subtotal" th="ยอดก่อน VAT" locale={locale} />} value={fmtMoney(expense.subtotal)} mono />
          <Field label={<Bilingual en="VAT" th="VAT" locale={locale} />} value={fmtMoney(expense.vat_amount)} mono />
          <Field
            label={<Bilingual en="Total" th="รวม" locale={locale} />}
            value={fmtMoney(expense.total_amount)}
            mono
            accent="text-emerald-300 font-bold"
          />
          <Field
            label={<Bilingual en="Receipt" th="สลิป" locale={locale} />}
            value={receipt ? `${receipt.mime_type} · ${fmtSize(receipt.file_size)}` : '—'}
            mono
          />
        </dl>
      </div>
      {expense.payment_method === 'transfer' && bookBank && (
        <div className="rounded-xl border border-indigo-500/30 bg-indigo-950/20 p-3 text-xs">
          <div className="flex items-center justify-between gap-2 text-[10px] font-mono uppercase tracking-widest text-indigo-200">
            <span>🏦 {<Bilingual en="Book bank (transfer)" th="สมุดบัญชี (โอน)" locale={locale} />}</span>
            {bookHref && (
              <a href={bookHref} target="_blank" rel="noreferrer" className="text-cyan-300 hover:underline">
                {<Bilingual en="open slip ↗" th="เปิดสลิป ↗" locale={locale} />}
              </a>
            )}
          </div>
          <div className="mt-2 flex items-start gap-3">
            {bookThumb}
            <div className="grid flex-1 grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-4">
              <Field label="Bank" value={bookBank.bank_name ?? '—'} />
              <Field label="Branch" value={bookBank.bank_branch ?? '—'} />
              <Field label={<Bilingual en="Account #" th="เลขบัญชี" locale={locale} />} value={bookBank.account_number ?? '—'} mono accent="text-cyan-300" />
              <Field label={<Bilingual en="Name" th="ชื่อ" locale={locale} />} value={bookBank.account_name ?? '—'} />
            </div>
          </div>
        </div>
      )}
    </ContextShell>
  );
}

async function DeptContext({
  picture,
  receipt,
  receiptUrlPromise,
  locale,
}: {
  picture: ExpenseFullPicture;
  receipt: WaybillSlip | null;
  receiptUrlPromise: Promise<string | null>;
  locale: SecondaryLocale;
}) {
  const { expense } = picture;
  const thumb = await ReceiptThumb({ receipt, receiptUrlPromise, size: 'sm' });
  const fmtDate = (d: Date | string | null) => formatDateServer(d, locale);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, locale);
  return (
    <ContextShell
      tone="amber"
      badge="👥 Dept-level check"
      hint={
        <Bilingual en="Confirm this employee in your dept actually incurred this expense — no duplicates." th="ยืนยันว่าพนักงานในแผนกของคุณใช้จ่ายจริง ไม่ซ้ำซ้อน" locale={locale} />
      }
    >
      <div className="flex flex-wrap items-center gap-4">
        {thumb}
        <dl className="grid flex-1 grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-3">
          <Field label={<Bilingual en="Vendor" th="ผู้ขาย" locale={locale} />} value={expense.vendor_name ?? '—'} mono />
          <Field label={<Bilingual en="Date" th="วันที่" locale={locale} />} value={fmtDate(expense.transaction_date)} mono />
          <Field label={<Bilingual en="Payment" th="การชำระ" locale={locale} />} value={paymentLabel(expense.payment_method)} mono />
          <Field
            label={<Bilingual en="Total" th="ยอดรวม" locale={locale} />}
            value={fmtMoney(expense.total_amount)}
            mono
            accent="text-amber-200 font-bold text-base"
          />
          <Field
            label={<Bilingual en="EXP" th="EXP" locale={locale} />}
            value={`EXP-${expense.id}`}
            mono
            accent="text-cyan-300"
          />
          <Field
            label={<Bilingual en="Submitter" th="ส่งโดย" locale={locale} />}
            value={expense.submitter_id ? `#${expense.submitter_id}` : '—'}
            mono
          />
        </dl>
      </div>
      <p className="text-[10px] font-mono text-slate-500">
        {<Bilingual en="💡 Verify the slip, amount, vendor, date — line-item breakdown is in the audit section below." th="💡 ตรวจสลิป, ยอด, ผู้ขาย, วันที่ — รายการย่อยดูได้ที่แท็บ Line items ด้านล่าง" locale={locale} />}
      </p>
    </ContextShell>
  );
}

function AccountingContext({
  picture,
  locale,
}: {
  picture: ExpenseFullPicture;
  locale: SecondaryLocale;
}) {
  const { expense, items } = picture;
  const subtotal = parseFloat(expense.subtotal ?? '0') || 0;
  const vat = parseFloat(expense.vat_amount ?? '0') || 0;
  const total = parseFloat(expense.total_amount ?? '0') || 0;
  const vatPct = subtotal > 0 ? ((vat / subtotal) * 100).toFixed(2) : '—';
  const sumItems = items.reduce((acc, it) => acc + (parseFloat(it.amount) || 0), 0);
  const diff = (total - (subtotal + vat)).toFixed(2);
  const _fmtDate = (d: Date | string | null) => formatDateServer(d, locale);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, locale);
  return (
    <ContextShell
      tone="indigo"
      badge="🧮 Accounting review"
      hint={
        <Bilingual en="Validate line items, mapped accounts, and VAT math." th="ตรวจสอบรายการย่อย, บัญชีที่ map, และภาษี" locale={locale} />
      }
    >
      <div className="grid gap-3 sm:grid-cols-4">
        <Field
          label={<Bilingual en="Subtotal" th="ยอดก่อน VAT" locale={locale} />}
          value={fmtMoney(expense.subtotal)}
          mono
        />
        <Field label={<Bilingual en="VAT" th="VAT" locale={locale} />} value={`${fmtMoney(expense.vat_amount)} (${vatPct}%)`} mono />
        <Field
          label={<Bilingual en="Total" th="ผลรวม" locale={locale} />}
          value={fmtMoney(expense.total_amount)}
          mono
          accent="text-indigo-200 font-bold"
        />
        <Field
          label={<Bilingual en="Sub+VAT vs Total" th="ส่วนต่าง" locale={locale} />}
          value={`${diff}`}
          mono
          accent={parseFloat(diff) === 0 ? 'text-emerald-300' : 'text-rose-300'}
        />
      </div>

      <div>
        <div className="flex items-center justify-between text-[10px] font-mono uppercase tracking-widest text-slate-500">
          <span>{<Bilingual en="Line items" th="รายการย่อย" locale={locale} />} ({items.length})</span>
          <span>
            {<Bilingual en="Σ" th="ผลรวม" locale={locale} />}{' '}
            <span className={Math.abs(sumItems - subtotal) < 0.01 ? 'text-emerald-300' : 'text-rose-300'}>
              {fmtMoney(sumItems.toString())}
            </span>
          </span>
        </div>
        {items.length === 0 ? (
          <p className="mt-1 text-xs italic text-slate-500">
            {<Bilingual en="no items — using single amount from slip" th="ไม่มีรายการ — ใช้ยอดเดียวจากใบเสร็จ" locale={locale} />}
          </p>
        ) : (
          <ul className="mt-2 divide-y divide-slate-800/40 rounded-xl border border-slate-800/60 bg-slate-950/40">
            {items.map((it) => (
              <li key={it.id} className="flex items-center justify-between gap-3 px-3 py-2 text-xs">
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium text-slate-100">{it.description}</div>
                  <div className="mt-0.5 flex flex-wrap gap-x-2 font-mono text-[10px] text-slate-500">
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
                <div className="shrink-0 font-mono text-sm font-semibold text-cyan-200">
                  {fmtMoney(it.amount)}
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </ContextShell>
  );
}

async function FinalContext({
  picture,
  bookBank,
  bookUrlPromise,
  locale,
}: {
  picture: ExpenseFullPicture;
  bookBank: WaybillSlip | null;
  bookUrlPromise: Promise<string | null>;
  locale: SecondaryLocale;
}) {
  const { expense } = picture;
  const bookThumb = await BookBankThumb({ bookBank, bookUrlPromise });
  const bookHref = await bookUrlPromise;
  const fmtDate = (d: Date | string | null) => formatDateServer(d, locale);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, locale);
  return (
    <ContextShell
      tone="emerald"
      badge="🔒 Final sign-off"
      hint={
        <Bilingual en="Final figure to post. Final approve = GL post · Final reject = close without posting." th="ตัวเลขสุดท้ายที่จะบันทึกบัญชี — กด Final approve = บันทึก, Final reject = ปิดไม่บันทึก" locale={locale} />
      }
    >
      <div className="grid gap-3 sm:grid-cols-4">
        <Field
          label={<Bilingual en="Total" th="ยอดรวม" locale={locale} />}
          value={fmtMoney(expense.total_amount)}
          mono
          accent="text-emerald-300 text-2xl font-extrabold"
        />
        <Field label={<Bilingual en="Vendor" th="ผู้ขาย" locale={locale} />} value={expense.vendor_name ?? '—'} mono />
        <Field label={<Bilingual en="Date" th="วันที่" locale={locale} />} value={fmtDate(expense.transaction_date)} mono />
        <Field
          label={<Bilingual en="Payment" th="การชำระ" locale={locale} />}
          value={paymentLabel(expense.payment_method)}
          mono
        />
      </div>
      {expense.payment_method === 'transfer' && bookBank && (
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-950/15 p-3 text-xs">
          <div className="flex items-center justify-between gap-2 text-[10px] font-mono uppercase tracking-widest text-emerald-200">
            <span>🏦 {<Bilingual en="Transfer to" th="โอนไปที่" locale={locale} />}</span>
            {bookHref && (
              <a href={bookHref} target="_blank" rel="noreferrer" className="text-cyan-300 hover:underline">
                {<Bilingual en="open slip ↗" th="เปิดสลิป ↗" locale={locale} />}
              </a>
            )}
          </div>
          <div className="mt-2 flex items-start gap-3">
            {bookThumb}
            <div className="grid flex-1 grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-4">
              <Field label="Bank" value={bookBank.bank_name ?? '—'} />
              <Field label={<Bilingual en="Branch" th="สาขา" locale={locale} />} value={bookBank.bank_branch ?? '—'} />
              <Field
                label={<Bilingual en="Account #" th="เลขบัญชี" locale={locale} />}
                value={bookBank.account_number ?? '—'}
                mono
                accent="text-emerald-300"
              />
              <Field label={<Bilingual en="Account name" th="ชื่อบัญชี" locale={locale} />} value={bookBank.account_name ?? '—'} />
            </div>
          </div>
        </div>
      )}
    </ContextShell>
  );
}

async function AwaitingDisbursementContext({
  picture,
  bookBank,
  bookUrlPromise,
  locale
}: {
  picture: ExpenseFullPicture;
  bookBank: WaybillSlip | null;
  bookUrlPromise: Promise<string | null>;
  locale: SecondaryLocale;
}) {
  const { expense } = picture;
  const bookThumb = await BookBankThumb({ bookBank, bookUrlPromise });
  const bookHref = await bookUrlPromise;
  const _fmtDate = (d: Date | string | null) => formatDateServer(d, locale);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, locale);
  return (
    <ContextShell
      tone="cyan"
      badge="💸 Disbursement"
      hint={
        <Bilingual en="Attach the payment slip and pick the payout method." th="แนบสลิปการจ่ายและเลือกวิธีการจ่าย" locale={locale} />
      }
    >
      <div className="grid gap-3 sm:grid-cols-3">
        <Field
          label={<Bilingual en="Amount to pay" th="ยอดที่ต้องจ่าย" locale={locale} />}
          value={fmtMoney(expense.total_amount)}
          mono
          accent="text-cyan-200 text-xl font-extrabold"
        />
        <Field
          label={<Bilingual en="Requested method" th="วิธีจ่ายที่ขอ" locale={locale} />}
          value={paymentLabel(expense.payment_method)}
          mono
        />
        <Field
          label={<Bilingual en="EXP" th="EXP" locale={locale} />}
          value={`EXP-${expense.id}`}
          mono
          accent="text-cyan-300"
        />
      </div>
      {expense.payment_method === 'transfer' && bookBank ? (
        <div className="rounded-xl border border-cyan-500/40 bg-cyan-950/20 p-4">
          <div className="flex items-center justify-between gap-2 text-[10px] font-mono uppercase tracking-widest text-cyan-200">
            <span>🏦 {<Bilingual en="Wire to" th="โอนไปที่" locale={locale} />}</span>
            {bookHref && (
              <a href={bookHref} target="_blank" rel="noreferrer" className="text-cyan-300 hover:underline">
                {<Bilingual en="view original slip ↗" th="เปิดสลิปต้นฉบับ ↗" locale={locale} />}
              </a>
            )}
          </div>
          <div className="mt-3 flex items-start gap-3">
            {bookThumb}
            <div className="grid flex-1 grid-cols-2 gap-3 sm:grid-cols-4">
              <div className="sm:col-span-2">
                <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
                  {<Bilingual en="Account name" th="ชื่อบัญชี" locale={locale} />}
                </div>
                <div className="mt-0.5 truncate text-base font-bold text-white" title={bookBank.account_name ?? ''}>
                  {bookBank.account_name ?? '—'}
                </div>
              </div>
              <div>
                <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
                  {<Bilingual en="Bank" th="ธนาคาร" locale={locale} />}
                </div>
                <div className="mt-0.5 truncate text-base text-slate-100">
                  {bookBank.bank_name ?? '—'}
                </div>
              </div>
              <div>
                <div className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
                  {<Bilingual en="Account #" th="เลขบัญชี" locale={locale} />}
                </div>
                <div className="mt-0.5 font-mono text-base font-bold text-cyan-300">
                  {bookBank.account_number ?? '—'}
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <p className="text-xs text-slate-400">
          {<Bilingual en="⚠ no book-bank slip — pay cash / credit and attach proof." th="⚠ ไม่มีสลิปสมุดบัญชี — โอนตรงให้ผู้ส่งหรือจ่ายเงินสด" locale={locale} />}
        </p>
      )}
    </ContextShell>
  );
}

async function DisbursedContext({
  picture,
  receipt,
  receiptUrlPromise,
  bookBank,
  hasGlConfirmed,
  locale
}: {
  picture: ExpenseFullPicture;
  receipt: WaybillSlip | null;
  receiptUrlPromise: Promise<string | null>;
  bookBank: WaybillSlip | null;
  hasGlConfirmed: boolean;
  locale: SecondaryLocale;
}) {
  const { expense } = picture;
  const thumb = await ReceiptThumb({ receipt, receiptUrlPromise, size: 'sm' });
  const _fmtDate = (d: Date | string | null) => formatDateServer(d, locale);
  const fmtMoney = (n: string | number | null) => formatMoneyServer(n, locale);
  return (
    <ContextShell
      tone="emerald"
      badge={hasGlConfirmed ? '✅ Disbursed · GL confirmed' : '✅ Disbursed · GL posted'}
      hint={
        hasGlConfirmed
          ? <Bilingual en="Money out + GL confirmed — closed." th="เงินออกแล้ว + ยืนยันบัญชีแล้ว — ปิดรายการ" locale={locale} />
          : <Bilingual en="Money out + GL posted — waiting on an accounting officer to confirm GL." th="เงินออกแล้ว + ลงบัญชีแล้ว — รอเจ้าหน้าที่กดยืนยัน GL" locale={locale} />
      }
    >
      <div className="flex flex-wrap items-center gap-4">
        {thumb}
        <dl className="grid flex-1 grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-3">
          <Field
            label={<Bilingual en="Paid" th="ยอดจ่าย" locale={locale} />}
            value={fmtMoney(expense.total_amount)}
            mono
            accent="text-emerald-300 font-bold text-base"
          />
          <Field label={<Bilingual en="Method" th="การชำระ" locale={locale} />} value={paymentLabel(expense.payment_method)} mono />
          <Field label={<Bilingual en="EXP" th="EXP" locale={locale} />} value={`EXP-${expense.id}`} mono accent="text-cyan-300" />
          <Field
            label="GL post"
            value={
              <span
                className={
                  'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-mono uppercase tracking-widest ' +
                  (hasGlConfirmed
                    ? 'border-emerald-500/40 bg-emerald-500/15 text-emerald-200'
                    : 'border-amber-500/40 bg-amber-500/15 text-amber-200')
                }
              >
                <span aria-hidden>{hasGlConfirmed ? '✓' : '◌'}</span>
                <span>{hasGlConfirmed ? 'confirmed' : 'posted, awaiting confirm'}</span>
              </span>
            }
          />
          <Field
            label={<Bilingual en="Wire to" th="โอนไป" locale={locale} />}
            value={
              bookBank?.account_number ? (
                <span className="font-mono">
                  <span className="text-cyan-300">{bookBank.account_number}</span>
                  <span className="ml-1 text-slate-400">· {bookBank.account_name ?? '—'}</span>
                </span>
              ) : (
                '—'
              )
            }
          />
          <Field
            label={<Bilingual en="Receipt" th="ใบเสร็จ" locale={locale} />}
            value={receipt ? `${receipt.mime_type}` : '—'}
            mono
          />
        </dl>
      </div>
    </ContextShell>
  );
}
