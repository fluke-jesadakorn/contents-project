'use client';

import React, { forwardRef, useEffect, useImperativeHandle, useRef, useState } from 'react';
import Link from 'next/link';
import { Modal } from './ui/Modal';
import {
  submitExpenseFromSlip,
  discardSlip,
  getSlipLockState,
} from '../app/actions';
import type { VisionModel } from '@/lib/ai/loadVisionModels';

const MODEL_STORAGE_KEY = 'slip.ocrModel';

type ParsedFields = {
  vendorName?: string;
  vendorAddress?: string;
  createdTo?: string;
  createdToAddress?: string;
  transactionDate?: string;
  paymentMethod?: string;
  subtotal?: number;
  vatAmount?: number;
  totalAmount?: number;
  currency?: string;
  items?: Array<{ description: string; qty?: number; unitPrice?: number; amount: number }>;
  isCorrupted?: boolean;
  correctionNotes?: string;
  bankName?: string;
  bankBranch?: string;
  accountNumber?: string;
  accountName?: string;
};

type UploadOk = {
  slipId: number;
  status: 'pending' | 'confirmed';
  parsed: ParsedFields;
  confidence: number;
  mode: string;
  fileKey: string;
  fileUrl: string;
  mime: string;
  size: number;
  kind?: 'receipt' | 'book_bank';
  validation?: {
    ok: boolean;
    errors: Array<{ code: string; severity: 'error' | 'warning'; field?: string; message: string }>;
    warnings: Array<{ code: string; severity: 'error' | 'warning'; field?: string; message: string }>;
    retried: boolean;
    summary: string;
  };
};

type Phase = 'idle' | 'extracting' | 'confirming' | 'confirmed';
type ExtractionState = 'pending' | 'running' | 'done';

export type SlipKind = 'receipt' | 'book_bank';

export interface BookBankFields {
  bankName: string;
  bankBranch: string;
  accountNumber: string;
  accountName: string;
}

interface SlipUploadProps {
  kind?: SlipKind;
  onConfirmed?: (result: { slipId: number; expenseId: number; status: string; waybillId?: string }) => void;
  onSlipReady?: (slipId: number, kind: SlipKind) => void;
  onSlipDiscarded?: (slipId: number, kind: SlipKind) => void;
  onPaymentChange?: (next: 'cash' | 'credit_card' | 'transfer') => void;
  currentUserId?: number;
  initialModels?: VisionModel[];
  bookBankSlipId?: number | null;
  bookBankFields?: BookBankFields;
  onBookBankFieldsChange?: (f: BookBankFields) => void;
  hideSubmitButton?: boolean;
  autoExtract?: boolean;
  onSubmitStateChange?: (state: SubmitState) => void;
  draftWaybillId?: string | null;
  onDraftStarted?: (info: { waybillId: string; expenseId: number }) => void;
}

export interface SlipDraftFields {
  vendorName: string;
  vendorAddress: string;
  createdTo: string;
  createdToAddress: string;
  transactionDate: string;
  paymentMethod: 'cash' | 'credit_card' | 'transfer';
  subtotal: number;
  vatAmount: number;
  totalAmount: number;
}

export interface SubmitState {
  visible: boolean;
  canConfirm: boolean;
  confirming: boolean;
  pendingFile: boolean;
  isBookBank: boolean;
  error: string | null;
  hint: 'ok' | 'transfer-needs-bookbank' | 'missing-fields';
  parsed: SlipDraftFields | null;
  slipId: number | null;
}

