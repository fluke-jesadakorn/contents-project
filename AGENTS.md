# AGENTS.md

Multi-project workspace under `/Users/fluke/Desktop/Work/Contents/`. Sub-project rules live as sections here — read the relevant section before working in that project.

## Sub-projects

- `folio/` — AI Financial System (Next.js admin + HR + Law + Finance). Single process, single DB.
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
| `folio` | `folio/app` | 3004 | `/tmp/folio.dev.log` |

Steps per affected project:

1. Check if already up: `lsof -ti:<port>`. If a PID returns, skip — don't restart.
2. If not running, clean cache: `rm -rf <project>/app/.next`.
3. Start in background: `cd <project>/app && bun run dev > /tmp/<project>.dev.log 2>&1 &`
4. Confirm boot: `tail -n 50 /tmp/<project>.dev.log` — look for "Ready in" and no stack traces.
5. Report the local URL to the user (e.g. `http://localhost:3004`).

Skip only if no Next.js code was touched in the task.

## folio

Single Next.js 16 process on port 3004. One Postgres database (`folio_db`) with schemas: `finance`, `perm`, `hook`, `hr`, `law`, `n8n`, `folio`, `public`. One n8n instance for HR + Law + future folio flows. One MinIO bucket `folio-storage` with key prefixes `slips/`, `law/contracts/`, `waybill/`, `hr/`.

Folio absorbs three prior projects (`hr-line-agent/`, `Law-digitalize-PoC/`, the host-native `infra/` stack). They no longer exist as folders — their functionality lives under folio.

### Bundler

Turbopack only. `next dev --turbopack` and `next build --turbopack` are explicit. No `webpack:` block in `next.config.ts`. See `folio/docs/BUNDLER.md`.

### LINE channels

Two distinct LINE OAs (no channel merger):

- **folio / Law bot** — secret `LINE_CHANNEL_SECRET`, provider id `line_law` in `hook.hook_providers`. Webhook: `https://n8n.jesadakorn.com/webhook/<law-flow>`.
- **HR bot** — secret `HR_LINE_CHANNEL_SECRET`, provider id `line_hr`. Webhook: `https://n8n.jesadakorn.com/webhook/hr-line-agent`.

n8n orchestrates; folio's `/api/hook/line` and `/api/hook/line-hr` are thin HMAC-verified event sinks into `hook.hook_events`.

### Shared infra (host-native)



AI Financial System. Single Next.js process + consolidated server library:

- `folio/` (root) — `bun install`, `bun run embed` / `bun run audit` scripts. `pg` + `axios`.
- `folio/lib/` — server-only library imported by app via the `@folio-lib/*` tsconfig path alias. Contains **single** perm/RBAC system (`lib/perm/*`), AI router + provider clients (`lib/ai/`), HR feature (`lib/hr/*`), Law feature (`lib/law/*`), MinIO slip storage + OCR pipeline (`lib/slips/*`), shared DB / config / session-token / guard (`lib/{db,config,server}/`), and the Swift N-API vision-ocr binding (`lib/native/vision-ocr/`).
- `folio/app/` — Next.js 16 admin dashboard. **NOT the Next.js you know** — same warning as hr-line-agent. Port 3004. UI + server actions + Next.js route handlers under `src/app/api/*` that call `@folio-lib/*` functions directly (no HTTP hop).

Verify with `bun run lint` + `bunx tsc --noEmit` (run from `folio/app/`).

**Post-task dev server**: see Workspace rules → "Post-task dev server (Next.js) — always start". Port `3004`. Always clean `.next/` and start `bun run dev` after finishing work on this project.

### Architecture

```
Browser → app (Next.js :3004) ─┬→ @folio-lib/perm/*      ──→ Postgres
                                    ├→ @folio-lib/ai/*        ──┬→ Postgres
                                    │                        ├→ Ollama
                                    │                        └→ MinIO (folio-storage)
                                    └→ @folio-lib/slips/*    (storage + OCR pipeline)
```

All business logic lives in `folio/lib/`. The Next.js route handlers under `src/app/api/*` are thin: parse input, call a `@folio-lib/*` function, return JSON. The legacy Fastify services and the separate `lib/rbac/*` matrix module have been removed — RBAC is now exclusively the perm-string system in `lib/perm/*`.

### tsconfig path alias

