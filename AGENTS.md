# AGENTS.md

LINE bot PoC: รับสัญญา (PDF/DOCX) จาก LINE → chunk + embed → เก็บใน Postgres+pgvector → RAG Q&A + admin CRUD UI. Orchestration ทั้งหมดอยู่ใน n8n (host-native, ไม่ใช้ docker แล้ว); embedding ผ่าน Ollama bge-m3; chat agent ผ่าน Ollama qwen3.6:35b-a3b-q4_K_M (OpenRouter เก็บไว้ใน env สำหรับ archived flows เท่านั้น).

## Setup commands

- Start stack:        อัตโนมัติตอน boot ผ่าน launchd (`com.lawpoc.n8n`, `com.lawpoc.minio`)
- Verify stack:       `launchctl list | grep lawpoc && curl http://localhost:5678/healthz && curl -I http://localhost:9000/minio/health/live`
- Open n8n:           `https://n8n.jesadakorn.com` (Cloudflare tunnel)
- Restart n8n:        `launchctl kickstart -k gui/$(id -u)/com.lawpoc.n8n`
- Restart minio:      `launchctl kickstart -k gui/$(id -u)/com.lawpoc.minio`
- View n8n log:       `tail -f /Users/fluke/Desktop/Work/Contents/infra/logs/n8n.log`
- DB schema:          `psql -h localhost -U contract -d contracts -f db/init.sql`
- Edit n8n env:       `vi /Users/fluke/Desktop/Work/Contents/infra/.env` แล้ว restart n8n

## Project layout

- `db/init.sql` — schema: `contracts`, `contract_chunks` (vector(1024) for bge-m3), `next_doc_seq()` + `touch_updated_at()` trigger (ivfflat index commented out — uncomment after >100 rows)
- `n8n/flows/` — exported workflow JSON. Active: `03-docs-hub.json` (78KB, 71 nodes), `04-docs-admin.json`. Archived (host-native migration leftovers): `archive/01-*.json`, `archive/02-*.json`
- `n8n/credentials.md`, `n8n/flows/CREDENTIAL-AUDIT.md` — credential IDs, flow wiring reference
- `docs/LINE-SETUP.md`, `docs/N8N-SETUP.md` — operator runbooks for LINE channel + n8n env
- `../infra/` — shared host-native infra (n8n runtime, MinIO, logs, launchd plists, backups)

## Infra layout (`/Users/fluke/Desktop/Work/Contents/infra/`)

- `.env` — n8n + minio runtime env (DB, LINE, OpenRouter, Ollama)
- `n8n-data/.n8n/config` — n8n encryptionKey (sensitive — อย่า commit)
- `minio-data/` — MinIO data dir (bucket: `epsx-contracts`)
- `logs/n8n.log`, `logs/minio.log` — runtime logs (stdout+stderr)
- `launchd/com.lawpoc.n8n.plist`, `launchd/com.lawpoc.minio.plist` — launchd agents (symlinked to `~/Library/LaunchAgents/`)
- `scripts/start-n8n.js` — launchd entrypoint (loads .env, exec n8n start)
- `scripts/start-n8n.sh` — manual run alternative (bash version)
- `backups/migration-YYYYMMDD/` — migration snapshots (n8n.sql, contracts-schema.sql, creds.json, flows.zip, n8n-config.json)

## Services

| Service | Binary | Port | launchd Label | Notes |
|---|---|---|---|---|
| n8n | `/Users/fluke/.nvm/versions/node/v22.23.0/bin/n8n` | 5678 | `com.lawpoc.n8n` | node 22 (nvm) ไม่ใช่ system node |
| MinIO | `/opt/homebrew/bin/minio` | 9000 (api) / 9001 (console) | `com.lawpoc.minio` | data at `infra/minio-data/` |
| Postgres | `/opt/homebrew/opt/postgresql@18/bin/postgres` | 5432 | `homebrew.mxcl.postgresql@18` | DBs: `contracts` (owner: contract), `lawpoc_n8n` (owner: n8n_user) |
| Ollama | `/opt/homebrew/bin/ollama` | 11434 | (manual / brew services) | bge-m3 model |
| cloudflared | `/opt/homebrew/bin/cloudflared` | — | (manual) | tunnel `b8f4ccf5-67de-4bfa-b292-7641ad185006`, ingress: n8n.jesadakorn.com → localhost:5678, ai.jesadakorn.com → localhost:11434 |

## Code style

