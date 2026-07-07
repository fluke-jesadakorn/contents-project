// lib/waybill/derive.ts — pure helpers. No DB, no 'server-only'.
// Translates status keys into Waybill pips / buckets / inheritance.

import { EXPENSE_STAGES, PROCUREMENT_STAGES, type WaybillStagePip } from './labels';
export type { WaybillStagePip } from './labels';

export type WaybillDomain = 'expense' | 'procurement';
export type WaybillBucket = 'submission' | 'verification' | 'authorization' | 'disbursement' | 'closed';

export function domainForOrigin(origin: 'expense' | 'pr' | 'po'): WaybillDomain {
  return origin === 'expense' ? 'expense' : 'procurement';
}

export function pipsForDomain(domain: WaybillDomain): WaybillStagePip[] {
  return domain === 'procurement' ? PROCUREMENT_STAGES.pips : EXPENSE_STAGES.pips;
}

export function findPip(domain: WaybillDomain, key: string): WaybillStagePip | null {
  return pipsForDomain(domain).find((p) => p.key === key) ?? null;
}

export function pipIndex(domain: WaybillDomain, key: string): number {
  const pips = pipsForDomain(domain);
  return pips.findIndex((p) => p.key === key);
}

export function bucketLabel(bucket: WaybillBucket, lang: 'en' | 'th'): string {
  const map: Record<WaybillBucket, { en: string; th: string }> = {
    submission:    { en: 'Submission',     th: 'ยื่นเอกสาร' },
    verification:  { en: 'Verification',   th: 'ตรวจสอบ' },
    authorization: { en: 'Authorization',  th: 'ลงนามอนุมัติ' },
    disbursement:  { en: 'Disbursement',   th: 'จ่ายเงิน' },
    closed:        { en: 'Closed',         th: 'ปิดรายการ' },
  };
  return map[bucket][lang];
}

// Decide the next stage in the canonical pipeline. Returns null at the end.
export function nextStageOf(
  domain: WaybillDomain,
  current: string,
  totalAmountTHB?: number,
): string | null {
  const pips = pipsForDomain(domain);
  const idx = pips.findIndex((p) => p.key === current);
  if (idx < 0 || idx >= pips.length - 1) return null;
  const nxt = pips[idx + 1];
  // Skip CEO if amount below threshold (only relevant for expense)
  if (domain === 'expense' && nxt.key === 'ceo_authorization') {
    const has = typeof totalAmountTHB === 'number' && Number.isFinite(totalAmountTHB);
    if (!has || totalAmountTHB < 200_000) {
      return null; // CEO is the final pip; if not required, end here
    }
  }
  return nxt.key;
}

export function inferActionStage(
  domain: WaybillDomain,
  currentStage: string,
): string {
  return currentStage;
}
