# Flow 03 - Docs Hub — credential + flow audit

**Last updated:** 2026-06-18 (53 nodes, smart routing with 4 tools)

## Credentials

### httpHeaderAuth (LINE Bearer Auth)
- ID: `LNHDR8F94CE3AA25E4B8E823C70`
- Data: `{"name":"Authorization","value":"Bearer <token>"}`
- **Required on:** `LINE Download from LINE`, `LINE Reply Success`, `LINE Reply Error`, `LINE: Reply Non-File`, `AI: Reply Text`, `AI: Send Reply`

### postgres (PG Contracts - localhost:5432)
- ID: `regb87eec1e08a5cce3`
- Data: `{"host":"localhost","port":5432,"database":"contracts","user":"contract","password":"contractpw","ssl":"disable"}`
- **Required on:** `LINE Register Start`, `LINE Insert contract row`, `LINE Insert chunks`, `LINE Register Done`, `AI: List Contracts`, `AI: Get Stats`

## Smart routing flow

```
LINE: Is file? (Switch)
├── is_file → [file upload pipeline: Download → Extract → Chunk → Embed → Combine → Insert contract → Insert chunks → Reply Success]
└── not_file → AI Agent (Ollama qwen3.6) → Parse AI Response
                                                ↓
                                          AI Route Switch (4 outputs)
                                          ├── search → AI: Call Vector Search → Build Flex Card → AI: Send Reply
                                          ├── list → AI: List Contracts → AI: Format List → AI: Reply Text
                                          ├── stats → AI: Get Stats → AI: Format Stats → AI: Reply Text
                                          └── text → AI: Reply Text
                                                                       ↓
                                                                  Format Response
```

## AI tools (qwen3.6:35b with system prompt)

| Tool | Args | When to use |
|------|------|-------------|
| `search_documents` | `query, limit=5` | "หา/ค้น/ค้นหา [keyword]" — semantic vector search |
| `list_documents` | `filter="", limit=10` | "กี่ฉบับ/list/ทั้งหมด/อันไหนบ้าง" — registry list |
| `get_stats` | (none) | "สรุป/ภาพรวม/สถิติ/สถานะ" — count + breakdown |
| (none) | — | greeting/chat/capabilities question |

## contracts schema requirements

```sql
-- Required columns (added via migration)
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS doc_no TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS source TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS metadata JSONB;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS idx_contracts_doc_no ON contracts (doc_no) WHERE doc_no IS NOT NULL;

-- Sequence function
CREATE OR REPLACE FUNCTION next_doc_seq() RETURNS TEXT AS $$ ... $$ LANGUAGE plpgsql;
```

## Startup scripts (run on Mac reboot)

```bash
# 1) Postgres already auto-starts via brew services
# 2) n8n
cd /Users/fluke/Desktop/Work/PhuketLawFirm/infra/workflow
nohup /tmp/start-plf-n8n.sh > /tmp/n8n.log 2>&1 &

# 3) Cloudflared
nohup /opt/homebrew/bin/cloudflared --config /Users/fluke/.cloudflared/config-n8n.yml \
  tunnel run b8f4ccf5-67de-4bfa-b292-7641ad185006 > /tmp/cloudflared.log 2>&1 &
```
