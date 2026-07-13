// world-erp/scripts/cleanup-expired-drafts.ts
//
// TTL cleanup for expense drafts. Walks `waybills` WHERE
// `current_stage = 'draft'` AND `updated_at < now() - interval '24 hours'`,
// then deletes the draft rows + cascading events + expenses + pending slips.
// The waybill ID sequence number is permanently lost — that's by design
// (the user burned it when they first interacted with the form).
//
// Run with:
//   cd world-erp && bun scripts/cleanup-expired-drafts.ts
//   cd world-erp && bun scripts/cleanup-expired-drafts.ts --dry-run
//   cd world-erp && bun scripts/cleanup-expired-drafts.ts --ttl=12h
//
// Reads DB + SESSION_SECRET from web-admin/.env.local.

import { readFileSync } from 'node:fs';
import { Pool } from 'pg';

const envFile = readFileSync(
  new URL('../web-admin/.env.local', import.meta.url),
  'utf8',
);
for (const line of envFile.split('\n')) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
}

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const ttlArg = args.find((a) => a.startsWith('--ttl='));
const ttl = ttlArg ? ttlArg.slice('--ttl='.length) : '24 hours';

const pool = new Pool({
  user: process.env.POSTGRES_USER || 'contract',
  password: process.env.POSTGRES_PASSWORD || 'contractpw',
  host: process.env.POSTGRES_HOST || 'localhost',
  database: process.env.POSTGRES_DB || 'finance_db',
  port: Number(process.env.POSTGRES_PORT || 5432),
});

async function findExpired(): Promise<Array<{ id: string; submitter_id: number; origin_id: number; updated_at: Date }>> {
  const r = await pool.query<{ id: string; submitter_id: number; origin_id: number; updated_at: Date }>(
    `SELECT id, submitter_id, origin_id, updated_at
       FROM waybills
      WHERE current_stage = 'draft'
        AND status = 'open'
        AND updated_at < now() - $1::interval`,
    [ttl],
  );
  return r.rows;
}

async function discardOne(id: string, origin_id: number): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`DELETE FROM waybill_events WHERE waybill_id = $1`, [id]);
    await client.query(`DELETE FROM waybill_attachments WHERE waybill_id = $1`, [id]);
    await client.query(`DELETE FROM slips WHERE expense_id = $1 AND status = 'pending'`, [origin_id]);
    await client.query(`DELETE FROM expense_items WHERE expense_id = $1`, [origin_id]);
    await client.query(`DELETE FROM expenses WHERE id = $1 AND status = 'draft'`, [origin_id]);
    await client.query(`DELETE FROM waybills WHERE id = $1 AND current_stage = 'draft'`, [id]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function main(): Promise<void> {
  const expired = await findExpired();
  if (expired.length === 0) {
    console.log(`[cleanup-expired-drafts] no drafts older than ${ttl} (dry-run=${dryRun})`);
    await pool.end();
    return;
  }

  console.log(
    `[cleanup-expired-drafts] ${dryRun ? 'DRY RUN — ' : ''}found ${expired.length} draft(s) older than ${ttl}`,
  );
  for (const row of expired) {
    console.log(`  · ${row.id} · submitter=${row.submitter_id} · expense=${row.origin_id} · updated_at=${row.updated_at.toISOString()}`);
    if (!dryRun) {
      await discardOne(row.id, row.origin_id);
      console.log(`    → deleted`);
    }
  }
  await pool.end();
}

main().catch((e) => {
  console.error('[cleanup-expired-drafts] failed:', e);
  process.exit(1);
});