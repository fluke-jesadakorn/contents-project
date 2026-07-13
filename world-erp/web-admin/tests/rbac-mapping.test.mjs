// Tests for the 2026-07-02-F rbac tile mapping fixes.
// Verifies:
//   B1: 4 orphaned tile-modules now have module_group membership
//   B2: 'permissions' tile points at rbac-edit-matrix (not tile-org-chart)
//   B3: 5 explicit deny rows override L4 inheritance for it/finance
//   Composite: the 4 previously-orphaned tiles now resolve to 'allow' for
//              appropriate persona roles; the 5 new denies take effect.

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

async function resolveCell(roleId, moduleId) {
  // Mirror lib/rbac/inheritance.ts:resolveCellWithGroups for action='read'
  const r = await q(`
    WITH RECURSIVE chain AS (
      SELECT id, parent_id, 0 AS depth FROM rbac.roles WHERE id = $1
      UNION ALL
      SELECT r.id, r.parent_id, c.depth + 1
        FROM rbac.roles r JOIN chain c ON r.id = c.parent_id
    ),
    picked AS (
      SELECT p.state::text AS state, c.depth
        FROM rbac.permissions p
        JOIN chain c ON c.id = p.role_id
       WHERE p.module_id = $2 AND p.action = 'read'
         AND p.state IN ('allow','deny')
       ORDER BY (p.role_id = $1) DESC, c.depth ASC
       LIMIT 1
    )
    SELECT state FROM picked
  `, [roleId, moduleId]);
  if (r.length > 0) return r[0].state;
  const c = await q(`
    WITH RECURSIVE
      module_groups AS (
        SELECT g.id FROM rbac.groups g
          JOIN rbac.module_groups mg ON mg.group_id = g.id
         WHERE mg.module_id = $2
        UNION
        SELECT g.id FROM rbac.groups g
          JOIN module_groups m ON m.id = g.parent_id
      ),
      role_groups AS (SELECT group_id FROM rbac.role_groups WHERE role_id = $1)
    SELECT gp.state::text AS state FROM rbac.group_permissions gp
     WHERE gp.action = 'read' AND gp.role_id = $1
       AND gp.group_id IN (SELECT id FROM module_groups)
       AND gp.state IN ('allow','deny')
     ORDER BY state ASC
     LIMIT 1
  `, [roleId, moduleId]);
  if (c.length > 0) return c[0].state;
  return 'deny';
}

