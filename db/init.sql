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
    file_mime       TEXT,
    file_data       BYTEA,
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

-- Existing PoC databases may have been created before inline file preview was
-- added. Keep this migration idempotent so re-running db/init.sql is safe.
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS file_mime TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS file_data BYTEA;

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

-- ===== Per-page image storage =====
-- Stores the rendered page image (PDF page → JPEG @ 100 DPI from ocr-service)
-- alongside the OCR'd chunks. Used for visual retrieval in admin UI ("ดู"
-- modal thumbnail) and as a permanent visual record of the source page even
-- if the original PDF in `contracts.file_data` is ever purged.
-- PoC: image-only, no CLIP embedding — search stays text-based via bge-m3.
CREATE TABLE IF NOT EXISTS contract_pages (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id  UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    page_index   INT  NOT NULL,          -- 0-based, matches ocr-service /vision `pages[].page_index`
    image_data   BYTEA NOT NULL,          -- JPEG bytes (~30-80KB per page @ 100 DPI)
    image_mime   TEXT NOT NULL DEFAULT 'image/jpeg',
    bytes        INT,                    -- size in bytes (for stats / admin UI)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (contract_id, page_index)
);

CREATE INDEX IF NOT EXISTS idx_pages_contract ON contract_pages (contract_id);

-- ===== Doc registry helpers =====
-- Sequence generator for `doc_no` (used by 03-docs-hub for INSERT when client
-- didn't supply a doc_no). Format: DOC-YYYYMMDD-NNNN, monotonically incrementing.
-- Uses pg_advisory_xact_lock to prevent race under concurrent inserts.
CREATE OR REPLACE FUNCTION next_doc_seq() RETURNS TEXT AS $$
DECLARE
    today TEXT := to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD');
    seq   INT;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('doc_no_seq'));
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
