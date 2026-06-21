-- ===== Init schema for contract RAG =====
-- Apply manually: psql -h localhost -U contract -d contracts -f db/init.sql
-- Embedding dim = 1024 (BAAI/bge-m3 via local Ollama, localhost:11434)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;

-- Main contract metadata table
CREATE TABLE IF NOT EXISTS contracts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    line_user_id    TEXT,
    line_group_id   TEXT,
    line_message_id TEXT,
    file_name       TEXT NOT NULL,
    file_type       TEXT,
    storage_bucket  TEXT,
    storage_path    TEXT,
    size_bytes      BIGINT,
    chunk_count     INT DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'pending',  -- pending | ready | failed
    error_message   TEXT,
    uploaded_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Migration: doc-registry fields (added 2026-06-14)
    doc_no          TEXT,
    category        TEXT,
    source          TEXT,
    metadata        JSONB,
    updated_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_contracts_line_user ON contracts (line_user_id);
CREATE INDEX IF NOT EXISTS idx_contracts_status    ON contracts (status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_contracts_doc_no ON contracts (doc_no) WHERE doc_no IS NOT NULL;

-- Vector chunks table
CREATE TABLE IF NOT EXISTS contract_chunks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id     UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    chunk_index     INT NOT NULL,
    content         TEXT NOT NULL,
    token_count     INT,
    embedding       vector(1024),  -- bge-m3
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chunks_contract ON contract_chunks (contract_id);

-- ivfflat index — uncomment after at least 100 rows are inserted
-- (or use HNSW instead — pgvector 0.7+ — for better recall/latency tradeoff)
-- CREATE INDEX IF NOT EXISTS idx_chunks_embedding ON contract_chunks
--   USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ===== Doc registry helpers =====
-- Sequence generator for `doc_no` (used by 03-docs-hub for INSERT when client
-- didn't supply a doc_no). Format: DOC-YYYYMMDD-NNNN, monotonically incrementing.
CREATE OR REPLACE FUNCTION next_doc_seq() RETURNS TEXT AS $$
DECLARE
    today TEXT := to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD');
    seq   INT;
BEGIN
    SELECT COALESCE(MAX(
        CAST(substring(doc_no FROM 'DOC-[0-9]{8}-([0-9]+)') AS INT)
    ), 0) + 1
    INTO seq
    FROM contracts
    WHERE doc_no LIKE 'DOC-' || today || '-%';

    RETURN 'DOC-' || today || '-' || lpad(seq::TEXT, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- ===== Auto-update updated_at on row change =====
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_contracts_touch ON contracts;
CREATE TRIGGER trg_contracts_touch
    BEFORE UPDATE ON contracts
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ===== Concurrent-safe doc_no (optional alternative to next_doc_seq) =====
-- next_doc_seq() uses MAX()+1 which races under concurrent inserts.
-- For production, prefer this pattern instead:
--   BEGIN;
--   SELECT pg_advisory_xact_lock(hashtext('doc_no_seq'));
--   SELECT next_doc_seq();  -- or use a real SEQUENCE
--   COMMIT;
