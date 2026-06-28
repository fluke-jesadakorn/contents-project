'use server';

import { query } from '@/lib/db';
import axios from 'axios';
import { SERVER_ACTION_ROLES, type RoleName } from '@/lib/permissions';

const OLLAMA_URL = process.env.OLLAMA_URL || 'http://localhost:11434';
const EMBED_MODEL = process.env.EMBED_MODEL || 'bge-m3:latest';

/**
 * Server-side role assertion helper.
 * Queries the DB for the user's role and throws if it's not in the allowed list.
 */
async function assertRole(actorId: number, allowedRoles: RoleName[]): Promise<string> {
  const res = await query(
    'SELECT r.name FROM users u JOIN roles r ON u.role_id = r.id WHERE u.id = $1',
    [actorId]
  );
  if (res.rows.length === 0) {
    throw new Error('User not found');
  }
  const role = res.rows[0].name as string;
  if (!allowedRoles.includes(role as RoleName)) {
    throw new Error(`Permission denied: บทบาท "${role}" ไม่มีสิทธิ์ดำเนินการนี้ (ต้องการ: ${allowedRoles.join(', ')})`);
  }
  return role;
}
export async function getDashboardData() {
  try {
    const usersRes = await query('SELECT u.*, r.name as role_name FROM users u JOIN roles r ON u.role_id = r.id ORDER BY u.id');
    const coaRes = await query('SELECT code, name, name_th, account_type FROM chart_of_accounts ORDER BY code');
    
    // Fetch expenses with submitter name
    const expensesRes = await query(`
      SELECT e.*, u.fullname as submitter_name, u.department as submitter_dept
      FROM expenses e
      JOIN users u ON e.submitter_id = u.id
      ORDER BY e.created_at DESC
    `);

    // For each expense, load its items
    const expenses = expensesRes.rows;
    for (const exp of expenses) {
      const itemsRes = await query(
        'SELECT id, description, amount, mapped_account_code FROM expense_items WHERE expense_id = $1 ORDER BY id',
        [exp.id]
      );
      exp.items = itemsRes.rows;

      // Load approval logs
      const logsRes = await query(`
        SELECT l.*, u.fullname as actor_name, r.name as actor_role
        FROM approval_logs l
        JOIN users u ON l.actor_id = u.id
        JOIN roles r ON u.role_id = r.id
        WHERE l.expense_id = $1
        ORDER BY l.created_at ASC
      `, [exp.id]);
      exp.logs = logsRes.rows;
    }

    return {
      success: true,
      users: usersRes.rows,
      coa: coaRes.rows,
      expenses: expenses,
    };
  } catch (error: any) {
    console.error('Failed to get dashboard data:', error);
    return { success: false, error: error.message };
  }
}

// Generate real-time semantic suggestions for a line-item description
export async function getSemanticSuggestions(description: string) {
  if (!description || description.trim() === '') {
    return { success: true, suggestions: [] };
  }
  
  try {
    // 1. Get embedding from local Ollama
    const response = await axios.post(`${OLLAMA_URL}/api/embed`, {
      model: EMBED_MODEL,
      input: description
    });

    const embedding = response.data.embeddings 
      ? response.data.embeddings[0] 
      : response.data.embedding;

    if (!embedding) {
      return { success: false, error: 'Could not generate embedding from Ollama.' };
    }

    const vectorStr = `[${embedding.join(',')}]`;

    // 2. Perform cosine similarity check
    const suggestionsRes = await query(`
      SELECT code, name, name_th, account_type,
             (1 - (embedding <=> $1::vector)) as similarity
      FROM chart_of_accounts
      ORDER BY similarity DESC
      LIMIT 3
    `, [vectorStr]);

    return {
      success: true,
      suggestions: suggestionsRes.rows.map(r => ({
        code: r.code,
        name: r.name,
        name_th: r.name_th,
        account_type: r.account_type,
        similarity: parseFloat((r.similarity * 100).toFixed(1))
      }))
    };
  } catch (error: any) {
    console.error('Semantic search error:', error);
    return { success: false, error: error.message };
  }
}

