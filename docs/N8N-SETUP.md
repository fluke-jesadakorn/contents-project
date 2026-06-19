# n8n Setup

n8n รันที่ `http://localhost:5678` (Phuket Law Firm n8n instance, pid 57491) และ exposed ผ่าน Cloudflare tunnel `https://n8n.jesadakorn.com`

## 1. เข้า n8n UI

```bash
open https://n8n.jesadakorn.com
```

ตอนแรก n8n จะถามให้สร้าง owner account (email + password)

## 2. ตั้ง Environment Variables

n8n อ่านจาก `.env` ของ project Phuket Law Firm (`/Users/fluke/Desktop/Work/PhuketLawFirm/infra/workflow/.env`)

```
# LINE
LINE_CHANNEL_ACCESS_TOKEN=<your token>
LINE_CHANNEL_SECRET=<your secret>

# Ollama (default ใช้ https://ai.jesadakorn.com ผ่าน tunnel)
OLLAMA_URL=https://ai.jesadakorn.com
OLLAMA_EMBED_MODEL=bge-m3
EMBED_DIM=1024

# OpenRouter (free chat)
OPENROUTER_API_KEY=<from https://openrouter.ai/keys>
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_CHAT_MODEL=google/gemma-4-31b-it:free
OPENROUTER_REFERER=https://n8n.jesadakorn.com
OPENROUTER_TITLE=Contract RAG PoC

# n8n API key (สำหรับ programmatic access)
N8N_API_KEY=<JWT token>
```

## 3. Architecture ใหม่ (PGVector Store + EmbeddingsOpenAI)

```
LINE → webhook (contract-rag-line) → IF file? / IF /help?
  ├─ file path: Download from LINE → Extract text → Chunk text → 
  │            Embeddings (bge-m3) → PGVector Insert (contract_vectors) → Reply Success
  ├─ /help path: Reply Help
  └─ text path: Embeddings (bge-m3) → PGVector Search (load mode) → 
                RAG answer (gemma3:1b) → Reply Search
```

**Nodes หลัก:**
- `EmbeddingsOpenAI` (bge-m3 via Ollama) — base URL = `https://ai.jesadakorn.com/v1`
- `Postgres PGVector Store` — insert mode (upload), load mode (search)
- `Code` (RAG answer) — ส่ง context + question → gemma3:1b

**Table schema (`contract_vectors`):**
- `id` UUID pk
- `text` TEXT NOT NULL
- `embedding` vector(1024)
- `metadata` JSONB
- `created_at` TIMESTAMPTZ

## 4. Credentials ที่ต้องตั้งใน n8n UI

| Name | Type | Host | Port | User | Database | Password |
|---|---|---|---|---|---|---|
| Postgres - contracts (Mac local) | postgres | localhost | 5432 | contract | contracts | contractpw |
| Ollama bge-m3 (no auth) | openAiApi | https://ai.jesadakorn.com/v1 | - | - | - | (any) |

## 5. Import Flows

ไปที่ **Workflows → Import from File**:
1. Import `n8n/flows/01-line-bot.json` — flow หลัก
2. **Activate** flow

Webhook path: `contract-rag-line`

## 6. ตั้ง Webhook URL ใน LINE

ดู `docs/LINE-SETUP.md` — เอา Production webhook URL ไปใส่ใน LINE console

URL: `https://n8n.jesadakorn.com/webhook/contract-rag-line`

## 7. ทดสอบ

```bash
# Test search
curl -X POST https://n8n.jesadakorn.com/webhook/contract-rag-line \
  -H "Content-Type: application/json" \
  -d '{"destination":"U","events":[{"type":"message","replyToken":"test","message":{"type":"text","id":"1","text":"ค่าเช่าเดือนเมษายนเท่าไหร่"},"source":{"type":"user","userId":"U"},"timestamp":1718554800000}]}'

# 1. ส่งไฟล์ PDF เข้า LINE bot
# 2. ดู execution ใน n8n
# 3. พิมพ์คำถามเกี่ยวกับสัญญา
```

## 8. ตรวจข้อมูลใน Postgres

```bash
PGPASSWORD=contractpw psql -h localhost -p 5432 -U contract -d contracts -c "SELECT count(*), array_length(string_to_array(embedding::text, ','), 1) as dim FROM contract_vectors;"
PGPASSWORD=contractpw psql -h localhost -p 5432 -U contract -d contracts -c "SELECT id, text, metadata, created_at FROM contract_vectors ORDER BY created_at DESC LIMIT 5;"
```

## Troubleshooting

| อาการ | สาเหตุ | แก้ |
|---|---|---|
| `getaddrinfo ENOTFOUND host.docker.internal` | n8n container ต่อ Mac ไม่ได้ — ใช้ `localhost` แทนเมื่อ n8n รันบน Mac ตรงๆ | เปลี่ยน credential host เป็น `localhost` (n8n process บน Mac) |
| `401 Unauthorized` จาก LINE | token หมดอายุ | rotate LINE token ใน LINE console + update n8n credential |
| `model 'gemma3' not found` (404) | `/api/chat` ใช้ model name เก่า | เปลี่ยน RAG answer ให้ใช้ `/v1/chat/completions` กับ model `gemma3:1b` |
| `vector extension not found` | Postgres ไม่มี pgvector | `brew install pgvector` (ต้องใช้ Postgres 17+ สำหรับ binary ล่าสุด) |
| `ENOTFOUND` หลัง restart | credentials หาย | สร้าง credential ใหม่ใน n8n UI (cluster mode ไม่ persist credentials) |

## หมายเหตุ

- **Postgres 18 บน Mac** ใช้แทน docker Postgres (pgvector binary สำหรับ Postgres 14 หายากแล้ว)
- **ทั้ง contract-n8n (docker) และ Phuket Law Firm n8n (Mac process)** ใช้ port 5678 พร้อมกัน — PLF n8n ครอบ port ก่อน
- Webhook path `contract-rag-line` ถูก register โดย PLF n8n (ที่รัน webhook handler) — ไม่ใช่ docker n8n
- Embeddings node (`EmbeddingsOpenAI`) เป็น **sub-node** ใช้กับ PGVector Store เท่านั้น — ต่อผ่าน `ai_embedding` connection ไม่ใช่ main