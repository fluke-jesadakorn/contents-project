import { withTransaction, query } from '../lib/db';

const PETTY_THRESHOLD = 5_000;
const dryRun = process.argv.includes('--dry-run');

interface ExpenseRow {
  id: number;
  submitter_id: number;
  vendor_name: string | null;
  total_amount: string | null;
  dept_group_id: string | null;
  fiscal_year: number;
  pr_id: number | null;
  po_id: number | null;
}

async function main() {
  const candidates = await query<ExpenseRow>(`
    SELECT e.id, e.submitter_id, e.vendor_name, e.total_amount,
           u.dept_group_id,
           EXTRACT(YEAR FROM e.created_at)::int AS fiscal_year,
           e.pr_id, e.po_id
      FROM expenses e
      JOIN users u ON u.id = e.submitter_id
     WHERE e.status NOT IN ('draft', 'rejected')
       AND (e.pr_id IS NULL OR e.po_id IS NULL)
     ORDER BY e.id ASC
  `);

  let prCreated = 0, poCreated = 0, skippedL = 0, errors = 0;
  for (const e of candidates.rows) {
    const amt = parseFloat(e.total_amount ?? '0');
    if (amt < PETTY_THRESHOLD) { skippedL++; continue; }
    if (dryRun) {
      console.log(`[dry-run] would backfill expense ${e.id} amount=${amt}`);
      continue;
    }
    try {
      await withTransaction(async (q) => {
        let prId = e.pr_id;
if (!prId) {
        const r = await q<{ id: number }>(
          `INSERT INTO purchase_requisitions
             (requester_id, vendor_name, total_estimate, dept_group_id, status)
           VALUES ($1, $2, $3, $4, 'submission') RETURNING id`,
          [e.submitter_id, e.vendor_name, e.total_amount, e.dept_group_id],
        );
        prId = r.rows[0].id;
        await q(`UPDATE expenses SET pr_id = $1 WHERE id = $2`, [prId, e.id]);
        prCreated++;
      }
      if (!e.po_id) {
        const poNum = await q<{ n: string }>(`SELECT next_purchase_order_number($1) AS n`, [e.fiscal_year]);
        const r = await q<{ id: number }>(
          `INSERT INTO purchase_orders
             (pr_id, po_number, vendor_name, total_amount, status, issued_by)
           VALUES ($1, $2, $3, $4, 'submission', $5) RETURNING id`,
          [prId, poNum.rows[0].n, e.vendor_name, e.total_amount, e.submitter_id],
        );
          const poId = r.rows[0].id;
          await q(`UPDATE expenses SET po_id = $1 WHERE id = $2`, [poId, e.id]);
          poCreated++;
        }
      });
    } catch (err) {
      errors++;
      console.error(`expense ${e.id} failed:`, err);
    }
  }

  console.log(JSON.stringify({ prCreated, poCreated, skippedL, errors, dryRun, total: candidates.rows.length }, null, 2));
}

main().catch((e) => {
  console.error('[backfill-expense-pr-po] failed:', e);
  process.exit(1);
});