// Staff submits a mock expense (simulating receipt OCR upload)
export async function submitMockExpense(data: {
  submitterId: number;
  vendorName: string;
  transactionDate: string;
  subtotal: number;
  vatAmount: number;
  totalAmount: number;
  paymentMethod: string;
  items: Array<{ description: string; amount: number }>;
  isCorrupted?: boolean;
  correctionNotes?: string;
}) {
  try {
    // Role check: only staff can submit expenses
    await assertRole(data.submitterId, SERVER_ACTION_ROLES.submit_expense);

    // Start transaction
    await query('BEGIN');

    // 1. Insert header
    const headerRes = await query(`
      INSERT INTO expenses (
        submitter_id, vendor_name, transaction_date, subtotal, vat_amount, total_amount, 
        payment_method, status, is_corrupted, correction_notes, ocr_raw_json
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING id
    `, [
      data.submitterId,
      data.vendorName,
      data.transactionDate,
      data.subtotal,
      data.vatAmount,
      data.totalAmount,
      data.paymentMethod,
      'ocr_extracted', // defaults to extracted directly
      data.isCorrupted || false,
      data.correctionNotes || '',
      JSON.stringify(data)
    ]);

    const expenseId = headerRes.rows[0].id;

    // 2. Insert items and run auto-mapping
    for (const item of data.items) {
      // Find best category match automatically
      let bestCode = null;
      let score = 0;

      try {
        const ollamaRes = await axios.post(`${OLLAMA_URL}/api/embed`, {
          model: EMBED_MODEL,
          input: item.description
        });
        const embedding = ollamaRes.data.embeddings ? ollamaRes.data.embeddings[0] : ollamaRes.data.embedding;
        if (embedding) {
          const vectorStr = `[${embedding.join(',')}]`;
          const matchRes = await query(`
            SELECT code, (1 - (embedding <=> $1::vector)) as similarity
            FROM chart_of_accounts
            ORDER BY similarity DESC
            LIMIT 1
          `, [vectorStr]);
          if (matchRes.rows.length > 0) {
            bestCode = matchRes.rows[0].code;
            score = matchRes.rows[0].similarity;
          }
        }
      } catch (err) {
        console.warn('Failed auto-mapping for item:', item.description, err);
      }

      await query(`
        INSERT INTO expense_items (expense_id, description, amount, mapped_account_code, confidence_score)
        VALUES ($1, $2, $3, $4, $5)
      `, [expenseId, item.description, item.amount, bestCode, score]);
    }

    // 3. Log initial status
    await query(`
      INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments)
      VALUES ($1, $2, NULL, 'ocr_extracted', 'Receipt uploaded and parsed via AI OCR pipeline')
    `, [expenseId, data.submitterId]);

    await query('COMMIT');
    return { success: true, expenseId };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('Failed to submit expense:', error);
    return { success: false, error: error.message };
  }
}

// Accountant reviews and corrects details and COA codes
export async function reviewAndCorrectExpense(
  expenseId: number,
  actorId: number,
  updates: {
    vendorName: string;
    transactionDate: string;
    subtotal: number;
    vatAmount: number;
    totalAmount: number;
    paymentMethod: string;
    isCorrupted: boolean;
    correctionNotes: string;
    items: Array<{ id: number; description: string; amount: number; code: string }>;
  }
) {
  try {
    // Role check: only accountant can review/correct expenses
    await assertRole(actorId, SERVER_ACTION_ROLES.review_expense);

    await query('BEGIN');

    // 1. Update header
    await query(`
      UPDATE expenses
      SET vendor_name = $1, transaction_date = $2, subtotal = $3, vat_amount = $4, total_amount = $5,
          payment_method = $6, is_corrupted = $7, correction_notes = $8, status = 'accountant_reviewed',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $9
    `, [
      updates.vendorName,
      updates.transactionDate,
      updates.subtotal,
      updates.vatAmount,
      updates.totalAmount,
      updates.paymentMethod,
      updates.isCorrupted,
      updates.correctionNotes,
      expenseId
    ]);

    // 2. Update items
    for (const item of updates.items) {
      await query(`
        UPDATE expense_items
        SET description = $1, amount = $2, mapped_account_code = $3, confidence_score = 1.0
        WHERE id = $4 AND expense_id = $5
      `, [item.description, item.amount, item.code, item.id, expenseId]);
    }

    // 3. Log approval state
    await query(`
      INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments)
      VALUES ($1, $2, 'ocr_extracted', 'accountant_reviewed', 'Accountant corrected values and confirmed accounts')
    `, [expenseId, actorId]);

    await query('COMMIT');
    return { success: true };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('Failed to review expense:', error);
    return { success: false, error: error.message };
  }
}

