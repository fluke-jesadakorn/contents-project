// web-admin/src/lib/server/waybill.ts — server-only queries for waybills.

import 'server-only';
import { cache } from 'react';
import { query } from '@erp-lib/db';
import { listEvents, type WaybillEventRow } from '@erp-lib/waybill/events';
import {
  pipsForDomain,
  type WaybillDomain,
} from '@erp-lib/waybill/derive';

export interface WaybillRow {
  id: string;
  origin: 'expense' | 'pr' | 'po';
  origin_id: number;
  fiscal_year: number;
  waybill_kind: 'reimbursement' | 'procurement';
  submitter_id: number | null;
  vendor_name: string | null;
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
            vendor_name, total_amount, currency, current_stage,
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
            vendor_name, total_amount, currency, current_stage,
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

export function domainOf(wb: WaybillRow): WaybillDomain {
  return wb.origin === 'expense' ? 'expense' : 'procurement';
}

export interface WaybillRailContext {
  waybill: WaybillRow;
  domain: WaybillDomain;
  events: WaybillEventRow[];
  pips: ReturnType<typeof pipsForDomain>;
  activePipIndex: number;
  activeActorName: string | null;
}

export async function loadWaybillRailContext(waybillId: string): Promise<WaybillRailContext | null> {
  const wb = await loadWaybill(waybillId);
  if (!wb) return null;
  const events = await listEvents(waybillId);
  const domain = domainOf(wb);
  const pips = pipsForDomain(domain);
  const activePipIndex = pips.findIndex((p) => p.key === wb.current_stage);

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
    pips,
    activePipIndex,
    activeActorName,
  };
}
