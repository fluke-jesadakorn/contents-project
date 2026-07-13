# AGENTS.md

Multi-project workspace under `/Users/fluke/Desktop/Work/Contents/`. Sub-project rules live as sections here — read the relevant section before working in that project.

## Sub-projects

- `Law-digitalize-PoC/` — Law RAG LINE bot (host-native n8n + MinIO + Postgres)
- `hr-line-agent/` — HR LINE bot + Next.js admin
- `world-erp/` — AI Financial System (Next.js admin + OCR service)
- `finance-line-agent/` — Finance LINE agent (scaffold)
- `smarthome-line-agent/` — Smarthome LINE agent (bash runtime)
- `ai-realtime-translate/` — Desktop realtime translator (Rust + Dioxus + Python)
- `infra/` — Shared host-native services (n8n, MinIO, Postgres, launchd plists)

## Workspace rules

### Package manager

Use **bun** for all Node.js / Next.js projects. `bun install` — never `npm install` / `npm ci`. Lockfile is `bun.lock` (commit it; same role as old `package-lock.json`).

### Verification — lint only

For verification use static checks only — **never** `build` / `start` / `cargo build` / `cargo run`. Verification commands:

| Project type | Verify with |
|---|---|
| Node / Next.js | `bun run lint` + `bunx tsc --noEmit` |
| Rust | `cargo check` + `cargo clippy` + `cargo fmt --check` |
| Python | `ruff check` + `ruff format --check` (if installed) |
| SQL / n8n / config edits | `psql` / `curl` against the already-running services only |

### Development — `bun dev` allowed

`bun run dev` is fine when actively developing. Run in background (`bun run dev > /tmp/<project>.dev.log 2>&1 &`) so it doesn't block the session. Check `tail -f /tmp/<project>.dev.log` for output.

Forbidden: `next build`, `npm run dev`, `cargo build`, `cargo run`, anything else that opens a port for the purpose of *verifying* a change.

### Post-task dev server (Next.js) — always start

After **every** task that touched a Next.js project, start `bun run dev` in the background so it's ready when the user opens the page. This is the final step of the task — same priority as lint/typecheck, not optional.

Ports & logs:

| Project | Path | Port | Log |
|---|---|---|---|
| `hr-line-agent` | `hr-line-agent/web-admin` | 3002 | `/tmp/hr-line-agent.dev.log` |
| `world-erp` | `world-erp/web-admin` | 3003 | `/tmp/world-erp.dev.log` |

Steps per affected project:

1. Check if already up: `lsof -ti:<port>`. If a PID returns, skip — don't restart.
2. If not running, clean cache: `rm -rf <project>/web-admin/.next`.
3. Start in background: `cd <project>/web-admin && bun run dev > /tmp/<project>.dev.log 2>&1 &`
4. Confirm boot: `tail -n 50 /tmp/<project>.dev.log` — look for "Ready in" and no stack traces.
5. Report the local URL to the user (e.g. `http://localhost:3002`).

Skip only if no Next.js code was touched in the task.

## Law-digitalize-PoC

LINE bot PoC: รับสัญญา (PDF/DOCX) จาก LINE → chunk + embed → เก็บใน Postgres+pgvector → RAG Q&A + admin CRUD UI. Orchestration ทั้งหมดอยู่ใน n8n (host-native, ไม่ใช้ docker แล้ว); embedding ผ่าน Ollama bge-m3; chat agent ผ่าน Ollama qwen3.6:35b-a3b-q4_K_M (OpenRouter เก็บไว้ใน env สำหรับ archived flows เท่านั้น).

### Setup commands

