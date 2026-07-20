# Contents Project Workspace

A multi-project workspace that hosts the **AI Financial System (folio)** plus a set of host-native services and companion apps, all running on a single macOS host.

> Authoritative operator & agent guide: [`AGENTS.md`](./AGENTS.md). This README is a high-level overview.

---

## Workspace Layout

| Path | Stack | Purpose |
| --- | --- | --- |
| [`folio/`](./folio) | Next.js 16 · Postgres · n8n · MinIO | **AI Financial System** — admin dashboard, HR, Law, Finance, RBAC, Waybill (expense/PR/PO) workflow, slip OCR pipeline |
| [`infra/`](./infra) | launchd · Docker | Shared host-native services: n8n, MinIO, Postgres 18, launchd plists |
| [`ai-realtime-translate/`](./ai-realtime-translate) | Rust · Dioxus · Python | Desktop realtime translator (macOS) |
| [`smarthome-line-agent/`](./smarthome-line-agent) | Bash | Smarthome LINE OA agent |
| `finance-line-agent/` | _(scaffold)_ | Finance LINE agent (planned) |

The three legacy projects (`hr-line-agent/`, `Law-digitalize-PoC/`, host-native `infra/` stack) have been absorbed into `folio/` and no longer exist as top-level folders.

---

## folio — AI Financial System

A single Next.js process on port **3004** backed by one Postgres database (`folio_db`) with schemas: `finance`, `perm`, `hook`, `hr`, `law`, `n8n`, `folio`, `public`.

**Architecture**

```
Browser → app (Next.js :3004) ─┬→ @folio-lib/perm/*      ──→ Postgres
                               ├→ @folio-lib/ai/*        ──┬→ Postgres
                               │                          ├→ Ollama
                               │                          └→ MinIO (folio-storage)
                               └→ @folio-lib/slips/*     (storage + OCR pipeline)
```

- `folio/lib/` — server-only library (perm/RBAC, AI router, HR, Law, slips/OCR, shared DB/config/session). Imported via the `@folio-lib/*` tsconfig alias.
- `folio/app/` — Next.js 16 admin UI + server actions + thin route handlers under `src/app/api/*`.
- **Bundler:** Turbopack only.
- **Session:** Single `SESSION_SECRET` (HMAC-SHA256); `folio_session` cookie or `x-folio-session` header.
- **LINE channels:** two distinct OAs — folio/Law bot (`line_law`) and HR bot (`line_hr`); n8n orchestrates, folio's `/api/hook/line*` are thin HMAC-verified event sinks.

### Waybill system

All expense, PR and PO flows share a single **Waybill** object (`WB-YYYY-NNNNNN`), one audit log (`waybill_events`, linked-list + HMAC-signed), one detail page (`/waybill/[id]`), one inbox (`/my-waybills`), and one `<WaybillRail>` component. CEO escalation auto-triggers above **200,000 THB**. UI is bilingual (EN/TH) via `localStorage.worderp.lang`.

### Run

```bash
cd folio/app && bun install && bun run dev
```

### Verify

```bash
cd folio/app
bun run lint && bunx tsc --noEmit
```

---

## Shared Infrastructure (`infra/`)

Host-native services managed by macOS `launchd` (`com.lawpoc.*`):

| Service | Port | Notes |
| --- | --- | --- |
| n8n | 5678 | Flow orchestration — https://n8n.jesadakorn.com |
| MinIO | 9000 / 9001 | Object storage for `folio-storage` bucket |
| PostgreSQL 18 | 5432 | Databases: `folio_db`, `hr_db`, `lawpoc_n8n` |

### Control

```bash
# inspect services
launchctl list | grep lawpoc

# restart a service (KeepAlive=true respawns automatically)
launchctl kickstart -k gui/$(id -u)/<label>
```

- Config (never commit): `infra/.env`, `infra/n8n-data/.n8n/config` (mode 600)
- Logs: `infra/logs/{n8n,minio}.log`
- Backups: `infra/backups/migration-YYYYMMDD/`

---

## Conventions

- **Package manager:** `bun` for all Node/Next.js work — never `npm install`/`npm ci`. Commit `bun.lock`.
- **Verification:** static checks only (`bun run lint`, `bunx tsc --noEmit`, `cargo check`, `ruff`). Never run `build`/`start`/`cargo build`/`cargo run` to verify.
- **Post-task:** after any Next.js change, start `bun run dev` in the background (folio on `:3004`, log `/tmp/folio.dev.log`).
- **Naming:** shortest reasonable names; no hardcoded/mock data; edit existing files over creating new ones.

---

## Local URLs

| Service | URL |
| --- | --- |
| folio admin | http://localhost:3004 |
| n8n editor | https://n8n.jesadakorn.com |
| MinIO console | http://localhost:9001 |
| PostgreSQL | `localhost:5432` |

---

## Further Reading

- [`AGENTS.md`](./AGENTS.md) — full operator and agent guide (source of truth).
- [`folio/docs/`](./folio/docs) — folio-specific docs (bundler, migrations, etc.).
