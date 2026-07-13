// world-erp/scripts/snapshot-exec.ts
//
// Snapshots today's executive KPIs into `exec_snapshots` for the 7-day trend
// shown on TodaysBrief. Reads .env.local from web-admin/ and connects directly
// via `pg` so it can be cron-launched without a Next.js process running.
//
// Run with: `bun run snapshot-exec` (from world-erp/)
// Or:       `cd world-erp && bun scripts/snapshot-exec.ts`

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

const pool = new Pool({
  user: process.env.POSTGRES_USER || 'contract',
  password: process.env.POSTGRES_PASSWORD || 'contractpw',
  host: process.env.POSTGRES_HOST || 'localhost',
  database: process.env.POSTGRES_DB || 'finance_db',
  port: Number(process.env.POSTGRES_PORT || 5432),
});

interface KpiRow {
  total_cash: string;
  outstanding_liabilities: string;
  mtd_expenses: string;
  net_income: string;
}

interface DeptRow {
  dept_id: string;
  dept_name: string;
  monthly_budget: string;
  mtd_spend: string;
  pct_used: string;
  is_over_threshold: boolean;
}

async function loadKpis(): Promise<KpiRow> {
  const r = await pool.query<KpiRow>(
    `WITH coa_balance AS (
       SELECT c.code, c.account_type,
              COALESCE(SUM(l.debit), 0)::numeric  AS total_debit,
              COALESCE(SUM(l.credit), 0)::numeric AS total_credit
         FROM chart_of_accounts c
         LEFT JOIN ledger_lines l ON c.code = l.account_code
         GROUP BY c.code, c.account_type
     ),
     mtd_expenses AS (
       SELECT COALESCE(SUM(l.debit), 0)::numeric AS mtd
         FROM ledger_lines l
         JOIN journal_entries j ON l.journal_entry_id = j.id
         JOIN chart_of_accounts c ON c.code = l.account_code
        WHERE c.account_type = 'expense'
          AND j.entry_date >= DATE_TRUNC('month', CURRENT_DATE)
     )
     SELECT
       COALESCE(SUM(CASE WHEN account_type IN ('asset','expense') THEN total_debit - total_credit ELSE 0 END), 0)::numeric -
       COALESCE(SUM(CASE WHEN account_type IN ('liability','equity','revenue') THEN total_credit - total_debit ELSE 0 END), 0)::numeric
       AS net_income,
       COALESCE(SUM(CASE WHEN code IN ('110100','110200','110300') AND account_type = 'asset' THEN total_debit - total_credit ELSE 0 END), 0)::numeric
       AS total_cash,
       COALESCE(SUM(CASE WHEN account_type = 'liability' THEN total_credit - total_debit ELSE 0 END), 0)::numeric
       AS outstanding_liabilities,
       (SELECT mtd FROM mtd_expenses) AS mtd_expenses
       FROM coa_balance`,
  );
  return r.rows[0];
}

async function loadDeptBudgets(year: number, month: number): Promise<DeptRow[]> {
  const r = await pool.query<DeptRow>(
    `SELECT * FROM get_dept_budget_status($1::int, $2::int)`,
    [year, month],
  );
  return r.rows;
}

