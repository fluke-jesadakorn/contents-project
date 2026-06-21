# Law Digitalize PoC

LINE Messaging API bot ที่:
1. รับไฟล์สัญญา (PDF/DOCX) จาก LINE → chunk + embed → เก็บใน Postgres+pgvector
2. ตอบคำถามเกี่ยวกับสัญญาผ่าน RAG (vector search + LLM)
3. Flow ทั้งหมด orchestrate ใน n8n (host-native, ไม่ใช้ docker แล้ว)

## Stack (host-native, ย้ายออกจาก docker แล้ว)

| Layer | Tech | Host |
|---|---|---|
| Bot | LINE Messaging API | LINE console |
| Orchestration | **n8n self-hosted** v2.26.8 (npm global, node 22 via nvm) | host native, launchd `com.lawpoc.n8n` |
| Vector DB | Postgres 18 + pgvector | brew `postgresql@18` บน `localhost:5432` |
| n8n DB | Postgres 18 (DB แยก `lawpoc_n8n`) | เดียวกับ contracts |
| File storage | MinIO (S3-compatible) | host native, launchd `com.lawpoc.minio` บน `localhost:9000` |
| Embeddings | **Ollama + bge-m3** (1024 dim, multilingual) | host native `localhost:11434` |
| LLM (chat agent) | **Ollama + qwen3.6:35b-a3b-q4_K_M** | host native `localhost:11434` |
| LLM (legacy) | OpenRouter free — `gemma-4-31b-it:free` | API (used by archived flows only) |
| Webhook URL | Cloudflare tunnel `n8n.jesadakorn.com` | https (LINE ต้องการ HTTPS) |

## Layout

```
/Users/fluke/Desktop/Work/Contents/
├── Law-digitalize-PoC/              # project (flow json, schema, docs)
│   ├── .env                         # project-level reference
│   ├── db/init.sql                  # schema (vector(1024) for bge-m3)
│   ├── n8n/flows/                   # exported workflow JSON
│   └── docs/
└── infra/                           # shared host-native infra
    ├── .env                         # n8n + minio runtime env
    ├── n8n-data/                    # N8N_USER_FOLDER (config, sqlite cache)
    │   └── .n8n/config              # encryptionKey
    ├── minio-data/                  # MinIO data dir
    ├── logs/                        # n8n.log, minio.log
    ├── launchd/                     # com.lawpoc.{n8n,minio}.plist
    ├── scripts/
    │   ├── start-n8n.js             # launchd entrypoint (loads .env)
    │   └── start-n8n.sh             # manual run alternative
    └── backups/                     # migration snapshots + ongoing
```

## สถาปัตยกรรม

```
LINE user
   │
   │ POST file/text
   ▼
LINE Messaging API
   │ webhook
   ▼
n8n.jesadakorn.com  ◀─── cloudflared tunnel ──── n8n:5678 (host native)
   │
    │ 1. Extract text  (n8n Extract from File)
    │ 2. Chunk          (n8n Code node JS)
    │ 3. Embed          (Ollama bge-m3 via localhost:11434)
    │ 4. Store          (Postgres pgvector via localhost:5432)
    │ 5. RAG search     (same)
    │ 6. LLM            (Ollama qwen3.6:35b-a3b-q4_K_M via localhost:11434)
    │ 7. Reply          (LINE Reply API)
   ▼
LINE user
```

## เริ่มใช้งานเร็ว

```bash
# 1. Services start อัตโนมัติตอน boot ผ่าน launchd
#    ตรวจสถานะ:
launchctl list | grep lawpoc

# 2. หากต้องการ start/stop manual:
launchctl kickstart -k gui/$(id -u)/com.lawpoc.n8n
launchctl kickstart -k gui/$(id -u)/com.lawpoc.minio

# 3. ดู log:
tail -f /Users/fluke/Desktop/Work/Contents/infra/logs/n8n.log
tail -f /Users/fluke/Desktop/Work/Contents/infra/logs/minio.log

# 4. เข้า n8n UI:
open https://n8n.jesadakorn.com

# 5. ตรวจ DB:
PGPASSWORD=contractpw psql -h localhost -U contract -d contracts -c "SELECT count(*) FROM contracts;"
PGPASSWORD=n8n_pw psql -h localhost -U n8n_user -d lawpoc_n8n -c "SELECT name, active FROM workflow_entity;"

# 6. ตรวจ MinIO:
mc ls local/epsx-contracts
```

ดู `docs/` สำหรับรายละเอียด LINE setup + n8n setup

## Prerequisites

- brew + `postgresql@18`, `pgvector`, `minio`, `minio-mc`, `nvm`
- node 22 (via nvm) — node 26 ไม่รองรับ n8n 2.26.8 (isolated-vm native build fail)
- `npm install -g n8n@2.26.8` (installed under nvm node 22)
- Ollama + bge-m3 ติดตั้งบน host (`brew install ollama` + `ollama pull bge-m3`)
- Cloudflare account (zone `jesadakorn.com` ต้อง manage อยู่) + cloudflared tunnel
- LINE Official Account + Messaging API channel
- OpenRouter API key (free tier ใช้ได้)
- macOS: `/Users/fluke/.nvm/versions/node/v22.23.0/bin/node` ต้องได้รับ Full Disk Access (System Settings > Privacy & Security) เพื่อให้ launchd เข้าถึง `~/Desktop/` ได้
