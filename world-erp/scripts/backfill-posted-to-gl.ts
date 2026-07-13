// world-erp/scripts/backfill-posted-to-gl.ts
//
// One-off backfill: waybills that were settled before the GL-post
// refactor landed do not have a `posted-to-gl` waybill_event. The
// journal_entries row exists (postExpenseToGL ran and was committed),
// and the slip is now attached, but the event chain is missing the
// intermediate step. This script re-derives the event from existing
// data (settled event actor + journal_entries.id + slip) and inserts
// the `posted-to-gl` event with a matching HMAC signature so the
// linked-list invariant holds.
//
// Run with:
//   cd world-erp && bun scripts/backfill-posted-to-gl.ts
//
// Reads DB + SESSION_SECRET from web-admin/.env.local.

import { readFileSync } from 'node:fs';
import { Pool } from 'pg';
import { createHmac } from 'node:crypto';

const envFile = readFileSync(
  new URL('../web-admin/.env.local', import.meta.url),
  'utf8',
);
for (const line of envFile.split('\n')) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
}

const pool = new Pool({
  host: process.env.POSTGRES_HOST ?? 'localhost',
  port: Number(process.env.POSTGRES_PORT ?? 5432),
  user: process.env.POSTGRES_USER ?? 'contract',
  password: process.env.POSTGRES_PASSWORD ?? 'contractpw',
  database: process.env.POSTGRES_DB ?? 'finance_db',
});

const SESSION_SECRET = process.env.SESSION_SECRET ?? 'wb-secret';

interface WaybillRow {
  id: string;
  origin: string;
  origin_id: number;
}

interface SettledEvent {
  actor_id: number | null;
  actor_role: string | null;
  payload: { slipId?: number } | null;
  occurred_at: Date;
}

interface JournalRow {
  id: number;
}

async function findCandidates(): Promise<WaybillRow[]> {
  const r = await pool.query<WaybillRow>(`
    SELECT w.id, w.origin, w.origin_id
      FROM waybills w
     WHERE w.current_stage = 'disbursed'
       AND w.origin = 'expense'
       AND NOT EXISTS (
         SELECT 1 FROM waybill_events we
          WHERE we.waybill_id = w.id AND we.kind = 'posted-to-gl'
       )
       AND EXISTS (
         SELECT 1 FROM waybill_events we
          WHERE we.waybill_id = w.id AND we.kind = 'settled'
       )
  `);
  return r.rows;
}

async function getSettledEvent(waybillId: string): Promise<SettledEvent | null> {
  const r = await pool.query<SettledEvent>(`
    SELECT actor_id, actor_role, payload, occurred_at
      FROM waybill_events
     WHERE waybill_id = $1 AND kind = 'settled'
     ORDER BY sequence ASC
     LIMIT 1
  `, [waybillId]);
  return r.rows[0] ?? null;
}

async function getJournal(expenseId: number): Promise<JournalRow | null> {
  const r = await pool.query<JournalRow>(`
    SELECT id FROM journal_entries WHERE expense_id = $1 ORDER BY id ASC LIMIT 1
  `, [expenseId]);
  return r.rows[0] ?? null;
}

async function getPreviousEvent(client: { query: typeof pool.query }, waybillId: string) {
  const r = await client.query<{ id: string; sequence: number }>(`
    SELECT id, sequence FROM waybill_events
     WHERE waybill_id = $1
     ORDER BY sequence DESC
     LIMIT 1
  `, [waybillId]);
  return r.rows[0] ?? null;
}

async function backfill(wb: WaybillRow): Promise<void> {
  const settled = await getSettledEvent(wb.id);
  if (!settled) {
    console.log(`skip ${wb.id}: no settled event`);
    return;
  }
  const journal = await getJournal(wb.origin_id);
  if (!journal) {
    console.log(`skip ${wb.id}: no journal_entries row for expense ${wb.origin_id}`);
    return;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const prev = await getPreviousEvent(client, wb.id);
    const nextSeq = (prev?.sequence ?? 0) + 1;
    const prevId = prev?.id ?? null;

    const payload = {
      journalId: journal.id,
      slipId: (settled.payload as { slipId?: number } | null)?.slipId ?? null,
    };
    const payloadJson = JSON.stringify(payload);

    const sigInput = [
      wb.id,
      nextSeq,
      'posted-to-gl',
      'awaiting_disbursement',
      'disbursed',
      payloadJson,
    ].join('|');
    const sig = createHmac('sha256', SESSION_SECRET).update(sigInput).digest();

    await client.query(
      `INSERT INTO waybill_events
         (waybill_id, sequence, previous_event_id, kind, stage_from, stage_to,
          actor_id, actor_role, actor_signature, payload, occurred_at)
       VALUES ($1, $2, $3, 'posted-to-gl', 'awaiting_disbursement', 'disbursed',
               $4, $5, $6, $7::jsonb, $8)`,
      [
        wb.id,
        nextSeq,
        prevId,
        settled.actor_id,
        settled.actor_role,
        sig,
        payloadJson,
        settled.occurred_at,
      ],
    );

    await client.query('COMMIT');
    console.log(`backfilled ${wb.id}: seq=${nextSeq} journal=${journal.id}`);
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function main() {
  const candidates = await findCandidates();
  console.log(`found ${candidates.length} waybill(s) needing posted-to-gl backfill`);
  for (const wb of candidates) {
    await backfill(wb);
  }
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