- Start stack:        อัตโนมัติตอน boot ผ่าน launchd (`com.lawpoc.n8n`, `com.lawpoc.minio`)
- Verify stack:       `launchctl list | grep lawpoc && curl http://localhost:5678/healthz && curl -I http://localhost:9000/minio/health/live`
- Open n8n:           `https://n8n.jesadakorn.com` (Cloudflare tunnel)
- Restart n8n:        `launchctl kickstart -k gui/$(id -u)/com.lawpoc.n8n`
- Restart minio:      `launchctl kickstart -k gui/$(id -u)/com.lawpoc.minio`
- View n8n log:       `tail -f /Users/fluke/Desktop/Work/Contents/infra/logs/n8n.log`
- DB schema:          `psql -h localhost -U contract -d contracts -f db/init.sql`
- Edit n8n env:       `vi /Users/fluke/Desktop/Work/Contents/infra/.env` แล้ว restart n8n
- n8n REST API:       `N8N_API_KEY` อยู่ใน `infra/.env` (file mode 600) — ใช้ `curl -H "X-N8N-API-KEY: $(grep ^N8N_API_KEY= infra/.env | cut -d= -f2-)" http://localhost:5678/api/v1/...` สำหรับ programmatic flow/execution/credential access. ดู `n8n/API-PATTERNS.md` (ถ้ามี) สำหรับ snippet ที่ใช้บ่อย

### Project layout

- `db/init.sql` — schema: `contracts`, `contract_chunks` (vector(1024) for bge-m3), `next_doc_seq()` + `touch_updated_at()` trigger (ivfflat index commented out — uncomment after >100 rows)
- `n8n/flows/` — exported workflow JSON. Active: `03-docs-hub.json`, `04-docs-admin.json`. Archived (host-native migration leftovers): `archive/01-*.json`, `archive/02-*.json`
- `n8n/credentials.md`, `n8n/flows/CREDENTIAL-AUDIT.md` — credential IDs, flow wiring reference
- `docs/LINE-SETUP.md`, `docs/N8N-SETUP.md` — operator runbooks for LINE channel + n8n env
- `../infra/` — shared host-native infra (n8n runtime, MinIO, logs, launchd plists, backups). `infra/.env` มี `N8N_API_KEY` (full access n8n REST API) — ใช้แทน direct SQL write เวลาแก้ flow

### Infra layout (`/Users/fluke/Desktop/Work/Contents/infra/`)

- `.env` — n8n + minio runtime env (DB, LINE, OpenRouter, Ollama)
- `n8n-data/.n8n/config` — n8n encryptionKey (sensitive — อย่า commit)
- `minio-data/` — MinIO data dir (bucket: `epsx-contracts`)
- `logs/n8n.log`, `logs/minio.log` — runtime logs (stdout+stderr)
- `launchd/com.lawpoc.n8n.plist`, `launchd/com.lawpoc.minio.plist` — launchd agents (symlinked to `~/Library/LaunchAgents/`)
- `scripts/start-n8n.js` — launchd entrypoint (loads .env, exec n8n start)
- `scripts/start-n8n.sh` — manual run alternative (bash version)
- `backups/migration-YYYYMMDD/` — migration snapshots (n8n.sql, contracts-schema.sql, creds.json, flows.zip, n8n-config.json)

### Services

| Service | Binary | Port | launchd Label | Notes |
|---|---|---|---|---|
| n8n | `/Users/fluke/.nvm/versions/node/v22.23.0/bin/n8n` | 5678 | `com.lawpoc.n8n` | node 22 (nvm) ไม่ใช่ system node |
| MinIO | `/opt/homebrew/bin/minio` | 9000 (api) / 9001 (console) | `com.lawpoc.minio` | data at `infra/minio-data/` |
| Postgres | `/opt/homebrew/opt/postgresql@18/bin/postgres` | 5432 | `homebrew.mxcl.postgresql@18` | DBs: `contracts` (owner: contract), `lawpoc_n8n` (owner: n8n_user), `finance_db` (owner: contract) |
| Ollama | `/opt/homebrew/bin/ollama` | 11434 | (manual / brew services) | bge-m3, qwen3-vl:4b, qwen2.5:7b |
| cloudflared | `/opt/homebrew/bin/cloudflared` | — | (manual) | tunnel `b8f4ccf5-67de-4bfa-b292-7641ad185006`, ingress: n8n.jesadakorn.com → localhost:5678, ai.jesadakorn.com → localhost:11434 |

### Code style