export interface SlipUploadHandle {
  submit: () => Promise<void>;
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

function Stars({ value }: { value: number | null }) {
  if (value == null) return <span className="text-slate-600 text-[10px]">—</span>;
  const filled = Math.max(0, Math.min(5, Math.round(value)));
  return (
    <span className="inline-flex items-center gap-px text-[11px] leading-none font-mono" aria-label={`${filled} of 5`}>
      {Array.from({ length: 5 }, (_, i) => (
        <span key={i} className={i < filled ? 'text-amber-400' : 'text-slate-700'}>
          {i < filled ? '★' : '☆'}
        </span>
      ))}
    </span>
  );
}

function ModelCard({
  m,
  selected,
  onSelect,
  testId,
  disabled,
}: {
  m: VisionModel;
  selected: boolean;
  onSelect: (name: string) => void;
  testId: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={() => onSelect(m.name)}
      disabled={disabled}
      data-testid={testId}
      className={`text-left rounded-xl border p-3 transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${
        selected
          ? 'border-emerald-500/60 bg-emerald-500/10'
          : 'border-slate-800 bg-slate-900/40 hover:border-slate-600 hover:bg-slate-900/70'
      }`}
    >
      <div className="flex items-start gap-2">
        <span
          className={`mt-1 inline-block w-3 h-3 rounded-full border shrink-0 ${
            selected
              ? 'border-emerald-400 bg-emerald-400 shadow-[0_0_0_2px_rgba(16,185,129,0.25)]'
              : 'border-slate-600'
          }`}
          aria-hidden
        />
        <div className="flex-1 min-w-0 space-y-1">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs font-bold text-white font-mono truncate">{m.name}</span>
            <span className="px-1.5 py-0.5 rounded bg-slate-800/80 text-[9px] font-mono text-slate-400 uppercase tracking-wider">
              {m.provider_name}
            </span>
          </div>
          {m.description && (
            <p className="text-[10px] text-slate-400 leading-snug break-words">{m.description}</p>
          )}
          {(m.speed_rating != null || m.accuracy_rating != null) && (
            <div className="grid grid-cols-2 gap-x-3 gap-y-0.5 pt-1 border-t border-slate-800/60">
              <div className="flex items-center justify-between gap-1.5">
                <span className="text-[9px] font-mono text-slate-500 uppercase tracking-wider">Speed</span>
                <Stars value={m.speed_rating} />
              </div>
              <div className="flex items-center justify-between gap-1.5">
                <span className="text-[9px] font-mono text-slate-500 uppercase tracking-wider">Accuracy</span>
                <Stars value={m.accuracy_rating} />
              </div>
            </div>
          )}
        </div>
      </div>
    </button>
  );
}

function FilledTick({ filled }: { filled: boolean }) {
  if (!filled) return null;
  return (
    <span
      className="absolute right-2.5 top-1/2 -translate-y-1/2 flex items-center justify-center w-5 h-5 rounded-full bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/30 pointer-events-none"
      aria-label="filled"
      data-testid="field-filled"
      title="Filled"
    >
      <svg className="w-2.5 h-2.5 stroke-[3.5] stroke-current fill-none" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12.75l6 6 9-13.5" />
      </svg>
    </span>
  );
}

function fileKind(mime: string, name?: string): string {
  const m = (mime || '').toLowerCase();
  if (m.startsWith('image/jpeg') || /\.jpe?g$/i.test(name || '')) return 'JPG';
  if (m.startsWith('image/png') || /\.png$/i.test(name || '')) return 'PNG';
  if (m.startsWith('image/webp') || /\.webp$/i.test(name || '')) return 'WEBP';
  if (m === 'application/pdf' || /\.pdf$/i.test(name || '')) return 'PDF';
  return (m.split('/')[1] || 'FILE').toUpperCase();
}

export const SlipUpload: React.ForwardRefExoticComponent<
  SlipUploadProps & React.RefAttributes<SlipUploadHandle>
> = forwardRef<SlipUploadHandle, SlipUploadProps>(function SlipUpload({
  kind = 'receipt',
  onConfirmed,
  onSlipReady,
  onSlipDiscarded,
  onPaymentChange,
  currentUserId,
  initialModels = [],
  bookBankSlipId = null,
  bookBankFields,
  onBookBankFieldsChange,
  hideSubmitButton = false,
  autoExtract = true,
  onSubmitStateChange,
  draftWaybillId = null,
}, ref) {
  const isBookBank = kind === 'book_bank';
  const inputRef = useRef<HTMLInputElement | null>(null);
  const xhrRef = useRef<XMLHttpRequest | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [phase, setPhase] = useState<Phase>('idle');
  const [extractionState, setExtractionState] = useState<ExtractionState>('pending');
  const [elapsed, setElapsed] = useState(0);
  const extractStartRef = useRef<number | null>(null);
  const [slipId, setSlipId] = useState<number | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const [confidence, setConfidence] = useState<number>(0);
  const [mode, setMode] = useState<string>('');

  const [vendor, setVendor] = useState('');
  const [vendorAddress, setVendorAddress] = useState('');
  const [createdTo, setCreatedTo] = useState('');
  const [createdToAddress, setCreatedToAddress] = useState('');
  const [date, setDate] = useState('');
  const [payment, setPayment] = useState<'cash' | 'credit_card' | 'transfer'>('cash');
  const [subtotal, setSubtotal] = useState('0');
  const [vat, setVat] = useState('0');
  const [total, setTotal] = useState('0');
  const [items, setItems] = useState<Array<{ description: string; qty?: number; unitPrice?: number; amount: number }>>([]);

  const updateItemDesc = (index: number, desc: string) => {
    const next = [...items];
    next[index] = { ...next[index], description: desc };
    setItems(next);
  };

  const updateItemQty = (index: number, val: string) => {
    const next = [...items];
    const qty = Number(val) || 0;
    const up = next[index].unitPrice ?? next[index].amount ?? 0;
    next[index] = { ...next[index], qty, unitPrice: up, amount: qty * up };
    setItems(next);
  };

  const updateItemUnitPrice = (index: number, val: string) => {
    const next = [...items];
    const unitPrice = Number(val) || 0;
    const q = next[index].qty ?? 1;
    next[index] = { ...next[index], unitPrice, amount: q * unitPrice };
    setItems(next);
  };

  const updateItemAmount = (index: number, val: string) => {
    const next = [...items];
    const amount = Number(val) || 0;
    next[index] = { ...next[index], amount };
    setItems(next);
  };

  const addItem = () => {
    setItems([...items, { description: '', qty: 1, unitPrice: 0, amount: 0 }]);
  };

  const removeItem = (index: number) => {
    setItems(items.filter((_, i) => i !== index));
  };

  const [ocrVendor, setOcrVendor] = useState('');
  const [ocrVendorAddress, setOcrVendorAddress] = useState('');
  const [ocrCreatedTo, setOcrCreatedTo] = useState('');
  const [ocrCreatedToAddress, setOcrCreatedToAddress] = useState('');
  const [ocrDate, setOcrDate] = useState('');
  const [ocrPayment, setOcrPayment] = useState<'cash' | 'credit_card' | 'transfer'>('cash');
  const [ocrSubtotal, setOcrSubtotal] = useState('0');
  const [ocrVat, setOcrVat] = useState('0');
  const [ocrTotal, setOcrTotal] = useState('0');

  const [bankName, setBankName] = useState('');
  const [bankBranch, setBankBranch] = useState('');
  const [accountNumber, setAccountNumber] = useState('');
  const [accountName, setAccountName] = useState('');

  function applyBankFields(b: { bankName?: string; bankBranch?: string; accountNumber?: string; accountName?: string }) {
    const next: BookBankFields = {
      bankName: b.bankName ?? '',
      bankBranch: b.bankBranch ?? '',
      accountNumber: b.accountNumber ?? '',
      accountName: b.accountName ?? '',
    };
    setBankName(next.bankName);
    setBankBranch(next.bankBranch);
    setAccountNumber(next.accountNumber);
    setAccountName(next.accountName);
    onBookBankFieldsChange?.(next);
  }

  const [confirmedExpenseId, setConfirmedExpenseId] = useState<number | null>(null);
  const [confirmedStatus, setConfirmedStatus] = useState<string | null>(null);
  const [locked, setLocked] = useState(false);
  const [lockReason, setLockReason] = useState<string | null>(null);
  const [zoomOpen, setZoomOpen] = useState(false);

  const [visionModels] = useState<VisionModel[]>(initialModels);
  const [selectedModel, setSelectedModel] = useState<string>('');
  const [validation, setValidation] = useState<UploadOk['validation']>(undefined);

  useEffect(() => {
    if (!selectedModel && visionModels.length > 0) {
      const saved = typeof window !== 'undefined' ? window.localStorage.getItem(MODEL_STORAGE_KEY) : null;
      if (saved && visionModels.some(m => m.name === saved)) {
        setSelectedModel(saved);
      } else {
        setSelectedModel(visionModels[0].name);
      }
    }
  }, [visionModels, selectedModel]);

  useEffect(() => {
    return () => {
      if (preview) URL.revokeObjectURL(preview);
    };
  }, [preview]);

  useEffect(() => {
    if (extractionState !== 'running') {
      extractStartRef.current = null;
      setElapsed(0);
      return;
    }
    extractStartRef.current = Date.now();
    setElapsed(0);
    const id = setInterval(() => {
      if (extractStartRef.current != null) {
        setElapsed(Math.floor((Date.now() - extractStartRef.current) / 1000));
      }
    }, 500);
    return () => clearInterval(id);
  }, [extractionState]);

  useEffect(() => {
    if (
      autoExtract &&
      selectedModel &&
      pendingFile &&
      extractionState === 'pending' &&
      phase === 'extracting'
    ) {
      void uploadFile(pendingFile);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoExtract, selectedModel, pendingFile, extractionState, phase]);

  function pickModel(name: string) {
    if (name === selectedModel) return;
    setSelectedModel(name);
    try { window.localStorage.setItem(MODEL_STORAGE_KEY, name); } catch { /* ignore */ }
    setValidation(undefined);
    if (extractionState === 'done' && pendingFile && visionModels.length > 0 && phase !== 'confirming') {
      setError(null);
      setExtractionState('running');
      void uploadFile(pendingFile);
    }
  }

  const selectedModelDesc = visionModels.find(m => m.name === selectedModel)?.description ?? null;

  function revokePreview() {
    if (preview) {
      URL.revokeObjectURL(preview);
      setPreview(null);
    }
  }

  function resetUploadState() {
    setSlipId(null);
    setConfidence(0);
    setMode('');
    setVendor('');
    setVendorAddress('');
    setCreatedTo('');
    setCreatedToAddress('');
    setDate('');
    setPayment('cash');
    setSubtotal('0');
    setVat('0');
    setTotal('0');
    setItems([]);
    setOcrVendor('');
    setOcrVendorAddress('');
    setOcrCreatedTo('');
    setOcrCreatedToAddress('');
    setOcrDate('');
    setOcrPayment('cash');
    setOcrSubtotal('0');
    setOcrVat('0');
    setOcrTotal('0');
    setBankName('');
    setBankBranch('');
    setAccountNumber('');
    setAccountName('');
    setConfirmedExpenseId(null);
    setConfirmedStatus(null);
    setLocked(false);
    setLockReason(null);
    setError(null);
    setValidation(undefined);
  }

  function applyParsed(p: ParsedFields) {
    if (isBookBank) {
      applyBankFields({
        bankName: p.bankName,
        bankBranch: p.bankBranch,
        accountNumber: p.accountNumber,
        accountName: p.accountName,
      });
      return;
    }
    const v = p.vendorName ?? '';
    const va = p.vendorAddress ?? '';
    const ct = p.createdTo ?? '';
    const cta = p.createdToAddress ?? '';
    const d = p.transactionDate ?? '';
    const pay: 'cash' | 'credit_card' | 'transfer' = (p.paymentMethod as any) ?? 'cash';
    const sub = String(p.subtotal ?? 0);
    const vt = String(p.vatAmount ?? 0);
    const tot = String(p.totalAmount ?? (Number(p.subtotal ?? 0) + Number(p.vatAmount ?? 0)));
    setVendor(v);
    setOcrVendor(v);
    setVendorAddress(va);
    setOcrVendorAddress(va);
    setCreatedTo(ct);
    setOcrCreatedTo(ct);
    setCreatedToAddress(cta);
    setOcrCreatedToAddress(cta);
    setDate(d);
    setOcrDate(d);
    setPayment(pay);
    setOcrPayment(pay);
    setSubtotal(sub);
    setOcrSubtotal(sub);
    setVat(vt);
    setOcrVat(vt);
    setTotal(tot);
    setOcrTotal(tot);
    setItems(p.items ?? []);
  }

  async function uploadFile(file: File) {
    setError(null);
    setFileName(file.name);
    setPhase('extracting');
    setExtractionState('running');
    try {
      const fd = new FormData();
      fd.append('file', file, file.name);
      if (selectedModel) fd.append('model_name', selectedModel);
      fd.append('kind', kind);
      const xhr = new XMLHttpRequest();
      xhrRef.current = xhr;
      const result: UploadOk = await new Promise((resolve, reject) => {
        xhr.open('POST', '/api/upload');
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            try { resolve(JSON.parse(xhr.responseText)); }
            catch { reject(new Error('Invalid JSON response')); }
          } else {
            try {
              const j = JSON.parse(xhr.responseText);
              reject(new Error(j.detail?.error || j.error || `HTTP ${xhr.status}`));
            } catch {
              reject(new Error(`HTTP ${xhr.status}`));
            }
          }
        };
        xhr.onerror = () => reject(new Error('Network error'));
        xhr.onabort = () => reject(new Error('Aborted'));
        xhr.send(fd);
      });

      setSlipId(result.slipId);
      setConfidence(result.confidence ?? 0);
      setMode(result.mode ?? '');
      setValidation(result.validation ?? undefined);
      applyParsed(result.parsed ?? {});

      if (result.status === 'confirmed') {
        const lock = await getSlipLockState({ slipId: result.slipId, actorId: currentUserId ?? 0 });
        setLocked(lock.locked);
        setLockReason(lock.reason);
        setPhase('confirmed');
      } else {
        setExtractionState('done');
        onSlipReady?.(result.slipId, kind);
      }
      xhrRef.current = null;
    } catch (err: unknown) {
      xhrRef.current = null;
      if (err instanceof Error && err.message === 'Aborted') {
        revokePreview();
        setPendingFile(null);
        setFileName(null);
        setError(null);
        setExtractionState('pending');
        setPhase('idle');
        return;
      }
      setError(err instanceof Error ? err.message : String(err));
      // Keep phase='extracting' but reset to 'pending' so the user can switch model
      // and click Extract again instead of being stuck on the running spinner.
      setExtractionState('pending');
    } finally {
    }
  }

  function selectFile(file: File) {
    setError(null);
    resetUploadState();
    revokePreview();
    if (file.type.startsWith('image/')) {
      setPreview(URL.createObjectURL(file));
    }
    setFileName(file.name);
    setPendingFile(file);
    setPhase('extracting');
    setExtractionState('pending');
    void uploadFile(file);
  }

  async function handleRemove() {
    if (slipId == null) return;
    const removedId = slipId;
    setError(null);
    const r = await discardSlip({ slipId, actorId: currentUserId ?? 0 });
    if (!r.success) {
      setError(r.error ?? 'Remove failed');
      if (r.error?.toLowerCase().includes('locked')) {
        setLocked(true);
        setLockReason(r.error);
      }
      return;
    }
    onSlipDiscarded?.(removedId, kind);
    resetUploadState();
    revokePreview();
    setPendingFile(null);
    setFileName(null);
    setExtractionState('pending');
    setPhase('idle');
  }

  async function handleConfirm() {
    if (slipId == null) return;
    if (isBookBank) {
      setError('Book bank slips are attached when the receipt is confirmed.');
      return;
    }
    if (!canConfirm) {
      if (payment === 'transfer' && !bookBankSlipId) {
        setError('Transfer expenses require a book bank slip.');
      } else {
        setError('Fill vendor + date; subtotal + VAT must equal total.');
      }
      return;
    }
    setError(null);
    setPhase('confirming');
    const overrides: any = {
      vendorName: vendor || undefined,
      vendorAddress: vendorAddress || undefined,
      createdTo: createdTo || undefined,
      createdToAddress: createdToAddress || undefined,
      transactionDate: date || undefined,
      paymentMethod: payment,
      items: items,
    };
    if (payment === 'transfer' && bookBankSlipId && bookBankFields) {
      overrides.bookBankSlipId = bookBankSlipId;
      overrides.bookBankFields = {
        bankName: bookBankFields.bankName || undefined,
        bankBranch: bookBankFields.bankBranch || undefined,
        accountNumber: bookBankFields.accountNumber || undefined,
        accountName: bookBankFields.accountName || undefined,
      };
    }
    const r = await submitExpenseFromSlip({
      slipId,
      actorId: currentUserId ?? 0,
      draftWaybillId: draftWaybillId ?? undefined,
      overrides,
    });
    if (!r.success || r.expenseId == null) {
      setError(r.error ?? 'Confirm failed');
      setExtractionState('done');
      setPhase('extracting');
      return;
    }
    setConfirmedExpenseId(r.expenseId);
    setConfirmedStatus(r.status ?? null);
    const lock = await getSlipLockState({ slipId, actorId: currentUserId ?? 0 });
    setLocked(lock.locked);
    setLockReason(lock.reason);
    setPhase('confirmed');
    onConfirmed?.({
      slipId,
      expenseId: r.expenseId,
      status: r.status ?? 'submission',
      waybillId: r.waybillId ?? undefined,
    });
  }

  function handlePickAnother() {
    resetUploadState();
    revokePreview();
    setPendingFile(null);
    setFileName(null);
    setExtractionState('pending');
    setPhase('idle');
  }

  function onPick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (f) selectFile(f);
    e.target.value = '';
  }

