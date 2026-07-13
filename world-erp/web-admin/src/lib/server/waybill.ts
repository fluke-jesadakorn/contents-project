// web-admin/src/lib/server/waybill.ts — server-only queries for waybills.

import 'server-only';
import { cache } from 'react';
import { query } from '@erp-lib/db';
import { listEvents, type WaybillEventRow } from '@erp-lib/waybill/events';
import {
  listAttachments,
  attachmentsAndEventsMerged,
  type WaybillAttachmentRow,
} from '@erp-lib/waybill/attachments';
import {
  pipsForDomain,
  type WaybillDomain,
} from '@erp-lib/waybill/derive';
import { stageRoles } from '@erp-lib/perm/server';

export interface WaybillRow {
  id: string;
  origin: 'expense' | 'pr' | 'po' | 'so';
  origin_id: number;
  fiscal_year: number;
  waybill_kind: 'reimbursement' | 'procurement';
  submitter_id: number | null;
  vendor_name: string | null;
  vendor_address: string | null;
  created_to: string | null;
  created_to_address: string | null;
  total_amount: string | null;
  currency: string;
  current_stage: string;
  current_owner_role: string | null;
  current_owner_user_id: number | null;
  status: 'open' | 'completed' | 'rejected' | 'reversed' | 'superseded';
  created_at: Date;
  updated_at: Date;
}

export const loadWaybill = cache(async (id: string): Promise<WaybillRow | null> => {
  const r = await query<WaybillRow>(
    `SELECT id, origin, origin_id, fiscal_year, waybill_kind, submitter_id,
            vendor_name, vendor_address, created_to, created_to_address, total_amount, currency, current_stage,
            current_owner_role, current_owner_user_id, status,
            created_at, updated_at
       FROM waybills WHERE id = $1`,
    [id],
  );
  return r.rows[0] ?? null;
});

export async function loadWaybillByOrigin(
  origin: 'expense' | 'pr' | 'po',
  originId: number,
): Promise<WaybillRow | null> {
  const r = await query<WaybillRow>(
    `SELECT id, origin, origin_id, fiscal_year, waybill_kind, submitter_id,
            vendor_name, vendor_address, created_to, created_to_address, total_amount, currency, current_stage,
            current_owner_role, current_owner_user_id, status,
            created_at, updated_at
       FROM waybills WHERE origin = $1 AND origin_id = $2`,
    [origin, originId],
  );
  return r.rows[0] ?? null;
}

export interface WaybillInboxRow extends WaybillRow {
  submitter_name: string | null;
  age_hours: number;
}

export async function listMyWaybills(actorId: number): Promise<WaybillInboxRow[]> {
  const r = await query<WaybillInboxRow>(
    `SELECT w.id, w.origin, w.origin_id, w.fiscal_year, w.waybill_kind, w.submitter_id,
            w.vendor_name, w.total_amount, w.currency, w.current_stage,
            w.current_owner_role, w.current_owner_user_id, w.status,
            w.created_at, w.updated_at,
            u.fullname AS submitter_name,
            EXTRACT(EPOCH FROM (now() - w.updated_at)) / 3600.0 AS age_hours
       FROM waybills w
  LEFT JOIN users u ON u.id = w.submitter_id
      WHERE w.submitter_id = $1
        AND w.status NOT IN ('completed', 'reversed', 'superseded')
   ORDER BY w.updated_at DESC
      LIMIT 100`,
    [actorId],
  );
  return r.rows;
}

export async function listAwaitingForActor(
  actorId: number,
  actorRoleId: string | null,
  limit = 100,
): Promise<WaybillInboxRow[]> {
  if (!actorRoleId) return [];
  const r = await query<WaybillInboxRow>(
    `SELECT w.id, w.origin, w.origin_id, w.fiscal_year, w.waybill_kind, w.submitter_id,
            w.vendor_name, w.total_amount, w.currency, w.current_stage,
            w.current_owner_role, w.current_owner_user_id, w.status,
            w.created_at, w.updated_at,
            u.fullname AS submitter_name,
            EXTRACT(EPOCH FROM (now() - w.updated_at)) / 3600.0 AS age_hours
       FROM waybills w
  LEFT JOIN users u ON u.id = w.submitter_id
      WHERE w.current_owner_role = $1
        AND w.status NOT IN ('completed', 'reversed', 'superseded')
   ORDER BY w.updated_at DESC
      LIMIT $2`,
    [actorRoleId, limit],
  );
  return r.rows;
}