- **n8n flows**: prefix node names with the subsystem (`LINE:`, `AI:`, `PG:`, `LLM:`); Code node JS uses `asyncCode: true`; SQL built dynamically uses dollar-quoting `$tag$...$tag$` for content + `'...'` escape for identifiers
- **SQL**: parameters via Postgres node's `queryReplacement` array, NOT f-string interpolation; always escape single quotes in dynamic content
- **Commits**: conventional (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`); body explains WHY not WHAT
- **Don't add** to AGENTS.md anything agent-specific; this file is shared

## Testing instructions

- **End-to-end**: send PDF to LINE OA → check `contracts` row + `contract_chunks` count
- **Verify rows**: `PGPASSWORD=contractpw psql -h localhost -U contract -d contracts -c "SELECT id, file_name, status, octet_length(file_data), chunk_count FROM contracts ORDER BY uploaded_at DESC LIMIT 5;"`
- **Verify preview**: `curl -I http://localhost:5678/webhook/admin-file?id=<contract_id>` (200, `Content-Type: application/pdf`)
- **Admin UI**: `https://n8n.jesadakorn.com/webhook/docs-admin-ui` — test dark/light toggle, "ดู" modal tabs (PDF/chunks/metadata)
- **Admin stats (smoke test)**: `curl -s https://n8n.jesadakorn.com/webhook/admin-stats` → `{"ok":true,"action":"stats","data":{...}}`
- **No automated tests** — verification is manual + DB inspection
- **Backfill rule**: if `file_data` is NULL, the file was uploaded before the save flow was wired; use `pg_read_binary_file('/path/to/sample.pdf')` to backfill (same size, not real content)

## PR & commit conventions

- Branch: `main` (remote: `git@github.com:fluke-jesadakorn/contents-project.git`)
- Commit message: conventional commits with Thai-friendly body when relevant
- Snapshot before edit: `pg_dump --schema-only contracts > /tmp/schema-pre.sql` before schema changes
- After n8n flow edit: export → save to `n8n/flows/<name>.json` → commit

## Security

- **`.env` is gitignored** — never commit; use `.env.example` for the template
- **`infra/.env` และ `infra/n8n-data/.n8n/config`** — sensitive (มี LINE token, OpenRouter key, encryptionKey); ไม่ได้ commit เพราะ `infra/` อยู่นอก repo
- **LINE access tokens**: long-lived tokens are sensitive; rotate from LINE console if leaked
- **OpenRouter API key**: free tier rate-limited; cache responses in production
- **Ollama bge-m3**: local embedding; no data leaves the host unless proxied via Cloudflare tunnel
- **Postgres roles**: `contract` (contracts DB) + `n8n_user` (lawpoc_n8n DB) — both SUPERUSER (PoC, ควรจำกัดสำหรับ production)
- **MinIO**: default credentials `minioadmin:minioadmin` (PoC; เปลี่ยนสำหรับ production)
- **No PII logging** in flow Code nodes; contract_chunks `content` is user document text, treat as confidential
- **launchd TCC**: `/Users/fluke/.nvm/versions/node/v22.23.0/bin/node` ต้องมี Full Disk Access ใน System Settings > Privacy & Security (สำหรับเข้าถึง `~/Desktop/Work/Contents/infra/`)
- See `n8n/flows/CREDENTIAL-AUDIT.md` for credential ID inventory

### Production hardening (PoC → prod checklist)

PoC ใช้ default ที่ไม่ปลอดภัยพอสำหรับ production. Before going live:

- **Postgres SUPERUSER → least privilege**: สร้าง role แยกสำหรับ n8n (GRANT SELECT/INSERT/UPDATE บน `contracts`, `contract_chunks`; REVOKE SUPERUSER). `contract` ควรเป็น owner เท่านั้น ไม่ใช่ app role.
- **MinIO credentials**: เปลี่ยน `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` จาก default; สร้าง service account แยกสำหรับ n8n ด้วย policy จำกัด bucket `epsx-contracts` (read/write + DeleteObject)
- **LINE webhook signature verify**: ตอนนี้ n8n flow รับ webhook โดยไม่ verify X-Line-Signature — ใครยิง POST ตรงไป webhook URL ได้ก็ insert contract ได้. เพิ่ม Code node แรก verify HMAC-SHA256 ด้วย `LINE_CHANNEL_SECRET`
- **Cloudflare tunnel auth**: พิจารณา Cloudflare Access policy หน้า `n8n.jesadakorn.com` (SSO) หรืออย่างน้อย IP allowlist สำหรับ admin endpoints (`/webhook/admin-*`)
- **n8n encryptionKey rotation**: ใน `infra/n8n-data/.n8n/config` — ถ้าเคย leak ต้อง rotate (re-encrypt credentials ทั้งหมด)
- **Backups**: `infra/backups/` มี migration snapshot แล้ว แต่ควรตั้ง pg_dump cron + MinIO versioning

## Architecture (one-liner per service)

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

## Rollback (to docker stack)

ถ้า host-native stack พัง สามารถ rollback ไป docker ได้:

```bash
# 1. หยุด host services
launchctl unload ~/Library/LaunchAgents/com.lawpoc.n8n.plist
launchctl unload ~/Library/LaunchAgents/com.lawpoc.minio.plist

# 2. คืน docker-compose + pg-gateway จาก backup
BACKUP=/Users/fluke/Desktop/Work/Contents/infra/backups/migration-20260621
cp $BACKUP/docker-compose.yml /Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC/
cp -r $BACKUP/pg-gateway /Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC/

# 3. รัน docker stack (volumes ยังอยู่ — ข้อมูลเดิมครบ)
cd /Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC
docker compose up -d
```