`app/tsconfig.json` declares `"@folio-lib/*": ["../lib/*"]` so any `import { x } from '@folio-lib/server/guard'` resolves to `folio/lib/server/guard.ts`. The webpack and turbopack resolvers in `app/next.config.ts` mirror the alias so the bundler can resolve it too.

### Session

Single `SESSION_SECRET` (HMAC-SHA256). app mints the `folio_session` cookie on sign-in; `@folio-lib/server/sessionToken.verifySession()` validates it from the cookie or `x-folio-session` header at every route handler.

### Slip storage

Slips live in MinIO bucket `folio-storage` (key `YYYY/MM/<uuid><ext>`). Browser receives a `/api/slips/file?key=...` URL which redirects to a 10-minute pre-signed MinIO GET via `@folio-lib/slips/storage.presignedGetUrl()`.

### Run

```bash
cd folio/app && bun install && bun run dev
```

That's it — one process. The native vision-ocr binding only loads at runtime via `createRequire`; the `bun run install:vision-ocr` script from the old ai-svc is no longer needed at runtime but the compiled `.node` binary in `lib/native/vision-ocr/build/Release/` is still required for OCR Pass 3.

### Permission grammar (single RBAC system)

**RBAC = compound of permissions. Roles = compound of permissions.** There is one system; legacy `lib/rbac/*` and `app/src/lib/{rbac,access}/` are deleted.

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

**File layout** (`folio/lib/perm/`):

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

**DB tables** (`folio_db.perm.*`):

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

- Server-side code (route handlers, server actions, `*.server.ts`): `import { ... } from '@folio-lib/perm/server'`
- Client code (components, hooks): `import { ... } from '@folio-lib/perm'`
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

**lib modules** (all in `folio/lib/waybill/`):

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

**Server actions wired** (in `app/src/app/actions.ts`): every state mutation calls `appendWaybillEvent()` — `submitExpenseFromSlip`, `submitPurchaseRequisition`, `advanceApproval`, `advancePurchaseRequisition`, `advancePurchaseOrder`, `attachDisbursementPayslip`, `settleExpenseMock`. Actions on `/waybill/[id]` live in `app/src/app/(protected)/waybill/[id]/_actions.ts`.

**CEO escalation**: 200,000 THB threshold. `nextStageOf()` and `<WaybillRail>` auto-dim the `ceo_authorization` pip when `total_amount_thb < 200_000`.

**Bilingual**: `localStorage.worderp.lang` ∈ `{en, th}`. `LangGate` (in `app/layout.tsx`) shows first-visit modal. `LangPickerTrigger` toggles via header pill. `<html lang>` hydrates from inline script in layout to avoid FOUC.

### Admin pages

- `/roles` — full role CRUD + user-role assignment + per-user perm grants. Backed by `/api/perm/roles*`, `/api/perm/users*`, `/api/perm/permissions`, `/api/perm/audit`, `/api/perm/levels`.
- `/tiles` — tile catalog with `view_perm_id` editor. Backed by `/api/perm/tiles*`.
- `/policy` — persona × stage matrix editor. Backed by `/api/policy/matrix` + `/api/perm/roles/[id]/permissions`.
- `/audit` — perm-tile audit log feed. Gated by `tile:audit:view::allow`.

### Verification commands

```bash
cd folio/app
bun run lint && bunx tsc --noEmit
curl -s http://localhost:3004/roles
curl -s http://localhost:3004/tiles
curl -s http://localhost:3004/policy
curl -s http://localhost:3004/my-waybills

PGPASSWORD=contractpw psql -h localhost -U contract -d folio_db -c "
  SELECT id FROM perm.roles LIMIT 5;"
PGPASSWORD=contractpw psql -h localhost -U contract -d folio_db -c "
  SELECT id FROM perm.permissions LIMIT 5;"
PGPASSWORD=contractpw psql -h localhost -U contract -d folio_db -c "
  SELECT role_id, permission_id FROM perm.role_permissions LIMIT 5;"

PGPASSWORD=contractpw psql -h localhost -U contract -d folio_db -c "
  SELECT id, origin, current_stage, total_amount_thb
  FROM waybills ORDER BY created_at;"
```

## finance-line-agent

Web admin scaffold. `app/.next/` build artifacts were stale and have been removed. No `package.json` yet — placeholder.

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
