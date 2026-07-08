// Backward-compat shim. The canonical source is lib/waybill/labels.ts.
// This module rebuilds the legacy Record<string, {th, en, emoji}> shape
// from WAYBILL_STAGES + PROCUREMENT_STAGES so old callsites continue to
// compile while new code consumes <WaybillChip>.

export { WAYBILL_LABELS } from '@erp-lib/waybill/labels';
export type { WaybillStagePip } from '@erp-lib/waybill/labels';

import { EXPENSE_STAGES } from '@erp-lib/waybill/labels';

interface LegacyLabel { th: string; en: string; emoji: string }

const ALL: Record<string, LegacyLabel> = {};
for (const pip of EXPENSE_STAGES.pips) {
  ALL[pip.key] = { th: pip.th, en: pip.en, emoji: pip.emoji };
}
// legacy alias keys — caller compat
const ALIASES: Record<string, string> = {
  ocr_extracted: 'submission',
  supervisor_review: 'dept_verification',
  manager_review: 'dept_authorization',
  account_officer_review: 'accounting_verification',
  account_supervisor_review: 'accounting_supervision',
  accounting_review: 'accounting_authorization',
  finance_review: 'disbursement_authorization',
  cfo_review: 'cfo_authorization',
  ceo_review: 'ceo_authorization',
  approved: 'awaiting_disbursement',
  paid: 'disbursed',
};
for (const [legacy, canonical] of Object.entries(ALIASES)) {
  const e = ALL[canonical];
  if (e) ALL[legacy] = { th: e.th, en: e.en, emoji: e.emoji };
}
ALL.draft = { th: 'Draft', en: 'Draft', emoji: '📝' };
ALL.rejected = ALL.rejected ?? { th: 'ปฏิเสธ', en: 'Rejected', emoji: '❌' };

export const STATUS_LABELS: Record<string, LegacyLabel> = ALL;