  function onDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault();
    setDragOver(false);
    const f = e.dataTransfer.files?.[0];
    if (f) selectFile(f);
  }

  const confPct = Math.round(confidence * 100);
  const pendingKind = pendingFile ? fileKind(pendingFile.type, pendingFile.name) : '';

  const subN = Number(subtotal);
  const vatN = Number(vat);
  const totalN = Number(total);
  const receiptMathOk =
    subN >= 0 && vatN >= 0 && totalN >= 0 &&
    Math.abs(totalN - (subN + vatN)) <= 0.01;
  const canConfirm =
    !isBookBank &&
    vendor.trim().length > 0 &&
    date.length > 0 && !Number.isNaN(new Date(date).getTime()) &&
    receiptMathOk;
  const editCount =
    (vendor !== ocrVendor ? 1 : 0) +
    (vendorAddress !== ocrVendorAddress ? 1 : 0) +
    (createdTo !== ocrCreatedTo ? 1 : 0) +
    (createdToAddress !== ocrCreatedToAddress ? 1 : 0) +
    (date !== ocrDate ? 1 : 0) +
    (payment !== ocrPayment ? 1 : 0) +
    (subtotal !== ocrSubtotal ? 1 : 0) +
    (vat !== ocrVat ? 1 : 0) +
    (total !== ocrTotal ? 1 : 0);

  const submitState: SubmitState = {
    visible: !isBookBank && !!pendingFile && extractionState === 'done',
    canConfirm,
    confirming: phase === 'confirming',
    pendingFile: !!pendingFile,
    isBookBank,
    error,
    hint: !canConfirm ? 'missing-fields' : 'ok',
    parsed: isBookBank
      ? null
      : ({
          vendorName: vendor,
          vendorAddress: vendorAddress,
          createdTo: createdTo,
          createdToAddress: createdToAddress,
          transactionDate: date,
          paymentMethod: payment,
          subtotal: Number(subtotal) || 0,
          vatAmount: Number(vat) || 0,
          totalAmount: Number(total) || 0,
        } as SlipDraftFields),
    slipId,
  };

  const handleConfirmRef = useRef<() => Promise<void>>(() => Promise.resolve());
  handleConfirmRef.current = handleConfirm;

  useImperativeHandle(ref, () => ({
    submit: () => handleConfirmRef.current(),
  }), []);

  const onSubmitStateChangeRef = useRef(onSubmitStateChange);
  onSubmitStateChangeRef.current = onSubmitStateChange;

  useEffect(() => {
    onSubmitStateChangeRef.current?.(submitState);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    submitState.visible,
    submitState.canConfirm,
    submitState.confirming,
    submitState.pendingFile,
    submitState.isBookBank,
    submitState.error,
    submitState.hint,
    submitState.parsed?.vendorName,
    submitState.parsed?.transactionDate,
    submitState.parsed?.paymentMethod,
    submitState.parsed?.subtotal,
    submitState.parsed?.vatAmount,
    submitState.parsed?.totalAmount,
    submitState.slipId,
  ]);

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-xs font-bold text-slate-200 uppercase tracking-wider flex items-center gap-2 font-mono">
          <span>{isBookBank ? '📖' : '📤'}</span>
          {isBookBank
            ? 'Book Bank (Upload → OCR → Review → Attached on receipt confirm)'
            : 'Slip Upload (Upload → OCR → Review → Confirm)'}
        </h3>
      </div>

      <input
        ref={inputRef}
        type="file"
        accept="image/*,application/pdf"
        onChange={onPick}
        className="hidden"
      />

      {phase !== 'confirmed' && (
        <div className="rounded-2xl border border-slate-800 bg-slate-950/40 p-5 space-y-4">
          <div className="flex items-start gap-4">
            {!pendingFile ? (
              <div
                onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
                onDragLeave={() => setDragOver(false)}
                onDrop={onDrop}
                onClick={() => inputRef.current?.click()}
                className={`shrink-0 w-48 h-64 rounded-xl border-2 border-dashed flex flex-col items-center justify-center gap-2 cursor-pointer transition-colors ${
                  dragOver ? 'border-emerald-400 bg-emerald-500/5' : 'border-slate-700 bg-slate-900/40 hover:border-emerald-500/50'
                }`}
                data-testid="slip-drop-zone"
              >
                <span className="text-4xl">📄</span>
                <p className="text-[10px] font-mono text-slate-400 text-center px-3">
                  Drag &amp; drop a slip<br />or click to browse
                </p>
              </div>
            ) : preview ? (
              <button
                type="button"
                onClick={() => setZoomOpen(true)}
                disabled={extractionState === 'running'}
                className="relative shrink-0 group rounded-xl border border-slate-800 bg-slate-900/60 hover:border-emerald-500/50 transition-colors disabled:cursor-default disabled:hover:border-slate-800"
                title={extractionState === 'running' ? '' : 'Click to enlarge'}
                data-testid="slip-preview-zoom"
              >
                <img
                  src={preview}
                  alt="preview"
                  className={`object-contain rounded-xl bg-slate-950 ${extractionState === 'running' ? 'w-32 h-40' : 'w-48 h-64'}`}
                />
                {extractionState !== 'running' && (
                  <span
                    aria-hidden
                    className="absolute bottom-1.5 right-1.5 grid place-items-center w-6 h-6 rounded-full bg-slate-950/85 ring-1 ring-slate-700/80 text-[11px] text-slate-100 opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    🔍
                  </span>
                )}
              </button>
            ) : (
              <div className={`shrink-0 rounded-xl bg-slate-900/80 flex items-center justify-center text-5xl border border-slate-800 ${extractionState === 'running' ? 'w-32 h-40' : 'w-48 h-64'}`}>📄</div>
            )}
            <div className="flex-1 min-w-0 space-y-2">
              <div className="flex items-center gap-2 flex-wrap">
                <span
                  className={`px-2 py-0.5 rounded-full text-[10px] font-mono uppercase ${
                    !pendingFile
                      ? 'bg-slate-700/40 text-slate-300'
                      : extractionState === 'pending'
                      ? 'bg-slate-700/40 text-slate-300'
                      : extractionState === 'running'
                      ? 'bg-amber-500/15 text-amber-300'
                      : 'bg-emerald-500/20 text-emerald-300'
                  }`}
                  data-testid="slip-step-badge"
                >
                  {!pendingFile && 'Step 1 · Pick model & file'}
                  {pendingFile && extractionState === 'pending' && 'Step 2 · Ready to extract'}
                  {pendingFile && extractionState === 'running' && `Step 2 · Extracting · ${elapsed}s`}
                  {pendingFile && extractionState === 'done' && (canConfirm ? 'Step 2 · Review OCR ✓ filled' : 'Step 2 · Review OCR')}
                </span>
                {pendingFile && (
                  <span className="text-[10px] font-mono text-slate-400">
                    {pendingKind} · {formatBytes(pendingFile.size)}
                  </span>
                )}
                {pendingFile && extractionState === 'done' && (
                  <span className="text-[10px] font-mono text-slate-400">
                    {confPct}% confidence · {mode}
                  </span>
                )}
                {pendingFile && extractionState === 'done' && !isBookBank && editCount > 0 && (
                  <span
                    className="px-2 py-0.5 rounded-full text-[10px] font-mono uppercase bg-indigo-500/15 text-indigo-300 border border-indigo-500/30"
                    data-testid="slip-edits-badge"
                  >
                    ✎ {editCount} edit{editCount === 1 ? '' : 's'}
                  </span>
                )}
                {pendingFile && extractionState === 'done' && canConfirm && (
                  <span
                    className="px-2 py-0.5 rounded-full text-[10px] font-mono uppercase bg-emerald-500/15 text-emerald-300 border border-emerald-500/30"
                    data-testid="slip-status-badge"
                  >
                    ✓ status: filled · ready
                  </span>
                )}
              </div>
              <p className="text-sm font-bold text-white truncate">
                {pendingFile ? pendingFile.name : 'No file selected'}
              </p>
              {pendingFile && extractionState === 'done' && (
                <p className="text-[10px] text-slate-400 font-mono">
                  {isBookBank
                    ? 'Edit any bank field if OCR was wrong. Attached automatically when the receipt is submitted.'
                    : receiptMathOk
                      ? '✓ math balanced — vendor + date + amounts look good. Click Submit to save.'
                      : 'Edit any field if OCR was wrong. Click Send & Confirm to save as draft expense.'}
                </p>
              )}

              {pendingFile && extractionState === 'done' && validation && (validation.errors.length > 0 || validation.warnings.length > 0) && (
                <details
                  className="rounded-lg border border-amber-500/40 bg-amber-500/5 p-3"
                  data-testid="slip-validation-banner"
                >
                  <summary className="text-[10px] font-mono text-amber-300 cursor-pointer flex items-center gap-2 [&::-webkit-details-marker]:hidden">
                    <span>⚠</span>
                    <span>
                      {validation.errors.length > 0
                        ? `OCR flagged ${validation.errors.length} issue${validation.errors.length === 1 ? '' : 's'}`
                        : `${validation.warnings.length} OCR warning${validation.warnings.length === 1 ? '' : 's'}`}
                      {validation.retried && ' (retry attempted)'}
                      {' — review carefully'}
                    </span>
                  </summary>
                  <ul className="mt-2 space-y-1 text-[10px] font-mono">
                    {[...validation.errors, ...validation.warnings].map((iss, i) => (
                      <li key={i} className={iss.severity === 'error' ? 'text-rose-300' : 'text-amber-200/80'}>
                        <span className="text-slate-500">[{iss.code}{iss.field ? `:${iss.field}` : ''}]</span> {iss.message}
                      </li>
                    ))}
                  </ul>
                </details>
              )}

              {extractionState !== 'running' && extractionState !== 'done' && visionModels.length > 0 && (
                <div className="space-y-2 pt-1">
                  <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider">Vision model</span>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2" data-testid="slip-vision-model">
                    {visionModels.map(m => (
                      <div key={m.id} className="min-w-0">
                        <ModelCard
                          m={m}
                          selected={m.name === selectedModel}
                          onSelect={pickModel}
                          testId={`slip-vision-model-${m.id}`}
                          disabled={phase === 'confirming'}
                        />
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {extractionState !== 'running' && extractionState !== 'done' && visionModels.length === 0 && (
                <p className="text-[10px] text-slate-500 italic">Loading models…</p>
              )}

              {extractionState === 'running' && (
                <div className="space-y-2">
                  <p className="text-[10px] text-slate-400 font-mono">
                    Running vision model <span className="text-slate-200">{selectedModel || '…'}</span>
                    {elapsed >= 5 && (
                      <span className="text-slate-500"> · large models can take 1-3 min</span>
                    )}
                  </p>
                  <div className="relative w-full bg-slate-800 h-1.5 rounded-full overflow-hidden">
                    <div
                      className="absolute inset-y-0 left-0 bg-emerald-500/40 w-1/3 rounded-full"
                      style={{ animation: 'slip-indeterminate 1.4s ease-in-out infinite' }}
                    />
                  </div>
                </div>
              )}
            </div>
          </div>

          {!pendingFile && (
            <div className="rounded-xl border border-slate-700 bg-slate-900/40 p-4">
              <p className="text-[11px] font-mono text-center text-slate-400 py-3">
                Drop a slip above or click to pick a file · Supports JPG / PNG / WEBP / PDF · Max 20 MB
              </p>
</div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {isBookBank ? (
              <>
                <Field label="Bank name">
                  <div className="relative">
                    <input
                      value={bankName}
                      onChange={(e) => {
                        const v = e.target.value;
                        setBankName(v);
                        onBookBankFieldsChange?.({
                          bankName: v,
                          bankBranch,
                          accountNumber,
                          accountName,
                        });
                      }}
                      placeholder="e.g. Krungthai, SCB, Kasikorn…"
                      disabled={!pendingFile || phase === 'confirming'}
                      className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                    />
                    {extractionState === 'running' && !bankName && <FieldSpinner />}
                  </div>
                </Field>
                <Field label="Branch" hint="optional">
                  <div className="relative">
                    <input
                      value={bankBranch}
                      onChange={(e) => {
                        const v = e.target.value;
                        setBankBranch(v);
                        onBookBankFieldsChange?.({
                          bankName,
                          bankBranch: v,
                          accountNumber,
                          accountName,
                        });
                      }}
                      placeholder="e.g. 0080 สาขาฟิวเจอร์พาร์ค รังสิต"
                      disabled={!pendingFile || phase === 'confirming'}
                      className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                    />
                    {extractionState === 'running' && !bankBranch && <FieldSpinner />}
                  </div>
                </Field>
                <Field label="Account number">
                  <div className="relative">
                    <input
                      inputMode="numeric"
                      value={accountNumber}
                      onChange={(e) => {
                        const v = e.target.value.replace(/[^\d]/g, '');
                        setAccountNumber(v);
                        onBookBankFieldsChange?.({
                          bankName,
                          bankBranch,
                          accountNumber: v,
                          accountName,
                        });
                      }}
                      placeholder="digits only"
                      disabled={!pendingFile || phase === 'confirming'}
                      className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white font-mono focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                    />
                    {extractionState === 'running' && !accountNumber && <FieldSpinner />}
                  </div>
                </Field>
                <Field label="Account name">
                  <div className="relative">
                    <input
                      value={accountName}
                      onChange={(e) => {
                        const v = e.target.value;
                        setAccountName(v);
                        onBookBankFieldsChange?.({
                          bankName,
                          bankBranch,
                          accountNumber,
                          accountName: v,
                        });
                      }}
                      placeholder="holder name as printed on the passbook"
                      disabled={!pendingFile || phase === 'confirming'}
                      className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                    />
                    {extractionState === 'running' && !accountName && <FieldSpinner />}
                  </div>
                </Field>
              </>
            ) : (
              <>
                {/* Section 1: Created from (Vendor) */}
                <div className="sm:col-span-2 rounded-xl border border-slate-800 bg-slate-900/10 p-3.5 space-y-3">
                  <div className="text-[10px] font-mono text-indigo-400 uppercase tracking-widest font-bold flex items-center gap-1.5">
                    <span>🏢</span> Created from (Vendor)
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <Field label="Vendor Name">
                      <div className="relative">
                        <input
                          value={vendor}
                          onChange={(e) => setVendor(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          placeholder="Vendor Name"
                          data-testid="slip-field-vendor"
                        />
                        {extractionState === 'running' && !vendor ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && vendor.trim() ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                    <Field label="Vendor Address">
                      <div className="relative">
                        <input
                          value={vendorAddress}
                          onChange={(e) => setVendorAddress(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          placeholder="Vendor Address"
                          data-testid="slip-field-vendor-address"
                        />
                        {extractionState === 'running' && !vendorAddress ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && vendorAddress.trim() ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                  </div>
                </div>

                {/* Section 2: Created to (Customer) */}
                <div className="sm:col-span-2 rounded-xl border border-slate-800 bg-slate-900/10 p-3.5 space-y-3">
                  <div className="text-[10px] font-mono text-cyan-400 uppercase tracking-widest font-bold flex items-center gap-1.5">
                    <span>👤</span> Created to (Customer)
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <Field label="Customer Name">
                      <div className="relative">
                        <input
                          value={createdTo}
                          onChange={(e) => setCreatedTo(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          placeholder="Customer Name"
                          data-testid="slip-field-created-to"
                        />
                        {extractionState === 'running' && !createdTo ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && createdTo.trim() ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                    <Field label="Customer Address">
                      <div className="relative">
                        <input
                          value={createdToAddress}
                          onChange={(e) => setCreatedToAddress(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          placeholder="Customer Address"
                          data-testid="slip-field-created-to-address"
                        />
                        {extractionState === 'running' && !createdToAddress ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && createdToAddress.trim() ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                  </div>
                </div>

                {/* Section 3: Transaction Details */}
                <div className="sm:col-span-2 rounded-xl border border-slate-800 bg-slate-900/10 p-3.5 space-y-3">
                  <div className="text-[10px] font-mono text-amber-400 uppercase tracking-widest font-bold flex items-center gap-1.5">
                    <span>📅</span> Transaction Details
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <Field label="Transaction date">
                      <div className="relative">
                        <input
                          type="date"
                          value={date}
                          onChange={(e) => setDate(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          data-testid="slip-field-date"
                        />
                        {extractionState === 'running' && !date ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && date ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                    <Field label="Payment">
                      <div className="relative">
                        <select
                          value={payment}
                          onChange={(e) => {
                            const next = e.target.value as 'cash' | 'credit_card' | 'transfer';
                            setPayment(next);
                            onPaymentChange?.(next);
                          }}
                          disabled={!pendingFile || phase === 'confirming' || extractionState === 'running'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed font-medium"
                        >
                          <option value="cash" className="bg-slate-900">Cash</option>
                          <option value="credit_card" className="bg-slate-900">Credit card</option>
                          <option value="transfer" className="bg-slate-900">Transfer</option>
                        </select>
                        {extractionState === 'running' && <FieldSpinner />}
                      </div>
                    </Field>
                  </div>
                </div>

                {/* Section 4: Financial Summary */}
                <div className="sm:col-span-2 rounded-xl border border-slate-800 bg-slate-900/10 p-3.5 space-y-3">
                  <div className="text-[10px] font-mono text-emerald-400 uppercase tracking-widest font-bold flex items-center gap-1.5">
                    <span>💵</span> Financial Summary
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <Field label="Subtotal">
                      <div className="relative">
                        <input
                          type="number"
                          step="0.01"
                          value={subtotal}
                          onChange={(e) => setSubtotal(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white font-mono text-right focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          data-testid="slip-field-subtotal"
                        />
                        {extractionState === 'running' && subtotal === '0' ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && (Number(subtotal) > 0 || subtotal !== '0') ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                    <Field label="VAT">
                      <div className="relative">
                        <input
                          type="number"
                          step="0.01"
                          value={vat}
                          onChange={(e) => setVat(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white font-mono text-right focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          data-testid="slip-field-vat"
                        />
                        {extractionState === 'running' && vat === '0' ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && (Number(vat) > 0 || vat !== '0') ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                    <Field label="Total">
                      <div className="relative">
                        <input
                          type="number"
                          step="0.01"
                          value={total}
                          onChange={(e) => setTotal(e.target.value)}
                          disabled={!pendingFile || phase === 'confirming'}
                          className="w-full rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-slate-800 focus:border-emerald-500/60 focus:ring-2 focus:ring-emerald-500/10 transition-all px-3.5 py-2.5 pr-9 text-xs text-white font-mono text-right focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed placeholder-slate-600 font-medium"
                          data-testid="slip-field-total"
                        />
                        {extractionState === 'running' && total === '0' ? (
                          <FieldSpinner />
                        ) : extractionState === 'done' && (Number(total) > 0 || total !== '0') ? (
                          <FilledTick filled />
                        ) : null}
                      </div>
                    </Field>
                  </div>
                </div>
              </>
            )}
          </div>

          {pendingFile && extractionState === 'done' && !isBookBank && !hideSubmitButton && (
            <div
              className={`rounded-xl border p-4 space-y-1 ${
                canConfirm
                  ? 'border-emerald-500/50 bg-gradient-to-br from-emerald-500/15 to-emerald-500/5'
                  : 'border-slate-700 bg-slate-900/40'
              }`}
            >
              <button
                type="button"
                onClick={handleConfirm}
                disabled={phase === 'confirming' || !canConfirm}
                data-testid="slip-confirm"
                className={`w-full py-3 rounded-lg text-sm font-bold font-mono inline-flex items-center justify-center gap-2 shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors ${
                  phase === 'confirming'
                    ? 'bg-slate-700 text-slate-300'
                    : canConfirm
                    ? 'bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-emerald-500/20'
                    : 'bg-slate-800 text-slate-500'
                }`}
              >
                {phase === 'confirming' ? '⏳ Saving…' : canConfirm ? '✓ Send & Confirm' : '🔒 Send & Confirm (disabled)'}
              </button>
              <p className={`text-[10px] font-mono text-center ${
                canConfirm ? 'text-emerald-200/70' : 'text-amber-300/80'
              }`}>
                {phase === 'confirming'
                  ? 'Saving your expense as draft.'
                  : canConfirm
                  ? 'All required fields look good. Click to save as draft expense.'
                  : (payment === 'transfer' && !bookBankSlipId
                      ? 'Transfer expenses require a book bank slip below.'
                      : 'Fill vendor + date; subtotal + VAT must equal total.')}
              </p>
            </div>
          )}

          {pendingFile && extractionState === 'done' && isBookBank && (
            <div className="rounded-xl border border-slate-700 bg-slate-900/40 p-4 space-y-1">
              <p className="text-[11px] font-mono text-emerald-300 text-center">
                ✓ Book bank attached — SLIP-{slipId}
              </p>
              <p className="text-[10px] font-mono text-center text-slate-400">
                Will be linked to the expense when you submit the receipt.
              </p>
            </div>
          )}

          {pendingFile && extractionState === 'done' && !isBookBank && (
            <div className="rounded-xl border border-slate-800/80 bg-slate-950/40 backdrop-blur-md overflow-hidden shadow-lg shadow-black/45">
              <details className="group" open>
                <summary className="flex items-center justify-between px-4 py-3 bg-slate-900/40 border-b border-slate-800/60 cursor-pointer select-none hover:bg-slate-900/60 transition-colors [&::-webkit-details-marker]:hidden">
                  <span className="text-[10px] font-mono text-slate-300 uppercase tracking-widest font-semibold flex items-center gap-2">
                    <span className="text-emerald-400 text-xs">📋</span> OCR line items ({items.length})
                  </span>
                  <span className="text-[10px] text-slate-500 font-mono transition-transform duration-200 group-open:rotate-180">
                    ▼
                  </span>
                </summary>
                <div className="p-3 space-y-3">
                  <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse text-[11px] font-mono">
                      <thead>
                        <tr className="border-b border-slate-800/60 text-slate-500 font-semibold uppercase tracking-wider text-[9px]">
                          <th className="py-1.5 px-2 pb-2 text-slate-400">Description</th>
                          <th className="py-1.5 px-2 pb-2 text-center w-20 text-slate-400">Qty</th>
                          <th className="py-1.5 px-2 pb-2 text-right w-24 text-slate-400">Unit Price</th>
                          <th className="py-1.5 px-2 pb-2 text-right w-28 text-slate-400">Amount</th>
                          <th className="py-1.5 px-2 pb-2 text-center w-10 text-slate-400"></th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800/30">
                        {items.map((it, i) => (
                          <tr key={i} className="hover:bg-slate-900/10 transition-colors group/row">
                            <td className="py-2 px-1">
                              <input
                                type="text"
                                value={it.description}
                                onChange={(e) => updateItemDesc(i, e.target.value)}
                                disabled={phase === 'confirming'}
                                placeholder="Description"
                                className="w-full bg-slate-900/30 border border-slate-800 focus:border-slate-700 rounded px-2 py-1 text-[11px] text-slate-200 focus:outline-none"
                              />
                            </td>
                            <td className="py-2 px-1 text-center">
                              <input
                                type="number"
                                step="any"
                                value={it.qty ?? 1}
                                onChange={(e) => updateItemQty(i, e.target.value)}
                                disabled={phase === 'confirming'}
                                className="w-16 bg-slate-900/30 border border-slate-800 focus:border-slate-700 rounded px-1.5 py-1 text-center text-[11px] font-mono text-slate-200 focus:outline-none"
                              />
                            </td>
                            <td className="py-2 px-1 text-right">
                              <input
                                type="number"
                                step="0.01"
                                value={it.unitPrice ?? it.amount ?? 0}
                                onChange={(e) => updateItemUnitPrice(i, e.target.value)}
                                disabled={phase === 'confirming'}
                                className="w-20 bg-slate-900/30 border border-slate-800 focus:border-slate-700 rounded px-1.5 py-1 text-right text-[11px] font-mono text-slate-200 focus:outline-none"
                              />
                            </td>
                            <td className="py-2 px-1 text-right">
                              <input
                                type="number"
                                step="0.01"
                                value={it.amount}
                                onChange={(e) => updateItemAmount(i, e.target.value)}
                                disabled={phase === 'confirming'}
                                className="w-24 bg-slate-900/30 border border-slate-800 focus:border-slate-700 rounded px-1.5 py-1 text-right text-[11px] font-mono font-semibold text-emerald-400 focus:outline-none"
                              />
                            </td>
                            <td className="py-2 px-1 text-center">
                              <button
                                type="button"
                                onClick={() => removeItem(i)}
                                disabled={phase === 'confirming'}
                                className="text-slate-500 hover:text-rose-400 transition-colors p-1"
                                title="Remove Item"
                              >
                                ✕
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <div className="flex justify-end pt-1">
                    <button
                      type="button"
                      onClick={addItem}
                      disabled={phase === 'confirming'}
                      className="px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-750 border border-slate-700 text-slate-200 text-[10px] font-mono transition-colors"
                    >
                      + Add Item
                    </button>
                  </div>
                </div>
              </details>
            </div>
          )}

          {error && <p className="text-xs text-rose-400 font-mono">⚠ {error}</p>}

          {pendingFile && extractionState === 'done' && selectedModelDesc && (
            <p className="text-[10px] text-slate-500 italic">{selectedModelDesc}</p>
          )}

          <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-slate-800">
            {pendingFile && slipId != null && extractionState !== 'running' ? (
              <button
                type="button"
                onClick={handleRemove}
                disabled={phase === 'confirming'}
                className="px-3 py-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-300 border border-rose-500/30 text-[11px] font-mono disabled:opacity-50"
                data-testid="slip-remove"
              >
                🗑 Remove (wrong upload)
              </button>
            ) : (
              <span />
            )}

            <div className="flex items-center gap-2">
              {extractionState !== 'running' && (
                <button
                  type="button"
                  onClick={handlePickAnother}
                  disabled={phase === 'confirming'}
                  className="px-3 py-1.5 rounded-lg bg-slate-800/60 hover:bg-slate-800 text-slate-200 border border-slate-700 text-[11px] font-mono disabled:opacity-50"
                >
                  {pendingFile ? '↺ Pick another file' : '📂 Pick a file'}
                </button>
              )}

              {pendingFile && extractionState === 'done' && (
                <details className="relative group" data-testid="slip-vision-model-review">
                  <summary className="list-none cursor-pointer flex items-center gap-1.5 px-2 py-1 rounded-lg bg-slate-900/60 border border-slate-800 hover:border-slate-600 text-[10px] font-mono text-slate-300 [&::-webkit-details-marker]:hidden">
                    <span className="text-slate-400">Model:</span>
                    <span className="text-white truncate max-w-[160px]">{selectedModel || '—'}</span>
                    <span className="text-slate-500">▾</span>
                  </summary>
                  <div className="absolute right-0 top-full mt-1 z-20 w-[min(560px,90vw)] p-2 rounded-xl bg-slate-950 border border-slate-800 shadow-2xl shadow-black/60">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-2 max-h-[60vh] overflow-y-auto">
                      {visionModels.map(m => (
                        <ModelCard
                          key={m.id}
                          m={m}
                          selected={m.name === selectedModel}
                          onSelect={pickModel}
                          testId={`slip-vision-model-review-${m.id}`}
                          disabled={phase === 'confirming'}
                        />
                      ))}
                    </div>
                  </div>
                </details>
              )}
            </div>
          </div>
        </div>
      )}

      {phase === 'confirmed' && slipId != null && (
        <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/5 p-5 space-y-3">
          <div className="flex items-center gap-2">
            <span className="px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 text-[10px] font-mono uppercase">
              Step 3 · Confirmed
            </span>
            {confirmedStatus && (
              <span className="text-[10px] font-mono text-slate-400">
                Submitted → {confirmedStatus}
              </span>
            )}
          </div>
          <div className="flex items-start gap-4">
            {preview ? (
              <button
                type="button"
                onClick={() => setZoomOpen(true)}
                className="shrink-0 rounded-lg border border-slate-800 bg-slate-900/60 hover:border-emerald-500/50 transition-colors cursor-zoom-in overflow-hidden"
                title="Click to enlarge"
              >
                <img src={preview} alt="preview" className="w-20 h-20 object-cover" />
              </button>
            ) : (
              <div className="w-20 h-20 shrink-0 rounded-lg bg-slate-900/80 flex items-center justify-center text-2xl border border-slate-800">📄</div>
            )}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold text-white truncate">{vendor || fileName}</p>
              <p className="text-[10px] text-slate-400 font-mono">
                {confirmedExpenseId != null && `EXP-${confirmedExpenseId} · `}
                SLIP-{slipId}
              </p>
            </div>
            <Link
              href={confirmedExpenseId != null ? `/waybill/by-expense/${confirmedExpenseId}` : '/my-waybills?scope=queue'}
              className="text-[11px] font-mono text-indigo-300 hover:text-white inline-flex items-center gap-1"
            >
              🔗 Open in expense workflow
            </Link>
          </div>

          {!locked && (
            <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-800">
              <button
                type="button"
                onClick={handleRemove}
                className="px-3 py-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-300 border border-rose-500/30 text-[11px] font-mono"
                data-testid="slip-remove-confirmed"
              >
                🗑 Remove (wrong upload)
              </button>
            </div>
          )}
          {locked && lockReason && (
            <p className="text-[10px] font-mono text-slate-500 border-t border-slate-800 pt-2">
              🔒 {lockReason}
            </p>
          )}

          <div className="flex items-center justify-end pt-1">
            <button
              type="button"
              onClick={handlePickAnother}
              className="px-3 py-1.5 rounded-lg bg-slate-800/60 hover:bg-slate-800 text-slate-200 border border-slate-700 text-[10px] font-mono"
            >
              + Upload another slip
            </button>
          </div>
        </div>
      )}

      {preview && (
        <Modal
          open={zoomOpen}
          onClose={() => setZoomOpen(false)}
          title="Slip preview"
          subtitle={fileName ?? undefined}
          tone="slate"
          width="2xl"
          hideCloseButton={false}
        >
          <div className="flex items-center justify-center bg-slate-950 rounded-xl border border-slate-800 p-1">
            <img
              src={preview}
              alt="preview enlarged"
              className="max-h-[60vh] w-auto max-w-full object-contain rounded-lg"
            />
          </div>
        </Modal>
      )}
    </div>
  );
});

const Field: React.FC<{ label: string; hint?: string; children: React.ReactNode }> = ({ label, hint, children }) => (
  <label className="block space-y-1.5">
    <span className="text-[10px] font-mono text-slate-400 uppercase tracking-widest font-semibold">
      {label}
      {hint && <span className="ml-1 text-slate-500 normal-case tracking-normal">({hint})</span>}
    </span>
    {children}
  </label>
);

const FieldSpinner: React.FC = () => (
  <span
    className="absolute right-2 top-1/2 -translate-y-1/2 inline-block w-3.5 h-3.5 border-2 border-emerald-500/40 border-t-emerald-400 rounded-full animate-spin"
    aria-label="extracting"
  />
);