# AGENTS.md

LINE bot PoC: รับสัญญา (PDF/DOCX) จาก LINE → chunk + embed → เก็บใน Postgres+pgvector → RAG Q&A + admin CRUD UI. Orchestration ทั้งหมดอยู่ใน n8n (self-host); embedding ผ่าน Ollama bge-m3; LLM ผ่าน OpenRouter.

## Setup commands

- Start stack:        `docker compose up -d` (postgres+pgvector, minio, n8n, pg-gateway)
- Verify stack:       `docker compose ps && curl http://localhost:5678/healthz`
- Open n8n:           `https://n8n.jesadakorn.com` (Cloudflare tunnel)
- Import flows:       `n8n/flows/03-docs-hub.json` + `04-docs-admin.json` (n8n UI → Workflows → Import)
- DB schema:          `psql -h localhost -p 5432 -U contract -d contracts -f db/init.sql`
- Generate n8n backup: `curl -H "X-N8N-API-KEY: $N8N_API_KEY" http://localhost:5678/rest/workflows/<id>` → save to `n8n/flows/<name>.json`
- Edit flow (no UI):  update `workflow_entity.nodes/connections` + new `versionId` in `workflow_history` + `workflow_published_version` + activate via REST

## Project layout

- `docker-compose.yml` — postgres+pgvector, minio, n8n, pg-gateway (4 services on `contract-net` 172.30.0.0/24)
- `db/init.sql` — schema: `contracts`, `contract_chunks` (vector(1024) for bge-m3), trigram + ivfflat indexes
- `pg-gateway/` — FastAPI HTTP wrapper for n8n Postgres queries (workaround for n8n 2.26.4 DNS bug)
- `n8n/flows/` — exported workflow JSON. Active: `03-docs-hub.json` (78KB, 71 nodes), `04-docs-admin.json`
- `n8n/credentials.md`, `n8n/flows/CREDENTIAL-AUDIT.md` — credential IDs, flow wiring reference
- `docs/LINE-SETUP.md`, `docs/N8N-SETUP.md` — operator runbooks for LINE channel + n8n env

## Code style

- **n8n flows**: prefix node names with the subsystem (`LINE:`, `AI:`, `PG:`, `LLM:`); Code node JS uses `asyncCode: true`; SQL built dynamically uses dollar-quoting `$tag$...$tag$` for content + `'...'` escape for identifiers
- **SQL**: parameters via Postgres node's `queryReplacement` array, NOT f-string interpolation; always escape single quotes in dynamic content
- **Python** (pg-gateway): minimal FastAPI, no framework magic; raw psycopg2 cursor, env-driven config
- **Commits**: conventional (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`); body explains WHY not WHAT
- **Don't add** to AGENTS.md anything agent-specific; this file is shared

## Testing instructions

- **End-to-end**: send PDF to LINE OA → check `n8n_executions` + `contracts` row + `contract_chunks` count
- **Verify rows**: `PGPASSWORD=contractpw psql -h localhost -U contract -d contracts -c "SELECT id, file_name, status, octet_length(file_data), chunk_count FROM contracts ORDER BY uploaded_at DESC LIMIT 5;"`
- **Verify preview**: `curl -I http://localhost:5678/webhook/admin-file?id=<contract_id>` (200, `Content-Type: application/pdf`)
- **Admin UI**: `https://n8n.jesadakorn.com/webhook/docs-admin-ui` — test dark/light toggle, "ดู" modal tabs (PDF/chunks/metadata)
- **No automated tests** — verification is manual + DB inspection
- **Backfill rule**: if `file_data` is NULL, the file was uploaded before the save flow was wired; use `pg_read_binary_file('/path/to/sample.pdf')` to backfill (same size, not real content)

## PR & commit conventions

- Single branch: `main` (no remote yet — this is a local PoC repo)
- Commit message: conventional commits with Thai-friendly body when relevant
- Snapshot before edit: `pg_dump --schema-only contracts > /tmp/schema-pre.sql` before schema changes
- After n8n flow edit: export → save to `n8n/flows/<name>.json` → commit

## Security

- **`.env` is gitignored** — never commit; use `.env.example` for the template
- **LINE access tokens**: long-lived tokens are sensitive; rotate from LINE console if leaked
- **OpenRouter API key**: free tier rate-limited; cache responses in production
- **Ollama bge-m3**: local embedding; no data leaves the host unless proxied via Cloudflare tunnel
- **Postgres credential in n8n**: stored encrypted in n8n DB; rotation requires n8n API update
- **No PII logging** in flow Code nodes; contract_chunks `content` is user document text, treat as confidential
- See `n8n/flows/CREDENTIAL-AUDIT.md` for credential ID inventory

## Architecture (one-liner per service)

```
LINE user → LINE OA → cloudflared tunnel → n8n:5678
                                          ↓
                            [Smart Router] → file? → extract + chunk + embed (Ollama bge-m3) → PG
                                          ↓
                                          text? → AI agent (Ollama qwen3.6) → RAG search (PG) → reply
                                          ↓
                            Admin UI: docs-admin-ui → n8n → PG (CRUD + file preview)
```

For detailed wiring, see `n8n/flows/CREDENTIAL-AUDIT.md` and individual flow JSON files.