// Manager or Admin changes status (Approve, Reject, Pay)
export async function changeExpenseStatus(
  expenseId: number,
  actorId: number,
  newStatus: string,
  comments: string
) {
  try {
    // Role check based on target status
    if (newStatus === 'approved' || newStatus === 'rejected') {
      await assertRole(actorId, SERVER_ACTION_ROLES.approve_reject);
    } else if (newStatus === 'paid') {
      await assertRole(actorId, SERVER_ACTION_ROLES.settle_payment);
    }

    await query('BEGIN');

    // Get current status
    const curRes = await query('SELECT status FROM expenses WHERE id = $1', [expenseId]);
    if (curRes.rows.length === 0) {
      throw new Error('Expense not found.');
    }
    const previousStatus = curRes.rows[0].status;

    // Update status
    await query(`
      UPDATE expenses
      SET status = $1, updated_at = CURRENT_TIMESTAMP
      WHERE id = $2
    `, [newStatus, expenseId]);

    // Log event
    await query(`
      INSERT INTO approval_logs (expense_id, actor_id, previous_status, new_status, comments)
      VALUES ($1, $2, $3, $4, $5)
    `, [expenseId, actorId, previousStatus, newStatus, comments || `Status changed to ${newStatus}`]);

    // GL Recording logic
    if (newStatus === 'approved') {
      // Fetch expense headers and details
      const expRes = await query('SELECT total_amount, vat_amount, vendor_name FROM expenses WHERE id = $1', [expenseId]);
      const exp = expRes.rows[0];
      
      const itemsRes = await query('SELECT amount, mapped_account_code, description FROM expense_items WHERE expense_id = $1', [expenseId]);
      const items = itemsRes.rows;

      // 1. Create Journal Entry Header
      const journalRes = await query(`
        INSERT INTO journal_entries (expense_id, description)
        VALUES ($1, $2)
        RETURNING id
      `, [expenseId, `Accrued expense liability from ${exp.vendor_name} (EXP-${expenseId})`]);
      
      const journalId = journalRes.rows[0].id;

      // 2. Insert Debits for Items
      for (const item of items) {
        const accountCode = item.mapped_account_code || '510300'; // Default to Office Supplies if null
        await query(`
          INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
          VALUES ($1, $2, $3, 0.00, $4)
        `, [journalId, accountCode, item.amount, item.description]);
      }

      // 3. Insert Debit for Input VAT (if any)
      const vatVal = parseFloat(exp.vat_amount);
      if (vatVal > 0) {
        await query(`
          INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
          VALUES ($1, '110500', $2, 0.00, $3)
        `, [journalId, vatVal, `Input VAT 7% for EXP-${expenseId}`]);
      }

      // 4. Insert Credit for Employee Reimbursement Payable
      const totalVal = parseFloat(exp.total_amount);
      await query(`
        INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
        VALUES ($1, '210500', 0.00, $2, $3)
      `, [journalId, totalVal, `Accrued employee reimbursement payable for EXP-${expenseId}`]);

    } else if (newStatus === 'paid') {
      // Fetch expense headers
      const expRes = await query('SELECT total_amount, vendor_name FROM expenses WHERE id = $1', [expenseId]);
      const exp = expRes.rows[0];
      const totalVal = parseFloat(exp.total_amount);

      // 1. Create Journal Entry Header
      const journalRes = await query(`
        INSERT INTO journal_entries (expense_id, description)
        VALUES ($1, $2)
        RETURNING id
      `, [expenseId, `Settled employee reimbursement for ${exp.vendor_name} (EXP-${expenseId})`]);
      
      const journalId = journalRes.rows[0].id;

      // 2. Debit Employee Reimbursement Payable (clear liability)
      await query(`
        INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
        VALUES ($1, '210500', $2, 0.00, $3)
      `, [journalId, totalVal, `Cleared employee reimbursement payable for EXP-${expenseId}`]);

      // 3. Credit Cash at Bank (disburse cash)
      await query(`
        INSERT INTO ledger_lines (journal_entry_id, account_code, debit, credit, description)
        VALUES ($1, '110200', 0.00, $2, $3)
      `, [journalId, totalVal, `Disbursed cash at bank for EXP-${expenseId}`]);
    }

    await query('COMMIT');
    return { success: true };
  } catch (error: any) {
    await query('ROLLBACK');
    console.error('Failed to change status:', error);
    return { success: false, error: error.message };
  }
}

