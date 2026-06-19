# Law Digitalize PoC

LINE Messaging API bot ที่:
1. รับไฟล์สัญญา (PDF/DOCX) จาก LINE → chunk + embed → เก็บใน Postgres+pgvector
2. ตอบคำถามเกี่ยวกับสัญญาผ่าน RAG (vector search + LLM)
3. Flow ทั้งหมด orchestrate ใน n8n (self-host ใน docker)

## Stack

| Layer | Tech | Host |
|---|---|---|
| Bot | LINE Messaging API | LINE console |
| Orchestration | **n8n self-hosted** (latest) | Docker container `contract-n8n` |
| Vector DB | Postgres 16 + pgvector | Docker container `contract-postgres` |
| File storage | MinIO (S3-compatible) | Docker container `contract-minio` |
| Embeddings | **Ollama + bge-m3** (1024 dim, multilingual) | Host native, เข้าถึงผ่าน `host.docker.internal:11434` |
| LLM | OpenRouter free — `google/gemma-4-31b-it:free` | API |
| Webhook URL | Cloudflare tunnel `n8n.jesadakorn.com` | https (LINE ต้องการ HTTPS) |

## สถาปัตยกรรม

```
LINE user
   │
   │ POST file/text
   ▼
LINE Messaging API
   │ webhook
   ▼
n8n.jesadakorn.com  ◀─── cloudflared tunnel ──── n8n:5678 (docker)
   │
   │ 1. Extract text  (n8n Extract from File)
   │ 2. Chunk          (n8n Code node JS)
   │ 3. Embed          (Ollama bge-m3 via host.docker.internal:11434)
   │ 4. Store          (Postgres pgvector via postgres:55432)
   │ 5. RAG search     (same)
   │ 6. LLM            (OpenRouter gemma-4-31b-it:free)
   │ 7. Reply          (LINE Reply API)
   ▼
LINE user
```

## โครงสร้างโปรเจกต์

```
Law-digitalize-PoC/
├── docker-compose.yml          # postgres+pgvector + minio + n8n
├── .env.example                # template
├── db/init.sql                 # schema (vector(1024) for bge-m3)
├── n8n/flows/
│   ├── 01-line-upload.json     # import เข้า n8n
│   └── 02-line-search.json
└── docs/
    ├── LINE-SETUP.md
    └── N8N-SETUP.md
```

## เริ่มใช้งานเร็ว

```bash
# 1. Start ทั้งหมด
cp .env.example .env
docker compose up -d

# 2. Verify
docker compose ps
curl http://localhost:5678/healthz

# 3. เข้า n8n UI
open https://n8n.jesadakorn.com

# 4. Setup n8n (first time)
#    - สร้าง owner account
#    - Import flows จาก n8n/flows/
#    - Set env vars ใน n8n UI (Settings > Variables)
#    - สร้าง Postgres credential

# 5. ตั้ง LINE webhook → https://n8n.jesadakorn.com/webhook/line-upload
#    (ดู docs/LINE-SETUP.md)

# 6. Test ส่งไฟล์ PDF เข้า LINE bot
```

ดู `docs/` สำหรับรายละเอียด

## Prerequisites

- Docker + Docker Compose
- Ollama + bge-m3 ติดตั้งบน host (`brew install ollama` + `ollama pull bge-m3`)
- Cloudflare account (zone `jesadakorn.com` ต้อง manage อยู่)
- LINE Official Account + Messaging API channel
- OpenRouter API key (free tier ใช้ได้)