export async function listAllOpenWaybills(limit = 200): Promise<WaybillInboxRow[]> {
  const r = await query<WaybillInboxRow>(
    `SELECT w.id, w.origin, w.origin_id, w.fiscal_year, w.waybill_kind, w.submitter_id,
            w.vendor_name, w.total_amount, w.currency, w.current_stage,
            w.current_owner_role, w.current_owner_user_id, w.status,
            w.created_at, w.updated_at,
            u.fullname AS submitter_name,
            EXTRACT(EPOCH FROM (now() - w.updated_at)) / 3600.0 AS age_hours
       FROM waybills w
  LEFT JOIN users u ON u.id = w.submitter_id
      WHERE w.status NOT IN ('completed', 'reversed', 'superseded')
   ORDER BY w.updated_at DESC
      LIMIT $1`,
    [limit],
  );
  return r.rows;
}

export async function loadWaybillEvents(waybillId: string): Promise<WaybillEventRow[]> {
  return listEvents(waybillId);
}

export const loadAttachmentsForWaybill = cache(
  async (waybillId: string): Promise<WaybillAttachmentRow[]> => {
    return listAttachments(waybillId);
  },
);

export async function loadUnifiedTimeline(
  waybillId: string,
): Promise<Awaited<ReturnType<typeof attachmentsAndEventsMerged>>> {
  return attachmentsAndEventsMerged(waybillId);
}

export function domainOf(wb: WaybillRow): WaybillDomain {
  if (wb.origin === 'expense') return 'expense';
  if (wb.origin === 'so') return 'sales' as WaybillDomain;
  return 'procurement';
}

export interface PipActorInfo {
  name: string;
  ts: Date;
  kind: string;
  actorId: number | null;
}

export interface WaybillRailContext {
  waybill: WaybillRow;
  domain: WaybillDomain;
  events: WaybillEventRow[];
  attachments: WaybillAttachmentRow[];
  pips: ReturnType<typeof pipsForDomain>;
  activePipIndex: number;
  activeActorName: string | null;
  pipActors: Record<string, PipActorInfo>;
}

export async function loadWaybillRailContext(waybillId: string): Promise<WaybillRailContext | null> {
  const wb = await loadWaybill(waybillId);
  if (!wb) return null;
  const events = await listEvents(waybillId);
  const attachments = await listAttachments(waybillId);
  const domain = domainOf(wb);
  const pips = pipsForDomain(domain);
  const activePipIndex = pips.findIndex((p) => p.key === wb.current_stage);

  // Resolve actor names for every event in one batched lookup.
  const actorIds = Array.from(new Set(events.map((e) => e.actor_id).filter((x): x is number => x != null)));
  const nameById = new Map<number, string>();
  if (actorIds.length) {
    const u = await query<{ id: number; fullname: string }>(
      `SELECT id, fullname FROM users WHERE id = ANY($1::int[])`,
      [actorIds],
    );
    for (const row of u.rows) nameById.set(row.id, row.fullname);
  }

  // Last event touching each stage_to wins (most recent action at that stage).
  const pipActors: Record<string, PipActorInfo> = {};
  for (const e of events) {
    if (!e.stage_to) continue;
    const name = e.actor_id != null ? (nameById.get(e.actor_id) ?? `#${e.actor_id}`) : '—';
    pipActors[e.stage_to] = { name, ts: e.occurred_at, kind: e.kind, actorId: e.actor_id };
  }

  let activeActorName: string | null = null;
  if (wb.current_owner_user_id) {
    const u = await query<{ fullname: string }>(
      `SELECT fullname FROM users WHERE id = $1`,
      [wb.current_owner_user_id],
    );
    activeActorName = u.rows[0]?.fullname ?? null;
  }

  return {
    waybill: wb,
    domain,
    events,
    attachments,
    pips,
    activePipIndex,
    activeActorName,
    pipActors,
  };
}

export function activeStageOf(stage: string): string {
  return stage;
}

export interface WaybillSlip {
  file_path: string;
  mime_type: string;
  file_size: number;
  kind: string | null;
  status: string | null;
  bank_name: string | null;
  bank_branch: string | null;
  account_number: string | null;
  account_name: string | null;
}

export interface ExpenseItemRow {
  id: number;
  description: string | null;
  qty: string;
  unit_price: string;
  amount: string;
  mapped_account_code: string | null;
}

