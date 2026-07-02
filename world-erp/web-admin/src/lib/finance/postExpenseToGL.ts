import { query } from '@/lib/db';

export interface GlPostResult {
  journalId: number;
}

/**
 * Post a paid expense to the General Ledger. Idempotency is handled by the
 * caller — invoke only once per (expense → paid) transition.
 *
 * Inserts one journal_entries row and one or more ledger_lines:
 *   - Dr expense account (per item mapped_account_code, default 510300)
 *   - Dr input VAT 110500 (if vatAmount > 0)
 *   - Cr cash-at-bank 110200 (total amount)
 */
export async function postExpenseToGL(args: {
  expenseId: number;
  vendorName: string;
  totalAmount: number | string;
  vatAmount: number | string;
}): Promise<GlPostResult> {
  const itemsRes = await query(
    `SELECT amount, mapped_account_code, description
     FROM expense_items WHERE expense_id = $1`,
    [args.expenseId],
  );
  const items = itemsRes.rows;

  const journalRes = await query(
    `INSERT INTO journal_entries (expense_id, description)
     VALUES ($1, $2) RETURNING id`,
    [args.expenseId, `Disbursed employee reimbursement for ${args.vendorName} (EXP-${args.expenseId})`],
  );
  const journalId: number = journalRes.rows[0].id;

  for (const item of items) {
    const accountCode = item.mapped_account_code || '510300';
    await query(
      `INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
       VALUES ($1, $2, $3, 0.00, $4)`,
      [journalId, accountCode, item.amount, item.description],
    );
  }

  const vatVal = parseFloat(String(args.vatAmount));
  if (vatVal > 0) {
    await query(
      `INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
       VALUES ($1, '110500', $2, 0.00, $3)`,
      [journalId, vatVal, `Input VAT 7% for EXP-${args.expenseId}`],
    );
  }

  const totalVal = parseFloat(String(args.totalAmount));
  await query(
    `INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
     VALUES ($1, '110200', 0.00, $2, $3)`,
    [journalId, totalVal, `Disbursed cash at bank for EXP-${args.expenseId}`],
  );

  return { journalId };
}