async function loadStuck(): Promise<number> {
  const r = await pool.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n
       FROM expenses e
       JOIN waybills w ON w.origin='expense' AND w.origin_id = e.id
      WHERE w.current_stage NOT IN ('disbursed','rejected','gl_confirmed')
        AND e.created_at < NOW() - INTERVAL '24 hours'`,
  );
  return r.rows[0]?.n ?? 0;
}

async function upsertSnapshot(date: string, kpis: unknown, deptBudgets: unknown[], stuck: number): Promise<void> {
  await pool.query(
    `INSERT INTO exec_snapshots (snapshot_date, kpis, dept_budgets, stuck_count)
       VALUES ($1, $2::jsonb, $3::jsonb, $4)
     ON CONFLICT (snapshot_date) DO UPDATE
       SET kpis = EXCLUDED.kpis,
           dept_budgets = EXCLUDED.dept_budgets,
           stuck_count = EXCLUDED.stuck_count,
           created_at = now()`,
    [date, JSON.stringify(kpis), JSON.stringify(deptBudgets), stuck],
  );
}

function parseBackfillDays(argv: string[]): number {
  const i = argv.indexOf('--backfill');
  if (i === -1) return 0;
  const n = parseInt(argv[i + 1] ?? '', 10);
  if (!Number.isFinite(n) || n < 0) return 0;
  return n;
}

async function snapshotToday(): Promise<void> {
  const now = new Date();
  const date = now.toISOString().slice(0, 10);
  const year = now.getFullYear();
  const month = now.getMonth() + 1;

  const [kpisRow, depts, stuck] = await Promise.all([
    loadKpis(),
    loadDeptBudgets(year, month),
    loadStuck(),
  ]);

  const kpis = {
    cash: { totalCash: Number(kpisRow.total_cash) },
    kpis: {
      outstandingLiabilities: Number(kpisRow.outstanding_liabilities),
      mtdExpenses: Number(kpisRow.mtd_expenses),
      netIncome: Number(kpisRow.net_income),
    },
  };

  const deptBudgets = depts.map((d) => ({
    dept_id: d.dept_id,
    dept_name: d.dept_name,
    monthly_budget: Number(d.monthly_budget),
    mtd_spend: Number(d.mtd_spend),
    pct_used: Number(d.pct_used),
    is_over_threshold: d.is_over_threshold,
  }));

  await upsertSnapshot(date, kpis, deptBudgets, stuck);

  console.log(`[snapshot-exec] ok ${date}`);
  console.log(`  cash=${kpis.cash.totalCash.toLocaleString()} THB`);
  console.log(`  mtd_expenses=${kpis.kpis.mtdExpenses.toLocaleString()} THB`);
  console.log(`  outstanding_liab=${kpis.kpis.outstandingLiabilities.toLocaleString()} THB`);
  console.log(`  net_income=${kpis.kpis.netIncome.toLocaleString()} THB`);
  console.log(`  dept_rows=${deptBudgets.length}  stuck=${stuck}`);
}

async function runBackfill(days: number): Promise<void> {
  const cashSeries = [20000, 12000, 5000, -8000, -28000, -45000, -58000, -67410];
  const mtdSeries  = [ 5000, 11000, 18000, 22000, 26000, 29000, 31000, 33000];
  if (days + 1 > cashSeries.length) {
    console.error(`[snapshot-exec] --backfill ${days} exceeds data length (max ${cashSeries.length - 1})`);
    return;
  }
  const today = new Date();
  for (let offset = days; offset >= 0; offset--) {
    const d = new Date(today);
    d.setUTCDate(d.getUTCDate() - offset);
    const dateStr = d.toISOString().slice(0, 10);
    const seriesIdx = days - offset;
    const cashVal = cashSeries[seriesIdx];
    const mtdVal  = mtdSeries[seriesIdx];
    await pool.query(
      'SELECT public.backfill_exec_snapshot($1::date, $2::numeric, $3::numeric)',
      [dateStr, cashVal, mtdVal],
    );
    console.log(`[snapshot-exec] backfilled ${dateStr}  cash=${cashVal}  mtd=${mtdVal}`);
  }
  console.log(`[snapshot-exec] backfill complete: ${days + 1} rows`);
}

async function main(): Promise<void> {
  const backfillDays = parseBackfillDays(process.argv.slice(2));
  if (backfillDays > 0) {
    await runBackfill(backfillDays);
  } else {
    await snapshotToday();
  }
  await pool.end();
}

main().catch((e) => {
  console.error('[snapshot-exec] failed:', e);
  process.exit(1);
});