export interface ExpenseFullPicture {
  expense: {
    id: number;
    vendor_name: string | null;
    vendor_address: string | null;
    created_to: string | null;
    created_to_address: string | null;
    transaction_date: Date | null;
    subtotal: string | null;
    vat_amount: string | null;
    total_amount: string | null;
    payment_method: string | null;
    status: string;
    submitter_id: number | null;
    rejection_reason: string | null;
    rejected_at: Date | null;
  };
  items: ExpenseItemRow[];
  slips: WaybillSlip[];
  submitter_name?: string | null;
}

export async function loadExpenseFullPicture(expenseId: number): Promise<ExpenseFullPicture | null> {
  const e = await query<ExpenseFullPicture['expense'] & { submitter_name: string | null }>(
    `SELECT e.id, e.vendor_name, e.vendor_address, e.created_to, e.created_to_address, e.transaction_date, e.subtotal::text, e.vat_amount::text,
            e.total_amount::text, e.payment_method, e.status, e.submitter_id,
            e.rejection_reason, e.rejected_at, u.fullname AS submitter_name
       FROM expenses e
       LEFT JOIN users u ON u.id = e.submitter_id
       WHERE e.id = $1`,
    [expenseId],
  );
  if (!e.rows.length) return null;
  const [items, slips] = await Promise.all([
    query<ExpenseItemRow>(
      `SELECT id, description, qty::text, unit_price::text, amount::text, mapped_account_code
         FROM expense_items WHERE expense_id = $1 ORDER BY id`,
      [expenseId],
    ),
    query<WaybillSlip>(
      `SELECT file_path, mime_type, file_size, kind, status,
              bank_name, bank_branch, account_number, account_name
         FROM slips WHERE expense_id = $1 ORDER BY id`,
      [expenseId],
    ),
  ]);
  const { submitter_name, ...expense } = e.rows[0];
  return { expense, items: items.rows, slips: slips.rows, submitter_name };
}

export async function loadSlipsForExpenses(
  expenseIds: number[],
): Promise<Map<number, WaybillSlip[]>> {
  if (!expenseIds.length) return new Map();
  const r = await query<WaybillSlip & { expense_id: number }>(
    `SELECT expense_id, file_path, mime_type, file_size, kind, status,
            bank_name, bank_branch, account_number, account_name
       FROM slips WHERE expense_id = ANY($1::int[]) ORDER BY id`,
    [expenseIds],
  );
  const m = new Map<number, WaybillSlip[]>();
  for (const row of r.rows) {
    const { expense_id, ...slip } = row;
    const a = m.get(expense_id) ?? [];
    a.push(slip);
    m.set(expense_id, a);
  }
  return m;
}

export async function loadSlipsForExpense(
  expenseId: number,
): Promise<WaybillSlip[]> {
  const m = await loadSlipsForExpenses([expenseId]);
  return m.get(expenseId) ?? [];
}

export async function loadSlipsForWaybill(
  waybillId: string,
): Promise<{ receipt: WaybillSlip | null; bookBank: WaybillSlip[] }> {
  const wb = await loadWaybill(waybillId);
  if (!wb) return { receipt: null, bookBank: [] };
  const slips = await loadSlipsForExpense(wb.origin_id);
  return {
    receipt: slips.find((s) => s.kind === 'receipt') ?? null,
    bookBank: slips.filter((s) => s.kind === 'book_bank' || s.kind === 'book-bank'),
  };
}

export const loadDocsForWaybill = loadAttachmentsForWaybill;

export interface ApproverRow {
  user_id: number;
  fullname: string;
  role_id: string | null;
  dept_group_id: string | null;
  dept_group_name: string | null;
  dept_group_name_th: string | null;
  dept_group_name_de: string | null;
  level: number;
}

export interface ActedUserEntry {
  user_id: number;
  fullname: string;
  role_id: string | null;
  role_name: string | null;
  dept_group_id: string | null;
  kind: string;
  sequence: number;
  occurred_at: Date;
}

export type ApproversByStage = Record<string, ApproverRow[]>;
export type ActedUsersByStage = Record<string, ActedUserEntry[]>;

// Stages whose approver pool is scoped to the submitter's own department.
const DEPT_SCOPED_STAGES = new Set(['submission', 'dept_verification', 'dept_authorization']);