// Fetch ledger entries for GL view (requires accountant, manager, or admin role)
export async function getLedgerEntries(actorId?: number) {
  try {
    // Role check if actorId is provided
    if (actorId) {
      await assertRole(actorId, SERVER_ACTION_ROLES.view_ledger);
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
// Fetch executive financial report for CFO/CEO Cockpit view (admin only)
export async function getExecutiveReport(actorId?: number) {
  try {
    // Role check if actorId is provided
    if (actorId) {
      await assertRole(actorId, SERVER_ACTION_ROLES.view_executive_report);
    }
    // 1. Fetch COA with computed balances from ledger lines
    const balanceRes = await query(`
      SELECT 
        c.code, 
        c.name, 
        c.name_th, 
        c.account_type,
        COALESCE(SUM(l.debit), 0)::float as total_debit,
        COALESCE(SUM(l.credit), 0)::float as total_credit
      FROM chart_of_accounts c
      LEFT JOIN ledger_lines l ON c.code = l.account_code
      GROUP BY c.code, c.name, c.name_th, c.account_type
      ORDER BY c.code
    `);

    const accounts = balanceRes.rows.map(acc => {
      let balance = 0;
      if (acc.account_type === 'asset' || acc.account_type === 'expense') {
        balance = acc.total_debit - acc.total_credit;
      } else {
        // liability, equity, revenue
        balance = acc.total_credit - acc.total_debit;
      }
      return {
        code: acc.code,
        name: acc.name,
        name_th: acc.name_th,
        account_type: acc.account_type,
        total_debit: acc.total_debit,
        total_credit: acc.total_credit,
        balance: balance
      };
    });

    // 2. Group into statements
    const assets = accounts.filter(a => a.account_type === 'asset');
    const liabilities = accounts.filter(a => a.account_type === 'liability');
    const equity = accounts.filter(a => a.account_type === 'equity');
    const revenue = accounts.filter(a => a.account_type === 'revenue');
    const expense = accounts.filter(a => a.account_type === 'expense' && a.balance > 0);

    const totalAssets = assets.reduce((sum, a) => sum + a.balance, 0);
    const totalLiabilities = liabilities.reduce((sum, a) => sum + a.balance, 0);
    const totalEquity = equity.reduce((sum, a) => sum + a.balance, 0);
    const totalRevenue = revenue.reduce((sum, a) => sum + a.balance, 0);
    const totalExpense = expense.reduce((sum, a) => sum + a.balance, 0);
    const netIncome = totalRevenue - totalExpense;

    // 3. Calculate KPIs
    // Total cash: 110100, 110200, 110300
    const cashAccounts = assets.filter(a => ['110100', '110200', '110300'].includes(a.code));
    const totalCash = cashAccounts.reduce((sum, a) => sum + a.balance, 0);

    // Outstanding liabilities
    const totalLiabilitiesOutstanding = liabilities.reduce((sum, a) => sum + a.balance, 0);

    // MTD Expenses
    const mtdRes = await query(`
      SELECT COALESCE(SUM(l.debit), 0)::float as mtd
      FROM ledger_lines l
      JOIN journal_entries j ON l.journal_entry_id = j.id
      JOIN chart_of_accounts c ON l.account_code = c.code
      WHERE c.account_type = 'expense'
        AND j.entry_date >= DATE_TRUNC('month', CURRENT_DATE)
    `);
    const mtdExpenses = mtdRes.rows[0].mtd;

    // 4. Calculate Statement of Cash Flows (Direct Method)
    const inflowsRes = await query(`
      SELECT COALESCE(SUM(debit), 0)::float as amount
      FROM ledger_lines
      WHERE account_code IN ('110100', '110200', '110300')
        AND debit > 0
    `);
    const cashInflows = inflowsRes.rows[0].amount;

    const outflowsRes = await query(`
      SELECT COALESCE(SUM(credit), 0)::float as amount
      FROM ledger_lines
      WHERE account_code IN ('110100', '110200', '110300')
        AND credit > 0
    `);
    const cashOutflows = outflowsRes.rows[0].amount;

    // Receipts from customers
    const clientReceiptsRes = await query(`
      SELECT COALESCE(SUM(l1.debit), 0)::float as amount
      FROM ledger_lines l1
      JOIN ledger_lines l2 ON l1.journal_entry_id = l2.journal_entry_id
      JOIN chart_of_accounts c2 ON l2.account_code = c2.code
      WHERE l1.account_code IN ('110100', '110200', '110300')
        AND l1.debit > 0
        AND c2.account_type = 'revenue'
        AND l2.credit > 0
    `);
    const customerReceipts = clientReceiptsRes.rows[0].amount;

    // Outflows for Employee Reimbursements
    const employeePaymentsRes = await query(`
      SELECT COALESCE(SUM(l1.credit), 0)::float as amount
      FROM ledger_lines l1
      JOIN ledger_lines l2 ON l1.journal_entry_id = l2.journal_entry_id
      WHERE l1.account_code IN ('110100', '110200', '110300')
        AND l1.credit > 0
        AND l2.account_code = '210500'
        AND l2.debit > 0
    `);
    const employeeReimbursementsPaid = employeePaymentsRes.rows[0].amount;

    const otherInflows = cashInflows - customerReceipts;
    const otherOutflows = cashOutflows - employeeReimbursementsPaid;

    return {
      success: true,
      report: {
        incomeStatement: {
          revenue,
          expense,
          totalRevenue,
          totalExpense,
          netIncome
        },
        balanceSheet: {
          assets: assets.filter(a => a.balance !== 0),
          liabilities: liabilities.filter(l => l.balance !== 0),
          equity: equity.filter(e => e.balance !== 0),
          totalAssets,
          totalLiabilities,
          totalEquity,
          netIncome,
          isBalanced: Math.abs(totalAssets - (totalLiabilities + totalEquity + netIncome)) < 0.01
        },
        cashFlowStatement: {
          customerReceipts,
          employeeReimbursementsPaid,
          otherInflows,
          otherOutflows,
          totalInflows: cashInflows,
          totalOutflows: cashOutflows,
          netCashFlow: cashInflows - cashOutflows,
          beginningBalance: 0.00,
          endingBalance: cashInflows - cashOutflows
        },
        kpis: {
          totalCash,
          outstandingLiabilities: totalLiabilitiesOutstanding,
          mtdExpenses
        }
      }
    };
  } catch (error: any) {
    console.error('Failed to generate executive report:', error);
    return { success: false, error: error.message };
  }
}
