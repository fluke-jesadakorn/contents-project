--
-- PostgreSQL database dump
--

\restrict uYIDfRzYZxarE3FqlLFrEZvEiGXwqHqhRP5r7FhLMWpcN1qpMfmGcnhMpFohQXb

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg12+1)
-- Dumped by pg_dump version 18.4 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: next_doc_seq(); Type: FUNCTION; Schema: public; Owner: contract
--

CREATE FUNCTION public.next_doc_seq() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    today TEXT := to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD');
    seq   INT;
BEGIN
    SELECT COALESCE(MAX(CAST(substring(doc_no FROM 'DOC-[0-9]{8}-([0-9]+)') AS INT)), 0) + 1
    INTO seq
    FROM contracts
    WHERE doc_no LIKE 'DOC-' || today || '-%';
    RETURN 'DOC-' || today || '-' || lpad(seq::TEXT, 4, '0');
END;
$$;


ALTER FUNCTION public.next_doc_seq() OWNER TO contract;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: contract_chunks; Type: TABLE; Schema: public; Owner: contract
--

CREATE TABLE public.contract_chunks (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    contract_id uuid NOT NULL,
    chunk_index integer NOT NULL,
    content text NOT NULL,
    token_count integer,
    embedding public.vector(1024),
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.contract_chunks OWNER TO contract;

--
-- Name: contracts; Type: TABLE; Schema: public; Owner: contract
--

CREATE TABLE public.contracts (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    line_user_id text,
    line_group_id text,
    line_message_id text,
    file_name text NOT NULL,
    file_type text,
    storage_bucket text,
    storage_path text,
    size_bytes bigint,
    chunk_count integer DEFAULT 0,
    status text DEFAULT 'pending'::text NOT NULL,
    error_message text,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    doc_no text,
    category text,
    source text,
    metadata jsonb,
    updated_at timestamp with time zone
);


ALTER TABLE public.contracts OWNER TO contract;

--
-- Name: contract_chunks contract_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: contract
--

ALTER TABLE ONLY public.contract_chunks
    ADD CONSTRAINT contract_chunks_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: contract
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: idx_chunks_contract; Type: INDEX; Schema: public; Owner: contract
--

CREATE INDEX idx_chunks_contract ON public.contract_chunks USING btree (contract_id);


--
-- Name: idx_contracts_doc_no; Type: INDEX; Schema: public; Owner: contract
--

CREATE UNIQUE INDEX idx_contracts_doc_no ON public.contracts USING btree (doc_no) WHERE (doc_no IS NOT NULL);


--
-- Name: idx_contracts_line_user; Type: INDEX; Schema: public; Owner: contract
--

CREATE INDEX idx_contracts_line_user ON public.contracts USING btree (line_user_id);


--
-- Name: idx_contracts_status; Type: INDEX; Schema: public; Owner: contract
--

CREATE INDEX idx_contracts_status ON public.contracts USING btree (status);


--
-- Name: contract_chunks contract_chunks_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: contract
--

ALTER TABLE ONLY public.contract_chunks
    ADD CONSTRAINT contract_chunks_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict uYIDfRzYZxarE3FqlLFrEZvEiGXwqHqhRP5r7FhLMWpcN1qpMfmGcnhMpFohQXb

