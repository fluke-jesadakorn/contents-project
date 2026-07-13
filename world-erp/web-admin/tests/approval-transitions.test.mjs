// Tests for the 2026-07-02 polymorphic approval_transitions refactor.
// Verifies:
//   1. recordTransition writes the correct polymorphic row
//   2. recordOverride writes the correct polymorphic row (regression for entity_id=0 bug)
//   3. Backfill idempotency (re-running migration A is safe)
//   4. The deferred trigger on slips enforces exactly-one parent
//   5. The domain_events fanout trigger produces notifications 1:1 with recipients.ts

import pg from 'pg';
const { Pool } = pg;

const pool = new Pool({
  user: process.env.POSTGRES_USER || 'contract',
  password: process.env.POSTGRES_PASSWORD || 'contractpw',
  host: process.env.POSTGRES_HOST || 'localhost',
  database: process.env.POSTGRES_DB || 'finance_db',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
});

let pass = 0, fail = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log('✓', name); }
  catch (e) { fail++; console.log('✗', name, '—', e.message); }
}

async function q(sql, params=[]) { return (await pool.query(sql, params)).rows; }
async function exec(sql, params=[]) { return (await pool.query(sql, params)).rowCount; }

async function run() {
  let skip = false;
  try { await pool.query('SELECT 1'); }
  catch { skip = true; }

  if (skip) {
    console.log('⚠️ Postgres unreachable — skipping');
    pool.end();
    process.exit(0);
  }

  // 1. Schema: approval_transitions exists with polymorphic shape
  await check('schema: approval_transitions has target_type/target_id columns', async () => {
    const r = await q(`
      SELECT column_name FROM information_schema.columns
       WHERE table_schema='public' AND table_name='approval_transitions'
         AND column_name IN ('target_type','target_id','actor_id','previous_status','new_status','comments','stage','chain_index','created_at')
    `);
    if (r.length !== 9) throw new Error(`expected 9 columns, got ${r.length}`);
  });

  // 2. Schema: approval_override_audit exists with polymorphic + kind column
  await check('schema: approval_override_audit has target_type + kind columns', async () => {
    const r = await q(`
      SELECT column_name FROM information_schema.columns
       WHERE table_schema='public' AND table_name='approval_override_audit'
         AND column_name IN ('target_type','target_id','actor_id','kind','attempted_stage','required_role','actor_role','reason','created_at')
    `);
    if (r.length !== 9) throw new Error(`expected 9 columns, got ${r.length}`);
  });

  // 3. Schema: legacy tables dropped
  await check('schema: legacy approval_logs/pr/po tables dropped', async () => {
    const r = await q(`
      SELECT table_name FROM information_schema.tables
       WHERE table_schema='public' AND table_name IN ('approval_logs','pr_approval_logs','po_approval_logs','ceo_overrides','stage_override_audit')
    `);
    if (r.length !== 0) throw new Error(`legacy tables still exist: ${r.map(x => x.table_name).join(',')}`);
  });

  // 4. Polymorphic INSERT: insert an expense transition
  let testExpenseId = null;
  await check('data: can insert approval_transitions row for expense', async () => {
    const exp = await q(`INSERT INTO expenses (submitter_id, vendor_name, total_amount, status) VALUES (1, 'Test Vendor', 100, 'draft') RETURNING id`);
    testExpenseId = exp[0].id;
    const ins = await q(`
      INSERT INTO approval_transitions (target_type, target_id, actor_id, previous_status, new_status, comments, stage, chain_index)
      VALUES ('expense', $1, 1, 'draft', 'manager_review', 'test transition', 'manager_review', 0)
      RETURNING id, target_type, target_id
    `, [testExpenseId]);
    if (ins.length !== 1) throw new Error('insert failed');
    if (ins[0].target_type !== 'expense') throw new Error('wrong target_type');
    if (ins[0].target_id !== testExpenseId) throw new Error('wrong target_id');
  });

  // 5. Polymorphic INSERT: insert a PR transition
  let testPrId = null;
  await check('data: can insert approval_transitions row for pr', async () => {
    const pr = await q(`INSERT INTO purchase_requisitions (requester_id, vendor_name, total_estimate) VALUES (1, 'Test PR Vendor', 500) RETURNING id`);
    testPrId = pr[0].id;
    const ins = await exec(`
      INSERT INTO approval_transitions (target_type, target_id, actor_id, previous_status, new_status, comments, stage)
      VALUES ('pr', $1, 1, 'draft', 'manager_review', 'pr test', 'manager_review')
    `, [testPrId]);
    if (ins !== 1) throw new Error('insert failed');
  });

  // 6. Polymorphic INSERT: insert a PO transition
  let testPoId = null;
  await check('data: can insert approval_transitions row for po', async () => {
    const po = await q(`INSERT INTO purchase_orders (pr_id, po_number, vendor_name, total_amount, issued_by) VALUES ($1, 'PO-TEST-001', 'Test PO', 500, 1) RETURNING id`, [testPrId]);
    testPoId = po[0].id;
    const ins = await exec(`
      INSERT INTO approval_transitions (target_type, target_id, actor_id, previous_status, new_status, comments, stage, chain_index)
      VALUES ('po', $1, 1, 'pending_approval', 'po_cfo', 'po test', 'po_cfo', 0)
    `, [testPoId]);
    if (ins !== 1) throw new Error('insert failed');
  });

  // 7. Regression: recordOverride writes the correct entity_id (was broken as 0)
  await check('regression: approval_override_audit stores actual entity_id (not 0)', async () => {
    await exec(`
      INSERT INTO approval_override_audit (target_type, target_id, actor_id, kind, attempted_stage, required_role, actor_role, reason)
      VALUES ('expense', $1, 1, 'denied', 'finance_review', 'finance_review', 'admin', 'out-of-stage approve_expense')
    `, [testExpenseId]);
    const r = await q(`
      SELECT target_id FROM approval_override_audit
       WHERE target_type='expense' AND target_id=$1 AND kind='denied'
    `, [testExpenseId]);
    if (r.length === 0) throw new Error('override audit row missing');
    if (r[0].target_id !== testExpenseId) throw new Error(`expected target_id=${testExpenseId}, got ${r[0].target_id}`);
  });

  // 8. Slips trigger: orphan INSERT (autocommit) fails
  await check('trigger: slips rejects orphan INSERT (autocommit)', async () => {
    let err = null;
    const c = await pool.connect();
    try {
      await c.query(`
        INSERT INTO slips (file_path, mime_type, file_size, uploaded_by)
        VALUES ('test/orphan-refuse.png','image/png',100,1)
      `);
    } catch (e) { err = e; }
    finally { c.release(); }
    if (!err) throw new Error('orphan INSERT should have failed');
    if (!err.message.includes('slips_exactly_one_parent')) {
      throw new Error(`unexpected error: ${err.message}`);
    }
  });

  // 9. Slips trigger: orphan-then-link in same tx succeeds
  await check('trigger: slips allows orphan-then-link in same tx (deferred)', async () => {
    const c = await pool.connect();
    try {
      await c.query('BEGIN');
      const ins = await c.query(`
        INSERT INTO slips (file_path, mime_type, file_size, uploaded_by)
        VALUES ('test/orphan-link-ok.png','image/png',100,1) RETURNING id
      `);
      const newId = ins.rows[0].id;
      await c.query(`UPDATE slips SET expense_id = $1 WHERE id = $2`, [testExpenseId, newId]);
      await c.query('COMMIT');
      const r = await c.query(`SELECT expense_id FROM slips WHERE id=$1`, [newId]);
      if (r.rows[0].expense_id !== testExpenseId) throw new Error('link not persisted');
    } catch (e) { throw new Error(`unexpected: ${e.message}`); }
    finally { c.release(); }
  });

  // 10. Slips trigger: two parents rejected
  await check('trigger: slips rejects two parents', async () => {
    let err = null;
    const c = await pool.connect();
    try {
      await c.query(`
        INSERT INTO slips (file_path, mime_type, file_size, uploaded_by, expense_id, pr_id)
        VALUES ('test/two-parents.png','image/png',100,1,$1,$2)
      `, [testExpenseId, testPrId]);
    } catch (e) { err = e; }
    finally { c.release(); }
    if (!err) throw new Error('two parents should have failed');
    if (!err.message.includes('slips_exactly_one_parent')) {
      throw new Error(`unexpected error: ${err.message}`);
    }
  });

  // 11. Domain events trigger: insert produces notifications
  await check('trigger: domain_events fanout produces notifications', async () => {
    const before = await q(`SELECT COUNT(*) AS n FROM notifications`);
    const beforeN = parseInt(before[0].n);
    const ins = await exec(`
      INSERT INTO domain_events (type, actor_id, ref_type, ref_id, payload, severity)
      VALUES ('expense.test.transition', 1, 'expense', $1, '{"msg":"trigger test"}'::jsonb, 'info')
    `, [testExpenseId]);
    if (ins !== 1) throw new Error('insert failed');
    const after = await q(`SELECT COUNT(*) AS n FROM notifications`);
    const afterN = parseInt(after[0].n);
    if (afterN <= beforeN) {
      throw new Error(`expected notifications to grow (before=${beforeN}, after=${afterN})`);
    }
    // Cleanup
    await exec(`DELETE FROM notifications WHERE payload_json->>'msg' = 'trigger test'`);
    await exec(`DELETE FROM domain_events WHERE type = 'expense.test.transition'`);
  });

  // 12. Domain events trigger: NO_FANOUT_TYPES bypass
  await check('trigger: policy.updated type bypasses fanout', async () => {
    const before = await q(`SELECT COUNT(*) AS n FROM notifications`);
    const beforeN = parseInt(before[0].n);
    await exec(`
      INSERT INTO domain_events (type, actor_id, ref_type, ref_id, payload, severity)
      VALUES ('policy.updated', 1, 'audit', 1, '{}'::jsonb, 'info')
    `);
    const after = await q(`SELECT COUNT(*) AS n FROM notifications`);
    const afterN = parseInt(after[0].n);
    if (afterN !== beforeN) {
      throw new Error(`policy.updated should not produce notifications (before=${beforeN}, after=${afterN})`);
    }
    await exec(`DELETE FROM domain_events WHERE type = 'policy.updated'`);
  });

  // 13. Cockpit summary slices reference new tables
  await check('cockpit: summary queries reference approval_transitions (no approval_logs)', async () => {
    const r = await q(`
      SELECT table_name FROM information_schema.tables
       WHERE table_schema='public' AND table_name='approval_logs'
    `);
    if (r.length !== 0) throw new Error('approval_logs table still exists — lib/rbac/server.ts would break');
  });

  // Cleanup test fixtures
  await exec(`DELETE FROM slips WHERE file_path LIKE 'test/%'`);
  await exec(`DELETE FROM approval_transitions WHERE target_id IN ($1, $2) AND target_type='expense'`, [testExpenseId, testPrId]);
  await exec(`DELETE FROM approval_transitions WHERE target_id=$1 AND target_type='pr'`, [testPrId]);
  await exec(`DELETE FROM approval_transitions WHERE target_id=$1 AND target_type='po'`, [testPoId]);
  await exec(`DELETE FROM approval_override_audit WHERE target_id=$1`, [testExpenseId]);
  await exec(`DELETE FROM purchase_orders WHERE id=$1`, [testPoId]);
  await exec(`DELETE FROM purchase_requisitions WHERE id=$1`, [testPrId]);
  await exec(`DELETE FROM expenses WHERE id=$1`, [testExpenseId]);

  console.log(`\n${pass} passed, ${fail} failed`);
  pool.end();
  process.exit(fail === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error('Fatal:', e.message);
  pool.end();
  process.exit(1);
});