import { cache } from 'react';
import { query } from '@/lib/db';
import { getActorScope, scopeFilter, PERM } from '@erp-lib/perm/server';
import { assertRole } from '@/lib/assertRole';
import { aiInvoke } from '@/lib/ai/router';
import { getUserLevels, getUserStaffLevels, resolveActorScope, loadOrgTree, type OrgNode } from '@/lib/orgScope';
import { loadActor } from '@/lib/server/guard';

export async function getDashboardData() {
  try {
    const usersRes = await query(`
      SELECT u.id, u.employee_code, u.fullname, u.line_user_id, u.created_at,
             u.is_active, u.hired_at, u.secondary_locale,
             r.role_id, r.role_name, dg.dept_id
        FROM users u
        LEFT JOIN LATERAL (
          SELECT ur.role_id, split_part(ur.role_id, '::', 1) AS role_name FROM perm.user_roles ur
            WHERE ur.user_id = u.id
            ORDER BY (CASE WHEN ur.role_id LIKE '%::1' THEN 0
                           WHEN ur.role_id LIKE '%::2' THEN 1
                           WHEN ur.role_id LIKE '%::3' THEN 2
                           WHEN ur.role_id LIKE '%::4' THEN 3
                           WHEN ur.role_id LIKE '%::5' THEN 4
                           ELSE 5 END), ur.granted_at ASC
            LIMIT 1
        ) r ON true
        LEFT JOIN LATERAL (
          SELECT split_part(up.permission_id, ':', 3) AS dept_id FROM perm.user_permissions up
            WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
              AND up.revoked_at IS NULL
              AND (up.ends_at IS NULL OR up.ends_at > now())
            ORDER BY up.permission_id LIMIT 1
        ) dg ON true
        ORDER BY u.id
    `);
    const levels = await getUserLevels();
    const staffLevels = await getUserStaffLevels();
    const users = usersRes.rows.map((u: any) => ({
      ...u,
      level: levels.get(u.id) ?? 0,
      staff_level: staffLevels.get(u.id) ?? 5,
      department: u.dept_id,
      dept_group_id: u.dept_id,
    }));
    const coaRes = await query('SELECT code, name, name_th, account_type FROM chart_of_accounts ORDER BY code');

    const expensesRes = await query(`
      SELECT e.*,
             u.fullname AS submitter_name,
             (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
               WHERE up.user_id = e.submitter_id AND up.permission_id LIKE 'user:dept:%'
                 AND up.revoked_at IS NULL
                 AND (up.ends_at IS NULL OR up.ends_at > now())
               ORDER BY up.permission_id LIMIT 1) AS submitter_dept_group_id,
             (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
               WHERE up.user_id = e.submitter_id AND up.permission_id LIKE 'user:dept:%'
                 AND up.revoked_at IS NULL
                 AND (up.ends_at IS NULL OR up.ends_at > now())
               ORDER BY up.permission_id LIMIT 1) AS submitter_dept_group_name,
             ra.fullname AS rejection_actor_name
      FROM expenses e
      JOIN users u ON e.submitter_id = u.id
      LEFT JOIN users ra ON ra.id = e.rejection_actor_id
      ORDER BY e.created_at DESC
    `);

    const expenses = expensesRes.rows;
    if (expenses.length > 0) {
      const ids = expenses.map((e: any) => e.id);
      const itemsRes = await query(
        `SELECT id, expense_id, description, amount, mapped_account_code, confidence_score
         FROM expense_items
         WHERE expense_id = ANY($1::int[])
         ORDER BY expense_id, id`,
        [ids]
      );
      const logsRes = await query(
        `SELECT l.id, l.target_id AS expense_id, l.actor_id, l.previous_status, l.new_status,
                l.comments, l.stage, l.chain_index, l.created_at,
                u.fullname as actor_name, split_part(r.role_id, '::', 1) as actor_role
         FROM approval_transitions l
         JOIN users u ON l.actor_id = u.id
         LEFT JOIN LATERAL (
            SELECT ur.role_id FROM perm.user_roles ur
              WHERE ur.user_id = u.id
              ORDER BY (CASE WHEN ur.role_id LIKE '%::1' THEN 0
                             WHEN ur.role_id LIKE '%::2' THEN 1
                             WHEN ur.role_id LIKE '%::3' THEN 2
                             WHEN ur.role_id LIKE '%::4' THEN 3
                             WHEN ur.role_id LIKE '%::5' THEN 4
                             ELSE 5 END), ur.granted_at ASC
              LIMIT 1
          ) r ON true
         WHERE l.target_type = 'expense' AND l.target_id = ANY($1::int[])
         ORDER BY l.target_id, l.created_at ASC, l.id ASC`,
        [ids]
      );
      const itemsByExpense = new Map<number, any[]>();
      for (const it of itemsRes.rows) {
        if (!itemsByExpense.has(it.expense_id)) itemsByExpense.set(it.expense_id, []);
        itemsByExpense.get(it.expense_id)!.push(it);
      }
      const logsByExpense = new Map<number, any[]>();
      for (const lg of logsRes.rows) {
        if (!logsByExpense.has(lg.expense_id)) logsByExpense.set(lg.expense_id, []);
        logsByExpense.get(lg.expense_id)!.push(lg);
      }
      for (const exp of expenses) {
        exp.items = itemsByExpense.get(exp.id) ?? [];
        exp.logs = logsByExpense.get(exp.id) ?? [];
      }
    }

    return { success: true, users, coa: coaRes.rows, expenses };
  } catch (error: any) {
    console.error('Failed to get dashboard data:', error);
    return { success: false, error: error.message };
  }
}

