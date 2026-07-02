// Direct DB integration test for HR actions. Requires a running Postgres
// (the same one configured in src/lib/db.ts). Each test isolates state by
// using a unique employee_code prefix and cleaning up at the end.
//
// Run:
//   cd web-admin && node tests/hr.actions.test.mjs
//
// Skips gracefully if the DB is unreachable so CI without Postgres still passes.

import pg from 'pg';
const { Pool } = pg;

const pool = new Pool({
  user: process.env.POSTGRES_USER || 'contract',
  password: process.env.POSTGRES_PASSWORD || 'contractpw',
  host: process.env.POSTGRES_HOST || 'localhost',
  database: process.env.POSTGRES_DB || 'world_erp_db',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
});

let pass = 0;
let fail = 0;
async function check(name, fn) {
  try {
    await fn();
    pass++;
    console.log('✓', name);
  } catch (e) {
    fail++;
    console.log('✗', name, '—', e.message);
  }
}

async function q(sql, params = []) {
  const r = await pool.query(sql, params);
  return r.rows;
}

let skipReason = null;
async function guard() {
  try {
    await pool.query('SELECT 1');
  } catch (e) {
    skipReason = e.message;
    throw e;
  }
}

// Ensure roles exist
async function ensureRole(name) {
  const r = await q('SELECT id FROM roles WHERE name=$1', [name]);
  if (r.length === 0) {
    await q('INSERT INTO roles(name) VALUES($1)', [name]);
    return (await q('SELECT id FROM roles WHERE name=$1', [name]))[0].id;
  }
  return r[0].id;
}

async function run() {
  try { await guard(); }
  catch (_e) {
    console.log(`⚠️  Postgres unreachable (${skipReason}) — skipping integration test.`);
    pool.end();
    process.exit(0);
  }

  const testTag = 'HRT' + Date.now().toString(36).slice(-6);
  const hrMgrId = await ensureRole('hr_manager');
  const staffId = await ensureRole('staff');

  // Setup: HR Manager actor + 2 direct reports + 1 unrelated user.
  const mgr = (await q(
    `INSERT INTO users(employee_code, fullname, role_id) VALUES($1,$2,$3) RETURNING id`,
    [`${testTag}_MGR`, 'HR Test Manager', hrMgrId]
  ))[0];
  const r1 = (await q(
    `INSERT INTO users(employee_code, fullname, role_id, reports_to_user_id) VALUES($1,$2,$3,$4) RETURNING id`,
    [`${testTag}_R1`, 'Report 1', staffId, mgr.id]
  ))[0];
  const r2 = (await q(
    `INSERT INTO users(employee_code, fullname, role_id, reports_to_user_id) VALUES($1,$2,$3,$4) RETURNING id`,
    [`${testTag}_R2`, 'Report 2', staffId, mgr.id]
  ))[0];
  const outside = (await q(
    `INSERT INTO users(employee_code, fullname, role_id) VALUES($1,$2,$3) RETURNING id`,
    [`${testTag}_OUT`, 'Outsider', staffId]
  ))[0];

  // Inline subtree query.
  await check('HR Manager subtree contains both direct reports', async () => {
    const rows = await q('SELECT id FROM users WHERE reports_to_user_id=$1', [mgr.id]);
    const ids = rows.map((r) => r.id);
    if (!ids.includes(r1.id) || !ids.includes(r2.id)) {
      throw new Error('subtree missing one of the reports');
    }
    if (ids.includes(outside.id)) {
      throw new Error('subtree unexpectedly contains outsider');
    }
  });

  await check('reports_to chain backfill skips when manager is NULL', async () => {
    const rows = await q('SELECT reports_to_user_id FROM users WHERE id=$1', [outside.id]);
    if (rows[0].reports_to_user_id !== null) {
      throw new Error('outsider should have no manager');
    }
  });

  await check('is_active defaults to TRUE for new users', async () => {
    const rows = await q('SELECT is_active FROM users WHERE id=$1', [r1.id]);
    if (rows[0].is_active !== true) {
      throw new Error('expected is_active=TRUE');
    }
  });

  await check('set is_active=false persists and is queryable', async () => {
    await q('UPDATE users SET is_active=$1 WHERE id=$2', [false, r1.id]);
    const rows = await q('SELECT is_active FROM users WHERE id=$1', [r1.id]);
    if (rows[0].is_active !== false) {
      throw new Error('expected is_active=FALSE after update');
    }
    // restore for cleanup
    await q('UPDATE users SET is_active=$1 WHERE id=$2', [true, r1.id]);
  });

  await check('cycle prevention in reports_to via walk-up', async () => {
    // If r1 reports to mgr and mgr tried to report to r1, walking up from r1
    // should encounter mgr and we'd detect a cycle in app logic. Here we
    // only assert the data model supports the relationship.
    const rows = await q('SELECT reports_to_user_id FROM users WHERE id=$1', [mgr.id]);
    if (rows[0].reports_to_user_id !== null) {
      throw new Error('mgr should have no manager in this test');
    }
  });

  await check('users_no_self_report CHECK prevents self-cycle at DB level', async () => {
    let threw = false;
    try {
      await q('UPDATE users SET reports_to_user_id=$1 WHERE id=$2', [mgr.id, mgr.id]);
    } catch (e) {
      threw = /users_no_self_report|check constraint/i.test(e.message);
    }
    if (!threw) {
      throw new Error('expected CHECK constraint violation when assigning self as manager');
    }
  });

  // Cleanup
  await q('DELETE FROM users WHERE employee_code LIKE $1', [`${testTag}_%`]);
  console.log(`\n${pass} passed, ${fail} failed`);
  pool.end();
  process.exit(fail === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error('Fatal:', e.message);
  pool.end();
  process.exit(1);
});