import { query } from '@/lib/db';
import { PERM } from '@erp-lib/perm/server';
import { assertRole } from '@/lib/assertRole';

export async function getLedgerEntries(actorId?: number) {
  try {
    if (actorId) {
      try { await assertRole(actorId, [], { perm: PERM.finance.ledger.view }); }
      catch { return { success: false, error: 'forbidden' }; }
    }
    const journalRes = await query(`
      SELECT j.*, e.vendor_name, e.total_amount, u.fullname as submitter_name
      FROM journal_entries j
      LEFT JOIN expenses e ON j.expense_id = e.id
      LEFT JOIN users u ON e.submitter_id = u.id
      ORDER BY j.entry_date DESC, j.id DESC
    `);
    const journals = journalRes.rows;
    for (const journal of journals) {
      const linesRes = await query(`
        SELECT l.*, c.name_th as account_name_th, c.name as account_name_en, c.account_type
        FROM ledger_lines l
        LEFT JOIN chart_of_accounts c ON l.account_code = c.code
        WHERE l.journal_entry_id = $1
        ORDER BY l.debit DESC, l.id ASC
      `, [journal.id]);
      journal.lines = linesRes.rows;
    }
    return { success: true, journals };
  } catch (error: any) {
    console.error('Failed to get ledger entries:', error);
    return { success: false, error: error.message };
  }
}