export async function getSemanticSuggestions(description: string) {
  if (!description || description.trim() === '') {
    return { success: true, suggestions: [] };
  }
  try {
    const ai = await aiInvoke('acct:coa-search', 'embed', { text: description });
    if (!ai.ok || !ai.embedding) {
      return { success: false, error: ai.error || 'Could not generate embedding.' };
    }
    const vectorStr = `[${ai.embedding.join(',')}]`;
    const suggestionsRes = await query(`
      SELECT code, name, name_th, account_type,
             (1 - (embedding <=> $1::vector)) as similarity
      FROM chart_of_accounts
      ORDER BY similarity DESC
      LIMIT 3
    `, [vectorStr]);
    return {
      success: true,
      suggestions: suggestionsRes.rows.map((r: any) => ({
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

export const getExecutiveReport = cache(async (actorId?: number) => {
  try {
    if (actorId) {
      try { await assertRole(actorId, [], { perm: 'tile:dash_exec:view::allow' }); }
      catch { return { success: false, error: 'forbidden' }; }
    }

    const r = await query(`
      WITH coa_balance AS (
        SELECT
          c.code, c.name, c.name_th, c.account_type,
          COALESCE(SUM(l.debit), 0)::float  AS total_debit,
          COALESCE(SUM(l.credit), 0)::float AS total_credit
        FROM chart_of_accounts c
        LEFT JOIN ledger_lines l ON c.code = l.account_code
        GROUP BY c.code, c.name, c.name_th, c.account_type
      ),
      cash_balance AS (
        SELECT
          COALESCE(SUM(CASE WHEN account_code IN ('110100','110200','110300') THEN debit ELSE 0 END), 0)::float AS cash_in,
          COALESCE(SUM(CASE WHEN account_code IN ('110100','110200','110300') THEN credit ELSE 0 END), 0)::float AS cash_out
        FROM ledger_lines
      ),
      customer_receipts AS (
        SELECT COALESCE(SUM(l1.debit), 0)::float AS amount
        FROM ledger_lines l1
        JOIN ledger_lines l2 ON l1.journal_entry_id = l2.journal_entry_id
        JOIN chart_of_accounts c2 ON l2.account_code = c2.code
        WHERE l1.account_code IN ('110100','110200','110300')
          AND l1.debit > 0
          AND c2.account_type = 'revenue'
          AND l2.credit > 0
      ),
      employee_payments AS (
        SELECT COALESCE(SUM(l1.credit), 0)::float AS amount
        FROM ledger_lines l1
        JOIN ledger_lines l2 ON l1.journal_entry_id = l2.journal_entry_id
        WHERE l1.account_code IN ('110100','110200','110300')
          AND l1.credit > 0
          AND l2.account_code = '210500'
          AND l2.debit > 0
      ),
      mtd_expenses AS (
        SELECT COALESCE(SUM(l.debit), 0)::float AS mtd
        FROM ledger_lines l
        JOIN journal_entries j ON l.journal_entry_id = j.id
        JOIN chart_of_accounts c ON l.account_code = c.code
        WHERE c.account_type = 'expense'
          AND j.entry_date >= DATE_TRUNC('month', CURRENT_DATE)
      )
      SELECT
        (SELECT json_agg(row_to_json(c)) FROM coa_balance c) AS accounts,
        (SELECT cash_in  FROM cash_balance) AS cash_in,
        (SELECT cash_out FROM cash_balance) AS cash_out,
        (SELECT amount   FROM customer_receipts) AS customer_receipts,
        (SELECT amount   FROM employee_payments) AS employee_payments,
        (SELECT mtd      FROM mtd_expenses) AS mtd_expenses
    `);

    const row = r.rows[0];
    const accounts = (row.accounts || []).map((acc: any) => {
      let balance = 0;
      if (acc.account_type === 'asset' || acc.account_type === 'expense') {
        balance = acc.total_debit - acc.total_credit;
      } else {
        balance = acc.total_credit - acc.total_debit;
      }
      return {
        code: acc.code, name: acc.name, name_th: acc.name_th,
        account_type: acc.account_type,
        total_debit: acc.total_debit, total_credit: acc.total_credit,
        balance,
      };
    });

    const assets = accounts.filter((a: any) => a.account_type === 'asset');
    const liabilities = accounts.filter((a: any) => a.account_type === 'liability');
    const equity = accounts.filter((a: any) => a.account_type === 'equity');
    const revenue = accounts.filter((a: any) => a.account_type === 'revenue');
    const expense = accounts.filter((a: any) => a.account_type === 'expense' && a.balance > 0);

    const totalAssets = assets.reduce((s: number, a: any) => s + a.balance, 0);
    const totalLiabilities = liabilities.reduce((s: number, a: any) => s + a.balance, 0);
    const totalEquity = equity.reduce((s: number, a: any) => s + a.balance, 0);
    const totalRevenue = revenue.reduce((s: number, a: any) => s + a.balance, 0);
    const totalExpense = expense.reduce((s: number, a: any) => s + a.balance, 0);
    const netIncome = totalRevenue - totalExpense;

    const cashAccounts = assets.filter((a: any) => ['110100', '110200', '110300'].includes(a.code));
    const totalCash = cashAccounts.reduce((s: number, a: any) => s + a.balance, 0);

    const cashInflows = row.cash_in;
    const cashOutflows = row.cash_out;
    const customerReceipts = row.customer_receipts;
    const employeeReimbursementsPaid = row.employee_payments;
    const otherInflows = cashInflows - customerReceipts;
    const otherOutflows = cashOutflows - employeeReimbursementsPaid;
    const mtdExpenses = row.mtd_expenses;

    return {
      success: true,
      report: {
        incomeStatement: { revenue, expense, totalRevenue, totalExpense, netIncome },
        balanceSheet: {
          assets: assets.filter((a: any) => a.balance !== 0),
          liabilities: liabilities.filter((l: any) => l.balance !== 0),
          equity: equity.filter((e: any) => e.balance !== 0),
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
        kpis: { totalCash, outstandingLiabilities: totalLiabilities, mtdExpenses }
      }
    };
  } catch (error: any) {
    console.error('Failed to generate executive report:', error);
    return { success: false, error: error.message };
  }
});

export async function listApprovalPolicies(actorId?: number) {
  try {
    if (actorId) {
      try { await assertRole(actorId, [], { perm: PERM.tile.policy.view }); }
      catch { return { success: false, error: 'forbidden', policies: [] }; }
    }
    const r = await query(
      `SELECT p.*, u.fullname AS created_by_name
       FROM approval_policies p
       LEFT JOIN users u ON p.created_by = u.id
       ORDER BY p.is_active DESC, p.priority ASC, p.id ASC`
    );
    return { success: true, policies: r.rows };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function listPurchaseRequisitions(actorId?: number) {
  try {
    let scopeSql = '';
    let params: any[] = [];
    if (actorId) {
      const actor = await loadActor();
      if (actor) {
        const scope = await getActorScope(new Set(actor.permissions ?? []), actor.id);
        const f = scopeFilter(scope, 'pr.requester_id');
        if (f.clause) {
          scopeSql = 'WHERE ' + f.clause;
          params = f.params;
        }
      }
    }
    const r = await query(
      `SELECT pr.*, u.fullname AS requester_name,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_id,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_name,
              d.display_name AS dept_name, p.display_name AS policy_name, p.priority AS policy_priority,
              ra.fullname AS rejection_actor_name
       FROM purchase_requisitions pr
       JOIN users u ON pr.requester_id = u.id
       LEFT JOIN perm.roles d ON pr.dept_group_id = d.id
       LEFT JOIN approval_policies p ON pr.matched_policy_id = p.id
       LEFT JOIN users ra ON ra.id = pr.rejection_actor_id
       ${scopeSql}
       ORDER BY pr.created_at DESC`,
      params,
    );
    const prs = r.rows;
    for (const pr of prs) {
      const items = await query(
        `SELECT i.*, c.name_th AS account_name_th FROM pr_items i
         LEFT JOIN chart_of_accounts c ON i.mapped_account_code = c.code
         WHERE i.pr_id = $1 ORDER BY i.id`, [pr.id]
      );
      pr.items = items.rows;
      const prLogs = await query(
        `SELECT l.*, u.fullname AS actor_name
         FROM approval_transitions l
         JOIN users u ON l.actor_id = u.id
         WHERE l.target_type = 'pr' AND l.target_id = $1
         ORDER BY l.created_at ASC`, [pr.id]
      );
      pr.logs = prLogs.rows;
    }
    return { success: true, prs };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function listPurchaseOrders(actorId?: number) {
  try {
    let scopeSql = '';
    let params: any[] = [];
    if (actorId) {
      const actor = await loadActor();
      if (actor) {
        const scope = await getActorScope(new Set(actor.permissions ?? []), actor.id);
        const f = scopeFilter(scope, 'pr.requester_id');
        if (f.clause) {
          scopeSql = 'WHERE ' + f.clause;
          params = f.params;
        }
      }
    }
    const r = await query(
      `SELECT po.*,
              u.fullname AS requester_name,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_id,
              (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS requester_dept_group_name,
              d.display_name AS dept_name,
              p.display_name AS policy_name,
              p.priority AS policy_priority,
              s.file_path AS paid_slip_path,
              s.mime_type AS paid_slip_mime,
              su.fullname AS settled_actor_name,
              ra.fullname AS rejection_actor_name
       FROM purchase_orders po
       JOIN purchase_requisitions pr ON po.pr_id = pr.id
       JOIN users u ON pr.requester_id = u.id
       LEFT JOIN perm.roles d ON pr.dept_group_id = d.id
       LEFT JOIN approval_policies p ON po.matched_policy_id = p.id
       LEFT JOIN slips s ON po.settled_slip_id = s.id
       LEFT JOIN users su ON po.settled_by = su.id
       LEFT JOIN users ra ON ra.id = po.rejection_actor_id
       ${scopeSql}
       ORDER BY po.created_at DESC`,
      params,
    );
    const pos = r.rows;
    for (const po of pos) {
      const items = await query(
        `SELECT i.*, c.name_th AS account_name_th FROM po_items i
         LEFT JOIN chart_of_accounts c ON i.mapped_account_code = c.code
         WHERE i.po_id = $1 ORDER BY i.id`,
        [po.id]
      );
      po.items = items.rows;
      const poLogs = await query(
        `SELECT l.*, u.fullname AS actor_name
         FROM approval_transitions l
         JOIN users u ON l.actor_id = u.id
         WHERE l.target_type = 'po' AND l.target_id = $1
         ORDER BY l.created_at ASC`, [po.id]
      );
      po.logs = poLogs.rows;
    }
    return { success: true, pos };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function listPayslipsForPo(poId: number) {
  try {
    const r = await query(
      `SELECT id, file_path, mime_type, ocr_confidence, uploaded_at
       FROM slips WHERE po_id = $1 ORDER BY uploaded_at DESC`,
      [poId]
    );
    return { success: true, slips: r.rows };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

type DashKind = 'it' | 'exec' | 'hod' | 'am' | 'reviewer' | 'staff' | 'hr' | 'finance';

// Legacy role-name matrix kept as dead code for reference; dashboard routing
// now resolves via `pickKindFromMatrix` based on the actor's tile:* perms.
const DASHBOARD_MATRIX: Record<DashKind, string[]> = {
  it:       ['it'],
  exec:     ['cfo', 'ceo', 'admin'],
  hod:      ['head_of_department'],
  am:       ['accounting_manager'],
  reviewer: ['accountant', 'account_officer', 'manager'],
  staff:    ['staff'],
  hr:       ['hr', 'hr_manager'],
  finance:  ['finance'],
};

function pickKind(role: string): DashKind | null {
  for (const k of Object.keys(DASHBOARD_MATRIX) as DashKind[]) {
    if (DASHBOARD_MATRIX[k].includes(role)) return k;
  }
  return null;
}

async function pickKindFromMatrix(_rbacRoleId: string | null, perms: string[] = []): Promise<DashKind | null> {
  const kindByPerm: Record<string, DashKind> = {
    'tile:dash_it:view::allow':       'it',
    'tile:dash_exec:view::allow':     'exec',
    'tile:dash_manager:view::allow':  'hod',
    'tile:dash_am:view::allow':       'am',
    'tile:dash_staff:view::allow':    'staff',
    'tile:dash_finance:view::allow':  'finance',
  };
  for (const [perm, k] of Object.entries(kindByPerm)) {
    if (perms.includes(perm)) return k;
  }
  return null;
}

async function buildITPayload() {
  const providers = await query(`
    SELECT p.id, p.name, p.type, p.base_url, p.enabled, p.preset,
           (SELECT COUNT(*)::int FROM ai_models m WHERE m.provider_id = p.id AND m.enabled) AS models_enabled,
           (SELECT COUNT(*)::int FROM ai_models m WHERE m.provider_id = p.id) AS models_total
    FROM ai_providers p
    ORDER BY p.enabled DESC, p.name ASC
  `);
  const models = await query(`
    SELECT m.id, m.display_name AS name, m.provider_id, p.display_name AS provider_name,
           m.capabilities, m.context_window, m.enabled
    FROM ai_models m
    LEFT JOIN ai_providers p ON p.id = m.provider_id
    ORDER BY m.enabled DESC, p.name, m.name
  `);
  const staff = await query(`
    SELECT s.id, s.name, s.role_label, s.enabled,
           (SELECT COUNT(*)::int FROM ai_assignments a WHERE a.staff_id = s.id AND a.enabled) AS active_assignments
    FROM ai_staff s
    ORDER BY s.enabled DESC, s.name
  `);
  const inv24 = await query(`
    SELECT
      COUNT(*)::int AS calls,
      COALESCE(AVG(latency_ms), 0)::float AS avg_latency,
      COALESCE(percentile_disc(0.95) WITHIN GROUP (ORDER BY latency_ms), 0)::int AS p95_latency,
      SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)::int AS errors
    FROM ai_invocations
    WHERE created_at >= NOW() - INTERVAL '24 hours'
  `);
  const invBySection = await query(`
    SELECT section_key, COUNT(*)::int AS calls,
           SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)::int AS errors,
           COALESCE(AVG(latency_ms), 0)::int AS avg_latency
    FROM ai_invocations
    WHERE created_at >= NOW() - INTERVAL '24 hours'
    GROUP BY section_key
    ORDER BY calls DESC
    LIMIT 8
  `);
  const recentInv = await query(`
    SELECT i.id, i.section_key, i.task_type, i.status, i.error,
           i.latency_ms, i.prompt_tokens, i.response_tokens, i.created_at,
           p.display_name AS provider_name, m.display_name AS model_name, s.display_name AS staff_name
    FROM ai_invocations i
    LEFT JOIN ai_providers p ON p.id = i.provider_id
    LEFT JOIN ai_models m ON m.id = i.model_id
    LEFT JOIN ai_staff s ON s.id = i.staff_id
    ORDER BY i.id DESC
    LIMIT 20
  `);

  const notifBacklog = await query(`SELECT COUNT(*)::int AS n FROM notifications WHERE read_at IS NULL`);
  const totalEvents = await query(`SELECT COUNT(*)::int AS n FROM domain_events WHERE created_at >= NOW() - INTERVAL '24 hours'`);

  const inv24Row = inv24.rows[0] || { calls: 0, avg_latency: 0, p95_latency: 0, errors: 0 };

  return {
    providers: providers.rows,
    models: models.rows,
    staff: staff.rows,
    invocations24h: {
      calls: inv24Row.calls,
      avgLatency: inv24Row.avg_latency,
      p95Latency: inv24Row.p95_latency,
      errors: inv24Row.errors,
      bySection: invBySection.rows,
    },
    recent: recentInv.rows,
    transport: {
      dbLatencyMs: 0,
      notificationsBacklog: notifBacklog.rows[0].n,
      events24h: totalEvents.rows[0].n,
    },
  };
}

async function buildExecPayload() {
  const exec = await getExecutiveReport();
  if (!exec.success || !exec.report) {
    return { trialBalance: { debit: 0, credit: 0, isBalanced: true }, cashflow: null, kpis: null, pipeline: [] };
  }
  const r = exec.report;
  const debits = (r.balanceSheet?.assets || []).reduce((s: number, a: any) => s + (a.balance || 0), 0)
                + (r.balanceSheet?.liabilities || []).reduce((s: number, a: any) => s + (a.balance || 0), 0)
                + (r.balanceSheet?.equity || []).reduce((s: number, a: any) => s + (a.balance || 0), 0);
  const credits = (r.balanceSheet?.liabilities || []).reduce((s: number, a: any) => s + (a.balance || 0), 0)
                + (r.balanceSheet?.equity || []).reduce((s: number, a: any) => s + (a.balance || 0), 0)
                + (r.incomeStatement?.revenue || []).reduce((s: number, a: any) => s + (a.balance || 0), 0);
  const pipelineRes = await query(`
    SELECT status, COUNT(*)::int AS count
    FROM expenses
    WHERE status IN ('head_review','accounting_review','cfo_review','ceo_review','finance_review','ocr_extracted','accountant_reviewed')
    GROUP BY status
    ORDER BY count DESC
  `);
  return {
    trialBalance: {
      debit: debits,
      credit: credits,
      isBalanced: Math.abs(debits - credits) < 0.01,
    },
    incomeStatement: r.incomeStatement,
    balanceSheet: r.balanceSheet,
    cashflow: r.cashFlowStatement,
    kpis: r.kpis,
    pipeline: pipelineRes.rows,
  };
}

async function buildHODPayload(dept: string) {
  const queue = await query(`
    SELECT id, vendor_name, total_amount, status, transaction_date, submitter_name
    FROM expenses
    WHERE submitter_dept = $1 AND status = 'head_review'
    ORDER BY created_at DESC
    LIMIT 10
  `, [dept]);
  const counts = await query(`
    SELECT
      COUNT(*)::int AS total_in_dept,
      SUM(CASE WHEN status='head_review' THEN 1 ELSE 0 END)::int AS head_review,
      SUM(CASE WHEN status='accounting_review' OR status='cfo_review' THEN 1 ELSE 0 END)::int AS upstream,
      SUM(CASE WHEN status='approved' OR status='paid' THEN 1 ELSE 0 END)::int AS settled
    FROM expenses
    WHERE submitter_dept = $1
  `, [dept]);
  const spend = await query(`
    SELECT
      COALESCE(SUM(total_amount), 0)::float AS mtd
    FROM expenses
    WHERE submitter_dept = $1
      AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
  `, [dept]);
  return { department: dept, queue: queue.rows, counts: counts.rows[0], mtdSpend: spend.rows[0].mtd };
}

async function buildAMPayload() {
  const queue = await query(`
    SELECT status, COUNT(*)::int AS n
    FROM expenses
    WHERE status IN ('accounting_review','cfo_review','ceo_review','finance_review','accountant_reviewed','ocr_extracted')
    GROUP BY status
  `);
  const corrupted = await query(`
    SELECT COUNT(*)::int AS n FROM expenses WHERE is_corrupted = TRUE AND status <> 'rejected'
  `);
  return {
    queueByStage: queue.rows,
    corruptedOpen: corrupted.rows[0].n,
  };
}

async function buildReviewerPayload() {
  const ocr = await query(`
    SELECT COUNT(*)::int AS n FROM expenses WHERE status = 'ocr_extracted'
  `);
  const corrupted = await query(`
    SELECT COUNT(*)::int AS n FROM expenses WHERE is_corrupted = TRUE AND status <> 'rejected'
  `);
  return {
    ocrQueue: ocr.rows[0].n,
    corruptedOpen: corrupted.rows[0].n,
  };
}

async function buildHRPayload() {
  const users = await query(`
    SELECT
      COUNT(*)::int AS total,
      SUM(CASE WHEN is_active THEN 1 ELSE 0 END)::int AS active,
      SUM(CASE WHEN NOT is_active THEN 1 ELSE 0 END)::int AS inactive
    FROM users
  `);
  const departments = await query(`
    SELECT COUNT(*)::int AS n FROM perm.roles WHERE id LIKE 'dept-%' AND head_user_id IS NOT NULL
  `);
  const byRole = await query(`
    SELECT r.display_name AS role, COUNT(ur.user_id)::int AS n
    FROM perm.roles r
    LEFT JOIN perm.user_roles ur ON ur.role_id = r.id
    LEFT JOIN users u ON u.id = ur.user_id AND u.is_active
    WHERE r.id NOT LIKE 'user:dept:%'
      AND r.id IN (
        'ceo::1','cfo::2','admin::2','finance::2','sales_supervisor::2',
        'manager::3','hr_manager::3','accounting_manager::3','sales_rep::3',
        'supervisor::4','account_supervisor::4','it::2',
        'officer::5','hr::5','account_officer::5'
      )
    GROUP BY r.display_name
    ORDER BY r.display_name
  `);
  const recent = await query(`
    SELECT u.id, u.fullname, u.employee_code,
           (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
             WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
               AND up.revoked_at IS NULL
               AND (up.ends_at IS NULL OR up.ends_at > now())
             ORDER BY up.permission_id LIMIT 1) AS dept_id,
           (SELECT split_part(up.permission_id, ':', 3) FROM perm.user_permissions up
             WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
               AND up.revoked_at IS NULL
               AND (up.ends_at IS NULL OR up.ends_at > now())
             ORDER BY up.permission_id LIMIT 1) AS dept_group_name,
           split_part(r.role_id, '::', 1) AS role_name, u.created_at
    FROM users u
    LEFT JOIN LATERAL (
            SELECT ur.role_id FROM perm.user_roles ur
              WHERE ur.user_id = u.id
              ORDER BY (CASE WHEN ur.role_id LIKE '%::1' THEN 0
                             WHEN ur.role_id LIKE '%::2' THEN 1
                             WHEN ur.role_id LIKE '%::3' THEN 2
                             WHEN ur.role_id LIKE '%::4' THEN 3
                             WHEN ur.role_id LIKE '%::5' THEN 4
                             ELSE 5 END), ur.granted_at ASC
              LIMIT 1
          ) r ON true
    ORDER BY u.id DESC
    LIMIT 10
  `);
  const unassigned = await query(`
    SELECT 0::int AS n
  `);
  const deptless = await query(`
    SELECT COUNT(*)::int AS n FROM users u
      WHERE u.is_active = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM perm.user_permissions up
            WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
              AND up.revoked_at IS NULL
              AND (up.ends_at IS NULL OR up.ends_at > now())
        )
  `);
  return {
    users: users.rows[0],
    activeDepartments: departments.rows[0].n,
    byRole: byRole.rows,
    recent: recent.rows,
    unassigned: unassigned.rows[0].n,
    deptless: deptless.rows[0].n,
  };
}

async function buildFinancePayload() {
  const queue = await query(`
    SELECT status, COUNT(*)::int AS n
    FROM expenses
    WHERE status IN ('finance_review','approved','paid')
    GROUP BY status
  `);
  const recent = await query(`
    SELECT e.id, e.vendor_name, e.total_amount, e.status, e.updated_at,
           u.fullname AS submitter_name FROM expenses e
    JOIN users u ON e.submitter_id = u.id
    WHERE e.status IN ('finance_review','paid')
    ORDER BY e.updated_at DESC
    LIMIT 8
  `);
  const valuePending = await query(`
    SELECT COALESCE(SUM(total_amount), 0)::float AS v
    FROM expenses WHERE status = 'finance_review'
  `);
  const paidToday = await query(`
    SELECT COUNT(*)::int AS n, COALESCE(SUM(total_amount), 0)::float AS v
    FROM expenses
    WHERE status = 'paid' AND updated_at >= CURRENT_DATE
  `);
  return {
    queueByStage: queue.rows,
    recent: recent.rows,
    valuePending: valuePending.rows[0].v,
    paidTodayCount: paidToday.rows[0].n,
    paidTodayValue: paidToday.rows[0].v,
  };
}

async function buildStaffPayload(userId: number) {
  const byStatus = await query(`
    SELECT status, COUNT(*)::int AS n
    FROM expenses
    WHERE submitter_id = $1
    GROUP BY status
  `, [userId]);
  const totals = await query(`
    SELECT
      COUNT(*)::int AS total,
      COALESCE(SUM(total_amount), 0)::float AS lifetime_amount,
      COALESCE(SUM(CASE WHEN created_at >= DATE_TRUNC('month', CURRENT_DATE) THEN total_amount ELSE 0 END), 0)::float AS mtd_amount
    FROM expenses
    WHERE submitter_id = $1
  `, [userId]);
  return {
    byStatus: byStatus.rows,
    totals: totals.rows[0],
  };
}

export async function getDashboardForRole(actorId: number) {
  try {
    const r = await query<{
      id: number; fullname: string;
      role_name: string | null; permissions: string[];
      dept_perm: string | null;
    }>(
      `SELECT u.id, u.fullname,
              (SELECT split_part(ur.role_id, '::', 1) FROM perm.user_roles ur
                WHERE ur.user_id = u.id
                ORDER BY (CASE WHEN ur.role_id LIKE '%::1' THEN 0
                               WHEN ur.role_id LIKE '%::2' THEN 1
                               WHEN ur.role_id LIKE '%::3' THEN 2
                               WHEN ur.role_id LIKE '%::4' THEN 3
                               WHEN ur.role_id LIKE '%::5' THEN 4
                               ELSE 5 END), ur.granted_at ASC
                LIMIT 1) AS role_name,
              COALESCE((
                SELECT array_agg(DISTINCT p_id ORDER BY p_id)
                  FROM (
                    SELECT rp.permission_id AS p_id
                      FROM perm.user_roles ur
                      JOIN perm.role_permissions rp ON rp.role_id = ur.role_id
                     WHERE ur.user_id = u.id
                    UNION
                    SELECT permission_id AS p_id
                      FROM perm.user_permissions
                     WHERE user_id = u.id AND revoked_at IS NULL
                       AND (ends_at IS NULL OR ends_at > now())
                  ) t
              ), ARRAY[]::text[]) AS permissions,
              (SELECT up.permission_id FROM perm.user_permissions up
                WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
                  AND up.revoked_at IS NULL
                  AND (up.ends_at IS NULL OR up.ends_at > now())
                ORDER BY up.permission_id LIMIT 1) AS dept_perm
         FROM users u WHERE u.id = $1`,
      [actorId]
    );
    if (r.rows.length === 0) return { success: false, error: 'user not found' };
    const actor = r.rows[0];
    const role = (actor.role_name ?? 'staff').split('::')[0];
    const deptId = actor.dept_perm
      ? actor.dept_perm.replace(/^user:dept:/, '').replace(/::allow$/, '')
      : null;
    const kind =
      (actor.permissions ? await pickKindFromMatrix(null, actor.permissions) : null) ??
      pickKind(role);
    void deptId;
    if (!kind) return { success: false, error: `no dashboard view for role "${role}"` };

    const common = {
      actor: {
        id: actor.id,
        fullname: actor.fullname,
        department: actor.department,
        dept_group_id: actor.dept_group_id,
        dept_group_name: actor.dept_group_name,
        role,
      },
    };

    if (kind === 'it') return { success: true, kind, ...common, summary: await buildITPayload() };
    if (kind === 'exec') return { success: true, kind, ...common, summary: await buildExecPayload() };
    if (kind === 'hod') return {
      success: true,
      kind,
      ...common,
      summary: {
        ...(await buildHODPayload(actor.department || 'Unknown')),
        department: (actor as any).dept_id ?? actor.department,
        dept_group_id: (actor as any).dept_id ?? actor.department,
        dept_group_name: (actor as any).dept_id ?? actor.department,
      },
    };
    if (kind === 'am') return { success: true, kind, ...common, summary: await buildAMPayload() };
    if (kind === 'reviewer') return { success: true, kind, ...common, summary: await buildReviewerPayload() };
    if (kind === 'hr') return { success: true, kind, ...common, summary: await buildHRPayload() };
    if (kind === 'finance') return { success: true, kind, ...common, summary: await buildFinancePayload() };
    return { success: true, kind, ...common, summary: await buildStaffPayload(actor.id) };
  } catch (error: any) {
    console.error('Failed to build dashboard for role:', error);
    return { success: false, error: error.message };
  }
}

export async function listOrgTree(actorId: number) {
  try { await assertRole(actorId, [], { perm: 'tile:org_chart:view::allow' }); }
  catch { return { success: false as const, tree: [] }; }
  const tree: OrgNode[] = await loadOrgTree(actorId);
  return { success: true as const, tree };
}

export async function listDepartments(actorId: number) {
  try { await assertRole(actorId, [], { perm: 'tile:departments:view::allow' }); }
  catch { return { success: false as const, departments: [] }; }
  const r = await query(
    `SELECT DISTINCT split_part(id, ':', 3) AS id, split_part(id, ':', 3) AS name,
            NULL::text AS monthly_budget, NULL::int AS head_user_id,
            NULL::text AS head_fullname, NULL::text AS head_code,
            NULL::int AS active_members
       FROM perm.permissions
      WHERE id LIKE 'user:dept:%::allow'
      ORDER BY id`,
  );
  return { success: true as const, departments: r.rows };
}

export async function listUserDirectory(args: {
  actorId: number;
  filterRole?: string;
  filterDeptId?: number;
  includeInactive?: boolean;
}) {
  await assertRole(args.actorId, [], { perm: 'tile:directory:view::allow' });
  const scope = await resolveActorScope(args.actorId);
  if (!scope.isHrManager && !scope.isHr) {
    throw new Error('Permission denied');
  }

  const where: string[] = [];
  const params: any[] = [];
  if (args.filterRole) {
    params.push(args.filterRole);
    where.push(`r.role_name=$${params.length}`);
  }
  if (args.filterDeptId) {
    params.push(`user:dept:${args.filterDeptId}::allow`);
    where.push(`EXISTS (
      SELECT 1 FROM perm.user_permissions up
       WHERE up.user_id = u.id AND up.permission_id = $${params.length}
         AND up.revoked_at IS NULL
         AND (up.ends_at IS NULL OR up.ends_at > now())
    )`);
  }
  if (!args.includeInactive) where.push('u.is_active=TRUE');
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const r = await query(
    `SELECT u.id, u.employee_code, u.fullname, u.is_active,
            u.line_user_id, u.created_at, r.role_id, r.role_name,
            NULL AS dept_code, dg.dept_id, dg.dept_id AS dept_name,
            NULL AS manager_name, NULL AS manager_code
     FROM users u
     LEFT JOIN LATERAL (
            SELECT ur.role_id, split_part(ur.role_id, '::', 1) AS role_name FROM perm.user_roles ur
              WHERE ur.user_id = u.id
              ORDER BY (CASE WHEN ur.role_id LIKE '%::1' THEN 0
                             WHEN ur.role_id LIKE '%::2' THEN 1
                             WHEN ur.role_id LIKE '%::3' THEN 2
                             WHEN ur.role_id LIKE '%::4' THEN 3
                             WHEN ur.role_id LIKE '%::5' THEN 4
                             ELSE 5 END), ur.granted_at ASC
              LIMIT 1
          ) r ON true
     LEFT JOIN LATERAL (
       SELECT split_part(up.permission_id, ':', 3) AS dept_id FROM perm.user_permissions up
         WHERE up.user_id = u.id AND up.permission_id LIKE 'user:dept:%'
           AND up.revoked_at IS NULL
           AND (up.ends_at IS NULL OR up.ends_at > now())
         ORDER BY up.permission_id LIMIT 1
     ) dg ON true
     ${whereSql}
     ORDER BY u.id`,
    params
  );
  const levels = await getUserLevels();
  const staffLevels = await getUserStaffLevels();
  const users = r.rows.map((row: any) => ({
    ...row,
    level: levels.get(row.id) ?? 0,
    staff_level: staffLevels.get(row.id) ?? null,
  }));
  return { success: true as const, users };
}

export async function listRoleOptions(actorId: number) {
  await assertRole(actorId, [], { perm: 'tile:directory:view::allow' });
  const r = await query(`SELECT id, display_name AS name FROM perm.roles ORDER BY id`);
  return { success: true as const, roles: r.rows };
}

export async function listRecentNotifications(limit = 30) {
  const r = await query(
    `SELECT id, type, payload, severity, created_at
     FROM domain_events
     ORDER BY id DESC
     LIMIT $1`,
    [limit]
  );
  return r.rows.map((row: any) => {
    const payload = typeof row.payload === 'string' ? safeParse(row.payload) : (row.payload || {});
    return {
      id: String(row.id),
      type: row.type,
      message: payload?.message || row.type,
      actorId: null as number | null,
      actorName: null as string | null,
      refType: null as string | null,
      refId: null as number | null,
      severity: (row.severity || 'info') as 'info' | 'success' | 'warning' | 'error',
      severityClass: severityClass(row.severity),
      createdAt: typeof row.created_at === 'string' ? row.created_at : new Date(row.created_at).toISOString(),
    };
  });
}

export interface ListUserNotificationsOpts {
  includeCleared?: boolean;
  onlyUnread?: boolean;
}

export async function listUserNotifications(
  actorId: number,
  limit = 30,
  opts: ListUserNotificationsOpts = {},
) {
  const where: string[] = ['user_id = $1'];
  const params: any[] = [actorId];
  if (!opts.includeCleared) where.push('cleared_at IS NULL');
  if (opts.onlyUnread) where.push('read_at IS NULL');
  params.push(limit);

  const r = await query(
    `SELECT id, type, payload_json, target_type, target_id, read_at, cleared_at, created_at
     FROM notifications
     WHERE ${where.join(' AND ')}
     ORDER BY (read_at IS NULL) DESC, id DESC
     LIMIT $${params.length}`,
    params,
  );
  if (r.rows.length === 0) return [];

  return r.rows.map((row: any) => {
    const payload = typeof row.payload_json === 'string' ? safeParse(row.payload_json) : (row.payload_json || {});
    const actorIdFromPayload = (payload?.actorId as number | null) ?? null;
    const actorName = (payload?.actorName as string | null) ?? null;
    const severity = (payload?.severity as string | null) || 'info';
    return {
      id: String(row.id),
      type: row.type,
      message: payload?.message || row.type,
      actorId: actorIdFromPayload,
      actorName,
      refType: row.target_type as string | null,
      refId: row.target_id != null ? Number(row.target_id) : null,
      severity: severity as 'info' | 'success' | 'warning' | 'error',
      severityClass: severityClass(severity),
      readAt: row.read_at ? new Date(row.read_at).toISOString() : null,
      clearedAt: row.cleared_at ? new Date(row.cleared_at).toISOString() : null,
      createdAt: typeof row.created_at === 'string' ? row.created_at : new Date(row.created_at).toISOString(),
    };
  });
}

export async function listUnreadCount(actorId: number): Promise<number> {
  const r = await query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM notifications WHERE user_id = $1 AND read_at IS NULL AND cleared_at IS NULL`,
    [actorId]
  );
  return r.rows[0]?.n ?? 0;
}

export async function markUnreadForUser(actorId: number, ids: number[]): Promise<number> {
  if (ids.length === 0) return 0;
  const r = await query(
    `UPDATE notifications SET read_at = NULL
     WHERE user_id = $1 AND id = ANY($2::bigint[]) AND cleared_at IS NULL`,
    [actorId, ids]
  );
  return r.rowCount ?? 0;
}

export async function clearForUser(actorId: number, ids: number[], all: boolean): Promise<number> {
  if (all) {
    const r = await query(
      `UPDATE notifications SET cleared_at = NOW()
       WHERE user_id = $1 AND cleared_at IS NULL`,
      [actorId]
    );
    return r.rowCount ?? 0;
  }
  if (ids.length === 0) return 0;
  const r = await query(
    `UPDATE notifications SET cleared_at = NOW()
     WHERE user_id = $1 AND id = ANY($2::bigint[]) AND cleared_at IS NULL`,
    [actorId, ids]
  );
  return r.rowCount ?? 0;
}

export async function toggleReadForUser(actorId: number, id: number): Promise<{ id: number; readAt: string | null } | null> {
  const r = await query<{ id: number; read_at: string | null }>(
    `UPDATE notifications
     SET read_at = CASE WHEN read_at IS NULL THEN NOW() ELSE NULL END
     WHERE user_id = $1 AND id = $2 AND cleared_at IS NULL
     RETURNING id, read_at`,
    [actorId, id]
  );
  if (r.rows.length === 0) return null;
  return {
    id: Number(r.rows[0].id),
    readAt: r.rows[0].read_at ? new Date(r.rows[0].read_at).toISOString() : null,
  };
}

function safeParse(s: string): any {
  try { return JSON.parse(s); } catch { return {}; }
}

function severityClass(sev: string | null | undefined): string {
  switch (sev) {
    case 'success': return 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30';
    case 'warning': return 'bg-amber-500/15 text-amber-300 border-amber-500/30';
    case 'error':   return 'bg-rose-500/15 text-rose-300 border-rose-500/30';
    default:        return 'bg-slate-500/15 text-slate-300 border-slate-500/30';
  }
}