// Quick smoke test for the 3-step GL sales flow.
// Runs via: bun world-erp/scripts/smoke-sales-gl.ts
import 'server-only';
import {
  upsertSalesDraftVat,
  upsertSalesDraftAccrual,
  upsertSalesDraftSettlement,
  finalizeSalesDraft,
} from '../lib/finance/postSalesToGL';
import { query } from '../lib/db';

async function main() {
  const r = await query<{ id: number; so_number: string }>(
    `SELECT id, so_number FROM sales_orders WHERE so_number = 'SO-2026-000001' LIMIT 1`,
  );
  const so = r.rows[0];
  if (!so) throw new Error('SO-2026-000001 not found');
  console.log('Testing GL posting for', so.so_number);

  const vat = await upsertSalesDraftVat({ salesOrderId: so.id, vendorName: so.so_number });
  console.log('  vat draft', vat);

  const accr = await upsertSalesDraftAccrual({ salesOrderId: so.id, vendorName: so.so_number });
  console.log('  accrual draft', accr);

  const sett = await upsertSalesDraftSettlement({ salesOrderId: so.id, vendorName: so.so_number });
  console.log('  settlement draft', sett);

  for (const j of [vat, accr, sett]) {
    const f = await finalizeSalesDraft({ journalId: j.journalId, actorId: 1 });
    console.log('  finalized', f);
  }

  const check = await query<{ step: string; description: string; finalized_at: string }>(
    `SELECT step, description, finalized_at::text FROM journal_entries WHERE so_id = $1 ORDER BY step`,
    [so.id],
  );
  console.log('Final state:');
  for (const row of check.rows) console.log(' ', row.step, '|', row.description, '|', row.finalized_at);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