export async function loadApproversByStage(waybillId: string): Promise<ApproversByStage> {
  const wb = await loadWaybill(waybillId);
  if (!wb) return {};

  const domain = domainOf(wb);
  const pips = pipsForDomain(domain);
  const out: ApproversByStage = {};
  const roleToPips = new Map<string, string[]>();
  for (const pip of pips) {
    out[pip.key] = [];
    for (const role of stageRoles(pip.key)) {
      const list = roleToPips.get(role) ?? [];
      list.push(pip.key);
      roleToPips.set(role, list);
    }
  }
  const roles = Array.from(roleToPips.keys());
  if (roles.length === 0) return out;

  let submitterDept: string | null = null;
  let submitterLevel = 10;
  if (wb.submitter_id != null) {
    const s = await query<{ dept_id: string | null; level: number }>(
      `SELECT (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS dept_id,
              COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int)
                          FROM perm.user_roles ur WHERE ur.user_id = u.id), 10) AS level
         FROM users u
        WHERE u.id = $1`,
      [wb.submitter_id],
    );
    submitterDept = s.rows[0]?.dept_id ?? null;
    submitterLevel = s.rows[0]?.level ?? 10;
  }

  const r = await query<ApproverRow>(
    `SELECT u.id AS user_id, u.fullname, ur.role_id,
            (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
              WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                AND up.revoked_at IS NULL
                AND (up.ends_at IS NULL OR up.ends_at > now())
              ORDER BY up.permission_id LIMIT 1) AS dept_group_id,
            (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
              WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                AND up.revoked_at IS NULL
                AND (up.ends_at IS NULL OR up.ends_at > now())
              ORDER BY up.permission_id LIMIT 1) AS dept_group_name,
            NULL::text AS dept_group_name_th,
            NULL::text AS dept_group_name_de,
            COALESCE((SELECT MIN(split_part(ur.role_id, '::', 2)::int)
                        FROM perm.user_roles ur WHERE ur.user_id = u.id), 10) AS level
       FROM perm.user_roles ur
       JOIN users u ON u.id = ur.user_id AND u.is_active
       WHERE ur.role_id = ANY($1::text[])
    ORDER BY level ASC, u.fullname`,
    [roles],
  );

  for (const row of r.rows) {
    if (wb.submitter_id != null && row.user_id === wb.submitter_id) continue;
    if (row.level > submitterLevel) continue;
    const keys = roleToPips.get(row.role_id ?? '') ?? [];
    for (const key of keys) {
      if (DEPT_SCOPED_STAGES.has(key) && row.dept_group_id !== submitterDept) continue;
      out[key].push(row);
    }
  }
  return out;
}

export async function loadActedUsersByStage(waybillId: string): Promise<ActedUsersByStage> {
  const r = await query<{
    stage_to: string | null;
    stage_from: string | null;
    sequence: number;
    kind: string;
    occurred_at: Date;
    actor_id: number | null;
    fullname: string | null;
    role_id: string | null;
  }>(
    `SELECT we.stage_to, we.stage_from, we.sequence, we.kind, we.occurred_at,
            we.actor_id, u.fullname,
            (SELECT ur.role_id FROM perm.user_roles ur
              WHERE ur.user_id = we.actor_id
              ORDER BY split_part(ur.role_id, '::', 2)::int ASC NULLS LAST
              LIMIT 1) AS role_id
       FROM waybill_events we
  LEFT JOIN users u ON u.id = we.actor_id
      WHERE we.waybill_id = $1 AND we.actor_id IS NOT NULL
   ORDER BY we.sequence`,
    [waybillId],
  );
  const out: ActedUsersByStage = {};
  for (const row of r.rows) {
    const bucket = row.stage_to ?? row.stage_from ?? 'submission';
    (out[bucket] ??= []).push({
      user_id: row.actor_id!,
      fullname: row.fullname ?? `#${row.actor_id}`,
      role_id: row.role_id,
      role_name: row.role_id,
      dept_group_id: null,
      kind: row.kind,
      sequence: row.sequence,
      occurred_at: row.occurred_at,
    });
  }
  return out;
}

export interface JournalLineRow {
  account_code: string;
  account_name: string | null;
  account_name_th: string | null;
  debit: number;
  credit: number;
  description: string | null;
}

export interface ExpenseArtifacts {
  po: { id: number; po_number: string | null; status: string | null; issued_at: Date | null; issuer_name: string | null } | null;
  gl: { id: number; finalized_at: Date | null; finalized_by_name: string | null; lines: JournalLineRow[] } | null;
  paySlip: { method: string | null; paid_at: Date | null; paid_by_name: string | null } | null;
}