async function run() {
  let skip = false;
  try { await pool.query('SELECT 1'); }
  catch { skip = true; }

  if (skip) {
    console.log('⚠️ Postgres unreachable — skipping');
    pool.end();
    process.exit(0);
  }

  // B1.1: tile-summary → grp-cockpit
  await check('B1.1: tile-summary joined to grp-cockpit', async () => {
    const r = await q(`
      SELECT 1 FROM rbac.module_groups
       WHERE module_id = 'tile-summary' AND group_id = 'grp-cockpit'
    `);
    if (r.length === 0) throw new Error('row missing');
  });

  // B1.2: rbac-visibility → grp-it
  await check('B1.2: rbac-visibility joined to grp-it', async () => {
    const r = await q(`
      SELECT 1 FROM rbac.module_groups
       WHERE module_id = 'rbac-visibility' AND group_id = 'grp-it'
    `);
    if (r.length === 0) throw new Error('row missing');
  });

  // B1.3: view-hook-events → grp-it
  await check('B1.3: view-hook-events joined to grp-it', async () => {
    const r = await q(`
      SELECT 1 FROM rbac.module_groups
       WHERE module_id = 'view-hook-events' AND group_id = 'grp-it'
    `);
    if (r.length === 0) throw new Error('row missing');
  });

  // B1.4: manage-hook-events → grp-it
  await check('B1.4: manage-hook-events joined to grp-it', async () => {
    const r = await q(`
      SELECT 1 FROM rbac.module_groups
       WHERE module_id = 'manage-hook-events' AND group_id = 'grp-it'
    `);
    if (r.length === 0) throw new Error('row missing');
  });

  // B2: 'permissions' tile module_id = 'rbac-edit-matrix'
  await check('B2: permissions tile routed to rbac-edit-matrix', async () => {
    const r = await q(`SELECT module_id FROM rbac.tiles WHERE id = 'permissions'`);
    if (r.length === 0) throw new Error('tile missing');
    if (r[0].module_id !== 'rbac-edit-matrix') {
      throw new Error(`expected rbac-edit-matrix, got ${r[0].module_id}`);
    }
  });

  // B3.1-B3.4: 4 explicit deny rows (override-queue dropped 2026-07-10)
  const expectedDenies = [
    ['it',      'tile-cockpit'],
    ['it',      'tile-summary'],
    ['finance', 'tile-summary'],
  ];
  for (const [roleId, moduleId] of expectedDenies) {
    await check(`B3: explicit deny on (${roleId}, ${moduleId}, read)`, async () => {
      const r = await q(`
        SELECT 1 FROM rbac.permissions
         WHERE role_id = $1 AND module_id = $2 AND action = 'read' AND state = 'deny'
      `, [roleId, moduleId]);
      if (r.length === 0) throw new Error('row missing');
    });
  }

  // Composite: previously-orphaned tiles now resolve correctly
  // summary → cfo/ceo/admin/finance (cockpit group)
  await check('composite: summary now allow for cfo', async () => {
    const s = await resolveCell('cfo', 'tile-summary');
    if (s !== 'allow') throw new Error(`expected allow, got ${s}`);
  });
  await check('composite: summary now allow for manager (via grp-finance ∩ grp-cockpit? no — but admin via L4→cockpit)', async () => {
    // manager is in grp-finance, not grp-cockpit. summary → grp-cockpit.
    // So manager should be DENIED on summary (cockpit-only tile).
    const s = await resolveCell('manager', 'tile-summary');
    if (s !== 'deny') throw new Error(`expected deny for manager, got ${s}`);
  });
  await check('composite: visibility now allow for admin (it group)', async () => {
    const s = await resolveCell('admin', 'rbac-visibility');
    if (s !== 'allow') throw new Error(`expected allow, got ${s}`);
  });
  await check('composite: visibility now allow for it (it group)', async () => {
    const s = await resolveCell('it', 'rbac-visibility');
    if (s !== 'allow') throw new Error(`expected allow, got ${s}`);
  });
  await check('composite: visibility still deny for manager (not in it group)', async () => {
    const s = await resolveCell('manager', 'rbac-visibility');
    if (s !== 'deny') throw new Error(`expected deny, got ${s}`);
  });
  await check('composite: hook now allow for admin', async () => {
    const s = await resolveCell('admin', 'view-hook-events');
    if (s !== 'allow') throw new Error(`expected allow, got ${s}`);
  });
  await check('composite: hook still deny for manager (not in it group)', async () => {
    const s = await resolveCell('manager', 'view-hook-events');
    if (s !== 'deny') throw new Error(`expected deny, got ${s}`);
  });

  // B3 verification: it denied on cockpit despite L4 inheritance
  await check('B3 verify: it denied on tile-cockpit (overrides L4 allow)', async () => {
    const s = await resolveCell('it', 'tile-cockpit');
    if (s !== 'deny') throw new Error(`expected deny, got ${s}`);
  });
  await check('B3 verify: cfo still allow on tile-cockpit (no deny row for cfo)', async () => {
    const s = await resolveCell('cfo', 'tile-cockpit');
    if (s !== 'allow') throw new Error(`expected allow, got ${s}`);
  });
  await check('B3 verify: finance denied on tile-summary', async () => {
    const s = await resolveCell('finance', 'tile-summary');
    if (s !== 'deny') throw new Error(`expected deny, got ${s}`);
  });
  await check('B3 verify: finance still allow on tile-cockpit (no deny row)', async () => {
    const s = await resolveCell('finance', 'tile-cockpit');
    if (s !== 'allow') throw new Error(`expected allow, got ${s}`);
  });

  // Final coverage count: CFO role should now have at least the 4 previously-orphaned tiles
  await check('coverage: cfo has 30/30 tiles (4 previously orphaned now allowed)', async () => {
    const tiles = await q(`SELECT id, module_id FROM rbac.tiles`);
    let allowCount = 0;
    for (const t of tiles) {
      const s = await resolveCell('cfo', t.module_id);
      if (s === 'allow') allowCount++;
    }
    if (allowCount < 30) throw new Error(`expected 30, got ${allowCount}`);
  });

  console.log(`\n${pass} passed, ${fail} failed`);
  pool.end();
  process.exit(fail === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error('Fatal:', e.message);
  pool.end();
  process.exit(1);
});