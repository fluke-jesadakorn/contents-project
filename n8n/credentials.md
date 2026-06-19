# n8n is hosted externally at https://n8n.jesadakorn.com
# This file documents the connections the n8n flows need.

1. Postgres credential (for direct DB queries from n8n, optional)
   - Host: host.docker.internal OR the public host that resolves to your machine
   - Database: contracts
   - User: contract
   - Password: contractpw
   - Port: 5432

2. HTTP Header Auth credential (for the FastAPI wrapper)
   - Name: Contract-API
   - Header Name: X-API-Key
   - Header Value: local-dev-token (or whatever you set in API_INGEST_TOKEN)

3. LINE Messaging API credential
   - Channel Access Token: from LINE Developers console
   - Channel Secret: from LINE Developers console