- **n8n flow edits**: ใช้ **n8n REST API** ผ่าน `N8N_API_KEY` ไม่ใช่ direct SQL เขียน `workflow_entity.nodes/connections`. SQL write ข้าม n8n's version management และเคยทำให้ `activeVersionId` ไม่ตรงกับ `versionId` (UI แสดง flow เก่าทั้งที่ DB อัพเดตแล้ว). Pattern: edit `n8n/flows/<name>.json` ใน local → POST/PUT ผ่าน API → restart n8n
- **n8n flows**: prefix node names with the subsystem (`LINE:`, `AI:`, `PG:`, `LLM:`); Code node JS uses `asyncCode: true`; SQL built dynamically uses dollar-quoting `$tag$...$tag$` for content + `'...'` escape for identifiers
- **SQL**: parameters via Postgres node's `queryReplacement` array, NOT f-string interpolation; always escape single quotes in dynamic content
- **Commits**: conventional (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`); body explains WHY not WHAT
- **Don't add** to AGENTS.md anything agent-specific; this file is shared

### Testing instructions

- **End-to-end**: send PDF to LINE OA → check `contracts` row + `contract_chunks` count
- **Verify rows**: `PGPASSWORD=contractpw psql -h localhost -U contract -d contracts -c "SELECT id, file_name, status, octet_length(file_data), chunk_count FROM contracts ORDER BY uploaded_at DESC LIMIT 5;"`
- **Verify preview**: `curl -I http://localhost:5678/webhook/admin-file?id=<contract_id>` (200, `Content-Type: application/pdf`)
- **Admin UI**: `https://n8n.jesadakorn.com/webhook/docs-admin-ui` — test dark/light toggle, "ดู" modal tabs (PDF/chunks/metadata)
- **Admin stats (smoke test)**: `curl -s https://n8n.jesadakorn.com/webhook/admin-stats` → `{"ok":true,"action":"stats","data":{...}}`
- **No automated tests** — verification is manual + DB inspection
- **Backfill rule**: if `file_data` is NULL, the file was uploaded before the save flow was wired; use `pg_read_binary_file('/path/to/sample.pdf')` to backfill (same size, not real content)

### PR & commit conventions

- Branch: `main` (remote: `git@github.com:fluke-jesadakorn/contents-project.git`)
- Commit message: conventional commits with Thai-friendly body when relevant
- Snapshot before edit: `pg_dump --schema-only contracts > /tmp/schema-pre.sql` before schema changes
- **n8n flow edit workflow** (ใช้ API แทน direct SQL):
  1. Edit `n8n/flows/<name>.json` ใน local (use `jq` หรือ Python script สำหรับ node/connection manipulation)
  2. Apply ผ่าน API: `curl -X PUT -H "X-N8N-API-KEY: $(grep ^N8N_API_KEY= infra/.env | cut -d= -f2-)" -H "Content-Type: application/json" -d @n8n/flows/<name>.json http://localhost:5678/api/v1/workflows/<id>`
  3. Activate: `curl -X POST -H "X-N8N-API-KEY: ..." http://localhost:5678/api/v1/workflows/<id>/activate`
  4. Restart n8n ถ้ามี credential/node type ใหม่: `launchctl kickstart -k gui/$(id -u)/com.lawpoc.n8n`
  5. Re-export: `curl -H "X-N8N-API-KEY: ..." http://localhost:5678/api/v1/workflows/<id> | jq '.nodes, .connections' > n8n/flows/<name>.json` เพื่อ verify n8n normalized the JSON
  6. Commit: `git add n8n/flows/<name>.json && git commit -m "feat: ..."`

### Security

- **`.env` is gitignored** — never commit; use `.env.example` for the template
- **`infra/.env` และ `infra/n8n-data/.n8n/config`** — sensitive (มี LINE token, OpenRouter key, encryptionKey, `N8N_API_KEY`); ไม่ได้ commit เพราะ `infra/` อยู่นอก repo. File mode 600.
- **`N8N_API_KEY`**: full-access n8n REST API key. สร้างจาก n8n UI → Settings → n8n API → Create API key. ใช้แทน UI access สำหรับ programmatic flow changes. ถ้า leak ให้ revoke ทันทีจาก UI (key เดียวกันเปิดสิทธิ์ workflows + executions + credentials ทั้งหมด)
- **LINE access tokens**: long-lived tokens are sensitive; rotate from LINE console if leaked
- **OpenRouter API key**: free tier rate-limited; cache responses in production
- **Ollama bge-m3**: local embedding; no data leaves the host unless proxied via Cloudflare tunnel
- **Postgres roles**: `contract` (contracts DB) + `n8n_user` (lawpoc_n8n DB) — both SUPERUSER (PoC, ควรจำกัดสำหรับ production)
- **MinIO**: default credentials `minioadmin:minioadmin` (PoC; เปลี่ยนสำหรับ production)
- **No PII logging** in flow Code nodes; contract_chunks `content` is user document text, treat as confidential
- **launchd TCC**: `/Users/fluke/.nvm/versions/node/v22.23.0/bin/node` ต้องมี Full Disk Access ใน System Settings > Privacy & Security (สำหรับเข้าถึง `~/Desktop/Work/Contents/infra/`)
- See `n8n/flows/CREDENTIAL-AUDIT.md` for credential ID inventory

#### Production hardening (PoC → prod checklist)

PoC ใช้ default ที่ไม่ปลอดภัยพอสำหรับ production. Before going live:

- **Postgres SUPERUSER → least privilege**: สร้าง role แยกสำหรับ n8n (GRANT SELECT/INSERT/UPDATE บน `contracts`, `contract_chunks`; REVOKE SUPERUSER). `contract` ควรเป็น owner เท่านั้น ไม่ใช่ app role.
- **MinIO credentials**: เปลี่ยน `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` จาก default; สร้าง service account แยกสำหรับ n8n ด้วย policy จำกัด bucket `epsx-contracts` (read/write + DeleteObject)
- **LINE webhook signature verify**: ตอนนี้ n8n flow รับ webhook โดยไม่ verify X-Line-Signature — ใครยิง POST ตรงไป webhook URL ได้ก็ insert contract ได้. เพิ่ม Code node แรก verify HMAC-SHA256 ด้วย `LINE_CHANNEL_SECRET`
- **Cloudflare tunnel auth**: พิจารณา Cloudflare Access policy หน้า `n8n.jesadakorn.com` (SSO) หรืออย่างน้อย IP allowlist สำหรับ admin endpoints (`/webhook/admin-*`)
- **n8n encryptionKey rotation**: ใน `infra/n8n-data/.n8n/config` — ถ้าเคย leak ต้อง rotate (re-encrypt credentials ทั้งหมด)
- **Backups**: `infra/backups/` มี migration snapshot แล้ว แต่ควรตั้ง pg_dump cron + MinIO versioning

### Architecture (one-liner per service)

```
LINE user → LINE OA → cloudflared tunnel → n8n:5678 (host native)
                                          ↓
                            [Smart Router] → file? → extract + chunk + embed (Ollama bge-m3) → PG
                                          ↓
                                          text? → AI agent (Ollama qwen3.6) → RAG search (PG) → reply
                                          ↓
                            Admin UI: docs-admin-ui → n8n → PG (CRUD + file preview)
```

For detailed wiring, see `n8n/flows/CREDENTIAL-AUDIT.md` and individual flow JSON files.

### Rollback (to docker stack)

ถ้า host-native stack พัง สามารถ rollback ไป docker ได้:

```bash
launchctl unload ~/Library/LaunchAgents/com.lawpoc.n8n.plist
launchctl unload ~/Library/LaunchAgents/com.lawpoc.minio.plist

BACKUP=/Users/fluke/Desktop/Work/Contents/infra/backups/migration-20260621
cp $BACKUP/docker-compose.yml /Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC/
cp -r $BACKUP/pg-gateway /Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC/

cd /Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC
docker compose up -d
```

## hr-line-agent

LINE OA bot: พนักงานขอลาหยุด / เช็คสิทธิ์วันหยุด / ขอดู Job Description. State machine + slot filling ใน n8n; HR approval ผ่าน Next.js admin.

### `web-admin/` (Next.js 16)

- Bun: `bun install` (lockfile = `bun.lock`)
- Verify: `bun run lint` + `bunx tsc --noEmit` — **no `next build`**
- **Post-task dev server**: see Workspace rules → "Post-task dev server (Next.js) — always start". Port `3002`. Always clean `.next/` and start `bun run dev` after finishing work on this project.
- **This is NOT the Next.js you know** — Next 16 has breaking changes vs training data. APIs, conventions, file structure may all differ. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
- Port: `3000` (dev: `next dev -p 3002` per package.json)

## world-erp

AI Financial System. Single Next.js process + consolidated server library:

- `world-erp/` (root) — `bun install`, `bun run embed` / `bun run audit` scripts. `pg` + `axios`.
- `world-erp/lib/` — server-only library imported by web-admin via the `@erp-lib/*` tsconfig path alias. Contains **single** perm/RBAC system (`lib/perm/*`), AI router + provider clients (`lib/ai/`), MinIO slip storage + OCR pipeline (`lib/slips/`), shared DB / config / session-token / guard (`lib/{db,config,server}/`), and the Swift N-API vision-ocr binding (`lib/native/vision-ocr/`).
- `world-erp/web-admin/` — Next.js 16 admin dashboard. **NOT the Next.js you know** — same warning as hr-line-agent. Port 3003. UI + server actions + Next.js route handlers under `src/app/api/*` that call `@erp-lib/*` functions directly (no HTTP hop).

Verify with `bun run lint` + `bunx tsc --noEmit` (run from `world-erp/web-admin/`).

**Post-task dev server**: see Workspace rules → "Post-task dev server (Next.js) — always start". Port `3003`. Always clean `.next/` and start `bun run dev` after finishing work on this project.

### Architecture

```
Browser → web-admin (Next.js :3003) ─┬→ @erp-lib/perm/*      ──→ Postgres
                                    ├→ @erp-lib/ai/*        ──┬→ Postgres
                                    │                        ├→ Ollama
                                    │                        └→ MinIO (epsx-erp-slips)
                                    └→ @erp-lib/slips/*    (storage + OCR pipeline)
```

All business logic lives in `world-erp/lib/`. The Next.js route handlers under `src/app/api/*` are thin: parse input, call a `@erp-lib/*` function, return JSON. The legacy Fastify services and the separate `lib/rbac/*` matrix module have been removed — RBAC is now exclusively the perm-string system in `lib/perm/*`.

### tsconfig path alias

`web-admin/tsconfig.json` declares `"@erp-lib/*": ["../lib/*"]` so any `import { x } from '@erp-lib/server/guard'` resolves to `world-erp/lib/server/guard.ts`. The webpack and turbopack resolvers in `web-admin/next.config.ts` mirror the alias so the bundler can resolve it too.

### Session

Single `SESSION_SECRET` (HMAC-SHA256). web-admin mints the `erp_session` cookie on sign-in; `@erp-lib/server/sessionToken.verifySession()` validates it from the cookie or `x-erp-session` header at every route handler.

### Slip storage

Slips live in MinIO bucket `epsx-erp-slips` (key `YYYY/MM/<uuid><ext>`). Browser receives a `/api/slips/file?key=...` URL which redirects to a 10-minute pre-signed MinIO GET via `@erp-lib/slips/storage.presignedGetUrl()`.

### Run

```bash
cd world-erp/web-admin && bun install && bun run dev
```

That's it — one process. The native vision-ocr binding only loads at runtime via `createRequire`; the `bun run install:vision-ocr` script from the old ai-svc is no longer needed at runtime but the compiled `.node` binary in `lib/native/vision-ocr/build/Release/` is still required for OCR Pass 3.

### Permission grammar (single RBAC system)

**RBAC = compound of permissions. Roles = compound of permissions.** There is one system; legacy `lib/rbac/*` and `web-admin/src/lib/{rbac,access}/` are deleted.

**Permission string grammar** (one canonical shape, no effect/dept/scope columns anywhere):

```
<domain>:<subject>:<verb>[:<qualifier>]::<effect>
```

- `domain` ∈ `{rbac, user, org, finance, stage, tile, hook, ai, policy, access_request, admin}`
- `subject` / `verb` — lowercase snake, lowercase snake
- `qualifier` — optional: omitted or `*` = global; otherwise free-form (typically a dept-id)
- `effect` ∈ `{allow, deny}` — required, **encoded inline in the string** (no separate `effect` column)

| Example | Meaning |
|---|---|
| `finance:expense:approve::allow` | global allow |
| `finance:expense:approve:finance-2::allow` | dept-scoped allow |
| `user:dept:finance-2::allow` | dept membership marker (granted to user) |
| `tile:expense:view::allow` | tile view gate |
| `admin:system:bypass::allow` | admin bypass — grants everything |

**Role-id grammar** (level encoded inline, no `level` column):

```
<name>::<level>
```

- `<level>` integer 1–10 (1 = CEO / highest authority)
- Examples: `ceo::1`, `cfo::2`, `manager::3`, `officer::5`
- Effective level = MIN(level) over assigned role-ids
- A user's department = the value of their `user:dept:<id>::allow` permission

**File layout** (`world-erp/lib/perm/`):

- `grammar.ts` — **single source of truth**: `parsePerm`, `parseRoleId`, `buildPerm`, `buildRoleId`, `parseDeptFromPerms`, `parseLevelFromRoles`, `effectOf`, `isAllow`/`isDeny`, `matchPerm`, `PERM_ID_REGEX`, `ROLE_ID_REGEX`, `ADMIN_PERM`
- `auth-client.ts` — client-safe `hasPermission`, `canManageResource`, `sessionDept`, `sessionLevel` (pure functions, no DB)
- `auth.ts` — server-only session loader: `loadActivePermSession`, `loadPermSessionFromHeaders`, `loadPermSessionFromCookieValue`; re-exports client helpers
- `ability.ts` — CASL ability builder: `buildAbilityFor(userId)`, `loadUserRoleIds`, `loadRoleGrants`
- `level.ts` — `getEffectiveLevel(userId)`, `getEffectiveLevels(userIds[])`, `getRoleEffectiveLevel(roleId)`
- `scope.ts` — `getActorScope`, `scopeFilter`, `assertInScope` (scope derived from perm string qualifiers)
- `chain.ts` — approval chain resolver: `resolveApprovalChain`, `canActOnStage`, `getApprovedStages`, `resolveNextStage`, `isFinalApprovalStage`
- `grants.ts` — CRUD for `perm.user_permissions` (replaces legacy `rbac.perm_grants`)
- `stages.ts` — pure stage data + `STAGE_ORDER`, `STAGE_TO_ROLE`, `STAGE_TO_PERM`, `normalizeStage` (with `LEGACY_TO_NEW` alias map)
- `taxonomy.ts` — `PERM` catalog (every value already includes `::allow`)
- `schema.ts` / `session.ts` — types only
- `client.ts` — browser hooks: `useHasPerm`, `useActorDept`, `useActorLevel`, `useActorRoleName`, `useHasPerms`
- `index.ts` — client-safe barrel
- `server.ts` — server-only barrel (imports `'server-only'`)

**DB tables** (`finance_db.perm.*`):

- `roles (id PK, display_name, description, is_system, sort_order, parent_role_id, display_name_th, display_name_de, monthly_budget, head_user_id)` — **no `kind`, no `level` column**
- `permissions (id PK, description)` — id is the full `::` string
- `role_permissions (role_id, permission_id, granted_at, granted_by)` — **no `effect` column**
- `user_roles (user_id, role_id, granted_at, granted_by)` — single binding table (persona + dept via row semantics)
- `user_permissions (id, user_id, permission_id, granted_by, reason, granted_at, revoked_at, revoked_by, starts_at, ends_at)` — supports both permanent (`ends_at IS NULL`) and time-bound grants; effect encoded in `permission_id`
- `tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, request_target, sort_order, is_system, owner_group_id, view_perm_id, created_at, updated_at)` — **`view_perm_id`** replaces the old `required_level` + `required_dept_id` columns
- `audit (id, kind, actor, target jsonb, occurred_at)`
- `policies (id, name, ast jsonb, …)` + `policy_decisions`

**No views** — the old `perm.user_effective_level`, `perm.role_effective_level`, `perm.effective_user_perms`, `perm.active_user_permissions` are dropped. Levels and effective perms are derived at read time via `parseRoleId` / `parseLevelFromRoles` / a SQL `COALESCE` + `array_agg` of role-ids.

**No triggers** — `perm_rp_sync_level`, `perm_ur_one_dept`, `perm_ur_sync_dept_cache`, `tile_required_dept_check` are dropped.

`users.dept_group_id` column is dropped — department is a `user:dept:<id>::allow` grant on `perm.user_permissions`.

**Caller rules**:

- Server-side code (route handlers, server actions, `*.server.ts`): `import { ... } from '@erp-lib/perm/server'`
- Client code (components, hooks): `import { ... } from '@erp-lib/perm'`
- The split exists because `'server-only'` modules cannot be bundled into client chunks.

**Migration scripts**:

- `db/perm/9000-rebuild-string-grammar.sql` — drops + recreates `perm` schema with new shape; also `ALTER TABLE users DROP COLUMN dept_group_id`
- `db/perm/9001-seed-new-grammar.sql` — full catalog (15 roles, 131 permissions, curated grants)
- `db/perm/9002-seed-user-roles-and-depts.sql` — 25 users + persona bindings + `user:dept:<id>::allow` grants

### Waybill system (consolidated expense/PR/PO)

**All expense, PR and PO flows now share a single Waybill object**. One DB row in `waybills` (keyed `WB-YYYY-NNNNNN`), one audit log in `waybill_events` (linked-list, HMAC-SHA256 signed), one detail page (`/waybill/[id]`), one inbox (`/my-waybills`), one Rail component (`<WaybillRail>`).

**DB tables** (migrations `db/2026-07-09-A-…` and `db/2026-07-09-B-…`):

- `waybills` — `(id text PK, origin text, origin_id int, current_stage text, total_amount_thb numeric, fiscal_year int, created_at, updated_at)`; CHECK on `origin IN ('expense','pr','po')`
- `waybill_events` — append-only; `(id bigserial PK, waybill_id text, sequence int, kind text, from_stage text, to_stage text, actor int, payload jsonb, previous_event_id bigint, signature text, occurred_at)`; UNIQUE(waybill_id, sequence); `previous_event_id` IS NULL only for `sequence=1`; HMAC-SHA256 signature over `(sequence|kind|from_stage|to_stage|actor|previous_event_id|waybill_id)` keyed by `SESSION_SECRET`; **UPDATE/DELETE revoked** for `contract` + `n8n_user` roles
- `next_waybill_number(fiscal_year)` SQL function — per-fiscal-year sequences starting at 1
- All legacy tables (`expenses`, `purchase_requisitions`, `purchase_orders`, `approval_transitions`) enforce **finance-standard status keys** via CHECK constraints: `submission`, `dept_verification`, `dept_authorization`, `accounting_verification`, `accounting_supervision`, `accounting_authorization`, `disbursement_authorization`, `cfo_authorization`, `ceo_authorization`, `awaiting_disbursement`, `disbursed`, `rejected`. **Snake_case keys (`pending_approval`, `po_cfo`, etc.) are rejected at INSERT.**

**lib modules** (all in `world-erp/lib/waybill/`):

- `labels.ts` — `EXPENSE_STAGES` (12 pips, EN+TH bilingual, bucket classification), `PROCUREMENT_STAGES` (5 pips), `stageLabel()` with fallbacks
- `number.ts` — `parseWaybillId()`, `generateWaybillId(fiscalYear)`, `currentFiscalYear()`
- `derive.ts` — `pipsForDomain()`, `nextStageOf()` (respects 200k CEO threshold), `inferActionStage()`, `bucketLabel()`
- `events.ts` — `recordEvent({client, waybillId, kind, fromStage, toStage, actor, payload, previousEventId})`, `listEvents()`, `verifyEventChain()`
- `append.ts` — `appendWaybillEvent({client, origin, originId, kind, fromStage, toStage, actor, payload})` — best-effort audit in own tx; resolves Waybill by `(origin, origin_id)`; creates placeholder if missing

**Stage permissions** (e.g. `stage:dept_verification:act::allow`) — granted to roles via `perm.role_permissions` and matched against the actor's effective permission list at every waybill action. Stage→role mapping is static in `lib/perm/stages.ts`.

**Routes**:

- `/waybill/[id]` — RSC detail with `<WaybillRail>`, integrity banner, native form-action approve/reject/resubmit (URL-driven via `?action=…`)
- `/waybill/by-expense/[id]`, `/waybill/by-pr/[id]`, `/waybill/by-po/[id]` — origin-lookup helpers (308 → `/waybill/WB-…`)
- `/my-waybills?scope={mine,queue,all}` — RSC inbox
- `/expense`, `/pr`, `/po` — thin landings (each 308 → `/my-waybills?scope=…`)
- Legacy URLs (`/expense-claim`, `/approve-expense`, `/all-approvals`, `/my-prs`, `/po`) — 308 redirects in `next.config.ts`

**Server actions wired** (in `web-admin/src/app/actions.ts`): every state mutation calls `appendWaybillEvent()` — `submitExpenseFromSlip`, `submitPurchaseRequisition`, `advanceApproval`, `advancePurchaseRequisition`, `advancePurchaseOrder`, `attachDisbursementPayslip`, `settleExpenseMock`. Actions on `/waybill/[id]` live in `web-admin/src/app/(protected)/waybill/[id]/_actions.ts`.

**CEO escalation**: 200,000 THB threshold. `nextStageOf()` and `<WaybillRail>` auto-dim the `ceo_authorization` pip when `total_amount_thb < 200_000`.

**Bilingual**: `localStorage.worderp.lang` ∈ `{en, th}`. `LangGate` (in `app/layout.tsx`) shows first-visit modal. `LangPickerTrigger` toggles via header pill. `<html lang>` hydrates from inline script in layout to avoid FOUC.

### Admin pages

- `/roles` — full role CRUD + user-role assignment + per-user perm grants. Backed by `/api/perm/roles*`, `/api/perm/users*`, `/api/perm/permissions`, `/api/perm/audit`, `/api/perm/levels`.
- `/tiles` — tile catalog with `view_perm_id` editor. Backed by `/api/perm/tiles*`.
- `/policy` — persona × stage matrix editor. Backed by `/api/policy/matrix` + `/api/perm/roles/[id]/permissions`.
- `/audit` — perm-tile audit log feed. Gated by `tile:audit:view::allow`.

### Verification commands

```bash
cd world-erp/web-admin
bun run lint && bunx tsc --noEmit
curl -s http://localhost:3003/roles
curl -s http://localhost:3003/tiles
curl -s http://localhost:3003/policy
curl -s http://localhost:3003/my-waybills

PGPASSWORD=contractpw psql -h localhost -U contract -d finance_db -c "
  SELECT id FROM perm.roles LIMIT 5;"
PGPASSWORD=contractpw psql -h localhost -U contract -d finance_db -c "
  SELECT id FROM perm.permissions LIMIT 5;"
PGPASSWORD=contractpw psql -h localhost -U contract -d finance_db -c "
  SELECT role_id, permission_id FROM perm.role_permissions LIMIT 5;"

PGPASSWORD=contractpw psql -h localhost -U contract -d finance_db -c "
  SELECT id, origin, current_stage, total_amount_thb
  FROM waybills ORDER BY created_at;"
```

## finance-line-agent

Web admin scaffold. `web-admin/.next/` build artifacts were stale and have been removed. No `package.json` yet — placeholder.

## smarthome-line-agent

Bash runtime + `.env.example`. No Node. Manual verification only (`run.sh` against LINE OA webhook).

## ai-realtime-translate

Desktop app (Dioxus on macOS).

- Rust crate: `cargo check` + `cargo clippy` + `cargo fmt --check` (no `cargo build` for verification)
- Python venv at `.venv/` — `ruff check` / `ruff format --check` if available; otherwise skip
- Build artifact: `dist/` (signed + notarized `.app`); do not regenerate as verification

## infra

Shared host-native services. Not a Node project.

- Sensitive runtime config: `infra/.env`, `infra/n8n-data/.n8n/config` (file mode 600, never commit)
- Service control: `launchctl list | grep lawpoc` to inspect; `launchctl kickstart -k gui/$(id -u)/<label>` to restart
- Logs: `infra/logs/{n8n,minio}.log`
- Backups: `infra/backups/migration-YYYYMMDD/`

## Coding principles

- Shortest reasonable names for variables, functions, files, folders
- No hardcoded / mockup data (unless explicitly requested)
- Edit existing files; do not create parallel "improved" versions
- No comments unless explicitly asked