export interface ProcurementArtifacts {
  pr: { id: number; pr_number: string | null; status: string | null; created_at: Date | null; requester_name: string | null } | null;
  po: { id: number; po_number: string | null; status: string | null; issued_at: Date | null; issuer_name: string | null } | null;
  glAccrual: { id: number; finalized_at: Date | null; finalized_by_name: string | null; lines: JournalLineRow[] } | null;
  glSettlement: { id: number; finalized_at: Date | null; finalized_by_name: string | null; lines: JournalLineRow[] } | null;
  paySlip: { method: string | null; paid_at: Date | null; paid_by_name: string | null } | null;
}

export interface ApproverSummary {
  role: string;
  role_label: string;
  role_label_th: string | null;
  names: string[];
  count: number;
  privacy: 'named' | 'team';
}

export async function loadApproverSummariesForRows(
  _rows: WaybillInboxRow[],
  _amountFn: (r: WaybillInboxRow) => number | null,
): Promise<Map<string, ApproverSummary>> {
  return new Map();
}

export interface ActiveDraft {
  waybill_id: string;
  expense_id: number;
  vendor_name: string | null;
  total_amount: string | null;
  draft_updated_at: Date | null;
}

export async function loadActiveDraftForSubmitter(userId: number): Promise<ActiveDraft | null> {
  const r = await query<{ id: string; origin_id: number; vendor_name: string | null; total_amount: string | null; updated_at: Date }>(
    `SELECT w.id, w.origin_id, e.vendor_name, e.total_amount, w.updated_at
       FROM waybills w
       JOIN expenses e ON e.id = w.origin_id
      WHERE w.origin = 'expense' AND e.submitter_id = $1
        AND w.status = 'open' AND w.current_stage = 'draft'
      ORDER BY w.updated_at DESC LIMIT 1`,
    [userId],
  );
  if (!r.rows.length) return null;
  return { waybill_id: r.rows[0].id, expense_id: r.rows[0].origin_id, vendor_name: r.rows[0].vendor_name, total_amount: r.rows[0].total_amount, draft_updated_at: r.rows[0].updated_at };
}

export interface ActiveSalesDraft {
  waybill_id: string;
  so_number: string | null;
  customer_name: string | null;
  total_amount: string | null;
  draft_updated_at: Date | null;
}

export async function loadActiveSalesDraftForRep(userId: number): Promise<ActiveSalesDraft | null> {
  const r = await query<{ id: string; so_number: string | null; customer_name: string | null; total_amount: string | null; updated_at: Date }>(
    `SELECT w.id, so.so_number, c.name AS customer_name, so.total_amount::text, w.updated_at
       FROM waybills w
       JOIN sales_orders so ON so.id = w.origin_id
       LEFT JOIN customers c ON c.id = so.customer_id
      WHERE w.origin = 'so' AND so.sales_rep_id = $1
        AND w.status = 'open' AND w.current_stage = 'so_draft'
      ORDER BY w.updated_at DESC LIMIT 1`,
    [userId],
  );
  if (!r.rows.length) return null;
  return {
    waybill_id: r.rows[0].id,
    so_number: r.rows[0].so_number,
    customer_name: r.rows[0].customer_name,
    total_amount: r.rows[0].total_amount,
    draft_updated_at: r.rows[0].updated_at,
  };
}

export interface SalesArtifacts {
  customer: { id: number; code: string; name: string; name_th: string | null; name_de: string | null } | null;
  items: Array<{ id: number; description: string; qty: number; unit_price: number; vat_amount: number; line_total: number }>;
  totals: { subtotal: number; vat_total: number; total: number };
  invoice: { number: string | null; issued_at: string | null } | null;
  ar_receipt: { file_path: string; mime_type: string; uploaded_at: string } | null;
}

export async function loadSalesArtifacts(_wb: WaybillRow): Promise<SalesArtifacts | null> {
  return null;
}

export type InboxScope = 'mine' | 'queue' | 'all';

export async function loadInboxForUser(userId: number, scope: InboxScope): Promise<WaybillInboxRow[]> {
  if (scope === 'all') return listAllOpenWaybills();
  if (scope === 'queue') return listAwaitingForActor(userId, null);
  return listMyWaybills(userId);
}

export interface JournalView {
  kind: 'expense' | 'procurement' | 'sales';
}

export async function loadJournalForWaybill(_waybillId: string): Promise<JournalView | null> {
  return null;
}
