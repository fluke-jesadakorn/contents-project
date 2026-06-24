# n8n is hosted at https://n8n.jesadakorn.com (host-native, launchd `com.lawpoc.n8n`)
# This file documents the credentials the active n8n flows need.
# Active flows: 03-docs-hub.json, 04-docs-admin.json
# Archived (in n8n/flows/archive/): 01-line-bot, 01-line-upload, 02-doc-registry, 02-line-search

1. Postgres credential (for direct DB queries from n8n)
   - Name: PG Contracts - localhost:5432
   - Type: postgres
   - Host: localhost
   - Port: 5432
   - Database: contracts
   - User: contract
   - Password: contractpw
   - Used by: 03-docs-hub (LINE insert + AI tools), 04-docs-admin (CRUD + stats)

2. HTTP Header Auth credential (LINE Reply/Download API)
   - Name: LINE Bearer Auth
   - Type: httpHeaderAuth
   - Header Name: Authorization
   - Header Value: Bearer <LINE_CHANNEL_ACCESS_TOKEN>
   - Used by: 03-docs-hub (LINE nodes)

3. S3 credential (MinIO object storage)
   - Name: MinIO Contracts
   - Type: s3
   - Endpoint: localhost:9000
   - Region: us-east-1
   - Access Key ID: minioadmin
   - Secret Access Key: minioadmin
   - Force Path Style: true
   - Used by: 03-docs-hub (file upload after chunk+embed success)

# Note: OpenRouter API key (in infra/.env) is not used by active flows.
# Active flows use Ollama for both embedding (bge-m3) and chat agent (qwen3.6:35b-a3b-q4_K_M).
