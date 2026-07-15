--
-- PostgreSQL database dump
--

\restrict maCD2TdT5Jf9wMncr685mrkZqsv9DR5979dhoJhljqPPScTrboHHOoeWIfJ7ljR

-- Dumped from database version 18.4 (Homebrew)
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
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: increment_workflow_version(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_workflow_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
			BEGIN
				IF NEW."versionCounter" IS NOT DISTINCT FROM OLD."versionCounter"
					AND (NEW."nodes"::text IS DISTINCT FROM OLD."nodes"::text
						OR NEW."settings"::text IS DISTINCT FROM OLD."settings"::text) THEN
					NEW."versionCounter" = OLD."versionCounter" + 1;
				END IF;
				RETURN NEW;
			END;
			$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agent_checkpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_checkpoints (
    "runId" character varying(255) NOT NULL,
    "agentId" character varying(255),
    state text,
    expired boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: agent_execution; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_execution (
    id character varying(36) NOT NULL,
    "threadId" character varying(128) NOT NULL,
    status character varying(16) NOT NULL,
    "startedAt" timestamp(3) with time zone,
    "stoppedAt" timestamp(3) with time zone,
    duration integer DEFAULT 0 NOT NULL,
    "userMessage" text NOT NULL,
    "assistantResponse" text NOT NULL,
    model character varying(255),
    "promptTokens" integer,
    "completionTokens" integer,
    "totalTokens" integer,
    cost double precision,
    "toolCalls" json,
    timeline json,
    error text,
    "hitlStatus" character varying(16),
    source character varying(32),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_agent_execution_hitlStatus" CHECK ((("hitlStatus")::text = ANY (ARRAY[('suspended'::character varying)::text, ('resumed'::character varying)::text]))),
    CONSTRAINT "CHK_agent_execution_status" CHECK (((status)::text = ANY (ARRAY[('success'::character varying)::text, ('error'::character varying)::text])))
);


--
-- Name: agent_execution_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_execution_threads (
    id character varying(128) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    "agentName" character varying(255) NOT NULL,
    "projectId" character varying(255) NOT NULL,
    "sessionNumber" integer DEFAULT 0 NOT NULL,
    "totalPromptTokens" integer DEFAULT 0 NOT NULL,
    "totalCompletionTokens" integer DEFAULT 0 NOT NULL,
    "totalCost" double precision DEFAULT 0 NOT NULL,
    "totalDuration" integer DEFAULT 0 NOT NULL,
    title character varying(255),
    emoji character varying(8),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "taskId" character varying(32),
    "taskVersionId" character varying(36),
    "parentThreadId" character varying(128),
    "parentAgentId" character varying(36)
);


--
-- Name: COLUMN agent_execution_threads."taskId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_execution_threads."taskId" IS 'Published task ID that triggered this session; not an FK because published runs can outlive draft task definition rows';


--
-- Name: COLUMN agent_execution_threads."taskVersionId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_execution_threads."taskVersionId" IS 'Published agent_history version that supplied the task snapshot';


--
-- Name: COLUMN agent_execution_threads."parentThreadId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_execution_threads."parentThreadId" IS 'Parent session thread id that delegated this subagent run.';


--
-- Name: COLUMN agent_execution_threads."parentAgentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_execution_threads."parentAgentId" IS 'Saved agent id of the parent that delegated this subagent run.';


--
-- Name: agent_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_files (
    id character varying(16) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    "binaryDataId" text NOT NULL,
    "fileName" character varying(255) NOT NULL,
    "mimeType" character varying(255) NOT NULL,
    "fileSizeBytes" integer NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agent_files.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_files.id IS 'Application-generated n8n nano ID';


--
-- Name: COLUMN agent_files."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_files."agentId" IS 'Agent that owns this uploaded file';


--
-- Name: COLUMN agent_files."binaryDataId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_files."binaryDataId" IS 'Opaque BinaryDataService reference (mode-prefixed, e.g. "filesystem-v2:<uuid>"); not an FK to binary_data, which only has rows in DB storage mode';


--
-- Name: COLUMN agent_files."fileSizeBytes"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_files."fileSizeBytes" IS 'Uploaded file size in bytes';


--
-- Name: agent_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_history (
    "versionId" character varying(36) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    schema json,
    tools json,
    skills json,
    "publishedById" uuid,
    author character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agent_history.schema; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_history.schema IS 'Frozen snapshot of the published AgentJsonConfig';


--
-- Name: COLUMN agent_history.tools; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_history.tools IS 'Frozen map of `toolId → { code, descriptor }` at publish time';


--
-- Name: COLUMN agent_history.skills; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_history.skills IS 'Frozen map of `skillId → AgentSkill` at publish time';


--
-- Name: agent_task_definition; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_task_definition (
    id character varying(32) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    objective text NOT NULL,
    "cronExpression" character varying(128) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agent_task_definition.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_definition.id IS 'Application-generated task ID referenced from agent JSON config';


--
-- Name: COLUMN agent_task_definition."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_definition."agentId" IS 'Owning agent; task definitions are deleted when the agent is deleted';


--
-- Name: COLUMN agent_task_definition.objective; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_definition.objective IS 'User-authored instruction sent to the agent when this task runs';


--
-- Name: COLUMN agent_task_definition."cronExpression"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_definition."cronExpression" IS 'Cron schedule evaluated using the instance timezone';


--
-- Name: agent_task_run_lock; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_task_run_lock (
    "agentId" character varying(36) NOT NULL,
    "taskId" character varying(32) NOT NULL,
    "holderId" uuid NOT NULL,
    "heldUntil" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agent_task_run_lock."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_run_lock."agentId" IS 'Published agent whose scheduled task run is locked';


--
-- Name: COLUMN agent_task_run_lock."taskId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_run_lock."taskId" IS 'Published task ID whose scheduled run is locked';


--
-- Name: COLUMN agent_task_run_lock."holderId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_run_lock."holderId" IS 'Ephemeral lock owner token generated by the running main';


--
-- Name: COLUMN agent_task_run_lock."heldUntil"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_run_lock."heldUntil" IS 'Time after which another main can claim this task run lock';


--
-- Name: agent_task_snapshot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_task_snapshot (
    "versionId" character varying(36) NOT NULL,
    "taskId" character varying(32) NOT NULL,
    enabled boolean NOT NULL,
    name character varying(128) NOT NULL,
    objective text NOT NULL,
    "cronExpression" character varying(128) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agent_task_snapshot."versionId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_snapshot."versionId" IS 'Published agent_history version this task snapshot belongs to';


--
-- Name: COLUMN agent_task_snapshot."taskId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_snapshot."taskId" IS 'Stable task ID referenced from the published agent JSON config';


--
-- Name: COLUMN agent_task_snapshot.enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_snapshot.enabled IS 'Published enabled state for this task at publish time';


--
-- Name: COLUMN agent_task_snapshot.objective; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_snapshot.objective IS 'User-authored instruction sent to the agent when this task runs';


--
-- Name: COLUMN agent_task_snapshot."cronExpression"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_snapshot."cronExpression" IS 'Cron schedule evaluated using the instance timezone';


--
-- Name: agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    description character varying(512),
    "projectId" character varying(255) NOT NULL,
    integrations json DEFAULT '[]'::json NOT NULL,
    schema json,
    tools json DEFAULT '{}'::json NOT NULL,
    skills json DEFAULT '{}'::json NOT NULL,
    "versionId" character varying(36),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "activeVersionId" character varying(36)
);


--
-- Name: agents_memory_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_memory_entries (
    id character varying(36) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    "resourceId" character varying(255) NOT NULL,
    content text NOT NULL,
    "contentHash" character varying(64) NOT NULL,
    status character varying(16) NOT NULL,
    "supersededBy" character varying(36),
    "embeddingModel" character varying(128),
    embedding json,
    metadata json,
    "lastSeenAt" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_agents_memory_entries_status" CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('superseded'::character varying)::text, ('dropped'::character varying)::text])))
);


--
-- Name: COLUMN agents_memory_entries."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries."agentId" IS 'Agent that owns this episodic memory entry';


--
-- Name: COLUMN agents_memory_entries."resourceId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries."resourceId" IS 'agents_resources.id partition used for episodic recall scope';


--
-- Name: COLUMN agents_memory_entries."supersededBy"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries."supersededBy" IS 'Self-reference to replacement memory entry';


--
-- Name: COLUMN agents_memory_entries."embeddingModel"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries."embeddingModel" IS 'Embedding model used to produce embedding';


--
-- Name: COLUMN agents_memory_entries.embedding; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries.embedding IS 'Embedding vector for episodic recall';


--
-- Name: COLUMN agents_memory_entries.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries.metadata IS 'Optional system metadata for ranking and debugging';


--
-- Name: COLUMN agents_memory_entries."lastSeenAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entries."lastSeenAt" IS 'Last time equivalent content was observed; updatedAt tracks row mutation time';


--
-- Name: agents_memory_entry_cursors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_memory_entry_cursors (
    "agentId" character varying(36) NOT NULL,
    "observationScopeId" character varying(255) NOT NULL,
    "lastIndexedObservationId" character varying(36) NOT NULL,
    "lastIndexedObservationCreatedAt" timestamp(3) with time zone CONSTRAINT "agents_memory_entry_cursors_lastIndexedObservationCrea_not_null" NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agents_memory_entry_cursors."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_cursors."agentId" IS 'Agent that owns this cursor';


--
-- Name: COLUMN agents_memory_entry_cursors."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_cursors."observationScopeId" IS 'agents_threads.id source stream indexed into episodic memory';


--
-- Name: COLUMN agents_memory_entry_cursors."lastIndexedObservationId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_cursors."lastIndexedObservationId" IS 'Last observation-log row indexed into episodic memory';


--
-- Name: COLUMN agents_memory_entry_cursors."lastIndexedObservationCreatedAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_cursors."lastIndexedObservationCreatedAt" IS 'Creation timestamp for the last indexed observation-log row';


--
-- Name: agents_memory_entry_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_memory_entry_locks (
    "agentId" character varying(36) NOT NULL,
    "resourceId" character varying(255) NOT NULL,
    "holderId" character varying(64) NOT NULL,
    "heldUntil" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agents_memory_entry_locks."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_locks."agentId" IS 'Agent that owns this lock';


--
-- Name: COLUMN agents_memory_entry_locks."resourceId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_locks."resourceId" IS 'agents_resources.id partition locked for episodic indexing';


--
-- Name: COLUMN agents_memory_entry_locks."holderId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_locks."holderId" IS 'Ephemeral background-task lock owner token';


--
-- Name: agents_memory_entry_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_memory_entry_sources (
    id character varying(36) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    "memoryEntryId" character varying(36) NOT NULL,
    "observationId" character varying(36) NOT NULL,
    "threadId" character varying(255) NOT NULL,
    "evidenceHash" character varying(64) NOT NULL,
    "evidenceText" text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agents_memory_entry_sources."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_sources."agentId" IS 'Agent that owns the linked episodic memory entry source';


--
-- Name: COLUMN agents_memory_entry_sources."memoryEntryId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_sources."memoryEntryId" IS 'Episodic memory entry linked to this source evidence';


--
-- Name: COLUMN agents_memory_entry_sources."observationId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_sources."observationId" IS 'Observation-log row used as source evidence';


--
-- Name: COLUMN agents_memory_entry_sources."threadId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_sources."threadId" IS 'Source conversation thread that produced the linked observation';


--
-- Name: COLUMN agents_memory_entry_sources."evidenceHash"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_sources."evidenceHash" IS 'Bounded hash used to deduplicate exact evidence links';


--
-- Name: COLUMN agents_memory_entry_sources."evidenceText"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_memory_entry_sources."evidenceText" IS 'Exact source evidence text from the observation, not recall scope';


--
-- Name: agents_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_messages (
    id character varying(36) NOT NULL,
    "threadId" character varying(255) NOT NULL,
    "resourceId" character varying(255) NOT NULL,
    role character varying(36) NOT NULL,
    type character varying(36),
    content json NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: agents_observation_cursors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_observation_cursors (
    "agentId" character varying(36) NOT NULL,
    "observationScopeId" character varying(255) NOT NULL,
    "lastObservedMessageId" character varying(36) NOT NULL,
    "lastObservedAt" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN agents_observation_cursors."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observation_cursors."agentId" IS 'Agent that owns this cursor';


--
-- Name: COLUMN agents_observation_cursors."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observation_cursors."observationScopeId" IS 'agents_threads.id source stream checkpointed by this cursor';


--
-- Name: agents_observation_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_observation_locks (
    "agentId" character varying(36) NOT NULL,
    "observationScopeId" character varying(255) NOT NULL,
    "taskKind" character varying(20) NOT NULL,
    "holderId" character varying(64) NOT NULL,
    "heldUntil" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_agents_observation_locks_taskKind" CHECK ((("taskKind")::text = ANY (ARRAY[('observer'::character varying)::text, ('reflector'::character varying)::text])))
);


--
-- Name: COLUMN agents_observation_locks."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observation_locks."agentId" IS 'Agent that owns this lock';


--
-- Name: COLUMN agents_observation_locks."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observation_locks."observationScopeId" IS 'agents_threads.id source stream locked for observation tasks';


--
-- Name: COLUMN agents_observation_locks."holderId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observation_locks."holderId" IS 'Ephemeral background-task lock owner token, not a user ID';


--
-- Name: agents_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_observations (
    id character varying(36) NOT NULL,
    "agentId" character varying(36) NOT NULL,
    "observationScopeId" character varying(255) NOT NULL,
    marker character varying(16) NOT NULL,
    text text NOT NULL,
    "parentId" character varying(36),
    "tokenCount" integer DEFAULT 0 NOT NULL,
    status character varying(16) NOT NULL,
    "supersededBy" character varying(36),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_agents_observations_marker" CHECK (((marker)::text = ANY (ARRAY[('critical'::character varying)::text, ('important'::character varying)::text, ('info'::character varying)::text, ('completion'::character varying)::text]))),
    CONSTRAINT "CHK_agents_observations_status" CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('superseded'::character varying)::text, ('dropped'::character varying)::text])))
);


--
-- Name: COLUMN agents_observations.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observations.id IS 'Application-generated n8n string ID, not a database UUID';


--
-- Name: COLUMN agents_observations."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observations."agentId" IS 'Agent that owns this observation row';


--
-- Name: COLUMN agents_observations."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agents_observations."observationScopeId" IS 'agents_threads.id source stream for this observation log';


--
-- Name: agents_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_resources (
    id character varying(255) NOT NULL,
    metadata text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: agents_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents_threads (
    id character varying(128) NOT NULL,
    "resourceId" character varying(255) NOT NULL,
    title character varying(255),
    metadata text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: ai_builder_temporary_workflow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_builder_temporary_workflow (
    "workflowId" character varying(36) NOT NULL,
    "threadId" uuid NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: annotation_tag_entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.annotation_tag_entity (
    id character varying(16) NOT NULL,
    name character varying(24) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: auth_identity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_identity (
    "userId" uuid,
    "providerId" character varying(255) NOT NULL,
    "providerType" character varying(32) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: auth_provider_sync_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_provider_sync_history (
    id integer NOT NULL,
    "providerType" character varying(32) NOT NULL,
    "runMode" text NOT NULL,
    status text NOT NULL,
    "startedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "endedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    scanned integer NOT NULL,
    created integer NOT NULL,
    updated integer NOT NULL,
    disabled integer NOT NULL,
    error text
);


--
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_provider_sync_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_provider_sync_history_id_seq OWNED BY public.auth_provider_sync_history.id;


--
-- Name: binary_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.binary_data (
    "fileId" uuid NOT NULL,
    "sourceType" character varying(50) NOT NULL,
    "sourceId" character varying(255) NOT NULL,
    data bytea NOT NULL,
    "mimeType" character varying(255),
    "fileName" character varying(255),
    "fileSize" integer NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_binary_data_sourceType" CHECK ((("sourceType")::text = ANY (ARRAY[('execution'::character varying)::text, ('chat_message_attachment'::character varying)::text, ('agent_file'::character varying)::text])))
);


--
-- Name: COLUMN binary_data."sourceType"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.binary_data."sourceType" IS 'Source the file belongs to, e.g. ''execution''';


--
-- Name: COLUMN binary_data."sourceId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.binary_data."sourceId" IS 'ID of the source, e.g. execution ID';


--
-- Name: COLUMN binary_data.data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.binary_data.data IS 'Raw, not base64 encoded';


--
-- Name: COLUMN binary_data."fileSize"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.binary_data."fileSize" IS 'In bytes';


--
-- Name: chat_hub_agent_tools; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_hub_agent_tools (
    "agentId" uuid NOT NULL,
    "toolId" uuid NOT NULL
);


--
-- Name: chat_hub_agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_hub_agents (
    id uuid NOT NULL,
    name character varying(256) NOT NULL,
    description character varying(512),
    "systemPrompt" text NOT NULL,
    "ownerId" uuid NOT NULL,
    "credentialId" character varying(36),
    provider character varying(16) NOT NULL,
    model character varying(64) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    icon json,
    files json DEFAULT '[]'::json NOT NULL,
    "suggestedPrompts" json DEFAULT '[]'::json NOT NULL
);


--
-- Name: COLUMN chat_hub_agents.provider; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_agents.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- Name: COLUMN chat_hub_agents.model; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_agents.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- Name: chat_hub_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_hub_messages (
    id uuid NOT NULL,
    "sessionId" uuid NOT NULL,
    "previousMessageId" uuid,
    "revisionOfMessageId" uuid,
    "retryOfMessageId" uuid,
    type character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    content text NOT NULL,
    provider character varying(16),
    model character varying(256),
    "workflowId" character varying(36),
    "executionId" integer,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "agentId" uuid,
    status character varying(16) DEFAULT 'success'::character varying NOT NULL,
    attachments json
);


--
-- Name: COLUMN chat_hub_messages.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_messages.type IS 'ChatHubMessageType enum: "human", "ai", "system", "tool", "generic"';


--
-- Name: COLUMN chat_hub_messages.provider; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_messages.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- Name: COLUMN chat_hub_messages.model; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_messages.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- Name: COLUMN chat_hub_messages."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_messages."agentId" IS 'ID of the custom agent (if provider is "custom-agent")';


--
-- Name: COLUMN chat_hub_messages.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_messages.status IS 'ChatHubMessageStatus enum, eg. "success", "error", "running", "cancelled"';


--
-- Name: COLUMN chat_hub_messages.attachments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_messages.attachments IS 'File attachments for the message (if any), stored as JSON. Files are stored as base64-encoded data URLs.';


--
-- Name: chat_hub_session_tools; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_hub_session_tools (
    "sessionId" uuid NOT NULL,
    "toolId" uuid NOT NULL
);


--
-- Name: chat_hub_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_hub_sessions (
    id uuid NOT NULL,
    title character varying(256) NOT NULL,
    "ownerId" uuid NOT NULL,
    "lastMessageAt" timestamp(3) with time zone NOT NULL,
    "credentialId" character varying(36),
    provider character varying(16),
    model character varying(256),
    "workflowId" character varying(36),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "agentId" uuid,
    "agentName" character varying(128),
    type character varying(16) DEFAULT 'production'::character varying NOT NULL,
    CONSTRAINT "CHK_chat_hub_sessions_type" CHECK (((type)::text = ANY (ARRAY[('production'::character varying)::text, ('manual'::character varying)::text])))
);


--
-- Name: COLUMN chat_hub_sessions.provider; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_sessions.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- Name: COLUMN chat_hub_sessions.model; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_sessions.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- Name: COLUMN chat_hub_sessions."agentId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_sessions."agentId" IS 'ID of the custom agent (if provider is "custom-agent")';


--
-- Name: COLUMN chat_hub_sessions."agentName"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_hub_sessions."agentName" IS 'Cached name of the custom agent (if provider is "custom-agent")';


--
-- Name: chat_hub_tools; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_hub_tools (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    "typeVersion" double precision NOT NULL,
    "ownerId" uuid NOT NULL,
    definition json NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: credential_dependency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_dependency (
    id integer NOT NULL,
    "credentialId" character varying(36) NOT NULL,
    "dependencyType" character varying(64) NOT NULL,
    "dependencyId" character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: credential_dependency_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.credential_dependency ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.credential_dependency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: credentials_entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credentials_entity (
    name character varying(128) NOT NULL,
    data text NOT NULL,
    type character varying(128) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    id character varying(36) NOT NULL,
    "isManaged" boolean DEFAULT false NOT NULL,
    "isGlobal" boolean DEFAULT false NOT NULL,
    "isResolvable" boolean DEFAULT false NOT NULL,
    "resolvableAllowFallback" boolean DEFAULT false NOT NULL,
    "resolverId" character varying(16)
);


--
-- Name: data_table; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_table (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: data_table_column; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_table_column (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    type character varying(32) NOT NULL,
    index integer NOT NULL,
    "dataTableId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN data_table_column.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.data_table_column.type IS 'Expected: string, number, boolean, or date (not enforced as a constraint)';


--
-- Name: COLUMN data_table_column.index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.data_table_column.index IS 'Column order, starting from 0 (0 = first column)';


--
-- Name: deployment_key; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deployment_key (
    id character varying(36) NOT NULL,
    type character varying(64) NOT NULL,
    value text NOT NULL,
    algorithm character varying(20),
    status character varying(20) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: dynamic_credential_entry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynamic_credential_entry (
    credential_id character varying(16) NOT NULL,
    subject_id character varying(2048) NOT NULL,
    resolver_id character varying(16) NOT NULL,
    data text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: dynamic_credential_resolver; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynamic_credential_resolver (
    id character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    type character varying(128) NOT NULL,
    config text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN dynamic_credential_resolver.config; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.dynamic_credential_resolver.config IS 'Encrypted resolver configuration (JSON encrypted as string)';


--
-- Name: dynamic_credential_user_entry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynamic_credential_user_entry (
    "credentialId" character varying(16) NOT NULL,
    "userId" uuid NOT NULL,
    "resolverId" character varying(16) NOT NULL,
    data text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: evaluation_collection; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_collection (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    description text,
    "workflowId" character varying(36) NOT NULL,
    "evaluationConfigId" character varying(36) NOT NULL,
    "createdById" uuid,
    "insightsCache" json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: evaluation_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_config (
    id character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    status character varying(16) DEFAULT 'valid'::character varying NOT NULL,
    "invalidReason" character varying(64),
    "datasetSource" character varying(32) NOT NULL,
    "datasetRef" json NOT NULL,
    "startNodeName" character varying(255) NOT NULL,
    "endNodeName" character varying(255) NOT NULL,
    metrics json NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: event_destinations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_destinations (
    id uuid NOT NULL,
    destination jsonb NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: execution_annotation_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execution_annotation_tags (
    "annotationId" integer NOT NULL,
    "tagId" character varying(24) NOT NULL
);


--
-- Name: execution_annotations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execution_annotations (
    id integer NOT NULL,
    "executionId" integer NOT NULL,
    vote character varying(6),
    note text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: execution_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.execution_annotations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: execution_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.execution_annotations_id_seq OWNED BY public.execution_annotations.id;


--
-- Name: execution_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execution_data (
    "executionId" integer NOT NULL,
    "workflowData" json NOT NULL,
    data text NOT NULL,
    "workflowVersionId" character varying(36)
);


--
-- Name: execution_entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execution_entity (
    id integer NOT NULL,
    finished boolean NOT NULL,
    mode character varying NOT NULL,
    "retryOf" character varying,
    "retrySuccessId" character varying,
    "startedAt" timestamp(3) with time zone,
    "stoppedAt" timestamp(3) with time zone,
    "waitTill" timestamp(3) with time zone,
    status character varying NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "deletedAt" timestamp(3) with time zone,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "storedAt" character varying(2) DEFAULT 'db'::character varying NOT NULL,
    "tracingContext" json,
    "deduplicationKey" character varying(255),
    CONSTRAINT "execution_entity_storedAt_check" CHECK ((("storedAt")::text = ANY (ARRAY[('db'::character varying)::text, ('fs'::character varying)::text, ('s3'::character varying)::text])))
);


--
-- Name: execution_entity_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.execution_entity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: execution_entity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.execution_entity_id_seq OWNED BY public.execution_entity.id;


--
-- Name: execution_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execution_metadata (
    id integer NOT NULL,
    "executionId" integer NOT NULL,
    key character varying(255) NOT NULL,
    value text NOT NULL
);


--
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.execution_metadata_temp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.execution_metadata_temp_id_seq OWNED BY public.execution_metadata.id;


--
-- Name: folder; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.folder (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    "parentFolderId" character varying(36),
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: folder_tag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.folder_tag (
    "folderId" character varying(36) NOT NULL,
    "tagId" character varying(36) NOT NULL
);


--
-- Name: insights_by_period; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.insights_by_period (
    id integer NOT NULL,
    "metaId" integer NOT NULL,
    type integer NOT NULL,
    value bigint NOT NULL,
    "periodUnit" integer NOT NULL,
    "periodStart" timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: COLUMN insights_by_period.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.insights_by_period.type IS '0: time_saved_minutes, 1: runtime_milliseconds, 2: success, 3: failure';


--
-- Name: COLUMN insights_by_period."periodUnit"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.insights_by_period."periodUnit" IS '0: hour, 1: day, 2: week';


--
-- Name: insights_by_period_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.insights_by_period ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insights_by_period_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: insights_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.insights_metadata (
    "metaId" integer NOT NULL,
    "workflowId" character varying(36),
    "projectId" character varying(36),
    "workflowName" character varying(128) NOT NULL,
    "projectName" character varying(255) NOT NULL
);


--
-- Name: insights_metadata_metaId_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.insights_metadata ALTER COLUMN "metaId" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."insights_metadata_metaId_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: insights_raw; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.insights_raw (
    id integer NOT NULL,
    "metaId" integer NOT NULL,
    type integer NOT NULL,
    value bigint NOT NULL,
    "timestamp" timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: COLUMN insights_raw.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.insights_raw.type IS '0: time_saved_minutes, 1: runtime_milliseconds, 2: success, 3: failure';


--
-- Name: insights_raw_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.insights_raw ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insights_raw_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: installed_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.installed_nodes (
    name character varying(200) NOT NULL,
    type character varying(200) NOT NULL,
    "latestVersion" integer DEFAULT 1 NOT NULL,
    package character varying(241) NOT NULL
);


--
-- Name: installed_packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.installed_packages (
    "packageName" character varying(214) NOT NULL,
    "installedVersion" character varying(50) NOT NULL,
    "authorName" character varying(70),
    "authorEmail" character varying(70),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_ai_checkpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_checkpoints (
    key character varying(255) NOT NULL,
    "runId" character varying(255),
    "threadId" uuid NOT NULL,
    "resourceId" character varying(255),
    state json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "expiredAt" timestamp(3) with time zone,
    CONSTRAINT instance_ai_checkpoints_state_tombstone_check CHECK (((("expiredAt" IS NOT NULL) AND (state IS NULL)) OR ("expiredAt" IS NULL)))
);


--
-- Name: COLUMN instance_ai_checkpoints.key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_checkpoints.key IS 'Opaque checkpoint key from the agent runtime.';


--
-- Name: COLUMN instance_ai_checkpoints."runId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_checkpoints."runId" IS 'Run ID parsed from the checkpoint key when available.';


--
-- Name: COLUMN instance_ai_checkpoints."threadId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_checkpoints."threadId" IS 'Instance AI thread that owns the checkpoint.';


--
-- Name: COLUMN instance_ai_checkpoints."resourceId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_checkpoints."resourceId" IS 'Resource ID recorded by the agent runtime.';


--
-- Name: COLUMN instance_ai_checkpoints.state; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_checkpoints.state IS 'Serializable agent state snapshot stored as JSON.';


--
-- Name: COLUMN instance_ai_checkpoints."expiredAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_checkpoints."expiredAt" IS 'Soft-delete timestamp: null means live; non-null marks the row as a tombstone.';


--
-- Name: instance_ai_iteration_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_iteration_logs (
    id character varying(36) NOT NULL,
    "threadId" uuid NOT NULL,
    "taskKey" character varying NOT NULL,
    entry text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_ai_mcp_registry_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_mcp_registry_connections (
    id uuid NOT NULL,
    "credentialId" character varying(36) NOT NULL,
    "serverSlug" character varying(255) NOT NULL,
    "toolFilter" json,
    "userId" uuid NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN instance_ai_mcp_registry_connections."toolFilter"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_mcp_registry_connections."toolFilter" IS 'Optional MCP tool filter per registry connection: { mode: "allow" | "exclude", tools: string[] }';


--
-- Name: instance_ai_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_messages (
    id character varying(36) NOT NULL,
    "threadId" uuid NOT NULL,
    content text NOT NULL,
    role character varying(16) NOT NULL,
    type character varying(32),
    "resourceId" character varying(255),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_ai_observation_cursors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_observation_cursors (
    "observationScopeId" uuid NOT NULL,
    "lastObservedMessageId" character varying(36) NOT NULL,
    "lastObservedAt" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN instance_ai_observation_cursors."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_observation_cursors."observationScopeId" IS 'instance_ai_threads.id source stream checkpointed by this cursor';


--
-- Name: instance_ai_observation_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_observation_locks (
    "observationScopeId" uuid NOT NULL,
    "taskKind" character varying(20) NOT NULL,
    "holderId" character varying(64) NOT NULL,
    "heldUntil" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_instance_ai_observation_locks_taskKind" CHECK ((("taskKind")::text = ANY (ARRAY[('observer'::character varying)::text, ('reflector'::character varying)::text])))
);


--
-- Name: COLUMN instance_ai_observation_locks."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_observation_locks."observationScopeId" IS 'instance_ai_threads.id source stream locked for observation tasks';


--
-- Name: COLUMN instance_ai_observation_locks."holderId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_observation_locks."holderId" IS 'Ephemeral background-task lock owner token, not a user ID';


--
-- Name: instance_ai_observational_memory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_observational_memory (
    id character varying(36) NOT NULL,
    "lookupKey" character varying(255) NOT NULL,
    scope character varying(16) NOT NULL,
    "threadId" uuid,
    "resourceId" character varying(255) NOT NULL,
    "activeObservations" text DEFAULT ''::text NOT NULL,
    "originType" character varying(32) NOT NULL,
    config text NOT NULL,
    "generationCount" integer DEFAULT 0 NOT NULL,
    "lastObservedAt" timestamp(3) with time zone,
    "pendingMessageTokens" integer DEFAULT 0 NOT NULL,
    "totalTokensObserved" integer DEFAULT 0 NOT NULL,
    "observationTokenCount" integer DEFAULT 0 NOT NULL,
    "isObserving" boolean DEFAULT false NOT NULL,
    "isReflecting" boolean DEFAULT false NOT NULL,
    "observedMessageIds" json,
    "observedTimezone" character varying,
    "bufferedObservations" text,
    "bufferedObservationTokens" integer,
    "bufferedMessageIds" json,
    "bufferedReflection" text,
    "bufferedReflectionTokens" integer,
    "bufferedReflectionInputTokens" integer,
    "reflectedObservationLineCount" integer,
    "bufferedObservationChunks" json,
    "isBufferingObservation" boolean DEFAULT false CONSTRAINT "instance_ai_observational_memor_isBufferingObservation_not_null" NOT NULL,
    "isBufferingReflection" boolean DEFAULT false NOT NULL,
    "lastBufferedAtTokens" integer DEFAULT 0 NOT NULL,
    "lastBufferedAtTime" timestamp(3) with time zone,
    metadata json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_ai_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_observations (
    id character varying(36) NOT NULL,
    "observationScopeId" uuid NOT NULL,
    marker character varying(16) NOT NULL,
    text text NOT NULL,
    "parentId" character varying(36),
    "tokenCount" integer DEFAULT 0 NOT NULL,
    status character varying(16) NOT NULL,
    "supersededBy" character varying(36),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_instance_ai_observations_marker" CHECK (((marker)::text = ANY (ARRAY[('critical'::character varying)::text, ('important'::character varying)::text, ('info'::character varying)::text, ('completion'::character varying)::text]))),
    CONSTRAINT "CHK_instance_ai_observations_status" CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('superseded'::character varying)::text, ('dropped'::character varying)::text])))
);


--
-- Name: COLUMN instance_ai_observations.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_observations.id IS 'Application-generated n8n string ID, not a database UUID';


--
-- Name: COLUMN instance_ai_observations."observationScopeId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_observations."observationScopeId" IS 'instance_ai_threads.id source stream for this observation log';


--
-- Name: instance_ai_pending_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_pending_confirmations (
    "requestId" character varying(36) NOT NULL,
    "threadId" uuid NOT NULL,
    "userId" uuid NOT NULL,
    kind character varying(16) NOT NULL,
    "runId" character varying(36) NOT NULL,
    "toolCallId" character varying(64),
    "messageGroupId" character varying(36),
    "checkpointKey" character varying(255),
    "checkpointTaskId" character varying(36),
    "expiresAt" timestamp(3) with time zone,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_instance_ai_pending_confirmations_kind" CHECK (((kind)::text = ANY (ARRAY[('suspended'::character varying)::text, ('inline'::character varying)::text])))
);


--
-- Name: COLUMN instance_ai_pending_confirmations."requestId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."requestId" IS 'HITL confirmation request identifier.';


--
-- Name: COLUMN instance_ai_pending_confirmations."threadId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."threadId" IS 'Instance AI thread that owns the confirmation.';


--
-- Name: COLUMN instance_ai_pending_confirmations."userId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."userId" IS 'User who is expected to confirm or cancel.';


--
-- Name: COLUMN instance_ai_pending_confirmations.kind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations.kind IS '''suspended'' (resumable from checkpoint) or ''inline'' (orchestrator-held Promise).';


--
-- Name: COLUMN instance_ai_pending_confirmations."runId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."runId" IS 'External run ID; reused on resume for SSE correlation.';


--
-- Name: COLUMN instance_ai_pending_confirmations."toolCallId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."toolCallId" IS 'Suspended tool call awaiting confirmation.';


--
-- Name: COLUMN instance_ai_pending_confirmations."messageGroupId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."messageGroupId" IS 'SSE event correlation group.';


--
-- Name: COLUMN instance_ai_pending_confirmations."checkpointKey"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."checkpointKey" IS 'FK to instance_ai_checkpoints.key; also the SDK runId used to resume.';


--
-- Name: COLUMN instance_ai_pending_confirmations."checkpointTaskId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."checkpointTaskId" IS 'Set when the suspended run was a planned-task checkpoint follow-up.';


--
-- Name: COLUMN instance_ai_pending_confirmations."expiresAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_pending_confirmations."expiresAt" IS 'TTL for the leader-only sweep; null disables auto-expiry.';


--
-- Name: instance_ai_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_resources (
    id character varying(255) NOT NULL,
    "workingMemory" text,
    metadata json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_ai_run_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_run_snapshots (
    "threadId" uuid NOT NULL,
    "runId" character varying(36) NOT NULL,
    "messageGroupId" character varying(36),
    "runIds" json,
    tree text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "langsmithRunId" character varying(36),
    "langsmithTraceId" character varying(36),
    "traceId" character varying(64),
    "spanId" character varying(64)
);


--
-- Name: COLUMN instance_ai_run_snapshots."langsmithRunId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_run_snapshots."langsmithRunId" IS 'LangSmith run ID (UUID v4, e.g. "f47ac10b-58cc-4372-a567-0e02b2c3d479").';


--
-- Name: COLUMN instance_ai_run_snapshots."langsmithTraceId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_run_snapshots."langsmithTraceId" IS 'LangSmith trace ID (UUID v4, e.g. "f47ac10b-58cc-4372-a567-0e02b2c3d479").';


--
-- Name: COLUMN instance_ai_run_snapshots."traceId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_run_snapshots."traceId" IS 'OpenTelemetry trace ID for the root Instance AI run.';


--
-- Name: COLUMN instance_ai_run_snapshots."spanId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_run_snapshots."spanId" IS 'OpenTelemetry span ID for the root Instance AI run.';


--
-- Name: instance_ai_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_threads (
    id uuid NOT NULL,
    "resourceId" character varying(255) NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    metadata json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "projectId" character varying(36) NOT NULL
);


--
-- Name: COLUMN instance_ai_threads."projectId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instance_ai_threads."projectId" IS 'Project this thread is scoped to';


--
-- Name: instance_ai_workflow_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_ai_workflow_snapshots (
    "runId" character varying(36) NOT NULL,
    "workflowName" character varying(255) NOT NULL,
    "resourceId" character varying(255),
    status character varying,
    snapshot text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_version_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_version_history (
    id integer NOT NULL,
    major integer NOT NULL,
    minor integer NOT NULL,
    patch integer NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: instance_version_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.instance_version_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: instance_version_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.instance_version_history_id_seq OWNED BY public.instance_version_history.id;


--
-- Name: invalid_auth_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invalid_auth_token (
    token character varying(512) NOT NULL,
    "expiresAt" timestamp(3) with time zone NOT NULL
);


--
-- Name: mcp_registry_server; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mcp_registry_server (
    slug character varying(255) NOT NULL,
    status character varying(50) NOT NULL,
    version character varying(50) NOT NULL,
    "registryUpdatedAt" timestamp(3) without time zone NOT NULL,
    data json DEFAULT '{}'::json NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_tmp_mcp_registry_server_status" CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('deprecated'::character varying)::text])))
);


--
-- Name: COLUMN mcp_registry_server.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mcp_registry_server.status IS 'Server status in the MCP registry. Deprecated servers are not surfaced to users.';


--
-- Name: COLUMN mcp_registry_server.data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mcp_registry_server.data IS 'JSON object containing server metadata (icons, remotes, tools, etc.)';


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    "timestamp" bigint NOT NULL,
    name character varying NOT NULL
);


--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_tokens (
    token character varying NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL
);


--
-- Name: oauth_authorization_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_authorization_codes (
    code character varying(255) NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL,
    "redirectUri" character varying NOT NULL,
    "codeChallenge" character varying NOT NULL,
    "codeChallengeMethod" character varying(255) NOT NULL,
    "expiresAt" bigint NOT NULL,
    state character varying,
    used boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    resource character varying,
    scope json DEFAULT '["tool:listWorkflows","tool:getWorkflowDetails"]'::json NOT NULL
);


--
-- Name: COLUMN oauth_authorization_codes."expiresAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_authorization_codes."expiresAt" IS 'Unix timestamp in milliseconds';


--
-- Name: COLUMN oauth_authorization_codes.resource; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_authorization_codes.resource IS 'RFC 8707 resource indicator URI (e.g. https://n8n.example.com/mcp-server/http). NULL = legacy flow predating resource indicator support; defaults to the instance canonical MCP resource URL.';


--
-- Name: COLUMN oauth_authorization_codes.scope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_authorization_codes.scope IS 'OAuth scopes granted for this authorization code';


--
-- Name: oauth_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_clients (
    id character varying NOT NULL,
    name character varying(255) NOT NULL,
    "redirectUris" json NOT NULL,
    "grantTypes" json NOT NULL,
    "clientSecret" character varying(255),
    "clientSecretExpiresAt" bigint,
    "tokenEndpointAuthMethod" character varying(255) DEFAULT 'none'::character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN oauth_clients."tokenEndpointAuthMethod"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_clients."tokenEndpointAuthMethod" IS 'Possible values: none, client_secret_basic or client_secret_post';


--
-- Name: oauth_refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_refresh_tokens (
    token character varying(255) NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL,
    "expiresAt" bigint NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    scope json DEFAULT '["tool:listWorkflows","tool:getWorkflowDetails"]'::json NOT NULL
);


--
-- Name: COLUMN oauth_refresh_tokens."expiresAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_refresh_tokens."expiresAt" IS 'Unix timestamp in milliseconds';


--
-- Name: COLUMN oauth_refresh_tokens.scope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_refresh_tokens.scope IS 'OAuth scopes granted for this refresh token';


--
-- Name: oauth_user_consents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_user_consents (
    id integer NOT NULL,
    "userId" uuid NOT NULL,
    "clientId" character varying NOT NULL,
    "grantedAt" bigint NOT NULL
);


--
-- Name: COLUMN oauth_user_consents."grantedAt"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.oauth_user_consents."grantedAt" IS 'Unix timestamp in milliseconds';


--
-- Name: oauth_user_consents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.oauth_user_consents ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.oauth_user_consents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: processed_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_data (
    "workflowId" character varying(36) NOT NULL,
    context character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    value text NOT NULL
);


--
-- Name: project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    icon json,
    description character varying(512),
    "creatorId" uuid,
    "customTelemetryTags" json DEFAULT '[]'::json NOT NULL
);


--
-- Name: COLUMN project."creatorId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.project."creatorId" IS 'ID of the user who created the project';


--
-- Name: project_relation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_relation (
    "projectId" character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    role character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: project_secrets_provider_access; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_secrets_provider_access (
    "secretsProviderConnectionId" integer CONSTRAINT "project_secrets_provider_ac_secretsProviderConnectionI_not_null" NOT NULL,
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    role character varying(128) DEFAULT 'secretsProviderConnection:user'::character varying NOT NULL,
    CONSTRAINT "CHK_project_secrets_provider_access_role" CHECK (((role)::text = ANY (ARRAY[('secretsProviderConnection:owner'::character varying)::text, ('secretsProviderConnection:user'::character varying)::text])))
);


--
-- Name: role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role (
    slug character varying(128) NOT NULL,
    "displayName" text,
    description text,
    "roleType" text,
    "systemRole" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN role.slug; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.role.slug IS 'Unique identifier of the role for example: "global:owner"';


--
-- Name: COLUMN role."displayName"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.role."displayName" IS 'Name used to display in the UI';


--
-- Name: COLUMN role.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.role.description IS 'Text describing the scope in more detail of users';


--
-- Name: COLUMN role."roleType"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.role."roleType" IS 'Type of the role, e.g., global, project, or workflow';


--
-- Name: COLUMN role."systemRole"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.role."systemRole" IS 'Indicates if the role is managed by the system and cannot be edited';


--
-- Name: role_mapping_rule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_mapping_rule (
    id character varying(16) NOT NULL,
    expression text NOT NULL,
    role character varying(128) NOT NULL,
    type character varying(64) NOT NULL,
    "order" integer NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN role_mapping_rule.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.role_mapping_rule.type IS 'Expected values: ''instance'' (maps to a global role) or ''project'' (maps to a project role; projects linked via role_mapping_rule_project).';


--
-- Name: role_mapping_rule_project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_mapping_rule_project (
    "roleMappingRuleId" character varying(16) NOT NULL,
    "projectId" character varying(36) NOT NULL
);


--
-- Name: role_scope; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_scope (
    "roleSlug" character varying(128) NOT NULL,
    "scopeSlug" character varying(128) NOT NULL
);


--
-- Name: scope; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scope (
    slug character varying(128) NOT NULL,
    "displayName" text,
    description text
);


--
-- Name: COLUMN scope.slug; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.scope.slug IS 'Unique identifier of the scope for example: "project:create"';


--
-- Name: COLUMN scope."displayName"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.scope."displayName" IS 'Name used to display in the UI';


--
-- Name: COLUMN scope.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.scope.description IS 'Text describing the scope in more detail of users';


--
-- Name: secrets_provider_connection; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.secrets_provider_connection (
    id integer NOT NULL,
    "providerKey" character varying(128) NOT NULL,
    type character varying(36) NOT NULL,
    "encryptedSettings" text NOT NULL,
    "isEnabled" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: COLUMN secrets_provider_connection.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.secrets_provider_connection.type IS 'Type of secrets provider. Possible values: awsSecretsManager, gcpSecretsManager, vault, azureKeyVault, infisical';


--
-- Name: secrets_provider_connection_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.secrets_provider_connection ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.secrets_provider_connection_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    key character varying(255) NOT NULL,
    value text NOT NULL,
    "loadOnStartup" boolean DEFAULT false NOT NULL
);


--
-- Name: shared_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shared_credentials (
    "credentialsId" character varying(36) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: shared_workflow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shared_workflow (
    "workflowId" character varying(36) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: tag_entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tag_entity (
    name character varying(24) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    id character varying(36) NOT NULL
);


--
-- Name: test_case_execution; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_case_execution (
    id character varying(36) NOT NULL,
    "testRunId" character varying(36) NOT NULL,
    "executionId" integer,
    status character varying NOT NULL,
    "runAt" timestamp(3) with time zone,
    "completedAt" timestamp(3) with time zone,
    "errorCode" character varying,
    "errorDetails" json,
    metrics json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    inputs json,
    outputs json,
    "runIndex" integer
);


--
-- Name: test_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_run (
    id character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    status character varying NOT NULL,
    "errorCode" character varying,
    "errorDetails" json,
    "runAt" timestamp(3) with time zone,
    "completedAt" timestamp(3) with time zone,
    metrics json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "runningInstanceId" character varying(255),
    "cancelRequested" boolean DEFAULT false NOT NULL,
    "workflowVersionId" character varying(36),
    "evaluationConfigId" character varying(36),
    "evaluationConfigSnapshot" jsonb,
    "collectionId" character varying(36)
);


--
-- Name: token_exchange_jti; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_exchange_jti (
    jti character varying(255) NOT NULL,
    "expiresAt" timestamp(3) with time zone NOT NULL,
    "createdAt" timestamp(3) with time zone NOT NULL
);


--
-- Name: trusted_key; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trusted_key (
    "sourceId" character varying(36) NOT NULL,
    kid character varying(255) NOT NULL,
    data text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: trusted_key_source; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trusted_key_source (
    id character varying(36) NOT NULL,
    type character varying(32) NOT NULL,
    config text NOT NULL,
    status character varying(32) DEFAULT 'pending'::character varying NOT NULL,
    "lastError" text,
    "lastRefreshedAt" timestamp(3) with time zone,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."user" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255),
    "firstName" character varying(32),
    "lastName" character varying(32),
    password character varying(255),
    "personalizationAnswers" json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    settings json,
    disabled boolean DEFAULT false NOT NULL,
    "mfaEnabled" boolean DEFAULT false NOT NULL,
    "mfaSecret" text,
    "mfaRecoveryCodes" text,
    "lastActiveAt" date,
    "roleSlug" character varying(128) DEFAULT 'global:member'::character varying NOT NULL
);


--
-- Name: user_api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_api_keys (
    id character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    label character varying(100) NOT NULL,
    "apiKey" character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    scopes json,
    audience character varying DEFAULT 'public-api'::character varying NOT NULL,
    "lastUsedAt" timestamp(3) with time zone
);


--
-- Name: user_favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_favorites (
    id integer NOT NULL,
    "userId" uuid NOT NULL,
    "resourceId" character varying(255) NOT NULL,
    "resourceType" character varying(64) NOT NULL
);


--
-- Name: user_favorites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_favorites ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.user_favorites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: variables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.variables (
    key character varying(50) NOT NULL,
    type character varying(50) DEFAULT 'string'::character varying NOT NULL,
    value text,
    id character varying(36) NOT NULL,
    "projectId" character varying(36),
    CONSTRAINT variables_value_max_len CHECK (((value IS NULL) OR (char_length(value) <= 1000)))
);


--
-- Name: webhook_entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_entity (
    "webhookPath" character varying NOT NULL,
    method character varying NOT NULL,
    node character varying NOT NULL,
    "webhookId" character varying,
    "pathLength" integer,
    "workflowId" character varying(36) NOT NULL
);


--
-- Name: workflow_builder_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_builder_session (
    id uuid NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    messages json DEFAULT '[]'::json NOT NULL,
    "previousSummary" text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "activeVersionCardId" character varying(255),
    "resumeAfterRestoreMessageId" character varying(255)
);


--
-- Name: COLUMN workflow_builder_session."previousSummary"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_builder_session."previousSummary" IS 'Summary of prior conversation from compaction (/compact or auto-compact)';


--
-- Name: workflow_dependency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_dependency (
    id integer NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "workflowVersionId" integer NOT NULL,
    "dependencyType" character varying(32) NOT NULL,
    "dependencyKey" character varying(255) NOT NULL,
    "dependencyInfo" json,
    "indexVersionId" smallint DEFAULT 1 NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "publishedVersionId" character varying(36)
);


--
-- Name: COLUMN workflow_dependency."workflowVersionId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_dependency."workflowVersionId" IS 'Version of the workflow';


--
-- Name: COLUMN workflow_dependency."dependencyType"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_dependency."dependencyType" IS 'Type of dependency: "credential", "nodeType", "webhookPath", or "workflowCall"';


--
-- Name: COLUMN workflow_dependency."dependencyKey"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_dependency."dependencyKey" IS 'ID or name of the dependency';


--
-- Name: COLUMN workflow_dependency."dependencyInfo"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_dependency."dependencyInfo" IS 'Additional info about the dependency, interpreted based on type';


--
-- Name: COLUMN workflow_dependency."indexVersionId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_dependency."indexVersionId" IS 'Version of the index structure';


--
-- Name: workflow_dependency_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.workflow_dependency ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.workflow_dependency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workflow_entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_entity (
    name character varying(128) NOT NULL,
    active boolean NOT NULL,
    nodes json NOT NULL,
    connections json NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    settings json,
    "staticData" json,
    "pinData" json,
    "versionId" character(36) NOT NULL,
    "triggerCount" integer DEFAULT 0 NOT NULL,
    id character varying(36) NOT NULL,
    meta json,
    "parentFolderId" character varying(36) DEFAULT NULL::character varying,
    "isArchived" boolean DEFAULT false NOT NULL,
    "versionCounter" integer DEFAULT 1 NOT NULL,
    description text,
    "activeVersionId" character varying(36),
    "nodeGroups" json DEFAULT '[]'::json NOT NULL,
    "sourceWorkflowId" character varying
);


--
-- Name: workflow_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_history (
    "versionId" character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    authors character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    nodes json NOT NULL,
    connections json NOT NULL,
    name character varying(128),
    autosaved boolean DEFAULT false NOT NULL,
    description text,
    "nodeGroups" json DEFAULT '[]'::json NOT NULL
);


--
-- Name: workflow_publication_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_publication_outbox (
    id integer NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "publishedVersionId" character varying(36) NOT NULL,
    status character varying(20) NOT NULL,
    "errorMessage" text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_workflow_publication_outbox_status" CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('in_progress'::character varying)::text, ('completed'::character varying)::text, ('partial_success'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: COLUMN workflow_publication_outbox."workflowId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_publication_outbox."workflowId" IS 'References workflow_entity.id.';


--
-- Name: COLUMN workflow_publication_outbox."publishedVersionId"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_publication_outbox."publishedVersionId" IS 'References workflow_history.versionId.';


--
-- Name: COLUMN workflow_publication_outbox."errorMessage"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_publication_outbox."errorMessage" IS 'Error details for surfacing failed publications to the user.';


--
-- Name: workflow_publication_outbox_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.workflow_publication_outbox ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.workflow_publication_outbox_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workflow_publish_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_publish_history (
    id integer NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "versionId" character varying(36),
    event character varying(36) NOT NULL,
    "userId" uuid,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_workflow_publish_history_event" CHECK (((event)::text = ANY (ARRAY[('activated'::character varying)::text, ('deactivated'::character varying)::text])))
);


--
-- Name: COLUMN workflow_publish_history.event; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workflow_publish_history.event IS 'Type of history record: activated (workflow is now active), deactivated (workflow is now inactive)';


--
-- Name: workflow_publish_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.workflow_publish_history ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.workflow_publish_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workflow_published_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_published_version (
    "workflowId" character varying(36) NOT NULL,
    "publishedVersionId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


--
-- Name: workflow_statistics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_statistics (
    count bigint DEFAULT 0,
    "latestEvent" timestamp(3) with time zone,
    name character varying(128) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "rootCount" bigint DEFAULT 0,
    id integer NOT NULL,
    "workflowName" character varying(128)
);


--
-- Name: workflow_statistics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workflow_statistics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workflow_statistics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workflow_statistics_id_seq OWNED BY public.workflow_statistics.id;


--
-- Name: workflows_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflows_tags (
    "workflowId" character varying(36) NOT NULL,
    "tagId" character varying(36) NOT NULL
);


--
-- Name: auth_provider_sync_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_provider_sync_history ALTER COLUMN id SET DEFAULT nextval('public.auth_provider_sync_history_id_seq'::regclass);


--
-- Name: execution_annotations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_annotations ALTER COLUMN id SET DEFAULT nextval('public.execution_annotations_id_seq'::regclass);


--
-- Name: execution_entity id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_entity ALTER COLUMN id SET DEFAULT nextval('public.execution_entity_id_seq'::regclass);


--
-- Name: execution_metadata id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_metadata ALTER COLUMN id SET DEFAULT nextval('public.execution_metadata_temp_id_seq'::regclass);


--
-- Name: instance_version_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_version_history ALTER COLUMN id SET DEFAULT nextval('public.instance_version_history_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: workflow_statistics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_statistics ALTER COLUMN id SET DEFAULT nextval('public.workflow_statistics_id_seq'::regclass);


--
-- Data for Name: agent_checkpoints; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_checkpoints ("runId", "agentId", state, expired, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agent_execution; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_execution (id, "threadId", status, "startedAt", "stoppedAt", duration, "userMessage", "assistantResponse", model, "promptTokens", "completionTokens", "totalTokens", cost, "toolCalls", timeline, error, "hitlStatus", source, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agent_execution_threads; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_execution_threads (id, "agentId", "agentName", "projectId", "sessionNumber", "totalPromptTokens", "totalCompletionTokens", "totalCost", "totalDuration", title, emoji, "createdAt", "updatedAt", "taskId", "taskVersionId", "parentThreadId", "parentAgentId") FROM stdin;
\.


--
-- Data for Name: agent_files; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_files (id, "agentId", "binaryDataId", "fileName", "mimeType", "fileSizeBytes", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agent_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_history ("versionId", "agentId", schema, tools, skills, "publishedById", author, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agent_task_definition; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_task_definition (id, "agentId", name, objective, "cronExpression", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agent_task_run_lock; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_task_run_lock ("agentId", "taskId", "holderId", "heldUntil", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agent_task_snapshot; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_task_snapshot ("versionId", "taskId", enabled, name, objective, "cronExpression", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents (id, name, description, "projectId", integrations, schema, tools, skills, "versionId", "createdAt", "updatedAt", "activeVersionId") FROM stdin;
\.


--
-- Data for Name: agents_memory_entries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_memory_entries (id, "agentId", "resourceId", content, "contentHash", status, "supersededBy", "embeddingModel", embedding, metadata, "lastSeenAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_memory_entry_cursors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_memory_entry_cursors ("agentId", "observationScopeId", "lastIndexedObservationId", "lastIndexedObservationCreatedAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_memory_entry_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_memory_entry_locks ("agentId", "resourceId", "holderId", "heldUntil", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_memory_entry_sources; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_memory_entry_sources (id, "agentId", "memoryEntryId", "observationId", "threadId", "evidenceHash", "evidenceText", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_messages (id, "threadId", "resourceId", role, type, content, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_observation_cursors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_observation_cursors ("agentId", "observationScopeId", "lastObservedMessageId", "lastObservedAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_observation_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_observation_locks ("agentId", "observationScopeId", "taskKind", "holderId", "heldUntil", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_observations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_observations (id, "agentId", "observationScopeId", marker, text, "parentId", "tokenCount", status, "supersededBy", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_resources; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_resources (id, metadata, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: agents_threads; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents_threads (id, "resourceId", title, metadata, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: ai_builder_temporary_workflow; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_builder_temporary_workflow ("workflowId", "threadId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: annotation_tag_entity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.annotation_tag_entity (id, name, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: auth_identity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_identity ("userId", "providerId", "providerType", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: auth_provider_sync_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_provider_sync_history (id, "providerType", "runMode", status, "startedAt", "endedAt", scanned, created, updated, disabled, error) FROM stdin;
\.


--
-- Data for Name: binary_data; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.binary_data ("fileId", "sourceType", "sourceId", data, "mimeType", "fileName", "fileSize", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: chat_hub_agent_tools; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_hub_agent_tools ("agentId", "toolId") FROM stdin;
\.


--
-- Data for Name: chat_hub_agents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_hub_agents (id, name, description, "systemPrompt", "ownerId", "credentialId", provider, model, "createdAt", "updatedAt", icon, files, "suggestedPrompts") FROM stdin;
\.


--
-- Data for Name: chat_hub_messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_hub_messages (id, "sessionId", "previousMessageId", "revisionOfMessageId", "retryOfMessageId", type, name, content, provider, model, "workflowId", "executionId", "createdAt", "updatedAt", "agentId", status, attachments) FROM stdin;
\.


--
-- Data for Name: chat_hub_session_tools; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_hub_session_tools ("sessionId", "toolId") FROM stdin;
\.


--
-- Data for Name: chat_hub_sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_hub_sessions (id, title, "ownerId", "lastMessageAt", "credentialId", provider, model, "workflowId", "createdAt", "updatedAt", "agentId", "agentName", type) FROM stdin;
\.


--
-- Data for Name: chat_hub_tools; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_hub_tools (id, name, type, "typeVersion", "ownerId", definition, enabled, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: credential_dependency; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.credential_dependency (id, "credentialId", "dependencyType", "dependencyId", "createdAt") FROM stdin;
\.


--
-- Data for Name: credentials_entity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.credentials_entity (name, data, type, "createdAt", "updatedAt", id, "isManaged", "isGlobal", "isResolvable", "resolvableAllowFallback", "resolverId") FROM stdin;
PG Contracts - localhost:5432	U2FsdGVkX1+TPotX9Ly5vAy771M85pB/i1ZqHwMel5XUx3MZJPizVT9wKQppqi6IjNP994oNHq2kTuYLqjqGWF7UgEqNCjUI4R4JOvgXduNkbecVdGMuW6dTgwui+UjMwEojFPcofhqy0/wAPSU9GLWeIF5Jwzw9agExoYrQP/9W67RQ5A7RdFp7WO19RUtl	postgres	2026-06-22 00:06:27.392+07	2026-06-22 00:06:27.392+07	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	f	f	f	f	\N
LINE Bearer Auth	U2FsdGVkX19Q/yYdYObPZBC19VFD3PD28tpO8LvIYMKdUxfPY/mEspvK8ZbRA5NuttxZGkJR2M+LpydTaTMwBD9IdFwMNMjABrHAvb98nvHakbXiN4pPLzA9UnViLubFCCXwGkWCFRVnnY71RJ7NPKFib6RKPWsR8l7EC3hoa59GiKbvGkADKeFO0Iuo6Um3inr9WZaBpQCwTZW8X9D3z+6uFSDSncAMt/Uq2CFGHEIxGUw4cGq+QWsrHZFJrYS53brNaVfdVzLidhf5GCX9SF4Hk5D9fRb0dMDgNZvzmfxKd8JYxFayzP9DencCsJmj	httpHeaderAuth	2026-06-22 00:06:27.392+07	2026-06-22 00:06:27.392+07	27fef0b4-9224-4a77-9741-c4f8e3d0aede	f	f	f	f	\N
MinIO Contracts	U2FsdGVkX192N7qcfbHk70ZkqerYHHe1EhOL0X0xqWmiCynbN2wt/SNgz9ZKqE+7IoF1TkoZy5fYVQy8B/FHR0lmuSqquyUNSEuu7tuPso4rrOo7MRdYvNdhFhL4z38OuGsn6VjJnhKp6gz+CbEZBdusJ+mH0MqMEmjSWBKpcgGDNWF7ydZEu2oDUnb6DtpKqWHJBsK7zMAER6eubMw16g==	s3	2026-06-22 00:06:27.392+07	2026-06-22 00:06:27.392+07	f719a9dd-b576-4cd5-bde6-13fb6344c447	f	f	f	f	\N
Postgres HR - localhost:5432	U2FsdGVkX18NvrrEbcnL5X1BRqVykNaLFv/ft4CQBKSV2D4gZNbn3cFBkZAtvbm2UHdlxvGvkOwzgHdTSbtpxZ8Fq66RO8UcVy7Pkv9xpvZqI4pc+EIdHdUXAxjCti3d00Sve2NQn/i84tUKWzhgBX2OzeNvxCww8OqiW0UpfVeJmRYCGjoHANlio+iah5WOjkUL/MAlz6URHiB7576KI3WYOp44mwfMUS6Vc7oDrSY=	postgres	2026-06-24 11:03:53.368+07	2026-06-24 11:03:53.367+07	vwf7u64OuSi5ejWs	f	f	f	f	\N
LINE HR Bearer Auth	U2FsdGVkX1+AsUyMUyBq6qf5wrp8GglRD6AUF3/HzuWOBrFOyqtOCwLNOMZAkYPryOHgp7g6Nk5imyQAdb1vjJqPQzNIUUn6gIxhCtrSt20gp4qlTebUPRZgb4YUC21D52Y4IU/3O7bjroghnClLPUZnjP45zOmx6pgO6LOtdQaKyqhmgb4K0wbRJvhqjI1lS0ylIwMSUiQslA1kegLg4cxFtTYsq9bwsUINEDKi8+397poUAHFXUURHAeDzRRc10rJFdF5zqpX6Vh99OgrF9Yq02LFillp8qiUqL4UV1Zxh1LHtkNPEDP5OCWNAaYTEWFhiai1xQ/Z6F9Jt8J3j6x7SfNyeEhi+zcXwUmupTpM=	httpHeaderAuth	2026-06-24 11:38:57.375+07	2026-06-24 11:38:57.374+07	W5ANm5bXR2xWA4Z2	f	f	f	f	\N
\.


--
-- Data for Name: data_table; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.data_table (id, name, "projectId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: data_table_column; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.data_table_column (id, name, type, index, "dataTableId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: deployment_key; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deployment_key (id, type, value, algorithm, status, "createdAt", "updatedAt") FROM stdin;
Owagw7j6DD7zgnJl	instance.id	9685be6f50bcbef5d8a8e86cafafb65bd62dd8e976fc3ff0b4bea52b5cf986aa	\N	active	2026-06-21 15:57:16.597+07	2026-06-21 15:57:16.597+07
tmTrNk7zKbMVzpMW	signing.hmac	dd7af79250e28d1d33514b88281549912c92f443c159fc97189be1f31a526a41	\N	active	2026-06-21 15:57:16.6+07	2026-06-21 15:57:16.6+07
Yt617pAQtlQigJIm	signing.jwt	e9a05fa2dbe5d6e3eb20a68f26690ac6f921ce0512f2c114e8cedb3ad0639f27	\N	active	2026-06-21 15:57:16.601+07	2026-06-21 15:57:16.601+07
3Ry15vZzrvFUymVl	signing.binary_data	eVxFptMIkxq5+TA/a6BLsB8W5mXqQUvTZd9lqkTxmT0=	\N	active	2026-06-21 15:57:16.602+07	2026-06-21 15:57:16.602+07
\.


--
-- Data for Name: dynamic_credential_entry; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dynamic_credential_entry (credential_id, subject_id, resolver_id, data, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: dynamic_credential_resolver; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dynamic_credential_resolver (id, name, type, config, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: dynamic_credential_user_entry; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dynamic_credential_user_entry ("credentialId", "userId", "resolverId", data, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: evaluation_collection; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.evaluation_collection (id, name, description, "workflowId", "evaluationConfigId", "createdById", "insightsCache", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: evaluation_config; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.evaluation_config (id, "workflowId", name, status, "invalidReason", "datasetSource", "datasetRef", "startNodeName", "endNodeName", metrics, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: event_destinations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.event_destinations (id, destination, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: execution_annotation_tags; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.execution_annotation_tags ("annotationId", "tagId") FROM stdin;
\.


--
-- Data for Name: execution_annotations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.execution_annotations (id, "executionId", vote, note, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: execution_data; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.execution_data ("executionId", "workflowData", data, "workflowVersionId") FROM stdin;
\.


--
-- Data for Name: execution_entity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.execution_entity (id, finished, mode, "retryOf", "retrySuccessId", "startedAt", "stoppedAt", "waitTill", status, "workflowId", "deletedAt", "createdAt", "storedAt", "tracingContext", "deduplicationKey") FROM stdin;
\.


--
-- Data for Name: execution_metadata; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.execution_metadata (id, "executionId", key, value) FROM stdin;
\.


--
-- Data for Name: folder; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.folder (id, name, "parentFolderId", "projectId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: folder_tag; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.folder_tag ("folderId", "tagId") FROM stdin;
\.


--
-- Data for Name: insights_by_period; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.insights_by_period (id, "metaId", type, value, "periodUnit", "periodStart") FROM stdin;
1	1	2	1	0	2026-06-21 16:00:00+07
2	2	3	2	0	2026-06-21 16:00:00+07
3	2	1	97	0	2026-06-21 16:00:00+07
4	1	1	100	0	2026-06-21 16:00:00+07
5	2	2	2	0	2026-06-21 16:00:00+07
6	1	0	0	0	2026-06-21 16:00:00+07
7	2	0	0	0	2026-06-21 16:00:00+07
8	1	3	1	0	2026-06-21 16:00:00+07
12	1	0	0	0	2026-06-22 00:00:00+07
13	1	0	0	0	2026-06-22 01:00:00+07
14	2	1	530	0	2026-06-21 23:00:00+07
15	1	1	5528	0	2026-06-22 00:00:00+07
16	1	1	1287	0	2026-06-22 01:00:00+07
17	2	2	48	0	2026-06-21 23:00:00+07
18	2	0	0	0	2026-06-21 23:00:00+07
19	1	2	2	0	2026-06-22 01:00:00+07
9	2	1	588	0	2026-06-21 22:00:00+07
21	1	3	2	0	2026-06-22 01:00:00+07
22	2	1	1788	0	2026-06-22 00:00:00+07
10	2	0	0	0	2026-06-21 22:00:00+07
24	1	2	3	0	2026-06-22 00:00:00+07
26	2	2	70	0	2026-06-22 00:00:00+07
28	2	3	1	0	2026-06-22 00:00:00+07
30	2	0	0	0	2026-06-22 00:00:00+07
11	2	2	44	0	2026-06-21 22:00:00+07
103	2	1	3761	0	2026-06-22 12:00:00+07
25	2	1	1179	0	2026-06-22 01:00:00+07
27	2	0	0	0	2026-06-22 01:00:00+07
29	2	2	60	0	2026-06-22 01:00:00+07
35	2	0	0	0	2026-06-22 02:00:00+07
36	2	2	60	0	2026-06-22 02:00:00+07
37	2	1	1103	0	2026-06-22 02:00:00+07
41	2	1	1122	0	2026-06-22 03:00:00+07
42	2	2	60	0	2026-06-22 03:00:00+07
43	2	0	0	0	2026-06-22 03:00:00+07
50	2	0	0	0	2026-06-22 04:00:00+07
51	2	1	1123	0	2026-06-22 04:00:00+07
52	2	2	60	0	2026-06-22 04:00:00+07
54	2	2	60	0	2026-06-22 05:00:00+07
56	2	0	0	0	2026-06-22 05:00:00+07
58	2	1	1163	0	2026-06-22 05:00:00+07
59	2	1	1142	0	2026-06-22 06:00:00+07
60	2	2	60	0	2026-06-22 06:00:00+07
62	2	0	0	0	2026-06-22 06:00:00+07
65	2	0	0	0	2026-06-22 07:00:00+07
69	2	2	60	0	2026-06-22 07:00:00+07
70	2	1	1153	0	2026-06-22 07:00:00+07
72	2	1	1107	0	2026-06-22 08:00:00+07
73	2	2	60	0	2026-06-22 08:00:00+07
74	2	0	0	0	2026-06-22 08:00:00+07
83	1	0	0	0	2026-06-22 10:00:00+07
85	1	2	1	0	2026-06-22 11:00:00+07
86	2	1	1782	0	2026-06-22 10:00:00+07
88	1	1	2053	0	2026-06-22 11:00:00+07
78	2	2	75	0	2026-06-22 09:00:00+07
90	2	2	80	0	2026-06-22 10:00:00+07
92	2	3	1	0	2026-06-22 11:00:00+07
93	2	0	0	0	2026-06-22 10:00:00+07
94	1	3	1	0	2026-06-22 10:00:00+07
79	2	1	1696	0	2026-06-22 09:00:00+07
96	1	1	3149	0	2026-06-22 10:00:00+07
97	1	2	2	0	2026-06-22 10:00:00+07
82	2	0	0	0	2026-06-22 09:00:00+07
99	1	0	0	0	2026-06-22 11:00:00+07
84	2	0	0	0	2026-06-22 11:00:00+07
87	2	1	2861	0	2026-06-22 11:00:00+07
102	1	2	4	0	2026-06-22 12:00:00+07
91	2	2	121	0	2026-06-22 11:00:00+07
105	1	0	0	0	2026-06-22 12:00:00+07
107	1	1	6884	0	2026-06-22 12:00:00+07
106	2	2	117	0	2026-06-22 12:00:00+07
108	2	0	0	0	2026-06-22 12:00:00+07
115	1	1	1628	0	2026-06-22 13:00:00+07
109	2	2	87	0	2026-06-22 13:00:00+07
111	2	0	0	0	2026-06-22 13:00:00+07
112	2	1	2543	0	2026-06-22 13:00:00+07
120	1	0	0	0	2026-06-22 13:00:00+07
123	1	2	1	0	2026-06-22 13:00:00+07
117	2	0	0	0	2026-06-22 14:00:00+07
126	1	3	1	0	2026-06-22 14:00:00+07
129	1	0	0	0	2026-06-22 14:00:00+07
130	1	2	2	0	2026-06-22 14:00:00+07
131	1	1	742	0	2026-06-22 14:00:00+07
121	2	2	107	0	2026-06-22 14:00:00+07
122	2	1	2337	0	2026-06-22 14:00:00+07
125	2	0	0	0	2026-06-22 15:00:00+07
127	2	2	66	0	2026-06-22 15:00:00+07
128	2	1	1487	0	2026-06-22 15:00:00+07
140	1	1	1085	0	2026-06-22 16:00:00+07
135	2	2	68	0	2026-06-22 16:00:00+07
145	1	3	1	0	2026-06-22 16:00:00+07
138	2	1	1419	0	2026-06-22 16:00:00+07
139	2	0	0	0	2026-06-22 16:00:00+07
151	2	0	0	0	2026-06-22 18:00:00+07
141	2	2	103	0	2026-06-22 17:00:00+07
153	1	3	4	0	2026-06-22 18:00:00+07
154	1	2	2	0	2026-06-22 18:00:00+07
155	2	2	106	0	2026-06-22 18:00:00+07
143	1	1	1721	0	2026-06-22 17:00:00+07
157	2	1	2367	0	2026-06-22 18:00:00+07
144	2	0	0	0	2026-06-22 17:00:00+07
161	1	1	48812	0	2026-06-22 18:00:00+07
148	2	1	1977	0	2026-06-22 17:00:00+07
149	1	3	2	0	2026-06-22 17:00:00+07
164	1	0	0	0	2026-06-22 18:00:00+07
150	2	0	0	0	2026-06-22 19:00:00+07
166	1	0	0	0	2026-06-22 19:00:00+07
167	1	1	2756	0	2026-06-22 19:00:00+07
168	1	2	1	0	2026-06-22 19:00:00+07
158	2	2	31	0	2026-06-22 19:00:00+07
160	2	1	623	0	2026-06-22 19:00:00+07
171	1	3	1	0	2026-06-22 19:00:00+07
172	1	0	0	0	2026-06-22 23:00:00+07
173	1	2	4	0	2026-06-22 23:00:00+07
174	1	1	2119	0	2026-06-23 00:00:00+07
175	1	2	1	0	2026-06-23 00:00:00+07
176	1	0	0	0	2026-06-23 00:00:00+07
177	1	1	8605	0	2026-06-22 23:00:00+07
178	1	2	1	0	2026-06-23 01:00:00+07
179	1	0	0	0	2026-06-23 01:00:00+07
180	1	1	2222	0	2026-06-23 01:00:00+07
181	2	2	37	0	2026-06-23 09:00:00+07
182	2	0	0	0	2026-06-23 09:00:00+07
183	2	1	838	0	2026-06-23 09:00:00+07
184	1	0	0	0	2026-06-23 10:00:00+07
185	2	0	0	0	2026-06-23 10:00:00+07
186	1	1	2350	0	2026-06-23 10:00:00+07
187	1	1	11074	0	2026-06-23 11:00:00+07
188	1	2	1	0	2026-06-23 10:00:00+07
189	2	2	23	0	2026-06-23 11:00:00+07
191	2	1	1237	0	2026-06-23 10:00:00+07
192	2	1	671	0	2026-06-23 11:00:00+07
193	1	0	0	0	2026-06-23 11:00:00+07
194	1	2	1	0	2026-06-23 11:00:00+07
195	1	3	1	0	2026-06-23 10:00:00+07
196	2	0	0	0	2026-06-23 11:00:00+07
197	2	2	43	0	2026-06-23 10:00:00+07
198	2	3	5	0	2026-06-23 11:00:00+07
200	1	3	3	0	2026-06-23 11:00:00+07
201	2	2	68	0	2026-06-23 12:00:00+07
202	1	0	0	0	2026-06-23 12:00:00+07
203	2	3	8	0	2026-06-23 13:00:00+07
206	1	0	0	0	2026-06-23 13:00:00+07
190	2	1	1526	0	2026-06-23 12:00:00+07
209	1	2	1	0	2026-06-23 12:00:00+07
210	1	1	3058	0	2026-06-23 12:00:00+07
211	1	2	1	0	2026-06-23 13:00:00+07
212	2	0	0	0	2026-06-23 12:00:00+07
213	1	1	1643	0	2026-06-23 13:00:00+07
199	2	3	4	0	2026-06-23 12:00:00+07
216	1	3	1	0	2026-06-23 14:00:00+07
217	2	1	12439	0	2026-06-23 14:00:00+07
218	2	0	0	0	2026-06-23 14:00:00+07
204	2	0	0	0	2026-06-23 13:00:00+07
222	1	1	14212	0	2026-06-23 14:00:00+07
205	2	1	5288	0	2026-06-23 13:00:00+07
207	2	2	93	0	2026-06-23 13:00:00+07
226	2	3	16	0	2026-06-23 14:00:00+07
227	1	0	0	0	2026-06-23 14:00:00+07
228	1	2	2	0	2026-06-23 14:00:00+07
229	2	2	128	0	2026-06-23 14:00:00+07
282	1	2	6	0	2026-06-23 19:00:00+07
285	1	1	969059	0	2026-06-23 19:00:00+07
215	2	0	0	0	2026-06-23 15:00:00+07
219	2	1	6073	0	2026-06-23 15:00:00+07
220	2	3	4	0	2026-06-23 15:00:00+07
224	2	2	128	0	2026-06-23 15:00:00+07
235	2	3	7	0	2026-06-23 16:00:00+07
289	1	0	0	0	2026-06-23 19:00:00+07
291	1	3	7	0	2026-06-23 19:00:00+07
292	2	0	0	0	2026-06-23 19:00:00+07
237	2	1	30119	0	2026-06-23 16:00:00+07
238	2	0	0	0	2026-06-23 16:00:00+07
244	1	1	26292	0	2026-06-23 16:00:00+07
245	1	2	8	0	2026-06-23 16:00:00+07
246	1	0	0	0	2026-06-23 16:00:00+07
240	2	2	243	0	2026-06-23 16:00:00+07
248	1	2	18	0	2026-06-23 17:00:00+07
262	1	3	6	0	2026-06-23 17:00:00+07
251	2	2	126	0	2026-06-23 17:00:00+07
255	2	0	0	0	2026-06-23 17:00:00+07
256	1	0	0	0	2026-06-23 17:00:00+07
257	1	1	791216	0	2026-06-23 17:00:00+07
258	2	1	5774	0	2026-06-23 17:00:00+07
293	2	2	96	0	2026-06-23 19:00:00+07
294	2	1	4657	0	2026-06-23 19:00:00+07
296	2	2	60	0	2026-06-23 20:00:00+07
260	2	1	2226	0	2026-06-23 18:00:00+07
263	1	1	4092263	0	2026-06-23 18:00:00+07
264	1	0	0	0	2026-06-23 18:00:00+07
265	1	3	12	0	2026-06-23 18:00:00+07
266	2	2	109	0	2026-06-23 18:00:00+07
267	2	0	0	0	2026-06-23 18:00:00+07
269	1	2	14	0	2026-06-23 18:00:00+07
302	2	0	0	0	2026-06-23 20:00:00+07
303	2	1	1737	0	2026-06-23 20:00:00+07
312	1	2	3	0	2026-06-23 21:00:00+07
313	1	1	70470	0	2026-06-23 21:00:00+07
306	2	0	0	0	2026-06-23 21:00:00+07
307	2	1	3283	0	2026-06-23 21:00:00+07
310	2	2	81	0	2026-06-23 21:00:00+07
319	1	0	0	0	2026-06-23 21:00:00+07
311	2	2	88	0	2026-06-23 22:00:00+07
316	2	1	4443	0	2026-06-23 22:00:00+07
317	2	0	0	0	2026-06-23 22:00:00+07
320	2	1	1738	0	2026-06-23 23:00:00+07
322	2	0	0	0	2026-06-23 23:00:00+07
323	2	2	63	0	2026-06-23 23:00:00+07
326	2	0	0	0	2026-06-24 00:00:00+07
329	2	2	75	0	2026-06-24 00:00:00+07
331	2	1	4324	0	2026-06-24 00:00:00+07
333	2	0	0	0	2026-06-24 01:00:00+07
341	1	1	71894	0	2026-06-24 02:00:00+07
342	1	0	0	0	2026-06-24 01:00:00+07
343	1	2	8	0	2026-06-24 02:00:00+07
344	1	2	3	0	2026-06-24 01:00:00+07
335	2	1	3568	0	2026-06-24 01:00:00+07
336	2	2	63	0	2026-06-24 01:00:00+07
348	1	1	38903	0	2026-06-24 01:00:00+07
349	1	0	0	0	2026-06-24 02:00:00+07
338	2	0	0	0	2026-06-24 02:00:00+07
339	2	2	138	0	2026-06-24 02:00:00+07
345	2	1	5143	0	2026-06-24 02:00:00+07
351	2	0	0	0	2026-06-24 03:00:00+07
353	2	2	120	0	2026-06-24 03:00:00+07
355	2	1	2133	0	2026-06-24 03:00:00+07
356	2	1	2182	0	2026-06-24 04:00:00+07
358	2	0	0	0	2026-06-24 04:00:00+07
364	2	0	0	0	2026-06-24 05:00:00+07
359	2	2	120	0	2026-06-24 04:00:00+07
366	2	2	120	0	2026-06-24 05:00:00+07
367	2	1	2120	0	2026-06-24 05:00:00+07
368	2	1	1658	0	2026-06-24 06:00:00+07
370	2	0	0	0	2026-06-24 06:00:00+07
373	2	2	88	0	2026-06-24 06:00:00+07
375	2	2	60	0	2026-06-24 07:00:00+07
376	2	1	1362	0	2026-06-24 07:00:00+07
378	2	0	0	0	2026-06-24 07:00:00+07
380	2	2	60	0	2026-06-24 08:00:00+07
381	2	0	0	0	2026-06-24 08:00:00+07
385	2	1	1528	0	2026-06-24 08:00:00+07
388	2	0	0	0	2026-06-24 09:00:00+07
389	2	1	2190	0	2026-06-24 09:00:00+07
390	2	2	80	0	2026-06-24 09:00:00+07
392	2	1	3175	0	2026-06-24 10:00:00+07
393	2	2	119	0	2026-06-24 10:00:00+07
396	2	0	0	0	2026-06-24 10:00:00+07
398	46	2	2	0	2026-06-24 11:00:00+07
399	46	1	1927	0	2026-06-24 11:00:00+07
400	46	0	0	0	2026-06-24 11:00:00+07
401	2	0	0	0	2026-06-24 11:00:00+07
402	2	1	2447	0	2026-06-24 11:00:00+07
405	2	2	99	0	2026-06-24 11:00:00+07
407	46	3	9	0	2026-06-24 11:00:00+07
411	46	3	17	0	2026-06-24 12:00:00+07
470	2	2	60	0	2026-06-24 17:00:00+07
471	2	0	0	0	2026-06-24 17:00:00+07
474	2	1	1581	0	2026-06-24 17:00:00+07
412	46	0	0	0	2026-06-24 12:00:00+07
414	2	0	0	0	2026-06-24 12:00:00+07
415	2	1	1955	0	2026-06-24 12:00:00+07
417	46	2	11	0	2026-06-24 12:00:00+07
437	46	3	4	0	2026-06-24 13:00:00+07
420	2	2	120	0	2026-06-24 12:00:00+07
421	46	1	21059	0	2026-06-24 12:00:00+07
427	2	1	1972	0	2026-06-24 13:00:00+07
428	46	2	25	0	2026-06-24 13:00:00+07
429	2	0	0	0	2026-06-24 13:00:00+07
430	46	0	0	0	2026-06-24 13:00:00+07
432	46	1	43855	0	2026-06-24 13:00:00+07
436	2	2	120	0	2026-06-24 13:00:00+07
440	2	1	2376	0	2026-06-24 14:00:00+07
441	2	2	120	0	2026-06-24 14:00:00+07
443	2	0	0	0	2026-06-24 14:00:00+07
456	46	0	0	0	2026-06-24 16:00:00+07
458	46	1	9742	0	2026-06-24 15:00:00+07
459	1	1	16080	0	2026-06-24 16:00:00+07
452	2	1	1860	0	2026-06-24 15:00:00+07
461	46	0	0	0	2026-06-24 15:00:00+07
462	1	2	1	0	2026-06-24 16:00:00+07
463	46	2	8	0	2026-06-24 16:00:00+07
464	46	2	6	0	2026-06-24 15:00:00+07
465	46	1	11625	0	2026-06-24 16:00:00+07
467	1	0	0	0	2026-06-24 16:00:00+07
453	2	0	0	0	2026-06-24 15:00:00+07
454	2	2	84	0	2026-06-24 15:00:00+07
455	2	1	7389	0	2026-06-24 16:00:00+07
457	2	2	83	0	2026-06-24 16:00:00+07
466	2	0	0	0	2026-06-24 16:00:00+07
482	46	0	0	0	2026-06-24 17:00:00+07
483	46	1	9968	0	2026-06-24 17:00:00+07
484	46	2	3	0	2026-06-24 17:00:00+07
478	2	2	60	0	2026-06-24 18:00:00+07
480	2	0	0	0	2026-06-24 18:00:00+07
481	2	1	1613	0	2026-06-24 18:00:00+07
488	2	0	0	0	2026-06-24 19:00:00+07
489	2	1	1691	0	2026-06-24 19:00:00+07
490	2	2	60	0	2026-06-24 19:00:00+07
491	2	0	0	0	2026-06-24 20:00:00+07
493	2	2	60	0	2026-06-24 20:00:00+07
496	2	1	1823	0	2026-06-24 20:00:00+07
503	46	2	2	0	2026-06-24 22:00:00+07
504	46	3	1	0	2026-06-24 22:00:00+07
498	2	2	60	0	2026-06-24 21:00:00+07
499	2	0	0	0	2026-06-24 21:00:00+07
509	46	0	0	0	2026-06-24 22:00:00+07
501	2	1	1798	0	2026-06-24 21:00:00+07
512	46	1	7978	0	2026-06-24 22:00:00+07
513	2	0	0	0	2026-06-24 23:00:00+07
514	46	3	2	0	2026-06-24 23:00:00+07
515	46	2	9	0	2026-06-24 23:00:00+07
516	2	2	27	0	2026-06-24 23:00:00+07
507	2	2	82	0	2026-06-24 22:00:00+07
518	2	1	591	0	2026-06-24 23:00:00+07
508	2	1	1809	0	2026-06-24 22:00:00+07
520	46	0	0	0	2026-06-25 00:00:00+07
521	46	0	0	0	2026-06-24 23:00:00+07
522	46	2	6	0	2026-06-25 00:00:00+07
523	46	1	11217	0	2026-06-25 00:00:00+07
524	46	1	25147	0	2026-06-24 23:00:00+07
511	2	0	0	0	2026-06-24 22:00:00+07
\.


--
-- Data for Name: insights_metadata; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.insights_metadata ("metaId", "workflowId", "projectId", "workflowName", "projectName") FROM stdin;
1	TL2qrOygnWKY69xe	40KI2a4v2OVG1X1W	03 - Docs Hub	Admin User <admin@local.test>
2	AdM1nFlow12345678CD0cHub2	40KI2a4v2OVG1X1W	04 - Docs Admin (CRUD UI)	Admin User <admin@local.test>
46	wb0BxLBPY80gSVpK	edYLrSaB7ytcV98Hy	HR Line Agent Bot (State Machine + NLP)	Fluke Jesadakorn <jesadakorn.kirtnu@gmail.com>
\.


--
-- Data for Name: insights_raw; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.insights_raw (id, "metaId", type, value, "timestamp") FROM stdin;
\.


--
-- Data for Name: installed_nodes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.installed_nodes (name, type, "latestVersion", package) FROM stdin;
\.


--
-- Data for Name: installed_packages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.installed_packages ("packageName", "installedVersion", "authorName", "authorEmail", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_checkpoints; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_checkpoints (key, "runId", "threadId", "resourceId", state, "createdAt", "updatedAt", "expiredAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_iteration_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_iteration_logs (id, "threadId", "taskKey", entry, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_mcp_registry_connections; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_mcp_registry_connections (id, "credentialId", "serverSlug", "toolFilter", "userId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_messages (id, "threadId", content, role, type, "resourceId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_observation_cursors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_observation_cursors ("observationScopeId", "lastObservedMessageId", "lastObservedAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_observation_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_observation_locks ("observationScopeId", "taskKind", "holderId", "heldUntil", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_observational_memory; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_observational_memory (id, "lookupKey", scope, "threadId", "resourceId", "activeObservations", "originType", config, "generationCount", "lastObservedAt", "pendingMessageTokens", "totalTokensObserved", "observationTokenCount", "isObserving", "isReflecting", "observedMessageIds", "observedTimezone", "bufferedObservations", "bufferedObservationTokens", "bufferedMessageIds", "bufferedReflection", "bufferedReflectionTokens", "bufferedReflectionInputTokens", "reflectedObservationLineCount", "bufferedObservationChunks", "isBufferingObservation", "isBufferingReflection", "lastBufferedAtTokens", "lastBufferedAtTime", metadata, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_observations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_observations (id, "observationScopeId", marker, text, "parentId", "tokenCount", status, "supersededBy", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_pending_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_pending_confirmations ("requestId", "threadId", "userId", kind, "runId", "toolCallId", "messageGroupId", "checkpointKey", "checkpointTaskId", "expiresAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_resources; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_resources (id, "workingMemory", metadata, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_ai_run_snapshots; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_run_snapshots ("threadId", "runId", "messageGroupId", "runIds", tree, "createdAt", "updatedAt", "langsmithRunId", "langsmithTraceId", "traceId", "spanId") FROM stdin;
\.


--
-- Data for Name: instance_ai_threads; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_threads (id, "resourceId", title, metadata, "createdAt", "updatedAt", "projectId") FROM stdin;
\.


--
-- Data for Name: instance_ai_workflow_snapshots; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_ai_workflow_snapshots ("runId", "workflowName", "resourceId", status, snapshot, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: instance_version_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.instance_version_history (id, major, minor, patch, "createdAt") FROM stdin;
1	2	26	8	2026-06-21 15:57:17.437+07
\.


--
-- Data for Name: invalid_auth_token; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.invalid_auth_token (token, "expiresAt") FROM stdin;
\.


--
-- Data for Name: mcp_registry_server; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.mcp_registry_server (slug, status, version, "registryUpdatedAt", data, "createdAt", "updatedAt") FROM stdin;
notion	active	1.0.1	2026-06-11 19:29:07.703	{"id":1,"name":"com.notion/mcp","title":"Notion","tagline":"Connect to the Notion MCP Server","description":"Official Notion MCP server","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:49:13.571Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":1,"type":"streamable-http","url":"https://mcp.notion.com/mcp"},{"id":2,"type":"sse","url":"https://mcp.notion.com/sse"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idjb_Qg_E_jj_26d71d08b5.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idjb_Qg_E_jj_5fcfcab5f8.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
atlassian	active	1.1.1	2026-06-11 19:28:42.32	{"id":2,"name":"com.atlassian/atlassian-mcp-server","title":"Atlassian","tagline":"Connect to the Atlassian MCP Server","description":"Atlassian Rovo MCP Server","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:49:24.904Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":3,"type":"streamable-http","url":"https://mcp.atlassian.com/v1/mcp"},{"id":4,"type":"sse","url":"https://mcp.atlassian.com/v1/sse"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_KV_Ejn_Mrk_716d407499.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_KV_Ejn_Mrk_1f404ecbfd.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
apify	active	0.10.6	2026-06-11 19:28:32.446	{"id":3,"name":"com.apify/apify-mcp-server","title":"Apify","tagline":"Connect to the Apify MCP Server","description":"Extract data from any website with thousands of scrapers, crawlers, and automations on Apify Store ⚡","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:49:36.524Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":5,"type":"streamable-http","url":"https://mcp.apify.com/"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_S_Uz5c4rz_d01d21b490.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id6k3_J_n_Mi_ceeccc3a3e.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
stripe	active	0.2.4	2026-06-11 19:29:33.086	{"id":4,"name":"com.stripe/mcp","title":"Stripe","tagline":"Connect to the Stripe MCP Server","description":"MCP server integrating with Stripe - tools for customers, products, payments, and more.","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:49:47.930Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":6,"type":"streamable-http","url":"https://mcp.stripe.com"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_Bn9_1_Njr_e4279db01b.jpeg","mimeType":"image/jpeg","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
monday-com	active	0.0.1	2026-06-11 19:29:02.947	{"id":5,"name":"com.monday/monday.com","title":"monday.com","tagline":"Connect to the monday.com MCP Server","description":"MCP server for monday.com integration.","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:49:59.434Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":7,"type":"streamable-http","url":"https://mcp.monday.com/mcp"},{"id":8,"type":"sse","url":"https://mcp.monday.com/sse"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idz_Vgm_C8_SV_4533eff3c2.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
git-lab	active	0.0.1	2026-06-11 19:28:56.391	{"id":6,"name":"com.gitlab/mcp","title":"GitLab","tagline":"Connect to the GitLab MCP Server","description":"Official GitLab MCP Server","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:50:10.745Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":9,"type":"streamable-http","url":"https://gitlab.com/api/v4/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idkt3_Cw41b_9f7043ad83.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_O_Daz_Q_Zbt_f76933a2e6.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
linear	active	1.0.0	2026-06-11 19:28:04.979	{"id":7,"name":"app.linear/linear","title":"Linear","tagline":"Connect to the Linear MCP Server","description":"MCP server for Linear project management and issue tracking","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:50:22.156Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":11,"type":"sse","url":"https://mcp.linear.app/sse"},{"id":10,"type":"streamable-http","url":"https://mcp.linear.app/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_P3_K9_Q_jj_6b6c66c6c7.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_P3_K9_Q_jj_7d409a8856.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
webflow	active	2.0.0	2026-06-11 19:29:37.869	{"id":8,"name":"com.webflow/mcp","title":"Webflow","tagline":"Connect to the Webflow MCP Server","description":"AI-powered design and management for Webflow Sites","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:50:33.630Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":12,"type":"streamable-http","url":"https://mcp.webflow.com/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idx_GYKE_Fj1_b568d3380a.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_Zp72_NUI_5_080d2c331c.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
pay-pal	active	1.0.0	2026-06-11 19:29:23.307	{"id":9,"name":"com.paypal.mcp/mcp","title":"PayPal","tagline":"Connect to the PayPal MCP Server","description":"PayPal MCP server provides access to PayPal services and operations for AI assistants","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:50:45.127Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":13,"type":"streamable-http","url":"https://mcp.paypal.com/mcp"},{"id":14,"type":"sse","url":"https://mcp.paypal.com/sse"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_R_Wy_Aj_C_Dz_324a3b0a2e.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
post-hog	active	0.2.5	2026-06-11 19:29:53.047	{"id":10,"name":"io.github.PostHog/mcp","title":"PostHog","tagline":"Connect to the PostHog MCP Server","description":"Official PostHog MCP Server for product analytics, feature flags, experiments, and more.","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:50:56.421Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":16,"type":"streamable-http","url":"https://mcp.posthog.com/mcp"},{"id":15,"type":"sse","url":"https://mcp.posthog.com/sse"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_Yz0_Wt_S_Oc_8e4d0f0070.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
amplitude	active	1.0.0	2026-06-11 19:28:25.27	{"id":11,"name":"com.amplitude/mcp-server","title":"Amplitude","tagline":"Connect to the Amplitude MCP Server","description":"Search, access, and get insights on your Amplitude data","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:51:08.257Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":17,"type":"streamable-http","url":"https://mcp.amplitude.com/mcp"},{"id":18,"type":"streamable-http","url":"https://mcp.eu.amplitude.com/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_G_Fjvl8_Pa_bd331a64fc.svg","mimeType":"image/svg+xml","theme":"dark"},{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_G_Fjvl8_Pa_a15896d97c.svg","mimeType":"image/svg+xml","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
postman	active	2.8.9	2026-06-11 19:29:28.445	{"id":12,"name":"com.postman/postman-mcp-server","title":"Postman","tagline":"Connect to the Postman MCP Server","description":"A basic MCP server to operate on the Postman API.","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:51:20.254Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":19,"type":"streamable-http","url":"https://mcp.postman.com/mcp"},{"id":20,"type":"streamable-http","url":"https://mcp.postman.com/minimal"},{"id":21,"type":"streamable-http","url":"https://mcp.eu.postman.com/mcp"},{"id":22,"type":"streamable-http","url":"https://mcp.eu.postman.com/minimal"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idr_UU_WRCO_c111cb0dea.png","mimeType":"image/png","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
close	active	1.0.1	2026-06-11 19:28:50.223	{"id":13,"name":"com.close/close-mcp","title":"Close","tagline":"Connect to the Close MCP Server","description":"Close CRM to manage your sales pipeline. Learn more at https://close.com or https://mcp.close.com","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:51:32.979Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":23,"type":"streamable-http","url":"https://mcp.close.com/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idpghi9sa_C_14d2cba8bf.png","mimeType":"image/png","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
wix	active	1.0.2	2026-06-11 19:29:47.22	{"id":14,"name":"com.wix/mcp","title":"Wix","tagline":"Connect to the Wix MCP Server","description":"A Model Context Protocol server for Wix AI tools","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:51:44.311Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":24,"type":"sse","url":"https://mcp.wix.com/sse"},{"id":25,"type":"streamable-http","url":"https://mcp.wix.com/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_Qa_F_Jx_Orc_31d963143f.jpeg","mimeType":"image/jpeg","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
prisma	active	1.0.0	2026-06-11 19:30:05.827	{"id":15,"name":"io.prisma/mcp","title":"Prisma","tagline":"Connect to the Prisma MCP Server","description":"MCP server for managing Prisma Postgres.","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:51:55.545Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":26,"type":"sse","url":"https://mcp.prisma.io/sse"},{"id":27,"type":"streamable-http","url":"https://mcp.prisma.io/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/idz_L_5t_H6_B_e6163aea2d.jpg","mimeType":"image/jpeg","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
sanity	active	2.19.0	2026-06-11 19:30:10.774	{"id":16,"name":"io.sanity.www/mcp","title":"Sanity","tagline":"Connect to the Sanity MCP Server","description":"Direct access to your Sanity projects (content, datasets, releases, schemas) and agent rules","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:52:07.029Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":28,"type":"streamable-http","url":"https://mcp.sanity.io"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_Qr019q7c_e4c0ec82b7.png","mimeType":"image/png","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
axiom	active	1.0.0	2026-06-11 19:28:11.99	{"id":17,"name":"co.axiom/mcp","title":"Axiom","tagline":"Connect to the Axiom MCP Server","description":"List datasets, schemas, run APL queries, and use prompts for exploration, anomalies, and monitoring.","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:52:18.335Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":30,"type":"sse","url":"https://mcp.axiom.co/sse"},{"id":29,"type":"streamable-http","url":"https://mcp.axiom.co/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_Xjr_Dncs4_d8a390ab33.jpeg","mimeType":"image/jpeg","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
hugging-face	active	0.2.33	2026-06-11 19:28:18.177	{"id":18,"name":"co.huggingface/hf-mcp-server","title":"Hugging Face","tagline":"Connect to the Hugging Face MCP Server","description":"Connect to Hugging Face Hub and thousands of Gradio AI Applications","websiteUrl":null,"authType":"oauth2","isOfficial":true,"isPublished":true,"origin":"registry","createdAt":"2026-05-19T16:52:30.024Z","publishedAt":"2026-06-18T09:50:05.210Z","remotes":[{"id":32,"type":"streamable-http","url":"https://huggingface.co/mcp?login"},{"id":31,"type":"streamable-http","url":"https://huggingface.co/mcp"},{"id":33,"type":"streamable-http","url":"https://huggingface.co/mcp"}],"tools":[],"tags":{"data":[]},"extendsCredential":null,"icons":[{"src":"https://n8niostorageaccount.blob.core.windows.net/n8nio-strapi-blobs-prod/assets/id_S6h_Od6z2_c35cc34669.jpeg","mimeType":"image/jpeg","theme":"light"}]}	2026-06-21 15:57:18.041+07	2026-06-21 23:58:18.37+07
\.


--
-- Data for Name: migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.migrations (id, "timestamp", name) FROM stdin;
1	1587669153312	InitialMigration1587669153312
2	1589476000887	WebhookModel1589476000887
3	1594828256133	CreateIndexStoppedAt1594828256133
4	1607431743768	MakeStoppedAtNullable1607431743768
5	1611144599516	AddWebhookId1611144599516
6	1617270242566	CreateTagEntity1617270242566
7	1620824779533	UniqueWorkflowNames1620824779533
8	1626176912946	AddwaitTill1626176912946
9	1630419189837	UpdateWorkflowCredentials1630419189837
10	1644422880309	AddExecutionEntityIndexes1644422880309
11	1646834195327	IncreaseTypeVarcharLimit1646834195327
12	1646992772331	CreateUserManagement1646992772331
13	1648740597343	LowerCaseUserEmail1648740597343
14	1652254514002	CommunityNodes1652254514002
15	1652367743993	AddUserSettings1652367743993
16	1652905585850	AddAPIKeyColumn1652905585850
17	1654090467022	IntroducePinData1654090467022
18	1658932090381	AddNodeIds1658932090381
19	1659902242948	AddJsonKeyPinData1659902242948
20	1660062385367	CreateCredentialsUserRole1660062385367
21	1663755770893	CreateWorkflowsEditorRole1663755770893
22	1664196174001	WorkflowStatistics1664196174001
23	1665484192212	CreateCredentialUsageTable1665484192212
24	1665754637025	RemoveCredentialUsageTable1665754637025
25	1669739707126	AddWorkflowVersionIdColumn1669739707126
26	1669823906995	AddTriggerCountColumn1669823906995
27	1671535397530	MessageEventBusDestinations1671535397530
28	1671726148421	RemoveWorkflowDataLoadedFlag1671726148421
29	1673268682475	DeleteExecutionsWithWorkflows1673268682475
30	1674138566000	AddStatusToExecutions1674138566000
31	1674509946020	CreateLdapEntities1674509946020
32	1675940580449	PurgeInvalidWorkflowConnections1675940580449
33	1676996103000	MigrateExecutionStatus1676996103000
34	1677236854063	UpdateRunningExecutionStatus1677236854063
35	1677501636754	CreateVariables1677501636754
36	1679416281778	CreateExecutionMetadataTable1679416281778
37	1681134145996	AddUserActivatedProperty1681134145996
38	1681134145997	RemoveSkipOwnerSetup1681134145997
39	1690000000000	MigrateIntegerKeysToString1690000000000
40	1690000000020	SeparateExecutionData1690000000020
41	1690000000030	RemoveResetPasswordColumns1690000000030
42	1690000000030	AddMfaColumns1690000000030
43	1690787606731	AddMissingPrimaryKeyOnExecutionData1690787606731
44	1691088862123	CreateWorkflowNameIndex1691088862123
45	1692967111175	CreateWorkflowHistoryTable1692967111175
46	1693491613982	ExecutionSoftDelete1693491613982
47	1693554410387	DisallowOrphanExecutions1693554410387
48	1694091729095	MigrateToTimestampTz1694091729095
49	1695128658538	AddWorkflowMetadata1695128658538
50	1695829275184	ModifyWorkflowHistoryNodesAndConnections1695829275184
51	1700571993961	AddGlobalAdminRole1700571993961
52	1705429061930	DropRoleMapping1705429061930
53	1711018413374	RemoveFailedExecutionStatus1711018413374
54	1711390882123	MoveSshKeysToDatabase1711390882123
55	1712044305787	RemoveNodesAccess1712044305787
56	1714133768519	CreateProject1714133768519
57	1714133768521	MakeExecutionStatusNonNullable1714133768521
58	1717498465931	AddActivatedAtUserSetting1717498465931
59	1720101653148	AddConstraintToExecutionMetadata1720101653148
60	1721377157740	FixExecutionMetadataSequence1721377157740
61	1723627610222	CreateInvalidAuthTokenTable1723627610222
62	1723796243146	RefactorExecutionIndices1723796243146
63	1724753530828	CreateAnnotationTables1724753530828
64	1724951148974	AddApiKeysTable1724951148974
65	1726606152711	CreateProcessedDataTable1726606152711
66	1727427440136	SeparateExecutionCreationFromStart1727427440136
67	1728659839644	AddMissingPrimaryKeyOnAnnotationTagMapping1728659839644
68	1729607673464	UpdateProcessedDataValueColumnToText1729607673464
69	1729607673469	AddProjectIcons1729607673469
70	1730386903556	CreateTestDefinitionTable1730386903556
71	1731404028106	AddDescriptionToTestDefinition1731404028106
72	1731582748663	MigrateTestDefinitionKeyToString1731582748663
73	1732271325258	CreateTestMetricTable1732271325258
74	1732549866705	CreateTestRun1732549866705
75	1733133775640	AddMockedNodesColumnToTestDefinition1733133775640
76	1734479635324	AddManagedColumnToCredentialsTable1734479635324
77	1736172058779	AddStatsColumnsToTestRun1736172058779
78	1736947513045	CreateTestCaseExecutionTable1736947513045
79	1737715421462	AddErrorColumnsToTestRuns1737715421462
80	1738709609940	CreateFolderTable1738709609940
81	1739549398681	CreateAnalyticsTables1739549398681
82	1740445074052	UpdateParentFolderIdColumn1740445074052
83	1741167584277	RenameAnalyticsToInsights1741167584277
84	1742918400000	AddScopesColumnToApiKeys1742918400000
85	1745322634000	ClearEvaluation1745322634000
86	1745587087521	AddWorkflowStatisticsRootCount1745587087521
87	1745934666076	AddWorkflowArchivedColumn1745934666076
88	1745934666077	DropRoleTable1745934666077
89	1747824239000	AddProjectDescriptionColumn1747824239000
90	1750252139166	AddLastActiveAtColumnToUser1750252139166
91	1750252139166	AddScopeTables1750252139166
92	1750252139167	AddRolesTables1750252139167
93	1750252139168	LinkRoleToUserTable1750252139168
94	1750252139170	RemoveOldRoleColumn1750252139170
95	1752669793000	AddInputsOutputsToTestCaseExecution1752669793000
96	1753953244168	LinkRoleToProjectRelationTable1753953244168
97	1754475614601	CreateDataStoreTables1754475614601
98	1754475614602	ReplaceDataStoreTablesWithDataTables1754475614602
99	1756906557570	AddTimestampsToRoleAndRoleIndexes1756906557570
100	1758731786132	AddAudienceColumnToApiKeys1758731786132
101	1758794506893	AddProjectIdToVariableTable1758794506893
102	1759399811000	ChangeValueTypesForInsights1759399811000
103	1760019379982	CreateChatHubTables1760019379982
104	1760020000000	CreateChatHubAgentTable1760020000000
105	1760020838000	UniqueRoleNames1760020838000
106	1760116750277	CreateOAuthEntities1760116750277
107	1760314000000	CreateWorkflowDependencyTable1760314000000
108	1760965142113	DropUnusedChatHubColumns1760965142113
109	1761047826451	AddWorkflowVersionColumn1761047826451
110	1761655473000	ChangeDependencyInfoToJson1761655473000
111	1761773155024	AddAttachmentsToChatHubMessages1761773155024
112	1761830340990	AddToolsColumnToChatHubTables1761830340990
113	1762177736257	AddWorkflowDescriptionColumn1762177736257
114	1762763704614	BackfillMissingWorkflowHistoryRecords1762763704614
115	1762771264000	ChangeDefaultForIdInUserTable1762771264000
116	1762771954619	AddIsGlobalColumnToCredentialsTable1762771954619
117	1762847206508	AddWorkflowHistoryAutoSaveFields1762847206508
118	1763047800000	AddActiveVersionIdColumn1763047800000
119	1763048000000	ActivateExecuteWorkflowTriggerWorkflows1763048000000
120	1763572724000	ChangeOAuthStateColumnToUnboundedVarchar1763572724000
121	1763716655000	CreateBinaryDataTable1763716655000
122	1764167920585	CreateWorkflowPublishHistoryTable1764167920585
123	1764276827837	AddCreatorIdToProjectTable1764276827837
124	1764682447000	CreateDynamicCredentialResolverTable1764682447000
125	1764689388394	AddDynamicCredentialEntryTable1764689388394
126	1765448186933	BackfillMissingWorkflowHistoryRecords1765448186933
127	1765459448000	AddResolvableFieldsToCredentials1765459448000
128	1765788427674	AddIconToAgentTable1765788427674
129	1765804780000	ConvertAgentIdToUuid1765804780000
130	1765886667897	AddAgentIdForeignKeys1765886667897
131	1765892199653	AddWorkflowVersionIdToExecutionData1765892199653
132	1766064542000	AddWorkflowPublishScopeToProjectRoles1766064542000
133	1766068346315	AddChatMessageIndices1766068346315
134	1766500000000	ExpandInsightsWorkflowIdLength1766500000000
135	1767018516000	ChangeWorkflowStatisticsFKToNoAction1767018516000
136	1768402473068	ExpandModelColumnLength1768402473068
137	1768557000000	AddStoredAtToExecutionEntity1768557000000
138	1768901721000	AddDynamicCredentialUserEntryTable1768901721000
139	1769000000000	AddPublishedVersionIdToWorkflowDependency1769000000000
140	1769433700000	CreateSecretsProviderConnectionTables1769433700000
141	1769698710000	CreateWorkflowPublishedVersionTable1769698710000
142	1769784356000	ExpandSubjectIDColumnLength1769784356000
143	1769900001000	AddWorkflowUnpublishScopeToCustomRoles1769900001000
144	1770000000000	CreateChatHubToolsTable1770000000000
145	1770000000000	ExpandProviderIdColumnLength1770000000000
146	1770220686000	CreateWorkflowBuilderSessionTable1770220686000
147	1771417407753	AddScalingFieldsToTestRun1771417407753
148	1771500000000	MigrateExternalSecretsToEntityStorage1771500000000
149	1771500000001	AddUnshareScopeToCustomRoles1771500000001
150	1771500000002	AddFilesColumnToChatHubAgents1771500000002
151	1772000000000	AddSuggestedPromptsToAgentTable1772000000000
152	1772619247761	AddRoleColumnToProjectSecretsProviderAccess1772619247761
153	1772619247762	ChangeWorkflowPublishedVersionFKsToRestrict1772619247762
154	1772700000000	AddTypeToChatHubSessions1772700000000
155	1772800000000	CreateRoleMappingRuleTable1772800000000
156	1773000000000	CreateCredentialDependencyTable1773000000000
157	1774280963551	AddRestoreFieldsToWorkflowBuilderSession1774280963551
158	1774854660000	CreateInstanceVersionHistoryTable1774854660000
159	1775000000000	CreateInstanceAiTables1775000000000
160	1775116241000	CreateTokenExchangeJtiTable1775116241000
161	1775740765000	ChangeWorkflowPublishHistoryVersionIdToSetNull1775740765000
162	1776000000000	CreateTrustedKeyTables1776000000000
163	1776150756000	CreateFavoritesTable1776150756000
164	1777000000000	CreateDeploymentKeyTable1777000000000
165	1777023444000	AddJweKeyIndexesToDeploymentKey1777023444000
166	1777045000000	AddTracingContextToExecution1777045000000
167	1777100000000	AddLangsmithIdsToInstanceAiRunSnapshots1777100000000
168	1777281990043	CreateAiBuilderTemporaryWorkflowTable1777281990043
169	1777420800000	ExpandVariablesValueColumnToText1777420800000
170	1777996709110	AddRunIndexToTestCaseExecution1777996709110
171	1778000000000	AddExecutionDeduplicationKey1778000000000
172	1778100000000	CreateEvaluationConfig1778100000000
173	1778100001000	AddWorkflowVersionToTestRun1778100001000
174	1778100002000	AddEvaluationConfigColumnsToTestRun1778100002000
175	1778496086558	CreateEvaluationCollection1778496086558
176	1783000000000	CreateAgentTables1783000000000
177	1783000000001	CreateAgentExecutionTables1783000000001
178	1784000000000	CreateAgentObservationTables1784000000000
179	1784000000001	ReplaceAgentObservationTables1784000000001
180	1784000000002	DropAgentExecutionWorkingMemory1784000000002
181	1784000000003	LimitWorkflowVersionTriggerToContent1784000000003
182	1784000000004	AddInsightsRawTimestampIdIndex1784000000004
183	1784000000005	CreateMcpRegistryServerTable1784000000005
184	1784000000006	AddNodeGroupsColumnToWorkflowAndHistory1784000000006
185	1784000000007	CreateInstanceAiCheckpointTable1784000000007
186	1784000000008	ResetInstanceAiNativePersistence1784000000008
187	1784000000009	CreateAgentMemoryEntryTables1784000000009
188	1784000000010	RefactorAgentObservationScope1784000000010
189	1784000000011	CreateAgentHistoryTable1784000000011
190	1784000000012	CreateInstanceAiObservationTables1784000000012
191	1784000000013	SplitRedactionScopeInCustomRoles1784000000013
192	1784000000014	PersistInstanceAiPendingConfirmations1784000000014
193	1784000000015	AddSourceWorkflowIdToWorkflow1784000000015
194	1784000000016	UseSlugAsPrimaryKeyInMcpRegistryServer1784000000016
195	1784000000017	AddLastUsedAtToApiKey1784000000017
196	1784000000018	CreateAgentFilesTable1784000000018
197	1784000000019	AddCustomTelemetryTagsToProject1784000000019
198	1784000000021	CreateAgentTaskDefinitionTable1784000000021
199	1784000000022	AddSubAgentLinkageToAgentExecutionThreads1784000000022
200	1784000000023	CreateInstanceAiMcpRegistryConnectionTable1784000000023
201	1784000000024	AddResourceToOAuthAuthorizationCodes1784000000024
202	1784000000025	MigrateRedactionEnforcementToFloor1784000000025
203	1784000000026	AddScopeColumnToOAuthTables1784000000026
204	1784000000027	CreateWorkflowPublicationOutboxTable1784000000027
205	1784000000028	AddProjectIdToInstanceAiThread1784000000028
\.


--
-- Data for Name: oauth_access_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth_access_tokens (token, "clientId", "userId") FROM stdin;
\.


--
-- Data for Name: oauth_authorization_codes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth_authorization_codes (code, "clientId", "userId", "redirectUri", "codeChallenge", "codeChallengeMethod", "expiresAt", state, used, "createdAt", "updatedAt", resource, scope) FROM stdin;
\.


--
-- Data for Name: oauth_clients; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth_clients (id, name, "redirectUris", "grantTypes", "clientSecret", "clientSecretExpiresAt", "tokenEndpointAuthMethod", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: oauth_refresh_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth_refresh_tokens (token, "clientId", "userId", "expiresAt", "createdAt", "updatedAt", scope) FROM stdin;
\.


--
-- Data for Name: oauth_user_consents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth_user_consents (id, "userId", "clientId", "grantedAt") FROM stdin;
\.


--
-- Data for Name: processed_data; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.processed_data ("workflowId", context, "createdAt", "updatedAt", value) FROM stdin;
\.


--
-- Data for Name: project; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.project (id, name, type, "createdAt", "updatedAt", icon, description, "creatorId", "customTelemetryTags") FROM stdin;
40KI2a4v2OVG1X1W	Admin User <admin@local.test>	personal	2026-06-21 15:57:15.807+07	2026-06-21 16:00:40.953+07	\N	\N	5c824990-2ef0-4078-80b0-3c09056f2f12	[]
edYLrSaB7ytcV98Hy	Fluke Jesadakorn <jesadakorn.kirtnu@gmail.com>	personal	2026-06-21 23:00:01.237+07	2026-06-21 23:00:01.237+07	\N	\N	35364927-4efa-4921-b395-25d6fee03c8d	[]
\.


--
-- Data for Name: project_relation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.project_relation ("projectId", "userId", role, "createdAt", "updatedAt") FROM stdin;
40KI2a4v2OVG1X1W	5c824990-2ef0-4078-80b0-3c09056f2f12	project:personalOwner	2026-06-21 15:57:15.807+07	2026-06-21 15:57:15.807+07
edYLrSaB7ytcV98Hy	35364927-4efa-4921-b395-25d6fee03c8d	project:personalOwner	2026-06-21 23:00:01.237+07	2026-06-21 23:00:01.237+07
\.


--
-- Data for Name: project_secrets_provider_access; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.project_secrets_provider_access ("secretsProviderConnectionId", "projectId", "createdAt", "updatedAt", role) FROM stdin;
\.


--
-- Data for Name: role; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role (slug, "displayName", description, "roleType", "systemRole", "createdAt", "updatedAt") FROM stdin;
global:chatUser	Chat User	Chat User	global	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
global:owner	Owner	Owner	global	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.627+07
global:admin	Admin	Admin	global	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.627+07
global:member	Member	Member	global	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.627+07
project:admin	Project Admin	Full control of settings, members, workflows, credentials and executions	project	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.64+07
project:personalOwner	Project Owner	Project Owner	project	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.64+07
project:editor	Project Editor	Create, edit, and delete workflows, credentials, and executions	project	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.64+07
project:viewer	Project Viewer	Read-only access to workflows, credentials, and executions	project	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.64+07
project:chatUser	Project Chat User	Chat-only access to chatting with workflows that have n8n Chat enabled	project	t	2026-06-21 15:57:16.042+07	2026-06-21 15:57:16.64+07
credential:owner	Credential Owner	Credential Owner	credential	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
credential:user	Credential User	Credential User	credential	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
workflow:owner	Workflow Owner	Workflow Owner	workflow	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
workflow:editor	Workflow Editor	Workflow Editor	workflow	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
secretsProviderConnection:owner	Secrets Provider Connection Owner	Full control of secrets provider connection settings and secrets	secretsProviderConnection	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
secretsProviderConnection:user	Secrets Provider Connection User	Read-only access to use secrets from the connection	secretsProviderConnection	t	2026-06-21 15:57:16.606+07	2026-06-21 15:57:16.606+07
\.


--
-- Data for Name: role_mapping_rule; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role_mapping_rule (id, expression, role, type, "order", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: role_mapping_rule_project; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role_mapping_rule_project ("roleMappingRuleId", "projectId") FROM stdin;
\.


--
-- Data for Name: role_scope; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role_scope ("roleSlug", "scopeSlug") FROM stdin;
global:owner	workflow:unpublish
global:owner	workflow:unshare
global:owner	credential:unshare
global:owner	agent:create
global:owner	agent:read
global:owner	agent:update
global:owner	agent:delete
global:owner	agent:list
global:owner	agent:execute
global:owner	agent:publish
global:owner	agent:unpublish
global:owner	agent:manage
global:owner	aiAssistant:manage
global:owner	annotationTag:create
global:owner	annotationTag:read
global:owner	annotationTag:update
global:owner	annotationTag:delete
global:owner	annotationTag:list
global:owner	auditLogs:manage
global:owner	banner:dismiss
global:owner	community:register
global:owner	communityPackage:install
global:owner	communityPackage:uninstall
global:owner	communityPackage:update
global:owner	communityPackage:list
global:owner	credential:share
global:owner	credential:shareGlobally
global:owner	credential:move
global:owner	credential:create
global:owner	credential:read
global:owner	credential:update
global:owner	credential:delete
global:owner	credential:list
global:owner	externalSecretsProvider:sync
global:owner	externalSecretsProvider:create
global:owner	externalSecretsProvider:read
global:owner	externalSecretsProvider:update
global:owner	externalSecretsProvider:delete
global:owner	externalSecretsProvider:list
global:owner	externalSecret:list
global:owner	eventBusDestination:test
global:owner	eventBusDestination:create
global:owner	eventBusDestination:read
global:owner	eventBusDestination:update
global:owner	eventBusDestination:delete
global:owner	eventBusDestination:list
global:owner	ldap:sync
global:owner	ldap:manage
global:owner	license:manage
global:owner	logStreaming:manage
global:owner	orchestration:read
global:owner	project:create
global:owner	project:read
global:owner	project:update
global:owner	project:delete
global:owner	project:list
global:owner	saml:manage
global:owner	securityAudit:generate
global:owner	securitySettings:manage
global:owner	sourceControl:pull
global:owner	sourceControl:push
global:owner	sourceControl:manage
global:owner	tag:create
global:owner	tag:read
global:owner	tag:update
global:owner	tag:delete
global:owner	tag:list
global:owner	user:resetPassword
global:owner	user:changeRole
global:owner	user:enforceMfa
global:owner	user:generateInviteLink
global:owner	user:create
global:owner	user:read
global:owner	user:update
global:owner	user:delete
global:owner	user:list
global:owner	variable:create
global:owner	variable:read
global:owner	variable:update
global:owner	variable:delete
global:owner	variable:list
global:owner	projectVariable:create
global:owner	projectVariable:read
global:owner	projectVariable:update
global:owner	projectVariable:delete
global:owner	projectVariable:list
global:owner	workersView:manage
global:owner	workflow:share
global:owner	workflow:execute
global:owner	workflow:execute-chat
global:owner	workflow:export
global:owner	workflow:import
global:owner	workflow:move
global:owner	workflow:create
global:owner	workflow:read
global:owner	workflow:update
global:owner	workflow:delete
global:owner	workflow:list
global:owner	folder:create
global:owner	folder:read
global:owner	folder:update
global:owner	folder:delete
global:owner	folder:list
global:owner	folder:move
global:owner	insights:list
global:owner	insights:read
global:owner	oidc:manage
global:owner	provisioning:manage
global:owner	dataTable:create
global:owner	dataTable:read
global:owner	dataTable:update
global:owner	dataTable:delete
global:owner	dataTable:list
global:owner	dataTable:readRow
global:owner	dataTable:writeRow
global:owner	dataTable:readColumn
global:owner	dataTable:writeColumn
global:owner	dataTable:listProject
global:owner	execution:reveal
global:owner	role:manage
global:owner	mcp:manage
global:owner	mcp:oauth
global:owner	mcpApiKey:create
global:owner	mcpApiKey:rotate
global:owner	chatHub:manage
global:owner	chatHub:message
global:owner	chatHubAgent:create
global:owner	chatHubAgent:read
global:owner	chatHubAgent:update
global:owner	chatHubAgent:delete
global:owner	chatHubAgent:list
global:owner	breakingChanges:list
global:owner	apiKey:manage
global:owner	apiKey:list
global:owner	apiKey:create
global:owner	apiKey:delete
global:owner	apiKey:update
global:owner	encryptionKey:manage
global:owner	credentialResolver:create
global:owner	credentialResolver:read
global:owner	credentialResolver:update
global:owner	credentialResolver:delete
global:owner	credentialResolver:list
global:owner	instanceAi:message
global:owner	instanceAi:manage
global:owner	instanceAi:gateway
global:owner	roleMappingRule:create
global:owner	roleMappingRule:read
global:owner	roleMappingRule:update
global:owner	roleMappingRule:delete
global:owner	roleMappingRule:list
global:owner	workflow:publish
global:owner	workflow:enableRedaction
global:owner	workflow:disableRedaction
global:admin	workflow:unpublish
global:admin	workflow:unshare
global:admin	credential:unshare
global:admin	agent:create
global:admin	agent:read
global:admin	agent:update
global:admin	agent:delete
global:admin	agent:list
global:admin	agent:execute
global:admin	agent:publish
global:admin	agent:unpublish
global:admin	agent:manage
global:admin	aiAssistant:manage
global:admin	annotationTag:create
global:admin	annotationTag:read
global:admin	annotationTag:update
global:admin	annotationTag:delete
global:admin	annotationTag:list
global:admin	auditLogs:manage
global:admin	banner:dismiss
global:admin	community:register
global:admin	communityPackage:install
global:admin	communityPackage:uninstall
global:admin	communityPackage:update
global:admin	communityPackage:list
global:admin	credential:share
global:admin	credential:shareGlobally
global:admin	credential:move
global:admin	credential:create
global:admin	credential:read
global:admin	credential:update
global:admin	credential:delete
global:admin	credential:list
global:admin	externalSecretsProvider:sync
global:admin	externalSecretsProvider:create
global:admin	externalSecretsProvider:read
global:admin	externalSecretsProvider:update
global:admin	externalSecretsProvider:delete
global:admin	externalSecretsProvider:list
global:admin	externalSecret:list
global:admin	eventBusDestination:test
global:admin	eventBusDestination:create
global:admin	eventBusDestination:read
global:admin	eventBusDestination:update
global:admin	eventBusDestination:delete
global:admin	eventBusDestination:list
global:admin	ldap:sync
global:admin	ldap:manage
global:admin	license:manage
global:admin	logStreaming:manage
global:admin	orchestration:read
global:admin	project:create
global:admin	project:read
global:admin	project:update
global:admin	project:delete
global:admin	project:list
global:admin	saml:manage
global:admin	securityAudit:generate
global:admin	securitySettings:manage
global:admin	sourceControl:pull
global:admin	sourceControl:push
global:admin	sourceControl:manage
global:admin	tag:create
global:admin	tag:read
global:admin	tag:update
global:admin	tag:delete
global:admin	tag:list
global:admin	user:resetPassword
global:admin	user:changeRole
global:admin	user:enforceMfa
global:admin	user:generateInviteLink
global:admin	user:create
global:admin	user:read
global:admin	user:update
global:admin	user:delete
global:admin	user:list
global:admin	variable:create
global:admin	variable:read
global:admin	variable:update
global:admin	variable:delete
global:admin	variable:list
global:admin	projectVariable:create
global:admin	projectVariable:read
global:admin	projectVariable:update
global:admin	projectVariable:delete
global:admin	projectVariable:list
global:admin	workersView:manage
global:admin	workflow:share
global:admin	workflow:execute
global:admin	workflow:execute-chat
global:admin	workflow:export
global:admin	workflow:import
global:admin	workflow:move
global:admin	workflow:create
global:admin	workflow:read
global:admin	workflow:update
global:admin	workflow:delete
global:admin	workflow:list
global:admin	folder:create
global:admin	folder:read
global:admin	folder:update
global:admin	folder:delete
global:admin	folder:list
global:admin	folder:move
global:admin	insights:list
global:admin	insights:read
global:admin	oidc:manage
global:admin	provisioning:manage
global:admin	dataTable:create
global:admin	dataTable:read
global:admin	dataTable:update
global:admin	dataTable:delete
global:admin	dataTable:list
global:admin	dataTable:readRow
global:admin	dataTable:writeRow
global:admin	dataTable:readColumn
global:admin	dataTable:writeColumn
global:admin	dataTable:listProject
global:admin	execution:reveal
global:admin	role:manage
global:admin	mcp:manage
global:admin	mcp:oauth
global:admin	mcpApiKey:create
global:admin	mcpApiKey:rotate
global:admin	chatHub:manage
global:admin	chatHub:message
global:admin	chatHubAgent:create
global:admin	chatHubAgent:read
global:admin	chatHubAgent:update
global:admin	chatHubAgent:delete
global:admin	chatHubAgent:list
global:admin	breakingChanges:list
global:admin	apiKey:manage
global:admin	apiKey:list
global:admin	apiKey:create
global:admin	apiKey:delete
global:admin	apiKey:update
global:admin	encryptionKey:manage
global:admin	credentialResolver:create
global:admin	credentialResolver:read
global:admin	credentialResolver:update
global:admin	credentialResolver:delete
global:admin	credentialResolver:list
global:admin	instanceAi:message
global:admin	instanceAi:manage
global:admin	instanceAi:gateway
global:admin	roleMappingRule:create
global:admin	roleMappingRule:read
global:admin	roleMappingRule:update
global:admin	roleMappingRule:delete
global:admin	roleMappingRule:list
global:admin	workflow:publish
global:admin	workflow:enableRedaction
global:admin	workflow:disableRedaction
global:member	annotationTag:create
global:member	annotationTag:read
global:member	annotationTag:update
global:member	annotationTag:delete
global:member	annotationTag:list
global:member	eventBusDestination:test
global:member	eventBusDestination:list
global:member	tag:create
global:member	tag:read
global:member	tag:update
global:member	tag:list
global:member	user:list
global:member	variable:read
global:member	variable:list
global:member	dataTable:list
global:member	mcp:oauth
global:member	mcpApiKey:create
global:member	mcpApiKey:rotate
global:member	chatHub:message
global:member	chatHubAgent:create
global:member	chatHubAgent:read
global:member	chatHubAgent:update
global:member	chatHubAgent:delete
global:member	chatHubAgent:list
global:member	apiKey:list
global:member	apiKey:create
global:member	apiKey:delete
global:member	apiKey:update
global:member	credentialResolver:list
global:member	instanceAi:message
global:member	instanceAi:gateway
global:chatUser	chatHub:message
global:chatUser	chatHubAgent:create
global:chatUser	chatHubAgent:read
global:chatUser	chatHubAgent:update
global:chatUser	chatHubAgent:delete
global:chatUser	chatHubAgent:list
project:admin	workflow:unpublish
project:admin	credential:unshare
project:admin	agent:create
project:admin	agent:read
project:admin	agent:update
project:admin	agent:delete
project:admin	agent:list
project:admin	agent:execute
project:admin	agent:publish
project:admin	agent:unpublish
project:admin	credential:share
project:admin	credential:move
project:admin	credential:create
project:admin	credential:read
project:admin	credential:update
project:admin	credential:delete
project:admin	credential:list
project:admin	project:read
project:admin	project:update
project:admin	project:delete
project:admin	project:list
project:admin	sourceControl:push
project:admin	projectVariable:create
project:admin	projectVariable:read
project:admin	projectVariable:update
project:admin	projectVariable:delete
project:admin	projectVariable:list
project:admin	workflow:execute
project:admin	workflow:execute-chat
project:admin	workflow:export
project:admin	workflow:import
project:admin	workflow:move
project:admin	workflow:create
project:admin	workflow:read
project:admin	workflow:update
project:admin	workflow:delete
project:admin	workflow:list
project:admin	folder:create
project:admin	folder:read
project:admin	folder:update
project:admin	folder:delete
project:admin	folder:list
project:admin	folder:move
project:admin	dataTable:create
project:admin	dataTable:read
project:admin	dataTable:update
project:admin	dataTable:delete
project:admin	dataTable:readRow
project:admin	dataTable:writeRow
project:admin	dataTable:readColumn
project:admin	dataTable:writeColumn
project:admin	dataTable:listProject
project:admin	execution:reveal
project:admin	workflow:publish
project:admin	workflow:enableRedaction
project:admin	workflow:disableRedaction
project:personalOwner	workflow:unpublish
project:personalOwner	workflow:unshare
project:personalOwner	credential:unshare
project:personalOwner	agent:create
project:personalOwner	agent:read
project:personalOwner	agent:update
project:personalOwner	agent:delete
project:personalOwner	agent:list
project:personalOwner	agent:execute
project:personalOwner	agent:publish
project:personalOwner	agent:unpublish
project:personalOwner	credential:share
project:personalOwner	credential:move
project:personalOwner	credential:create
project:personalOwner	credential:read
project:personalOwner	credential:update
project:personalOwner	credential:delete
project:personalOwner	credential:list
project:personalOwner	project:read
project:personalOwner	project:list
project:personalOwner	workflow:share
project:personalOwner	workflow:execute
project:personalOwner	workflow:execute-chat
project:personalOwner	workflow:export
project:personalOwner	workflow:import
project:personalOwner	workflow:move
project:personalOwner	workflow:create
project:personalOwner	workflow:read
project:personalOwner	workflow:update
project:personalOwner	workflow:delete
project:personalOwner	workflow:list
project:personalOwner	folder:create
project:personalOwner	folder:read
project:personalOwner	folder:update
project:personalOwner	folder:delete
project:personalOwner	folder:list
project:personalOwner	folder:move
project:personalOwner	dataTable:create
project:personalOwner	dataTable:read
project:personalOwner	dataTable:update
project:personalOwner	dataTable:delete
project:personalOwner	dataTable:readRow
project:personalOwner	dataTable:writeRow
project:personalOwner	dataTable:readColumn
project:personalOwner	dataTable:writeColumn
project:personalOwner	dataTable:listProject
project:personalOwner	execution:reveal
project:personalOwner	workflow:publish
project:personalOwner	workflow:enableRedaction
project:personalOwner	workflow:disableRedaction
project:editor	workflow:unpublish
project:editor	agent:create
project:editor	agent:read
project:editor	agent:update
project:editor	agent:delete
project:editor	agent:list
project:editor	agent:execute
project:editor	agent:publish
project:editor	agent:unpublish
project:editor	credential:create
project:editor	credential:read
project:editor	credential:update
project:editor	credential:delete
project:editor	credential:list
project:editor	project:read
project:editor	project:list
project:editor	projectVariable:create
project:editor	projectVariable:read
project:editor	projectVariable:update
project:editor	projectVariable:delete
project:editor	projectVariable:list
project:editor	workflow:execute
project:editor	workflow:execute-chat
project:editor	workflow:export
project:editor	workflow:import
project:editor	workflow:create
project:editor	workflow:read
project:editor	workflow:update
project:editor	workflow:delete
project:editor	workflow:list
project:editor	folder:create
project:editor	folder:read
project:editor	folder:update
project:editor	folder:delete
project:editor	folder:list
project:editor	dataTable:create
project:editor	dataTable:read
project:editor	dataTable:update
project:editor	dataTable:delete
project:editor	dataTable:readRow
project:editor	dataTable:writeRow
project:editor	dataTable:readColumn
project:editor	dataTable:writeColumn
project:editor	dataTable:listProject
project:editor	workflow:publish
project:viewer	agent:read
project:viewer	agent:list
project:viewer	agent:execute
project:viewer	credential:read
project:viewer	credential:list
project:viewer	project:read
project:viewer	project:list
project:viewer	projectVariable:read
project:viewer	projectVariable:list
project:viewer	workflow:execute-chat
project:viewer	workflow:export
project:viewer	workflow:read
project:viewer	workflow:list
project:viewer	folder:read
project:viewer	folder:list
project:viewer	dataTable:read
project:viewer	dataTable:readRow
project:viewer	dataTable:readColumn
project:viewer	dataTable:listProject
project:chatUser	agent:execute
project:chatUser	workflow:execute-chat
credential:owner	credential:unshare
credential:owner	credential:share
credential:owner	credential:move
credential:owner	credential:read
credential:owner	credential:update
credential:owner	credential:delete
credential:user	credential:read
workflow:owner	workflow:unpublish
workflow:owner	workflow:unshare
workflow:owner	workflow:share
workflow:owner	workflow:execute
workflow:owner	workflow:execute-chat
workflow:owner	workflow:export
workflow:owner	workflow:move
workflow:owner	workflow:read
workflow:owner	workflow:update
workflow:owner	workflow:delete
workflow:owner	execution:reveal
workflow:owner	workflow:publish
workflow:owner	workflow:enableRedaction
workflow:owner	workflow:disableRedaction
workflow:editor	workflow:unpublish
workflow:editor	workflow:execute
workflow:editor	workflow:execute-chat
workflow:editor	workflow:export
workflow:editor	workflow:read
workflow:editor	workflow:update
workflow:editor	workflow:publish
secretsProviderConnection:owner	externalSecretsProvider:sync
secretsProviderConnection:owner	externalSecretsProvider:read
secretsProviderConnection:owner	externalSecretsProvider:update
secretsProviderConnection:owner	externalSecretsProvider:delete
secretsProviderConnection:owner	externalSecretsProvider:list
secretsProviderConnection:owner	externalSecret:list
secretsProviderConnection:user	externalSecretsProvider:read
secretsProviderConnection:user	externalSecretsProvider:list
secretsProviderConnection:user	externalSecret:list
\.


--
-- Data for Name: scope; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.scope (slug, "displayName", description) FROM stdin;
workflow:unpublish	Unpublish Workflow	Allows unpublishing workflows.
workflow:unshare	Unshare Workflow	Allows removing workflow shares.
credential:unshare	Unshare Credential	Allows removing credential shares.
agent:create	Create Agent	Allows creating new agents in a project.
agent:read	Read Agent	Allows reading agent configuration and history.
agent:update	Update Agent	Allows updating, building, publishing, and managing integrations of agents.
agent:delete	Delete Agent	Allows deleting agents.
agent:list	List Agents	Allows listing agents in a project.
agent:execute	Execute Agent	Allows running agents in chat.
agent:publish	Publish Agent	Allows publishing agents.
agent:unpublish	Unpublish Agent	Allows unpublishing agents.
agent:manage	agent:manage	\N
agent:*	agent:*	\N
aiAssistant:manage	Manage AI Usage	Allows managing AI Usage settings.
aiAssistant:*	aiAssistant:*	\N
annotationTag:create	Create Annotation Tag	Allows creating new annotation tags.
annotationTag:read	annotationTag:read	\N
annotationTag:update	annotationTag:update	\N
annotationTag:delete	annotationTag:delete	\N
annotationTag:list	annotationTag:list	\N
annotationTag:*	annotationTag:*	\N
auditLogs:manage	auditLogs:manage	\N
auditLogs:*	auditLogs:*	\N
banner:dismiss	banner:dismiss	\N
banner:*	banner:*	\N
community:register	community:register	\N
community:*	community:*	\N
communityPackage:install	communityPackage:install	\N
communityPackage:uninstall	communityPackage:uninstall	\N
communityPackage:update	communityPackage:update	\N
communityPackage:list	communityPackage:list	\N
communityPackage:manage	communityPackage:manage	\N
communityPackage:*	communityPackage:*	\N
credential:share	credential:share	\N
credential:shareGlobally	credential:shareGlobally	\N
credential:move	credential:move	\N
credential:create	credential:create	\N
credential:read	credential:read	\N
credential:update	credential:update	\N
credential:delete	credential:delete	\N
credential:list	credential:list	\N
credential:*	credential:*	\N
externalSecretsProvider:sync	externalSecretsProvider:sync	\N
externalSecretsProvider:create	externalSecretsProvider:create	\N
externalSecretsProvider:read	externalSecretsProvider:read	\N
externalSecretsProvider:update	externalSecretsProvider:update	\N
externalSecretsProvider:delete	externalSecretsProvider:delete	\N
externalSecretsProvider:list	externalSecretsProvider:list	\N
externalSecretsProvider:*	externalSecretsProvider:*	\N
externalSecret:list	externalSecret:list	\N
externalSecret:*	externalSecret:*	\N
eventBusDestination:test	eventBusDestination:test	\N
eventBusDestination:create	eventBusDestination:create	\N
eventBusDestination:read	eventBusDestination:read	\N
eventBusDestination:update	eventBusDestination:update	\N
eventBusDestination:delete	eventBusDestination:delete	\N
eventBusDestination:list	eventBusDestination:list	\N
eventBusDestination:*	eventBusDestination:*	\N
ldap:sync	ldap:sync	\N
ldap:manage	ldap:manage	\N
ldap:*	ldap:*	\N
license:manage	license:manage	\N
license:*	license:*	\N
logStreaming:manage	logStreaming:manage	\N
logStreaming:*	logStreaming:*	\N
orchestration:read	orchestration:read	\N
orchestration:list	orchestration:list	\N
orchestration:*	orchestration:*	\N
project:create	project:create	\N
project:read	project:read	\N
project:update	project:update	\N
project:delete	project:delete	\N
project:list	project:list	\N
project:*	project:*	\N
saml:manage	saml:manage	\N
saml:*	saml:*	\N
securityAudit:generate	securityAudit:generate	\N
securityAudit:*	securityAudit:*	\N
securitySettings:manage	securitySettings:manage	\N
securitySettings:*	securitySettings:*	\N
sourceControl:pull	sourceControl:pull	\N
sourceControl:push	sourceControl:push	\N
sourceControl:manage	sourceControl:manage	\N
sourceControl:*	sourceControl:*	\N
tag:create	tag:create	\N
tag:read	tag:read	\N
tag:update	tag:update	\N
tag:delete	tag:delete	\N
tag:list	tag:list	\N
tag:*	tag:*	\N
user:resetPassword	user:resetPassword	\N
user:changeRole	user:changeRole	\N
user:enforceMfa	user:enforceMfa	\N
user:generateInviteLink	user:generateInviteLink	\N
user:create	user:create	\N
user:read	user:read	\N
user:update	user:update	\N
user:delete	user:delete	\N
user:list	user:list	\N
user:*	user:*	\N
variable:create	variable:create	\N
variable:read	variable:read	\N
variable:update	variable:update	\N
variable:delete	variable:delete	\N
variable:list	variable:list	\N
variable:*	variable:*	\N
projectVariable:create	projectVariable:create	\N
projectVariable:read	projectVariable:read	\N
projectVariable:update	projectVariable:update	\N
projectVariable:delete	projectVariable:delete	\N
projectVariable:list	projectVariable:list	\N
projectVariable:*	projectVariable:*	\N
workersView:manage	workersView:manage	\N
workersView:*	workersView:*	\N
workflow:share	workflow:share	\N
workflow:execute	workflow:execute	\N
workflow:execute-chat	workflow:execute-chat	\N
workflow:export	Export Workflow	Allows including workflows in a portable package export.
workflow:import	Import Workflow	Allows importing workflows from a portable package into the project.
workflow:move	workflow:move	\N
workflow:activate	workflow:activate	\N
workflow:deactivate	workflow:deactivate	\N
workflow:create	workflow:create	\N
workflow:read	workflow:read	\N
workflow:update	workflow:update	\N
workflow:delete	workflow:delete	\N
workflow:list	workflow:list	\N
workflow:*	workflow:*	\N
folder:create	folder:create	\N
folder:read	folder:read	\N
folder:update	folder:update	\N
folder:delete	folder:delete	\N
folder:list	folder:list	\N
folder:move	folder:move	\N
folder:*	folder:*	\N
insights:list	insights:list	\N
insights:read	Read Insights	Allows reading insights data.
insights:*	insights:*	\N
oidc:manage	oidc:manage	\N
oidc:*	oidc:*	\N
provisioning:manage	provisioning:manage	\N
provisioning:*	provisioning:*	\N
dataTable:create	dataTable:create	\N
dataTable:read	dataTable:read	\N
dataTable:update	dataTable:update	\N
dataTable:delete	dataTable:delete	\N
dataTable:list	dataTable:list	\N
dataTable:readRow	dataTable:readRow	\N
dataTable:writeRow	dataTable:writeRow	\N
dataTable:readColumn	dataTable:readColumn	\N
dataTable:writeColumn	dataTable:writeColumn	\N
dataTable:listProject	dataTable:listProject	\N
dataTable:*	dataTable:*	\N
execution:delete	execution:delete	\N
execution:read	execution:read	\N
execution:retry	execution:retry	\N
execution:list	execution:list	\N
execution:get	execution:get	\N
execution:reveal	execution:reveal	\N
execution:*	execution:*	\N
workflowTags:update	workflowTags:update	\N
workflowTags:list	workflowTags:list	\N
workflowTags:*	workflowTags:*	\N
role:manage	role:manage	\N
role:*	role:*	\N
mcp:manage	mcp:manage	\N
mcp:oauth	mcp:oauth	\N
mcp:*	mcp:*	\N
mcpApiKey:create	mcpApiKey:create	\N
mcpApiKey:rotate	mcpApiKey:rotate	\N
mcpApiKey:*	mcpApiKey:*	\N
chatHub:manage	chatHub:manage	\N
chatHub:message	chatHub:message	\N
chatHub:*	chatHub:*	\N
chatHubAgent:create	chatHubAgent:create	\N
chatHubAgent:read	chatHubAgent:read	\N
chatHubAgent:update	chatHubAgent:update	\N
chatHubAgent:delete	chatHubAgent:delete	\N
chatHubAgent:list	chatHubAgent:list	\N
chatHubAgent:*	chatHubAgent:*	\N
breakingChanges:list	breakingChanges:list	\N
breakingChanges:*	breakingChanges:*	\N
apiKey:manage	apiKey:manage	\N
apiKey:list	apiKey:list	\N
apiKey:create	apiKey:create	\N
apiKey:delete	apiKey:delete	\N
apiKey:update	apiKey:update	\N
apiKey:*	apiKey:*	\N
encryptionKey:manage	Manage Encryption Keys	Allows listing and rotating instance encryption keys.
encryptionKey:*	encryptionKey:*	\N
credentialResolver:create	credentialResolver:create	\N
credentialResolver:read	credentialResolver:read	\N
credentialResolver:update	credentialResolver:update	\N
credentialResolver:delete	credentialResolver:delete	\N
credentialResolver:list	credentialResolver:list	\N
credentialResolver:*	credentialResolver:*	\N
instanceAi:message	instanceAi:message	\N
instanceAi:manage	instanceAi:manage	\N
instanceAi:gateway	instanceAi:gateway	\N
instanceAi:*	instanceAi:*	\N
roleMappingRule:create	roleMappingRule:create	\N
roleMappingRule:read	roleMappingRule:read	\N
roleMappingRule:update	roleMappingRule:update	\N
roleMappingRule:delete	roleMappingRule:delete	\N
roleMappingRule:list	roleMappingRule:list	\N
roleMappingRule:*	roleMappingRule:*	\N
*	*	\N
workflow:publish	Publish Workflow	Allows publishing workflows.
workflow:enableRedaction	workflow:enableRedaction	\N
workflow:disableRedaction	workflow:disableRedaction	\N
\.


--
-- Data for Name: secrets_provider_connection; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.secrets_provider_connection (id, "providerKey", type, "encryptedSettings", "isEnabled", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.settings (key, value, "loadOnStartup") FROM stdin;
ui.banners.dismissed	["V1"]	t
features.ldap	{"loginEnabled":false,"loginLabel":"","connectionUrl":"","allowUnauthorizedCerts":false,"connectionSecurity":"none","connectionPort":389,"baseDn":"","bindingAdminDn":"","bindingAdminPassword":"","firstNameAttribute":"","lastNameAttribute":"","emailAttribute":"","loginIdAttribute":"","ldapIdAttribute":"","userFilter":"","synchronizationEnabled":false,"synchronizationInterval":60,"searchPageSize":0,"searchTimeout":60,"enforceEmailUniqueness":true}	t
userManagement.isInstanceOwnerSetUp	true	t
instance.firstProductionFailure	{"workflowId":"AdM1nFlow12345678CD0cHub2","projectId":"40KI2a4v2OVG1X1W","userId":"5c824990-2ef0-4078-80b0-3c09056f2f12","timestamp":1782035070038}	f
license.cert	eyJsaWNlbnNlS2V5IjoiLS0tLS1CRUdJTiBMSUNFTlNFIEtFWS0tLS0tXG52QURZZTVqRmd1Z1Eya2I2cnVWRjZ1UEtRU2ZFdGlycUdZeGNaUGFTVjl0bFZ4MFRCNCticDI3S0d4dDhmK01VXG5Uc3FRbzNXbituRVBaaGthbmQ1eDY4N0wzUGRCLzU0cFl2a25jVk5YVitVQUh0TVhENXE2UTBnQk8yb3Myd2l2XG5qZWZQSnNFU0hNdVF0WStRTFdWZFE2TkxlUmM5SlgwUDcrb0czVGJ2UDlzeHhQMjNiTlQzb1lRTUNqVTdmTVAvXG4zRlI4WTlWbWwwcmxlcDlNemR5S005ZDEvUEJBNmRJVk5qejE0VnJCU1QxMW9XbFNRNlpKeUkzcTFreUJDVXNEXG4yeVdNRGh2dktuZlZqcTlVT0NYcHpGTC9xUGRqT3FidWRkQ2x3UkM3SFBORUlicW1zTjlGUnNzaU4yaDJJZ0oxXG5KTnVFNkNsUlR0R1ZyWWFRSnZrK3BnPT18fFUyRnNkR1ZrWDErTEY4MDJ6Nlh6SXlGUDlLNmp1aHZrVWFVanRsXG5PUUFNdFVNU0hndGdHZ29ITC9OUkNYb0R4aGh1TU5RR3Ircys1ODZtZGVHVHZiVGw2aW93cG5NNmxVblM4bUV2XG5pVjh5UXQ5bEFJSGVzSXkvM3FKT2VsVVlWb3AyVDJ0ekdKSlVlZ0ZvYkVCVnVsSFR1d2Y3T1JYbGxNcXdlM2JxXG5oaFVlMXRVYlk5QkpVOHRTdlMwSTc5OUV3R2VVVlNtckNtMkE4VjJuSnhlK1VDU2hhUlBQNDk2WjNib3ZPZkJLXG5LbmR5T2ptT2ZXQWFibmlwbzhlNVlOcC9XM0dVQzBXNGhUdGpSNkErVGVHT1piK09jeGVsbE5PZ3NCUzF0ODB4XG5MR1NuWGRUYy95bWJldE5vOEsyRlJoa2tDeWhGWGFwMVM0WUxlY3pLeFViRG9haDluQ0c5Yy91bzlNdGN3eDl2XG5nWEJZcFJOK2hCKzhsSzVsTFhKamZUNzI0cXFnNFdqZkxoSXhsMEZMUlVJd2xYOEE5M0ZzbnFRWEJ6V25wVmJLXG5vNVFPM1RqeFhqOGxkQVV3dVllRVVuNlFYeEpscEdhUnlpaU9WZk5rVFdsbnhRVjdyZWptWS9BajF0TWVRbGpKXG5qelVMR3k0aE5yMTMzM21rejRZeHB1b1I0dEQvcW14WGRlZkNIcUZmUG9jTEZnejkxc0U2OFJxSWw2aVc3dDRUXG4vOWttNWVjZmgxcTFxQVhTZmVyTmNXRmVrci9oY2kwd2JMSDF4U0hLeEwvN3Vnd25JaStRbUx6c3dSTERlalhTXG5vVWZoL3VFdSs4aEx0YXFwc1Q1a3ZDVzBlT1UwY0NUK3RsT1ZndGF4N1Q2d0NuRXJGbWU1NEVOTFp0MlRGUko5XG43ODVwc3A3LytHV216anJCd25lY1lnNklmVkppK21reUl6dlB4TjM4L3VQRTg2ZXA1alA0aTRJdkpLQ2NQdGdJXG55UlpCZFMzc2VBeVdvRTFOTnNQR2ErWHVFVU1pRlhXbWgxVXFtQUppcWwxWHQ2d3hFdjBFczB2T3pNQktaVlBpXG5zaHF5UUVKM0xJUEZDVDI1SnAvZDE4SXJ5MytRVlVGck15bitDQnAyL2RNMnFOcGJVazVBcmp6YlZsYm9VdHYwXG4xeFZDa3Y2aW5TMWE4T1I1UWZnUTYvRlNLeWFiZDhDRU12V2RhNmRjSjF1VHVuOUdVUThlOXVscmhQb2Z2QktwXG5LTDFsV1VHd0wzbTJSZ3drZ2UrR2VrWndTU2xHV2F4UGQ3bDNEUldKUkhESEFLKzVaa0JkdDFOQUVzcVZYUFhPXG5pTXNqTmxSeWh6UTViVVI5bWpJQTZZRC9CdHdIYUE3UW5MazB6aEVCRytzLzdGS0dBbHFSTHVvcHBNcnowS0dKXG40VGJjVU9IekZIN2czOTRISVh6azQ5VmtPdUdpam9FZ3JoaGFFWlFGSTE0cVRtWkQ4NzBTaXBydXpqVVJEM2RpXG5iNE02N2hjN09YTkF0YkJyT2dnOU5JRHdDU3F3eWhybVEwMkR6dkxtQ0JzSlBQbDBDenZvWVkzaXQwUGpNRWlXXG44cDV2UkFxNUxrSUJDWU8rRE5BczRaUTY3ci9uMGtZWEpUUFp3a1hmeiszcGVDQXcrTEFDTVJ6bTRPTVFuZWwxXG44RkJGVFNjZHYveHBlbGdReXJVWlFHcTdvRkNDamdRbHZWNEphYXFZV3dkem9RK3ZJWXlHblJRSDRFcVJxRlhKXG5GL1VyT3AxbmJCV3VjTzJrdzcrVjZqR3BsZXNJK25Xc3UwZGJTRVRvKzFQcGMycUpBcm0xaG1NOVJySEZjUnJJXG40VnFUUmc3TVRORlpDd0JIU1F2ZU0yamM4SkR5TFJDV3BXVEs4TmdSZDJtWTN3aUhBRnR2ZmJ6bnZHSDJmMkFNXG42dlFVc3liQ0x3QVRVdHYxVFBhZ0lTWHBNOS9nRytoTjNRUmdnWWs2TGcwM1dtYWlsMVJqOHVjQTFmWCttSCsvXG5YaDRIeVRzUlAyN1NoTE9TaWxhYjAwd3BDNUNBajFobmhqaTFNa3VtdXZwSHlDV09sWmlGeFJ1aWQrMDA1ODFrXG43Vi9yQVk1VmtyRlFTTERqdCtGOFBSY1N1bERrU1hsYjFIa3crTGJ1YjVoRGhqUnkzUmhKdXBtMXg3SWUveHk0XG5oaDBrTFpYWVg4RlVkcVpReDQveEhJY3dpMUFyL1pYVmdiZk9IQXVwK0FkMTgxbnFQSEVrdktjaUxaTklCNGIwXG5PMTNtM3ZLQ2RvVTMxK2Vyei9hMWFENkpTb2lYSHJrYU5ZaW0vTk9BSTgzSVBWcXV3U3VWWi9rV0Y5ekc0WmRWXG5iaExwU0h6cHdvQ01KYzJYdmg5anBOUCs1alFweHpMU2RtME11RFN4Q2pSS1hzVmhENG1pVXFINmxLeE1EbE1GXG4xMk00M20rOUdJa2M2OHY3VHdTSCsrRWhTY29uZllrWHJMaTByOERObk1yWDNzejB5amkydjV5eDZqZ0d0SDVYXG5hbSt0S0NyR0d4SnNNNGsxbEd6cHJDaGRCNjZyTS82bFRISjhBc09GNkNGSkxZTjlmQ2JPSGE5YXBxQnNVMDZoXG5UTUVTLzUwRzJqOXIxUGFGeC80a1VmaklValRGWnlzcDBXVHp1dU5qN2s1Ty9wdFc0dG1SU0VqN3pla1lPemtQXG40cG4yYVQ5NG9oOCtKdUJCVUtVc1dLUnBYSlpESmUyUEZZbzNEMkNjUVVDN2Jucmo3TkhJa3dJZmczMWhjL3g2XG5ZbmFKQi9SMHFTWDlVQXVjYkVVcWxIZ0JOc2dGeXhrYThzdEZmTnlYSXdxVFcvYWZlK2RTT0FIODhhMHBrKzV0XG5wd1ROSnM3dnk4R1FYd09KL1B2a0JTMW5sS1A0TnZTbEdQakRqai9WYmpJTkpzV29oZmpFUTNLOVo5Vm1mK2xWXG5xakhaQy9USkxudjd5UDh4MlVNQjlSRGx5VjZRU3lTSiswY3BBWGl5Ujg2a0wwOENVUDA4a0xkVTliellxLzVGXG52Wm9mMWE5aFVrZUMrTHZlMWd2YWlZYlZLNWM4akI2MDVsKzIvWUFKOU1DVXNIREE9PXx8R1UwcTVVSWp0TDJNXG5CVU9aaHdXeGt3azd5TGNSTlJUa0JTS2tnVUN1T1Y4Uk1qakJrOE5wL01odE9TN2ZsanRJWFEyVXJPQXZmSEs2XG5OQUdzMHJQNHhJMzMvVE9QNE1ZRzN2N3J3YWJOZXhXVThjSllVdlBaS2NlNFgrZmt5czduUzJOWGo5OTNWY2pHXG5ESDc2VUZzYWUwdzd0Vk1HcnRCb2FNbnZWSFduQTdCZ3pRVlJubi9XUnlpNDhmcVBrbFltdHN3RVY2eCtabFFJXG5ITkdFbm1XRFlIWm50UWVXdjBoTlRHbzNvVVNoVHdtS05TZFIxa2tuR1EwZHRYS0EyVkNnRUxyODdseHFCb0kvXG52RGpPdFU1SzFNWFFuM29yUVJGMDNHaFRpTTlIOTl3Z00zVnNSbUhQVzA4M24ycVp0RkJaMG9NeEloZnJpbElEXG5QUnlIU092QXh3PT1cbi0tLS0tRU5EIExJQ0VOU0UgS0VZLS0tLS0iLCJ4NTA5IjoiLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tXG5NSUlFRERDQ0FmUUNDUUNxZzJvRFQ4MHh3akFOQmdrcWhraUc5dzBCQVFVRkFEQklNUXN3Q1FZRFZRUUdFd0pFXG5SVEVQTUEwR0ExVUVDQXdHUW1WeWJHbHVNUTh3RFFZRFZRUUhEQVpDWlhKc2FXNHhGekFWQmdOVkJBTU1EbXhwXG5ZMlZ1YzJVdWJqaHVMbWx2TUI0WERUSXlNRFl5TkRBME1UQTBNRm9YRFRJek1EWXlOREEwTVRBME1Gb3dTREVMXG5NQWtHQTFVRUJoTUNSRVV4RHpBTkJnTlZCQWdNQmtKbGNteHBiakVQTUEwR0ExVUVCd3dHUW1WeWJHbHVNUmN3XG5GUVlEVlFRRERBNXNhV05sYm5ObExtNDRiaTVwYnpDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDXG5BUW9DZ2dFQkFNQk0wNVhCNDRnNXhmbUNMd2RwVVR3QVQ4K0NCa3lMS0ZzZXprRDVLLzZXaGFYL1hyc2QvUWQwXG4yMEo3d2w1V2RIVTRjVkJtRlJqVndWemtsQ0syeVlKaThtang4c1hzR3E5UTFsYlVlTUtmVjlkc2dmdWhubEFTXG50blFaZ2x1Z09uRjJGZ1JoWGIvakswdHhUb2FvK2JORTZyNGdJRXpwa3RITEJUWXZ2aXVKbXJlZjdXYlBSdDRJXG5uZDlEN2xoeWJlYnloVjdrdXpqUUEvcFBLSFRGczhNVEhaOGhZVXhSeXJwbTMrTVl6UUQrYmpBMlUxRkljdGFVXG53UVhZV2FON3QydVR3Q3Q5ekFLc21ZL1dlT2J2bDNUWk41T05MQXp5V0dDdWxtNWN3S1IzeGJsQlp6WG5CNmdzXG5Pbk4yT0FkU3RjelRWQ3ljbThwY0ZVcnl0S1NLa0dFQ0F3RUFBVEFOQmdrcWhraUc5dzBCQVFVRkFBT0NBZ0VBXG5sSjAxd2NuMXZqWFhDSHVvaTdSMERKMWxseDErZGFmcXlFcVBBMjdKdStMWG1WVkdYUW9yUzFiOHhqVXFVa2NaXG5UQndiV0ZPNXo1ZFptTnZuYnlqYXptKzZvT2cwUE1hWXhoNlRGd3NJMlBPYmM3YkZ2MmVheXdQdC8xQ3BuYzQwXG5xVU1oZnZSeC9HQ1pQQ1d6My8yUlBKV1g5alFEU0hYQ1hxOEJXK0kvM2N1TERaeVkzZkVZQkIwcDNEdlZtYWQ2XG42V0hRYVVyaU4wL0xxeVNPcC9MWmdsbC90MDI5Z1dWdDA1WmliR29LK2NWaFpFY3NMY1VJaHJqMnVGR0ZkM0ltXG5KTGcxSktKN2pLU0JVUU9kSU1EdnNGVUY3WWRNdk11ckNZQTJzT05OOENaK0k1eFFWMUtTOWV2R0hNNWZtd2dTXG5PUEZ2UHp0RENpMC8xdVc5dE9nSHBvcnVvZGFjdCtFWk5rQVRYQ3ZaaXUydy9xdEtSSkY0VTRJVEVtNWFXMGt3XG42enVDOHh5SWt0N3ZoZHM0OFV1UlNHSDlqSnJBZW1sRWl6dEdJTGhHRHF6UUdZYmxoVVFGR01iQmI3amhlTHlDXG5MSjFXT0c2MkYxc3B4Q0tCekVXNXg2cFIxelQxbWhFZ2Q0TWtMYTZ6UFRwYWNyZDk1QWd4YUdLRUxhMVJXU0ZwXG5NdmRoR2s0TnY3aG5iOHIrQnVNUkM2aWVkUE1DelhxL001MGNOOEFnOGJ3K0oxYUZvKzBFSzJoV0phN2tpRStzXG45R3ZGalNkekNGbFVQaEtra1Vaa1NvNWFPdGNRcTdKdTZrV0JoTG9GWUtncHJscDFRVkIwc0daQTZvNkR0cWphXG5HNy9SazZ2YmFZOHdzTllLMnpCWFRUOG5laDVab1JaL1BKTFV0RUV0YzdZPVxuLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLSJ9	f
\.


--
-- Data for Name: shared_credentials; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.shared_credentials ("credentialsId", "projectId", role, "createdAt", "updatedAt") FROM stdin;
a70ff3bd-3863-49c2-b2d4-e74d97d77c01	edYLrSaB7ytcV98Hy	credential:owner	2026-06-22 00:06:27.392+07	2026-06-22 00:06:27.392+07
27fef0b4-9224-4a77-9741-c4f8e3d0aede	edYLrSaB7ytcV98Hy	credential:owner	2026-06-22 00:06:27.392+07	2026-06-22 00:06:27.392+07
f719a9dd-b576-4cd5-bde6-13fb6344c447	edYLrSaB7ytcV98Hy	credential:owner	2026-06-22 00:06:27.392+07	2026-06-22 00:06:27.392+07
vwf7u64OuSi5ejWs	edYLrSaB7ytcV98Hy	credential:owner	2026-06-24 11:03:53.368+07	2026-06-24 11:03:53.368+07
W5ANm5bXR2xWA4Z2	edYLrSaB7ytcV98Hy	credential:owner	2026-06-24 11:38:57.375+07	2026-06-24 11:38:57.375+07
\.


--
-- Data for Name: shared_workflow; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.shared_workflow ("workflowId", "projectId", role, "createdAt", "updatedAt") FROM stdin;
TL2qrOygnWKY69xe	40KI2a4v2OVG1X1W	workflow:owner	2026-06-21 16:42:45.082+07	2026-06-21 16:42:45.082+07
AdM1nFlow12345678CD0cHub2	40KI2a4v2OVG1X1W	workflow:owner	2026-06-21 16:42:47.854+07	2026-06-21 16:42:47.854+07
wb0BxLBPY80gSVpK	edYLrSaB7ytcV98Hy	workflow:owner	2026-06-24 11:04:16.734+07	2026-06-24 11:04:16.734+07
\.


--
-- Data for Name: tag_entity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tag_entity (name, "createdAt", "updatedAt", id) FROM stdin;
\.


--
-- Data for Name: test_case_execution; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.test_case_execution (id, "testRunId", "executionId", status, "runAt", "completedAt", "errorCode", "errorDetails", metrics, "createdAt", "updatedAt", inputs, outputs, "runIndex") FROM stdin;
\.


--
-- Data for Name: test_run; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.test_run (id, "workflowId", status, "errorCode", "errorDetails", "runAt", "completedAt", metrics, "createdAt", "updatedAt", "runningInstanceId", "cancelRequested", "workflowVersionId", "evaluationConfigId", "evaluationConfigSnapshot", "collectionId") FROM stdin;
\.


--
-- Data for Name: token_exchange_jti; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.token_exchange_jti (jti, "expiresAt", "createdAt") FROM stdin;
\.


--
-- Data for Name: trusted_key; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.trusted_key ("sourceId", kid, data, "createdAt") FROM stdin;
\.


--
-- Data for Name: trusted_key_source; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.trusted_key_source (id, type, config, status, "lastError", "lastRefreshedAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public."user" (id, email, "firstName", "lastName", password, "personalizationAnswers", "createdAt", "updatedAt", settings, disabled, "mfaEnabled", "mfaSecret", "mfaRecoveryCodes", "lastActiveAt", "roleSlug") FROM stdin;
5c824990-2ef0-4078-80b0-3c09056f2f12	admin@local.test	Admin	User	$2b$10$BS16eyGSMrb69SzDLJcjPOhK8JnBHWgTSmjip2B1UBi7qd.r8f/C2	\N	2026-06-21 15:57:15.611+07	2026-06-22 00:40:03.628+07	{"userActivated":true,"firstSuccessfulWorkflowId":"TL2qrOygnWKY69xe","userActivatedAt":1782035239557}	f	f	\N	\N	2026-06-22	global:owner
35364927-4efa-4921-b395-25d6fee03c8d	jesadakorn.kirtnu@gmail.com	Fluke	Jesadakorn	$2a$10$cO0FbG3B8lbOE764fswSXed3zPMeOW6qeOox0rlsIrC/E.YV004KC	{"version":"v4","personalization_survey_submitted_at":"2026-06-21T16:02:02.696Z","personalization_survey_n8n_version":"2.26.8"}	2026-06-21 22:26:55.318+07	2026-06-25 00:07:21.781+07	{"firstSuccessfulWorkflowId":"wb0BxLBPY80gSVpK","userActivated":true,"userActivatedAt":1782273943122}	f	f	\N	\N	2026-06-25	global:owner
\.


--
-- Data for Name: user_api_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_api_keys (id, "userId", label, "apiKey", "createdAt", "updatedAt", scopes, audience, "lastUsedAt") FROM stdin;
Z5Zm9DllxO72cqLU	35364927-4efa-4921-b395-25d6fee03c8d	For AI	eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIzNTM2NDkyNy00ZWZhLTQ5MjEtYjM5NS0yNWQ2ZmVlMDNjOGQiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiNTgyNDYwMGMtM2EwNC00OTIzLWI0NWEtN2JiM2YzYWQ2NTRkIiwiaWF0IjoxNzgyMTA1NTQ2fQ.1sRqdY-bBCcGi7SXITB7IPgKIepSWamvheV7If_mF-c	2026-06-22 12:19:06.48+07	2026-06-24 15:59:29.757+07	["communityPackage:install","communityPackage:uninstall","communityPackage:update","communityPackage:list","credential:move","credential:create","credential:read","credential:update","credential:delete","credential:list","project:create","project:update","project:delete","project:list","securityAudit:generate","sourceControl:pull","tag:create","tag:read","tag:update","tag:delete","tag:list","user:changeRole","user:enforceMfa","user:create","user:read","user:delete","user:list","variable:create","variable:update","variable:delete","variable:list","workflow:export","workflow:import","workflow:move","workflow:create","workflow:read","workflow:update","workflow:delete","workflow:list","folder:create","folder:read","folder:update","folder:delete","folder:list","insights:read","dataTable:create","dataTable:read","dataTable:update","dataTable:delete","dataTable:list","workflowTags:update","workflowTags:list","executionTags:update","executionTags:list","workflow:activate","workflow:deactivate","execution:delete","execution:read","execution:retry","execution:stop","execution:list","dataTableRow:create","dataTableRow:read","dataTableRow:update","dataTableRow:delete","dataTableRow:upsert","dataTableColumn:create","dataTableColumn:read","dataTableColumn:update","dataTableColumn:delete"]	public-api	2026-06-24 15:59:29.754+07
\.


--
-- Data for Name: user_favorites; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_favorites (id, "userId", "resourceId", "resourceType") FROM stdin;
\.


--
-- Data for Name: variables; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.variables (key, type, value, id, "projectId") FROM stdin;
\.


--
-- Data for Name: webhook_entity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.webhook_entity ("webhookPath", method, node, "webhookId", "pathLength", "workflowId") FROM stdin;
hr-line-agent	POST	LINE Webhook	\N	\N	wb0BxLBPY80gSVpK
docs	POST	Docs Webhook	\N	\N	TL2qrOygnWKY69xe
vector-search-json	POST	JS-VS Webhook	\N	\N	TL2qrOygnWKY69xe
contract-rag-line	POST	LINE Webhook	\N	\N	TL2qrOygnWKY69xe
docs-admin-ui	GET	Admin UI Webhook	\N	\N	AdM1nFlow12345678CD0cHub2
admin-list	GET	Admin List	\N	\N	AdM1nFlow12345678CD0cHub2
admin-get	GET	Admin Get	\N	\N	AdM1nFlow12345678CD0cHub2
admin-update	POST	Admin Update	\N	\N	AdM1nFlow12345678CD0cHub2
admin-delete	POST	Admin Delete	\N	\N	AdM1nFlow12345678CD0cHub2
admin-stats	GET	Admin Stats	\N	\N	AdM1nFlow12345678CD0cHub2
admin-file	GET	Admin File	\N	\N	AdM1nFlow12345678CD0cHub2
admin-semantic-search	GET	Admin Semantic Search	\N	\N	AdM1nFlow12345678CD0cHub2
\.


--
-- Data for Name: workflow_builder_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_builder_session (id, "workflowId", "userId", messages, "previousSummary", "createdAt", "updatedAt", "activeVersionCardId", "resumeAfterRestoreMessageId") FROM stdin;
\.


--
-- Data for Name: workflow_dependency; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_dependency (id, "workflowId", "workflowVersionId", "dependencyType", "dependencyKey", "dependencyInfo", "indexVersionId", "createdAt", "publishedVersionId") FROM stdin;
11577	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-prep-reg","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11578	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-gen-seq","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11579	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-gen-seq","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11580	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-insert-doc","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11581	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-insert-doc","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11582	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-reg","nodeVersion":1}	1	2026-06-23 19:26:43.456+07	\N
11583	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse-stats","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11584	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-stats","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11585	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11586	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11587	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-format-stats","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11588	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-stats","nodeVersion":1}	1	2026-06-23 19:26:43.456+07	\N
11589	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-other","nodeVersion":1}	1	2026-06-23 19:26:43.456+07	\N
11590	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-needs-gen","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11591	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-passthrough","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11592	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse-search","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11593	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-mode","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11594	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-list","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11595	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-list","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11596	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"embed-query","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11597	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-vector","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11598	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-vector","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11599	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-render-html","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11600	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-html","nodeVersion":1}	1	2026-06-23 19:26:43.456+07	\N
11601	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-build-vec-params","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11602	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-daily","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11603	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-daily","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11604	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-recent","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11605	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-recent","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11606	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-by-status","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11607	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-by-status","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11608	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"line-chunk","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11609	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-embed","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11610	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"line-combine","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11611	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"line-build-sql","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11612	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"line-insert-chunks","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11613	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"line-insert-chunks","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11614	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-reply-ok","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11615	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"line-reply-ok","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11616	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-reply-err","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11617	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"line-reply-err","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11618	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"line-reg-start-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11619	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"line-reg-start-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11620	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-docs","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11621	TL2qrOygnWKY69xe	57	webhookPath	docs	{"nodeId":"wh-docs","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11622	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-smart-router","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11623	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-route","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11624	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-is-file","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11625	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-not-file","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11626	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"line-not-file","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11627	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-docs","nodeVersion":1}	1	2026-06-23 19:26:43.456+07	\N
11628	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-format-resp","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11629	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ollama-agent","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11630	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse-agent","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11631	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-ai-route","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11632	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-search","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11633	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-text-reply","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11634	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"ai-text-reply","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11635	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-ai-flex","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11636	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-send-flex","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11637	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"ai-send-flex","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11638	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"ai-list-contracts","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11639	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"ai-list-contracts","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11640	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"ai-get-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11641	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"ai-get-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11642	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"ai-format-list","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11643	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"ai-format-stats","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11644	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-vs-json","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11645	TL2qrOygnWKY69xe	57	webhookPath	vector-search-json	{"nodeId":"wh-vs-json","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11646	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"js-vs-parse","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11647	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"js-vs-embed","nodeVersion":4.1}	1	2026-06-23 19:26:43.456+07	\N
11648	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"js-vs-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11649	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"js-vs-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11650	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"js-vs-format","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11651	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"build-safe-reply","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11652	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-decode-prepare","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11653	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.if	{"nodeId":"node-300","nodeVersion":1}	1	2026-06-23 19:26:43.456+07	\N
11654	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-check-rt","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11655	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"if-has-reply-token","nodeVersion":3.2}	1	2026-06-23 19:26:43.456+07	\N
11656	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"63098214-c190-4b93-8f32-4c94ffccb7fc","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11657	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"4f9ec6d5-5947-4b71-8169-9d5b96595407","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11658	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"4f9ec6d5-5947-4b71-8169-9d5b96595407","nodeVersion":2.4}	1	2026-06-23 19:26:43.456+07	\N
11659	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"node-301","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11660	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.webhook	{"nodeId":"line-webhook-trigger","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11661	TL2qrOygnWKY69xe	57	webhookPath	contract-rag-line	{"nodeId":"line-webhook-trigger","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11662	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-extract-vision","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11663	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-rerank-http","nodeVersion":4.2}	1	2026-06-23 19:26:43.456+07	\N
11664	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"ai-rerank-parse","nodeVersion":2}	1	2026-06-23 19:26:43.456+07	\N
11665	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-prep-reg","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11666	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-gen-seq","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11667	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-gen-seq","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11668	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-insert-doc","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11669	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-insert-doc","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11670	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-reg","nodeVersion":1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11671	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse-stats","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11672	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-stats","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11673	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11674	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11675	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-format-stats","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11676	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-stats","nodeVersion":1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11677	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-other","nodeVersion":1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11678	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-needs-gen","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11679	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-passthrough","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11680	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse-search","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11681	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-mode","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11682	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-list","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11683	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-list","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11684	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"embed-query","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11685	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-vector","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11686	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-vector","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11687	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-render-html","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11688	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-html","nodeVersion":1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11689	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-build-vec-params","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11690	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-daily","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11691	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-daily","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11692	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-recent","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11693	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-recent","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11694	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-by-status","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11695	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-by-status","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11696	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"line-chunk","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11697	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-embed","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11698	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"line-combine","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11699	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"line-build-sql","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11700	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"line-insert-chunks","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11701	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"line-insert-chunks","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11702	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-reply-ok","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11703	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"line-reply-ok","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11704	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-reply-err","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11705	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"line-reply-err","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11706	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"line-reg-start-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11707	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"line-reg-start-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11708	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-docs","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11709	TL2qrOygnWKY69xe	57	webhookPath	docs	{"nodeId":"wh-docs","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11710	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-smart-router","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11711	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-route","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11712	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-is-file","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11713	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-not-file","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11714	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"line-not-file","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11715	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-docs","nodeVersion":1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11716	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-format-resp","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11717	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ollama-agent","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11718	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse-agent","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11719	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"sw-ai-route","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11720	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-search","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11721	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-text-reply","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11722	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"ai-text-reply","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11723	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-ai-flex","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11724	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-send-flex","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11725	TL2qrOygnWKY69xe	57	credentialId	27fef0b4-9224-4a77-9741-c4f8e3d0aede	{"nodeId":"ai-send-flex","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11726	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"ai-list-contracts","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11727	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"ai-list-contracts","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11728	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"ai-get-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11729	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"ai-get-stats","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11730	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"ai-format-list","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11731	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"ai-format-stats","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11732	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-vs-json","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11733	TL2qrOygnWKY69xe	57	webhookPath	vector-search-json	{"nodeId":"wh-vs-json","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11734	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"js-vs-parse","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11735	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"js-vs-embed","nodeVersion":4.1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11736	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"js-vs-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11737	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"js-vs-pg","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11738	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"js-vs-format","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11739	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"build-safe-reply","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11740	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-decode-prepare","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11741	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.if	{"nodeId":"node-300","nodeVersion":1}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11742	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"code-check-rt","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11743	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.switch	{"nodeId":"if-has-reply-token","nodeVersion":3.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11744	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"63098214-c190-4b93-8f32-4c94ffccb7fc","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11745	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.postgres	{"nodeId":"4f9ec6d5-5947-4b71-8169-9d5b96595407","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11746	TL2qrOygnWKY69xe	57	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"4f9ec6d5-5947-4b71-8169-9d5b96595407","nodeVersion":2.4}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11747	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"node-301","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11748	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.webhook	{"nodeId":"line-webhook-trigger","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11749	TL2qrOygnWKY69xe	57	webhookPath	contract-rag-line	{"nodeId":"line-webhook-trigger","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11750	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"line-extract-vision","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11751	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ai-rerank-http","nodeVersion":4.2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
11752	TL2qrOygnWKY69xe	57	nodeType	n8n-nodes-base.code	{"nodeId":"ai-rerank-parse","nodeVersion":2}	1	2026-06-23 19:26:43.514+07	9a290dc3-4ead-4606-adec-2f3df5650125
12645	wb0BxLBPY80gSVpK	33	credentialId	vwf7u64OuSi5ejWs	{"nodeId":"pg-execute-actions","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12646	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"http-line-reply","nodeVersion":4.2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12647	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ollama-parse-intent","nodeVersion":4.2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12648	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-notify-manager","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12649	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-format-sql","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12622	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-line-bot","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
11799	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-ui","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11800	AdM1nFlow12345678CD0cHub2	32	webhookPath	docs-admin-ui	{"nodeId":"wh-admin-ui","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11801	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"code-build-html","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11802	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-ui","nodeVersion":1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11803	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-list","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11804	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-list	{"nodeId":"wh-admin-list","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11805	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-get","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11806	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-get	{"nodeId":"wh-admin-get","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11807	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-update","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11808	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-update	{"nodeId":"wh-admin-update","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11809	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-delete","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
12623	wb0BxLBPY80gSVpK	33	webhookPath	hr-line-agent	{"nodeId":"wh-line-bot","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12624	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-200","nodeVersion":1}	1	2026-06-25 00:07:21.844+07	\N
12625	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12626	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-get-session","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12627	wb0BxLBPY80gSVpK	33	credentialId	vwf7u64OuSi5ejWs	{"nodeId":"pg-get-session","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12628	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-controller","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12629	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.if	{"nodeId":"switch-response","nodeVersion":1}	1	2026-06-25 00:07:21.844+07	\N
12630	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-execute-actions","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12631	wb0BxLBPY80gSVpK	33	credentialId	vwf7u64OuSi5ejWs	{"nodeId":"pg-execute-actions","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12632	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"http-line-reply","nodeVersion":4.2}	1	2026-06-25 00:07:21.844+07	\N
12633	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"ollama-parse-intent","nodeVersion":4.2}	1	2026-06-25 00:07:21.844+07	\N
12634	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-notify-manager","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12635	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-format-sql","nodeVersion":2}	1	2026-06-25 00:07:21.844+07	\N
12636	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-line-bot","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12637	wb0BxLBPY80gSVpK	33	webhookPath	hr-line-agent	{"nodeId":"wh-line-bot","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12638	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-200","nodeVersion":1}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12639	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-parse","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12640	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-get-session","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12641	wb0BxLBPY80gSVpK	33	credentialId	vwf7u64OuSi5ejWs	{"nodeId":"pg-get-session","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12642	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-controller","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12643	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.if	{"nodeId":"switch-response","nodeVersion":1}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
12644	wb0BxLBPY80gSVpK	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-execute-actions","nodeVersion":2}	1	2026-06-25 00:07:21.937+07	342bf076-f7ce-4690-884f-889a033db7d9
11810	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-delete	{"nodeId":"wh-admin-delete","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11811	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-stats","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11812	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-stats	{"nodeId":"wh-admin-stats","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11813	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-list","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11814	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-list","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11815	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-get","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11816	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-get","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11817	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-update","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11818	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-update","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11819	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-delete","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11820	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-delete","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11821	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-stats","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11822	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-stats","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11823	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-list","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11824	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-get","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11825	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-update","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11826	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-delete","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11827	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-stats","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11828	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"extract-minio-key-001","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11829	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.s3	{"nodeId":"minio-delete-001","nodeVersion":1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11830	AdM1nFlow12345678CD0cHub2	32	credentialId	f719a9dd-b576-4cd5-bde6-13fb6344c447	{"nodeId":"minio-delete-001","nodeVersion":1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11831	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-file","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11832	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-file	{"nodeId":"wh-admin-file","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11833	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-file","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11834	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-file","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11835	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-file","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11836	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-file","nodeVersion":1.1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11837	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-semantic","nodeVersion":1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11838	AdM1nFlow12345678CD0cHub2	32	webhookPath	admin-semantic-search	{"nodeId":"wh-admin-semantic","nodeVersion":1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11839	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"parse-semantic","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11840	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"embed-semantic","nodeVersion":4.2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11841	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-semantic","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11842	AdM1nFlow12345678CD0cHub2	32	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-semantic","nodeVersion":2.4}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11843	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-semantic","nodeVersion":2}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11844	AdM1nFlow12345678CD0cHub2	32	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-semantic","nodeVersion":1}	1	2026-06-23 22:45:37.705+07	4936517b-f48b-4073-9755-0467045e870c
11845	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-ui","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11846	AdM1nFlow12345678CD0cHub2	33	webhookPath	docs-admin-ui	{"nodeId":"wh-admin-ui","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11847	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"code-build-html","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11848	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-ui","nodeVersion":1}	1	2026-06-24 02:14:33.645+07	\N
11849	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-list","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11850	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-list	{"nodeId":"wh-admin-list","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11851	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-get","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11852	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-get	{"nodeId":"wh-admin-get","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11853	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-update","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11854	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-update	{"nodeId":"wh-admin-update","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11855	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-delete","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11856	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-delete	{"nodeId":"wh-admin-delete","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11857	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-stats","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11858	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-stats	{"nodeId":"wh-admin-stats","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11859	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-list","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11860	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-list","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11861	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-get","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11862	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-get","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11863	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-update","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11864	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-update","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11865	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-delete","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11866	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-delete","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11867	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-stats","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11868	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-stats","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11869	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-list","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11870	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-get","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11871	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-update","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11872	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-delete","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11873	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-stats","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11874	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"extract-minio-key-001","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11875	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.s3	{"nodeId":"minio-delete-001","nodeVersion":1}	1	2026-06-24 02:14:33.645+07	\N
11876	AdM1nFlow12345678CD0cHub2	33	credentialId	f719a9dd-b576-4cd5-bde6-13fb6344c447	{"nodeId":"minio-delete-001","nodeVersion":1}	1	2026-06-24 02:14:33.645+07	\N
11877	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-file","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11878	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-file	{"nodeId":"wh-admin-file","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11879	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-file","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11880	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-file","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11881	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-file","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11882	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-file","nodeVersion":1.1}	1	2026-06-24 02:14:33.645+07	\N
11883	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.webhook	{"nodeId":"wh-admin-semantic","nodeVersion":1}	1	2026-06-24 02:14:33.645+07	\N
11884	AdM1nFlow12345678CD0cHub2	33	webhookPath	admin-semantic-search	{"nodeId":"wh-admin-semantic","nodeVersion":1}	1	2026-06-24 02:14:33.645+07	\N
11885	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"parse-semantic","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11886	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.httpRequest	{"nodeId":"embed-semantic","nodeVersion":4.2}	1	2026-06-24 02:14:33.645+07	\N
11887	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.postgres	{"nodeId":"pg-admin-semantic","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11888	AdM1nFlow12345678CD0cHub2	33	credentialId	a70ff3bd-3863-49c2-b2d4-e74d97d77c01	{"nodeId":"pg-admin-semantic","nodeVersion":2.4}	1	2026-06-24 02:14:33.645+07	\N
11889	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.code	{"nodeId":"wrap-semantic","nodeVersion":2}	1	2026-06-24 02:14:33.645+07	\N
11890	AdM1nFlow12345678CD0cHub2	33	nodeType	n8n-nodes-base.respondToWebhook	{"nodeId":"resp-semantic","nodeVersion":1}	1	2026-06-24 02:14:33.645+07	\N
\.


--
-- Data for Name: workflow_entity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_entity (name, active, nodes, connections, "createdAt", "updatedAt", settings, "staticData", "pinData", "versionId", "triggerCount", id, meta, "parentFolderId", "isArchived", "versionCounter", description, "activeVersionId", "nodeGroups", "sourceWorkflowId") FROM stdin;
HR Line Agent Bot (State Machine + NLP)	t	[{"parameters":{"httpMethod":"POST","path":"hr-line-agent","responseMode":"responseNode","options":{}},"id":"wh-line-bot","name":"LINE Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-256,160],"webhookId":"hr-line-agent-webhook"},{"parameters":{"respondWith":"json","responseBody":"{}","options":{"responseHeaders":{"entries":[{"name":"Content-Type","value":"application/json"}]}}},"id":"resp-200","name":"Respond 200 OK","type":"n8n-nodes-base.respondToWebhook","typeVersion":1,"position":[-32,64]},{"parameters":{"jsCode":"const body = items[0].json.body;\\nif (!body || !body.events || body.events.length === 0) {\\n  return [];\\n}\\n\\nconst event = body.events[0];\\nconst userId = event.source.userId;\\nconst eventType = event.type;\\nconst replyToken = event.replyToken;\\n\\nlet messageText = '';\\nlet postbackData = '';\\nlet postbackParams = {};\\n\\nif (eventType === 'message' && event.message.type === 'text') {\\n  messageText = event.message.text.trim();\\n} else if (eventType === 'postback') {\\n  postbackData = event.postback.data;\\n  postbackParams = event.postback.params || {};\\n}\\n\\nreturn [{\\n  json: {\\n    userId,\\n    eventType,\\n    replyToken,\\n    messageText,\\n    postbackData,\\n    postbackParams\\n  }\\n}];"},"id":"code-parse","name":"Parse LINE Event","type":"n8n-nodes-base.code","typeVersion":2,"position":[-32,256]},{"parameters":{"operation":"executeQuery","query":"SELECT \\n  e.id as employee_id, \\n  e.employee_code, \\n  e.name, \\n  e.position, \\n  e.department, \\n  e.role, \\n  e.job_description,\\n  e.total_sick_leave, e.used_sick_leave,\\n  e.total_annual_leave, e.used_annual_leave,\\n  e.total_personal_leave, e.used_personal_leave,\\n  s.current_state,\\n  s.temp_data\\nFROM (SELECT $1::text as line_id) input\\nLEFT JOIN employees e ON e.line_user_id = input.line_id\\nLEFT JOIN user_sessions s ON s.line_user_id = input.line_id;","options":{"queryReplacement":"={{ [$('Parse LINE Event').first().json.userId] }}"}},"id":"pg-get-session","name":"PG: Get Employee & Session","type":"n8n-nodes-base.postgres","typeVersion":2,"position":[192,256],"credentials":{"postgres":{"id":"vwf7u64OuSi5ejWs","name":"Postgres HR - localhost:5432"}}},{"parameters":{"jsCode":"const input = $('PG: Get Employee & Session').first().json;\\nconst parsedEvent = $('Parse LINE Event').first().json;\\nconst userId = parsedEvent.userId;\\nconst replyToken = parsedEvent.replyToken;\\nconst messageText = parsedEvent.messageText ? parsedEvent.messageText.trim() : '';\\nconst cleanText = messageText.toLowerCase();\\n\\n// Get Ollama NLP output\\nconst ollamaRes = $('Ollama: Parse Intent').first().json.response;\\nlet nlp = { intent: 'general_chat', leave_type: null, start_date: null, end_date: null, days: null, reason: null, employee_code: null, check_date: null };\\ntry {\\n  let cleanRes = ollamaRes.trim();\\n  const jsonMatch = cleanRes.match(/\\\\{[\\\\s\\\\S]*\\\\}/);\\n  if (jsonMatch) {\\n    nlp = JSON.parse(jsonMatch[0]);\\n  } else {\\n    nlp = JSON.parse(cleanRes);\\n  }\\n} catch (e) {\\n  console.error('Failed to parse Ollama JSON:', e);\\n}\\n\\nlet responseType = 'direct_reply';\\nlet replyMessages = [];\\nlet sql = '';\\nlet params = [];\\n\\n// Helper functions for date parsing and days calculation\\nfunction parseDate(text, baseDate = null) {\\n  if (!text) return null;\\n  const clean = text.trim().toLowerCase().replace(/\\\\s+/g, ' ');\\n  const today = new Date(new Date().getTime() + (7 * 60 * 60 * 1000));\\n  const currentYear = today.getFullYear();\\n\\n  // 1. Relative words\\n  if (clean === 'วันนี้') {\\n    return today.toISOString().split('T')[0];\\n  }\\n  if (clean === 'พรุ่งนี้') {\\n    const d = new Date(today.getTime() + (24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'เมื่อวาน' || clean === 'เมื่อวานนี้') {\\n    const d = new Date(today.getTime() - (24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'วานซืน' || clean === 'เมื่อวานซืน') {\\n    const d = new Date(today.getTime() - (2 * 24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'มะรืน' || clean === 'มะรืนนี้') {\\n    const d = new Date(today.getTime() + (2 * 24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n\\n  // 2. Duration match: e.g., \\"3 วัน\\", \\"5 วัน\\", \\"3 days\\"\\n  if (baseDate) {\\n    const durMatch = clean.match(/^(\\\\d+)\\\\s*(วัน|day|days)$/);\\n    if (durMatch) {\\n      const numDays = parseInt(durMatch[1]);\\n      if (numDays > 0) {\\n        const start = new Date(baseDate);\\n        const end = new Date(start.getTime() + ((numDays - 1) * 24 * 60 * 60 * 1000));\\n        return end.toISOString().split('T')[0];\\n      }\\n    }\\n  }\\n\\n  // 3. Parse Thai months\\n  const thaiMonthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];\\n  const thaiMonthsFull = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];\\n\\n  let parsedText = clean;\\n  let monthIndex = -1;\\n  for (let i = 0; i < 12; i++) {\\n    if (clean.includes(thaiMonthsFull[i])) {\\n      monthIndex = i + 1;\\n      parsedText = clean.replace(thaiMonthsFull[i], ' ' + monthIndex + ' ');\\n      break;\\n    }\\n  }\\n  if (monthIndex === -1) {\\n    for (let i = 0; i < 12; i++) {\\n      const term = thaiMonthsShort[i].replace('.', '\\\\\\\\.?');\\n      const regex = new RegExp(term, 'g');\\n      if (regex.test(clean)) {\\n        monthIndex = i + 1;\\n        parsedText = clean.replace(regex, ' ' + monthIndex + ' ');\\n        break;\\n      }\\n    }\\n  }\\n\\n  // Match formats:\\n  // - \\"YYYY-MM-DD\\"\\n  const dateRegexYMD = /^(\\\\d{4})[-/](\\\\d{1,2})[-/](\\\\d{1,2})$/;\\n  const matchYMD = parsedText.match(dateRegexYMD);\\n  if (matchYMD) {\\n    let y = parseInt(matchYMD[1]);\\n    let m = parseInt(matchYMD[2]) - 1;\\n    let d = parseInt(matchYMD[3]);\\n    if (y >= 2400) y -= 543;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // - \\"DD/MM/YYYY\\"\\n  const dateRegexDMY = /^(\\\\d{1,2})[-/ ](\\\\d{1,2})[-/ ](\\\\d{4})$/;\\n  const matchDMY = parsedText.match(dateRegexDMY);\\n  if (matchDMY) {\\n    let d = parseInt(matchDMY[1]);\\n    let m = parseInt(matchDMY[2]) - 1;\\n    let y = parseInt(matchDMY[3]);\\n    if (y >= 2400) y -= 543;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // - \\"DD/MM\\" (e.g. 20/02 or 20 08)\\n  const dateRegexDM = /^(\\\\d{1,2})[-/ ](\\\\d{1,2})$/;\\n  const matchDM = parsedText.match(dateRegexDM);\\n  if (matchDM) {\\n    let d = parseInt(matchDM[1]);\\n    let m = parseInt(matchDM[2]) - 1;\\n    let y = currentYear;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // Digits fallback extraction (e.g. \\"วันที่ 20 เดือน 8\\")\\n  const digits = parsedText.match(/\\\\d+/g);\\n  if (digits) {\\n    if (digits.length === 3) {\\n      let d = parseInt(digits[0]);\\n      let m = parseInt(digits[1]) - 1;\\n      let y = parseInt(digits[2]);\\n      if (y < 100) y += 2000;\\n      if (y >= 2400) y -= 543;\\n      const dateObj = new Date(y, m, d);\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    } else if (digits.length === 2) {\\n      let d = parseInt(digits[0]);\\n      let m = parseInt(digits[1]) - 1;\\n      let y = currentYear;\\n      if (monthIndex !== -1) {\\n        m = monthIndex - 1;\\n      }\\n      const dateObj = new Date(y, m, d);\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    } else if (digits.length === 1 && baseDate) {\\n      let d = parseInt(digits[0]);\\n      const base = new Date(baseDate);\\n      const dateObj = new Date(base.getFullYear(), base.getMonth(), d);\\n      if (dateObj < base) {\\n        dateObj.setMonth(dateObj.getMonth() + 1);\\n      }\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    }\\n  }\\n\\n  const parsed = Date.parse(clean);\\n  if (!isNaN(parsed)) {\\n    return formatDate(new Date(parsed));\\n  }\\n\\n  return null;\\n}\\n\\nfunction formatDate(date) {\\n  const y = date.getFullYear();\\n  const m = String(date.getMonth() + 1).padStart(2, '0');\\n  const d = String(date.getDate()).padStart(2, '0');\\n  return `${y}-${m}-${d}`;\\n}\\n\\nfunction calculateDays(start, end) {\\n  const s = new Date(start);\\n  const e = new Date(end);\\n  const diffTime = e.getTime() - s.getTime();\\n  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1;\\n  return diffDays > 0 ? diffDays : 1;\\n}\\n\\nfunction getLeaveTypeThai(type) {\\n  if (type === 'sick') return '🤒 ลาป่วย';\\n  if (type === 'annual') return '✈️ ลาพักร้อน';\\n  if (type === 'personal') return 'ลากิจ';\\n  return type;\\n}\\n\\nfunction getRemainingDays(type) {\\n  if (type === 'sick') return input.total_sick_leave - input.used_sick_leave;\\n  if (type === 'annual') return input.total_annual_leave - input.used_annual_leave;\\n  if (type === 'personal') return input.total_personal_leave - input.used_personal_leave;\\n  return 0;\\n}\\n\\n// 1. Handlers for unregistered users\\nif (!input.employee_id && !messageText.startsWith('/switch ')) {\\n  responseType = 'direct_reply';\\n  replyMessages = [{\\n    \\"type\\": \\"text\\",\\n    \\"text\\": \\"⚠️ คุณยังไม่ได้ลงทะเบียนในระบบบอท HR\\\\nโปรดพิมพ์คำสั่งสลับบัญชีเพื่อทดสอบ เช่น:\\\\n/switch EMP001 (เพื่อสวมบทบาท สมชาย)\\"\\n  }];\\n}\\n// 2. Handler for /switch <employee_code>\\nelse if (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code)) {\\n  const code = (nlp.intent === 'switch_user' && nlp.employee_code) ? nlp.employee_code : messageText.replace('/switch ', '').trim().toUpperCase();\\n  responseType = 'execute_sql';\\n  \\n  sql = `\\n    WITH unbind AS (\\n      UPDATE employees SET line_user_id = NULL WHERE line_user_id = $1\\n    ), bind AS (\\n      UPDATE employees SET line_user_id = $1 WHERE employee_code = $2 RETURNING name, position\\n    )\\n    INSERT INTO user_sessions (line_user_id, current_state, temp_data)\\n    VALUES ($1, 'idle', '{}'::jsonb)\\n    ON CONFLICT (line_user_id) DO UPDATE SET current_state = 'idle', temp_data = '{}'::jsonb\\n    RETURNING (SELECT name FROM bind) AS employee_name, (SELECT position FROM bind) AS employee_position;\\n  `;\\n  params = [userId, code];\\n  \\n  replyMessages = [{\\n    \\"type\\": \\"text\\",\\n    \\"text\\": `🔄 กำลังสลับบัญชี...`\\n  }];\\n}\\n// 3. User is registered - State Machine for Leave Request (Multi-turn Slot Filling)\\nelse if (input.current_state && input.current_state !== 'idle') {\\n  const state = input.current_state;\\n  let tempData = input.temp_data || {};\\n  \\n  if (cleanText === 'ยกเลิก' || nlp.intent === 'general_chat' && cleanText === 'cancel') {\\n    responseType = 'execute_sql';\\n    sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n    params = [userId];\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": \\"❌ ยกเลิกการทำรายการเรียบร้อยแล้ว กลับสู่สถานะปกติ\\"\\n    }];\\n  }\\n  else if (state === 'awaiting_leave_type') {\\n    let leaveType = '';\\n    let leaveTypeThai = '';\\n    if (cleanText.includes('ป่วย') || cleanText === 'sick') {\\n      leaveType = 'sick';\\n      leaveTypeThai = '🤒 ลาป่วย';\\n    } else if (cleanText.includes('พักร้อน') || cleanText === 'annual') {\\n      leaveType = 'annual';\\n      leaveTypeThai = '✈️ ลาพักร้อน';\\n    } else if (cleanText.includes('กิจ') || cleanText === 'personal') {\\n      leaveType = 'personal';\\n      leaveTypeThai = 'ลากิจ';\\n    }\\n    \\n    if (!leaveType) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ ประเภทการลาไม่ถูกต้อง โปรดเลือกประเภทการลา:\\\\n- พิมพ์ \\\\\\"ลาป่วย\\\\\\"\\\\n- พิมพ์ \\\\\\"ลาพักร้อน\\\\\\"\\\\n- พิมพ์ \\\\\\"ลากิจ\\\\\\"\\\\n(หรือพิมพ์ \\\\\\"ยกเลิก\\\\\\" เพื่อออกจากการทำรายการ)\\"\\n      }];\\n    } else {\\n      const rem = getRemainingDays(leaveType);\\n      if (rem <= 0) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n        params = [userId];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากสิทธิ์วันลาหมดแล้ว\\\\n\\\\n- ประเภทการลา: ${leaveTypeThai}\\\\n- คงเหลือ: 0 วัน`\\n        }];\\n      } else {\\n        tempData.leave_type = leaveType;\\n        tempData.leave_type_thai = leaveTypeThai;\\n      \\n      // Check next missing slot\\n      if (!tempData.start_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_start_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n\\\\nโปรดระบุ \\"วันที่เริ่มลาหยุด\\" (เช่น 2026-06-25 หรือพิมพ์ วันนี้ / พรุ่งนี้)`\\n        }];\\n      } else if (!tempData.end_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_end_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n📅 วันที่เริ่มลา: ${tempData.start_date}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26)`\\n        }];\\n      } else if (!tempData.reason) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\" (เช่น พักผ่อน / มีธุระ)`\\n        }];\\n      } else {\\n        if (!tempData.days && tempData.start_date && tempData.end_date) {\\n          tempData.days = calculateDays(tempData.start_date, tempData.end_date);\\n        }\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (tempData.days > rem) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n          params = [userId];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n          }];\\n        } else {\\n          if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n            }];\\n          } else {\\n            responseType = 'execute_sql';\\n            sql = `\\n              WITH new_leave AS (\\n                INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                RETURNING id\\n              )\\n              UPDATE user_sessions \\n              SET current_state = 'idle', temp_data = '{}'::jsonb \\n              WHERE line_user_id = $1;\\n            `;\\n            params = [\\n              userId,\\n              input.employee_id,\\n              tempData.leave_type,\\n              tempData.start_date,\\n              tempData.end_date,\\n              tempData.days,\\n              tempData.reason\\n            ];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n            }];\\n          }\\n        }\\n      }\\n    }\\n    }\\n  }\\n  else if (state === 'awaiting_start_date') {\\n    const startDate = parseDate(messageText);\\n    if (!startDate) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ วันที่เริ่มไม่ถูกต้อง โปรดระบุฟอร์แมต YYYY-MM-DD (เช่น 2026-06-25) หรือพิมพ์ \\\\\\"วันนี้\\\\\\" / \\\\\\"พรุ่งนี้\\\\\\"\\"\\n      }];\\n    } else {\\n      tempData.start_date = startDate;\\n      \\n      // Check next missing slot\\n      if (!tempData.end_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_end_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📅 วันที่เริ่มลา: ${startDate}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26 หรือพิมพ์จำนวนวัน เช่น 2 วัน)`\\n        }];\\n      } else {\\n        const days = calculateDays(startDate, tempData.end_date);\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (days > rem) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n          params = [userId];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n          }];\\n        } else {\\n          tempData.days = days;\\n          if (!tempData.reason) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📅 ระยะเวลาลา: ${startDate} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\"`\\n            }];\\n          } else {\\n            if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n              responseType = 'execute_sql';\\n              sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n              params = [userId, JSON.stringify(tempData)];\\n              replyMessages = [{\\n                \\"type\\": \\"text\\",\\n                \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n              }];\\n            } else {\\n              responseType = 'execute_sql';\\n              sql = `\\n                WITH new_leave AS (\\n                  INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                  VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                  RETURNING id\\n                )\\n                UPDATE user_sessions \\n                SET current_state = 'idle', temp_data = '{}'::jsonb \\n                WHERE line_user_id = $1;\\n              `;\\n              params = [\\n                userId,\\n                input.employee_id,\\n                tempData.leave_type,\\n                tempData.start_date,\\n                tempData.end_date,\\n                tempData.days,\\n                tempData.reason\\n              ];\\n              replyMessages = [{\\n                \\"type\\": \\"text\\",\\n                \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n              }];\\n            }\\n          }\\n        }\\n      }\\n    }\\n  }\\n  else if (state === 'awaiting_end_date') {\\n    const endDate = parseDate(messageText, tempData.start_date);\\n    if (!endDate || endDate < tempData.start_date) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ วันที่สิ้นสุดไม่ถูกต้อง (ต้องไม่น้อยกว่าวันที่เริ่ม) โปรดระบุแบบ YYYY-MM-DD หรือพิมพ์จำนวนวัน เช่น 1 วัน\\"\\n      }];\\n    } else {\\n      const days = calculateDays(tempData.start_date, endDate);\\n      const rem = getRemainingDays(tempData.leave_type);\\n      if (days > rem) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n        params = [userId];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n        }];\\n      } else {\\n        tempData.end_date = endDate;\\n        tempData.days = days;\\n        \\n        if (!tempData.reason) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n          params = [userId, JSON.stringify(tempData)];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${endDate} (${days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\"`\\n          }];\\n        } else {\\n          if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n            }];\\n          } else {\\n            responseType = 'execute_sql';\\n            sql = `\\n              WITH new_leave AS (\\n                INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                RETURNING id\\n              )\\n              UPDATE user_sessions \\n              SET current_state = 'idle', temp_data = '{}'::jsonb \\n              WHERE line_user_id = $1;\\n            `;\\n            params = [\\n              userId,\\n              input.employee_id,\\n              tempData.leave_type,\\n              tempData.start_date,\\n              tempData.end_date,\\n              tempData.days,\\n              tempData.reason\\n            ];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n            }];\\n          }\\n        }\\n      }\\n    }\\n  }\\n  else if (state === 'awaiting_reason') {\\n    const reason = messageText;\\n    tempData.reason = reason;\\n    \\n    const rem = getRemainingDays(tempData.leave_type);\\n    if (tempData.days > rem) {\\n      responseType = 'execute_sql';\\n      sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n      params = [userId];\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n      }];\\n    } else if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n      // Feature 2: Sick leave > 2 days — ask for medical certificate\\n      tempData.reason = reason;\\n      responseType = 'execute_sql';\\n      sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n      params = [userId, JSON.stringify(tempData)];\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n      }];\\n    } else {\\n      responseType = 'execute_sql';\\n      \\n      // Save to leave_requests and reset user session in a single transaction\\n      sql = `\\n        WITH new_leave AS (\\n          INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n          VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n          RETURNING id\\n        )\\n        UPDATE user_sessions \\n        SET current_state = 'idle', temp_data = '{}'::jsonb \\n        WHERE line_user_id = $1;\\n      `;\\n      params = [\\n        userId,\\n        input.employee_id,\\n        tempData.leave_type,\\n        tempData.start_date,\\n        tempData.end_date,\\n        tempData.days,\\n        reason\\n      ];\\n      \\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n      }];\\n    }\\n  }\\n  else if (state === 'awaiting_medical_cert') {\\n    // Feature 2: Handle medical certificate note submission\\n    const certNote = messageText;\\n    const tdMC = input.temp_data || {};\\n    responseType = 'execute_sql';\\n    sql = `\\n      WITH new_leave AS (\\n        INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n        VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n        RETURNING id\\n      )\\n      UPDATE user_sessions \\n      SET current_state = 'idle', temp_data = '{}'::jsonb \\n      WHERE line_user_id = $1;\\n    `;\\n    const certReason = tdMC.reason + ' [ใบรับรองแพทย์: ' + certNote + ']';\\n    params = [\\n      userId,\\n      input.employee_id,\\n      tdMC.leave_type,\\n      tdMC.start_date,\\n      tdMC.end_date,\\n      tdMC.days,\\n      certReason\\n    ];\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tdMC.leave_type_thai}\\\\n- ระยะเวลา: ${tdMC.start_date} ถึง ${tdMC.end_date} (${tdMC.days} วัน)\\\\n- เหตุผล: ${tdMC.reason}\\\\n- 🏥 ใบรับรองแพทย์: ${certNote}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n    }];\\n  }\\n  else if (state === 'display_team_schedule') {\\n    // Feature 1: Display stored team schedule from temp_data (populated previous turn)\\n    responseType = 'execute_sql';\\n    sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n    params = [userId];\\n    \\n    const schedData = input.temp_data || {};\\n    const schedule = Array.isArray(schedData.schedule) ? schedData.schedule : [];\\n    const displayDate = schedData.check_date || '?';\\n    const dept = schedData.department || input.department;\\n    \\n    function ltThai(t) {\\n      if (t === 'sick') return '🤒 ลาป่วย';\\n      if (t === 'annual') return '✈️ ลาพักร้อน';\\n      if (t === 'personal') return '💼 ลากิจ';\\n      return t;\\n    }\\n    \\n    if (schedule.length === 0) {\\n      replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${displayDate}\\\\n\\\\n✅ ไม่มีสมาชิกทีมลาหยุดในวันดังกล่าว` }];\\n    } else {\\n      const lines = schedule.map(s => `• ${s.name} — ${ltThai(s.leave_type)}`).join('\\\\n');\\n      replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${displayDate}\\\\n\\\\nสมาชิกที่ลาหยุด (${schedule.length} คน):\\\\n${lines}` }];\\n    }\\n  }\\n}\\n// 4. NLP Smart Processing (When user is in 'idle' state)\\nelse {\\n  if (nlp.intent === 'request_leave') {\\n    // LLM extracted a leave request! Let's check what variables are already present.\\n    let tempData = {\\n      leave_type: nlp.leave_type || null,\\n      leave_type_thai: nlp.leave_type ? getLeaveTypeThai(nlp.leave_type) : null,\\n      start_date: nlp.start_date || null,\\n      end_date: nlp.end_date || null,\\n      days: nlp.days || null,\\n      reason: nlp.reason || null\\n    };\\n    \\n    // If end_date is present but start_date is not, default start_date to today\\n    const today = new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0];\\n    if (tempData.end_date && !tempData.start_date) {\\n      tempData.start_date = today;\\n    }\\n    \\n    // If start_date is present but end_date is not:\\n    if (tempData.start_date && !tempData.end_date) {\\n      if (tempData.days) {\\n        // Calculate end_date = start_date + days - 1\\n        const start = new Date(tempData.start_date);\\n        const end = new Date(start.getTime() + ((tempData.days - 1) * 24 * 60 * 60 * 1000));\\n        tempData.end_date = end.toISOString().split('T')[0];\\n      } else {\\n        // Default end_date to start_date (1 day)\\n        tempData.end_date = tempData.start_date;\\n        tempData.days = 1;\\n      }\\n    }\\n    \\n    // Recalculate days if start and end are present\\n    if (tempData.start_date && tempData.end_date && !tempData.days) {\\n      tempData.days = calculateDays(tempData.start_date, tempData.end_date);\\n    }\\n    \\n    // Check if we have EVERYTHING to submit immediately\\n    if (tempData.leave_type && tempData.start_date && tempData.end_date && tempData.reason) {\\n      const rem = getRemainingDays(tempData.leave_type);\\n      if (tempData.days > rem) {\\n        responseType = 'direct_reply';\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน`\\n        }];\\n      } else if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n        // Feature 2: NLP direct path — sick leave > 2 days, ask for medical cert\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n        }];\\n      } else {\\n        // Submit immediately!\\n        responseType = 'execute_sql';\\n        sql = `\\n          INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n          VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending');\\n        `;\\n        params = [\\n          userId,\\n          input.employee_id,\\n          tempData.leave_type,\\n          tempData.start_date,\\n          tempData.end_date,\\n          tempData.days,\\n          tempData.reason\\n        ];\\n        \\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `✅ ส่งคำขอลาหยุดผ่านระบบ AI สำเร็จเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดใบลา:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอได้รับการบันทึกเข้าระบบแล้ว และกำลังรอฝ่ายบุคคล (HR) พิจารณาอนุมัติครับ`\\n        }];\\n      }\\n    } else {\\n      // Check if we have leave_type but days are depleted\\n      if (tempData.leave_type) {\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (rem <= 0) {\\n          responseType = 'direct_reply';\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากสิทธิ์วันลาหมดแล้ว\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- คงเหลือ: 0 วัน`\\n          }];\\n          \\n          // Automatically append \\"- bot\\" to all text responses, and a footer to all Flex bubbles\\n          if (replyMessages && Array.isArray(replyMessages)) {\\n            replyMessages.forEach(msg => {\\n              if (msg.type === 'text') {\\n                msg.text = msg.text + '\\\\n\\\\n- bot';\\n              }\\n            });\\n          }\\n          \\n          return [{\\n            json: {\\n              userId,\\n              replyToken,\\n              responseType,\\n              replyMessages,\\n              sql: '',\\n              params: []\\n            }\\n          }];\\n        }\\n      }\\n\\n      // Something is missing. Determine the next state to transition to\\n      let nextState = 'awaiting_leave_type';\\n      let promptText = 'กรุณาเลือกประเภทการลาที่ต้องการยื่นหยุดงาน:';\\n      \\n      if (!tempData.leave_type) {\\n        nextState = 'awaiting_leave_type';\\n        // Show buttons\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        \\n        replyMessages = [{\\n          \\"type\\": \\"flex\\",\\n          \\"altText\\": \\"เลือกประเภทการลาหยุด\\",\\n          \\"contents\\": {\\n            \\"type\\": \\"bubble\\",\\n            \\"body\\": {\\n              \\"type\\": \\"box\\",\\n              \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n              \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": \\"📝 ยื่นใบลาหยุดงาน\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#4f46e5\\" },\\n                { \\"type\\": \\"text\\", \\"text\\": \\"กรุณาเลือกประเภทการลาเพื่อดำเนินการต่อ:\\", \\"size\\": \\"sm\\", \\"color\\": \\"#94a3b8\\", \\"margin\\": \\"md\\", \\"wrap\\": true },\\n                { \\"type\\": \\"separator\\", \\"margin\\": \\"md\\" },\\n                {\\n                  \\"type\\": \\"box\\",\\n                  \\"layout\\": \\"vertical\\",\\n                  \\"margin\\": \\"md\\",\\n                  \\"spacing\\": \\"sm\\",\\n                  \\"contents\\": [\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"🤒 ลาป่วย (Sick Leave)\\", \\"text\\": \\"ลาป่วย\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#ef4444\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"✈️ ลาพักร้อน (Annual Leave)\\", \\"text\\": \\"ลาพักร้อน\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#4f46e5\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"💼 ลากิจ (Personal Leave)\\", \\"text\\": \\"ลากิจ\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#f59e0b\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"❌ ยกเลิกรายการ\\", \\"text\\": \\"ยกเลิก\\" }, \\"style\\": \\"link\\", \\"color\\": \\"#ef4444\\" }\\n                  ]\\n                }\\n              ]\\n            }\\n          }\\n        }];\\n      } else if (!tempData.start_date) {\\n        nextState = 'awaiting_start_date';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n\\\\nโปรดระบุ \\"วันที่เริ่มลาหยุด\\" (เช่น 2026-06-25 หรือพิมพ์ วันนี้ / พรุ่งนี้)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      } else if (!tempData.end_date) {\\n        nextState = 'awaiting_end_date';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n📅 วันเริ่มลา: ${tempData.start_date}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26 หรือพิมพ์จำนวนวัน เช่น 3 วัน)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      } else if (!tempData.reason) {\\n        nextState = 'awaiting_reason';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\" (เช่น พักผ่อนส่วนตัว / เป็นไข้หวัด)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      }\\n    }\\n  }\\n  else if (nlp.intent === 'check_leave') {\\n    // Trigger case 6: Check Remaining Leave\\n    responseType = 'direct_reply';\\n    const sickRem = input.total_sick_leave - input.used_sick_leave;\\n    const annualRem = input.total_annual_leave - input.used_annual_leave;\\n    const personalRem = input.total_personal_leave - input.used_personal_leave;\\n    \\n    replyMessages = [{\\n      \\"type\\": \\"flex\\",\\n      \\"altText\\": \\"วันลาคงเหลือของคุณ\\",\\n      \\"contents\\": {\\n        \\"type\\": \\"bubble\\",\\n        \\"body\\": {\\n          \\"type\\": \\"box\\",\\n          \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n          \\"contents\\": [\\n            { \\"type\\": \\"text\\", \\"text\\": \\"📊 วันลาคงเหลือของคุณ\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#10b981\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": `คุณ ${input.name}`, \\"size\\": \\"xs\\", \\"color\\": \\"#94a3b8\\", \\"margin\\": \\"xs\\" },\\n            { \\"type\\": \\"separator\\", \\"margin\\": \\"sm\\" },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `🤒 ลาป่วย: คงเหลือ ${sickRem} จาก ${input.total_sick_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#10b981\\", \\"height\\": \\"6px\\", \\"width\\": `${(sickRem/input.total_sick_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `✈️ ลาพักร้อน: คงเหลือ ${annualRem} จาก ${input.total_annual_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#6366f1\\", \\"height\\": \\"6px\\", \\"width\\": `${(annualRem/input.total_annual_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `💼 ลากิจ: คงเหลือ ${personalRem} จาก ${input.total_personal_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#f59e0b\\", \\"height\\": \\"6px\\", \\"width\\": `${(personalRem/input.total_personal_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            }\\n          ]\\n        }\\n      }\\n    }];\\n  }\\n  else if (nlp.intent === 'check_team_schedule') {\\n    const todayStr = new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0];\\n    const checkDate = nlp.check_date || todayStr;\\n    responseType = 'execute_sql';\\n    sql = `\\n      SELECT e.name, lr.leave_type, lr.start_date::text, lr.end_date::text\\n      FROM leave_requests lr\\n      JOIN employees e ON lr.employee_id = e.id\\n      WHERE lr.status = 'approved'\\n        AND e.department = $1\\n        AND $2::date BETWEEN lr.start_date AND lr.end_date\\n      ORDER BY e.name;\\n    `;\\n    params = [input.department, checkDate];\\n    replyMessages = [{ type: 'text', text: `🔍 กำลังค้นหาข้อมูลคิวทีม...` }];\\n  }\\n  else if (nlp.intent === 'check_jd') {\\n    // Trigger case 5: Job Description check\\n    responseType = 'direct_reply';\\n    replyMessages = [{\\n      \\"type\\": \\"flex\\",\\n      \\"altText\\": \\"ขอบข่ายงาน (Job Description)\\",\\n      \\"contents\\": {\\n        \\"type\\": \\"bubble\\",\\n        \\"body\\": {\\n          \\"type\\": \\"box\\",\\n          \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n          \\"contents\\": [\\n            { \\"type\\": \\"text\\", \\"text\\": \\"📋 ขอบข่ายงานของคุณ\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#6366f1\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": input.name, \\"weight\\": \\"bold\\", \\"size\\": \\"md\\", \\"margin\\": \\"md\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": `${input.position} • แผนก ${input.department}`, \\"size\\": \\"xs\\", \\"color\\": \\"#94a3b8\\" },\\n            { \\"type\\": \\"separator\\", \\"margin\\": \\"md\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": input.job_description, \\"size\\": \\"sm\\", \\"wrap\\": true, \\"margin\\": \\"md\\", \\"color\\": \\"#cbd5e1\\" }\\n          ]\\n        }\\n      }\\n    }];\\n  }\\n  else {\\n    // Default Help menu\\n    responseType = 'direct_reply';\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": `สวัสดีครับคุณ ${input.name} ตำแหน่ง ${input.position}\\\\nโปรดระบุงานที่ต้องการจากตัวเลือกด้านล่าง:\\\\n\\\\n- พิมพ์ \\"ลา\\" เพื่อยื่นใบลาหยุดงาน\\\\n- พิมพ์ \\"วันลา\\" เพื่อเช็คสิทธิ์วันลาคงเหลือ\\\\n- พิมพ์ \\"job description\\" เพื่อขอดูขอบข่ายงาน\\\\n- พิมพ์ \\"คิวทีม\\" เพื่อเช็คตารางลาของทีม\\\\n- พิมพ์ \\"/switch <รหัสพนักงาน>\\" เพื่อสลับตัวตน` \\n    }];\\n  }\\n}\\n// Automatically append \\"- bot\\" to all text responses, and a footer to all Flex bubbles\\nif (replyMessages && Array.isArray(replyMessages)) {\\n  replyMessages.forEach(msg => {\\n    if (msg.type === 'text') {\\n      msg.text = msg.text + '\\\\n\\\\n- bot';\\n    } else if (msg.type === 'flex') {\\n      try {\\n        const bubble = msg.contents;\\n        if (bubble && bubble.type === 'bubble') {\\n          if (!bubble.footer) {\\n            bubble.footer = {\\n              \\"type\\": \\"box\\",\\n              \\"layout\\": \\"vertical\\",\\n              \\"contents\\": [\\n                {\\n                  \\"type\\": \\"text\\",\\n                  \\"text\\": \\"- bot\\",\\n                  \\"size\\": \\"xs\\",\\n                  \\"color\\": \\"#94a3b8\\",\\n                  \\"align\\": \\"end\\"\\n                }\\n              ]\\n            };\\n          } else if (bubble.footer.contents) {\\n            bubble.footer.contents.push({\\n              \\"type\\": \\"text\\",\\n              \\"text\\": \\"- bot\\",\\n              \\"size\\": \\"xs\\",\\n              \\"color\\": \\"#94a3b8\\",\\n              \\"align\\": \\"end\\"\\n            });\\n          }\\n        }\\n      } catch (e) {\\n        console.error('Failed to append bot footer to flex:', e);\\n      }\\n    }\\n  });\\n}\\n\\n// Feature 3: Manager notification flag\\nconst isLeaveSubmission = sql.includes('INSERT INTO leave_requests');\\n\\nreturn [{\\n  json: {\\n    userId,\\n    replyToken,\\n    responseType,\\n    replyMessages,\\n    sql,\\n    params,\\n    isLeaveSubmission,\\n    employeeId: input.employee_id || null,\\n    employeeName: input.name || null,\\n    department: input.department || null,\\n    sqlType: (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code) ? 'switch' : ((input.current_state && input.current_state !== 'idle') ? 'other' : (nlp.intent === 'check_team_schedule' ? 'check_team_schedule' : 'other'))),\\n    sqlMeta: {\\n      checkDate: (nlp.intent === 'check_team_schedule' ? (nlp.check_date || new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0]) : null),\\n      department: input.department || null,\\n      employeeCode: (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code) ? (nlp.employee_code || cleanText.replace('/switch ', '').trim().toUpperCase()) : null)\\n    }\\n  }\\n}];\\n"},"id":"code-controller","name":"Core Controller","type":"n8n-nodes-base.code","typeVersion":2,"position":[640,256]},{"parameters":{"conditions":{"string":[{"value1":"={{ $json.responseType }}","value2":"execute_sql"}]}},"id":"switch-response","name":"Switch Response Mode","type":"n8n-nodes-base.if","typeVersion":1,"position":[864,256]},{"parameters":{"operation":"executeQuery","query":"{{$json.sql}}","options":{"queryReplacement":"={{ $('Core Controller').first().json.params }}"}},"id":"pg-execute-actions","name":"PG: Execute SQL Action","type":"n8n-nodes-base.postgres","typeVersion":2,"position":[1088,192],"credentials":{"postgres":{"id":"vwf7u64OuSi5ejWs","name":"Postgres HR - localhost:5432"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"},{"name":"Authorization","value":"=Bearer {{ $env.HR_LINE_CHANNEL_ACCESS_TOKEN }}"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": \\"{{ $('Format SQL Result').first().json.replyToken }}\\",\\n  \\"messages\\": {{ JSON.stringify($('Format SQL Result').first().json.replyMessages) }}\\n}","options":{}},"id":"http-line-reply","name":"LINE: Reply Message","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[1536,256]},{"parameters":{"method":"POST","url":"http://localhost:11434/api/generate","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"qwen2.5:7b\\",\\n  \\"prompt\\": \\"You are an HR Assistant Bot. Parse the user's Thai message and extract structured fields in JSON format.\\\\nCurrent date today is: {{ new Date(new Date().getTime() + 7 * 3600 * 1000).toISOString().split('T')[0] }} (Bangkok Time).\\\\n\\\\nAnalyze the input text and output a JSON object with these EXACT keys:\\\\n{\\\\n  \\\\\\"intent\\\\\\": \\\\\\"request_leave\\\\\\" | \\\\\\"check_leave\\\\\\" | \\\\\\"check_jd\\\\\\" | \\\\\\"switch_user\\\\\\" | \\\\\\"check_team_schedule\\\\\\" | \\\\\\"general_chat\\\\\\",\\\\n  \\\\\\"leave_type\\\\\\": \\\\\\"sick\\\\\\" | \\\\\\"annual\\\\\\" | \\\\\\"personal\\\\\\" | null,\\\\n  \\\\\\"start_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null,\\\\n  \\\\\\"end_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null,\\\\n  \\\\\\"days\\\\\\": number | null,\\\\n  \\\\\\"reason\\\\\\": \\\\\\"Thai string\\\\\\" | null,\\\\n  \\\\\\"employee_code\\\\\\": \\\\\\"EMPxxx\\\\\\" | null,\\\\n  \\\\\\"check_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null\\\\n}\\\\n\\\\nGuidelines:\\\\n1. Intent:\\\\n   - \\\\\\"request_leave\\\\\\": User wants to request leave (e.g., \\\\\\"ขอลา\\\\\\", \\\\\\"ป่วย\\\\\\", \\\\\\"ลากิจ\\\\\\", \\\\\\"พักร้อน\\\\\\").\\\\n   - \\\\\\"check_leave\\\\\\": User wants to check remaining leave days (e.g., \\\\\\"วันลาคงเหลือ\\\\\\", \\\\\\"สิทธิ์วันหยุด\\\\\\").\\\\n   - \\\\\\"check_jd\\\\\\": User wants to check job description (e.g., \\\\\\"งานของฉัน\\\\\\", \\\\\\"job description\\\\\\").\\\\n   - \\\\\\"switch_user\\\\\\": User wants to switch account (e.g., \\\\\\"/switch EMP001\\\\\\", \\\\\\"สลับผู้ใช้เป็น EMP002\\\\\\").\\\\n   - \\\\\\"check_team_schedule\\\\\\": User wants to check who is on leave in their department/team (e.g. \\\\\\"ใครลาบ้าง\\\\\\", \\\\\\"พรุ่งนี้มีใครหยุดไหม\\\\\\", \\\\\\"เช็คตารางลาทีม\\\\\\"). Extract the date to check as YYYY-MM-DD in check_date. Default to today if no date is specified.\\\\n   - \\\\\\"general_chat\\\\\\": Any other text.\\\\n2. Relative and Absolute Dates parsing (relative to today):\\\\n   - \\\\\\"วันนี้\\\\\\" -> today's date\\\\n   - \\\\\\"พรุ่งนี้\\\\\\" -> today's date + 1 day\\\\n   - \\\\\\"เมื่อวาน\\\\\\" / \\\\\\"เมื่อวานนี้\\\\\\" -> today's date - 1 day\\\\n   - \\\\\\"วานซืน\\\\\\" / \\\\\\"เมื่อวานซืน\\\\\\" -> today's date - 2 days\\\\n   - \\\\\\"มะรืน\\\\\\" / \\\\\\"มะรืนนี้\\\\\\" -> today's date + 2 days\\\\n   - \\\\\\"วันจันทร์อาทิตย์หน้า\\\\\\" -> next Monday\\\\n   - \\\\\\"วันอาทิตย์เดือนหน้า\\\\\\" -> first Sunday of next month\\\\n   - \\\\\\"20 สิงหา\\\\\\" / \\\\\\"20 สิงหาคม\\\\\\" / \\\\\\"20 สิงหาคม ปีนี้\\\\\\" -> YYYY-08-20 (using current year)\\\\n   - \\\\\\"20 02\\\\\\" / \\\\\\"20/02\\\\\\" -> YYYY-02-20 (using current year)\\\\n   - \\\\\\"อีก 3 วันถัดไป\\\\\\" starting tomorrow -> start_date: tomorrow, end_date: 2 days after tomorrow, days: 3\\\\n   - If Buddhist Era (พ.ศ. / B.E. e.g. 2569) is mentioned, convert to Gregorian (e.g. 2026) by subtracting 543.\\\\n3. Output ONLY raw JSON. No markdown, no formatting, no extra text.\\\\n\\\\nUser text: \\\\\\"{{ ($('Parse LINE Event').first().json.messageText || '').replace(/\\\\\\\\/g, '\\\\\\\\\\\\\\\\').replace(/\\\\\\"/g, '\\\\\\\\\\\\\\"') }}\\\\\\"\\\\nJSON Output:\\",\\n  \\"stream\\": false,\\n  \\"options\\": {\\n    \\"temperature\\": 0.1\\n  }\\n}","options":{}},"id":"ollama-parse-intent","name":"Ollama: Parse Intent","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[416,256]},{"parameters":{"jsCode":"\\nconst data = $('Core Controller').first().json;\\nif (!data.isLeaveSubmission) return [];\\n\\n// Send LINE push to manager via notify-manager API\\nconst LINE_TOKEN = 'Irn1vjQBmg/DV0/8s7bSFAyqZETfWKV1lGNBAAMgq7xL78hlbs3fMK0QG+Rqh3MW9/G0fQuV/a2nYIyZoeelGM9p8pYfgZpb7I91nTT3g05e3Oqa3cP0xkw6clx5mI55v64cCiYPdU1xDpB7bQgBsQdB04t89/1O/w1cDnyilFU=';\\n\\ntry {\\n  const res = await fetch('http://localhost:3000/api/notify-manager', {\\n    method: 'POST',\\n    headers: { 'Content-Type': 'application/json' },\\n    body: JSON.stringify({\\n      employeeId: data.employeeId,\\n      employeeName: data.employeeName,\\n      department: data.department,\\n      lineToken: LINE_TOKEN\\n    })\\n  });\\n  const result = await res.json();\\n  return [{ json: { notified: true, result } }];\\n} catch(e) {\\n  console.error('Manager notify failed:', e.message);\\n  return [{ json: { notified: false, error: e.message } }];\\n}\\n        "},"id":"code-notify-manager","name":"Notify Manager","type":"n8n-nodes-base.code","typeVersion":2,"position":[1760,256]},{"parameters":{"jsCode":"\\nlet replyToken = '';\\nlet replyMessages = [];\\nlet userId = '';\\nlet isLeaveSubmission = false;\\nlet employeeId = null;\\nlet employeeName = null;\\nlet department = null;\\n\\ntry {\\n  const core = $('Core Controller').first().json;\\n  replyToken = core.replyToken;\\n  replyMessages = core.replyMessages || [];\\n  userId = core.userId;\\n  isLeaveSubmission = core.isLeaveSubmission || false;\\n  employeeId = core.employeeId || null;\\n  employeeName = core.employeeName || null;\\n  department = core.department || null;\\n\\n  if (core.responseType === 'execute_sql') {\\n    let pgRows = [];\\n    try {\\n      pgRows = $input.all().map(item => item.json);\\n    } catch (e) {\\n      pgRows = $('PG: Execute SQL Action').all().map(item => item.json);\\n    }\\n    \\n    if (core.sqlType === 'check_team_schedule') {\\n      const checkDate = core.sqlMeta.checkDate;\\n      const dept = core.sqlMeta.department || 'ไม่ระบุ';\\n      \\n      const schedule = pgRows || [];\\n      \\n      function ltThai(t) {\\n        if (t === 'sick') return '🤒 ลาป่วย';\\n        if (t === 'annual') return '✈️ ลาพักร้อน';\\n        if (t === 'personal') return '💼 ลากิจ';\\n        return t;\\n      }\\n      \\n      if (schedule.length === 0 || (schedule.length === 1 && schedule[0].name === null)) {\\n        replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${checkDate}\\\\n\\\\n✅ ไม่มีสมาชิกทีมลาหยุดในวันดังกล่าว\\\\n\\\\n- bot` }];\\n      } else {\\n        const lines = schedule.map(s => `• ${s.name} — ${ltThai(s.leave_type)}`).join('\\\\n');\\n        replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${checkDate}\\\\n\\\\nสมาชิกที่ลาหยุด (${schedule.length} คน):\\\\n${lines}\\\\n\\\\n- bot` }];\\n      }\\n    }\\n    else if (core.sqlType === 'switch') {\\n      const row = pgRows[0] || {};\\n      const newName = row.employee_name;\\n      const newPos = row.employee_position;\\n      \\n      if (!newName) {\\n        replyMessages = [{\\n          type: 'text',\\n          text: `❌ ไม่พบรหัสพนักงาน ${core.sqlMeta.employeeCode} ในระบบ โปรดตรวจสอบความถูกต้อง\\\\n\\\\n- bot`\\n        }];\\n      } else {\\n        replyMessages = [{\\n          type: 'text',\\n          text: `✅ สลับบัญชีสำเร็จ!\\\\n\\\\nสวัสดีครับคุณ ${newName} ตำแหน่ง ${newPos}\\\\nโปรดระบุงานที่ต้องการจากตัวเลือกด้านล่าง:\\\\n\\\\n- พิมพ์ \\"ลา\\" เพื่อยื่นใบลาหยุดงาน\\\\n- พิมพ์ \\"วันลา\\" เพื่อเช็คสิทธิ์วันลาคงเหลือ\\\\n- พิมพ์ \\"job description\\" เพื่อขอดูขอบข่ายงาน\\\\n- พิมพ์ \\"คิวทีม\\" เพื่อเช็คตารางลาของทีม\\\\n- พิมพ์ \\"/switch <รหัสพนักงาน>\\" เพื่อสลับตัวตน\\\\n\\\\n- bot`\\n        }];\\n      }\\n    }\\n  }\\n} catch (err) {\\n  console.error('Format SQL Result failed:', err);\\n}\\n\\nreturn [{\\n  json: {\\n    userId,\\n    replyToken,\\n    replyMessages,\\n    isLeaveSubmission,\\n    employeeId,\\n    employeeName,\\n    department\\n  }\\n}];\\n        "},"id":"code-format-sql","name":"Format SQL Result","type":"n8n-nodes-base.code","typeVersion":2,"position":[1312,256]}]	{"LINE Webhook":{"main":[[{"node":"Respond 200 OK","type":"main","index":0},{"node":"Parse LINE Event","type":"main","index":0}]]},"Parse LINE Event":{"main":[[{"node":"PG: Get Employee & Session","type":"main","index":0}]]},"PG: Get Employee & Session":{"main":[[{"node":"Ollama: Parse Intent","type":"main","index":0}]]},"Core Controller":{"main":[[{"node":"Switch Response Mode","type":"main","index":0}]]},"Switch Response Mode":{"main":[[{"node":"PG: Execute SQL Action","type":"main","index":0}],[{"node":"Format SQL Result","type":"main","index":0}]]},"PG: Execute SQL Action":{"main":[[{"node":"Format SQL Result","type":"main","index":0}]]},"Ollama: Parse Intent":{"main":[[{"node":"Core Controller","type":"main","index":0}]]},"LINE: Reply Message":{"main":[[{"node":"Notify Manager","type":"main","index":0}]]},"Format SQL Result":{"main":[[{"node":"LINE: Reply Message","type":"main","index":0}]]}}	2026-06-24 11:04:16.734+07	2026-06-25 00:07:21.802+07	{"executionOrder":"v1","binaryMode":"separate"}	\N	{}	5ca0fefa-1da9-4da1-ab3f-09fcc21f28ee	1	wb0BxLBPY80gSVpK	\N	\N	f	33	\N	342bf076-f7ce-4690-884f-889a033db7d9	[]	\N
03 - Docs Hub	t	[{"parameters":{"jsCode":"// Normalize - Smart Router wrapped body in _body\\nconst wrapped = $input.first().json;\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst docNo = (body.doc_no || '').toString().trim() || null;\\nconst fileName = (body.filename || body.file_name || 'unknown').toString();\\nconst fileType = (body.file_type || 'unknown').toString();\\nconst category = body.category || null;\\nconst status = body.status || 'registered';\\nconst lineUserId = body.line_user_id || null;\\nconst lineMessageId = body.line_message_id || null;\\nconst lineGroupId = body.line_group_id || null;\\nconst storageBucket = body.storage_bucket || null;\\nconst storagePath = body.storage_path || null;\\nconst sizeBytes = (body.size_bytes === '' || body.size_bytes === undefined) ? null : Number(body.size_bytes);\\nconst chunkCount = (body.chunk_count === '' || body.chunk_count === undefined) ? 0 : Number(body.chunk_count);\\nconst source = body.source || 'api';\\nconst metadata = body.metadata ? JSON.stringify(body.metadata) : null;\\nreturn [{ json: {\\n  doc_no: docNo, file_name: fileName, file_type: fileType,\\n  category, status, line_user_id: lineUserId, line_message_id: lineMessageId,\\n  line_group_id: lineGroupId, storage_bucket: storageBucket,\\n  storage_path: storagePath, size_bytes: sizeBytes, chunk_count: chunkCount,\\n  source, metadata, needs_generate: !docNo\\n}}];\\n"},"id":"code-prep-reg","name":"Prep Registry Row","type":"n8n-nodes-base.code","position":[2288,896],"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"SELECT 'DOC-' || to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD') || '-' || lpad(next_doc_seq()::text, 3, '0') AS doc_no","options":{}},"id":"pg-gen-seq","name":"PG: Get Next Seq","type":"n8n-nodes-base.postgres","position":[2736,816],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"INSERT INTO contracts (doc_no, file_name, file_type, category, status, line_user_id, line_group_id, line_message_id, storage_bucket, storage_path, size_bytes, chunk_count, source, metadata) VALUES ('{{ ($('Prep Registry Row').item.json.needs_generate ? $('PG: Get Next Seq').item.json.doc_no : $('Prep Registry Row').item.json.doc_no).replace(/'/g, \\"''\\") }}', '{{ $('Prep Registry Row').item.json.file_name.replace(/'/g, \\"''\\") }}', '{{ $('Prep Registry Row').item.json.file_type.replace(/'/g, \\"''\\") }}', {{ $('Prep Registry Row').item.json.category ? \\"'\\" + $('Prep Registry Row').item.json.category.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, '{{ $('Prep Registry Row').item.json.status.replace(/'/g, \\"''\\") }}', {{ $('Prep Registry Row').item.json.line_user_id ? \\"'\\" + $('Prep Registry Row').item.json.line_user_id.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.line_group_id ? \\"'\\" + $('Prep Registry Row').item.json.line_group_id.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.line_message_id ? \\"'\\" + $('Prep Registry Row').item.json.line_message_id.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.storage_bucket ? \\"'\\" + $('Prep Registry Row').item.json.storage_bucket.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.storage_path ? \\"'\\" + $('Prep Registry Row').item.json.storage_path.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.size_bytes === null ? \\"NULL\\" : $('Prep Registry Row').item.json.size_bytes }}, {{ $('Prep Registry Row').item.json.chunk_count }}, '{{ $('Prep Registry Row').item.json.source.replace(/'/g, \\"''\\") }}', {{ $('Prep Registry Row').item.json.metadata ? \\"'\\" + $('Prep Registry Row').item.json.metadata.replace(/'/g, \\"''\\") + \\"'::jsonb\\" : \\"NULL\\" }}) ON CONFLICT (doc_no) DO UPDATE SET file_name = EXCLUDED.file_name, file_type = EXCLUDED.file_type, category = EXCLUDED.category, status = EXCLUDED.status, updated_at = now(), metadata = COALESCE(EXCLUDED.metadata, contracts.metadata) RETURNING id, doc_no, file_name, file_type, status, uploaded_at;","options":{}},"id":"pg-insert-doc","name":"PG: Insert/Update Document","type":"n8n-nodes-base.postgres","position":[2960,896],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"respondWith":"json","responseBody":"={{ ({ ok: true, doc: $('PG: Insert/Update Document').first().json, generated: $('Prep Registry Row').item.json.needs_generate }) }}","options":{}},"id":"resp-reg","name":"Respond Registry","type":"n8n-nodes-base.respondToWebhook","position":[3184,896],"typeVersion":1},{"parameters":{"jsCode":"// Parse stats request - Smart Router wrapped body in _body\\nconst wrapped = $input.first().json;\\nconst body = wrapped._body || wrapped.body || wrapped;\\nconst message = (body.message || body.text || '').toString().toLowerCase();\\nconst keywords = ['สรุปผล', 'สถิติ', 'stats', 'summary', 'รายงาน', 'list', 'ทั้งหมด', 'all'];\\nconst matched = keywords.find(k => message.includes(k.toLowerCase()));\\nconst isStats = !!matched || body.mode === 'stats';\\nconst docNo = body.doc_no || null;\\nconst days = parseInt(String(body.days != null ? body.days : '7'), 10);\\nreturn [{ json: {\\n  is_stats: isStats,\\n  doc_no: docNo,\\n  days: isNaN(days) ? 7 : days\\n}}];\\n"},"id":"code-parse-stats","name":"Parse Stats Request","type":"n8n-nodes-base.code","position":[2288,1280],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"boolean","operation":"true","singleValue":true},"leftValue":"={{ $json.is_stats }}","rightValue":true}]}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"not_stats"}},"id":"sw-stats","name":"Is stats?","type":"n8n-nodes-base.switch","position":[2512,1280],"typeVersion":3.2},{"parameters":{"operation":"executeQuery","query":"WITH params AS (SELECT ({{ $('Parse Stats Request').item.json.days }})::int AS days), base AS (  SELECT * FROM contracts, params   WHERE uploaded_at >= now() - (params.days || ' days')::interval), agg AS (  SELECT     (SELECT COUNT(*) FROM base) AS total,     (SELECT COUNT(*) FROM base WHERE status='ready') AS ready,     (SELECT COUNT(*) FROM base WHERE status='pending') AS pending,     (SELECT COUNT(*) FROM base WHERE status='failed') AS failed,     (SELECT COUNT(*) FROM base WHERE status='registered') AS registered,     (SELECT COUNT(*) FROM base WHERE uploaded_at::date = CURRENT_DATE) AS today_count ) SELECT row_to_json(agg) AS summary, (SELECT json_agg(t) FROM (SELECT file_type, COUNT(*) AS cnt FROM base GROUP BY file_type ORDER BY cnt DESC LIMIT 5) t) AS by_type, (SELECT json_agg(t) FROM (SELECT category, COUNT(*) AS cnt FROM base WHERE category IS NOT NULL GROUP BY category ORDER BY cnt DESC LIMIT 5) t) AS by_category, (SELECT json_agg(t) FROM (SELECT doc_no, file_name, file_type, status, uploaded_at FROM base ORDER BY uploaded_at DESC LIMIT 5) t) AS recent FROM agg;","options":{}},"id":"pg-stats","name":"PG: Aggregate Stats","type":"n8n-nodes-base.postgres","position":[2736,1200],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"const r = ($('PG: Aggregate Stats').first().json || {});\\nconst summary = r.summary || {};\\nconst days = $('Parse Stats Request').item.json.days;\\nconst lines = [];\\nlines.push(`📊 สรุปเอกสาร (ย้อนหลัง ${days} วัน)`);\\nlines.push(`• ทั้งหมด: ${summary.total ?? 0} ฉบับ`);\\nlines.push(`• วันนี้: ${summary.today_count ?? 0} ฉบับ`);\\nlines.push(`• registered: ${summary.registered ?? 0} | ready: ${summary.ready ?? 0} | pending: ${summary.pending ?? 0} | failed: ${summary.failed ?? 0}`);\\nconst byType = r.by_type || [];\\nif (byType.length) {\\n  lines.push('');\\n  lines.push('— แยกตามประเภท —');\\n  for (const t of byType) lines.push(`  • ${t.file_type || 'unknown'}: ${t.cnt}`);\\n}\\nconst byCat = r.by_category || [];\\nif (byCat.length) {\\n  lines.push('');\\n  lines.push('— แยกตามหมวด —');\\n  for (const c of byCat) lines.push(`  • ${c.category || 'ไม่ระบุ'}: ${c.cnt}`);\\n}\\nconst recent = r.recent || [];\\nif (recent.length) {\\n  lines.push('');\\n  lines.push('— 5 ฉบับล่าสุด —');\\n  for (const d of recent) {\\n    const dt = new Date(d.uploaded_at).toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' });\\n    lines.push(`  • ${d.doc_no} | ${d.file_name} [${d.status}] @ ${dt}`);\\n  }\\n}\\nreturn [{ json: { summary_text: lines.join('\\\\n'), raw: r } }];\\n"},"id":"code-format-stats","name":"Format Stats Text","type":"n8n-nodes-base.code","position":[2960,1200],"typeVersion":2},{"parameters":{"respondWith":"json","responseBody":"={{ ({ ok: true, summary_text: $('Format Stats Text').first().json.summary_text, raw: $('Format Stats Text').first().json.raw, days: $('Parse Stats Request').item.json.days }) }}","options":{}},"id":"resp-stats","name":"Respond Stats","type":"n8n-nodes-base.respondToWebhook","position":[3184,1200],"typeVersion":1},{"parameters":{"respondWith":"json","responseBody":"={{ ({ ok: false, is_stats: false, message: 'ไม่พบคำสั่งสถิติ — ส่ง message ที่มีคำว่า สรุปผล/สถิติ/stats/summary/รายงาน/list/all หรือระบุ mode=stats' }) }}","options":{}},"id":"resp-other","name":"Respond Not Stats","type":"n8n-nodes-base.respondToWebhook","position":[3184,1392],"typeVersion":1},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"boolean","operation":"true","singleValue":true},"leftValue":"={{ $json.needs_generate }}","rightValue":true}]},"renameOutput":true,"outputKey":"generate"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"boolean","operation":"false","singleValue":true},"leftValue":"={{ $json.needs_generate }}","rightValue":false}]},"renameOutput":true,"outputKey":"passthrough"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"no_generate"}},"id":"sw-needs-gen","name":"Needs generate?","type":"n8n-nodes-base.switch","position":[2512,880],"typeVersion":3.2},{"parameters":{"jsCode":"// Passthrough: re-emit Prep Registry Row's payload as the resolved doc_no\\nreturn [{ json: { ...$('Prep Registry Row').first().json, needs_generate: false, doc_no: $('Prep Registry Row').first().json.doc_no } }];\\n"},"id":"code-passthrough","name":"Passthrough (use provided doc_no)","type":"n8n-nodes-base.code","position":[2736,1008],"typeVersion":2},{"parameters":{"jsCode":"// Parse - Smart Router wrapped query in _query, body in _body\\nconst wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\n// Read query/q from either URL query OR body\\nconst query = (q.q || body.q || '').toString().trim();\\n// Read mode from either URL query OR body\\nlet mode = (q.mode || body.mode || '').toString();\\nif (!mode) mode = query ? 'vector' : 'list';\\nif (mode !== 'list' && mode !== 'vector') mode = 'list';\\nconst limit = parseInt(q.limit || body.limit || '20', 10);\\nconst safeLimit = isNaN(limit) ? 20 : limit;\\nreturn [{ json: { \\n  query, mode, limit: safeLimit,\\n  list_params: [query, safeLimit],\\n  vector_params: [[], safeLimit]\\n}}];\\n"},"id":"code-parse-search","name":"Parse Search","type":"n8n-nodes-base.code","position":[1392,1664],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json.mode }}","rightValue":"list"}]},"renameOutput":true,"outputKey":"list"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json.mode }}","rightValue":"vector"}]},"renameOutput":true,"outputKey":"vector"}]},"options":{}},"id":"sw-mode","name":"Mode Switch","type":"n8n-nodes-base.switch","position":[1616,1664],"typeVersion":3.2},{"parameters":{"operation":"executeQuery","query":"SELECT doc_no, file_name, file_type, category, status, source, (SELECT COUNT(*) FROM contract_chunks WHERE contract_id = c.id) AS chunk_count, uploaded_at FROM contracts c WHERE (($1::text IS NULL OR $1 = '') OR LOWER(file_name) LIKE '%' || LOWER($1) || '%' OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%') ORDER BY uploaded_at DESC LIMIT $2::int","options":{"queryReplacement":"={{ $json.list_params }}"}},"id":"pg-list","name":"PG: List Docs","type":"n8n-nodes-base.postgres","position":[2288,1584],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || 'http://127.0.0.1:11434') }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"bge-m3\\",\\n  \\"input\\": {{ JSON.stringify($('Parse Search').item.json.query) }}\\n}","options":{"response":{"response":{"neverError":true}},"timeout":30000}},"id":"embed-query","name":"Embed Query","type":"n8n-nodes-base.httpRequest","position":[1840,1776],"typeVersion":4.2},{"parameters":{"operation":"executeQuery","query":"SELECT c.doc_no, c.file_name, ch.chunk_index, ch.content, 1 - (ch.embedding <=> $1::vector) AS similarity FROM contract_chunks ch JOIN contracts c ON c.id = ch.contract_id WHERE ch.embedding IS NOT NULL ORDER BY ch.embedding <=> $1::vector LIMIT $2::int","options":{"queryReplacement":"={{ $json.vector_params }}"}},"id":"pg-vector","name":"PG: Vector Search","type":"n8n-nodes-base.postgres","position":[2288,1776],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"\\n// === Executive Summary Renderer ===\\nconst items = $input.all();\\nconst mode = $('Parse Search').item.json.mode;\\nconst query = $('Parse Search').item.json.query;\\nconst limit = $('Parse Search').item.json.limit || 20;\\n\\nlet docs = [], results = [], stats = {}, daily = [], recent = [], byStatus = [];\\n\\ntry {\\n  if (mode === 'vector') {\\n    const v = $('PG: Vector Search').all() || [];\\n    results = v.map(i => i.json);\\n  } else {\\n    const l = $('PG: List Docs').all() || [];\\n    docs = l.map(i => i.json);\\n  }\\n  // Daily Activity now returns { stats: {total,ready,...}, daily: [{day,cnt}] }\\n  const dailyRows = ($('PG: Daily Activity').all() || []).map(i => i.json);\\n  if (dailyRows.length) {\\n    const first = dailyRows[0];\\n    stats = first.stats || {};\\n    daily = first.daily || [];\\n  } else {\\n    stats = { total: 0, ready: 0, registered: 0, pending: 0, failed: 0, chunks: 0 };\\n    daily = [];\\n  }\\n  recent = ($('PG: Recent Activity').all() || []).map(i => i.json);\\n  byStatus = ($('PG: By Status').all() || []).map(i => i.json);\\n} catch (e) {\\n  stats = { total: 0, ready: 0, registered: 0, pending: 0, failed: 0, chunks: 0 };\\n  daily = [];\\n}\\n\\nconst escapeHtml = (s) => String(s == null ? '' : s).replace(/[&<>\\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\\"':'&quot;',\\"'\\":'&#39;'}[c]));\\nconst fmtNum = (n) => n == null ? '?' : Number(n).toLocaleString('th-TH');\\nconst fmtPct = (n) => n == null ? '?' : (Number(n) * 100).toFixed(0) + '%';\\n\\n// ===== Executive Summary KPIs =====\\nconst kpiCards = `\\n<div class=\\"kpi-row\\">\\n  <div class=\\"kpi-card kpi-primary\\">\\n    <div class=\\"kpi-label\\">📄 เอกสารทั้งหมด</div>\\n    <div class=\\"kpi-value\\">${fmtNum(stats.total)}</div>\\n    <div class=\\"kpi-sub\\">${fmtNum(stats.chunks)} chunks</div>\\n  </div>\\n  <div class=\\"kpi-card kpi-success\\">\\n    <div class=\\"kpi-label\\">✅ พร้อมใช้งาน</div>\\n    <div class=\\"kpi-value\\">${fmtNum(stats.ready)}</div>\\n    <div class=\\"kpi-sub\\">${fmtPct(stats.total ? stats.ready / stats.total : 0)} ของทั้งหมด</div>\\n  </div>\\n  <div class=\\"kpi-card kpi-warn\\">\\n    <div class=\\"kpi-label\\">⏳ กำลังประมวลผล</div>\\n    <div class=\\"kpi-value\\">${fmtNum((Number(stats.registered)||0) + (Number(stats.pending)||0))}</div>\\n    <div class=\\"kpi-sub\\">registered: ${fmtNum(stats.registered)} · pending: ${fmtNum(stats.pending)}</div>\\n  </div>\\n  <div class=\\"kpi-card kpi-danger\\">\\n    <div class=\\"kpi-label\\">❌ ล้มเหลว</div>\\n    <div class=\\"kpi-value\\">${fmtNum(stats.failed)}</div>\\n    <div class=\\"kpi-sub\\">${fmtPct(stats.total ? stats.failed / stats.total : 0)} ของทั้งหมด</div>\\n  </div>\\n</div>`;\\n\\n// ===== Daily Activity Chart =====\\nlet chartHtml = '<div class=\\"empty-mini\\">ยังไม่มีข้อมูล</div>';\\nif (daily && daily.length) {\\n  const maxCnt = Math.max(...daily.map(d => Number(d.cnt)||0), 1);\\n  const bars = daily.map(d => {\\n    const h = Math.max(2, Math.round((Number(d.cnt)||0) / maxCnt * 80));\\n    const dd = String(d.day || '').slice(5);\\n    return `<div class=\\"chart-bar-col\\">\\n      <div class=\\"chart-bar\\" style=\\"height:${h}px\\" title=\\"${escapeHtml(d.day)}: ${d.cnt}\\"></div>\\n      <div class=\\"chart-label\\">${dd}</div>\\n    </div>`;\\n  }).join('');\\n  chartHtml = `<div class=\\"chart\\">${bars}</div>\\n<div class=\\"chart-legend\\">📊 กิจกรรม 14 วันล่าสุด (เอกสารต่อวัน)</div>`;\\n}\\n\\n// ===== Recent Activity Timeline =====\\nlet recentHtml = '<div class=\\"empty-mini\\">ยังไม่มีข้อมูล</div>';\\nif (recent && recent.length) {\\n  recentHtml = recent.slice(0, 8).map(d => {\\n    const dt = new Date(d.uploaded_at);\\n    const dtStr = dt.toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' });\\n    const statusClass = `status-${d.status || 'unknown'}`;\\n    return `<div class=\\"timeline-item\\">\\n      <div class=\\"timeline-dot ${statusClass}\\"></div>\\n      <div class=\\"timeline-content\\">\\n        <div class=\\"timeline-title\\">${escapeHtml(d.file_name)}</div>\\n        <div class=\\"timeline-meta\\">\\n          <span class=\\"doc-no-mini\\">${escapeHtml(d.doc_no)}</span>\\n          <span>${dtStr}</span>\\n          <span class=\\"doc-status ${statusClass}\\">${escapeHtml(d.status)}</span>\\n        </div>\\n      </div>\\n    </div>`;\\n  }).join('');\\n}\\n\\n// ===== Status Breakdown =====\\nlet byStatusHtml = '<div class=\\"empty-mini\\">ยังไม่มีข้อมูล</div>';\\nif (byStatus && byStatus.length) {\\n  byStatusHtml = `<table class=\\"status-table\\">` +\\n    byStatus.map(r => `<tr><td><span class=\\"status-dot status-${escapeHtml(r.status || 'unknown')}\\"></span>${escapeHtml(r.status)}</td><td class=\\"num\\">${fmtNum(r.cnt)}</td></tr>`).join('') +\\n    `</table>`;\\n}\\n\\n// ===== Search Results =====\\nfunction renderListPage(docs) {\\n  if (!docs.length) return '<div class=\\"empty\\">ไม่พบเอกสาร</div>';\\n  return docs.map(d => {\\n    const uploaded = (d.uploaded_at || '').slice(0, 19).replace('T', ' ');\\n    return `\\n<div class=\\"doc-item\\">\\n  <span class=\\"doc-no\\">${escapeHtml(d.doc_no)}</span>\\n  <span class=\\"doc-name\\">${escapeHtml(d.file_name)}</span>\\n  <div class=\\"doc-meta\\">\\n    <span>${escapeHtml(d.file_type)}</span>\\n    <span>${escapeHtml(d.category || '—')}</span>\\n    <span>${escapeHtml(uploaded)}</span>\\n    <span class=\\"doc-status status-${escapeHtml(d.status || 'unknown')}\\">${escapeHtml(d.status)}</span>\\n  </div>\\n</div>`;\\n  }).join('');\\n}\\n\\nfunction renderVectorResults(results, query) {\\n  if (!results.length) return '<div class=\\"empty\\">ไม่พบผลลัพธ์</div>';\\n  return results.map(r => {\\n    const sim = ((r.similarity || 0) * 100).toFixed(1);\\n    let content = (r.content || '').slice(0, 500);\\n    if (query) {\\n      query.split(/\\\\s+/).filter(w => w.length > 1).forEach(w => {\\n        content = content.replace(new RegExp(w, 'gi'), m => '<span class=\\"search-q\\">' + m + '</span>');\\n      });\\n    }\\n    return `\\n<div class=\\"result-card\\">\\n  <div class=\\"result-meta\\">\\n    <span class=\\"result-similarity\\">📊 ${sim}%</span>\\n    <span>${escapeHtml(r.doc_no)}</span>\\n    <span>${escapeHtml(r.file_name)}</span>\\n    <span>chunk #${escapeHtml(r.chunk_index)}</span>\\n  </div>\\n  <div class=\\"result-content\\">${content}${(r.content || '').length > 500 ? '...' : ''}</div>\\n</div>`;\\n  }).join('');\\n}\\n\\n// ===== Tabs =====\\nconst listTabActive = mode === 'list' ? 'active' : '';\\nconst vectorTabActive = mode === 'vector' ? 'active' : '';\\nconst listLink = '/webhook/docs-search?mode=list';\\nconst vectorLink = '/webhook/docs-search?mode=vector&q=' + encodeURIComponent(query || '');\\nconst isOverview = !query && mode === 'list';\\n\\nconst html = `<!DOCTYPE html>\\n<html lang=\\"th\\">\\n<head>\\n<meta charset=\\"UTF-8\\">\\n<meta name=\\"viewport\\" content=\\"width=device-width, initial-scale=1.0\\">\\n<title>${isOverview ? 'Executive Summary' : 'Document Search'} — Law Firm</title>\\n<style>\\n* { box-sizing: border-box; margin: 0; padding: 0; }\\nbody { font-family: -apple-system, BlinkMacSystemFont, \\"Segoe UI\\", \\"Noto Sans Thai\\", sans-serif; background: #f5f7fa; color: #2c3e50; padding: 24px; }\\n.container { max-width: 1280px; margin: 0 auto; }\\nheader { background: linear-gradient(135deg, #1a3a5c 0%, #2c5e8a 100%); color: white; padding: 24px 32px; border-radius: 12px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(26,58,92,0.15); }\\nheader h1 { font-size: 26px; margin-bottom: 6px; }\\n.subtitle { opacity: 0.85; font-size: 14px; }\\n.tabs { display: flex; gap: 4px; margin-bottom: 16px; background: #e1e8ed; padding: 4px; border-radius: 8px; }\\n.tab { padding: 10px 24px; cursor: pointer; background: transparent; border: none; border-radius: 6px; font-size: 14px; font-weight: 600; color: #5a6c7d; text-decoration: none; transition: all 0.15s; display: inline-block; }\\n.tab:hover { background: rgba(255,255,255,0.5); }\\n.tab.active { background: white; color: #1a3a5c; box-shadow: 0 2px 4px rgba(0,0,0,0.06); }\\n.search-box { background: white; padding: 16px 20px; border-radius: 8px; margin-bottom: 16px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); }\\n.search-form { display: flex; gap: 8px; }\\ninput[type=\\"text\\"] { flex: 1; padding: 10px 14px; border: 1px solid #cbd5e0; border-radius: 6px; font-size: 14px; }\\nbutton { padding: 10px 20px; background: #1a3a5c; color: white; border: none; border-radius: 6px; font-weight: 600; cursor: pointer; font-size: 14px; }\\nbutton:hover { background: #122a44; }\\n.kpi-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 20px; }\\n.kpi-card { background: white; padding: 20px 24px; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); border-left: 4px solid #cbd5e0; }\\n.kpi-primary { border-left-color: #1a3a5c; }\\n.kpi-success { border-left-color: #0a6b3e; }\\n.kpi-warn { border-left-color: #c47a00; }\\n.kpi-danger { border-left-color: #a01818; }\\n.kpi-label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; color: #6b7785; font-weight: 600; margin-bottom: 6px; }\\n.kpi-value { font-size: 32px; font-weight: 700; color: #1a3a5c; line-height: 1; margin-bottom: 4px; }\\n.kpi-sub { font-size: 12px; color: #6b7785; }\\n.overview-row { display: grid; grid-template-columns: 2fr 1fr; gap: 20px; margin-bottom: 20px; }\\n.panel { background: white; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); padding: 20px 24px; }\\n.panel-title { font-size: 14px; font-weight: 700; color: #1a3a5c; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid #ecf0f3; }\\n.chart { display: flex; align-items: flex-end; gap: 6px; height: 100px; padding: 8px 0; }\\n.chart-bar-col { display: flex; flex-direction: column; align-items: center; flex: 1; min-width: 0; }\\n.chart-bar { background: linear-gradient(to top, #2c5e8a, #4a8ec8); width: 100%; border-radius: 3px 3px 0 0; min-height: 2px; transition: all 0.2s; }\\n.chart-bar:hover { background: linear-gradient(to top, #1a3a5c, #2c5e8a); }\\n.chart-label { font-size: 10px; color: #6b7785; margin-top: 4px; }\\n.chart-legend { font-size: 12px; color: #6b7785; margin-top: 12px; }\\n.timeline-item { display: flex; gap: 12px; padding: 10px 0; border-bottom: 1px solid #ecf0f3; }\\n.timeline-item:last-child { border-bottom: none; }\\n.timeline-dot { width: 10px; height: 10px; border-radius: 50%; margin-top: 6px; flex-shrink: 0; }\\n.timeline-dot.status-ready { background: #0a6b3e; }\\n.timeline-dot.status-registered { background: #c47a00; }\\n.timeline-dot.status-pending { background: #c47a00; }\\n.timeline-dot.status-failed { background: #a01818; }\\n.timeline-content { flex: 1; min-width: 0; }\\n.timeline-title { font-weight: 500; font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\\n.timeline-meta { display: flex; gap: 10px; font-size: 11px; color: #6b7785; margin-top: 2px; flex-wrap: wrap; }\\n.doc-no-mini { background: #e8f0fe; color: #1a3a5c; padding: 1px 6px; border-radius: 3px; font-family: monospace; font-size: 10px; }\\n.status-table { width: 100%; border-collapse: collapse; }\\n.status-table td { padding: 8px 0; border-bottom: 1px solid #ecf0f3; font-size: 13px; }\\n.status-table td.num { text-align: right; font-weight: 600; color: #1a3a5c; }\\n.status-table tr:last-child td { border-bottom: none; }\\n.status-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 8px; }\\n.status-dot.status-ready { background: #0a6b3e; }\\n.status-dot.status-registered { background: #c47a00; }\\n.status-dot.status-pending { background: #c47a00; }\\n.status-dot.status-failed { background: #a01818; }\\n.empty-mini { color: #6b7785; font-size: 13px; padding: 20px; text-align: center; }\\n.docs-list { background: white; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); overflow: hidden; }\\n.doc-item { padding: 14px 20px; border-bottom: 1px solid #ecf0f3; display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }\\n.doc-item:last-child { border-bottom: none; }\\n.doc-no { background: #e8f0fe; color: #1a3a5c; padding: 4px 10px; border-radius: 4px; font-family: monospace; font-size: 12px; font-weight: 600; }\\n.doc-name { flex: 1; font-weight: 500; min-width: 200px; }\\n.doc-meta { color: #6b7785; font-size: 12px; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }\\n.doc-status { padding: 3px 10px; border-radius: 12px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.3px; }\\n.status-ready { background: #d4f5e1; color: #0a6b3e; }\\n.status-registered { background: #fff4d4; color: #8a6708; }\\n.status-pending { background: #fde7d4; color: #9c4a0a; }\\n.status-failed { background: #fdd4d4; color: #a01818; }\\n.empty { padding: 40px; text-align: center; color: #6b7785; }\\n.result-card { background: white; padding: 16px 20px; border-radius: 8px; margin-bottom: 12px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); }\\n.result-meta { display: flex; gap: 12px; font-size: 12px; color: #6b7785; margin-bottom: 8px; flex-wrap: wrap; }\\n.result-similarity { background: #e8f0fe; color: #1a3a5c; padding: 2px 8px; border-radius: 4px; font-weight: 600; }\\n.result-content { font-size: 14px; line-height: 1.6; color: #2c3e50; white-space: pre-wrap; word-wrap: break-word; }\\n.search-q { background: #fff8c5; padding: 2px 6px; border-radius: 3px; font-weight: 600; }\\n.section-title { font-size: 18px; font-weight: 700; color: #1a3a5c; margin: 24px 0 12px 0; }\\n.footer { text-align: center; padding: 20px; color: #6b7785; font-size: 12px; margin-top: 24px; border-top: 1px solid #ecf0f3; }\\n@media (max-width: 768px) { .overview-row { grid-template-columns: 1fr; } }\\n</style>\\n</head>\\n<body>\\n<div class=\\"container\\">\\n<header>\\n  <h1>${isOverview ? '📊 Executive Summary' : '📋 Document Registry'}</h1>\\n  <div class=\\"subtitle\\">Law Firm — Document Pipeline & Search</div>\\n</header>\\n\\n<div class=\\"tabs\\">\\n  <a class=\\"tab ${listTabActive}\\" href=\\"${listLink}\\">📋 ${isOverview ? 'Overview' : 'List'}</a>\\n  <a class=\\"tab ${vectorTabActive}\\" href=\\"${vectorLink}\\">🔍 Vector Search</a>\\n</div>\\n\\n<div class=\\"search-box\\">\\n  <form class=\\"search-form\\" method=\\"get\\" action=\\"/webhook/docs-search\\">\\n    <input type=\\"hidden\\" name=\\"mode\\" value=\\"${mode}\\">\\n    <input type=\\"text\\" name=\\"q\\" value=\\"${escapeHtml(query)}\\" placeholder=\\"${mode === 'vector' ? 'ค้นหาด้วย semantic search... (e.g. สัญญาเช่า ผิดนัด)' : 'กรองรายการ (filename, category)...'}\\" autofocus>\\n    <button type=\\"submit\\">${mode === 'vector' ? '🔍 Search' : '🔎 Filter'}</button>\\n  </form>\\n</div>\\n\\n${isOverview ? kpiCards : ''}\\n\\n${isOverview ? `\\n<div class=\\"overview-row\\">\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">📈 กิจกรรมการอัปโหลด</div>\\n    ${chartHtml}\\n  </div>\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">📌 สถานะเอกสาร</div>\\n    ${byStatusHtml}\\n  </div>\\n</div>\\n\\n<div class=\\"overview-row\\">\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">🕐 เอกสารล่าสุด</div>\\n    ${recentHtml}\\n  </div>\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">🔗 Quick Links</div>\\n    <div style=\\"display: flex; flex-direction: column; gap: 10px;\\">\\n      <a href=\\"/webhook/docs-search?mode=list\\" style=\\"padding: 12px 16px; background: #f5f7fa; border-radius: 6px; text-decoration: none; color: #1a3a5c; font-weight: 500;\\">📋 ดูเอกสารทั้งหมด</a>\\n      <a href=\\"/webhook/docs-search?mode=vector\\" style=\\"padding: 12px 16px; background: #f5f7fa; border-radius: 6px; text-decoration: none; color: #1a3a5c; font-weight: 500;\\">🔍 Vector Search</a>\\n      <a href=\\"/webhook/docs-stats\\" style=\\"padding: 12px 16px; background: #f5f7fa; border-radius: 6px; text-decoration: none; color: #1a3a5c; font-weight: 500;\\">📊 Stats JSON API</a>\\n      <code style=\\"padding: 12px 16px; background: #fff8c5; border-radius: 6px; font-size: 11px; color: #5a4a08; word-break: break-all;\\">POST /webhook/docs-registry<br>{filename, file_type, ...}</code>\\n    </div>\\n  </div>\\n</div>\\n` : ''}\\n\\n<div class=\\"section-title\\">${mode === 'vector' ? '🔍 ผลการค้นหา (Semantic)' : isOverview ? '📄 เอกสารทั้งหมด' : '🔎 ผลการกรอง'}</div>\\n${mode === 'vector' ? renderVectorResults(results, query) : '<div class=\\"docs-list\\">' + renderListPage(docs) + '</div>'}\\n\\n<div class=\\"footer\\">\\n  Generated at ${new Date().toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' })} • n8n workflow: 02 - Document Registry & Stats • Global URLs: /webhook/docs-search · /webhook/docs-stats · /webhook/docs-registry\\n</div>\\n</div>\\n</body>\\n</html>`;\\n\\nreturn [{ json: { html: html, contentType: 'text/html' } }];\\n"},"id":"code-render-html","name":"Render HTML","type":"n8n-nodes-base.code","position":[3184,1664],"typeVersion":2},{"parameters":{"respondWith":"text","responseBody":"={{ $('Render HTML').first().json.html }}","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Type","value":"text/html; charset=utf-8"}]}}},"id":"resp-html","name":"Respond HTML","type":"n8n-nodes-base.respondToWebhook","position":[48,2912],"typeVersion":1},{"parameters":{"jsCode":"// Build vector_params for n8n pg node - array of raw values\\nconst embeddings = $json.embeddings || ($json.embedding ? [$json.embedding] : []);\\nconst vec = embeddings[0] || [];\\nconst limit = $('Parse Search').item.json.limit || 10;\\n// Format: '[0.1,0.2,...]' as string for pg vector literal\\nconst vectorStr = '[' + vec.map(Number).join(',') + ']';\\nreturn [{ json: { ...$json, vector_params: [vectorStr, limit] } }];\\n"},"id":"code-build-vec-params","name":"Build Vector Params","type":"n8n-nodes-base.code","position":[2064,1776],"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT row_to_json(s) FROM (SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='registered') AS registered, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed, (SELECT COUNT(*) FROM contract_chunks) AS chunks) s) AS stats, (SELECT COALESCE(json_agg(daily), '[]'::json) FROM (  SELECT to_char(\\"uploaded_at\\" AT TIME ZONE 'Asia/Bangkok', 'YYYY-MM-DD') AS day, COUNT(*)::int AS cnt   FROM contracts   WHERE \\"uploaded_at\\" >= (now() - interval '14 days')   GROUP BY 1 ORDER BY 1) daily) AS daily","options":{}},"id":"pg-daily","name":"PG: Daily Activity","type":"n8n-nodes-base.postgres","position":[2512,1664],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT doc_no, file_name, file_type, status, uploaded_at FROM contracts ORDER BY uploaded_at DESC LIMIT 8","options":{}},"id":"pg-recent","name":"PG: Recent Activity","type":"n8n-nodes-base.postgres","position":[2736,1664],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT status, COUNT(*)::int AS cnt FROM contracts WHERE status IS NOT NULL GROUP BY status ORDER BY status","options":{}},"id":"pg-by-status","name":"PG: By Status","type":"n8n-nodes-base.postgres","position":[2960,1664],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Chunk the extracted text. Empty text = empty chunks → caller rolls back the file.\\nconst MAX = 1500;\\nconst OVERLAP = 200;\\nconst text = ($('LINE Extract via Vision LLM').first().json.text || '').toString();\\n\\nif (!text.trim()) {\\n  return [{ json: { empty: true, chunk_count: 0, chunks: [] } }];\\n}\\n\\nconst chunks = [];\\nlet i = 0, idx = 0;\\nwhile (i < text.length) {\\n  chunks.push({ chunk_index: idx, content: text.slice(i, i + MAX) });\\n  if (i + MAX >= text.length) break;\\n  i += MAX - OVERLAP;\\n  idx++;\\n}\\nreturn [{ json: { empty: false, chunk_count: chunks.length, chunks } }];\\n"},"id":"line-chunk","name":"LINE Chunk text","type":"n8n-nodes-base.code","position":[1616,464],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ $env.OLLAMA_URL || 'http://127.0.0.1:11434' }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.chunks.map(c => c.content)) }}\\n}","options":{"timeout":180000}},"id":"line-embed","name":"LINE Embed all chunks (Ollama bge-m3)","type":"n8n-nodes-base.httpRequest","position":[2288,384],"typeVersion":4.2},{"parameters":{"jsCode":"// Combine: file metadata + chunk embeddings into rows ready to insert.\\n// Use explicit $() to fetch from each upstream — $input.first() picks whichever\\n// runs first which is brittle when Decode and Embed both feed in.\\nconst embedResp = $('LINE Embed all chunks (Ollama bge-m3)').first().json;\\nconst vecs = embedResp.embeddings || embedResp;\\nconst chunkInfo = $('LINE Chunk text').first().json;\\nconst sm = $('Smart Router').first().json;\\nconst evt = sm._event || {};\\nconst downloadMeta = sm._downloadResult || {};\\n\\n// Pull file_data_b64 from Decode (preferred) — scan $input.all() as fallback\\nlet fileDataB64 = null, fileMime = null, fileName = null, fileSize = null;\\nconst decodeOut = $('LINE Decode & Prepare Binary').first();\\nif (decodeOut && decodeOut.json) {\\n  fileDataB64 = decodeOut.json.file_data_b64 || null;\\n  fileMime = decodeOut.json.file_mime || null;\\n  fileName = decodeOut.json.file_name || null;\\n  fileSize = decodeOut.json.file_size || null;\\n}\\nif (!fileDataB64) {\\n  for (const it of $input.all()) {\\n    if (it.json && it.json.file_data_b64) {\\n      fileDataB64 = it.json.file_data_b64;\\n      fileMime = it.json.file_mime || null;\\n      fileName = it.json.file_name || null;\\n      fileSize = it.json.file_size || null;\\n      break;\\n    }\\n  }\\n}\\n\\nconst chunks = chunkInfo.chunks || [];\\nconst rows = chunks.map((c, i) => ({\\n  chunk_index: c.chunk_index,\\n  content: c.content,\\n  embedding: vecs[i] ? ('[' + vecs[i].map(Number).join(',') + ']') : null\\n}));\\n\\nreturn [{\\n  json: {\\n    file_name: fileName || downloadMeta.fileName || evt.message?.fileName || 'unknown',\\n    file_type: ((fileName || downloadMeta.fileName || evt.message?.fileName || '').split('.').pop() || '').toLowerCase(),\\n    size_bytes: fileSize || downloadMeta.fileSize || evt.message?.fileSize || null,\\n    line_user_id: evt.source?.userId || null,\\n    line_group_id: evt.source?.groupId || null,\\n    line_message_id: evt.message?.id || null,\\n    chunk_count: rows.length,\\n    file_data_b64: fileDataB64,\\n    file_mime: fileMime,\\n    rows\\n  }\\n}];\\n"},"id":"line-combine","name":"LINE Combine metadata + vectors","type":"n8n-nodes-base.code","position":[2512,384],"typeVersion":2},{"parameters":{"jsCode":"// Build one Postgres statement that marks the document ready and stores all vectors\\n// AND all per-page images (JPEG bytes from ocr-service /vision page_images[]).\\nconst start = $('LINE Register Start').first().json || {};\\nconst meta = $('LINE Combine metadata + vectors').first().json || {};\\nconst visionResp = $('LINE Extract via Vision LLM').first().json || {};\\nconst contractId = start.id;\\nif (!contractId) {\\n  throw new Error('Missing contract id from LINE Register Start');\\n}\\n\\nconst rows = Array.isArray(meta.rows) ? meta.rows : [];\\nconst chunkCount = rows.length;\\nconst pageImages = Array.isArray(visionResp.page_images) ? visionResp.page_images : [];\\nconst pageCount = pageImages.length;\\nconst quoteIdent = String(contractId).replace(/'/g, \\"''\\");\\nconst dollarTag = (i) => `$chunk_${i}$`;\\nconst cleanForTag = (value, tag) => String(value ?? '').replaceAll(tag, '');\\n\\nlet insertedCte;\\nif (chunkCount > 0) {\\n  const values = rows.map((row, i) => {\\n    const tag = dollarTag(i);\\n    const content = cleanForTag(row.content, tag);\\n    const vector = row.embedding ? `'${row.embedding}'::vector` : 'NULL';\\n    return `((SELECT id FROM updated), ${Number(row.chunk_index) || 0}, ${tag}${content}${tag}, ${content.length}, ${vector})`;\\n  }).join(',\\\\n');\\n  insertedCte = `inserted AS (\\\\n  INSERT INTO contract_chunks (contract_id, chunk_index, content, token_count, embedding)\\\\n  VALUES ${values}\\\\n  RETURNING 1\\\\n)`;\\n} else {\\n  insertedCte = `inserted AS (SELECT 1 WHERE false)`;\\n}\\n\\n// Per-page images: base64 in single-quoted literal -> decode(..., 'base64') -> BYTEA.\\n// b64 alphabet excludes single quotes, but escape anyway for safety. ON CONFLICT\\n// makes re-runs idempotent (same contract_id+page_index is replaced, not duplicated).\\nlet pagesCte;\\nif (pageCount > 0) {\\n  const values = pageImages.map((p) => {\\n    const b64 = String(p.image_b64 || '').replace(/'/g, \\"''\\");\\n    const mime = String(p.mime || 'image/jpeg').replace(/'/g, \\"''\\");\\n    const idx = Number(p.page_index) || 0;\\n    const bytes = Number(p.bytes) || 0;\\n    return `((SELECT id FROM updated), ${idx}, decode('${b64}', 'base64'), '${mime}', ${bytes})`;\\n  }).join(',\\\\n');\\n  pagesCte = `inserted_pages AS (\\\\n  INSERT INTO contract_pages (contract_id, page_index, image_data, image_mime, bytes)\\\\n  VALUES ${values}\\\\n  ON CONFLICT (contract_id, page_index) DO UPDATE SET\\\\n    image_data = EXCLUDED.image_data,\\\\n    image_mime = EXCLUDED.image_mime,\\\\n    bytes = EXCLUDED.bytes\\\\n  RETURNING 1\\\\n)`;\\n} else {\\n  pagesCte = `inserted_pages AS (SELECT 1 WHERE false)`;\\n}\\n\\nconst sql = `WITH updated AS (\\\\n  UPDATE contracts\\\\n  SET chunk_count = ${chunkCount}::int, status = 'ready', error_message = NULL, updated_at = now()\\\\n  WHERE id = '${quoteIdent}'::uuid\\\\n  RETURNING id, doc_no, file_name\\\\n), deleted AS (\\\\n  DELETE FROM contract_chunks WHERE contract_id = (SELECT id FROM updated)\\\\n), ${insertedCte},\\\\n${pagesCte}\\\\nSELECT id, doc_no, file_name, ${chunkCount}::int AS chunk_count,\\\\n       (SELECT count(*) FROM inserted) AS inserted_chunks,\\\\n       (SELECT count(*) FROM inserted_pages) AS inserted_pages\\\\nFROM updated`;\\n\\nreturn [{ json: { sql, contract_id: contractId, chunk_count: chunkCount, page_count: pageCount } }];\\n"},"id":"line-build-sql","name":"LINE Build Store SQL","type":"n8n-nodes-base.code","position":[2736,384],"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"{{ $json.sql }}","options":{}},"id":"line-insert-chunks","name":"PG: Store Embeddings","type":"n8n-nodes-base.postgres","position":[2960,384],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/push","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"to\\": {{ JSON.stringify($('Smart Router').first().json._event.source.groupId || $('Smart Router').first().json._event.source.userId) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": \\"บันทึกเอกสารเรียบร้อย\\\\nเลขที่: {{ $('PG: Store Embeddings').first().json.doc_no || $('LINE Register Start').first().json.doc_no }}\\\\nไฟล์: {{ $('LINE Combine metadata + vectors').item.json.file_name }}\\\\nChunks: {{ $('LINE Combine metadata + vectors').item.json.chunk_count }}\\" }]\\n}","options":{}},"id":"line-reply-ok","name":"LINE Reply Success","type":"n8n-nodes-base.httpRequest","position":[3184,336],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/push","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"to\\": {{ JSON.stringify($('Smart Router').first().json._event.source.groupId || $('Smart Router').first().json._event.source.userId) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": \\"บันทึกเอกสารไม่สำเร็จ: {{ $json.error || $json.message || 'unknown' }}\\" }]\\n}","options":{}},"id":"line-reply-err","name":"LINE Reply Error","type":"n8n-nodes-base.httpRequest","position":[3184,576],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"operation":"executeQuery","query":"INSERT INTO contracts (doc_no, line_user_id, line_group_id, line_message_id, file_name, file_type, size_bytes, status, source, file_mime, file_data) VALUES (next_doc_seq(), NULLIF($1::text, '')::text, NULLIF($2::text, '')::text, NULLIF($3::text, '')::text, $4::text, $5::text, $6::bigint, 'processing', 'line', NULLIF($7::text, '')::text, decode($8::text, 'base64')) RETURNING id, doc_no","options":{"queryReplacement":"={{ [$('LINE Decode & Prepare Binary').first().json.line_user_id || '', $('LINE Decode & Prepare Binary').first().json.line_group_id || '', $('LINE Decode & Prepare Binary').first().json.line_message_id || '', $('LINE Decode & Prepare Binary').first().json.file_name || '', $('LINE Decode & Prepare Binary').first().json.file_type || '', $('LINE Decode & Prepare Binary').first().json.file_size || 0, $('LINE Decode & Prepare Binary').first().json.file_mime || '', $('LINE Decode & Prepare Binary').first().json.file_data_b64 || ''] }}"}},"id":"line-reg-start-pg","name":"LINE Register Start","type":"n8n-nodes-base.postgres","position":[1392,464],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}},"continueOnFail":true},{"parameters":{"httpMethod":"POST","path":"docs","responseMode":"responseNode","options":{}},"id":"wh-docs","name":"Docs Webhook","type":"n8n-nodes-base.webhook","position":[48,1200],"webhookId":"docs-webhook","typeVersion":2},{"parameters":{"jsCode":"// Smart Router: detect request type\\nconst req = $input.first().json;\\nconst body = req.body || req || {};\\nconst headers = req.headers || {};\\nconst query = req.query || {};\\n\\nconst isLineSignature = headers['x-line-signature'] !== undefined ||\\n  (Array.isArray(body.events) && body.events.length > 0);\\n\\nconst messageText = (body.message || body.text || '').toString().toLowerCase();\\nconst statsKeywords = ['สรุปผล', 'สถิติ', 'stats', 'summary', 'รายงาน', 'list', 'ทั้งหมด', 'all'];\\nconst isStats = !!statsKeywords.find(k => messageText.includes(k.toLowerCase())) || body.mode === 'stats';\\n\\nconst isRegistry = body.filename !== undefined || body.file_name !== undefined;\\n\\n// Routing priority:\\n// 1. LINE events (highest)\\n// 2. Registry (filename present)\\n// 3. Stats (keyword or mode=stats)\\n// 4. Search HTML (default - including mode=vector and mode=list)\\nlet route = 'search_html';\\nif (isLineSignature) route = 'line_event';\\nelse if (isRegistry) route = 'registry_insert';\\nelse if (isStats) route = 'stats_text';\\n\\nconst result = {\\n  _route: route,\\n  _body: body,\\n  _events: body.events || [],\\n  _query: query,\\n  _mode: body.mode || 'list',\\n  _q: body.q || '',\\n  _days: body.days || 7,\\n  _headers: headers\\n};\\nif (isLineSignature && body.events && body.events.length > 0) {\\n  result._event = body.events[0];\\n  result._replyToken = body.events[0].replyToken;\\n}\\nreturn [{ json: result }];\\n"},"id":"code-smart-router","name":"Smart Router","type":"n8n-nodes-base.code","position":[272,1104],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"line_event"}]},"renameOutput":true,"outputKey":"line"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"registry_insert"}]},"renameOutput":true,"outputKey":"registry"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"stats_text"}]},"renameOutput":true,"outputKey":"stats"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"search_html"}]},"renameOutput":true,"outputKey":"search"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"unknown"}},"id":"sw-route","name":"Route Switch","type":"n8n-nodes-base.switch","position":[496,1056],"typeVersion":3.2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._event.message.type }}","rightValue":"file"}]},"renameOutput":true,"outputKey":"is_file"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"not_file"}},"id":"sw-is-file","name":"LINE: Is file?","type":"n8n-nodes-base.switch","position":[720,464],"typeVersion":3.2},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": {{ JSON.stringify($('Smart Router').first().json._replyToken) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": \\"ส่งไฟล์ PDF/DOCX/TXT มาวิเคราะห์สัญญาได้เลย หรือพิมพ์คำถามเกี่ยวกับสัญญาได้เลย\\" }]\\n}","options":{"timeout":15000}},"id":"line-not-file","name":"LINE: Reply Non-File","type":"n8n-nodes-base.httpRequest","position":[3184,2688],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"respondWith":"text","responseBody":"={{ $('Format Response').first().json.body }}","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Type","value":"={{ $('Format Response').first().json.contentType }}"}]}}},"id":"resp-docs","name":"Respond Docs","type":"n8n-nodes-base.respondToWebhook","position":[3632,1568],"typeVersion":1},{"parameters":{"jsCode":"// Pick response based on route\\nconst route = $('Smart Router').first().json._route || 'search_html';\\nconst replyToken = $('Smart Router').first().json._replyToken;\\nlet body = '';\\nlet contentType = 'application/json; charset=utf-8';\\nif (route === 'registry_insert') {\\n  const r = $('Respond Registry').first().json || {};\\n  body = JSON.stringify(r);\\n} else if (route === 'stats_text') {\\n  const r = $('Respond Stats').first().json || $('Respond Not Stats').first().json || { ok: false };\\n  body = JSON.stringify(r);\\n} else if (route === 'line_event') {\\n  if (replyToken) {\\n    // Real LINE event - just ack\\n    body = JSON.stringify({ ok: true, route: 'line_event', events: $('Smart Router').first().json._events.length });\\n  } else {\\n    // Test mode - no replyToken. Return the AI agent decision so tester can verify routing.\\n    const aiResp = $('Parse AI Response').first().json || {};\\n    body = JSON.stringify({\\n      ok: true,\\n      mode: 'test',\\n      route: 'line_event',\\n      _route: aiResp._route || null,\\n      _text: aiResp._text || null,\\n      _query: aiResp._query || null,\\n      _filter: aiResp._filter || null,\\n      _tool_call_id: aiResp._tool_call_id || null\\n    });\\n  }\\n} else {\\n  body = ($('Render HTML').first().json || {}).html || '<h1>Error</h1>';\\n  contentType = 'text/html; charset=utf-8';\\n}\\nreturn [{ json: { body, contentType } }];\\n"},"id":"code-format-resp","name":"Format Response","type":"n8n-nodes-base.code","position":[3408,1568],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ $env.OLLAMA_URL || 'http://127.0.0.1:11434' }}/api/chat","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_AGENT_MODEL || 'qwen3.6:35b-a3b-q4_K_M' }}\\",\\n  \\"stream\\": false,\\n  \\"messages\\": {{ JSON.stringify([\\n    {role: 'system', content: 'คุณคือผู้ช่วย AI ของ Law Firm (Phuket Law Firm)\\\\n\\\\nตอบเป็นภาษาไทยเสมอ กระชับ ไม่เกิน 3-4 บรรทัด\\\\n\\\\n**เลือก tool ที่เหมาะสมที่สุด 1 ตัว ตาม intent:**\\\\n\\\\n1. `search_documents(query, limit=5)` — เมื่อ user ต้องการ ค้นหา/หา/ค้น/สืบค้น เอกสารที่เกี่ยวกับ เนื้อหา/หัวข้อ/keyword เฉพาะ (เช่น \\\\\\"หาสัญญาเช่า\\\\\\", \\\\\\"ค้นหนี้สิน\\\\\\", \\\\\\"มีสัญญาเกี่ยวกับที่ดินมั้ย\\\\\\")\\\\n\\\\n2. `list_documents(filter=\\\\\\"\\\\\\", limit=10)` — เมื่อ user ถาม จำนวน/กี่ฉบับ/list/ทั้งหมด/อันไหนบ้าง โดยไม่ระบุหัวข้อเฉพาะ (เช่น \\\\\\"มี contract กี่ฉบับ list มาให้หน่อย\\\\\\", \\\\\\"ทั้งหมดมีอะไรบ้าง\\\\\\", \\\\\\"มีเอกสารอะไรบ้าง\\\\\\")\\\\n\\\\n3. `get_stats()` — เมื่อ user ถาม สรุป/ภาพรวม/สถิติ/สถานะ/จัดกลุ่ม (เช่น \\\\\\"สรุปผล\\\\\\", \\\\\\"ภาพรวมเอกสาร\\\\\\", \\\\\\"มีกี่หมวดหมู่\\\\\\")\\\\n\\\\n4. ไม่ต้องใช้ tool — เมื่อ user ทักทาย/ถามทั่วไป/ถามเกี่ยวกับบริษัท\\\\n\\\\n**ตัวอย่าง intent → tool:**\\\\n- \\\\\\"หาสัญญาเช่า\\\\\\" → search_documents(query=\\\\\\"สัญญาเช่า\\\\\\")\\\\n- \\\\\\"มี contract กี่ฉบับ\\\\\\" → list_documents\\\\n- \\\\\\"list มาให้หน่อย\\\\\\" → list_documents\\\\n- \\\\\\"ทั้งหมดมีอะไรบ้าง\\\\\\" → list_documents\\\\n- \\\\\\"สรุปผลหน่อย\\\\\\" → get_stats\\\\n- \\\\\\"ภาพรวม\\\\\\" → get_stats\\\\n- \\\\\\"สวัสดี\\\\\\" → text reply\\\\n- \\\\\\"ช่วยได้อะไรบ้าง\\\\\\" → text reply อธิบาย capabilities\\\\n'},\\n    {role: 'user', content: $('Smart Router').first().json._event.message.text || 'สวัสดี'}\\n  ]) }},\\n  \\"tools\\": {{ JSON.stringify([\\n    {\\n      type: 'function',\\n      function: {\\n        name: 'search_documents',\\n        description: 'Search contracts by semantic similarity (vector search). Use when user asks about content/topic/keyword.',\\n        parameters: {\\n          type: 'object',\\n          properties: {\\n            query: {type: 'string', description: 'Search query in Thai'},\\n            limit: {type: 'integer', default: 5, description: 'Max results 1-20'}\\n          },\\n          required: ['query']\\n        }\\n      }\\n    },\\n    {\\n      type: 'function',\\n      function: {\\n        name: 'list_documents',\\n        description: 'List all contract documents in the registry. Returns metadata: doc_no, file_name, category, status, chunk_count, uploaded_at. Use when user asks for count, list, total, or all documents without specific topic.',\\n        parameters: {\\n          type: 'object',\\n          properties: {\\n            filter: {type: 'string', default: '', description: 'Optional filter by file_name or category (substring match)'},\\n            limit: {type: 'integer', default: 10, description: 'Max docs to return 1-50'}\\n          }\\n        }\\n      }\\n    },\\n    {\\n      type: 'function',\\n      function: {\\n        name: 'get_stats',\\n        description: 'Get statistics summary of all contracts: total count, breakdown by category and status. Use when user asks for summary, overview, stats, status breakdown.',\\n        parameters: {\\n          type: 'object',\\n          properties: {}\\n        }\\n      }\\n    }\\n  ]) }}\\n}","options":{"response":{"response":{"neverError":true}},"timeout":600000}},"id":"ollama-agent","name":"AI Agent (Ollama)","type":"n8n-nodes-base.httpRequest","position":[1392,2336],"typeVersion":4.2},{"parameters":{"jsCode":"// Parse Ollama response - robust text fallback using string matching\\nconst resp = $('AI Agent (Ollama)').first().json;\\nconst msg = resp.message || {};\\nlet toolCalls = msg.tool_calls || [];\\nconst content = (msg.content || '').trim();\\nconst thinking = (msg.thinking || '').trim();\\nconst allText = content + ' ' + thinking;\\n\\n// FALLBACK: detect tool call from text using simple string matching\\nif (toolCalls.length === 0 && content) {\\n  let detectedTool = null;\\n  if (content.includes('list_documents') || allText.includes('list_documents')) {\\n    detectedTool = 'list_documents';\\n  } else if (content.includes('search_documents') || allText.includes('search_documents')) {\\n    detectedTool = 'search_documents';\\n  } else if (content.includes('get_stats') || allText.includes('get_stats')) {\\n    detectedTool = 'get_stats';\\n  }\\n  \\n  if (detectedTool) {\\n    // Try to extract args from \\"(...)\\" \\n    let args = {};\\n    const parenMatch = content.match(new RegExp(detectedTool + '\\\\\\\\s*\\\\\\\\(([^)]*)\\\\\\\\)'));\\n    if (parenMatch) {\\n      const argsStr = parenMatch[1];\\n      // Match filter=\\"...\\" or query=\\"...\\" or limit=N\\n      const stringArg = argsStr.match(/(?:filter|query)\\\\\\\\s*=\\\\\\\\s*\\"([^\\"]*)\\"/);\\n      if (stringArg) {\\n        if (detectedTool === 'search_documents') args.query = stringArg[1];\\n        else args.filter = stringArg[1];\\n      }\\n      const intArg = argsStr.match(/limit\\\\\\\\s*=\\\\\\\\s*(\\\\\\\\d+)/);\\n      if (intArg) args.limit = parseInt(intArg[1]);\\n    }\\n    toolCalls = [{\\n      id: 'fallback-' + Date.now(),\\n      function: { name: detectedTool, arguments: args }\\n    }];\\n  }\\n}\\n\\nif (toolCalls.length > 0) {\\n  const tc = toolCalls[0];\\n  const toolName = tc.function.name;\\n  const args = typeof tc.function.arguments === 'string'\\n    ? (tc.function.arguments.trim() ? JSON.parse(tc.function.arguments) : {})\\n    : (tc.function.arguments || {});\\n\\n  if (toolName === 'search_documents') {\\n    return [{\\n      json: {\\n        _route: 'ai_search',\\n        _query: args.query || '',\\n        _limit: args.limit || 5,\\n        _tool_call_id: tc.id,\\n        _tool_name: toolName\\n      }\\n    }];\\n  } else if (toolName === 'list_documents') {\\n    return [{\\n      json: {\\n        _route: 'ai_list',\\n        _filter: args.filter || '',\\n        _limit: args.limit || 10,\\n        _tool_call_id: tc.id,\\n        _tool_name: toolName\\n      }\\n    }];\\n  } else if (toolName === 'get_stats') {\\n    return [{\\n      json: {\\n        _route: 'ai_stats',\\n        _tool_call_id: tc.id,\\n        _tool_name: toolName\\n      }\\n    }];\\n  }\\n}\\n\\nreturn [{\\n  json: {\\n    _route: 'ai_text',\\n    _text: content || 'ขออภัย ระบบไม่สามารถประมวลผลได้ในขณะนี้'\\n  }\\n}];\\n"},"id":"code-parse-agent","name":"Parse AI Response","type":"n8n-nodes-base.code","position":[1616,2336],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-search","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_search"}]},"renameOutput":true,"outputKey":"search"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-list","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_list"}]},"renameOutput":true,"outputKey":"list"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-stats","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_stats"}]},"renameOutput":true,"outputKey":"stats"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-text","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_text"}]},"renameOutput":true,"outputKey":"text"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"unknown"}},"id":"sw-ai-route","name":"AI Route Switch","type":"n8n-nodes-base.switch","position":[2288,2144],"typeVersion":3.2},{"parameters":{"method":"POST","url":"http://localhost:5678/webhook/vector-search-json","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"q\\": {{ JSON.stringify($json._query) }} }","options":{"response":{"response":{"neverError":true}},"timeout":60000}},"id":"ai-search","name":"AI: Call Vector Search","type":"n8n-nodes-base.httpRequest","position":[2512,1920],"typeVersion":4.2},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": {{ JSON.stringify($('Smart Router').first().json._replyToken) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": {{ JSON.stringify($json._text) }} }]\\n}","options":{"timeout":15000}},"id":"ai-text-reply","name":"AI: Reply Text","type":"n8n-nodes-base.httpRequest","position":[2960,2304],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"jsCode":"// Build LINE Flex message from search results (filtered by AI re-rank)\\nconst searchResp = $('AI: Call Vector Search').first().json;\\nconst query = $('Parse AI Response').first().json._query;\\nlet results = (searchResp.results || []).slice(0, 10);\\n\\n// Get AI re-rank selection if available\\nlet aiSelected = null;\\ntry {\\n  const rr = $('Parse Re-rank Response').first().json;\\n  if (rr && Array.isArray(rr._selected_doc_nos) && rr._selected_doc_nos.length > 0) {\\n    aiSelected = rr._selected_doc_nos;\\n  }\\n} catch (e) {\\n  aiSelected = null;\\n}\\n\\n// Use AI selection if available, else top 5 by similarity\\nlet orderedResults;\\nif (aiSelected && aiSelected.length > 0) {\\n  const byDocNo = new Map(results.map(r => [r.doc_no, r]));\\n  orderedResults = aiSelected\\n    .map(docNo => byDocNo.get(docNo))\\n    .filter(Boolean)\\n    .slice(0, 5);\\n} else {\\n  orderedResults = results.slice(0, 5);\\n}\\n\\nif (!orderedResults.length) {\\n  return [{\\n    json: {\\n      _flex: null,\\n      _fallback: `🔍 ไม่พบเอกสารที่เกี่ยวข้องกับ \\"${query}\\"\\\\n\\\\nเปิดดูเอกสารทั้งหมด: https://n8n.jesadakorn.com/webhook/docs-admin-ui?q=${encodeURIComponent(query)}\\\\n\\\\nลองค้นหาด้วยคำอื่น หรือพิมพ์ \\"สรุปผล\\" เพื่อดูภาพรวม`,\\n      _result_count: 0,\\n      _query: query\\n    }\\n  }];\\n}\\n\\nconst adminUrl = `https://n8n.jesadakorn.com/webhook/docs-admin-ui?q=${encodeURIComponent(query)}`;\\n\\n// Build match snippet with highlighted query (LINE Flex pattern, like flow 04 admin UI)\\nfunction buildMatchContent(content, q) {\\n  if (!content) {\\n    return [{ type: 'text', text: '', size: 'xs', color: '#999999', wrap: true }];\\n  }\\n  if (!q || q.trim().length === 0) {\\n    return [{\\n      type: 'text',\\n      text: content.slice(0, 140).replace(/\\\\n/g, ' ').trim() + (content.length > 140 ? '…' : ''),\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    }];\\n  }\\n\\n  // Find query or partial match in content (case-insensitive, Thai-aware)\\n  const lowerContent = content.toLowerCase();\\n  const lowerQuery = q.toLowerCase().trim();\\n\\n  // Try exact query first\\n  let idx = lowerContent.indexOf(lowerQuery);\\n  let matchedLen = lowerQuery.length;\\n  let matchedText = content.slice(idx, idx + matchedLen);\\n\\n  // Fallback: try substrings of the query (sliding window). Critical for Thai\\n  // where words aren't space-separated. Try longer substrings first.\\n  if (idx === -1 && lowerQuery.length >= 2) {\\n    const skip = ['ที่', 'ใน', 'ของ', 'และ', 'มี', 'เป็น', 'ได้', 'จะ', 'มา', 'ไป', 'ก็', 'ให้', 'แต่', 'หรือ', 'นี้', 'นั้น', 'มา', 'จาก', 'กับ', 'แล้ว', 'อยู่', 'ไหม', 'ครับ', 'ค่ะ'];\\n    for (let len = Math.min(lowerQuery.length, 10); len >= 2; len--) {\\n      for (let start = 0; start + len <= lowerQuery.length; start++) {\\n        const candidate = lowerQuery.slice(start, start + len);\\n        if (skip.includes(candidate)) continue;\\n        const wordIdx = lowerContent.indexOf(candidate);\\n        if (wordIdx !== -1) {\\n          idx = wordIdx;\\n          matchedLen = len;\\n          matchedText = content.slice(idx, idx + len);\\n          break;\\n        }\\n      }\\n      if (idx !== -1) break;\\n    }\\n  }\\n\\n  if (idx === -1) {\\n    return [{\\n      type: 'text',\\n      text: content.slice(0, 140).replace(/\\\\n/g, ' ').trim() + (content.length > 140 ? '…' : ''),\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    }];\\n  }\\n\\n  // Build context: ~30 chars before, the match, ~70 chars after\\n  const beforeStart = Math.max(0, idx - 30);\\n  const afterEnd = Math.min(content.length, idx + matchedLen + 70);\\n  const beforeText = (beforeStart > 0 ? '…' : '') + content.slice(beforeStart, idx).replace(/\\\\n/g, ' ').trim();\\n  const afterText = content.slice(idx + matchedLen, afterEnd).replace(/\\\\n/g, ' ').trim() + (afterEnd < content.length ? '…' : '');\\n\\n  // Highlight box containing the match snippet\\n  return [\\n    {\\n      type: 'text',\\n      text: beforeText,\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    },\\n    {\\n      type: 'box',\\n      layout: 'horizontal',\\n      backgroundColor: '#fef08a',\\n      cornerRadius: '4px',\\n      paddingAll: '4px',\\n      margin: 'xs',\\n      contents: [\\n        {\\n          type: 'text',\\n          text: matchedText,\\n          size: 'xs',\\n          color: '#713f12',\\n          weight: 'bold',\\n          flex: 0\\n        }\\n      ]\\n    },\\n    {\\n      type: 'text',\\n      text: afterText,\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    }\\n  ];\\n}\\n\\n// Build Flex card with carousel of results\\nconst bubbles = orderedResults.map(r => {\\n  // Use vector_sim (cosine 0-1) for the match % - more meaningful than RRF score\\n  const vectorSim = (r.vector_sim != null) ? r.vector_sim : (r.similarity || 0);\\n  const simPct = Math.max(0, Math.min(100, Math.round(vectorSim * 100)));\\n  const keywordHit = (r.keyword_sim != null) ? r.keyword_sim : 0;\\n\\n  const headerText = (r.doc_no && r.doc_no.length > 0) ? r.doc_no : '🔍 ' + (r.file_name || 'document').slice(0, 20);\\n  const docNo = (r.doc_no && r.doc_no.length > 0) ? r.doc_no : '';\\n\\n  return {\\n    type: 'bubble',\\n    size: 'mega',\\n    header: {\\n      type: 'box',\\n      layout: 'vertical',\\n      contents: [\\n        {\\n          type: 'text',\\n          text: headerText,\\n          weight: 'bold',\\n          size: 'sm',\\n          color: '#1a3a5c',\\n          wrap: true\\n        }\\n      ],\\n      backgroundColor: '#f5f7fa',\\n      paddingAll: 'sm'\\n    },\\n    body: {\\n      type: 'box',\\n      layout: 'vertical',\\n      contents: [\\n        {\\n          type: 'text',\\n          text: r.file_name || '',\\n          weight: 'bold',\\n          size: 'md',\\n          wrap: true\\n        },\\n        {\\n          type: 'box',\\n          layout: 'baseline',\\n          margin: 'md',\\n          contents: [\\n            {\\n              type: 'text',\\n              text: `📊 ${simPct}% match`,\\n              size: 'xs',\\n              color: simPct >= 50 ? '#15803d' : (simPct >= 30 ? '#b45309' : '#999999'),\\n              weight: 'bold'\\n            },\\n            {\\n              type: 'text',\\n              text: keywordHit > 0 ? ` · keyword ${keywordHit.toFixed(1)}` : '',\\n              size: 'xs',\\n              color: '#0a6b3e'\\n            },\\n            {\\n              type: 'text',\\n              text: ` · chunk #${r.chunk_index || 0}`,\\n              size: 'xs',\\n              color: '#999999'\\n            }\\n          ]\\n        },\\n        // Match snippet with highlighted query\\n        {\\n          type: 'box',\\n          layout: 'vertical',\\n          margin: 'md',\\n          contents: buildMatchContent(r.content || '', query)\\n        }\\n      ]\\n    },\\n    footer: {\\n      type: 'box',\\n      layout: 'vertical',\\n      contents: [\\n        {\\n          type: 'button',\\n          style: 'primary',\\n          color: '#1a3a5c',\\n          action: {\\n            type: 'uri',\\n            label: '📂 เปิดในระบบ',\\n            uri: adminUrl\\n          }\\n        },\\n        {\\n          type: 'button',\\n          style: 'secondary',\\n          margin: 'sm',\\n          action: {\\n            type: 'uri',\\n            label: docNo ? ('ดู ' + docNo) : '📋 ดูเอกสารทั้งหมด',\\n            uri: adminUrl\\n          }\\n        }\\n      ]\\n    }\\n  };\\n});\\n\\nconst flex = {\\n  type: 'flex',\\n  altText: `🔍 ผลการค้นหา: ${query} (${orderedResults.length} รายการ)`,\\n  contents: {\\n    type: 'carousel',\\n    contents: bubbles\\n  }\\n};\\n\\nreturn [{\\n  json: {\\n    _flex: flex,\\n    _fallback: `🔍 ผลการค้นหา: ${query} (${orderedResults.length} รายการ)\\\\n\\\\nเปิดดูในระบบ: ${adminUrl}`,\\n    _result_count: orderedResults.length,\\n    _query: query,\\n    _ai_filtered: !!(aiSelected && aiSelected.length > 0)\\n  }\\n}];\\n"},"id":"code-ai-flex","name":"AI: Build Flex Card","type":"n8n-nodes-base.code","position":[2848,1920],"typeVersion":2},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": {{ JSON.stringify($('Smart Router').first().json._replyToken) }},\\n  \\"messages\\": {{ JSON.stringify($('Build Safe Reply').first().json.messages) }}\\n}","options":{"timeout":15000}},"id":"ai-send-flex","name":"AI: Send Reply","type":"n8n-nodes-base.httpRequest","position":[3296,1920],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"operation":"executeQuery","query":"SELECT * FROM (SELECT doc_no, file_name, file_type, category, status, source, (SELECT COUNT(*) FROM contract_chunks WHERE contract_id = c.id) AS chunk_count, uploaded_at, FALSE AS _is_dummy FROM contracts c WHERE (($1::text IS NULL OR $1 = '') OR LOWER(file_name) LIKE '%' || LOWER($1) || '%' OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%') ORDER BY uploaded_at DESC LIMIT $2::int ) real_rows UNION ALL SELECT NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, TRUE AS _is_dummy WHERE NOT EXISTS (SELECT 1 FROM contracts) ORDER BY _is_dummy ASC, uploaded_at DESC NULLS LAST","options":{"queryReplacement":"={{ [$json._filter || null, $json._limit || 10] }}"}},"id":"ai-list-contracts","name":"AI: List Contracts","type":"n8n-nodes-base.postgres","position":[2512,2112],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed, (SELECT json_agg(json_build_object('category', COALESCE(category,'ไม่ระบุ'),'count', cnt) ORDER BY cnt DESC) FROM (SELECT category, COUNT(*) AS cnt FROM contracts GROUP BY category) x) AS by_category","options":{}},"id":"ai-get-stats","name":"AI: Get Stats","type":"n8n-nodes-base.postgres","position":[2512,2400],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Format list of contracts as readable Thai text\\nconst allItems = $('AI: List Contracts').all().map(i => i.json);\\nconst rows = allItems.filter(r => !r._is_dummy);\\nconst filter = $json._filter || '';\\nconst limit = $json._limit || 10;\\n\\nif (rows.length === 0) {\\n  const emptyText = filter\\n    ? `ไม่พบเอกสารที่ตรงกับ \\"${filter}\\"\\\\n\\\\nลองค้นหาด้วยคำอื่น หรือพิมพ์ \\"สรุปผล\\" เพื่อดูภาพรวม`\\n    : 'ตอนนี้ยังไม่มีเอกสารในระบบเลยครับ\\\\n\\\\nส่ง PDF/รูปภาพ เข้า LINE OA เพื่อเริ่มอัปโหลดได้เลย';\\n  return [{ json: { _text: emptyText } }];\\n}\\n\\nlet text = filter\\n  ? `📋 พบ ${rows.length} เอกสารที่ตรงกับ \\"${filter}\\" (แสดง ${rows.length}/${limit}):\\\\n\\\\n`\\n  : `📋 ตอนนี้มี ${rows.length} เอกสารในระบบ (แสดง ${rows.length}/${limit}):\\\\n\\\\n`;\\n\\nrows.forEach((r, i) => {\\n  const statusEmoji = r.status === 'ready' ? '✅' : r.status === 'pending' ? '⏳' : r.status === 'failed' ? '❌' : '❔';\\n  const date = r.uploaded_at ? new Date(r.uploaded_at).toLocaleDateString('th-TH', { year: 'numeric', month: 'short', day: 'numeric' }) : '';\\n  text += `${i+1}. ${statusEmoji} ${r.file_name}`;\\n  if (r.doc_no) text += ` (${r.doc_no})`;\\n  if (r.category) text += `\\\\n   หมวด: ${r.category} | chunks: ${r.chunk_count} | ${date}`;\\n  text += '\\\\n';\\n});\\n\\ntext += '\\\\n💡 พิมพ์ \\"หา[คำค้น]\\" เพื่อค้นหาแบบ semantic | \\"สรุปผล\\" เพื่อดูภาพรวม';\\n\\nreturn [{ json: { _text: text } }];\\n"},"id":"ai-format-list","name":"AI: Format List","type":"n8n-nodes-base.code","position":[2736,2112],"typeVersion":2},{"parameters":{"jsCode":"const rows = $('AI: Get Stats').all().map(i => i.json);\\nconst s = rows[0] || {};\\n\\nlet text = `📊 สรุปภาพรวมเอกสาร\\\\n\\\\n`;\\ntext += `📁 ทั้งหมด: ${s.total || 0} เอกสาร\\\\n`;\\ntext += `✅ พร้อมใช้งาน: ${s.ready || 0}\\\\n`;\\ntext += `⏳ กำลังประมวลผล: ${s.pending || 0}\\\\n`;\\ntext += `❌ ล้มเหลว: ${s.failed || 0}\\\\n\\\\n`;\\n\\nif (s.by_category && Array.isArray(s.by_category)) {\\n  text += `📂 แยกตามหมวดหมู่:\\\\n`;\\n  s.by_category.forEach(c => {\\n    text += `  • ${c.category}: ${c.count} ฉบับ\\\\n`;\\n  });\\n}\\n\\ntext += `\\\\n💡 พิมพ์ \\\\\\"list\\\\\\" เพื่อดูเอกสารทั้งหมด | \\\\\\"หา[คำค้น]\\\\\\" เพื่อค้นหา`;\\n\\nreturn [{ json: { _text: text } }];\\n"},"id":"ai-format-stats","name":"AI: Format Stats","type":"n8n-nodes-base.code","position":[2736,2400],"typeVersion":2},{"parameters":{"httpMethod":"POST","path":"vector-search-json","responseMode":"lastNode","options":{}},"id":"wh-vs-json","name":"JS-VS Webhook","type":"n8n-nodes-base.webhook","position":[48,112],"webhookId":"vs-json-wh","typeVersion":2},{"parameters":{"jsCode":"// Read q from either URL query OR body\\nconst wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst query = (q.q || body.q || '').toString().trim();\\nconst limit = parseInt(q.limit || body.limit || 10, 10) || 10;\\nreturn [{json: {query, _query: query, _limit: limit}}];\\n"},"id":"js-vs-parse","name":"JS-VS Parse","type":"n8n-nodes-base.code","position":[272,112],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || 'http://127.0.0.1:11434') }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.query) }} }","options":{"timeout":30000}},"id":"js-vs-embed","name":"JS-VS Embed","type":"n8n-nodes-base.httpRequest","position":[496,112],"typeVersion":4.1},{"parameters":{"operation":"executeQuery","query":"WITH q AS (SELECT $1::vector AS qvec, $3::text AS qtxt),\\nv AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         1 - (ch.embedding <=> q.qvec) AS v_sim,\\n         ROW_NUMBER() OVER (ORDER BY ch.embedding <=> q.qvec) AS v_rank\\n  FROM contract_chunks ch, q\\n  WHERE ch.embedding IS NOT NULL\\n  ORDER BY ch.embedding <=> q.qvec\\n  LIMIT $2::int * 2\\n),\\nt AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 1.0 ELSE 0 END)\\n         + (length(ch.content) - length(replace(ch.content, q.qtxt, '')))::float / greatest(length(q.qtxt), 1)::float * 0.1 AS t_sim,\\n         ROW_NUMBER() OVER (\\n           ORDER BY \\n             (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n             (length(ch.content) - length(replace(ch.content, q.qtxt, '')))::float DESC,\\n             ch.chunk_index ASC\\n         ) AS t_rank\\n  FROM contract_chunks ch, q\\n  ORDER BY \\n    (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n    (length(ch.content) - length(replace(ch.content, q.qtxt, '')))::float DESC\\n  LIMIT $2::int * 2\\n),\\nfused AS (\\n  SELECT COALESCE(v.contract_id, t.contract_id) AS contract_id,\\n         COALESCE(v.chunk_index, t.chunk_index) AS chunk_index,\\n         COALESCE(v.content, t.content) AS content,\\n         COALESCE(1.0/(60+v.v_rank), 0) + COALESCE(1.0/(60+t.t_rank), 0) AS rrf_score,\\n         COALESCE(v.v_sim, 0) AS vector_sim,\\n         COALESCE(t.t_sim, 0) AS keyword_sim\\n  FROM v FULL OUTER JOIN t USING (contract_id, chunk_index)\\n)\\nSELECT c.id AS contract_id, c.doc_no, c.file_name, f.chunk_index, f.content,\\n       f.rrf_score AS similarity, f.vector_sim, f.keyword_sim\\nFROM fused f JOIN contracts c ON c.id = f.contract_id\\nORDER BY f.rrf_score DESC\\nLIMIT $2::int","options":{"queryReplacement":"={{ [\\n  ($json.embeddings && $json.embeddings[0]) ? '[' + $json.embeddings[0].map(Number).join(',') + ']' : '[]',\\n  $json._limit || 10,\\n  $json._query || ''\\n] }}"}},"id":"js-vs-pg","name":"JS-VS PG","type":"n8n-nodes-base.postgres","position":[720,112],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Format hybrid search results as JSON\\nconst rows = $input.all().map(i => i.json).filter(r => r && r.contract_id);\\nreturn [{json: {\\n  ok: true,\\n  query: $('JS-VS Parse').first().json.query,\\n  count: rows.length,\\n  results: rows.map(r => ({\\n    contract_id: r.contract_id,\\n    doc_no: r.doc_no,\\n    file_name: r.file_name,\\n    chunk_index: r.chunk_index,\\n    content: r.content,\\n    similarity: parseFloat(r.similarity) || 0,\\n    vector_sim: parseFloat(r.vector_sim) || 0,\\n    keyword_sim: parseFloat(r.keyword_sim) || 0\\n  }))\\n}}];\\n"},"id":"js-vs-format","name":"JS-VS Format","type":"n8n-nodes-base.code","position":[944,112],"typeVersion":2},{"parameters":{"jsCode":"// Build LINE messages array: [text summary, flex cards]\\nconst bfc = $('AI: Build Flex Card').first().json || {};\\nlet aiSummary = '';\\ntry {\\n  const rr = $('Parse Re-rank Response').first().json;\\n  aiSummary = (rr && rr._summary ? rr._summary : '').toString().trim();\\n} catch (e) {}\\n\\nconst messages = [];\\n\\n// First: AI summary text (if available)\\nif (aiSummary) {\\n  messages.push({ type: 'text', text: aiSummary });\\n}\\n\\n// Second: Flex card or fallback text\\nlet cardMessage = null;\\nif (bfc._flex) {\\n  const flex = bfc._flex;\\n  if (flex.type === 'flex' && flex.altText && flex.contents) {\\n    cardMessage = flex;\\n  }\\n}\\nif (!cardMessage && bfc._fallback) {\\n  cardMessage = { type: 'text', text: bfc._fallback };\\n}\\nif (cardMessage) {\\n  messages.push(cardMessage);\\n}\\n\\n// Last resort: at least one message\\nif (messages.length === 0) {\\n  messages.push({ type: 'text', text: 'ไม่สามารถแสดงผลได้ในขณะนี้' });\\n}\\n\\nreturn [{ json: { messages } }];\\n"},"id":"build-safe-reply","name":"Build Safe Reply","type":"n8n-nodes-base.code","position":[3072,1920],"typeVersion":2},{"parameters":{"jsCode":"// Download LINE message content and expose both binary + base64 for storage.\\n// The channel token must come from the n8n runtime environment.\\nconst sm = $('Smart Router').first().json;\\nconst evt = sm._event || {};\\nconst messageId = evt.message?.id;\\nif (!messageId) {\\n  throw new Error('No message id from Smart Router event');\\n}\\n\\nconst token = ($env.LINE_CHANNEL_ACCESS_TOKEN || '').trim();\\nif (!token) {\\n  throw new Error('Missing LINE_CHANNEL_ACCESS_TOKEN in n8n environment');\\n}\\n\\nlet response;\\ntry {\\n  response = await this.helpers.httpRequest({\\n    method: 'GET',\\n    url: `https://api-data.line.me/v2/bot/message/${messageId}/content`,\\n    headers: { Authorization: `Bearer ${token}` },\\n    // n8n's helper maps 'encoding' -> axios 'responseType' (see\\n    // n8n-core/dist/execution-engine/.../http-request.js:60-62). 'encoding: null'\\n    // was silently coerced to axios 'responseType: null' which defaults to\\n    // 'json' -> UTF-8 decode + U+FFFD replacement for invalid bytes (verified June\\n    // 2026: 69,301 bytes -> 111,939 bytes with 21,746 U+FFFD chars).\\n    // 'encoding: arraybuffer' -> axios returns ArrayBuffer (raw bytes).\\n    encoding: 'arraybuffer',\\n    timeout: 30000,\\n  });\\n} catch (e) {\\n  throw new Error(`LINE content download failed: ${e.message} (message_id=${messageId})`);\\n}\\n\\n// responseType: 'arraybuffer' returns ArrayBuffer; wrap to Buffer for downstream ops.\\nconst buffer = Buffer.from(response);\\nif (!buffer || buffer.length === 0) {\\n  throw new Error('Empty response from LINE content API');\\n}\\n\\nconst msg = evt.message || {};\\nconst src = evt.source || {};\\nconst fname = msg.fileName || 'upload.pdf';\\nconst ext = fname.toLowerCase().split('.').pop();\\nlet mime = msg.type === 'image' ? 'image/jpeg' : 'application/octet-stream';\\nif (ext === 'pdf') mime = 'application/pdf';\\nelse if (ext === 'png') mime = 'image/png';\\nelse if (ext === 'jpg' || ext === 'jpeg') mime = 'image/jpeg';\\nelse if (ext === 'txt') mime = 'text/plain';\\nelse if (ext === 'docx') mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';\\n\\nconst b64 = buffer.toString('base64');\\nconst binaryData = await this.helpers.prepareBinaryData(buffer, fname, mime);\\n\\nreturn [{\\n  json: Object.assign({}, sm, {\\n    _event: evt,\\n    line_user_id: src.userId || '',\\n    line_group_id: src.groupId || '',\\n    line_message_id: messageId || '',\\n    file_type: ext || '',\\n    file_data_b64: b64,\\n    file_mime: mime,\\n    file_name: fname,\\n    file_size: buffer.length,\\n  }),\\n  binary: binaryData\\n}];\\n"},"id":"code-decode-prepare","name":"LINE Decode & Prepare Binary","type":"n8n-nodes-base.code","position":[944,464],"typeVersion":2},{"parameters":{"conditions":{"boolean":[{"value1":"={{ $json.has_chunks }}","value2":true}]}},"id":"node-300","name":"Has Chunks?","type":"n8n-nodes-base.if","position":[2064,464],"typeVersion":1},{"parameters":{"jsCode":"// Set _has_reply_token flag based on Smart Router's _replyToken\\nconst sr = $('Smart Router').first().json;\\nconst replyToken = sr._replyToken;\\nconst hasReplyToken = (typeof replyToken === 'string' && replyToken.length > 0);\\n\\n// Pass through input + add flag\\nconst input = $input.first().json;\\nreturn [{\\n  json: {\\n    ...input,\\n    _has_reply_token: hasReplyToken,\\n    _reply_token_value: replyToken || null\\n  }\\n}];"},"id":"code-check-rt","name":"Check Reply Token","type":"n8n-nodes-base.code","position":[1840,2336],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ String($json._has_reply_token) }}","rightValue":"true"}]},"renameOutput":true,"outputKey":"real_line"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"notEquals"},"leftValue":"={{ String($json._has_reply_token) }}","rightValue":"true"}]},"renameOutput":true,"outputKey":"test_mode"}]},"options":{}},"id":"if-has-reply-token","name":"Has Reply Token?","type":"n8n-nodes-base.switch","position":[2064,2336],"typeVersion":3.2},{"parameters":{"jsCode":"// Rollback: collect the contract id we tried to save so we can DELETE it.\\nconst start = $('LINE Register Start').first();\\nconst id = start && start.json && start.json.id;\\nreturn [{ json: { contract_id: id, action: 'rollback' } }];\\n"},"id":"63098214-c190-4b93-8f32-4c94ffccb7fc","name":"LINE Rollback File","type":"n8n-nodes-base.code","position":[2736,624],"executeOnce":false,"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"DELETE FROM contracts WHERE id = $1::uuid RETURNING id","options":{"queryReplacement":"={{ [$json.contract_id || ''] }}"}},"id":"4f9ec6d5-5947-4b71-8169-9d5b96595407","name":"LINE Delete Contract Row","type":"n8n-nodes-base.postgres","position":[2960,624],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Normalize Chunk text output to a boolean has_chunks field.\\n// IF v1 with strict typeValidation mis-evaluates Number($json.x) > 0\\n// when chunk_count is 0, so we do the comparison here in JS land.\\nconst info = $input.first().json || {};\\nconst chunkCount = Number(info.chunk_count || 0);\\nconst hasChunks = chunkCount > 0;\\nreturn [{\\n  json: Object.assign({}, info, {\\n    chunk_count: chunkCount,\\n    has_chunks: hasChunks,\\n  })\\n}];\\n"},"id":"node-301","name":"LINE: Normalize Has Chunks","type":"n8n-nodes-base.code","position":[1840,464],"typeVersion":2},{"parameters":{"httpMethod":"POST","path":"contract-rag-line","responseMode":"responseNode","options":{}},"id":"line-webhook-trigger","name":"LINE Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[48,1008],"webhookId":"contract-rag-line-webhook"},{"parameters":{"method":"POST","url":"http://127.0.0.1:8765/vision","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={{ JSON.stringify({ file_data_b64: $json.file_data_b64, file_mime: $json.file_mime, file_name: $json.file_name }) }}","options":{"timeout":180000}},"id":"line-extract-vision","name":"LINE Extract via Vision LLM","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[1168,464]},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || 'http://127.0.0.1:11434') }}/api/chat","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_AGENT_MODEL || 'qwen3.6:35b-a3b-q4_K_M' }}\\",\\n  \\"stream\\": false,\\n  \\"format\\": \\"json\\",\\n  \\"messages\\": {{ JSON.stringify([\\n    {role: 'system', content: 'คุณคือผู้ช่วยคัดเลือกเอกสาร (re-ranker) สำหรับสำนักงานกฎหมายไทย\\\\n\\\\nหน้าที่ของคุณ:\\\\n1. อ่าน search results ที่ได้รับ (อาจมี similarity ต่ำ เพราะ embedding model เป็น general purpose)\\\\n2. ดูชื่อไฟล์ + เนื้อหาตัวอย่าง แล้วเลือก 3-5 ฉบับที่เกี่ยวข้องกับ query จริงๆ (เรียงตามความเกี่ยวข้อง)\\\\n3. เขียนสรุปสั้นๆ 1-2 บรรทัดเป็นภาษาไทย บอกว่า:\\\\n   - พบเอกสารที่ตรง query กี่ฉบับ (ระบุ doc_no)\\\\n   - ถ้ามี noise (เอกสารไม่เกี่ยว) ให้บอกด้วยว่าเป็นประเภทอื่น\\\\n   - ถ้าไม่มีตรงเลย ให้บอกว่าไม่พบและแนะนำให้ลองคำอื่น\\\\n\\\\nตอบเป็น JSON เท่านั้น:\\\\n{\\"summary\\": \\"ข้อความสรุป 1-2 บรรทัด\\", \\"selected_doc_nos\\": [\\"DOC-XXX\\", \\"DOC-YYY\\"]}\\\\n\\\\nถ้าไม่มีเอกสารที่เกี่ยวข้องเลย ให้ selected_doc_nos เป็น array ว่าง'},\\n    {role: 'user', content: 'Query: ' + $('Parse AI Response').first().json._query + '\\\\n\\\\nSearch results:\\\\n' + JSON.stringify(($('AI: Call Vector Search').first().json.results || []).map((r, i) => '[' + (i+1) + '] doc_no=' + r.doc_no + ', file=' + r.file_name + ', sim=' + ((r.similarity || 0)*100).toFixed(1) + '%\\\\n    content: ' + (r.content || '').slice(0, 200).replace(/\\\\n/g, ' ')))}\\n  ]) }}\\n}","options":{"response":{"response":{"neverError":true}},"timeout":600000}},"id":"ai-rerank-http","name":"AI: Re-rank & Summarize","type":"n8n-nodes-base.httpRequest","position":[2624,1920],"typeVersion":4.2},{"parameters":{"jsCode":"// Parse Ollama re-rank response\\nconst resp = $('AI: Re-rank & Summarize').first().json;\\nconst msg = resp.message || {};\\nconst content = (msg.content || '').trim();\\nconst thinking = (msg.thinking || '').trim();\\nconst allText = content || thinking;\\n\\nlet summary = '';\\nlet selected = [];\\n\\n// Try to parse JSON from content\\nif (content) {\\n  try {\\n    // Ollama format:json sometimes wraps in ```json ... ```\\n    let cleanContent = content.replace(/^```json\\\\s*/i, '').replace(/```\\\\s*$/, '').trim();\\n    const parsed = JSON.parse(cleanContent);\\n    summary = (parsed.summary || '').toString().trim();\\n    if (Array.isArray(parsed.selected_doc_nos)) {\\n      selected = parsed.selected_doc_nos.map(s => s.toString().trim()).filter(Boolean);\\n    }\\n  } catch (e) {\\n    // Try to extract JSON object from text\\n    const jsonMatch = content.match(/\\\\{[\\\\s\\\\S]*\\\\}/);\\n    if (jsonMatch) {\\n      try {\\n        const parsed = JSON.parse(jsonMatch[0]);\\n        summary = (parsed.summary || '').toString().trim();\\n        if (Array.isArray(parsed.selected_doc_nos)) {\\n          selected = parsed.selected_doc_nos.map(s => s.toString().trim()).filter(Boolean);\\n        }\\n      } catch (e2) {\\n        // Give up on JSON - treat whole content as summary\\n        summary = content.slice(0, 300);\\n      }\\n    } else {\\n      summary = content.slice(0, 300);\\n    }\\n  }\\n}\\n\\nreturn [{\\n  json: {\\n    _summary: summary,\\n    _selected_doc_nos: selected,\\n    _raw_content: content\\n  }\\n}];\\n"},"id":"ai-rerank-parse","name":"Parse Re-rank Response","type":"n8n-nodes-base.code","position":[2736,1920],"typeVersion":2}]	{"JS-VS PG":{"main":[[{"node":"JS-VS Format","type":"main","index":0}]]},"Is stats?":{"main":[[{"node":"PG: Aggregate Stats","type":"main","index":0}],[{"node":"Respond Not Stats","type":"main","index":0}]]},"Embed Query":{"main":[[{"node":"Build Vector Params","type":"main","index":0}]]},"Has Chunks?":{"main":[[{"node":"LINE Embed all chunks (Ollama bge-m3)","type":"main","index":0}],[{"node":"LINE Rollback File","type":"main","index":1}]]},"JS-VS Embed":{"main":[[{"node":"JS-VS PG","type":"main","index":0}]]},"JS-VS Parse":{"main":[[{"node":"JS-VS Embed","type":"main","index":0}]]},"Mode Switch":{"main":[[{"node":"PG: List Docs","type":"main","index":0}],[{"node":"Embed Query","type":"main","index":0}]]},"Render HTML":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"Docs Webhook":{"main":[[{"node":"Smart Router","type":"main","index":0}]]},"Parse Search":{"main":[[{"node":"Mode Switch","type":"main","index":0}]]},"Route Switch":{"main":[[{"node":"LINE: Is file?","type":"main","index":0}],[{"node":"Prep Registry Row","type":"main","index":0}],[{"node":"Parse Stats Request","type":"main","index":0}],[{"node":"Parse Search","type":"main","index":0}]]},"Smart Router":{"main":[[{"node":"Route Switch","type":"main","index":0}]]},"AI: Get Stats":{"main":[[{"node":"AI: Format Stats","type":"main","index":0}]]},"JS-VS Webhook":{"main":[[{"node":"JS-VS Parse","type":"main","index":0}]]},"PG: By Status":{"main":[[{"node":"Render HTML","type":"main","index":0}]]},"PG: List Docs":{"main":[[{"node":"PG: Daily Activity","type":"main","index":0}]]},"Respond Stats":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: Reply Text":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: Send Reply":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"LINE: Is file?":{"main":[[{"node":"LINE Decode & Prepare Binary","type":"main","index":0}],[{"node":"AI Agent (Ollama)","type":"main","index":0}]]},"AI Route Switch":{"main":[[{"node":"AI: Call Vector Search","type":"main","index":0}],[{"node":"AI: List Contracts","type":"main","index":0}],[{"node":"AI: Get Stats","type":"main","index":0}],[{"node":"AI: Reply Text","type":"main","index":0}]]},"AI: Format List":{"main":[[{"node":"AI: Reply Text","type":"main","index":0}]]},"Format Response":{"main":[[{"node":"Respond Docs","type":"main","index":0}]]},"LINE Chunk text":{"main":[[{"node":"LINE: Normalize Has Chunks","type":"main","index":0}]]},"Needs generate?":{"main":[[{"node":"PG: Get Next Seq","type":"main","index":0}],[{"node":"Passthrough (use provided doc_no)","type":"main","index":0}]]},"AI: Format Stats":{"main":[[{"node":"AI: Reply Text","type":"main","index":0}]]},"Build Safe Reply":{"main":[[{"node":"AI: Send Reply","type":"main","index":0}]]},"Has Reply Token?":{"main":[[{"node":"AI Route Switch","type":"main","index":0}],[{"node":"Format Response","type":"main","index":0}]]},"LINE Reply Error":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"PG: Get Next Seq":{"main":[[{"node":"PG: Insert/Update Document","type":"main","index":0}]]},"Respond Registry":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI Agent (Ollama)":{"main":[[{"node":"Parse AI Response","type":"main","index":0}]]},"Check Reply Token":{"main":[[{"node":"Has Reply Token?","type":"main","index":0}]]},"Format Stats Text":{"main":[[{"node":"Respond Stats","type":"main","index":0}]]},"PG: Vector Search":{"main":[[{"node":"PG: Daily Activity","type":"main","index":0}]]},"Parse AI Response":{"main":[[{"node":"Check Reply Token","type":"main","index":0}]]},"Prep Registry Row":{"main":[[{"node":"Needs generate?","type":"main","index":0}]]},"Respond Not Stats":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: List Contracts":{"main":[[{"node":"AI: Format List","type":"main","index":0}]]},"LINE Reply Success":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"LINE Rollback File":{"main":[[{"node":"LINE Delete Contract Row","type":"main","index":0}]]},"PG: Daily Activity":{"main":[[{"node":"PG: Recent Activity","type":"main","index":0}]]},"AI: Build Flex Card":{"main":[[{"node":"Build Safe Reply","type":"main","index":0}]]},"Build Vector Params":{"main":[[{"node":"PG: Vector Search","type":"main","index":0}]]},"LINE Register Start":{"main":[[{"node":"LINE Chunk text","type":"main","index":0}]]},"PG: Aggregate Stats":{"main":[[{"node":"Format Stats Text","type":"main","index":0}]]},"PG: Recent Activity":{"main":[[{"node":"PG: By Status","type":"main","index":0}]]},"Parse Stats Request":{"main":[[{"node":"Is stats?","type":"main","index":0}]]},"LINE: Reply Non-File":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: Call Vector Search":{"main":[[{"node":"AI: Re-rank & Summarize","type":"main","index":0}]]},"LINE Delete Contract Row":{"main":[[{"node":"LINE Reply Error","type":"main","index":0}]]},"PG: Insert/Update Document":{"main":[[{"node":"Respond Registry","type":"main","index":0}]]},"LINE Decode & Prepare Binary":{"main":[[{"node":"LINE Extract via Vision LLM","type":"main","index":0}]]},"LINE Combine metadata + vectors":{"main":[[{"node":"LINE Build Store SQL","type":"main","index":0}]]},"Passthrough (use provided doc_no)":{"main":[[{"node":"PG: Insert/Update Document","type":"main","index":0}]]},"LINE Embed all chunks (Ollama bge-m3)":{"main":[[{"node":"LINE Combine metadata + vectors","type":"main","index":0}]]},"LINE: Normalize Has Chunks":{"main":[[{"node":"Has Chunks?","type":"main","index":0}]]},"LINE Webhook":{"main":[[{"node":"Smart Router","type":"main","index":0}]]},"LINE Extract via Vision LLM":{"main":[[{"node":"LINE Register Start","type":"main","index":0}]]},"LINE Build Store SQL":{"main":[[{"node":"PG: Store Embeddings","type":"main","index":0}]]},"PG: Store Embeddings":{"main":[[{"node":"LINE Reply Success","type":"main","index":0}],[{"node":"LINE Reply Error","type":"main","index":1}]]},"AI: Re-rank & Summarize":{"main":[[{"node":"Parse Re-rank Response","type":"main","index":0}]]},"Parse Re-rank Response":{"main":[[{"node":"AI: Build Flex Card","type":"main","index":0}]]}}	2026-06-18 11:19:01.736+07	2026-06-23 19:26:43.431+07	{"executionOrder":"v1","saveManualExecutions":true,"saveExecutionProgress":true,"saveDataErrorExecution":"all","saveDataSuccessExecution":"all","binaryMode":"separate"}	\N	{}	9a290dc3-4ead-4606-adec-2f3df5650125	3	TL2qrOygnWKY69xe	{"templateCredsSetupCompleted":true}	\N	f	57	Docs Hub: LINE pipeline + registry + search + AI agent	9a290dc3-4ead-4606-adec-2f3df5650125	[]	\N
04 - Docs Admin (CRUD UI)	t	[{"parameters":{"path":"docs-admin-ui","responseMode":"responseNode","options":{}},"id":"wh-admin-ui","name":"Admin UI Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,0],"webhookId":"admin-ui-webhook"},{"parameters":{"jsCode":"// Return HTML page for Docs Admin\\nconst html = `<!doctype html>\\n<html lang=\\"th\\">\\n<head>\\n<meta charset=\\"utf-8\\">\\n<title>Docs Admin | Phuket Law</title>\\n<meta name=\\"viewport\\" content=\\"width=device-width,initial-scale=1\\">\\n<script>\\n  // No-flash theme bootstrap: set data-theme BEFORE <style> parses so first\\n  // paint uses the right colors. Order: localStorage > OS preference > dark.\\n  (function(){\\n    try{\\n      var saved = localStorage.getItem('lawpoc-admin-theme');\\n      var theme = saved || (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');\\n      document.documentElement.setAttribute('data-theme', theme);\\n    }catch(e){ document.documentElement.setAttribute('data-theme', 'dark'); }\\n  })();\\n</script>\\n<style>\\n:root{\\n  /* Core tokens (light defaults) */\\n  --bg:#f6f7f9;--card:#fff;--ink:#0f172a;--muted:#64748b;--muted-2:#94a3b8;\\n  --bd:#e2e8f0;--bd-soft:#f1f5f9;\\n  --pri:#0f766e;--pri-2:#0d9488;--warn:#b45309;--err:#b91c1c;--ok:#15803d;\\n\\n  /* Component tokens (light) */\\n  --header-bg:#0f172a;--header-fg:#fff;--crumb-fg:#94a3b8;\\n  --hover-bg:#f1f5f9;--th-bg:#f8fafc;\\n  --row-divider:#f1f5f9;--row-hover-bg:#fafbfc;\\n  --mono-fg:#475569;--chunk-text:#334155;\\n  --modal-overlay:rgba(15,23,42,.5);--modal-card:#fff;--modal-ft-bg:#f8fafc;\\n  --file-preview-bg:#f8fafc;--input-bg:#fff;\\n  --toast-bg:#0f172a;--toast-fg:#fff;\\n  --spinner-border:#fff;\\n  --sticky-act-shadow:rgba(15,23,42,.15);\\n\\n  /* Status badges (light = pastel solid; dark = semi-transparent tinted) */\\n  --badge-ready-bg:#dcfce7;     --badge-ready-fg:#15803d;\\n  --badge-pending-bg:#fef3c7;   --badge-pending-fg:#b45309;\\n  --badge-failed-bg:#fee2e2;    --badge-failed-fg:#b91c1c;\\n  --badge-processing-bg:#dbeafe;--badge-processing-fg:#1d4ed8;\\n\\n  /* Shadow tokens */\\n  --shadow-sm:0 1px 2px rgba(15,23,42,.06);\\n  --shadow-md:0 4px 12px rgba(15,23,42,.08);\\n}\\n[data-theme=\\"dark\\"]{\\n  --bg:#0e1422;--card:#161e35;--ink:#f1f5f9;--muted:#94a3b8;--muted-2:#64748b;\\n  --bd:rgba(148,163,184,.15);--bd-soft:rgba(148,163,184,.08);\\n  --pri:#2dd4bf;--pri-2:#14b8a6;--warn:#fbbf24;--err:#f87171;--ok:#4ade80;\\n\\n  --header-bg:#050a17;--header-fg:#f1f5f9;--crumb-fg:#64748b;\\n  --hover-bg:rgba(148,163,184,.08);--th-bg:rgba(148,163,184,.05);\\n  --row-divider:rgba(148,163,184,.08);--row-hover-bg:rgba(20,184,166,.05);\\n  --mono-fg:#cbd5e1;--chunk-text:#cbd5e1;\\n  --modal-overlay:rgba(0,0,0,.7);--modal-card:#161e35;--modal-ft-bg:#0e1422;\\n  --file-preview-bg:#0e1422;--input-bg:#0e1422;\\n  --toast-bg:#f1f5f9;--toast-fg:#0f172a;\\n  --spinner-border:#0e1422;\\n  --sticky-act-shadow:rgba(0,0,0,.5);\\n\\n  --badge-ready-bg:rgba(34,197,94,.18);     --badge-ready-fg:#4ade80;\\n  --badge-pending-bg:rgba(245,158,11,.18);   --badge-pending-fg:#fbbf24;\\n  --badge-failed-bg:rgba(239,68,68,.18);    --badge-failed-fg:#f87171;\\n  --badge-processing-bg:rgba(59,130,246,.18);--badge-processing-fg:#60a5fa;\\n\\n  --shadow-sm:0 1px 2px rgba(0,0,0,.4);\\n  --shadow-md:0 4px 12px rgba(0,0,0,.4);\\n}\\n*{box-sizing:border-box}\\nbody{font:14px/1.5 -apple-system,\\"SF Pro Text\\",\\"Inter\\",system-ui,sans-serif;margin:0;background:var(--bg);color:var(--ink);transition:background-color .2s ease,color .2s ease}\\nheader{background:var(--header-bg);color:var(--header-fg);padding:14px 24px;display:flex;align-items:center;gap:16px;box-shadow:0 1px 0 rgba(0,0,0,.2);transition:background-color .2s ease}\\nheader h1{font-size:16px;font-weight:600;margin:0;letter-spacing:.2px}\\nheader .crumb{color:var(--crumb-fg);font-size:12px;margin-left:auto}\\nheader .theme-toggle{margin-left:8px;background:transparent;color:var(--header-fg);border:1px solid rgba(255,255,255,.18);border-radius:8px;height:32px;width:32px;padding:0;cursor:pointer;font-size:14px;display:inline-flex;align-items:center;justify-content:center;transition:all .15s}\\nheader .theme-toggle:hover{background:rgba(255,255,255,.08);border-color:rgba(255,255,255,.35)}\\n.wrap{max-width:1280px;margin:0 auto;padding:24px}\\n.toolbar{display:flex;gap:8px;align-items:center;margin-bottom:16px;flex-wrap:wrap}\\n.toolbar input,.toolbar select{height:36px;padding:0 12px;border:1px solid var(--bd);border-radius:8px;background:var(--input-bg);font:inherit;color:var(--ink);outline:none;transition:border-color .15s,box-shadow .15s}\\n.toolbar input:focus,.toolbar select:focus{border-color:var(--pri-2);box-shadow:0 0 0 3px rgba(13,148,136,.2)}\\n.toolbar input.search{flex:1;min-width:200px}\\n\\n.similarity-bar{display:inline-block;height:6px;border-radius:3px;background:var(--bd);width:60px;vertical-align:middle;margin-right:6px;position:relative;overflow:hidden}\\n.similarity-bar>span{position:absolute;left:0;top:0;bottom:0;background:var(--pri)}\\n.chunk-preview{font-size:11px;color:var(--muted);margin-top:4px;line-height:1.4;max-width:420px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\\n.btn{height:36px;padding:0 14px;border:0;border-radius:8px;background:var(--pri);color:#fff;font:inherit;font-weight:500;cursor:pointer;display:inline-flex;align-items:center;gap:6px;transition:background-color .15s,box-shadow .15s,transform .05s}\\n.btn:hover{background:var(--pri-2)}\\n.btn:active{transform:translateY(1px)}\\n.btn.ghost{background:transparent;color:var(--ink);border:1px solid var(--bd)}\\n.btn.ghost:hover{background:var(--hover-bg)}\\n.btn.warn{background:var(--warn)}\\n.btn.danger{background:var(--err)}\\n.btn.sm{height:28px;padding:0 10px;font-size:12px;border-radius:6px}\\n.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}\\n.stat{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:14px;box-shadow:var(--shadow-sm);transition:background-color .2s ease,border-color .2s ease}\\n.stat .label{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}\\n.stat .num{font-size:24px;font-weight:600;margin-top:4px}\\n.stat .num.warn{color:var(--warn)} .stat .num.ok{color:var(--ok)} .stat .num.err{color:var(--err)}\\n.card{background:var(--card);border:1px solid var(--bd);border-radius:12px;overflow-x:auto;box-shadow:var(--shadow-sm);transition:background-color .2s ease,border-color .2s ease}\\ntable{width:100%;border-collapse:collapse;font-size:13px}\\nth{text-align:left;padding:12px 14px;background:var(--th-bg);font-weight:600;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.4px;border-bottom:1px solid var(--bd)}\\ntd{padding:12px 14px;border-bottom:1px solid var(--row-divider);vertical-align:middle}\\ntr:hover td{background:var(--row-hover-bg)}\\ntr:last-child td{border-bottom:0}\\ntd.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--mono-fg)}\\ntd .name{font-weight:500;color:var(--ink)}\\ntd .name small{display:block;color:var(--muted);font-weight:400;font-size:11px;margin-top:2px}\\n.badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:500}\\n.badge.ready{background:var(--badge-ready-bg);color:var(--badge-ready-fg)}\\n.badge.pending{background:var(--badge-pending-bg);color:var(--badge-pending-fg)}\\n.badge.failed{background:var(--badge-failed-bg);color:var(--badge-failed-fg)}\\n.badge.processing{background:var(--badge-processing-bg);color:var(--badge-processing-fg)}\\n.empty{padding:60px 20px;text-align:center;color:var(--muted)}\\n.empty h3{margin:0 0 6px;font-weight:500;color:var(--ink)}\\n.row-actions{display:flex;gap:6px;justify-content:flex-end;position:sticky;right:0;background:var(--card);padding-left:12px;box-shadow:-8px 0 12px -6px var(--sticky-act-shadow)}\\n.row-actions::before{content:'';position:absolute;left:-12px;top:0;bottom:0;width:12px;background:linear-gradient(to right,transparent,var(--card) 70%);pointer-events:none}\\nth.sticky-act{position:sticky;right:0;background:var(--th-bg);z-index:2;box-shadow:-8px 0 12px -6px var(--sticky-act-shadow)}\\n.modal{position:fixed;inset:0;background:var(--modal-overlay);display:none;align-items:center;justify-content:center;z-index:50;padding:20px}\\n.modal.on{display:flex}\\n.modal .box{background:var(--modal-card);border-radius:12px;width:100%;max-width:760px;max-height:90vh;display:flex;flex-direction:column;overflow:hidden;box-shadow:var(--shadow-md)}\\n#m-view .box{max-width:1180px}\\n.preview-grid{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(320px,.75fr);gap:16px}\\n.preview-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px}\\n.file-preview{height:min(66vh,720px);min-height:420px;border:1px solid var(--bd);border-radius:8px;overflow:hidden;background:var(--file-preview-bg)}\\n.file-preview iframe{width:100%;height:100%;border:0;background:var(--input-bg)}\\n.meta-grid{grid-template-columns:1fr 1fr}\\n@media(max-width:900px){.preview-grid{grid-template-columns:1fr}.file-preview{height:60vh;min-height:320px}.grid2,.meta-grid{grid-template-columns:1fr}}\\n.modal .hd{padding:16px 20px;border-bottom:1px solid var(--bd);display:flex;align-items:center;gap:12px}\\n.modal .hd h2{margin:0;font-size:16px;font-weight:600;flex:1}\\n.modal .bd{padding:20px;overflow-y:auto;flex:1}\\n.modal .ft{padding:14px 20px;border-top:1px solid var(--bd);display:flex;justify-content:flex-end;gap:8px;background:var(--modal-ft-bg)}\\n.field{margin-bottom:14px}\\n.field label{display:block;font-size:12px;font-weight:500;color:var(--muted);margin-bottom:4px}\\n.field input,.field select,.field textarea{width:100%;padding:8px 10px;border:1px solid var(--bd);border-radius:6px;font:inherit;background:var(--input-bg);color:var(--ink);transition:border-color .15s,box-shadow .15s}\\n.field input:focus,.field select:focus,.field textarea:focus{outline:none;border-color:var(--pri-2);box-shadow:0 0 0 3px rgba(13,148,136,.2)}\\n.field .hint{font-size:11px;color:var(--muted);margin-top:3px}\\n.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}\\n.chunk-list{margin-top:8px;max-height:340px;overflow-y:auto;border:1px solid var(--bd);border-radius:6px;background:var(--input-bg)}\\n.chunk{padding:10px 12px;border-bottom:1px solid var(--bd-soft);font-size:12px}\\n.chunk:last-child{border-bottom:0}\\n.chunk .ci{color:var(--muted);font-family:ui-monospace,monospace;font-size:11px}\\n.chunk .cp{color:var(--chunk-text);margin-top:4px;line-height:1.4}\\n.toast{position:fixed;bottom:20px;right:20px;background:var(--toast-bg);color:var(--toast-fg);padding:12px 18px;border-radius:8px;font-size:13px;opacity:0;transform:translateY(10px);transition:all .2s;z-index:100;max-width:360px;box-shadow:var(--shadow-md)}\\n.toast.on{opacity:1;transform:translateY(0)}\\n.toast.err{background:var(--err);color:#fff}\\n.toast.ok{background:var(--ok);color:#fff}\\nmark.match{background:#fef08a;color:#713f12;padding:0 3px;border-radius:3px;font-weight:500}\\n.match-cell{max-width:240px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px;color:var(--mono-fg)}\\n.spin{display:inline-block;width:14px;height:14px;border:2px solid var(--spinner-border);border-top-color:transparent;border-radius:50%;animation:spin 1s linear infinite}\\n@keyframes spin{to{transform:rotate(360deg)}}\\n.loading{padding:40px;text-align:center;color:var(--muted)}\\n</style>\\n</head>\\n<body>\\n<header>\\n  <h1>📑 Docs Admin</h1>\\n  <button class=\\"theme-toggle\\" id=\\"btn-theme\\" aria-label=\\"สลับโหมดมืด/สว่าง\\" title=\\"สลับโหมดมืด/สว่าง\\">\\n    <span id=\\"theme-icon\\">🌙</span>\\n  </button>\\n  <span class=\\"crumb\\" id=\\"crumb\\">Phuket Law Firm • LINE-fed document store</span>\\n</header>\\n<div class=\\"wrap\\">\\n  <div class=\\"stats\\" id=\\"stats\\">\\n    <div class=\\"stat\\"><div class=\\"label\\">Total</div><div class=\\"num\\" id=\\"stat-total\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Ready</div><div class=\\"num ok\\" id=\\"stat-ready\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Pending</div><div class=\\"num warn\\" id=\\"stat-pending\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Failed</div><div class=\\"num err\\" id=\\"stat-failed\\">—</div></div>\\n  </div>\\n  <div class=\\"toolbar\\">\\n    <input class=\\"search\\" id=\\"q\\" placeholder=\\"🔍 ค้นหาในเนื้อหา (semantic)\\">\\n    <select id=\\"f-status\\">\\n      <option value=\\"\\">สถานะทั้งหมด</option>\\n      <option value=\\"ready\\">ready</option>\\n      <option value=\\"pending\\">pending</option>\\n      <option value=\\"failed\\">failed</option>\\n      <option value=\\"processing\\">processing</option>\\n    </select>\\n    <button class=\\"btn ghost\\" id=\\"btn-refresh\\">↻ รีเฟรช</button>\\n  </div>\\n  <div class=\\"card\\">\\n    <table>\\n      <thead><tr>\\n        <th style=\\"width:130px\\">Doc No</th>\\n        <th>ชื่อไฟล์</th>\\n        <th style=\\"width:110px\\">ความเหมือน</th>\\n        <th style=\\"width:240px\\">Match</th>\\n        <th style=\\"width:110px\\">Category</th>\\n        <th style=\\"width:90px\\">Status</th>\\n        <th style=\\"width:60px;text-align:right\\">Chunks</th>\\n        <th style=\\"width:130px\\">อัปโหลด</th>\\n        <th class=\\"sticky-act\\" style=\\"width:200px\\"></th>\\n      </tr></thead>\\n      <tbody id=\\"tbody\\">\\n        <tr><td colspan=\\"9\\" class=\\"loading\\">กำลังโหลด…</td></tr>\\n      </tbody>\\n    </table>\\n  </div>\\n</div>\\n\\n<!-- View Modal -->\\n<div class=\\"modal\\" id=\\"m-view\\">\\n  <div class=\\"box\\">\\n    <div class=\\"hd\\"><h2 id=\\"v-title\\">รายละเอียดเอกสาร</h2><button class=\\"btn ghost sm\\" onclick=\\"closeModal('m-view')\\">✕</button></div>\\n    <div class=\\"bd\\" id=\\"v-body\\"></div>\\n    <div class=\\"ft\\"><button class=\\"btn ghost\\" onclick=\\"closeModal('m-view')\\">ปิด</button><button class=\\"btn ghost\\" id=\\"v-open-btn\\">เปิดไฟล์</button><button class=\\"btn\\" id=\\"v-edit-btn\\">แก้ไข</button></div>\\n  </div>\\n</div>\\n\\n<!-- Edit Modal -->\\n<div class=\\"modal\\" id=\\"m-edit\\">\\n  <div class=\\"box\\">\\n    <div class=\\"hd\\"><h2>แก้ไขเอกสาร</h2><button class=\\"btn ghost sm\\" onclick=\\"closeModal('m-edit')\\">✕</button></div>\\n    <div class=\\"bd\\">\\n      <input type=\\"hidden\\" id=\\"e-id\\">\\n      <div class=\\"grid2\\">\\n        <div class=\\"field\\"><label>Doc No</label><input id=\\"e-doc_no\\" disabled><div class=\\"hint\\">ไม่สามารถแก้ไขได้</div></div>\\n        <div class=\\"field\\"><label>Status</label>\\n          <select id=\\"e-status\\"><option value=\\"ready\\">ready</option><option value=\\"pending\\">pending</option><option value=\\"failed\\">failed</option><option value=\\"processing\\">processing</option></select>\\n        </div>\\n      </div>\\n      <div class=\\"field\\"><label>ชื่อไฟล์</label><input id=\\"e-file_name\\"></div>\\n      <div class=\\"grid2\\">\\n        <div class=\\"field\\"><label>Category</label><input id=\\"e-category\\" placeholder=\\"เช่น สัญญาเช่า, หนังสือมอบอำนาจ\\"></div>\\n        <div class=\\"field\\"><label>Source</label><input id=\\"e-source\\" placeholder=\\"เช่น LINE OA, web upload\\"></div>\\n      </div>\\n    </div>\\n    <div class=\\"ft\\">\\n      <button class=\\"btn ghost\\" onclick=\\"closeModal('m-edit')\\">ยกเลิก</button>\\n      <button class=\\"btn\\" id=\\"e-save\\">บันทึก</button>\\n    </div>\\n  </div>\\n</div>\\n\\n<div class=\\"toast\\" id=\\"toast\\"></div>\\n\\n<script>\\nconst BASE = location.origin;\\nlet allRows = [];\\nlet statsCache = null;\\nlet currentQuery = '';\\n\\n// =========================================================================\\n// Theme switcher (toggle dark/light, persist in localStorage, respect OS pref)\\n// =========================================================================\\nconst themeBtn = document.getElementById('btn-theme');\\nconst themeIcon = document.getElementById('theme-icon');\\nconst THEME_KEY = 'lawpoc-admin-theme';\\nconst themeMedia = window.matchMedia('(prefers-color-scheme: light)');\\n\\nfunction currentTheme(){ return document.documentElement.getAttribute('data-theme') || 'light'; }\\n\\nfunction syncThemeIcon(theme){\\n  // Show the icon of the CURRENT theme so the button reflects page state\\n  themeIcon.textContent = theme === 'dark' ? '🌙' : '☀️';\\n  themeBtn.setAttribute('aria-label', theme === 'dark' ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด');\\n  themeBtn.setAttribute('title', theme === 'dark' ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด');\\n}\\n\\nfunction applyTheme(theme, persist){\\n  document.documentElement.setAttribute('data-theme', theme);\\n  syncThemeIcon(theme);\\n  if(persist){ try{ localStorage.setItem(THEME_KEY, theme); }catch(e){} }\\n}\\n\\nthemeBtn.addEventListener('click', ()=>{\\n  applyTheme(currentTheme() === 'dark' ? 'light' : 'dark', true);\\n});\\n\\n// Sync icon to whatever the head bootstrap set\\nsyncThemeIcon(currentTheme());\\n\\n// If user hasn't explicitly chosen, follow OS theme changes live\\nthemeMedia.addEventListener('change', e=>{\\n  let saved = null;\\n  try{ saved = localStorage.getItem(THEME_KEY); }catch(err){}\\n  if(!saved) applyTheme(e.matches ? 'light' : 'dark', false);\\n});\\n// =========================================================================\\n\\nfunction toast(msg, kind=''){\\n  const t = document.getElementById('toast');\\n  t.textContent = msg;\\n  t.className = 'toast on ' + kind;\\n  setTimeout(()=>t.className='toast '+kind, 2200);\\n}\\n\\nasync function api(path, opts){\\n  const r = await fetch(BASE + path, opts);\\n  if (!r.ok) throw new Error('HTTP '+r.status);\\n  return r.json();\\n}\\n\\nfunction fmtDate(s){\\n  if(!s) return '—';\\n  const d = new Date(s);\\n  return d.toLocaleString('th-TH',{dateStyle:'short',timeStyle:'short'});\\n}\\n\\nfunction esc(s){return String(s??'').replace(/[&<>\\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\\"':'&quot;',\\"'\\":'&#39;'}[c]))}\\n\\nasync function loadStats(){\\n  try{\\n    const s = await api('/webhook/admin-stats');\\n    const v = (s && s.data) || s;\\n    if (typeof v === 'string') { try { v = JSON.parse(v); } catch {} }\\n    document.getElementById('stat-total').textContent = v.total??0;\\n    document.getElementById('stat-ready').textContent = v.ready??0;\\n    document.getElementById('stat-pending').textContent = v.pending??0;\\n    document.getElementById('stat-failed').textContent = v.failed??0;\\n  }catch(e){console.warn('stats',e)}\\n}\\n\\nasync function loadList(){\\n  const q = document.getElementById('q').value.trim();\\n  const st = document.getElementById('f-status').value;\\n  const params = new URLSearchParams();\\n  if(st) params.set('status', st);\\n  params.set('limit', '200');\\n  // Empty q → admin-list (full listing, no embedding). Non-empty q → admin-semantic-search.\\n  const endpoint = q ? '/webhook/admin-semantic-search' : '/webhook/admin-list';\\n  if (q) params.set('q', q);\\n  currentQuery = q;\\n  try{\\n    const data = await api(endpoint+'?'+params.toString());\\n    allRows = Array.isArray(data)?data:((data&&data.data)||[]);\\n    render(q ? 'semantic' : 'list');\\n  }catch(e){\\n    document.getElementById('tbody').innerHTML = \\\\`<tr><td colspan=\\"9\\" class=\\"empty\\"><h3>โหลดไม่สำเร็จ</h3>\\\\${esc(e.message)}</td></tr>\\\\`;\\n  }\\n}\\n\\nfunction render(mode){\\n  const tb = document.getElementById('tbody');\\n  if(!allRows.length){\\n    const msg = (mode === 'semantic') ? 'ไม่พบเอกสารที่คล้ายกัน' : 'ไม่มีเอกสาร';\\n    const hint = (mode === 'semantic') ? 'ลองค้นหาด้วยคำอื่น' : 'อัปโหลดผ่าน LINE OA เพื่อเริ่มต้น';\\n    tb.innerHTML = \\\\`<tr><td colspan=\\"9\\" class=\\"empty\\"><h3>\\\\${esc(msg)}</h3>\\\\${esc(hint)}</td></tr>\\\\`;\\n    return;\\n  }\\n  // Build match snippet: find query in top_chunk_content, show ~20\\n  // chars context on each side with <mark> wrapping the match.\\n  function buildMatch(r){\\n    if(mode !== 'semantic') return '<td style=\\"color:var(--muted)\\">—</td>';\\n    const q = (currentQuery||'').trim();\\n    const txt = r.top_chunk_content || '';\\n    if(!txt) return '<td style=\\"color:var(--muted)\\">—</td>';\\n    if(q){\\n      const safe = q.replace(/[.*+?^\\\\${}()|[\\\\]\\\\\\\\]/g, '\\\\\\\\$&');\\n      const re = new RegExp(safe, 'i');\\n      const m = re.exec(txt);\\n      if(m){\\n        const start = Math.max(0, m.index - 20);\\n        const end = Math.min(txt.length, m.index + q.length + 20);\\n        const before = (start > 0 ? '…' : '') + txt.slice(start, m.index);\\n        const matchTxt = txt.slice(m.index, m.index + q.length);\\n        const after = txt.slice(m.index + q.length, end) + (end < txt.length ? '…' : '');\\n        return \\\\`<td><div class=\\"match-cell\\" title=\\"\\\\${esc(txt.slice(0,200))}\\">\\\\${esc(before)}<mark class=\\"match\\">\\\\${esc(matchTxt)}</mark>\\\\${esc(after)}</div></td>\\\\`;\\n      }\\n    }\\n    if(r.keyword_sim && parseFloat(r.keyword_sim) > 0){\\n      return \\\\`<td style=\\"color:var(--muted);font-size:12px\\">semantic match · kw \\\\${(parseFloat(r.keyword_sim)).toFixed(1)}</td>\\\\`;\\n    }\\n    return '<td style=\\"color:var(--muted)\\">—</td>';\\n  }\\n  // Similarity: use vector_sim (cosine 0-1). RRF score is meaningless\\n  // for human display (always ~3% for top-ranked results).\\n  function buildSim(r){\\n    if(mode !== 'semantic') return '<td style=\\"color:var(--muted)\\">—</td>';\\n    const v = parseFloat(r.vector_sim != null ? r.vector_sim : (r.similarity || 0));\\n    const pct = Math.max(0, Math.min(100, Math.round(v * 100)));\\n    return \\\\`<td><div style=\\"display:flex;align-items:center\\"><div class=\\"similarity-bar\\"><span style=\\"width:\\\\${pct}%\\"></span></div><span style=\\"font-variant-numeric:tabular-nums;font-size:12px;color:var(--muted)\\">\\\\${pct}%</span></div></td>\\\\`;\\n  }\\n  tb.innerHTML = allRows.map(r=>{\\n    return \\\\`\\n    <tr>\\n      <td class=\\"mono\\">\\\\${esc(r.doc_no||'—')}</td>\\n      <td><div class=\\"name\\">\\\\${esc(r.file_name||'')}<small>\\\\${esc(r.file_type||'')}\\\\${r.size_bytes?' • '+Math.round(r.size_bytes/1024)+' KB':''}</small></div></td>\\n      \\\\${buildSim(r)}\\n      \\\\${buildMatch(r)}\\n      <td>\\\\${esc(r.category||'—')}</td>\\n      <td><span class=\\"badge \\\\${esc(r.status||'pending')}\\">\\\\${esc(r.status||'pending')}</span></td>\\n      <td style=\\"text-align:right;font-variant-numeric:tabular-nums\\">\\\\${r.chunk_count??0}</td>\\n      <td class=\\"mono\\">\\\\${fmtDate(r.uploaded_at)}</td>\\n      <td><div class=\\"row-actions\\">\\n        <button class=\\"btn ghost sm\\" onclick=\\"view('\\\\${esc(r.id)}')\\">ดู</button>\\n        <button class=\\"btn sm\\" onclick=\\"edit('\\\\${esc(r.id)}')\\">แก้ไข</button>\\n        <button class=\\"btn danger sm\\" onclick=\\"del('\\\\${esc(r.id)}','\\\\${esc(r.file_name||'')}')\\">ลบ</button>\\n      </div></td>\\n    </tr>\\n  \\\\`}).join('');\\n}\\n\\nasync function view(id){\\n  try{\\n    const data = await api('/webhook/admin-get?id='+encodeURIComponent(id));\\n    const r = (Array.isArray(data)?data[0]:((data&&data.data)||data));\\n    if(!r||!r.id){toast('ไม่พบเอกสาร','err');return}\\n    const chunks = r.chunks||[];\\n    const fileUrl = '/webhook/admin-file?id='+encodeURIComponent(id);\\n    document.getElementById('v-title').textContent = r.file_name||'(ไม่มีชื่อ)';\\n    document.getElementById('v-body').innerHTML = \\\\`\\n      <div class=\\"preview-grid\\">\\n        <section>\\n          <div class=\\"preview-bar\\">\\n            <div><div class=\\"hint\\">ไฟล์จาก Postgres</div><strong>\\\\${esc(r.file_name||'document')}</strong></div>\\n            <a href=\\"\\\\${esc(fileUrl)}\\" target=\\"_blank\\" class=\\"btn ghost sm\\" style=\\"text-decoration:none\\">เปิดแท็บใหม่</a>\\n          </div>\\n          <div class=\\"file-preview\\"><iframe src=\\"\\\\${esc(fileUrl) + '#toolbar=0&navpanes=0&scrollbar=0&view=FitH'}\\" title=\\"\\\\${esc(r.file_name||'document')}\\"></iframe></div>\\n        </section>\\n        <section>\\n          <div class=\\"grid2 meta-grid\\">\\n            <div><div class=\\"hint\\">Doc No</div><div class=\\"mono\\" style=\\"font-weight:500\\">\\\\${esc(r.doc_no||'—')}</div></div>\\n            <div><div class=\\"hint\\">Status</div><span class=\\"badge \\\\${esc(r.status)}\\">\\\\${esc(r.status)}</span></div>\\n            <div><div class=\\"hint\\">Category</div>\\\\${esc(r.category||'—')}</div>\\n            <div><div class=\\"hint\\">Source</div>\\\\${esc(r.source||'—')}</div>\\n            <div><div class=\\"hint\\">File Type</div>\\\\${esc(r.file_type||'—')}</div>\\n            <div><div class=\\"hint\\">Size</div>\\\\${r.size_bytes?(Math.round(r.size_bytes/1024)+' KB'):'—'}</div>\\n            <div><div class=\\"hint\\">Line User</div><div class=\\"mono\\" style=\\"font-size:11px\\">\\\\${esc(r.line_user_id||'—')}</div></div>\\n            <div><div class=\\"hint\\">Line Group</div><div class=\\"mono\\" style=\\"font-size:11px\\">\\\\${esc(r.line_group_id||'—')}</div></div>\\n            <div><div class=\\"hint\\">อัปโหลด</div>\\\\${fmtDate(r.uploaded_at)}</div>\\n            <div><div class=\\"hint\\">อัปเดต</div>\\\\${fmtDate(r.updated_at)}</div>\\n          </div>\\n          <div style=\\"margin-top:18px\\">\\n            <div class=\\"hint\\" style=\\"margin-bottom:6px\\">Chunks (\\\\${chunks.length})</div>\\n            <div class=\\"chunk-list\\">\\\\${chunks.length?chunks.map(c=>\\\\`<div class=\\"chunk\\"><div class=\\"ci\\">#\\\\${c.chunk_index} • \\\\${c.token_count||0} tokens</div><div class=\\"cp\\">\\\\${esc(c.preview||'')}</div></div>\\\\`).join(''):'<div class=\\"chunk\\" style=\\"color:var(--muted-2)\\">ยังไม่มี chunks</div>'}</div>\\n          </div>\\n        </section>\\n      </div>\\n    \\\\`;\\n    document.getElementById('v-edit-btn').onclick = ()=>{closeModal('m-view');edit(id)};\\n    document.getElementById('v-open-btn').onclick = ()=>window.open(fileUrl, '_blank');\\n    document.getElementById('m-view').classList.add('on');\\n  }catch(e){toast('โหลดรายละเอียดไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nfunction edit(id){\\n  const r = allRows.find(x=>x.id===id);\\n  if(!r){toast('ไม่พบเอกสาร','err');return}\\n  document.getElementById('e-id').value = id;\\n  document.getElementById('e-doc_no').value = r.doc_no||'';\\n  document.getElementById('e-file_name').value = r.file_name||'';\\n  document.getElementById('e-category').value = r.category||'';\\n  document.getElementById('e-source').value = r.source||'';\\n  document.getElementById('e-status').value = r.status||'pending';\\n  document.getElementById('m-edit').classList.add('on');\\n}\\n\\nasync function saveEdit(){\\n  const id = document.getElementById('e-id').value;\\n  const body = {\\n    id,\\n    file_name: document.getElementById('e-file_name').value.trim(),\\n    category: document.getElementById('e-category').value.trim(),\\n    source: document.getElementById('e-source').value.trim(),\\n    status: document.getElementById('e-status').value\\n  };\\n  if(!body.file_name){toast('กรุณากรอกชื่อไฟล์','err');return}\\n  try{\\n    await api('/webhook/admin-update',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});\\n    toast('บันทึกเรียบร้อย','ok');\\n    closeModal('m-edit');\\n    loadList();loadStats();\\n  }catch(e){toast('บันทึกไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nasync function del(id, name){\\n  if(!confirm('ลบ \\"'+name+'\\"?\\\\\\\\n\\\\\\\\n⚠️ chunks ทั้งหมดจะถูกลบด้วย (CASCADE)')) return;\\n  try{\\n    await api('/webhook/admin-delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})});\\n    toast('ลบเรียบร้อย','ok');\\n    loadList();loadStats();\\n  }catch(e){toast('ลบไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nfunction closeModal(id){document.getElementById(id).classList.remove('on')}\\n\\ndocument.getElementById('btn-refresh').onclick = ()=>{loadList();loadStats()};\\ndocument.getElementById('q').oninput = debounce(loadList, 300);\\ndocument.getElementById('f-status').onchange = loadList;\\ndocument.getElementById('e-save').onclick = saveEdit;\\n\\nfunction debounce(fn, ms){let t;return(...a)=>{clearTimeout(t);t=setTimeout(()=>fn(...a),ms)}}\\n\\n// Read URL query params (?q=, ?status=) and pre-fill inputs\\nconst urlParams = new URLSearchParams(window.location.search);\\nconst urlQ = urlParams.get('q');\\nconst urlStatus = urlParams.get('status');\\nif (urlQ) document.getElementById('q').value = urlQ;\\nif (urlStatus) document.getElementById('f-status').value = urlStatus;\\n\\nloadList();\\nloadStats();\\nsetInterval(()=>{loadStats()}, 60000);\\n</script>\\n</body>\\n</html>`;\\nreturn [{json: {html: html}}];\\n"},"id":"code-build-html","name":"Build HTML","type":"n8n-nodes-base.code","typeVersion":2,"position":[176,0]},{"parameters":{"respondWith":"text","responseBody":"={{ $('Build HTML').first().json.html }}","options":{"responseHeaders":{"entries":[{"name":"Content-Type","value":"text/html; charset=utf-8"}]}}},"id":"resp-ui","name":"Respond UI","type":"n8n-nodes-base.respondToWebhook","typeVersion":1,"position":[400,0]},{"parameters":{"path":"admin-list","responseMode":"lastNode","options":{}},"id":"wh-admin-list","name":"Admin List","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,224],"webhookId":"admin-list-wh"},{"parameters":{"path":"admin-get","responseMode":"lastNode","options":{}},"id":"wh-admin-get","name":"Admin Get","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,448],"webhookId":"admin-get-wh"},{"parameters":{"httpMethod":"POST","path":"admin-update","responseMode":"lastNode","options":{}},"id":"wh-admin-update","name":"Admin Update","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1120],"webhookId":"admin-update-wh"},{"parameters":{"httpMethod":"POST","path":"admin-delete","responseMode":"lastNode","options":{}},"id":"wh-admin-delete","name":"Admin Delete","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1344],"webhookId":"admin-delete-wh"},{"parameters":{"path":"admin-stats","responseMode":"lastNode","options":{}},"id":"wh-admin-stats","name":"Admin Stats","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1568],"webhookId":"admin-stats-wh"},{"parameters":{"operation":"executeQuery","query":"SELECT * FROM (\\n  SELECT id, doc_no, file_name, file_type, category, status, source, size_bytes, chunk_count, line_user_id, uploaded_at, updated_at, error_message\\n  FROM contracts c\\n  WHERE (($1::text IS NULL OR $1 = '')\\n      OR LOWER(COALESCE(file_name,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(source,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(doc_no,'')) LIKE '%' || LOWER($1) || '%')\\n    AND ($2::text IS NULL OR $2 = '' OR status = $2)\\n  ORDER BY uploaded_at DESC\\n  LIMIT $3::int OFFSET $4::int\\n) real\\nUNION ALL\\nSELECT NULL::uuid, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL\\nWHERE NOT EXISTS (SELECT 1 FROM contracts)\\nORDER BY 1 NULLS LAST","options":{"queryReplacement":"={{ [($json.query && $json.query.q) || null, ($json.query && $json.query.status) || null, parseInt(($json.query && $json.query.limit) || 200, 10), parseInt(($json.query && $json.query.offset) || 0, 10)] }}"}},"id":"pg-admin-list","name":"PG: Admin List","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,224],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT c.id, c.doc_no, c.file_name, c.file_type, c.category, c.status, c.source, c.size_bytes, c.chunk_count, c.line_user_id, c.line_group_id, c.line_message_id, c.uploaded_at, c.updated_at, (SELECT json_agg(json_build_object('id', ch.id, 'chunk_index', ch.chunk_index, 'preview', LEFT(ch.content, 200), 'token_count', ch.token_count) ORDER BY ch.chunk_index) FROM contract_chunks ch WHERE ch.contract_id = c.id) AS chunks FROM contracts c WHERE c.id = $1::uuid","options":{"queryReplacement":"={{ [$json.query.id] }}"}},"id":"pg-admin-get","name":"PG: Admin Get","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,448],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"UPDATE contracts SET file_name = COALESCE(NULLIF($2, ''), file_name), category = NULLIF($3, ''), source = NULLIF($4, ''), status = COALESCE(NULLIF($5, ''), status), updated_at = now() WHERE id = $1::uuid RETURNING id, doc_no, file_name, file_type, category, status, source, size_bytes, chunk_count, line_user_id, uploaded_at, updated_at","options":{"queryReplacement":"={{ [$json.body.id, $json.body.file_name, $json.body.category, $json.body.source, $json.body.status] }}"}},"id":"pg-admin-update","name":"PG: Admin Update","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1120],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"DELETE FROM contracts\\nWHERE id = $1::uuid\\nRETURNING id, file_name, storage_bucket, storage_path,\\n  CASE \\n    WHEN storage_path LIKE 'http%' AND storage_path LIKE '%/' || storage_bucket || '/%'\\n    THEN split_part(storage_path, '/' || storage_bucket || '/', 2)\\n    ELSE NULL\\n  END AS minio_key;","options":{"queryReplacement":"={{ [$json.body.id] }}"}},"id":"pg-admin-delete","name":"PG: Admin Delete","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1344],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed","options":{}},"id":"pg-admin-stats","name":"PG: Admin Stats","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1568],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Wrap list results - always output 1 item even if empty\\nlet items = $input.all().map(i => i.json);\\n// Filter out dummy rows (where id IS NULL)\\nitems = items.filter(it => it && it.id != null);\\nreturn [{json: {ok: true, action: 'list', count: items.length, data: items}}];"},"id":"wrap-list","name":"Wrap List","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,224]},{"parameters":{"jsCode":"// Wrap get result - returns null if no row found\\nconst items = $input.all().map(i => i.json).filter(it => it && it.id != null);\\nreturn [{json: {ok: items.length > 0, action: 'get', data: items[0] || null}}];"},"id":"wrap-get","name":"Wrap Get","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,448]},{"parameters":{"jsCode":"// Wrap update result\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'update', data: items[0] || null}}];"},"id":"wrap-update","name":"Wrap Update","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1120]},{"parameters":{"jsCode":"// Wrap delete result\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'delete', data: items[0] || null}}];"},"id":"wrap-delete","name":"Wrap Delete","type":"n8n-nodes-base.code","typeVersion":2,"position":[848,1344]},{"parameters":{"jsCode":"// Wrap stats result - always output 1 item\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'stats', data: items[0] || {total: 0, ready: 0, pending: 0, failed: 0}}}];"},"id":"wrap-stats","name":"Wrap Stats","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1568]},{"parameters":{"jsCode":"// minio_key is computed in SQL (short string, ~26 chars, not ref-compressed).\\n// Just copy it to _minio_key for MinIO Delete.\\nconst data = $input.first().json;\\nconst minioKey = data.minio_key;\\nreturn [{\\n  json: {\\n    ...data,\\n    _minio_bucket: data.storage_bucket,\\n    _minio_key: minioKey,\\n    _skip_minio_delete: !minioKey\\n  }\\n}];"},"id":"extract-minio-key-001","name":"Extract MinIO Key","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1344],"alwaysOutputData":true},{"parameters":{"operation":"delete","bucketName":"epsx-contracts","fileKey":"={{ $json._minio_key }}","options":{}},"id":"minio-delete-001","name":"MinIO Delete","type":"n8n-nodes-base.s3","typeVersion":1,"position":[624,1344],"credentials":{"s3":{"id":"f719a9dd-b576-4cd5-bde6-13fb6344c447","name":"MinIO Contracts"}}},{"parameters":{"path":"admin-file","responseMode":"responseNode","options":{}},"id":"wh-admin-file","name":"Admin File","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,672],"webhookId":"admin-file-webhook"},{"parameters":{"operation":"executeQuery","query":"SELECT id, file_name, file_type,\\n  COALESCE(\\n    file_mime,\\n    CASE\\n      WHEN lower(COALESCE(file_type, '')) = 'pdf' THEN 'application/pdf'\\n      WHEN lower(COALESCE(file_type, '')) = 'png' THEN 'image/png'\\n      WHEN lower(COALESCE(file_type, '')) IN ('jpg', 'jpeg') THEN 'image/jpeg'\\n      WHEN lower(COALESCE(file_type, '')) = 'txt' THEN 'text/plain; charset=utf-8'\\n      ELSE 'application/octet-stream'\\n    END\\n  ) AS file_mime,\\n  encode(file_data, 'base64') AS file_data_b64,\\n  octet_length(file_data) AS file_size\\nFROM contracts\\nWHERE id = $1::uuid","options":{"queryReplacement":"={{ [$json.query.id] }}"}},"id":"pg-admin-file","name":"PG: Admin File","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,672],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Build binary file response from contracts.file_data (Postgres bytea).\\nconst item = $input.first();\\nconst json = item?.json || {};\\nlet mime = json.file_mime || (json.file_type === 'pdf' ? 'application/pdf' : 'application/octet-stream');\\nlet fileName = json.file_name || 'document';\\nlet fileDataB64 = json.file_data_b64 || '';\\n\\nif (!fileDataB64) {\\n  const message = 'No file_data stored in Postgres for this document. Re-upload or backfill contracts.file_data.';\\n  fileDataB64 = Buffer.from(message, 'utf8').toString('base64');\\n  mime = 'text/plain; charset=utf-8';\\n  fileName = 'missing-file.txt';\\n}\\n\\nconst fileSize = Buffer.from(fileDataB64, 'base64').length;\\nreturn [{\\n  json: { file_name: fileName, file_mime: mime, file_size: fileSize },\\n  binary: {\\n    data: {\\n      data: fileDataB64,\\n      mimeType: mime,\\n      fileName,\\n      fileSize,\\n    }\\n  }\\n}];\\n"},"id":"wrap-file","name":"Wrap File","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,672]},{"parameters":{"respondWith":"binary","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Disposition","value":"={{ 'inline; filename=\\"' + (($json.file_name || 'document').replace(/\\"/g, '')) + '\\"' }}"},{"name":"Content-Type","value":"={{ $json.file_mime || 'application/octet-stream' }}"},{"name":"Cache-Control","value":"no-cache"}]}}},"id":"resp-file","name":"Respond File","type":"n8n-nodes-base.respondToWebhook","typeVersion":1.1,"position":[624,672]},{"parameters":{"path":"admin-semantic-search","responseMode":"lastNode","options":{}},"id":"wh-admin-semantic","name":"Admin Semantic Search","type":"n8n-nodes-base.webhook","position":[-48,896],"typeVersion":1,"webhookId":"b55eade8-a4fa-4f89-b72c-199525e05146"},{"parameters":{"jsCode":"const wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst query = (q.q || body.q || \\"\\").toString().trim();\\nconst limit = parseInt(q.limit || body.limit || 20, 10) || 20;\\nreturn [{json: {query, _query: query, _limit: limit}}];"},"id":"parse-semantic","name":"Parse Semantic","type":"n8n-nodes-base.code","position":[176,896],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || \\"http://127.0.0.1:11434\\") }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.query) }} }","options":{"timeout":30000}},"id":"embed-semantic","name":"Embed Semantic","type":"n8n-nodes-base.httpRequest","position":[400,896],"typeVersion":4.2},{"parameters":{"operation":"executeQuery","query":"WITH q AS (SELECT $1::vector AS qvec, $3::text AS qtxt),\\nv AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         1 - (ch.embedding <=> q.qvec) AS v_sim,\\n         ROW_NUMBER() OVER (ORDER BY ch.embedding <=> q.qvec) AS v_rank\\n  FROM contract_chunks ch, q\\n  WHERE ch.embedding IS NOT NULL\\n  ORDER BY ch.embedding <=> q.qvec\\n  LIMIT $2::int * 4\\n),\\nt AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 1.0 ELSE 0 END)::float\\n         + (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float\\n           / greatest(length(q.qtxt), 1)::float * 0.1 AS t_sim,\\n         ROW_NUMBER() OVER (ORDER BY\\n           (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n           (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float DESC,\\n           ch.chunk_index ASC) AS t_rank\\n  FROM contract_chunks ch, q\\n  WHERE length(q.qtxt) > 0\\n  ORDER BY (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n           (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float DESC\\n  LIMIT $2::int * 4\\n),\\nfused AS (\\n  SELECT COALESCE(v.contract_id, t.contract_id) AS contract_id,\\n         COALESCE(v.chunk_index, t.chunk_index) AS chunk_index,\\n         COALESCE(v.content, t.content) AS content,\\n         COALESCE(1.0/(60+v.v_rank), 0) + COALESCE(1.0/(60+t.t_rank), 0) AS rrf_score,\\n         COALESCE(v.v_sim, 0) AS v_sim,\\n         COALESCE(t.t_sim, 0) AS t_sim\\n  FROM v FULL OUTER JOIN t ON v.contract_id = t.contract_id AND v.chunk_index = t.chunk_index\\n  WHERE COALESCE(v.contract_id, t.contract_id) IS NOT NULL\\n),\\ncontract_ranked AS (\\n  SELECT *, ROW_NUMBER() OVER (PARTITION BY contract_id ORDER BY rrf_score DESC) AS in_contract_rank\\n  FROM fused\\n),\\nbest_per_contract AS (\\n  SELECT contract_id, chunk_index, content, rrf_score, v_sim, t_sim\\n  FROM contract_ranked\\n  WHERE in_contract_rank = 1\\n  ORDER BY rrf_score DESC\\n  LIMIT $2::int\\n),\\njoined AS (\\n  SELECT c.id, c.doc_no, c.file_name, c.file_type, c.category, c.status, c.source,\\n         c.size_bytes, c.chunk_count, c.line_user_id, c.uploaded_at, c.updated_at, c.error_message,\\n         b.chunk_index AS top_chunk_index, b.content AS top_chunk_content,\\n         b.rrf_score AS similarity, b.v_sim AS vector_sim, b.t_sim AS keyword_sim\\n  FROM best_per_contract b\\n  JOIN contracts c ON c.id = b.contract_id\\n)\\nSELECT COALESCE(\\n  (SELECT json_build_object(\\n    'ok', true,\\n    'mode', 'semantic',\\n    'query', $3::text,\\n    'count', (SELECT COUNT(*)::int FROM joined),\\n    'data', COALESCE((SELECT json_agg(row_to_json(j) ORDER BY similarity DESC) FROM joined j), '[]'::json)\\n  )::text),\\n  json_build_object('ok', true, 'mode', 'semantic', 'query', $3::text, 'count', 0, 'data', '[]'::json)::text\\n) AS result_json","options":{"queryReplacement":"={{ [($json.embeddings && $json.embeddings[0]) ? \\"[\\" + $json.embeddings[0].map(Number).join(\\",\\") + \\"]\\" : \\"[]\\", parseInt($(\\"Parse Semantic\\").first().json._limit || 20, 10), $(\\"Parse Semantic\\").first().json._query || \\"\\"] }}"}},"id":"pg-admin-semantic","name":"PG: Admin Semantic","type":"n8n-nodes-base.postgres","position":[624,896],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"const row = $input.first().json;\\nlet result;\\ntry {\\n  result = JSON.parse(row.result_json || '{\\"ok\\":true,\\"count\\":0,\\"data\\":[]}');\\n} catch(e) {\\n  return [{json: {ok: false, error: \\"parse_failed\\", message: e.message, data: []}}];\\n}\\nreturn [{json: result}];"},"id":"wrap-semantic","name":"Wrap Semantic","type":"n8n-nodes-base.code","position":[848,896],"typeVersion":2},{"parameters":{"respondWith":"json","responseBody":"={{ $json }}","options":{}},"id":"resp-semantic","name":"Respond Semantic","type":"n8n-nodes-base.respondToWebhook","position":[1072,896],"typeVersion":1}]	{"Admin Get":{"main":[[{"node":"PG: Admin Get","type":"main","index":0}]]},"Admin List":{"main":[[{"node":"PG: Admin List","type":"main","index":0}]]},"Build HTML":{"main":[[{"node":"Respond UI","type":"main","index":0}]]},"Admin Stats":{"main":[[{"node":"PG: Admin Stats","type":"main","index":0}]]},"Admin Delete":{"main":[[{"node":"PG: Admin Delete","type":"main","index":0}]]},"Admin Update":{"main":[[{"node":"PG: Admin Update","type":"main","index":0}]]},"PG: Admin Get":{"main":[[{"node":"Wrap Get","type":"main","index":0}]]},"PG: Admin List":{"main":[[{"node":"Wrap List","type":"main","index":0}]]},"PG: Admin Stats":{"main":[[{"node":"Wrap Stats","type":"main","index":0}]]},"Admin UI Webhook":{"main":[[{"node":"Build HTML","type":"main","index":0}]]},"PG: Admin Delete":{"main":[[{"node":"Extract MinIO Key","type":"main","index":0}]]},"PG: Admin Update":{"main":[[{"node":"Wrap Update","type":"main","index":0}]]},"Extract MinIO Key":{"main":[[{"node":"MinIO Delete","type":"main","index":0}]]},"MinIO Delete":{"main":[[{"node":"Wrap Delete","type":"main","index":0}]]},"Admin File":{"main":[[{"node":"PG: Admin File","type":"main","index":0}]]},"PG: Admin File":{"main":[[{"node":"Wrap File","type":"main","index":0}]]},"Wrap File":{"main":[[{"node":"Respond File","type":"main","index":0}]]},"Admin Semantic Search":{"main":[[{"node":"Parse Semantic","type":"main","index":0}]]},"Parse Semantic":{"main":[[{"node":"Embed Semantic","type":"main","index":0}]]},"Embed Semantic":{"main":[[{"node":"PG: Admin Semantic","type":"main","index":0}]]},"PG: Admin Semantic":{"main":[[{"node":"Wrap Semantic","type":"main","index":0}]]},"Wrap Semantic":{"main":[[{"node":"Respond Semantic","type":"main","index":0}]]}}	2026-06-18 11:19:01.736+07	2026-06-24 02:14:33.618+07	{"executionOrder":"v1","binaryMode":"separate"}	\N	{}	f8af4454-0091-4412-bf10-19ddfd9c25d2	8	AdM1nFlow12345678CD0cHub2	\N	\N	f	33		4936517b-f48b-4073-9755-0467045e870c	[]	\N
\.


--
-- Data for Name: workflow_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_history ("versionId", "workflowId", authors, "createdAt", "updatedAt", nodes, connections, name, autosaved, description, "nodeGroups") FROM stdin;
342bf076-f7ce-4690-884f-889a033db7d9	wb0BxLBPY80gSVpK	import	2026-06-24 23:45:58.357+07	2026-06-24 23:45:58.357+07	[{"parameters":{"httpMethod":"POST","path":"hr-line-agent","responseMode":"responseNode","options":{}},"id":"wh-line-bot","name":"LINE Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-250,150],"webhookId":"hr-line-agent-webhook"},{"parameters":{"respondWith":"json","responseBody":"{}","options":{"responseHeaders":{"entries":[{"name":"Content-Type","value":"application/json"}]}}},"id":"resp-200","name":"Respond 200 OK","type":"n8n-nodes-base.respondToWebhook","typeVersion":1,"position":[-50,150]},{"parameters":{"jsCode":"const body = items[0].json.body;\\nif (!body || !body.events || body.events.length === 0) {\\n  return [];\\n}\\n\\nconst event = body.events[0];\\nconst userId = event.source.userId;\\nconst eventType = event.type;\\nconst replyToken = event.replyToken;\\n\\nlet messageText = '';\\nlet postbackData = '';\\nlet postbackParams = {};\\n\\nif (eventType === 'message' && event.message.type === 'text') {\\n  messageText = event.message.text.trim();\\n} else if (eventType === 'postback') {\\n  postbackData = event.postback.data;\\n  postbackParams = event.postback.params || {};\\n}\\n\\nreturn [{\\n  json: {\\n    userId,\\n    eventType,\\n    replyToken,\\n    messageText,\\n    postbackData,\\n    postbackParams\\n  }\\n}];"},"id":"code-parse","name":"Parse LINE Event","type":"n8n-nodes-base.code","typeVersion":2,"position":[150,150]},{"parameters":{"operation":"executeQuery","query":"SELECT \\n  e.id as employee_id, \\n  e.employee_code, \\n  e.name, \\n  e.position, \\n  e.department, \\n  e.role, \\n  e.job_description,\\n  e.total_sick_leave, e.used_sick_leave,\\n  e.total_annual_leave, e.used_annual_leave,\\n  e.total_personal_leave, e.used_personal_leave,\\n  s.current_state,\\n  s.temp_data\\nFROM (SELECT $1::text as line_id) input\\nLEFT JOIN employees e ON e.line_user_id = input.line_id\\nLEFT JOIN user_sessions s ON s.line_user_id = input.line_id;","options":{"queryReplacement":"={{ [$('Parse LINE Event').first().json.userId] }}"}},"id":"pg-get-session","name":"PG: Get Employee & Session","type":"n8n-nodes-base.postgres","typeVersion":2,"position":[350,150],"credentials":{"postgres":{"id":"vwf7u64OuSi5ejWs","name":"Postgres HR - localhost:5432"}}},{"parameters":{"jsCode":"const input = $('PG: Get Employee & Session').first().json;\\nconst parsedEvent = $('Parse LINE Event').first().json;\\nconst userId = parsedEvent.userId;\\nconst replyToken = parsedEvent.replyToken;\\nconst messageText = parsedEvent.messageText ? parsedEvent.messageText.trim() : '';\\nconst cleanText = messageText.toLowerCase();\\n\\n// Get Ollama NLP output\\nconst ollamaRes = $('Ollama: Parse Intent').first().json.response;\\nlet nlp = { intent: 'general_chat', leave_type: null, start_date: null, end_date: null, days: null, reason: null, employee_code: null, check_date: null };\\ntry {\\n  let cleanRes = ollamaRes.trim();\\n  const jsonMatch = cleanRes.match(/\\\\{[\\\\s\\\\S]*\\\\}/);\\n  if (jsonMatch) {\\n    nlp = JSON.parse(jsonMatch[0]);\\n  } else {\\n    nlp = JSON.parse(cleanRes);\\n  }\\n} catch (e) {\\n  console.error('Failed to parse Ollama JSON:', e);\\n}\\n\\nlet responseType = 'direct_reply';\\nlet replyMessages = [];\\nlet sql = '';\\nlet params = [];\\n\\n// Helper functions for date parsing and days calculation\\nfunction parseDate(text, baseDate = null) {\\n  if (!text) return null;\\n  const clean = text.trim().toLowerCase().replace(/\\\\s+/g, ' ');\\n  const today = new Date(new Date().getTime() + (7 * 60 * 60 * 1000));\\n  const currentYear = today.getFullYear();\\n\\n  // 1. Relative words\\n  if (clean === 'วันนี้') {\\n    return today.toISOString().split('T')[0];\\n  }\\n  if (clean === 'พรุ่งนี้') {\\n    const d = new Date(today.getTime() + (24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'เมื่อวาน' || clean === 'เมื่อวานนี้') {\\n    const d = new Date(today.getTime() - (24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'วานซืน' || clean === 'เมื่อวานซืน') {\\n    const d = new Date(today.getTime() - (2 * 24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'มะรืน' || clean === 'มะรืนนี้') {\\n    const d = new Date(today.getTime() + (2 * 24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n\\n  // 2. Duration match: e.g., \\"3 วัน\\", \\"5 วัน\\", \\"3 days\\"\\n  if (baseDate) {\\n    const durMatch = clean.match(/^(\\\\d+)\\\\s*(วัน|day|days)$/);\\n    if (durMatch) {\\n      const numDays = parseInt(durMatch[1]);\\n      if (numDays > 0) {\\n        const start = new Date(baseDate);\\n        const end = new Date(start.getTime() + ((numDays - 1) * 24 * 60 * 60 * 1000));\\n        return end.toISOString().split('T')[0];\\n      }\\n    }\\n  }\\n\\n  // 3. Parse Thai months\\n  const thaiMonthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];\\n  const thaiMonthsFull = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];\\n\\n  let parsedText = clean;\\n  let monthIndex = -1;\\n  for (let i = 0; i < 12; i++) {\\n    if (clean.includes(thaiMonthsFull[i])) {\\n      monthIndex = i + 1;\\n      parsedText = clean.replace(thaiMonthsFull[i], ' ' + monthIndex + ' ');\\n      break;\\n    }\\n  }\\n  if (monthIndex === -1) {\\n    for (let i = 0; i < 12; i++) {\\n      const term = thaiMonthsShort[i].replace('.', '\\\\\\\\.?');\\n      const regex = new RegExp(term, 'g');\\n      if (regex.test(clean)) {\\n        monthIndex = i + 1;\\n        parsedText = clean.replace(regex, ' ' + monthIndex + ' ');\\n        break;\\n      }\\n    }\\n  }\\n\\n  // Match formats:\\n  // - \\"YYYY-MM-DD\\"\\n  const dateRegexYMD = /^(\\\\d{4})[-/](\\\\d{1,2})[-/](\\\\d{1,2})$/;\\n  const matchYMD = parsedText.match(dateRegexYMD);\\n  if (matchYMD) {\\n    let y = parseInt(matchYMD[1]);\\n    let m = parseInt(matchYMD[2]) - 1;\\n    let d = parseInt(matchYMD[3]);\\n    if (y >= 2400) y -= 543;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // - \\"DD/MM/YYYY\\"\\n  const dateRegexDMY = /^(\\\\d{1,2})[-/ ](\\\\d{1,2})[-/ ](\\\\d{4})$/;\\n  const matchDMY = parsedText.match(dateRegexDMY);\\n  if (matchDMY) {\\n    let d = parseInt(matchDMY[1]);\\n    let m = parseInt(matchDMY[2]) - 1;\\n    let y = parseInt(matchDMY[3]);\\n    if (y >= 2400) y -= 543;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // - \\"DD/MM\\" (e.g. 20/02 or 20 08)\\n  const dateRegexDM = /^(\\\\d{1,2})[-/ ](\\\\d{1,2})$/;\\n  const matchDM = parsedText.match(dateRegexDM);\\n  if (matchDM) {\\n    let d = parseInt(matchDM[1]);\\n    let m = parseInt(matchDM[2]) - 1;\\n    let y = currentYear;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // Digits fallback extraction (e.g. \\"วันที่ 20 เดือน 8\\")\\n  const digits = parsedText.match(/\\\\d+/g);\\n  if (digits) {\\n    if (digits.length === 3) {\\n      let d = parseInt(digits[0]);\\n      let m = parseInt(digits[1]) - 1;\\n      let y = parseInt(digits[2]);\\n      if (y < 100) y += 2000;\\n      if (y >= 2400) y -= 543;\\n      const dateObj = new Date(y, m, d);\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    } else if (digits.length === 2) {\\n      let d = parseInt(digits[0]);\\n      let m = parseInt(digits[1]) - 1;\\n      let y = currentYear;\\n      if (monthIndex !== -1) {\\n        m = monthIndex - 1;\\n      }\\n      const dateObj = new Date(y, m, d);\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    } else if (digits.length === 1 && baseDate) {\\n      let d = parseInt(digits[0]);\\n      const base = new Date(baseDate);\\n      const dateObj = new Date(base.getFullYear(), base.getMonth(), d);\\n      if (dateObj < base) {\\n        dateObj.setMonth(dateObj.getMonth() + 1);\\n      }\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    }\\n  }\\n\\n  const parsed = Date.parse(clean);\\n  if (!isNaN(parsed)) {\\n    return formatDate(new Date(parsed));\\n  }\\n\\n  return null;\\n}\\n\\nfunction formatDate(date) {\\n  const y = date.getFullYear();\\n  const m = String(date.getMonth() + 1).padStart(2, '0');\\n  const d = String(date.getDate()).padStart(2, '0');\\n  return `${y}-${m}-${d}`;\\n}\\n\\nfunction calculateDays(start, end) {\\n  const s = new Date(start);\\n  const e = new Date(end);\\n  const diffTime = e.getTime() - s.getTime();\\n  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1;\\n  return diffDays > 0 ? diffDays : 1;\\n}\\n\\nfunction getLeaveTypeThai(type) {\\n  if (type === 'sick') return '🤒 ลาป่วย';\\n  if (type === 'annual') return '✈️ ลาพักร้อน';\\n  if (type === 'personal') return 'ลากิจ';\\n  return type;\\n}\\n\\nfunction getRemainingDays(type) {\\n  if (type === 'sick') return input.total_sick_leave - input.used_sick_leave;\\n  if (type === 'annual') return input.total_annual_leave - input.used_annual_leave;\\n  if (type === 'personal') return input.total_personal_leave - input.used_personal_leave;\\n  return 0;\\n}\\n\\n// 1. Handlers for unregistered users\\nif (!input.employee_id && !messageText.startsWith('/switch ')) {\\n  responseType = 'direct_reply';\\n  replyMessages = [{\\n    \\"type\\": \\"text\\",\\n    \\"text\\": \\"⚠️ คุณยังไม่ได้ลงทะเบียนในระบบบอท HR\\\\nโปรดพิมพ์คำสั่งสลับบัญชีเพื่อทดสอบ เช่น:\\\\n/switch EMP001 (เพื่อสวมบทบาท สมชาย)\\"\\n  }];\\n}\\n// 2. Handler for /switch <employee_code>\\nelse if (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code)) {\\n  const code = (nlp.intent === 'switch_user' && nlp.employee_code) ? nlp.employee_code : messageText.replace('/switch ', '').trim().toUpperCase();\\n  responseType = 'execute_sql';\\n  \\n  sql = `\\n    WITH unbind AS (\\n      UPDATE employees SET line_user_id = NULL WHERE line_user_id = $1\\n    ), bind AS (\\n      UPDATE employees SET line_user_id = $1 WHERE employee_code = $2 RETURNING name, position\\n    )\\n    INSERT INTO user_sessions (line_user_id, current_state, temp_data)\\n    VALUES ($1, 'idle', '{}'::jsonb)\\n    ON CONFLICT (line_user_id) DO UPDATE SET current_state = 'idle', temp_data = '{}'::jsonb\\n    RETURNING (SELECT name FROM bind) AS employee_name, (SELECT position FROM bind) AS employee_position;\\n  `;\\n  params = [userId, code];\\n  \\n  replyMessages = [{\\n    \\"type\\": \\"text\\",\\n    \\"text\\": `🔄 กำลังสลับบัญชี...`\\n  }];\\n}\\n// 3. User is registered - State Machine for Leave Request (Multi-turn Slot Filling)\\nelse if (input.current_state && input.current_state !== 'idle') {\\n  const state = input.current_state;\\n  let tempData = input.temp_data || {};\\n  \\n  if (cleanText === 'ยกเลิก' || nlp.intent === 'general_chat' && cleanText === 'cancel') {\\n    responseType = 'execute_sql';\\n    sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n    params = [userId];\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": \\"❌ ยกเลิกการทำรายการเรียบร้อยแล้ว กลับสู่สถานะปกติ\\"\\n    }];\\n  }\\n  else if (state === 'awaiting_leave_type') {\\n    let leaveType = '';\\n    let leaveTypeThai = '';\\n    if (cleanText.includes('ป่วย') || cleanText === 'sick') {\\n      leaveType = 'sick';\\n      leaveTypeThai = '🤒 ลาป่วย';\\n    } else if (cleanText.includes('พักร้อน') || cleanText === 'annual') {\\n      leaveType = 'annual';\\n      leaveTypeThai = '✈️ ลาพักร้อน';\\n    } else if (cleanText.includes('กิจ') || cleanText === 'personal') {\\n      leaveType = 'personal';\\n      leaveTypeThai = 'ลากิจ';\\n    }\\n    \\n    if (!leaveType) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ ประเภทการลาไม่ถูกต้อง โปรดเลือกประเภทการลา:\\\\n- พิมพ์ \\\\\\"ลาป่วย\\\\\\"\\\\n- พิมพ์ \\\\\\"ลาพักร้อน\\\\\\"\\\\n- พิมพ์ \\\\\\"ลากิจ\\\\\\"\\\\n(หรือพิมพ์ \\\\\\"ยกเลิก\\\\\\" เพื่อออกจากการทำรายการ)\\"\\n      }];\\n    } else {\\n      const rem = getRemainingDays(leaveType);\\n      if (rem <= 0) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n        params = [userId];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากสิทธิ์วันลาหมดแล้ว\\\\n\\\\n- ประเภทการลา: ${leaveTypeThai}\\\\n- คงเหลือ: 0 วัน`\\n        }];\\n      } else {\\n        tempData.leave_type = leaveType;\\n        tempData.leave_type_thai = leaveTypeThai;\\n      \\n      // Check next missing slot\\n      if (!tempData.start_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_start_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n\\\\nโปรดระบุ \\"วันที่เริ่มลาหยุด\\" (เช่น 2026-06-25 หรือพิมพ์ วันนี้ / พรุ่งนี้)`\\n        }];\\n      } else if (!tempData.end_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_end_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n📅 วันที่เริ่มลา: ${tempData.start_date}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26)`\\n        }];\\n      } else if (!tempData.reason) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\" (เช่น พักผ่อน / มีธุระ)`\\n        }];\\n      } else {\\n        if (!tempData.days && tempData.start_date && tempData.end_date) {\\n          tempData.days = calculateDays(tempData.start_date, tempData.end_date);\\n        }\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (tempData.days > rem) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n          params = [userId];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n          }];\\n        } else {\\n          if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n            }];\\n          } else {\\n            responseType = 'execute_sql';\\n            sql = `\\n              WITH new_leave AS (\\n                INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                RETURNING id\\n              )\\n              UPDATE user_sessions \\n              SET current_state = 'idle', temp_data = '{}'::jsonb \\n              WHERE line_user_id = $1;\\n            `;\\n            params = [\\n              userId,\\n              input.employee_id,\\n              tempData.leave_type,\\n              tempData.start_date,\\n              tempData.end_date,\\n              tempData.days,\\n              tempData.reason\\n            ];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n            }];\\n          }\\n        }\\n      }\\n    }\\n    }\\n  }\\n  else if (state === 'awaiting_start_date') {\\n    const startDate = parseDate(messageText);\\n    if (!startDate) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ วันที่เริ่มไม่ถูกต้อง โปรดระบุฟอร์แมต YYYY-MM-DD (เช่น 2026-06-25) หรือพิมพ์ \\\\\\"วันนี้\\\\\\" / \\\\\\"พรุ่งนี้\\\\\\"\\"\\n      }];\\n    } else {\\n      tempData.start_date = startDate;\\n      \\n      // Check next missing slot\\n      if (!tempData.end_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_end_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📅 วันที่เริ่มลา: ${startDate}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26 หรือพิมพ์จำนวนวัน เช่น 2 วัน)`\\n        }];\\n      } else {\\n        const days = calculateDays(startDate, tempData.end_date);\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (days > rem) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n          params = [userId];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n          }];\\n        } else {\\n          tempData.days = days;\\n          if (!tempData.reason) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📅 ระยะเวลาลา: ${startDate} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\"`\\n            }];\\n          } else {\\n            if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n              responseType = 'execute_sql';\\n              sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n              params = [userId, JSON.stringify(tempData)];\\n              replyMessages = [{\\n                \\"type\\": \\"text\\",\\n                \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n              }];\\n            } else {\\n              responseType = 'execute_sql';\\n              sql = `\\n                WITH new_leave AS (\\n                  INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                  VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                  RETURNING id\\n                )\\n                UPDATE user_sessions \\n                SET current_state = 'idle', temp_data = '{}'::jsonb \\n                WHERE line_user_id = $1;\\n              `;\\n              params = [\\n                userId,\\n                input.employee_id,\\n                tempData.leave_type,\\n                tempData.start_date,\\n                tempData.end_date,\\n                tempData.days,\\n                tempData.reason\\n              ];\\n              replyMessages = [{\\n                \\"type\\": \\"text\\",\\n                \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n              }];\\n            }\\n          }\\n        }\\n      }\\n    }\\n  }\\n  else if (state === 'awaiting_end_date') {\\n    const endDate = parseDate(messageText, tempData.start_date);\\n    if (!endDate || endDate < tempData.start_date) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ วันที่สิ้นสุดไม่ถูกต้อง (ต้องไม่น้อยกว่าวันที่เริ่ม) โปรดระบุแบบ YYYY-MM-DD หรือพิมพ์จำนวนวัน เช่น 1 วัน\\"\\n      }];\\n    } else {\\n      const days = calculateDays(tempData.start_date, endDate);\\n      const rem = getRemainingDays(tempData.leave_type);\\n      if (days > rem) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n        params = [userId];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n        }];\\n      } else {\\n        tempData.end_date = endDate;\\n        tempData.days = days;\\n        \\n        if (!tempData.reason) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n          params = [userId, JSON.stringify(tempData)];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${endDate} (${days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\"`\\n          }];\\n        } else {\\n          if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n            }];\\n          } else {\\n            responseType = 'execute_sql';\\n            sql = `\\n              WITH new_leave AS (\\n                INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                RETURNING id\\n              )\\n              UPDATE user_sessions \\n              SET current_state = 'idle', temp_data = '{}'::jsonb \\n              WHERE line_user_id = $1;\\n            `;\\n            params = [\\n              userId,\\n              input.employee_id,\\n              tempData.leave_type,\\n              tempData.start_date,\\n              tempData.end_date,\\n              tempData.days,\\n              tempData.reason\\n            ];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n            }];\\n          }\\n        }\\n      }\\n    }\\n  }\\n  else if (state === 'awaiting_reason') {\\n    const reason = messageText;\\n    tempData.reason = reason;\\n    \\n    const rem = getRemainingDays(tempData.leave_type);\\n    if (tempData.days > rem) {\\n      responseType = 'execute_sql';\\n      sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n      params = [userId];\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n      }];\\n    } else if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n      // Feature 2: Sick leave > 2 days — ask for medical certificate\\n      tempData.reason = reason;\\n      responseType = 'execute_sql';\\n      sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n      params = [userId, JSON.stringify(tempData)];\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n      }];\\n    } else {\\n      responseType = 'execute_sql';\\n      \\n      // Save to leave_requests and reset user session in a single transaction\\n      sql = `\\n        WITH new_leave AS (\\n          INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n          VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n          RETURNING id\\n        )\\n        UPDATE user_sessions \\n        SET current_state = 'idle', temp_data = '{}'::jsonb \\n        WHERE line_user_id = $1;\\n      `;\\n      params = [\\n        userId,\\n        input.employee_id,\\n        tempData.leave_type,\\n        tempData.start_date,\\n        tempData.end_date,\\n        tempData.days,\\n        reason\\n      ];\\n      \\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n      }];\\n    }\\n  }\\n  else if (state === 'awaiting_medical_cert') {\\n    // Feature 2: Handle medical certificate note submission\\n    const certNote = messageText;\\n    const tdMC = input.temp_data || {};\\n    responseType = 'execute_sql';\\n    sql = `\\n      WITH new_leave AS (\\n        INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n        VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n        RETURNING id\\n      )\\n      UPDATE user_sessions \\n      SET current_state = 'idle', temp_data = '{}'::jsonb \\n      WHERE line_user_id = $1;\\n    `;\\n    const certReason = tdMC.reason + ' [ใบรับรองแพทย์: ' + certNote + ']';\\n    params = [\\n      userId,\\n      input.employee_id,\\n      tdMC.leave_type,\\n      tdMC.start_date,\\n      tdMC.end_date,\\n      tdMC.days,\\n      certReason\\n    ];\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tdMC.leave_type_thai}\\\\n- ระยะเวลา: ${tdMC.start_date} ถึง ${tdMC.end_date} (${tdMC.days} วัน)\\\\n- เหตุผล: ${tdMC.reason}\\\\n- 🏥 ใบรับรองแพทย์: ${certNote}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n    }];\\n  }\\n  else if (state === 'display_team_schedule') {\\n    // Feature 1: Display stored team schedule from temp_data (populated previous turn)\\n    responseType = 'execute_sql';\\n    sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n    params = [userId];\\n    \\n    const schedData = input.temp_data || {};\\n    const schedule = Array.isArray(schedData.schedule) ? schedData.schedule : [];\\n    const displayDate = schedData.check_date || '?';\\n    const dept = schedData.department || input.department;\\n    \\n    function ltThai(t) {\\n      if (t === 'sick') return '🤒 ลาป่วย';\\n      if (t === 'annual') return '✈️ ลาพักร้อน';\\n      if (t === 'personal') return '💼 ลากิจ';\\n      return t;\\n    }\\n    \\n    if (schedule.length === 0) {\\n      replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${displayDate}\\\\n\\\\n✅ ไม่มีสมาชิกทีมลาหยุดในวันดังกล่าว` }];\\n    } else {\\n      const lines = schedule.map(s => `• ${s.name} — ${ltThai(s.leave_type)}`).join('\\\\n');\\n      replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${displayDate}\\\\n\\\\nสมาชิกที่ลาหยุด (${schedule.length} คน):\\\\n${lines}` }];\\n    }\\n  }\\n}\\n// 4. NLP Smart Processing (When user is in 'idle' state)\\nelse {\\n  if (nlp.intent === 'request_leave') {\\n    // LLM extracted a leave request! Let's check what variables are already present.\\n    let tempData = {\\n      leave_type: nlp.leave_type || null,\\n      leave_type_thai: nlp.leave_type ? getLeaveTypeThai(nlp.leave_type) : null,\\n      start_date: nlp.start_date || null,\\n      end_date: nlp.end_date || null,\\n      days: nlp.days || null,\\n      reason: nlp.reason || null\\n    };\\n    \\n    // If end_date is present but start_date is not, default start_date to today\\n    const today = new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0];\\n    if (tempData.end_date && !tempData.start_date) {\\n      tempData.start_date = today;\\n    }\\n    \\n    // If start_date is present but end_date is not:\\n    if (tempData.start_date && !tempData.end_date) {\\n      if (tempData.days) {\\n        // Calculate end_date = start_date + days - 1\\n        const start = new Date(tempData.start_date);\\n        const end = new Date(start.getTime() + ((tempData.days - 1) * 24 * 60 * 60 * 1000));\\n        tempData.end_date = end.toISOString().split('T')[0];\\n      } else {\\n        // Default end_date to start_date (1 day)\\n        tempData.end_date = tempData.start_date;\\n        tempData.days = 1;\\n      }\\n    }\\n    \\n    // Recalculate days if start and end are present\\n    if (tempData.start_date && tempData.end_date && !tempData.days) {\\n      tempData.days = calculateDays(tempData.start_date, tempData.end_date);\\n    }\\n    \\n    // Check if we have EVERYTHING to submit immediately\\n    if (tempData.leave_type && tempData.start_date && tempData.end_date && tempData.reason) {\\n      const rem = getRemainingDays(tempData.leave_type);\\n      if (tempData.days > rem) {\\n        responseType = 'direct_reply';\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน`\\n        }];\\n      } else if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n        // Feature 2: NLP direct path — sick leave > 2 days, ask for medical cert\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n        }];\\n      } else {\\n        // Submit immediately!\\n        responseType = 'execute_sql';\\n        sql = `\\n          INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n          VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending');\\n        `;\\n        params = [\\n          userId,\\n          input.employee_id,\\n          tempData.leave_type,\\n          tempData.start_date,\\n          tempData.end_date,\\n          tempData.days,\\n          tempData.reason\\n        ];\\n        \\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `✅ ส่งคำขอลาหยุดผ่านระบบ AI สำเร็จเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดใบลา:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอได้รับการบันทึกเข้าระบบแล้ว และกำลังรอฝ่ายบุคคล (HR) พิจารณาอนุมัติครับ`\\n        }];\\n      }\\n    } else {\\n      // Check if we have leave_type but days are depleted\\n      if (tempData.leave_type) {\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (rem <= 0) {\\n          responseType = 'direct_reply';\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากสิทธิ์วันลาหมดแล้ว\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- คงเหลือ: 0 วัน`\\n          }];\\n          \\n          // Automatically append \\"- bot\\" to all text responses, and a footer to all Flex bubbles\\n          if (replyMessages && Array.isArray(replyMessages)) {\\n            replyMessages.forEach(msg => {\\n              if (msg.type === 'text') {\\n                msg.text = msg.text + '\\\\n\\\\n- bot';\\n              }\\n            });\\n          }\\n          \\n          return [{\\n            json: {\\n              userId,\\n              replyToken,\\n              responseType,\\n              replyMessages,\\n              sql: '',\\n              params: []\\n            }\\n          }];\\n        }\\n      }\\n\\n      // Something is missing. Determine the next state to transition to\\n      let nextState = 'awaiting_leave_type';\\n      let promptText = 'กรุณาเลือกประเภทการลาที่ต้องการยื่นหยุดงาน:';\\n      \\n      if (!tempData.leave_type) {\\n        nextState = 'awaiting_leave_type';\\n        // Show buttons\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        \\n        replyMessages = [{\\n          \\"type\\": \\"flex\\",\\n          \\"altText\\": \\"เลือกประเภทการลาหยุด\\",\\n          \\"contents\\": {\\n            \\"type\\": \\"bubble\\",\\n            \\"body\\": {\\n              \\"type\\": \\"box\\",\\n              \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n              \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": \\"📝 ยื่นใบลาหยุดงาน\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#4f46e5\\" },\\n                { \\"type\\": \\"text\\", \\"text\\": \\"กรุณาเลือกประเภทการลาเพื่อดำเนินการต่อ:\\", \\"size\\": \\"sm\\", \\"color\\": \\"#94a3b8\\", \\"margin\\": \\"md\\", \\"wrap\\": true },\\n                { \\"type\\": \\"separator\\", \\"margin\\": \\"md\\" },\\n                {\\n                  \\"type\\": \\"box\\",\\n                  \\"layout\\": \\"vertical\\",\\n                  \\"margin\\": \\"md\\",\\n                  \\"spacing\\": \\"sm\\",\\n                  \\"contents\\": [\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"🤒 ลาป่วย (Sick Leave)\\", \\"text\\": \\"ลาป่วย\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#ef4444\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"✈️ ลาพักร้อน (Annual Leave)\\", \\"text\\": \\"ลาพักร้อน\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#4f46e5\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"💼 ลากิจ (Personal Leave)\\", \\"text\\": \\"ลากิจ\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#f59e0b\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"❌ ยกเลิกรายการ\\", \\"text\\": \\"ยกเลิก\\" }, \\"style\\": \\"link\\", \\"color\\": \\"#ef4444\\" }\\n                  ]\\n                }\\n              ]\\n            }\\n          }\\n        }];\\n      } else if (!tempData.start_date) {\\n        nextState = 'awaiting_start_date';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n\\\\nโปรดระบุ \\"วันที่เริ่มลาหยุด\\" (เช่น 2026-06-25 หรือพิมพ์ วันนี้ / พรุ่งนี้)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      } else if (!tempData.end_date) {\\n        nextState = 'awaiting_end_date';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n📅 วันเริ่มลา: ${tempData.start_date}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26 หรือพิมพ์จำนวนวัน เช่น 3 วัน)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      } else if (!tempData.reason) {\\n        nextState = 'awaiting_reason';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\" (เช่น พักผ่อนส่วนตัว / เป็นไข้หวัด)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      }\\n    }\\n  }\\n  else if (nlp.intent === 'check_leave') {\\n    // Trigger case 6: Check Remaining Leave\\n    responseType = 'direct_reply';\\n    const sickRem = input.total_sick_leave - input.used_sick_leave;\\n    const annualRem = input.total_annual_leave - input.used_annual_leave;\\n    const personalRem = input.total_personal_leave - input.used_personal_leave;\\n    \\n    replyMessages = [{\\n      \\"type\\": \\"flex\\",\\n      \\"altText\\": \\"วันลาคงเหลือของคุณ\\",\\n      \\"contents\\": {\\n        \\"type\\": \\"bubble\\",\\n        \\"body\\": {\\n          \\"type\\": \\"box\\",\\n          \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n          \\"contents\\": [\\n            { \\"type\\": \\"text\\", \\"text\\": \\"📊 วันลาคงเหลือของคุณ\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#10b981\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": `คุณ ${input.name}`, \\"size\\": \\"xs\\", \\"color\\": \\"#94a3b8\\", \\"margin\\": \\"xs\\" },\\n            { \\"type\\": \\"separator\\", \\"margin\\": \\"sm\\" },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `🤒 ลาป่วย: คงเหลือ ${sickRem} จาก ${input.total_sick_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#10b981\\", \\"height\\": \\"6px\\", \\"width\\": `${(sickRem/input.total_sick_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `✈️ ลาพักร้อน: คงเหลือ ${annualRem} จาก ${input.total_annual_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#6366f1\\", \\"height\\": \\"6px\\", \\"width\\": `${(annualRem/input.total_annual_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `💼 ลากิจ: คงเหลือ ${personalRem} จาก ${input.total_personal_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#f59e0b\\", \\"height\\": \\"6px\\", \\"width\\": `${(personalRem/input.total_personal_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            }\\n          ]\\n        }\\n      }\\n    }];\\n  }\\n  else if (nlp.intent === 'check_team_schedule') {\\n    const todayStr = new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0];\\n    const checkDate = nlp.check_date || todayStr;\\n    responseType = 'execute_sql';\\n    sql = `\\n      SELECT e.name, lr.leave_type, lr.start_date::text, lr.end_date::text\\n      FROM leave_requests lr\\n      JOIN employees e ON lr.employee_id = e.id\\n      WHERE lr.status = 'approved'\\n        AND e.department = $1\\n        AND $2::date BETWEEN lr.start_date AND lr.end_date\\n      ORDER BY e.name;\\n    `;\\n    params = [input.department, checkDate];\\n    replyMessages = [{ type: 'text', text: `🔍 กำลังค้นหาข้อมูลคิวทีม...` }];\\n  }\\n  else if (nlp.intent === 'check_jd') {\\n    // Trigger case 5: Job Description check\\n    responseType = 'direct_reply';\\n    replyMessages = [{\\n      \\"type\\": \\"flex\\",\\n      \\"altText\\": \\"ขอบข่ายงาน (Job Description)\\",\\n      \\"contents\\": {\\n        \\"type\\": \\"bubble\\",\\n        \\"body\\": {\\n          \\"type\\": \\"box\\",\\n          \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n          \\"contents\\": [\\n            { \\"type\\": \\"text\\", \\"text\\": \\"📋 ขอบข่ายงานของคุณ\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#6366f1\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": input.name, \\"weight\\": \\"bold\\", \\"size\\": \\"md\\", \\"margin\\": \\"md\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": `${input.position} • แผนก ${input.department}`, \\"size\\": \\"xs\\", \\"color\\": \\"#94a3b8\\" },\\n            { \\"type\\": \\"separator\\", \\"margin\\": \\"md\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": input.job_description, \\"size\\": \\"sm\\", \\"wrap\\": true, \\"margin\\": \\"md\\", \\"color\\": \\"#cbd5e1\\" }\\n          ]\\n        }\\n      }\\n    }];\\n  }\\n  else {\\n    // Default Help menu\\n    responseType = 'direct_reply';\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": `สวัสดีครับคุณ ${input.name} ตำแหน่ง ${input.position}\\\\nโปรดระบุงานที่ต้องการจากตัวเลือกด้านล่าง:\\\\n\\\\n- พิมพ์ \\"ลา\\" เพื่อยื่นใบลาหยุดงาน\\\\n- พิมพ์ \\"วันลา\\" เพื่อเช็คสิทธิ์วันลาคงเหลือ\\\\n- พิมพ์ \\"job description\\" เพื่อขอดูขอบข่ายงาน\\\\n- พิมพ์ \\"คิวทีม\\" เพื่อเช็คตารางลาของทีม\\\\n- พิมพ์ \\"/switch <รหัสพนักงาน>\\" เพื่อสลับตัวตน` \\n    }];\\n  }\\n}\\n// Automatically append \\"- bot\\" to all text responses, and a footer to all Flex bubbles\\nif (replyMessages && Array.isArray(replyMessages)) {\\n  replyMessages.forEach(msg => {\\n    if (msg.type === 'text') {\\n      msg.text = msg.text + '\\\\n\\\\n- bot';\\n    } else if (msg.type === 'flex') {\\n      try {\\n        const bubble = msg.contents;\\n        if (bubble && bubble.type === 'bubble') {\\n          if (!bubble.footer) {\\n            bubble.footer = {\\n              \\"type\\": \\"box\\",\\n              \\"layout\\": \\"vertical\\",\\n              \\"contents\\": [\\n                {\\n                  \\"type\\": \\"text\\",\\n                  \\"text\\": \\"- bot\\",\\n                  \\"size\\": \\"xs\\",\\n                  \\"color\\": \\"#94a3b8\\",\\n                  \\"align\\": \\"end\\"\\n                }\\n              ]\\n            };\\n          } else if (bubble.footer.contents) {\\n            bubble.footer.contents.push({\\n              \\"type\\": \\"text\\",\\n              \\"text\\": \\"- bot\\",\\n              \\"size\\": \\"xs\\",\\n              \\"color\\": \\"#94a3b8\\",\\n              \\"align\\": \\"end\\"\\n            });\\n          }\\n        }\\n      } catch (e) {\\n        console.error('Failed to append bot footer to flex:', e);\\n      }\\n    }\\n  });\\n}\\n\\n// Feature 3: Manager notification flag\\nconst isLeaveSubmission = sql.includes('INSERT INTO leave_requests');\\n\\nreturn [{\\n  json: {\\n    userId,\\n    replyToken,\\n    responseType,\\n    replyMessages,\\n    sql,\\n    params,\\n    isLeaveSubmission,\\n    employeeId: input.employee_id || null,\\n    employeeName: input.name || null,\\n    department: input.department || null,\\n    sqlType: (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code) ? 'switch' : ((input.current_state && input.current_state !== 'idle') ? 'other' : (nlp.intent === 'check_team_schedule' ? 'check_team_schedule' : 'other'))),\\n    sqlMeta: {\\n      checkDate: (nlp.intent === 'check_team_schedule' ? (nlp.check_date || new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0]) : null),\\n      department: input.department || null,\\n      employeeCode: (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code) ? (nlp.employee_code || cleanText.replace('/switch ', '').trim().toUpperCase()) : null)\\n    }\\n  }\\n}];\\n"},"id":"code-controller","name":"Core Controller","type":"n8n-nodes-base.code","typeVersion":2,"position":[680,150]},{"parameters":{"conditions":{"string":[{"value1":"={{ $json.responseType }}","operation":"equal","value2":"execute_sql"}]}},"id":"switch-response","name":"Switch Response Mode","type":"n8n-nodes-base.if","typeVersion":1,"position":[880,150]},{"parameters":{"operation":"executeQuery","query":"={{$json.sql}}","options":{"queryReplacement":"={{ $('Core Controller').first().json.params }}"}},"id":"pg-execute-actions","name":"PG: Execute SQL Action","type":"n8n-nodes-base.postgres","typeVersion":2,"position":[1080,50],"credentials":{"postgres":{"id":"vwf7u64OuSi5ejWs","name":"Postgres HR - localhost:5432"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"},{"name":"Authorization","value":"=Bearer {{ $env.HR_LINE_CHANNEL_ACCESS_TOKEN }}"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": \\"{{ $('Format SQL Result').first().json.replyToken }}\\",\\n  \\"messages\\": {{ JSON.stringify($('Format SQL Result').first().json.replyMessages) }}\\n}","options":{}},"id":"http-line-reply","name":"LINE: Reply Message","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[1300,150]},{"parameters":{"method":"POST","url":"http://localhost:11434/api/generate","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"qwen2.5:7b\\",\\n  \\"prompt\\": \\"You are an HR Assistant Bot. Parse the user's Thai message and extract structured fields in JSON format.\\\\nCurrent date today is: {{ new Date(new Date().getTime() + 7 * 3600 * 1000).toISOString().split('T')[0] }} (Bangkok Time).\\\\n\\\\nAnalyze the input text and output a JSON object with these EXACT keys:\\\\n{\\\\n  \\\\\\"intent\\\\\\": \\\\\\"request_leave\\\\\\" | \\\\\\"check_leave\\\\\\" | \\\\\\"check_jd\\\\\\" | \\\\\\"switch_user\\\\\\" | \\\\\\"check_team_schedule\\\\\\" | \\\\\\"general_chat\\\\\\",\\\\n  \\\\\\"leave_type\\\\\\": \\\\\\"sick\\\\\\" | \\\\\\"annual\\\\\\" | \\\\\\"personal\\\\\\" | null,\\\\n  \\\\\\"start_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null,\\\\n  \\\\\\"end_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null,\\\\n  \\\\\\"days\\\\\\": number | null,\\\\n  \\\\\\"reason\\\\\\": \\\\\\"Thai string\\\\\\" | null,\\\\n  \\\\\\"employee_code\\\\\\": \\\\\\"EMPxxx\\\\\\" | null,\\\\n  \\\\\\"check_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null\\\\n}\\\\n\\\\nGuidelines:\\\\n1. Intent:\\\\n   - \\\\\\"request_leave\\\\\\": User wants to request leave (e.g., \\\\\\"ขอลา\\\\\\", \\\\\\"ป่วย\\\\\\", \\\\\\"ลากิจ\\\\\\", \\\\\\"พักร้อน\\\\\\").\\\\n   - \\\\\\"check_leave\\\\\\": User wants to check remaining leave days (e.g., \\\\\\"วันลาคงเหลือ\\\\\\", \\\\\\"สิทธิ์วันหยุด\\\\\\").\\\\n   - \\\\\\"check_jd\\\\\\": User wants to check job description (e.g., \\\\\\"งานของฉัน\\\\\\", \\\\\\"job description\\\\\\").\\\\n   - \\\\\\"switch_user\\\\\\": User wants to switch account (e.g., \\\\\\"/switch EMP001\\\\\\", \\\\\\"สลับผู้ใช้เป็น EMP002\\\\\\").\\\\n   - \\\\\\"check_team_schedule\\\\\\": User wants to check who is on leave in their department/team (e.g. \\\\\\"ใครลาบ้าง\\\\\\", \\\\\\"พรุ่งนี้มีใครหยุดไหม\\\\\\", \\\\\\"เช็คตารางลาทีม\\\\\\"). Extract the date to check as YYYY-MM-DD in check_date. Default to today if no date is specified.\\\\n   - \\\\\\"general_chat\\\\\\": Any other text.\\\\n2. Relative and Absolute Dates parsing (relative to today):\\\\n   - \\\\\\"วันนี้\\\\\\" -> today's date\\\\n   - \\\\\\"พรุ่งนี้\\\\\\" -> today's date + 1 day\\\\n   - \\\\\\"เมื่อวาน\\\\\\" / \\\\\\"เมื่อวานนี้\\\\\\" -> today's date - 1 day\\\\n   - \\\\\\"วานซืน\\\\\\" / \\\\\\"เมื่อวานซืน\\\\\\" -> today's date - 2 days\\\\n   - \\\\\\"มะรืน\\\\\\" / \\\\\\"มะรืนนี้\\\\\\" -> today's date + 2 days\\\\n   - \\\\\\"วันจันทร์อาทิตย์หน้า\\\\\\" -> next Monday\\\\n   - \\\\\\"วันอาทิตย์เดือนหน้า\\\\\\" -> first Sunday of next month\\\\n   - \\\\\\"20 สิงหา\\\\\\" / \\\\\\"20 สิงหาคม\\\\\\" / \\\\\\"20 สิงหาคม ปีนี้\\\\\\" -> YYYY-08-20 (using current year)\\\\n   - \\\\\\"20 02\\\\\\" / \\\\\\"20/02\\\\\\" -> YYYY-02-20 (using current year)\\\\n   - \\\\\\"อีก 3 วันถัดไป\\\\\\" starting tomorrow -> start_date: tomorrow, end_date: 2 days after tomorrow, days: 3\\\\n   - If Buddhist Era (พ.ศ. / B.E. e.g. 2569) is mentioned, convert to Gregorian (e.g. 2026) by subtracting 543.\\\\n3. Output ONLY raw JSON. No markdown, no formatting, no extra text.\\\\n\\\\nUser text: \\\\\\"{{ ($('Parse LINE Event').first().json.messageText || '').replace(/\\\\\\\\/g, '\\\\\\\\\\\\\\\\').replace(/\\\\\\"/g, '\\\\\\\\\\\\\\"') }}\\\\\\"\\\\nJSON Output:\\",\\n  \\"stream\\": false,\\n  \\"options\\": {\\n    \\"temperature\\": 0.1\\n  }\\n}","options":{}},"id":"ollama-parse-intent","name":"Ollama: Parse Intent","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[480,150]},{"parameters":{"jsCode":"\\nconst data = $('Core Controller').first().json;\\nif (!data.isLeaveSubmission) return [];\\n\\n// Send LINE push to manager via notify-manager API\\nconst LINE_TOKEN = 'Irn1vjQBmg/DV0/8s7bSFAyqZETfWKV1lGNBAAMgq7xL78hlbs3fMK0QG+Rqh3MW9/G0fQuV/a2nYIyZoeelGM9p8pYfgZpb7I91nTT3g05e3Oqa3cP0xkw6clx5mI55v64cCiYPdU1xDpB7bQgBsQdB04t89/1O/w1cDnyilFU=';\\n\\ntry {\\n  const res = await fetch('http://localhost:3000/api/notify-manager', {\\n    method: 'POST',\\n    headers: { 'Content-Type': 'application/json' },\\n    body: JSON.stringify({\\n      employeeId: data.employeeId,\\n      employeeName: data.employeeName,\\n      department: data.department,\\n      lineToken: LINE_TOKEN\\n    })\\n  });\\n  const result = await res.json();\\n  return [{ json: { notified: true, result } }];\\n} catch(e) {\\n  console.error('Manager notify failed:', e.message);\\n  return [{ json: { notified: false, error: e.message } }];\\n}\\n        "},"id":"code-notify-manager","name":"Notify Manager","type":"n8n-nodes-base.code","typeVersion":2,"position":[1500,300]},{"parameters":{"jsCode":"\\nlet replyToken = '';\\nlet replyMessages = [];\\nlet userId = '';\\nlet isLeaveSubmission = false;\\nlet employeeId = null;\\nlet employeeName = null;\\nlet department = null;\\n\\ntry {\\n  const core = $('Core Controller').first().json;\\n  replyToken = core.replyToken;\\n  replyMessages = core.replyMessages || [];\\n  userId = core.userId;\\n  isLeaveSubmission = core.isLeaveSubmission || false;\\n  employeeId = core.employeeId || null;\\n  employeeName = core.employeeName || null;\\n  department = core.department || null;\\n\\n  if (core.responseType === 'execute_sql') {\\n    let pgRows = [];\\n    try {\\n      pgRows = $input.all().map(item => item.json);\\n    } catch (e) {\\n      pgRows = $('PG: Execute SQL Action').all().map(item => item.json);\\n    }\\n    \\n    if (core.sqlType === 'check_team_schedule') {\\n      const checkDate = core.sqlMeta.checkDate;\\n      const dept = core.sqlMeta.department || 'ไม่ระบุ';\\n      \\n      const schedule = pgRows || [];\\n      \\n      function ltThai(t) {\\n        if (t === 'sick') return '🤒 ลาป่วย';\\n        if (t === 'annual') return '✈️ ลาพักร้อน';\\n        if (t === 'personal') return '💼 ลากิจ';\\n        return t;\\n      }\\n      \\n      if (schedule.length === 0 || (schedule.length === 1 && schedule[0].name === null)) {\\n        replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${checkDate}\\\\n\\\\n✅ ไม่มีสมาชิกทีมลาหยุดในวันดังกล่าว\\\\n\\\\n- bot` }];\\n      } else {\\n        const lines = schedule.map(s => `• ${s.name} — ${ltThai(s.leave_type)}`).join('\\\\n');\\n        replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${checkDate}\\\\n\\\\nสมาชิกที่ลาหยุด (${schedule.length} คน):\\\\n${lines}\\\\n\\\\n- bot` }];\\n      }\\n    }\\n    else if (core.sqlType === 'switch') {\\n      const row = pgRows[0] || {};\\n      const newName = row.employee_name;\\n      const newPos = row.employee_position;\\n      \\n      if (!newName) {\\n        replyMessages = [{\\n          type: 'text',\\n          text: `❌ ไม่พบรหัสพนักงาน ${core.sqlMeta.employeeCode} ในระบบ โปรดตรวจสอบความถูกต้อง\\\\n\\\\n- bot`\\n        }];\\n      } else {\\n        replyMessages = [{\\n          type: 'text',\\n          text: `✅ สลับบัญชีสำเร็จ!\\\\n\\\\nสวัสดีครับคุณ ${newName} ตำแหน่ง ${newPos}\\\\nโปรดระบุงานที่ต้องการจากตัวเลือกด้านล่าง:\\\\n\\\\n- พิมพ์ \\"ลา\\" เพื่อยื่นใบลาหยุดงาน\\\\n- พิมพ์ \\"วันลา\\" เพื่อเช็คสิทธิ์วันลาคงเหลือ\\\\n- พิมพ์ \\"job description\\" เพื่อขอดูขอบข่ายงาน\\\\n- พิมพ์ \\"คิวทีม\\" เพื่อเช็คตารางลาของทีม\\\\n- พิมพ์ \\"/switch <รหัสพนักงาน>\\" เพื่อสลับตัวตน\\\\n\\\\n- bot`\\n        }];\\n      }\\n    }\\n  }\\n} catch (err) {\\n  console.error('Format SQL Result failed:', err);\\n}\\n\\nreturn [{\\n  json: {\\n    userId,\\n    replyToken,\\n    replyMessages,\\n    isLeaveSubmission,\\n    employeeId,\\n    employeeName,\\n    department\\n  }\\n}];\\n        "},"id":"code-format-sql","name":"Format SQL Result","type":"n8n-nodes-base.code","typeVersion":2,"position":[1150,150]}]	{"LINE Webhook":{"main":[[{"node":"Respond 200 OK","type":"main","index":0},{"node":"Parse LINE Event","type":"main","index":0}]]},"Parse LINE Event":{"main":[[{"node":"PG: Get Employee & Session","type":"main","index":0}]]},"PG: Get Employee & Session":{"main":[[{"node":"Ollama: Parse Intent","type":"main","index":0}]]},"Core Controller":{"main":[[{"node":"Switch Response Mode","type":"main","index":0}]]},"Switch Response Mode":{"main":[[{"node":"PG: Execute SQL Action","type":"main","index":0}],[{"node":"Format SQL Result","type":"main","index":0}]]},"PG: Execute SQL Action":{"main":[[{"node":"Format SQL Result","type":"main","index":0}]]},"Ollama: Parse Intent":{"main":[[{"node":"Core Controller","type":"main","index":0}]]},"LINE: Reply Message":{"main":[[{"node":"Notify Manager","type":"main","index":0}]]},"Format SQL Result":{"main":[[{"node":"LINE: Reply Message","type":"main","index":0}]]}}	\N	f	\N	[]
5ca0fefa-1da9-4da1-ab3f-09fcc21f28ee	wb0BxLBPY80gSVpK	Fluke Jesadakorn	2026-06-25 00:07:21.807+07	2026-06-25 00:07:21.807+07	[{"parameters":{"httpMethod":"POST","path":"hr-line-agent","responseMode":"responseNode","options":{}},"id":"wh-line-bot","name":"LINE Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-256,160],"webhookId":"hr-line-agent-webhook"},{"parameters":{"respondWith":"json","responseBody":"{}","options":{"responseHeaders":{"entries":[{"name":"Content-Type","value":"application/json"}]}}},"id":"resp-200","name":"Respond 200 OK","type":"n8n-nodes-base.respondToWebhook","typeVersion":1,"position":[-32,64]},{"parameters":{"jsCode":"const body = items[0].json.body;\\nif (!body || !body.events || body.events.length === 0) {\\n  return [];\\n}\\n\\nconst event = body.events[0];\\nconst userId = event.source.userId;\\nconst eventType = event.type;\\nconst replyToken = event.replyToken;\\n\\nlet messageText = '';\\nlet postbackData = '';\\nlet postbackParams = {};\\n\\nif (eventType === 'message' && event.message.type === 'text') {\\n  messageText = event.message.text.trim();\\n} else if (eventType === 'postback') {\\n  postbackData = event.postback.data;\\n  postbackParams = event.postback.params || {};\\n}\\n\\nreturn [{\\n  json: {\\n    userId,\\n    eventType,\\n    replyToken,\\n    messageText,\\n    postbackData,\\n    postbackParams\\n  }\\n}];"},"id":"code-parse","name":"Parse LINE Event","type":"n8n-nodes-base.code","typeVersion":2,"position":[-32,256]},{"parameters":{"operation":"executeQuery","query":"SELECT \\n  e.id as employee_id, \\n  e.employee_code, \\n  e.name, \\n  e.position, \\n  e.department, \\n  e.role, \\n  e.job_description,\\n  e.total_sick_leave, e.used_sick_leave,\\n  e.total_annual_leave, e.used_annual_leave,\\n  e.total_personal_leave, e.used_personal_leave,\\n  s.current_state,\\n  s.temp_data\\nFROM (SELECT $1::text as line_id) input\\nLEFT JOIN employees e ON e.line_user_id = input.line_id\\nLEFT JOIN user_sessions s ON s.line_user_id = input.line_id;","options":{"queryReplacement":"={{ [$('Parse LINE Event').first().json.userId] }}"}},"id":"pg-get-session","name":"PG: Get Employee & Session","type":"n8n-nodes-base.postgres","typeVersion":2,"position":[192,256],"credentials":{"postgres":{"id":"vwf7u64OuSi5ejWs","name":"Postgres HR - localhost:5432"}}},{"parameters":{"jsCode":"const input = $('PG: Get Employee & Session').first().json;\\nconst parsedEvent = $('Parse LINE Event').first().json;\\nconst userId = parsedEvent.userId;\\nconst replyToken = parsedEvent.replyToken;\\nconst messageText = parsedEvent.messageText ? parsedEvent.messageText.trim() : '';\\nconst cleanText = messageText.toLowerCase();\\n\\n// Get Ollama NLP output\\nconst ollamaRes = $('Ollama: Parse Intent').first().json.response;\\nlet nlp = { intent: 'general_chat', leave_type: null, start_date: null, end_date: null, days: null, reason: null, employee_code: null, check_date: null };\\ntry {\\n  let cleanRes = ollamaRes.trim();\\n  const jsonMatch = cleanRes.match(/\\\\{[\\\\s\\\\S]*\\\\}/);\\n  if (jsonMatch) {\\n    nlp = JSON.parse(jsonMatch[0]);\\n  } else {\\n    nlp = JSON.parse(cleanRes);\\n  }\\n} catch (e) {\\n  console.error('Failed to parse Ollama JSON:', e);\\n}\\n\\nlet responseType = 'direct_reply';\\nlet replyMessages = [];\\nlet sql = '';\\nlet params = [];\\n\\n// Helper functions for date parsing and days calculation\\nfunction parseDate(text, baseDate = null) {\\n  if (!text) return null;\\n  const clean = text.trim().toLowerCase().replace(/\\\\s+/g, ' ');\\n  const today = new Date(new Date().getTime() + (7 * 60 * 60 * 1000));\\n  const currentYear = today.getFullYear();\\n\\n  // 1. Relative words\\n  if (clean === 'วันนี้') {\\n    return today.toISOString().split('T')[0];\\n  }\\n  if (clean === 'พรุ่งนี้') {\\n    const d = new Date(today.getTime() + (24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'เมื่อวาน' || clean === 'เมื่อวานนี้') {\\n    const d = new Date(today.getTime() - (24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'วานซืน' || clean === 'เมื่อวานซืน') {\\n    const d = new Date(today.getTime() - (2 * 24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n  if (clean === 'มะรืน' || clean === 'มะรืนนี้') {\\n    const d = new Date(today.getTime() + (2 * 24 * 60 * 60 * 1000));\\n    return d.toISOString().split('T')[0];\\n  }\\n\\n  // 2. Duration match: e.g., \\"3 วัน\\", \\"5 วัน\\", \\"3 days\\"\\n  if (baseDate) {\\n    const durMatch = clean.match(/^(\\\\d+)\\\\s*(วัน|day|days)$/);\\n    if (durMatch) {\\n      const numDays = parseInt(durMatch[1]);\\n      if (numDays > 0) {\\n        const start = new Date(baseDate);\\n        const end = new Date(start.getTime() + ((numDays - 1) * 24 * 60 * 60 * 1000));\\n        return end.toISOString().split('T')[0];\\n      }\\n    }\\n  }\\n\\n  // 3. Parse Thai months\\n  const thaiMonthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];\\n  const thaiMonthsFull = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];\\n\\n  let parsedText = clean;\\n  let monthIndex = -1;\\n  for (let i = 0; i < 12; i++) {\\n    if (clean.includes(thaiMonthsFull[i])) {\\n      monthIndex = i + 1;\\n      parsedText = clean.replace(thaiMonthsFull[i], ' ' + monthIndex + ' ');\\n      break;\\n    }\\n  }\\n  if (monthIndex === -1) {\\n    for (let i = 0; i < 12; i++) {\\n      const term = thaiMonthsShort[i].replace('.', '\\\\\\\\.?');\\n      const regex = new RegExp(term, 'g');\\n      if (regex.test(clean)) {\\n        monthIndex = i + 1;\\n        parsedText = clean.replace(regex, ' ' + monthIndex + ' ');\\n        break;\\n      }\\n    }\\n  }\\n\\n  // Match formats:\\n  // - \\"YYYY-MM-DD\\"\\n  const dateRegexYMD = /^(\\\\d{4})[-/](\\\\d{1,2})[-/](\\\\d{1,2})$/;\\n  const matchYMD = parsedText.match(dateRegexYMD);\\n  if (matchYMD) {\\n    let y = parseInt(matchYMD[1]);\\n    let m = parseInt(matchYMD[2]) - 1;\\n    let d = parseInt(matchYMD[3]);\\n    if (y >= 2400) y -= 543;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // - \\"DD/MM/YYYY\\"\\n  const dateRegexDMY = /^(\\\\d{1,2})[-/ ](\\\\d{1,2})[-/ ](\\\\d{4})$/;\\n  const matchDMY = parsedText.match(dateRegexDMY);\\n  if (matchDMY) {\\n    let d = parseInt(matchDMY[1]);\\n    let m = parseInt(matchDMY[2]) - 1;\\n    let y = parseInt(matchDMY[3]);\\n    if (y >= 2400) y -= 543;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // - \\"DD/MM\\" (e.g. 20/02 or 20 08)\\n  const dateRegexDM = /^(\\\\d{1,2})[-/ ](\\\\d{1,2})$/;\\n  const matchDM = parsedText.match(dateRegexDM);\\n  if (matchDM) {\\n    let d = parseInt(matchDM[1]);\\n    let m = parseInt(matchDM[2]) - 1;\\n    let y = currentYear;\\n    const dateObj = new Date(y, m, d);\\n    if (!isNaN(dateObj.getTime())) {\\n      return formatDate(dateObj);\\n    }\\n  }\\n\\n  // Digits fallback extraction (e.g. \\"วันที่ 20 เดือน 8\\")\\n  const digits = parsedText.match(/\\\\d+/g);\\n  if (digits) {\\n    if (digits.length === 3) {\\n      let d = parseInt(digits[0]);\\n      let m = parseInt(digits[1]) - 1;\\n      let y = parseInt(digits[2]);\\n      if (y < 100) y += 2000;\\n      if (y >= 2400) y -= 543;\\n      const dateObj = new Date(y, m, d);\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    } else if (digits.length === 2) {\\n      let d = parseInt(digits[0]);\\n      let m = parseInt(digits[1]) - 1;\\n      let y = currentYear;\\n      if (monthIndex !== -1) {\\n        m = monthIndex - 1;\\n      }\\n      const dateObj = new Date(y, m, d);\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    } else if (digits.length === 1 && baseDate) {\\n      let d = parseInt(digits[0]);\\n      const base = new Date(baseDate);\\n      const dateObj = new Date(base.getFullYear(), base.getMonth(), d);\\n      if (dateObj < base) {\\n        dateObj.setMonth(dateObj.getMonth() + 1);\\n      }\\n      if (!isNaN(dateObj.getTime())) return formatDate(dateObj);\\n    }\\n  }\\n\\n  const parsed = Date.parse(clean);\\n  if (!isNaN(parsed)) {\\n    return formatDate(new Date(parsed));\\n  }\\n\\n  return null;\\n}\\n\\nfunction formatDate(date) {\\n  const y = date.getFullYear();\\n  const m = String(date.getMonth() + 1).padStart(2, '0');\\n  const d = String(date.getDate()).padStart(2, '0');\\n  return `${y}-${m}-${d}`;\\n}\\n\\nfunction calculateDays(start, end) {\\n  const s = new Date(start);\\n  const e = new Date(end);\\n  const diffTime = e.getTime() - s.getTime();\\n  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1;\\n  return diffDays > 0 ? diffDays : 1;\\n}\\n\\nfunction getLeaveTypeThai(type) {\\n  if (type === 'sick') return '🤒 ลาป่วย';\\n  if (type === 'annual') return '✈️ ลาพักร้อน';\\n  if (type === 'personal') return 'ลากิจ';\\n  return type;\\n}\\n\\nfunction getRemainingDays(type) {\\n  if (type === 'sick') return input.total_sick_leave - input.used_sick_leave;\\n  if (type === 'annual') return input.total_annual_leave - input.used_annual_leave;\\n  if (type === 'personal') return input.total_personal_leave - input.used_personal_leave;\\n  return 0;\\n}\\n\\n// 1. Handlers for unregistered users\\nif (!input.employee_id && !messageText.startsWith('/switch ')) {\\n  responseType = 'direct_reply';\\n  replyMessages = [{\\n    \\"type\\": \\"text\\",\\n    \\"text\\": \\"⚠️ คุณยังไม่ได้ลงทะเบียนในระบบบอท HR\\\\nโปรดพิมพ์คำสั่งสลับบัญชีเพื่อทดสอบ เช่น:\\\\n/switch EMP001 (เพื่อสวมบทบาท สมชาย)\\"\\n  }];\\n}\\n// 2. Handler for /switch <employee_code>\\nelse if (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code)) {\\n  const code = (nlp.intent === 'switch_user' && nlp.employee_code) ? nlp.employee_code : messageText.replace('/switch ', '').trim().toUpperCase();\\n  responseType = 'execute_sql';\\n  \\n  sql = `\\n    WITH unbind AS (\\n      UPDATE employees SET line_user_id = NULL WHERE line_user_id = $1\\n    ), bind AS (\\n      UPDATE employees SET line_user_id = $1 WHERE employee_code = $2 RETURNING name, position\\n    )\\n    INSERT INTO user_sessions (line_user_id, current_state, temp_data)\\n    VALUES ($1, 'idle', '{}'::jsonb)\\n    ON CONFLICT (line_user_id) DO UPDATE SET current_state = 'idle', temp_data = '{}'::jsonb\\n    RETURNING (SELECT name FROM bind) AS employee_name, (SELECT position FROM bind) AS employee_position;\\n  `;\\n  params = [userId, code];\\n  \\n  replyMessages = [{\\n    \\"type\\": \\"text\\",\\n    \\"text\\": `🔄 กำลังสลับบัญชี...`\\n  }];\\n}\\n// 3. User is registered - State Machine for Leave Request (Multi-turn Slot Filling)\\nelse if (input.current_state && input.current_state !== 'idle') {\\n  const state = input.current_state;\\n  let tempData = input.temp_data || {};\\n  \\n  if (cleanText === 'ยกเลิก' || nlp.intent === 'general_chat' && cleanText === 'cancel') {\\n    responseType = 'execute_sql';\\n    sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n    params = [userId];\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": \\"❌ ยกเลิกการทำรายการเรียบร้อยแล้ว กลับสู่สถานะปกติ\\"\\n    }];\\n  }\\n  else if (state === 'awaiting_leave_type') {\\n    let leaveType = '';\\n    let leaveTypeThai = '';\\n    if (cleanText.includes('ป่วย') || cleanText === 'sick') {\\n      leaveType = 'sick';\\n      leaveTypeThai = '🤒 ลาป่วย';\\n    } else if (cleanText.includes('พักร้อน') || cleanText === 'annual') {\\n      leaveType = 'annual';\\n      leaveTypeThai = '✈️ ลาพักร้อน';\\n    } else if (cleanText.includes('กิจ') || cleanText === 'personal') {\\n      leaveType = 'personal';\\n      leaveTypeThai = 'ลากิจ';\\n    }\\n    \\n    if (!leaveType) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ ประเภทการลาไม่ถูกต้อง โปรดเลือกประเภทการลา:\\\\n- พิมพ์ \\\\\\"ลาป่วย\\\\\\"\\\\n- พิมพ์ \\\\\\"ลาพักร้อน\\\\\\"\\\\n- พิมพ์ \\\\\\"ลากิจ\\\\\\"\\\\n(หรือพิมพ์ \\\\\\"ยกเลิก\\\\\\" เพื่อออกจากการทำรายการ)\\"\\n      }];\\n    } else {\\n      const rem = getRemainingDays(leaveType);\\n      if (rem <= 0) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n        params = [userId];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากสิทธิ์วันลาหมดแล้ว\\\\n\\\\n- ประเภทการลา: ${leaveTypeThai}\\\\n- คงเหลือ: 0 วัน`\\n        }];\\n      } else {\\n        tempData.leave_type = leaveType;\\n        tempData.leave_type_thai = leaveTypeThai;\\n      \\n      // Check next missing slot\\n      if (!tempData.start_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_start_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n\\\\nโปรดระบุ \\"วันที่เริ่มลาหยุด\\" (เช่น 2026-06-25 หรือพิมพ์ วันนี้ / พรุ่งนี้)`\\n        }];\\n      } else if (!tempData.end_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_end_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n📅 วันที่เริ่มลา: ${tempData.start_date}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26)`\\n        }];\\n      } else if (!tempData.reason) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 ประเภทการลา: ${leaveTypeThai}\\\\n📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\" (เช่น พักผ่อน / มีธุระ)`\\n        }];\\n      } else {\\n        if (!tempData.days && tempData.start_date && tempData.end_date) {\\n          tempData.days = calculateDays(tempData.start_date, tempData.end_date);\\n        }\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (tempData.days > rem) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n          params = [userId];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n          }];\\n        } else {\\n          if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n            }];\\n          } else {\\n            responseType = 'execute_sql';\\n            sql = `\\n              WITH new_leave AS (\\n                INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                RETURNING id\\n              )\\n              UPDATE user_sessions \\n              SET current_state = 'idle', temp_data = '{}'::jsonb \\n              WHERE line_user_id = $1;\\n            `;\\n            params = [\\n              userId,\\n              input.employee_id,\\n              tempData.leave_type,\\n              tempData.start_date,\\n              tempData.end_date,\\n              tempData.days,\\n              tempData.reason\\n            ];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n            }];\\n          }\\n        }\\n      }\\n    }\\n    }\\n  }\\n  else if (state === 'awaiting_start_date') {\\n    const startDate = parseDate(messageText);\\n    if (!startDate) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ วันที่เริ่มไม่ถูกต้อง โปรดระบุฟอร์แมต YYYY-MM-DD (เช่น 2026-06-25) หรือพิมพ์ \\\\\\"วันนี้\\\\\\" / \\\\\\"พรุ่งนี้\\\\\\"\\"\\n      }];\\n    } else {\\n      tempData.start_date = startDate;\\n      \\n      // Check next missing slot\\n      if (!tempData.end_date) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_end_date', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📅 วันที่เริ่มลา: ${startDate}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26 หรือพิมพ์จำนวนวัน เช่น 2 วัน)`\\n        }];\\n      } else {\\n        const days = calculateDays(startDate, tempData.end_date);\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (days > rem) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n          params = [userId];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n          }];\\n        } else {\\n          tempData.days = days;\\n          if (!tempData.reason) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📅 ระยะเวลาลา: ${startDate} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\"`\\n            }];\\n          } else {\\n            if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n              responseType = 'execute_sql';\\n              sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n              params = [userId, JSON.stringify(tempData)];\\n              replyMessages = [{\\n                \\"type\\": \\"text\\",\\n                \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n              }];\\n            } else {\\n              responseType = 'execute_sql';\\n              sql = `\\n                WITH new_leave AS (\\n                  INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                  VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                  RETURNING id\\n                )\\n                UPDATE user_sessions \\n                SET current_state = 'idle', temp_data = '{}'::jsonb \\n                WHERE line_user_id = $1;\\n              `;\\n              params = [\\n                userId,\\n                input.employee_id,\\n                tempData.leave_type,\\n                tempData.start_date,\\n                tempData.end_date,\\n                tempData.days,\\n                tempData.reason\\n              ];\\n              replyMessages = [{\\n                \\"type\\": \\"text\\",\\n                \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n              }];\\n            }\\n          }\\n        }\\n      }\\n    }\\n  }\\n  else if (state === 'awaiting_end_date') {\\n    const endDate = parseDate(messageText, tempData.start_date);\\n    if (!endDate || endDate < tempData.start_date) {\\n      responseType = 'direct_reply';\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": \\"⚠️ วันที่สิ้นสุดไม่ถูกต้อง (ต้องไม่น้อยกว่าวันที่เริ่ม) โปรดระบุแบบ YYYY-MM-DD หรือพิมพ์จำนวนวัน เช่น 1 วัน\\"\\n      }];\\n    } else {\\n      const days = calculateDays(tempData.start_date, endDate);\\n      const rem = getRemainingDays(tempData.leave_type);\\n      if (days > rem) {\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n        params = [userId];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n        }];\\n      } else {\\n        tempData.end_date = endDate;\\n        tempData.days = days;\\n        \\n        if (!tempData.reason) {\\n          responseType = 'execute_sql';\\n          sql = `UPDATE user_sessions SET current_state = 'awaiting_reason', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n          params = [userId, JSON.stringify(tempData)];\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${endDate} (${days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\"`\\n          }];\\n        } else {\\n          if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n            responseType = 'execute_sql';\\n            sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n            params = [userId, JSON.stringify(tempData)];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n            }];\\n          } else {\\n            responseType = 'execute_sql';\\n            sql = `\\n              WITH new_leave AS (\\n                INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n                VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n                RETURNING id\\n              )\\n              UPDATE user_sessions \\n              SET current_state = 'idle', temp_data = '{}'::jsonb \\n              WHERE line_user_id = $1;\\n            `;\\n            params = [\\n              userId,\\n              input.employee_id,\\n              tempData.leave_type,\\n              tempData.start_date,\\n              tempData.end_date,\\n              tempData.days,\\n              tempData.reason\\n            ];\\n            replyMessages = [{\\n              \\"type\\": \\"text\\",\\n              \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n            }];\\n          }\\n        }\\n      }\\n    }\\n  }\\n  else if (state === 'awaiting_reason') {\\n    const reason = messageText;\\n    tempData.reason = reason;\\n    \\n    const rem = getRemainingDays(tempData.leave_type);\\n    if (tempData.days > rem) {\\n      responseType = 'execute_sql';\\n      sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n      params = [userId];\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน\\\\n\\\\nระบบยกเลิกรายการโดยอัตโนมัติ`\\n      }];\\n    } else if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n      // Feature 2: Sick leave > 2 days — ask for medical certificate\\n      tempData.reason = reason;\\n      responseType = 'execute_sql';\\n      sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n      params = [userId, JSON.stringify(tempData)];\\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n      }];\\n    } else {\\n      responseType = 'execute_sql';\\n      \\n      // Save to leave_requests and reset user session in a single transaction\\n      sql = `\\n        WITH new_leave AS (\\n          INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n          VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n          RETURNING id\\n        )\\n        UPDATE user_sessions \\n        SET current_state = 'idle', temp_data = '{}'::jsonb \\n        WHERE line_user_id = $1;\\n      `;\\n      params = [\\n        userId,\\n        input.employee_id,\\n        tempData.leave_type,\\n        tempData.start_date,\\n        tempData.end_date,\\n        tempData.days,\\n        reason\\n      ];\\n      \\n      replyMessages = [{\\n        \\"type\\": \\"text\\",\\n        \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${reason}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n      }];\\n    }\\n  }\\n  else if (state === 'awaiting_medical_cert') {\\n    // Feature 2: Handle medical certificate note submission\\n    const certNote = messageText;\\n    const tdMC = input.temp_data || {};\\n    responseType = 'execute_sql';\\n    sql = `\\n      WITH new_leave AS (\\n        INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n        VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending')\\n        RETURNING id\\n      )\\n      UPDATE user_sessions \\n      SET current_state = 'idle', temp_data = '{}'::jsonb \\n      WHERE line_user_id = $1;\\n    `;\\n    const certReason = tdMC.reason + ' [ใบรับรองแพทย์: ' + certNote + ']';\\n    params = [\\n      userId,\\n      input.employee_id,\\n      tdMC.leave_type,\\n      tdMC.start_date,\\n      tdMC.end_date,\\n      tdMC.days,\\n      certReason\\n    ];\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": `✅ ส่งคำขอลาหยุดเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดคำขอ:\\\\n- ประเภท: ${tdMC.leave_type_thai}\\\\n- ระยะเวลา: ${tdMC.start_date} ถึง ${tdMC.end_date} (${tdMC.days} วัน)\\\\n- เหตุผล: ${tdMC.reason}\\\\n- 🏥 ใบรับรองแพทย์: ${certNote}\\\\n\\\\nคำขอของคุณได้รับการบันทึกเข้าระบบแล้ว และกำลังรอการพิจารณาอนุมัติจากฝ่ายบุคคล (HR)`\\n    }];\\n  }\\n  else if (state === 'display_team_schedule') {\\n    // Feature 1: Display stored team schedule from temp_data (populated previous turn)\\n    responseType = 'execute_sql';\\n    sql = `UPDATE user_sessions SET current_state = 'idle', temp_data = '{}'::jsonb WHERE line_user_id = $1;`;\\n    params = [userId];\\n    \\n    const schedData = input.temp_data || {};\\n    const schedule = Array.isArray(schedData.schedule) ? schedData.schedule : [];\\n    const displayDate = schedData.check_date || '?';\\n    const dept = schedData.department || input.department;\\n    \\n    function ltThai(t) {\\n      if (t === 'sick') return '🤒 ลาป่วย';\\n      if (t === 'annual') return '✈️ ลาพักร้อน';\\n      if (t === 'personal') return '💼 ลากิจ';\\n      return t;\\n    }\\n    \\n    if (schedule.length === 0) {\\n      replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${displayDate}\\\\n\\\\n✅ ไม่มีสมาชิกทีมลาหยุดในวันดังกล่าว` }];\\n    } else {\\n      const lines = schedule.map(s => `• ${s.name} — ${ltThai(s.leave_type)}`).join('\\\\n');\\n      replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${displayDate}\\\\n\\\\nสมาชิกที่ลาหยุด (${schedule.length} คน):\\\\n${lines}` }];\\n    }\\n  }\\n}\\n// 4. NLP Smart Processing (When user is in 'idle' state)\\nelse {\\n  if (nlp.intent === 'request_leave') {\\n    // LLM extracted a leave request! Let's check what variables are already present.\\n    let tempData = {\\n      leave_type: nlp.leave_type || null,\\n      leave_type_thai: nlp.leave_type ? getLeaveTypeThai(nlp.leave_type) : null,\\n      start_date: nlp.start_date || null,\\n      end_date: nlp.end_date || null,\\n      days: nlp.days || null,\\n      reason: nlp.reason || null\\n    };\\n    \\n    // If end_date is present but start_date is not, default start_date to today\\n    const today = new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0];\\n    if (tempData.end_date && !tempData.start_date) {\\n      tempData.start_date = today;\\n    }\\n    \\n    // If start_date is present but end_date is not:\\n    if (tempData.start_date && !tempData.end_date) {\\n      if (tempData.days) {\\n        // Calculate end_date = start_date + days - 1\\n        const start = new Date(tempData.start_date);\\n        const end = new Date(start.getTime() + ((tempData.days - 1) * 24 * 60 * 60 * 1000));\\n        tempData.end_date = end.toISOString().split('T')[0];\\n      } else {\\n        // Default end_date to start_date (1 day)\\n        tempData.end_date = tempData.start_date;\\n        tempData.days = 1;\\n      }\\n    }\\n    \\n    // Recalculate days if start and end are present\\n    if (tempData.start_date && tempData.end_date && !tempData.days) {\\n      tempData.days = calculateDays(tempData.start_date, tempData.end_date);\\n    }\\n    \\n    // Check if we have EVERYTHING to submit immediately\\n    if (tempData.leave_type && tempData.start_date && tempData.end_date && tempData.reason) {\\n      const rem = getRemainingDays(tempData.leave_type);\\n      if (tempData.days > rem) {\\n        responseType = 'direct_reply';\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากวันหยุดคงเหลือไม่พอ\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- จำนวนที่ขอ: ${tempData.days} วัน\\\\n- คงเหลือ: ${rem} วัน`\\n        }];\\n      } else if (tempData.leave_type === 'sick' && tempData.days > 2) {\\n        // Feature 2: NLP direct path — sick leave > 2 days, ask for medical cert\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = 'awaiting_medical_cert', temp_data = $2::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, JSON.stringify(tempData)];\\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `📋 เนื่องจากคุณขอลาป่วยมากกว่า 2 วัน (${tempData.days} วัน)\\\\nกรุณาแจ้งรายละเอียดใบรับรองแพทย์:\\\\n\\\\n- พิมพ์ชื่อโรงพยาบาล/คลินิก และวันที่ออกใบรับรอง\\\\n- หรือพิมพ์ \\"ยังไม่มี\\" หากยังไม่ได้รับใบรับรองแพทย์`\\n        }];\\n      } else {\\n        // Submit immediately!\\n        responseType = 'execute_sql';\\n        sql = `\\n          INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, reason, status)\\n          VALUES ($2::uuid, $3::text, $4::date, $5::date, $6::numeric, $7::text, 'pending');\\n        `;\\n        params = [\\n          userId,\\n          input.employee_id,\\n          tempData.leave_type,\\n          tempData.start_date,\\n          tempData.end_date,\\n          tempData.days,\\n          tempData.reason\\n        ];\\n        \\n        replyMessages = [{\\n          \\"type\\": \\"text\\",\\n          \\"text\\": `✅ ส่งคำขอลาหยุดผ่านระบบ AI สำเร็จเรียบร้อยแล้ว!\\\\n\\\\n📋 รายละเอียดใบลา:\\\\n- ประเภท: ${tempData.leave_type_thai}\\\\n- ระยะเวลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n- เหตุผล: ${tempData.reason}\\\\n\\\\nคำขอได้รับการบันทึกเข้าระบบแล้ว และกำลังรอฝ่ายบุคคล (HR) พิจารณาอนุมัติครับ`\\n        }];\\n      }\\n    } else {\\n      // Check if we have leave_type but days are depleted\\n      if (tempData.leave_type) {\\n        const rem = getRemainingDays(tempData.leave_type);\\n        if (rem <= 0) {\\n          responseType = 'direct_reply';\\n          replyMessages = [{\\n            \\"type\\": \\"text\\",\\n            \\"text\\": `⚠️ ไม่สามารถยื่นคำขอลาได้เนื่องจากสิทธิ์วันลาหมดแล้ว\\\\n\\\\n- ประเภทการลา: ${tempData.leave_type_thai}\\\\n- คงเหลือ: 0 วัน`\\n          }];\\n          \\n          // Automatically append \\"- bot\\" to all text responses, and a footer to all Flex bubbles\\n          if (replyMessages && Array.isArray(replyMessages)) {\\n            replyMessages.forEach(msg => {\\n              if (msg.type === 'text') {\\n                msg.text = msg.text + '\\\\n\\\\n- bot';\\n              }\\n            });\\n          }\\n          \\n          return [{\\n            json: {\\n              userId,\\n              replyToken,\\n              responseType,\\n              replyMessages,\\n              sql: '',\\n              params: []\\n            }\\n          }];\\n        }\\n      }\\n\\n      // Something is missing. Determine the next state to transition to\\n      let nextState = 'awaiting_leave_type';\\n      let promptText = 'กรุณาเลือกประเภทการลาที่ต้องการยื่นหยุดงาน:';\\n      \\n      if (!tempData.leave_type) {\\n        nextState = 'awaiting_leave_type';\\n        // Show buttons\\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        \\n        replyMessages = [{\\n          \\"type\\": \\"flex\\",\\n          \\"altText\\": \\"เลือกประเภทการลาหยุด\\",\\n          \\"contents\\": {\\n            \\"type\\": \\"bubble\\",\\n            \\"body\\": {\\n              \\"type\\": \\"box\\",\\n              \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n              \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": \\"📝 ยื่นใบลาหยุดงาน\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#4f46e5\\" },\\n                { \\"type\\": \\"text\\", \\"text\\": \\"กรุณาเลือกประเภทการลาเพื่อดำเนินการต่อ:\\", \\"size\\": \\"sm\\", \\"color\\": \\"#94a3b8\\", \\"margin\\": \\"md\\", \\"wrap\\": true },\\n                { \\"type\\": \\"separator\\", \\"margin\\": \\"md\\" },\\n                {\\n                  \\"type\\": \\"box\\",\\n                  \\"layout\\": \\"vertical\\",\\n                  \\"margin\\": \\"md\\",\\n                  \\"spacing\\": \\"sm\\",\\n                  \\"contents\\": [\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"🤒 ลาป่วย (Sick Leave)\\", \\"text\\": \\"ลาป่วย\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#ef4444\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"✈️ ลาพักร้อน (Annual Leave)\\", \\"text\\": \\"ลาพักร้อน\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#4f46e5\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"💼 ลากิจ (Personal Leave)\\", \\"text\\": \\"ลากิจ\\" }, \\"style\\": \\"primary\\", \\"color\\": \\"#f59e0b\\" },\\n                    { \\"type\\": \\"button\\", \\"action\\": { \\"type\\": \\"message\\", \\"label\\": \\"❌ ยกเลิกรายการ\\", \\"text\\": \\"ยกเลิก\\" }, \\"style\\": \\"link\\", \\"color\\": \\"#ef4444\\" }\\n                  ]\\n                }\\n              ]\\n            }\\n          }\\n        }];\\n      } else if (!tempData.start_date) {\\n        nextState = 'awaiting_start_date';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n\\\\nโปรดระบุ \\"วันที่เริ่มลาหยุด\\" (เช่น 2026-06-25 หรือพิมพ์ วันนี้ / พรุ่งนี้)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      } else if (!tempData.end_date) {\\n        nextState = 'awaiting_end_date';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n📅 วันเริ่มลา: ${tempData.start_date}\\\\n\\\\nโปรดระบุ \\"วันที่สิ้นสุด\\" (เช่น 2026-06-26 หรือพิมพ์จำนวนวัน เช่น 3 วัน)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      } else if (!tempData.reason) {\\n        nextState = 'awaiting_reason';\\n        promptText = `📋 ประเภทการลา: ${tempData.leave_type_thai}\\\\n📅 ระยะเวลาลา: ${tempData.start_date} ถึง ${tempData.end_date} (${tempData.days} วัน)\\\\n\\\\nโปรดระบุ \\"เหตุผลการลา\\" (เช่น พักผ่อนส่วนตัว / เป็นไข้หวัด)`;\\n        \\n        responseType = 'execute_sql';\\n        sql = `UPDATE user_sessions SET current_state = $2, temp_data = $3::jsonb WHERE line_user_id = $1;`;\\n        params = [userId, nextState, JSON.stringify(tempData)];\\n        replyMessages = [{ \\"type\\": \\"text\\", \\"text\\": promptText }];\\n      }\\n    }\\n  }\\n  else if (nlp.intent === 'check_leave') {\\n    // Trigger case 6: Check Remaining Leave\\n    responseType = 'direct_reply';\\n    const sickRem = input.total_sick_leave - input.used_sick_leave;\\n    const annualRem = input.total_annual_leave - input.used_annual_leave;\\n    const personalRem = input.total_personal_leave - input.used_personal_leave;\\n    \\n    replyMessages = [{\\n      \\"type\\": \\"flex\\",\\n      \\"altText\\": \\"วันลาคงเหลือของคุณ\\",\\n      \\"contents\\": {\\n        \\"type\\": \\"bubble\\",\\n        \\"body\\": {\\n          \\"type\\": \\"box\\",\\n          \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n          \\"contents\\": [\\n            { \\"type\\": \\"text\\", \\"text\\": \\"📊 วันลาคงเหลือของคุณ\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#10b981\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": `คุณ ${input.name}`, \\"size\\": \\"xs\\", \\"color\\": \\"#94a3b8\\", \\"margin\\": \\"xs\\" },\\n            { \\"type\\": \\"separator\\", \\"margin\\": \\"sm\\" },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `🤒 ลาป่วย: คงเหลือ ${sickRem} จาก ${input.total_sick_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#10b981\\", \\"height\\": \\"6px\\", \\"width\\": `${(sickRem/input.total_sick_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `✈️ ลาพักร้อน: คงเหลือ ${annualRem} จาก ${input.total_annual_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#6366f1\\", \\"height\\": \\"6px\\", \\"width\\": `${(annualRem/input.total_annual_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            },\\n            { \\n              \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"margin\\": \\"md\\", \\"contents\\": [\\n                { \\"type\\": \\"text\\", \\"text\\": `💼 ลากิจ: คงเหลือ ${personalRem} จาก ${input.total_personal_leave} วัน`, \\"size\\": \\"sm\\", \\"weight\\": \\"bold\\" },\\n                { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#1e293b\\", \\"height\\": \\"6px\\", \\"cornerRadius\\": \\"3px\\", \\"margin\\": \\"xs\\", \\"contents\\": [\\n                  { \\"type\\": \\"box\\", \\"layout\\": \\"vertical\\", \\"backgroundColor\\": \\"#f59e0b\\", \\"height\\": \\"6px\\", \\"width\\": `${(personalRem/input.total_personal_leave)*100}%`, \\"cornerRadius\\": \\"3px\\", \\"contents\\": [] }\\n                ]}\\n              ] \\n            }\\n          ]\\n        }\\n      }\\n    }];\\n  }\\n  else if (nlp.intent === 'check_team_schedule') {\\n    const todayStr = new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0];\\n    const checkDate = nlp.check_date || todayStr;\\n    responseType = 'execute_sql';\\n    sql = `\\n      SELECT e.name, lr.leave_type, lr.start_date::text, lr.end_date::text\\n      FROM leave_requests lr\\n      JOIN employees e ON lr.employee_id = e.id\\n      WHERE lr.status = 'approved'\\n        AND e.department = $1\\n        AND $2::date BETWEEN lr.start_date AND lr.end_date\\n      ORDER BY e.name;\\n    `;\\n    params = [input.department, checkDate];\\n    replyMessages = [{ type: 'text', text: `🔍 กำลังค้นหาข้อมูลคิวทีม...` }];\\n  }\\n  else if (nlp.intent === 'check_jd') {\\n    // Trigger case 5: Job Description check\\n    responseType = 'direct_reply';\\n    replyMessages = [{\\n      \\"type\\": \\"flex\\",\\n      \\"altText\\": \\"ขอบข่ายงาน (Job Description)\\",\\n      \\"contents\\": {\\n        \\"type\\": \\"bubble\\",\\n        \\"body\\": {\\n          \\"type\\": \\"box\\",\\n          \\"layout\\": \\"vertical\\",\\n          \\"backgroundColor\\": \\"#0f172a\\",\\n          \\"contents\\": [\\n            { \\"type\\": \\"text\\", \\"text\\": \\"📋 ขอบข่ายงานของคุณ\\", \\"weight\\": \\"bold\\", \\"size\\": \\"lg\\", \\"color\\": \\"#6366f1\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": input.name, \\"weight\\": \\"bold\\", \\"size\\": \\"md\\", \\"margin\\": \\"md\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": `${input.position} • แผนก ${input.department}`, \\"size\\": \\"xs\\", \\"color\\": \\"#94a3b8\\" },\\n            { \\"type\\": \\"separator\\", \\"margin\\": \\"md\\" },\\n            { \\"type\\": \\"text\\", \\"text\\": input.job_description, \\"size\\": \\"sm\\", \\"wrap\\": true, \\"margin\\": \\"md\\", \\"color\\": \\"#cbd5e1\\" }\\n          ]\\n        }\\n      }\\n    }];\\n  }\\n  else {\\n    // Default Help menu\\n    responseType = 'direct_reply';\\n    replyMessages = [{\\n      \\"type\\": \\"text\\",\\n      \\"text\\": `สวัสดีครับคุณ ${input.name} ตำแหน่ง ${input.position}\\\\nโปรดระบุงานที่ต้องการจากตัวเลือกด้านล่าง:\\\\n\\\\n- พิมพ์ \\"ลา\\" เพื่อยื่นใบลาหยุดงาน\\\\n- พิมพ์ \\"วันลา\\" เพื่อเช็คสิทธิ์วันลาคงเหลือ\\\\n- พิมพ์ \\"job description\\" เพื่อขอดูขอบข่ายงาน\\\\n- พิมพ์ \\"คิวทีม\\" เพื่อเช็คตารางลาของทีม\\\\n- พิมพ์ \\"/switch <รหัสพนักงาน>\\" เพื่อสลับตัวตน` \\n    }];\\n  }\\n}\\n// Automatically append \\"- bot\\" to all text responses, and a footer to all Flex bubbles\\nif (replyMessages && Array.isArray(replyMessages)) {\\n  replyMessages.forEach(msg => {\\n    if (msg.type === 'text') {\\n      msg.text = msg.text + '\\\\n\\\\n- bot';\\n    } else if (msg.type === 'flex') {\\n      try {\\n        const bubble = msg.contents;\\n        if (bubble && bubble.type === 'bubble') {\\n          if (!bubble.footer) {\\n            bubble.footer = {\\n              \\"type\\": \\"box\\",\\n              \\"layout\\": \\"vertical\\",\\n              \\"contents\\": [\\n                {\\n                  \\"type\\": \\"text\\",\\n                  \\"text\\": \\"- bot\\",\\n                  \\"size\\": \\"xs\\",\\n                  \\"color\\": \\"#94a3b8\\",\\n                  \\"align\\": \\"end\\"\\n                }\\n              ]\\n            };\\n          } else if (bubble.footer.contents) {\\n            bubble.footer.contents.push({\\n              \\"type\\": \\"text\\",\\n              \\"text\\": \\"- bot\\",\\n              \\"size\\": \\"xs\\",\\n              \\"color\\": \\"#94a3b8\\",\\n              \\"align\\": \\"end\\"\\n            });\\n          }\\n        }\\n      } catch (e) {\\n        console.error('Failed to append bot footer to flex:', e);\\n      }\\n    }\\n  });\\n}\\n\\n// Feature 3: Manager notification flag\\nconst isLeaveSubmission = sql.includes('INSERT INTO leave_requests');\\n\\nreturn [{\\n  json: {\\n    userId,\\n    replyToken,\\n    responseType,\\n    replyMessages,\\n    sql,\\n    params,\\n    isLeaveSubmission,\\n    employeeId: input.employee_id || null,\\n    employeeName: input.name || null,\\n    department: input.department || null,\\n    sqlType: (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code) ? 'switch' : ((input.current_state && input.current_state !== 'idle') ? 'other' : (nlp.intent === 'check_team_schedule' ? 'check_team_schedule' : 'other'))),\\n    sqlMeta: {\\n      checkDate: (nlp.intent === 'check_team_schedule' ? (nlp.check_date || new Date(new Date().getTime() + (7 * 60 * 60 * 1000)).toISOString().split('T')[0]) : null),\\n      department: input.department || null,\\n      employeeCode: (cleanText.startsWith('/switch ') || messageText.startsWith('/switch ') || (nlp.intent === 'switch_user' && nlp.employee_code) ? (nlp.employee_code || cleanText.replace('/switch ', '').trim().toUpperCase()) : null)\\n    }\\n  }\\n}];\\n"},"id":"code-controller","name":"Core Controller","type":"n8n-nodes-base.code","typeVersion":2,"position":[640,256]},{"parameters":{"conditions":{"string":[{"value1":"={{ $json.responseType }}","value2":"execute_sql"}]}},"id":"switch-response","name":"Switch Response Mode","type":"n8n-nodes-base.if","typeVersion":1,"position":[864,256]},{"parameters":{"operation":"executeQuery","query":"{{$json.sql}}","options":{"queryReplacement":"={{ $('Core Controller').first().json.params }}"}},"id":"pg-execute-actions","name":"PG: Execute SQL Action","type":"n8n-nodes-base.postgres","typeVersion":2,"position":[1088,192],"credentials":{"postgres":{"id":"vwf7u64OuSi5ejWs","name":"Postgres HR - localhost:5432"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"},{"name":"Authorization","value":"=Bearer {{ $env.HR_LINE_CHANNEL_ACCESS_TOKEN }}"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": \\"{{ $('Format SQL Result').first().json.replyToken }}\\",\\n  \\"messages\\": {{ JSON.stringify($('Format SQL Result').first().json.replyMessages) }}\\n}","options":{}},"id":"http-line-reply","name":"LINE: Reply Message","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[1536,256]},{"parameters":{"method":"POST","url":"http://localhost:11434/api/generate","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"qwen2.5:7b\\",\\n  \\"prompt\\": \\"You are an HR Assistant Bot. Parse the user's Thai message and extract structured fields in JSON format.\\\\nCurrent date today is: {{ new Date(new Date().getTime() + 7 * 3600 * 1000).toISOString().split('T')[0] }} (Bangkok Time).\\\\n\\\\nAnalyze the input text and output a JSON object with these EXACT keys:\\\\n{\\\\n  \\\\\\"intent\\\\\\": \\\\\\"request_leave\\\\\\" | \\\\\\"check_leave\\\\\\" | \\\\\\"check_jd\\\\\\" | \\\\\\"switch_user\\\\\\" | \\\\\\"check_team_schedule\\\\\\" | \\\\\\"general_chat\\\\\\",\\\\n  \\\\\\"leave_type\\\\\\": \\\\\\"sick\\\\\\" | \\\\\\"annual\\\\\\" | \\\\\\"personal\\\\\\" | null,\\\\n  \\\\\\"start_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null,\\\\n  \\\\\\"end_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null,\\\\n  \\\\\\"days\\\\\\": number | null,\\\\n  \\\\\\"reason\\\\\\": \\\\\\"Thai string\\\\\\" | null,\\\\n  \\\\\\"employee_code\\\\\\": \\\\\\"EMPxxx\\\\\\" | null,\\\\n  \\\\\\"check_date\\\\\\": \\\\\\"YYYY-MM-DD\\\\\\" | null\\\\n}\\\\n\\\\nGuidelines:\\\\n1. Intent:\\\\n   - \\\\\\"request_leave\\\\\\": User wants to request leave (e.g., \\\\\\"ขอลา\\\\\\", \\\\\\"ป่วย\\\\\\", \\\\\\"ลากิจ\\\\\\", \\\\\\"พักร้อน\\\\\\").\\\\n   - \\\\\\"check_leave\\\\\\": User wants to check remaining leave days (e.g., \\\\\\"วันลาคงเหลือ\\\\\\", \\\\\\"สิทธิ์วันหยุด\\\\\\").\\\\n   - \\\\\\"check_jd\\\\\\": User wants to check job description (e.g., \\\\\\"งานของฉัน\\\\\\", \\\\\\"job description\\\\\\").\\\\n   - \\\\\\"switch_user\\\\\\": User wants to switch account (e.g., \\\\\\"/switch EMP001\\\\\\", \\\\\\"สลับผู้ใช้เป็น EMP002\\\\\\").\\\\n   - \\\\\\"check_team_schedule\\\\\\": User wants to check who is on leave in their department/team (e.g. \\\\\\"ใครลาบ้าง\\\\\\", \\\\\\"พรุ่งนี้มีใครหยุดไหม\\\\\\", \\\\\\"เช็คตารางลาทีม\\\\\\"). Extract the date to check as YYYY-MM-DD in check_date. Default to today if no date is specified.\\\\n   - \\\\\\"general_chat\\\\\\": Any other text.\\\\n2. Relative and Absolute Dates parsing (relative to today):\\\\n   - \\\\\\"วันนี้\\\\\\" -> today's date\\\\n   - \\\\\\"พรุ่งนี้\\\\\\" -> today's date + 1 day\\\\n   - \\\\\\"เมื่อวาน\\\\\\" / \\\\\\"เมื่อวานนี้\\\\\\" -> today's date - 1 day\\\\n   - \\\\\\"วานซืน\\\\\\" / \\\\\\"เมื่อวานซืน\\\\\\" -> today's date - 2 days\\\\n   - \\\\\\"มะรืน\\\\\\" / \\\\\\"มะรืนนี้\\\\\\" -> today's date + 2 days\\\\n   - \\\\\\"วันจันทร์อาทิตย์หน้า\\\\\\" -> next Monday\\\\n   - \\\\\\"วันอาทิตย์เดือนหน้า\\\\\\" -> first Sunday of next month\\\\n   - \\\\\\"20 สิงหา\\\\\\" / \\\\\\"20 สิงหาคม\\\\\\" / \\\\\\"20 สิงหาคม ปีนี้\\\\\\" -> YYYY-08-20 (using current year)\\\\n   - \\\\\\"20 02\\\\\\" / \\\\\\"20/02\\\\\\" -> YYYY-02-20 (using current year)\\\\n   - \\\\\\"อีก 3 วันถัดไป\\\\\\" starting tomorrow -> start_date: tomorrow, end_date: 2 days after tomorrow, days: 3\\\\n   - If Buddhist Era (พ.ศ. / B.E. e.g. 2569) is mentioned, convert to Gregorian (e.g. 2026) by subtracting 543.\\\\n3. Output ONLY raw JSON. No markdown, no formatting, no extra text.\\\\n\\\\nUser text: \\\\\\"{{ ($('Parse LINE Event').first().json.messageText || '').replace(/\\\\\\\\/g, '\\\\\\\\\\\\\\\\').replace(/\\\\\\"/g, '\\\\\\\\\\\\\\"') }}\\\\\\"\\\\nJSON Output:\\",\\n  \\"stream\\": false,\\n  \\"options\\": {\\n    \\"temperature\\": 0.1\\n  }\\n}","options":{}},"id":"ollama-parse-intent","name":"Ollama: Parse Intent","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[416,256]},{"parameters":{"jsCode":"\\nconst data = $('Core Controller').first().json;\\nif (!data.isLeaveSubmission) return [];\\n\\n// Send LINE push to manager via notify-manager API\\nconst LINE_TOKEN = 'Irn1vjQBmg/DV0/8s7bSFAyqZETfWKV1lGNBAAMgq7xL78hlbs3fMK0QG+Rqh3MW9/G0fQuV/a2nYIyZoeelGM9p8pYfgZpb7I91nTT3g05e3Oqa3cP0xkw6clx5mI55v64cCiYPdU1xDpB7bQgBsQdB04t89/1O/w1cDnyilFU=';\\n\\ntry {\\n  const res = await fetch('http://localhost:3000/api/notify-manager', {\\n    method: 'POST',\\n    headers: { 'Content-Type': 'application/json' },\\n    body: JSON.stringify({\\n      employeeId: data.employeeId,\\n      employeeName: data.employeeName,\\n      department: data.department,\\n      lineToken: LINE_TOKEN\\n    })\\n  });\\n  const result = await res.json();\\n  return [{ json: { notified: true, result } }];\\n} catch(e) {\\n  console.error('Manager notify failed:', e.message);\\n  return [{ json: { notified: false, error: e.message } }];\\n}\\n        "},"id":"code-notify-manager","name":"Notify Manager","type":"n8n-nodes-base.code","typeVersion":2,"position":[1760,256]},{"parameters":{"jsCode":"\\nlet replyToken = '';\\nlet replyMessages = [];\\nlet userId = '';\\nlet isLeaveSubmission = false;\\nlet employeeId = null;\\nlet employeeName = null;\\nlet department = null;\\n\\ntry {\\n  const core = $('Core Controller').first().json;\\n  replyToken = core.replyToken;\\n  replyMessages = core.replyMessages || [];\\n  userId = core.userId;\\n  isLeaveSubmission = core.isLeaveSubmission || false;\\n  employeeId = core.employeeId || null;\\n  employeeName = core.employeeName || null;\\n  department = core.department || null;\\n\\n  if (core.responseType === 'execute_sql') {\\n    let pgRows = [];\\n    try {\\n      pgRows = $input.all().map(item => item.json);\\n    } catch (e) {\\n      pgRows = $('PG: Execute SQL Action').all().map(item => item.json);\\n    }\\n    \\n    if (core.sqlType === 'check_team_schedule') {\\n      const checkDate = core.sqlMeta.checkDate;\\n      const dept = core.sqlMeta.department || 'ไม่ระบุ';\\n      \\n      const schedule = pgRows || [];\\n      \\n      function ltThai(t) {\\n        if (t === 'sick') return '🤒 ลาป่วย';\\n        if (t === 'annual') return '✈️ ลาพักร้อน';\\n        if (t === 'personal') return '💼 ลากิจ';\\n        return t;\\n      }\\n      \\n      if (schedule.length === 0 || (schedule.length === 1 && schedule[0].name === null)) {\\n        replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${checkDate}\\\\n\\\\n✅ ไม่มีสมาชิกทีมลาหยุดในวันดังกล่าว\\\\n\\\\n- bot` }];\\n      } else {\\n        const lines = schedule.map(s => `• ${s.name} — ${ltThai(s.leave_type)}`).join('\\\\n');\\n        replyMessages = [{ type: 'text', text: `🗓️ คิวทีม ${dept}\\\\n📅 วันที่ ${checkDate}\\\\n\\\\nสมาชิกที่ลาหยุด (${schedule.length} คน):\\\\n${lines}\\\\n\\\\n- bot` }];\\n      }\\n    }\\n    else if (core.sqlType === 'switch') {\\n      const row = pgRows[0] || {};\\n      const newName = row.employee_name;\\n      const newPos = row.employee_position;\\n      \\n      if (!newName) {\\n        replyMessages = [{\\n          type: 'text',\\n          text: `❌ ไม่พบรหัสพนักงาน ${core.sqlMeta.employeeCode} ในระบบ โปรดตรวจสอบความถูกต้อง\\\\n\\\\n- bot`\\n        }];\\n      } else {\\n        replyMessages = [{\\n          type: 'text',\\n          text: `✅ สลับบัญชีสำเร็จ!\\\\n\\\\nสวัสดีครับคุณ ${newName} ตำแหน่ง ${newPos}\\\\nโปรดระบุงานที่ต้องการจากตัวเลือกด้านล่าง:\\\\n\\\\n- พิมพ์ \\"ลา\\" เพื่อยื่นใบลาหยุดงาน\\\\n- พิมพ์ \\"วันลา\\" เพื่อเช็คสิทธิ์วันลาคงเหลือ\\\\n- พิมพ์ \\"job description\\" เพื่อขอดูขอบข่ายงาน\\\\n- พิมพ์ \\"คิวทีม\\" เพื่อเช็คตารางลาของทีม\\\\n- พิมพ์ \\"/switch <รหัสพนักงาน>\\" เพื่อสลับตัวตน\\\\n\\\\n- bot`\\n        }];\\n      }\\n    }\\n  }\\n} catch (err) {\\n  console.error('Format SQL Result failed:', err);\\n}\\n\\nreturn [{\\n  json: {\\n    userId,\\n    replyToken,\\n    replyMessages,\\n    isLeaveSubmission,\\n    employeeId,\\n    employeeName,\\n    department\\n  }\\n}];\\n        "},"id":"code-format-sql","name":"Format SQL Result","type":"n8n-nodes-base.code","typeVersion":2,"position":[1312,256]}]	{"LINE Webhook":{"main":[[{"node":"Respond 200 OK","type":"main","index":0},{"node":"Parse LINE Event","type":"main","index":0}]]},"Parse LINE Event":{"main":[[{"node":"PG: Get Employee & Session","type":"main","index":0}]]},"PG: Get Employee & Session":{"main":[[{"node":"Ollama: Parse Intent","type":"main","index":0}]]},"Core Controller":{"main":[[{"node":"Switch Response Mode","type":"main","index":0}]]},"Switch Response Mode":{"main":[[{"node":"PG: Execute SQL Action","type":"main","index":0}],[{"node":"Format SQL Result","type":"main","index":0}]]},"PG: Execute SQL Action":{"main":[[{"node":"Format SQL Result","type":"main","index":0}]]},"Ollama: Parse Intent":{"main":[[{"node":"Core Controller","type":"main","index":0}]]},"LINE: Reply Message":{"main":[[{"node":"Notify Manager","type":"main","index":0}]]},"Format SQL Result":{"main":[[{"node":"LINE: Reply Message","type":"main","index":0}]]}}	\N	t	\N	[]
9a290dc3-4ead-4606-adec-2f3df5650125	TL2qrOygnWKY69xe	Fluke Jesadakorn	2026-06-23 19:26:43.432+07	2026-06-23 19:26:43.432+07	[{"parameters":{"jsCode":"// Normalize - Smart Router wrapped body in _body\\nconst wrapped = $input.first().json;\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst docNo = (body.doc_no || '').toString().trim() || null;\\nconst fileName = (body.filename || body.file_name || 'unknown').toString();\\nconst fileType = (body.file_type || 'unknown').toString();\\nconst category = body.category || null;\\nconst status = body.status || 'registered';\\nconst lineUserId = body.line_user_id || null;\\nconst lineMessageId = body.line_message_id || null;\\nconst lineGroupId = body.line_group_id || null;\\nconst storageBucket = body.storage_bucket || null;\\nconst storagePath = body.storage_path || null;\\nconst sizeBytes = (body.size_bytes === '' || body.size_bytes === undefined) ? null : Number(body.size_bytes);\\nconst chunkCount = (body.chunk_count === '' || body.chunk_count === undefined) ? 0 : Number(body.chunk_count);\\nconst source = body.source || 'api';\\nconst metadata = body.metadata ? JSON.stringify(body.metadata) : null;\\nreturn [{ json: {\\n  doc_no: docNo, file_name: fileName, file_type: fileType,\\n  category, status, line_user_id: lineUserId, line_message_id: lineMessageId,\\n  line_group_id: lineGroupId, storage_bucket: storageBucket,\\n  storage_path: storagePath, size_bytes: sizeBytes, chunk_count: chunkCount,\\n  source, metadata, needs_generate: !docNo\\n}}];\\n"},"id":"code-prep-reg","name":"Prep Registry Row","type":"n8n-nodes-base.code","position":[2288,896],"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"SELECT 'DOC-' || to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD') || '-' || lpad(next_doc_seq()::text, 3, '0') AS doc_no","options":{}},"id":"pg-gen-seq","name":"PG: Get Next Seq","type":"n8n-nodes-base.postgres","position":[2736,816],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"INSERT INTO contracts (doc_no, file_name, file_type, category, status, line_user_id, line_group_id, line_message_id, storage_bucket, storage_path, size_bytes, chunk_count, source, metadata) VALUES ('{{ ($('Prep Registry Row').item.json.needs_generate ? $('PG: Get Next Seq').item.json.doc_no : $('Prep Registry Row').item.json.doc_no).replace(/'/g, \\"''\\") }}', '{{ $('Prep Registry Row').item.json.file_name.replace(/'/g, \\"''\\") }}', '{{ $('Prep Registry Row').item.json.file_type.replace(/'/g, \\"''\\") }}', {{ $('Prep Registry Row').item.json.category ? \\"'\\" + $('Prep Registry Row').item.json.category.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, '{{ $('Prep Registry Row').item.json.status.replace(/'/g, \\"''\\") }}', {{ $('Prep Registry Row').item.json.line_user_id ? \\"'\\" + $('Prep Registry Row').item.json.line_user_id.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.line_group_id ? \\"'\\" + $('Prep Registry Row').item.json.line_group_id.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.line_message_id ? \\"'\\" + $('Prep Registry Row').item.json.line_message_id.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.storage_bucket ? \\"'\\" + $('Prep Registry Row').item.json.storage_bucket.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.storage_path ? \\"'\\" + $('Prep Registry Row').item.json.storage_path.replace(/'/g, \\"''\\") + \\"'\\" : \\"NULL\\" }}, {{ $('Prep Registry Row').item.json.size_bytes === null ? \\"NULL\\" : $('Prep Registry Row').item.json.size_bytes }}, {{ $('Prep Registry Row').item.json.chunk_count }}, '{{ $('Prep Registry Row').item.json.source.replace(/'/g, \\"''\\") }}', {{ $('Prep Registry Row').item.json.metadata ? \\"'\\" + $('Prep Registry Row').item.json.metadata.replace(/'/g, \\"''\\") + \\"'::jsonb\\" : \\"NULL\\" }}) ON CONFLICT (doc_no) DO UPDATE SET file_name = EXCLUDED.file_name, file_type = EXCLUDED.file_type, category = EXCLUDED.category, status = EXCLUDED.status, updated_at = now(), metadata = COALESCE(EXCLUDED.metadata, contracts.metadata) RETURNING id, doc_no, file_name, file_type, status, uploaded_at;","options":{}},"id":"pg-insert-doc","name":"PG: Insert/Update Document","type":"n8n-nodes-base.postgres","position":[2960,896],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"respondWith":"json","responseBody":"={{ ({ ok: true, doc: $('PG: Insert/Update Document').first().json, generated: $('Prep Registry Row').item.json.needs_generate }) }}","options":{}},"id":"resp-reg","name":"Respond Registry","type":"n8n-nodes-base.respondToWebhook","position":[3184,896],"typeVersion":1},{"parameters":{"jsCode":"// Parse stats request - Smart Router wrapped body in _body\\nconst wrapped = $input.first().json;\\nconst body = wrapped._body || wrapped.body || wrapped;\\nconst message = (body.message || body.text || '').toString().toLowerCase();\\nconst keywords = ['สรุปผล', 'สถิติ', 'stats', 'summary', 'รายงาน', 'list', 'ทั้งหมด', 'all'];\\nconst matched = keywords.find(k => message.includes(k.toLowerCase()));\\nconst isStats = !!matched || body.mode === 'stats';\\nconst docNo = body.doc_no || null;\\nconst days = parseInt(String(body.days != null ? body.days : '7'), 10);\\nreturn [{ json: {\\n  is_stats: isStats,\\n  doc_no: docNo,\\n  days: isNaN(days) ? 7 : days\\n}}];\\n"},"id":"code-parse-stats","name":"Parse Stats Request","type":"n8n-nodes-base.code","position":[2288,1280],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"boolean","operation":"true","singleValue":true},"leftValue":"={{ $json.is_stats }}","rightValue":true}]}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"not_stats"}},"id":"sw-stats","name":"Is stats?","type":"n8n-nodes-base.switch","position":[2512,1280],"typeVersion":3.2},{"parameters":{"operation":"executeQuery","query":"WITH params AS (SELECT ({{ $('Parse Stats Request').item.json.days }})::int AS days), base AS (  SELECT * FROM contracts, params   WHERE uploaded_at >= now() - (params.days || ' days')::interval), agg AS (  SELECT     (SELECT COUNT(*) FROM base) AS total,     (SELECT COUNT(*) FROM base WHERE status='ready') AS ready,     (SELECT COUNT(*) FROM base WHERE status='pending') AS pending,     (SELECT COUNT(*) FROM base WHERE status='failed') AS failed,     (SELECT COUNT(*) FROM base WHERE status='registered') AS registered,     (SELECT COUNT(*) FROM base WHERE uploaded_at::date = CURRENT_DATE) AS today_count ) SELECT row_to_json(agg) AS summary, (SELECT json_agg(t) FROM (SELECT file_type, COUNT(*) AS cnt FROM base GROUP BY file_type ORDER BY cnt DESC LIMIT 5) t) AS by_type, (SELECT json_agg(t) FROM (SELECT category, COUNT(*) AS cnt FROM base WHERE category IS NOT NULL GROUP BY category ORDER BY cnt DESC LIMIT 5) t) AS by_category, (SELECT json_agg(t) FROM (SELECT doc_no, file_name, file_type, status, uploaded_at FROM base ORDER BY uploaded_at DESC LIMIT 5) t) AS recent FROM agg;","options":{}},"id":"pg-stats","name":"PG: Aggregate Stats","type":"n8n-nodes-base.postgres","position":[2736,1200],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"const r = ($('PG: Aggregate Stats').first().json || {});\\nconst summary = r.summary || {};\\nconst days = $('Parse Stats Request').item.json.days;\\nconst lines = [];\\nlines.push(`📊 สรุปเอกสาร (ย้อนหลัง ${days} วัน)`);\\nlines.push(`• ทั้งหมด: ${summary.total ?? 0} ฉบับ`);\\nlines.push(`• วันนี้: ${summary.today_count ?? 0} ฉบับ`);\\nlines.push(`• registered: ${summary.registered ?? 0} | ready: ${summary.ready ?? 0} | pending: ${summary.pending ?? 0} | failed: ${summary.failed ?? 0}`);\\nconst byType = r.by_type || [];\\nif (byType.length) {\\n  lines.push('');\\n  lines.push('— แยกตามประเภท —');\\n  for (const t of byType) lines.push(`  • ${t.file_type || 'unknown'}: ${t.cnt}`);\\n}\\nconst byCat = r.by_category || [];\\nif (byCat.length) {\\n  lines.push('');\\n  lines.push('— แยกตามหมวด —');\\n  for (const c of byCat) lines.push(`  • ${c.category || 'ไม่ระบุ'}: ${c.cnt}`);\\n}\\nconst recent = r.recent || [];\\nif (recent.length) {\\n  lines.push('');\\n  lines.push('— 5 ฉบับล่าสุด —');\\n  for (const d of recent) {\\n    const dt = new Date(d.uploaded_at).toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' });\\n    lines.push(`  • ${d.doc_no} | ${d.file_name} [${d.status}] @ ${dt}`);\\n  }\\n}\\nreturn [{ json: { summary_text: lines.join('\\\\n'), raw: r } }];\\n"},"id":"code-format-stats","name":"Format Stats Text","type":"n8n-nodes-base.code","position":[2960,1200],"typeVersion":2},{"parameters":{"respondWith":"json","responseBody":"={{ ({ ok: true, summary_text: $('Format Stats Text').first().json.summary_text, raw: $('Format Stats Text').first().json.raw, days: $('Parse Stats Request').item.json.days }) }}","options":{}},"id":"resp-stats","name":"Respond Stats","type":"n8n-nodes-base.respondToWebhook","position":[3184,1200],"typeVersion":1},{"parameters":{"respondWith":"json","responseBody":"={{ ({ ok: false, is_stats: false, message: 'ไม่พบคำสั่งสถิติ — ส่ง message ที่มีคำว่า สรุปผล/สถิติ/stats/summary/รายงาน/list/all หรือระบุ mode=stats' }) }}","options":{}},"id":"resp-other","name":"Respond Not Stats","type":"n8n-nodes-base.respondToWebhook","position":[3184,1392],"typeVersion":1},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"boolean","operation":"true","singleValue":true},"leftValue":"={{ $json.needs_generate }}","rightValue":true}]},"renameOutput":true,"outputKey":"generate"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"boolean","operation":"false","singleValue":true},"leftValue":"={{ $json.needs_generate }}","rightValue":false}]},"renameOutput":true,"outputKey":"passthrough"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"no_generate"}},"id":"sw-needs-gen","name":"Needs generate?","type":"n8n-nodes-base.switch","position":[2512,880],"typeVersion":3.2},{"parameters":{"jsCode":"// Passthrough: re-emit Prep Registry Row's payload as the resolved doc_no\\nreturn [{ json: { ...$('Prep Registry Row').first().json, needs_generate: false, doc_no: $('Prep Registry Row').first().json.doc_no } }];\\n"},"id":"code-passthrough","name":"Passthrough (use provided doc_no)","type":"n8n-nodes-base.code","position":[2736,1008],"typeVersion":2},{"parameters":{"jsCode":"// Parse - Smart Router wrapped query in _query, body in _body\\nconst wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\n// Read query/q from either URL query OR body\\nconst query = (q.q || body.q || '').toString().trim();\\n// Read mode from either URL query OR body\\nlet mode = (q.mode || body.mode || '').toString();\\nif (!mode) mode = query ? 'vector' : 'list';\\nif (mode !== 'list' && mode !== 'vector') mode = 'list';\\nconst limit = parseInt(q.limit || body.limit || '20', 10);\\nconst safeLimit = isNaN(limit) ? 20 : limit;\\nreturn [{ json: { \\n  query, mode, limit: safeLimit,\\n  list_params: [query, safeLimit],\\n  vector_params: [[], safeLimit]\\n}}];\\n"},"id":"code-parse-search","name":"Parse Search","type":"n8n-nodes-base.code","position":[1392,1664],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json.mode }}","rightValue":"list"}]},"renameOutput":true,"outputKey":"list"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json.mode }}","rightValue":"vector"}]},"renameOutput":true,"outputKey":"vector"}]},"options":{}},"id":"sw-mode","name":"Mode Switch","type":"n8n-nodes-base.switch","position":[1616,1664],"typeVersion":3.2},{"parameters":{"operation":"executeQuery","query":"SELECT doc_no, file_name, file_type, category, status, source, (SELECT COUNT(*) FROM contract_chunks WHERE contract_id = c.id) AS chunk_count, uploaded_at FROM contracts c WHERE (($1::text IS NULL OR $1 = '') OR LOWER(file_name) LIKE '%' || LOWER($1) || '%' OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%') ORDER BY uploaded_at DESC LIMIT $2::int","options":{"queryReplacement":"={{ $json.list_params }}"}},"id":"pg-list","name":"PG: List Docs","type":"n8n-nodes-base.postgres","position":[2288,1584],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || 'http://127.0.0.1:11434') }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"bge-m3\\",\\n  \\"input\\": {{ JSON.stringify($('Parse Search').item.json.query) }}\\n}","options":{"response":{"response":{"neverError":true}},"timeout":30000}},"id":"embed-query","name":"Embed Query","type":"n8n-nodes-base.httpRequest","position":[1840,1776],"typeVersion":4.2},{"parameters":{"operation":"executeQuery","query":"SELECT c.doc_no, c.file_name, ch.chunk_index, ch.content, 1 - (ch.embedding <=> $1::vector) AS similarity FROM contract_chunks ch JOIN contracts c ON c.id = ch.contract_id WHERE ch.embedding IS NOT NULL ORDER BY ch.embedding <=> $1::vector LIMIT $2::int","options":{"queryReplacement":"={{ $json.vector_params }}"}},"id":"pg-vector","name":"PG: Vector Search","type":"n8n-nodes-base.postgres","position":[2288,1776],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"\\n// === Executive Summary Renderer ===\\nconst items = $input.all();\\nconst mode = $('Parse Search').item.json.mode;\\nconst query = $('Parse Search').item.json.query;\\nconst limit = $('Parse Search').item.json.limit || 20;\\n\\nlet docs = [], results = [], stats = {}, daily = [], recent = [], byStatus = [];\\n\\ntry {\\n  if (mode === 'vector') {\\n    const v = $('PG: Vector Search').all() || [];\\n    results = v.map(i => i.json);\\n  } else {\\n    const l = $('PG: List Docs').all() || [];\\n    docs = l.map(i => i.json);\\n  }\\n  // Daily Activity now returns { stats: {total,ready,...}, daily: [{day,cnt}] }\\n  const dailyRows = ($('PG: Daily Activity').all() || []).map(i => i.json);\\n  if (dailyRows.length) {\\n    const first = dailyRows[0];\\n    stats = first.stats || {};\\n    daily = first.daily || [];\\n  } else {\\n    stats = { total: 0, ready: 0, registered: 0, pending: 0, failed: 0, chunks: 0 };\\n    daily = [];\\n  }\\n  recent = ($('PG: Recent Activity').all() || []).map(i => i.json);\\n  byStatus = ($('PG: By Status').all() || []).map(i => i.json);\\n} catch (e) {\\n  stats = { total: 0, ready: 0, registered: 0, pending: 0, failed: 0, chunks: 0 };\\n  daily = [];\\n}\\n\\nconst escapeHtml = (s) => String(s == null ? '' : s).replace(/[&<>\\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\\"':'&quot;',\\"'\\":'&#39;'}[c]));\\nconst fmtNum = (n) => n == null ? '?' : Number(n).toLocaleString('th-TH');\\nconst fmtPct = (n) => n == null ? '?' : (Number(n) * 100).toFixed(0) + '%';\\n\\n// ===== Executive Summary KPIs =====\\nconst kpiCards = `\\n<div class=\\"kpi-row\\">\\n  <div class=\\"kpi-card kpi-primary\\">\\n    <div class=\\"kpi-label\\">📄 เอกสารทั้งหมด</div>\\n    <div class=\\"kpi-value\\">${fmtNum(stats.total)}</div>\\n    <div class=\\"kpi-sub\\">${fmtNum(stats.chunks)} chunks</div>\\n  </div>\\n  <div class=\\"kpi-card kpi-success\\">\\n    <div class=\\"kpi-label\\">✅ พร้อมใช้งาน</div>\\n    <div class=\\"kpi-value\\">${fmtNum(stats.ready)}</div>\\n    <div class=\\"kpi-sub\\">${fmtPct(stats.total ? stats.ready / stats.total : 0)} ของทั้งหมด</div>\\n  </div>\\n  <div class=\\"kpi-card kpi-warn\\">\\n    <div class=\\"kpi-label\\">⏳ กำลังประมวลผล</div>\\n    <div class=\\"kpi-value\\">${fmtNum((Number(stats.registered)||0) + (Number(stats.pending)||0))}</div>\\n    <div class=\\"kpi-sub\\">registered: ${fmtNum(stats.registered)} · pending: ${fmtNum(stats.pending)}</div>\\n  </div>\\n  <div class=\\"kpi-card kpi-danger\\">\\n    <div class=\\"kpi-label\\">❌ ล้มเหลว</div>\\n    <div class=\\"kpi-value\\">${fmtNum(stats.failed)}</div>\\n    <div class=\\"kpi-sub\\">${fmtPct(stats.total ? stats.failed / stats.total : 0)} ของทั้งหมด</div>\\n  </div>\\n</div>`;\\n\\n// ===== Daily Activity Chart =====\\nlet chartHtml = '<div class=\\"empty-mini\\">ยังไม่มีข้อมูล</div>';\\nif (daily && daily.length) {\\n  const maxCnt = Math.max(...daily.map(d => Number(d.cnt)||0), 1);\\n  const bars = daily.map(d => {\\n    const h = Math.max(2, Math.round((Number(d.cnt)||0) / maxCnt * 80));\\n    const dd = String(d.day || '').slice(5);\\n    return `<div class=\\"chart-bar-col\\">\\n      <div class=\\"chart-bar\\" style=\\"height:${h}px\\" title=\\"${escapeHtml(d.day)}: ${d.cnt}\\"></div>\\n      <div class=\\"chart-label\\">${dd}</div>\\n    </div>`;\\n  }).join('');\\n  chartHtml = `<div class=\\"chart\\">${bars}</div>\\n<div class=\\"chart-legend\\">📊 กิจกรรม 14 วันล่าสุด (เอกสารต่อวัน)</div>`;\\n}\\n\\n// ===== Recent Activity Timeline =====\\nlet recentHtml = '<div class=\\"empty-mini\\">ยังไม่มีข้อมูล</div>';\\nif (recent && recent.length) {\\n  recentHtml = recent.slice(0, 8).map(d => {\\n    const dt = new Date(d.uploaded_at);\\n    const dtStr = dt.toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' });\\n    const statusClass = `status-${d.status || 'unknown'}`;\\n    return `<div class=\\"timeline-item\\">\\n      <div class=\\"timeline-dot ${statusClass}\\"></div>\\n      <div class=\\"timeline-content\\">\\n        <div class=\\"timeline-title\\">${escapeHtml(d.file_name)}</div>\\n        <div class=\\"timeline-meta\\">\\n          <span class=\\"doc-no-mini\\">${escapeHtml(d.doc_no)}</span>\\n          <span>${dtStr}</span>\\n          <span class=\\"doc-status ${statusClass}\\">${escapeHtml(d.status)}</span>\\n        </div>\\n      </div>\\n    </div>`;\\n  }).join('');\\n}\\n\\n// ===== Status Breakdown =====\\nlet byStatusHtml = '<div class=\\"empty-mini\\">ยังไม่มีข้อมูล</div>';\\nif (byStatus && byStatus.length) {\\n  byStatusHtml = `<table class=\\"status-table\\">` +\\n    byStatus.map(r => `<tr><td><span class=\\"status-dot status-${escapeHtml(r.status || 'unknown')}\\"></span>${escapeHtml(r.status)}</td><td class=\\"num\\">${fmtNum(r.cnt)}</td></tr>`).join('') +\\n    `</table>`;\\n}\\n\\n// ===== Search Results =====\\nfunction renderListPage(docs) {\\n  if (!docs.length) return '<div class=\\"empty\\">ไม่พบเอกสาร</div>';\\n  return docs.map(d => {\\n    const uploaded = (d.uploaded_at || '').slice(0, 19).replace('T', ' ');\\n    return `\\n<div class=\\"doc-item\\">\\n  <span class=\\"doc-no\\">${escapeHtml(d.doc_no)}</span>\\n  <span class=\\"doc-name\\">${escapeHtml(d.file_name)}</span>\\n  <div class=\\"doc-meta\\">\\n    <span>${escapeHtml(d.file_type)}</span>\\n    <span>${escapeHtml(d.category || '—')}</span>\\n    <span>${escapeHtml(uploaded)}</span>\\n    <span class=\\"doc-status status-${escapeHtml(d.status || 'unknown')}\\">${escapeHtml(d.status)}</span>\\n  </div>\\n</div>`;\\n  }).join('');\\n}\\n\\nfunction renderVectorResults(results, query) {\\n  if (!results.length) return '<div class=\\"empty\\">ไม่พบผลลัพธ์</div>';\\n  return results.map(r => {\\n    const sim = ((r.similarity || 0) * 100).toFixed(1);\\n    let content = (r.content || '').slice(0, 500);\\n    if (query) {\\n      query.split(/\\\\s+/).filter(w => w.length > 1).forEach(w => {\\n        content = content.replace(new RegExp(w, 'gi'), m => '<span class=\\"search-q\\">' + m + '</span>');\\n      });\\n    }\\n    return `\\n<div class=\\"result-card\\">\\n  <div class=\\"result-meta\\">\\n    <span class=\\"result-similarity\\">📊 ${sim}%</span>\\n    <span>${escapeHtml(r.doc_no)}</span>\\n    <span>${escapeHtml(r.file_name)}</span>\\n    <span>chunk #${escapeHtml(r.chunk_index)}</span>\\n  </div>\\n  <div class=\\"result-content\\">${content}${(r.content || '').length > 500 ? '...' : ''}</div>\\n</div>`;\\n  }).join('');\\n}\\n\\n// ===== Tabs =====\\nconst listTabActive = mode === 'list' ? 'active' : '';\\nconst vectorTabActive = mode === 'vector' ? 'active' : '';\\nconst listLink = '/webhook/docs-search?mode=list';\\nconst vectorLink = '/webhook/docs-search?mode=vector&q=' + encodeURIComponent(query || '');\\nconst isOverview = !query && mode === 'list';\\n\\nconst html = `<!DOCTYPE html>\\n<html lang=\\"th\\">\\n<head>\\n<meta charset=\\"UTF-8\\">\\n<meta name=\\"viewport\\" content=\\"width=device-width, initial-scale=1.0\\">\\n<title>${isOverview ? 'Executive Summary' : 'Document Search'} — Law Firm</title>\\n<style>\\n* { box-sizing: border-box; margin: 0; padding: 0; }\\nbody { font-family: -apple-system, BlinkMacSystemFont, \\"Segoe UI\\", \\"Noto Sans Thai\\", sans-serif; background: #f5f7fa; color: #2c3e50; padding: 24px; }\\n.container { max-width: 1280px; margin: 0 auto; }\\nheader { background: linear-gradient(135deg, #1a3a5c 0%, #2c5e8a 100%); color: white; padding: 24px 32px; border-radius: 12px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(26,58,92,0.15); }\\nheader h1 { font-size: 26px; margin-bottom: 6px; }\\n.subtitle { opacity: 0.85; font-size: 14px; }\\n.tabs { display: flex; gap: 4px; margin-bottom: 16px; background: #e1e8ed; padding: 4px; border-radius: 8px; }\\n.tab { padding: 10px 24px; cursor: pointer; background: transparent; border: none; border-radius: 6px; font-size: 14px; font-weight: 600; color: #5a6c7d; text-decoration: none; transition: all 0.15s; display: inline-block; }\\n.tab:hover { background: rgba(255,255,255,0.5); }\\n.tab.active { background: white; color: #1a3a5c; box-shadow: 0 2px 4px rgba(0,0,0,0.06); }\\n.search-box { background: white; padding: 16px 20px; border-radius: 8px; margin-bottom: 16px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); }\\n.search-form { display: flex; gap: 8px; }\\ninput[type=\\"text\\"] { flex: 1; padding: 10px 14px; border: 1px solid #cbd5e0; border-radius: 6px; font-size: 14px; }\\nbutton { padding: 10px 20px; background: #1a3a5c; color: white; border: none; border-radius: 6px; font-weight: 600; cursor: pointer; font-size: 14px; }\\nbutton:hover { background: #122a44; }\\n.kpi-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 20px; }\\n.kpi-card { background: white; padding: 20px 24px; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); border-left: 4px solid #cbd5e0; }\\n.kpi-primary { border-left-color: #1a3a5c; }\\n.kpi-success { border-left-color: #0a6b3e; }\\n.kpi-warn { border-left-color: #c47a00; }\\n.kpi-danger { border-left-color: #a01818; }\\n.kpi-label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; color: #6b7785; font-weight: 600; margin-bottom: 6px; }\\n.kpi-value { font-size: 32px; font-weight: 700; color: #1a3a5c; line-height: 1; margin-bottom: 4px; }\\n.kpi-sub { font-size: 12px; color: #6b7785; }\\n.overview-row { display: grid; grid-template-columns: 2fr 1fr; gap: 20px; margin-bottom: 20px; }\\n.panel { background: white; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); padding: 20px 24px; }\\n.panel-title { font-size: 14px; font-weight: 700; color: #1a3a5c; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid #ecf0f3; }\\n.chart { display: flex; align-items: flex-end; gap: 6px; height: 100px; padding: 8px 0; }\\n.chart-bar-col { display: flex; flex-direction: column; align-items: center; flex: 1; min-width: 0; }\\n.chart-bar { background: linear-gradient(to top, #2c5e8a, #4a8ec8); width: 100%; border-radius: 3px 3px 0 0; min-height: 2px; transition: all 0.2s; }\\n.chart-bar:hover { background: linear-gradient(to top, #1a3a5c, #2c5e8a); }\\n.chart-label { font-size: 10px; color: #6b7785; margin-top: 4px; }\\n.chart-legend { font-size: 12px; color: #6b7785; margin-top: 12px; }\\n.timeline-item { display: flex; gap: 12px; padding: 10px 0; border-bottom: 1px solid #ecf0f3; }\\n.timeline-item:last-child { border-bottom: none; }\\n.timeline-dot { width: 10px; height: 10px; border-radius: 50%; margin-top: 6px; flex-shrink: 0; }\\n.timeline-dot.status-ready { background: #0a6b3e; }\\n.timeline-dot.status-registered { background: #c47a00; }\\n.timeline-dot.status-pending { background: #c47a00; }\\n.timeline-dot.status-failed { background: #a01818; }\\n.timeline-content { flex: 1; min-width: 0; }\\n.timeline-title { font-weight: 500; font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\\n.timeline-meta { display: flex; gap: 10px; font-size: 11px; color: #6b7785; margin-top: 2px; flex-wrap: wrap; }\\n.doc-no-mini { background: #e8f0fe; color: #1a3a5c; padding: 1px 6px; border-radius: 3px; font-family: monospace; font-size: 10px; }\\n.status-table { width: 100%; border-collapse: collapse; }\\n.status-table td { padding: 8px 0; border-bottom: 1px solid #ecf0f3; font-size: 13px; }\\n.status-table td.num { text-align: right; font-weight: 600; color: #1a3a5c; }\\n.status-table tr:last-child td { border-bottom: none; }\\n.status-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 8px; }\\n.status-dot.status-ready { background: #0a6b3e; }\\n.status-dot.status-registered { background: #c47a00; }\\n.status-dot.status-pending { background: #c47a00; }\\n.status-dot.status-failed { background: #a01818; }\\n.empty-mini { color: #6b7785; font-size: 13px; padding: 20px; text-align: center; }\\n.docs-list { background: white; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); overflow: hidden; }\\n.doc-item { padding: 14px 20px; border-bottom: 1px solid #ecf0f3; display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }\\n.doc-item:last-child { border-bottom: none; }\\n.doc-no { background: #e8f0fe; color: #1a3a5c; padding: 4px 10px; border-radius: 4px; font-family: monospace; font-size: 12px; font-weight: 600; }\\n.doc-name { flex: 1; font-weight: 500; min-width: 200px; }\\n.doc-meta { color: #6b7785; font-size: 12px; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }\\n.doc-status { padding: 3px 10px; border-radius: 12px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.3px; }\\n.status-ready { background: #d4f5e1; color: #0a6b3e; }\\n.status-registered { background: #fff4d4; color: #8a6708; }\\n.status-pending { background: #fde7d4; color: #9c4a0a; }\\n.status-failed { background: #fdd4d4; color: #a01818; }\\n.empty { padding: 40px; text-align: center; color: #6b7785; }\\n.result-card { background: white; padding: 16px 20px; border-radius: 8px; margin-bottom: 12px; box-shadow: 0 2px 6px rgba(0,0,0,0.04); }\\n.result-meta { display: flex; gap: 12px; font-size: 12px; color: #6b7785; margin-bottom: 8px; flex-wrap: wrap; }\\n.result-similarity { background: #e8f0fe; color: #1a3a5c; padding: 2px 8px; border-radius: 4px; font-weight: 600; }\\n.result-content { font-size: 14px; line-height: 1.6; color: #2c3e50; white-space: pre-wrap; word-wrap: break-word; }\\n.search-q { background: #fff8c5; padding: 2px 6px; border-radius: 3px; font-weight: 600; }\\n.section-title { font-size: 18px; font-weight: 700; color: #1a3a5c; margin: 24px 0 12px 0; }\\n.footer { text-align: center; padding: 20px; color: #6b7785; font-size: 12px; margin-top: 24px; border-top: 1px solid #ecf0f3; }\\n@media (max-width: 768px) { .overview-row { grid-template-columns: 1fr; } }\\n</style>\\n</head>\\n<body>\\n<div class=\\"container\\">\\n<header>\\n  <h1>${isOverview ? '📊 Executive Summary' : '📋 Document Registry'}</h1>\\n  <div class=\\"subtitle\\">Law Firm — Document Pipeline & Search</div>\\n</header>\\n\\n<div class=\\"tabs\\">\\n  <a class=\\"tab ${listTabActive}\\" href=\\"${listLink}\\">📋 ${isOverview ? 'Overview' : 'List'}</a>\\n  <a class=\\"tab ${vectorTabActive}\\" href=\\"${vectorLink}\\">🔍 Vector Search</a>\\n</div>\\n\\n<div class=\\"search-box\\">\\n  <form class=\\"search-form\\" method=\\"get\\" action=\\"/webhook/docs-search\\">\\n    <input type=\\"hidden\\" name=\\"mode\\" value=\\"${mode}\\">\\n    <input type=\\"text\\" name=\\"q\\" value=\\"${escapeHtml(query)}\\" placeholder=\\"${mode === 'vector' ? 'ค้นหาด้วย semantic search... (e.g. สัญญาเช่า ผิดนัด)' : 'กรองรายการ (filename, category)...'}\\" autofocus>\\n    <button type=\\"submit\\">${mode === 'vector' ? '🔍 Search' : '🔎 Filter'}</button>\\n  </form>\\n</div>\\n\\n${isOverview ? kpiCards : ''}\\n\\n${isOverview ? `\\n<div class=\\"overview-row\\">\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">📈 กิจกรรมการอัปโหลด</div>\\n    ${chartHtml}\\n  </div>\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">📌 สถานะเอกสาร</div>\\n    ${byStatusHtml}\\n  </div>\\n</div>\\n\\n<div class=\\"overview-row\\">\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">🕐 เอกสารล่าสุด</div>\\n    ${recentHtml}\\n  </div>\\n  <div class=\\"panel\\">\\n    <div class=\\"panel-title\\">🔗 Quick Links</div>\\n    <div style=\\"display: flex; flex-direction: column; gap: 10px;\\">\\n      <a href=\\"/webhook/docs-search?mode=list\\" style=\\"padding: 12px 16px; background: #f5f7fa; border-radius: 6px; text-decoration: none; color: #1a3a5c; font-weight: 500;\\">📋 ดูเอกสารทั้งหมด</a>\\n      <a href=\\"/webhook/docs-search?mode=vector\\" style=\\"padding: 12px 16px; background: #f5f7fa; border-radius: 6px; text-decoration: none; color: #1a3a5c; font-weight: 500;\\">🔍 Vector Search</a>\\n      <a href=\\"/webhook/docs-stats\\" style=\\"padding: 12px 16px; background: #f5f7fa; border-radius: 6px; text-decoration: none; color: #1a3a5c; font-weight: 500;\\">📊 Stats JSON API</a>\\n      <code style=\\"padding: 12px 16px; background: #fff8c5; border-radius: 6px; font-size: 11px; color: #5a4a08; word-break: break-all;\\">POST /webhook/docs-registry<br>{filename, file_type, ...}</code>\\n    </div>\\n  </div>\\n</div>\\n` : ''}\\n\\n<div class=\\"section-title\\">${mode === 'vector' ? '🔍 ผลการค้นหา (Semantic)' : isOverview ? '📄 เอกสารทั้งหมด' : '🔎 ผลการกรอง'}</div>\\n${mode === 'vector' ? renderVectorResults(results, query) : '<div class=\\"docs-list\\">' + renderListPage(docs) + '</div>'}\\n\\n<div class=\\"footer\\">\\n  Generated at ${new Date().toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' })} • n8n workflow: 02 - Document Registry & Stats • Global URLs: /webhook/docs-search · /webhook/docs-stats · /webhook/docs-registry\\n</div>\\n</div>\\n</body>\\n</html>`;\\n\\nreturn [{ json: { html: html, contentType: 'text/html' } }];\\n"},"id":"code-render-html","name":"Render HTML","type":"n8n-nodes-base.code","position":[3184,1664],"typeVersion":2},{"parameters":{"respondWith":"text","responseBody":"={{ $('Render HTML').first().json.html }}","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Type","value":"text/html; charset=utf-8"}]}}},"id":"resp-html","name":"Respond HTML","type":"n8n-nodes-base.respondToWebhook","position":[48,2912],"typeVersion":1},{"parameters":{"jsCode":"// Build vector_params for n8n pg node - array of raw values\\nconst embeddings = $json.embeddings || ($json.embedding ? [$json.embedding] : []);\\nconst vec = embeddings[0] || [];\\nconst limit = $('Parse Search').item.json.limit || 10;\\n// Format: '[0.1,0.2,...]' as string for pg vector literal\\nconst vectorStr = '[' + vec.map(Number).join(',') + ']';\\nreturn [{ json: { ...$json, vector_params: [vectorStr, limit] } }];\\n"},"id":"code-build-vec-params","name":"Build Vector Params","type":"n8n-nodes-base.code","position":[2064,1776],"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT row_to_json(s) FROM (SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='registered') AS registered, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed, (SELECT COUNT(*) FROM contract_chunks) AS chunks) s) AS stats, (SELECT COALESCE(json_agg(daily), '[]'::json) FROM (  SELECT to_char(\\"uploaded_at\\" AT TIME ZONE 'Asia/Bangkok', 'YYYY-MM-DD') AS day, COUNT(*)::int AS cnt   FROM contracts   WHERE \\"uploaded_at\\" >= (now() - interval '14 days')   GROUP BY 1 ORDER BY 1) daily) AS daily","options":{}},"id":"pg-daily","name":"PG: Daily Activity","type":"n8n-nodes-base.postgres","position":[2512,1664],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT doc_no, file_name, file_type, status, uploaded_at FROM contracts ORDER BY uploaded_at DESC LIMIT 8","options":{}},"id":"pg-recent","name":"PG: Recent Activity","type":"n8n-nodes-base.postgres","position":[2736,1664],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT status, COUNT(*)::int AS cnt FROM contracts WHERE status IS NOT NULL GROUP BY status ORDER BY status","options":{}},"id":"pg-by-status","name":"PG: By Status","type":"n8n-nodes-base.postgres","position":[2960,1664],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Chunk the extracted text. Empty text = empty chunks → caller rolls back the file.\\nconst MAX = 1500;\\nconst OVERLAP = 200;\\nconst text = ($('LINE Extract via Vision LLM').first().json.text || '').toString();\\n\\nif (!text.trim()) {\\n  return [{ json: { empty: true, chunk_count: 0, chunks: [] } }];\\n}\\n\\nconst chunks = [];\\nlet i = 0, idx = 0;\\nwhile (i < text.length) {\\n  chunks.push({ chunk_index: idx, content: text.slice(i, i + MAX) });\\n  if (i + MAX >= text.length) break;\\n  i += MAX - OVERLAP;\\n  idx++;\\n}\\nreturn [{ json: { empty: false, chunk_count: chunks.length, chunks } }];\\n"},"id":"line-chunk","name":"LINE Chunk text","type":"n8n-nodes-base.code","position":[1616,464],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ $env.OLLAMA_URL || 'http://127.0.0.1:11434' }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.chunks.map(c => c.content)) }}\\n}","options":{"timeout":180000}},"id":"line-embed","name":"LINE Embed all chunks (Ollama bge-m3)","type":"n8n-nodes-base.httpRequest","position":[2288,384],"typeVersion":4.2},{"parameters":{"jsCode":"// Combine: file metadata + chunk embeddings into rows ready to insert.\\n// Use explicit $() to fetch from each upstream — $input.first() picks whichever\\n// runs first which is brittle when Decode and Embed both feed in.\\nconst embedResp = $('LINE Embed all chunks (Ollama bge-m3)').first().json;\\nconst vecs = embedResp.embeddings || embedResp;\\nconst chunkInfo = $('LINE Chunk text').first().json;\\nconst sm = $('Smart Router').first().json;\\nconst evt = sm._event || {};\\nconst downloadMeta = sm._downloadResult || {};\\n\\n// Pull file_data_b64 from Decode (preferred) — scan $input.all() as fallback\\nlet fileDataB64 = null, fileMime = null, fileName = null, fileSize = null;\\nconst decodeOut = $('LINE Decode & Prepare Binary').first();\\nif (decodeOut && decodeOut.json) {\\n  fileDataB64 = decodeOut.json.file_data_b64 || null;\\n  fileMime = decodeOut.json.file_mime || null;\\n  fileName = decodeOut.json.file_name || null;\\n  fileSize = decodeOut.json.file_size || null;\\n}\\nif (!fileDataB64) {\\n  for (const it of $input.all()) {\\n    if (it.json && it.json.file_data_b64) {\\n      fileDataB64 = it.json.file_data_b64;\\n      fileMime = it.json.file_mime || null;\\n      fileName = it.json.file_name || null;\\n      fileSize = it.json.file_size || null;\\n      break;\\n    }\\n  }\\n}\\n\\nconst chunks = chunkInfo.chunks || [];\\nconst rows = chunks.map((c, i) => ({\\n  chunk_index: c.chunk_index,\\n  content: c.content,\\n  embedding: vecs[i] ? ('[' + vecs[i].map(Number).join(',') + ']') : null\\n}));\\n\\nreturn [{\\n  json: {\\n    file_name: fileName || downloadMeta.fileName || evt.message?.fileName || 'unknown',\\n    file_type: ((fileName || downloadMeta.fileName || evt.message?.fileName || '').split('.').pop() || '').toLowerCase(),\\n    size_bytes: fileSize || downloadMeta.fileSize || evt.message?.fileSize || null,\\n    line_user_id: evt.source?.userId || null,\\n    line_group_id: evt.source?.groupId || null,\\n    line_message_id: evt.message?.id || null,\\n    chunk_count: rows.length,\\n    file_data_b64: fileDataB64,\\n    file_mime: fileMime,\\n    rows\\n  }\\n}];\\n"},"id":"line-combine","name":"LINE Combine metadata + vectors","type":"n8n-nodes-base.code","position":[2512,384],"typeVersion":2},{"parameters":{"jsCode":"// Build one Postgres statement that marks the document ready and stores all vectors\\n// AND all per-page images (JPEG bytes from ocr-service /vision page_images[]).\\nconst start = $('LINE Register Start').first().json || {};\\nconst meta = $('LINE Combine metadata + vectors').first().json || {};\\nconst visionResp = $('LINE Extract via Vision LLM').first().json || {};\\nconst contractId = start.id;\\nif (!contractId) {\\n  throw new Error('Missing contract id from LINE Register Start');\\n}\\n\\nconst rows = Array.isArray(meta.rows) ? meta.rows : [];\\nconst chunkCount = rows.length;\\nconst pageImages = Array.isArray(visionResp.page_images) ? visionResp.page_images : [];\\nconst pageCount = pageImages.length;\\nconst quoteIdent = String(contractId).replace(/'/g, \\"''\\");\\nconst dollarTag = (i) => `$chunk_${i}$`;\\nconst cleanForTag = (value, tag) => String(value ?? '').replaceAll(tag, '');\\n\\nlet insertedCte;\\nif (chunkCount > 0) {\\n  const values = rows.map((row, i) => {\\n    const tag = dollarTag(i);\\n    const content = cleanForTag(row.content, tag);\\n    const vector = row.embedding ? `'${row.embedding}'::vector` : 'NULL';\\n    return `((SELECT id FROM updated), ${Number(row.chunk_index) || 0}, ${tag}${content}${tag}, ${content.length}, ${vector})`;\\n  }).join(',\\\\n');\\n  insertedCte = `inserted AS (\\\\n  INSERT INTO contract_chunks (contract_id, chunk_index, content, token_count, embedding)\\\\n  VALUES ${values}\\\\n  RETURNING 1\\\\n)`;\\n} else {\\n  insertedCte = `inserted AS (SELECT 1 WHERE false)`;\\n}\\n\\n// Per-page images: base64 in single-quoted literal -> decode(..., 'base64') -> BYTEA.\\n// b64 alphabet excludes single quotes, but escape anyway for safety. ON CONFLICT\\n// makes re-runs idempotent (same contract_id+page_index is replaced, not duplicated).\\nlet pagesCte;\\nif (pageCount > 0) {\\n  const values = pageImages.map((p) => {\\n    const b64 = String(p.image_b64 || '').replace(/'/g, \\"''\\");\\n    const mime = String(p.mime || 'image/jpeg').replace(/'/g, \\"''\\");\\n    const idx = Number(p.page_index) || 0;\\n    const bytes = Number(p.bytes) || 0;\\n    return `((SELECT id FROM updated), ${idx}, decode('${b64}', 'base64'), '${mime}', ${bytes})`;\\n  }).join(',\\\\n');\\n  pagesCte = `inserted_pages AS (\\\\n  INSERT INTO contract_pages (contract_id, page_index, image_data, image_mime, bytes)\\\\n  VALUES ${values}\\\\n  ON CONFLICT (contract_id, page_index) DO UPDATE SET\\\\n    image_data = EXCLUDED.image_data,\\\\n    image_mime = EXCLUDED.image_mime,\\\\n    bytes = EXCLUDED.bytes\\\\n  RETURNING 1\\\\n)`;\\n} else {\\n  pagesCte = `inserted_pages AS (SELECT 1 WHERE false)`;\\n}\\n\\nconst sql = `WITH updated AS (\\\\n  UPDATE contracts\\\\n  SET chunk_count = ${chunkCount}::int, status = 'ready', error_message = NULL, updated_at = now()\\\\n  WHERE id = '${quoteIdent}'::uuid\\\\n  RETURNING id, doc_no, file_name\\\\n), deleted AS (\\\\n  DELETE FROM contract_chunks WHERE contract_id = (SELECT id FROM updated)\\\\n), ${insertedCte},\\\\n${pagesCte}\\\\nSELECT id, doc_no, file_name, ${chunkCount}::int AS chunk_count,\\\\n       (SELECT count(*) FROM inserted) AS inserted_chunks,\\\\n       (SELECT count(*) FROM inserted_pages) AS inserted_pages\\\\nFROM updated`;\\n\\nreturn [{ json: { sql, contract_id: contractId, chunk_count: chunkCount, page_count: pageCount } }];\\n"},"id":"line-build-sql","name":"LINE Build Store SQL","type":"n8n-nodes-base.code","position":[2736,384],"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"{{ $json.sql }}","options":{}},"id":"line-insert-chunks","name":"PG: Store Embeddings","type":"n8n-nodes-base.postgres","position":[2960,384],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/push","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"to\\": {{ JSON.stringify($('Smart Router').first().json._event.source.groupId || $('Smart Router').first().json._event.source.userId) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": \\"บันทึกเอกสารเรียบร้อย\\\\nเลขที่: {{ $('PG: Store Embeddings').first().json.doc_no || $('LINE Register Start').first().json.doc_no }}\\\\nไฟล์: {{ $('LINE Combine metadata + vectors').item.json.file_name }}\\\\nChunks: {{ $('LINE Combine metadata + vectors').item.json.chunk_count }}\\" }]\\n}","options":{}},"id":"line-reply-ok","name":"LINE Reply Success","type":"n8n-nodes-base.httpRequest","position":[3184,336],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/push","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"to\\": {{ JSON.stringify($('Smart Router').first().json._event.source.groupId || $('Smart Router').first().json._event.source.userId) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": \\"บันทึกเอกสารไม่สำเร็จ: {{ $json.error || $json.message || 'unknown' }}\\" }]\\n}","options":{}},"id":"line-reply-err","name":"LINE Reply Error","type":"n8n-nodes-base.httpRequest","position":[3184,576],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"operation":"executeQuery","query":"INSERT INTO contracts (doc_no, line_user_id, line_group_id, line_message_id, file_name, file_type, size_bytes, status, source, file_mime, file_data) VALUES (next_doc_seq(), NULLIF($1::text, '')::text, NULLIF($2::text, '')::text, NULLIF($3::text, '')::text, $4::text, $5::text, $6::bigint, 'processing', 'line', NULLIF($7::text, '')::text, decode($8::text, 'base64')) RETURNING id, doc_no","options":{"queryReplacement":"={{ [$('LINE Decode & Prepare Binary').first().json.line_user_id || '', $('LINE Decode & Prepare Binary').first().json.line_group_id || '', $('LINE Decode & Prepare Binary').first().json.line_message_id || '', $('LINE Decode & Prepare Binary').first().json.file_name || '', $('LINE Decode & Prepare Binary').first().json.file_type || '', $('LINE Decode & Prepare Binary').first().json.file_size || 0, $('LINE Decode & Prepare Binary').first().json.file_mime || '', $('LINE Decode & Prepare Binary').first().json.file_data_b64 || ''] }}"}},"id":"line-reg-start-pg","name":"LINE Register Start","type":"n8n-nodes-base.postgres","position":[1392,464],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}},"continueOnFail":true},{"parameters":{"httpMethod":"POST","path":"docs","responseMode":"responseNode","options":{}},"id":"wh-docs","name":"Docs Webhook","type":"n8n-nodes-base.webhook","position":[48,1200],"webhookId":"docs-webhook","typeVersion":2},{"parameters":{"jsCode":"// Smart Router: detect request type\\nconst req = $input.first().json;\\nconst body = req.body || req || {};\\nconst headers = req.headers || {};\\nconst query = req.query || {};\\n\\nconst isLineSignature = headers['x-line-signature'] !== undefined ||\\n  (Array.isArray(body.events) && body.events.length > 0);\\n\\nconst messageText = (body.message || body.text || '').toString().toLowerCase();\\nconst statsKeywords = ['สรุปผล', 'สถิติ', 'stats', 'summary', 'รายงาน', 'list', 'ทั้งหมด', 'all'];\\nconst isStats = !!statsKeywords.find(k => messageText.includes(k.toLowerCase())) || body.mode === 'stats';\\n\\nconst isRegistry = body.filename !== undefined || body.file_name !== undefined;\\n\\n// Routing priority:\\n// 1. LINE events (highest)\\n// 2. Registry (filename present)\\n// 3. Stats (keyword or mode=stats)\\n// 4. Search HTML (default - including mode=vector and mode=list)\\nlet route = 'search_html';\\nif (isLineSignature) route = 'line_event';\\nelse if (isRegistry) route = 'registry_insert';\\nelse if (isStats) route = 'stats_text';\\n\\nconst result = {\\n  _route: route,\\n  _body: body,\\n  _events: body.events || [],\\n  _query: query,\\n  _mode: body.mode || 'list',\\n  _q: body.q || '',\\n  _days: body.days || 7,\\n  _headers: headers\\n};\\nif (isLineSignature && body.events && body.events.length > 0) {\\n  result._event = body.events[0];\\n  result._replyToken = body.events[0].replyToken;\\n}\\nreturn [{ json: result }];\\n"},"id":"code-smart-router","name":"Smart Router","type":"n8n-nodes-base.code","position":[272,1104],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"line_event"}]},"renameOutput":true,"outputKey":"line"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"registry_insert"}]},"renameOutput":true,"outputKey":"registry"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"stats_text"}]},"renameOutput":true,"outputKey":"stats"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"search_html"}]},"renameOutput":true,"outputKey":"search"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"unknown"}},"id":"sw-route","name":"Route Switch","type":"n8n-nodes-base.switch","position":[496,1056],"typeVersion":3.2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._event.message.type }}","rightValue":"file"}]},"renameOutput":true,"outputKey":"is_file"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"not_file"}},"id":"sw-is-file","name":"LINE: Is file?","type":"n8n-nodes-base.switch","position":[720,464],"typeVersion":3.2},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": {{ JSON.stringify($('Smart Router').first().json._replyToken) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": \\"ส่งไฟล์ PDF/DOCX/TXT มาวิเคราะห์สัญญาได้เลย หรือพิมพ์คำถามเกี่ยวกับสัญญาได้เลย\\" }]\\n}","options":{"timeout":15000}},"id":"line-not-file","name":"LINE: Reply Non-File","type":"n8n-nodes-base.httpRequest","position":[3184,2688],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"respondWith":"text","responseBody":"={{ $('Format Response').first().json.body }}","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Type","value":"={{ $('Format Response').first().json.contentType }}"}]}}},"id":"resp-docs","name":"Respond Docs","type":"n8n-nodes-base.respondToWebhook","position":[3632,1568],"typeVersion":1},{"parameters":{"jsCode":"// Pick response based on route\\nconst route = $('Smart Router').first().json._route || 'search_html';\\nconst replyToken = $('Smart Router').first().json._replyToken;\\nlet body = '';\\nlet contentType = 'application/json; charset=utf-8';\\nif (route === 'registry_insert') {\\n  const r = $('Respond Registry').first().json || {};\\n  body = JSON.stringify(r);\\n} else if (route === 'stats_text') {\\n  const r = $('Respond Stats').first().json || $('Respond Not Stats').first().json || { ok: false };\\n  body = JSON.stringify(r);\\n} else if (route === 'line_event') {\\n  if (replyToken) {\\n    // Real LINE event - just ack\\n    body = JSON.stringify({ ok: true, route: 'line_event', events: $('Smart Router').first().json._events.length });\\n  } else {\\n    // Test mode - no replyToken. Return the AI agent decision so tester can verify routing.\\n    const aiResp = $('Parse AI Response').first().json || {};\\n    body = JSON.stringify({\\n      ok: true,\\n      mode: 'test',\\n      route: 'line_event',\\n      _route: aiResp._route || null,\\n      _text: aiResp._text || null,\\n      _query: aiResp._query || null,\\n      _filter: aiResp._filter || null,\\n      _tool_call_id: aiResp._tool_call_id || null\\n    });\\n  }\\n} else {\\n  body = ($('Render HTML').first().json || {}).html || '<h1>Error</h1>';\\n  contentType = 'text/html; charset=utf-8';\\n}\\nreturn [{ json: { body, contentType } }];\\n"},"id":"code-format-resp","name":"Format Response","type":"n8n-nodes-base.code","position":[3408,1568],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ $env.OLLAMA_URL || 'http://127.0.0.1:11434' }}/api/chat","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_AGENT_MODEL || 'qwen3.6:35b-a3b-q4_K_M' }}\\",\\n  \\"stream\\": false,\\n  \\"messages\\": {{ JSON.stringify([\\n    {role: 'system', content: 'คุณคือผู้ช่วย AI ของ Law Firm (Phuket Law Firm)\\\\n\\\\nตอบเป็นภาษาไทยเสมอ กระชับ ไม่เกิน 3-4 บรรทัด\\\\n\\\\n**เลือก tool ที่เหมาะสมที่สุด 1 ตัว ตาม intent:**\\\\n\\\\n1. `search_documents(query, limit=5)` — เมื่อ user ต้องการ ค้นหา/หา/ค้น/สืบค้น เอกสารที่เกี่ยวกับ เนื้อหา/หัวข้อ/keyword เฉพาะ (เช่น \\\\\\"หาสัญญาเช่า\\\\\\", \\\\\\"ค้นหนี้สิน\\\\\\", \\\\\\"มีสัญญาเกี่ยวกับที่ดินมั้ย\\\\\\")\\\\n\\\\n2. `list_documents(filter=\\\\\\"\\\\\\", limit=10)` — เมื่อ user ถาม จำนวน/กี่ฉบับ/list/ทั้งหมด/อันไหนบ้าง โดยไม่ระบุหัวข้อเฉพาะ (เช่น \\\\\\"มี contract กี่ฉบับ list มาให้หน่อย\\\\\\", \\\\\\"ทั้งหมดมีอะไรบ้าง\\\\\\", \\\\\\"มีเอกสารอะไรบ้าง\\\\\\")\\\\n\\\\n3. `get_stats()` — เมื่อ user ถาม สรุป/ภาพรวม/สถิติ/สถานะ/จัดกลุ่ม (เช่น \\\\\\"สรุปผล\\\\\\", \\\\\\"ภาพรวมเอกสาร\\\\\\", \\\\\\"มีกี่หมวดหมู่\\\\\\")\\\\n\\\\n4. ไม่ต้องใช้ tool — เมื่อ user ทักทาย/ถามทั่วไป/ถามเกี่ยวกับบริษัท\\\\n\\\\n**ตัวอย่าง intent → tool:**\\\\n- \\\\\\"หาสัญญาเช่า\\\\\\" → search_documents(query=\\\\\\"สัญญาเช่า\\\\\\")\\\\n- \\\\\\"มี contract กี่ฉบับ\\\\\\" → list_documents\\\\n- \\\\\\"list มาให้หน่อย\\\\\\" → list_documents\\\\n- \\\\\\"ทั้งหมดมีอะไรบ้าง\\\\\\" → list_documents\\\\n- \\\\\\"สรุปผลหน่อย\\\\\\" → get_stats\\\\n- \\\\\\"ภาพรวม\\\\\\" → get_stats\\\\n- \\\\\\"สวัสดี\\\\\\" → text reply\\\\n- \\\\\\"ช่วยได้อะไรบ้าง\\\\\\" → text reply อธิบาย capabilities\\\\n'},\\n    {role: 'user', content: $('Smart Router').first().json._event.message.text || 'สวัสดี'}\\n  ]) }},\\n  \\"tools\\": {{ JSON.stringify([\\n    {\\n      type: 'function',\\n      function: {\\n        name: 'search_documents',\\n        description: 'Search contracts by semantic similarity (vector search). Use when user asks about content/topic/keyword.',\\n        parameters: {\\n          type: 'object',\\n          properties: {\\n            query: {type: 'string', description: 'Search query in Thai'},\\n            limit: {type: 'integer', default: 5, description: 'Max results 1-20'}\\n          },\\n          required: ['query']\\n        }\\n      }\\n    },\\n    {\\n      type: 'function',\\n      function: {\\n        name: 'list_documents',\\n        description: 'List all contract documents in the registry. Returns metadata: doc_no, file_name, category, status, chunk_count, uploaded_at. Use when user asks for count, list, total, or all documents without specific topic.',\\n        parameters: {\\n          type: 'object',\\n          properties: {\\n            filter: {type: 'string', default: '', description: 'Optional filter by file_name or category (substring match)'},\\n            limit: {type: 'integer', default: 10, description: 'Max docs to return 1-50'}\\n          }\\n        }\\n      }\\n    },\\n    {\\n      type: 'function',\\n      function: {\\n        name: 'get_stats',\\n        description: 'Get statistics summary of all contracts: total count, breakdown by category and status. Use when user asks for summary, overview, stats, status breakdown.',\\n        parameters: {\\n          type: 'object',\\n          properties: {}\\n        }\\n      }\\n    }\\n  ]) }}\\n}","options":{"response":{"response":{"neverError":true}},"timeout":600000}},"id":"ollama-agent","name":"AI Agent (Ollama)","type":"n8n-nodes-base.httpRequest","position":[1392,2336],"typeVersion":4.2},{"parameters":{"jsCode":"// Parse Ollama response - robust text fallback using string matching\\nconst resp = $('AI Agent (Ollama)').first().json;\\nconst msg = resp.message || {};\\nlet toolCalls = msg.tool_calls || [];\\nconst content = (msg.content || '').trim();\\nconst thinking = (msg.thinking || '').trim();\\nconst allText = content + ' ' + thinking;\\n\\n// FALLBACK: detect tool call from text using simple string matching\\nif (toolCalls.length === 0 && content) {\\n  let detectedTool = null;\\n  if (content.includes('list_documents') || allText.includes('list_documents')) {\\n    detectedTool = 'list_documents';\\n  } else if (content.includes('search_documents') || allText.includes('search_documents')) {\\n    detectedTool = 'search_documents';\\n  } else if (content.includes('get_stats') || allText.includes('get_stats')) {\\n    detectedTool = 'get_stats';\\n  }\\n  \\n  if (detectedTool) {\\n    // Try to extract args from \\"(...)\\" \\n    let args = {};\\n    const parenMatch = content.match(new RegExp(detectedTool + '\\\\\\\\s*\\\\\\\\(([^)]*)\\\\\\\\)'));\\n    if (parenMatch) {\\n      const argsStr = parenMatch[1];\\n      // Match filter=\\"...\\" or query=\\"...\\" or limit=N\\n      const stringArg = argsStr.match(/(?:filter|query)\\\\\\\\s*=\\\\\\\\s*\\"([^\\"]*)\\"/);\\n      if (stringArg) {\\n        if (detectedTool === 'search_documents') args.query = stringArg[1];\\n        else args.filter = stringArg[1];\\n      }\\n      const intArg = argsStr.match(/limit\\\\\\\\s*=\\\\\\\\s*(\\\\\\\\d+)/);\\n      if (intArg) args.limit = parseInt(intArg[1]);\\n    }\\n    toolCalls = [{\\n      id: 'fallback-' + Date.now(),\\n      function: { name: detectedTool, arguments: args }\\n    }];\\n  }\\n}\\n\\nif (toolCalls.length > 0) {\\n  const tc = toolCalls[0];\\n  const toolName = tc.function.name;\\n  const args = typeof tc.function.arguments === 'string'\\n    ? (tc.function.arguments.trim() ? JSON.parse(tc.function.arguments) : {})\\n    : (tc.function.arguments || {});\\n\\n  if (toolName === 'search_documents') {\\n    return [{\\n      json: {\\n        _route: 'ai_search',\\n        _query: args.query || '',\\n        _limit: args.limit || 5,\\n        _tool_call_id: tc.id,\\n        _tool_name: toolName\\n      }\\n    }];\\n  } else if (toolName === 'list_documents') {\\n    return [{\\n      json: {\\n        _route: 'ai_list',\\n        _filter: args.filter || '',\\n        _limit: args.limit || 10,\\n        _tool_call_id: tc.id,\\n        _tool_name: toolName\\n      }\\n    }];\\n  } else if (toolName === 'get_stats') {\\n    return [{\\n      json: {\\n        _route: 'ai_stats',\\n        _tool_call_id: tc.id,\\n        _tool_name: toolName\\n      }\\n    }];\\n  }\\n}\\n\\nreturn [{\\n  json: {\\n    _route: 'ai_text',\\n    _text: content || 'ขออภัย ระบบไม่สามารถประมวลผลได้ในขณะนี้'\\n  }\\n}];\\n"},"id":"code-parse-agent","name":"Parse AI Response","type":"n8n-nodes-base.code","position":[1616,2336],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-search","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_search"}]},"renameOutput":true,"outputKey":"search"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-list","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_list"}]},"renameOutput":true,"outputKey":"list"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-stats","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_stats"}]},"renameOutput":true,"outputKey":"stats"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"id":"r-text","operator":{"type":"string","operation":"equals"},"leftValue":"={{ $json._route }}","rightValue":"ai_text"}]},"renameOutput":true,"outputKey":"text"}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"unknown"}},"id":"sw-ai-route","name":"AI Route Switch","type":"n8n-nodes-base.switch","position":[2288,2144],"typeVersion":3.2},{"parameters":{"method":"POST","url":"http://localhost:5678/webhook/vector-search-json","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"q\\": {{ JSON.stringify($json._query) }} }","options":{"response":{"response":{"neverError":true}},"timeout":60000}},"id":"ai-search","name":"AI: Call Vector Search","type":"n8n-nodes-base.httpRequest","position":[2512,1920],"typeVersion":4.2},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": {{ JSON.stringify($('Smart Router').first().json._replyToken) }},\\n  \\"messages\\": [{ \\"type\\": \\"text\\", \\"text\\": {{ JSON.stringify($json._text) }} }]\\n}","options":{"timeout":15000}},"id":"ai-text-reply","name":"AI: Reply Text","type":"n8n-nodes-base.httpRequest","position":[2960,2304],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"jsCode":"// Build LINE Flex message from search results (filtered by AI re-rank)\\nconst searchResp = $('AI: Call Vector Search').first().json;\\nconst query = $('Parse AI Response').first().json._query;\\nlet results = (searchResp.results || []).slice(0, 10);\\n\\n// Get AI re-rank selection if available\\nlet aiSelected = null;\\ntry {\\n  const rr = $('Parse Re-rank Response').first().json;\\n  if (rr && Array.isArray(rr._selected_doc_nos) && rr._selected_doc_nos.length > 0) {\\n    aiSelected = rr._selected_doc_nos;\\n  }\\n} catch (e) {\\n  aiSelected = null;\\n}\\n\\n// Use AI selection if available, else top 5 by similarity\\nlet orderedResults;\\nif (aiSelected && aiSelected.length > 0) {\\n  const byDocNo = new Map(results.map(r => [r.doc_no, r]));\\n  orderedResults = aiSelected\\n    .map(docNo => byDocNo.get(docNo))\\n    .filter(Boolean)\\n    .slice(0, 5);\\n} else {\\n  orderedResults = results.slice(0, 5);\\n}\\n\\nif (!orderedResults.length) {\\n  return [{\\n    json: {\\n      _flex: null,\\n      _fallback: `🔍 ไม่พบเอกสารที่เกี่ยวข้องกับ \\"${query}\\"\\\\n\\\\nเปิดดูเอกสารทั้งหมด: https://n8n.jesadakorn.com/webhook/docs-admin-ui?q=${encodeURIComponent(query)}\\\\n\\\\nลองค้นหาด้วยคำอื่น หรือพิมพ์ \\"สรุปผล\\" เพื่อดูภาพรวม`,\\n      _result_count: 0,\\n      _query: query\\n    }\\n  }];\\n}\\n\\nconst adminUrl = `https://n8n.jesadakorn.com/webhook/docs-admin-ui?q=${encodeURIComponent(query)}`;\\n\\n// Build match snippet with highlighted query (LINE Flex pattern, like flow 04 admin UI)\\nfunction buildMatchContent(content, q) {\\n  if (!content) {\\n    return [{ type: 'text', text: '', size: 'xs', color: '#999999', wrap: true }];\\n  }\\n  if (!q || q.trim().length === 0) {\\n    return [{\\n      type: 'text',\\n      text: content.slice(0, 140).replace(/\\\\n/g, ' ').trim() + (content.length > 140 ? '…' : ''),\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    }];\\n  }\\n\\n  // Find query or partial match in content (case-insensitive, Thai-aware)\\n  const lowerContent = content.toLowerCase();\\n  const lowerQuery = q.toLowerCase().trim();\\n\\n  // Try exact query first\\n  let idx = lowerContent.indexOf(lowerQuery);\\n  let matchedLen = lowerQuery.length;\\n  let matchedText = content.slice(idx, idx + matchedLen);\\n\\n  // Fallback: try substrings of the query (sliding window). Critical for Thai\\n  // where words aren't space-separated. Try longer substrings first.\\n  if (idx === -1 && lowerQuery.length >= 2) {\\n    const skip = ['ที่', 'ใน', 'ของ', 'และ', 'มี', 'เป็น', 'ได้', 'จะ', 'มา', 'ไป', 'ก็', 'ให้', 'แต่', 'หรือ', 'นี้', 'นั้น', 'มา', 'จาก', 'กับ', 'แล้ว', 'อยู่', 'ไหม', 'ครับ', 'ค่ะ'];\\n    for (let len = Math.min(lowerQuery.length, 10); len >= 2; len--) {\\n      for (let start = 0; start + len <= lowerQuery.length; start++) {\\n        const candidate = lowerQuery.slice(start, start + len);\\n        if (skip.includes(candidate)) continue;\\n        const wordIdx = lowerContent.indexOf(candidate);\\n        if (wordIdx !== -1) {\\n          idx = wordIdx;\\n          matchedLen = len;\\n          matchedText = content.slice(idx, idx + len);\\n          break;\\n        }\\n      }\\n      if (idx !== -1) break;\\n    }\\n  }\\n\\n  if (idx === -1) {\\n    return [{\\n      type: 'text',\\n      text: content.slice(0, 140).replace(/\\\\n/g, ' ').trim() + (content.length > 140 ? '…' : ''),\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    }];\\n  }\\n\\n  // Build context: ~30 chars before, the match, ~70 chars after\\n  const beforeStart = Math.max(0, idx - 30);\\n  const afterEnd = Math.min(content.length, idx + matchedLen + 70);\\n  const beforeText = (beforeStart > 0 ? '…' : '') + content.slice(beforeStart, idx).replace(/\\\\n/g, ' ').trim();\\n  const afterText = content.slice(idx + matchedLen, afterEnd).replace(/\\\\n/g, ' ').trim() + (afterEnd < content.length ? '…' : '');\\n\\n  // Highlight box containing the match snippet\\n  return [\\n    {\\n      type: 'text',\\n      text: beforeText,\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    },\\n    {\\n      type: 'box',\\n      layout: 'horizontal',\\n      backgroundColor: '#fef08a',\\n      cornerRadius: '4px',\\n      paddingAll: '4px',\\n      margin: 'xs',\\n      contents: [\\n        {\\n          type: 'text',\\n          text: matchedText,\\n          size: 'xs',\\n          color: '#713f12',\\n          weight: 'bold',\\n          flex: 0\\n        }\\n      ]\\n    },\\n    {\\n      type: 'text',\\n      text: afterText,\\n      size: 'xs',\\n      color: '#666666',\\n      wrap: true\\n    }\\n  ];\\n}\\n\\n// Build Flex card with carousel of results\\nconst bubbles = orderedResults.map(r => {\\n  // Use vector_sim (cosine 0-1) for the match % - more meaningful than RRF score\\n  const vectorSim = (r.vector_sim != null) ? r.vector_sim : (r.similarity || 0);\\n  const simPct = Math.max(0, Math.min(100, Math.round(vectorSim * 100)));\\n  const keywordHit = (r.keyword_sim != null) ? r.keyword_sim : 0;\\n\\n  const headerText = (r.doc_no && r.doc_no.length > 0) ? r.doc_no : '🔍 ' + (r.file_name || 'document').slice(0, 20);\\n  const docNo = (r.doc_no && r.doc_no.length > 0) ? r.doc_no : '';\\n\\n  return {\\n    type: 'bubble',\\n    size: 'mega',\\n    header: {\\n      type: 'box',\\n      layout: 'vertical',\\n      contents: [\\n        {\\n          type: 'text',\\n          text: headerText,\\n          weight: 'bold',\\n          size: 'sm',\\n          color: '#1a3a5c',\\n          wrap: true\\n        }\\n      ],\\n      backgroundColor: '#f5f7fa',\\n      paddingAll: 'sm'\\n    },\\n    body: {\\n      type: 'box',\\n      layout: 'vertical',\\n      contents: [\\n        {\\n          type: 'text',\\n          text: r.file_name || '',\\n          weight: 'bold',\\n          size: 'md',\\n          wrap: true\\n        },\\n        {\\n          type: 'box',\\n          layout: 'baseline',\\n          margin: 'md',\\n          contents: [\\n            {\\n              type: 'text',\\n              text: `📊 ${simPct}% match`,\\n              size: 'xs',\\n              color: simPct >= 50 ? '#15803d' : (simPct >= 30 ? '#b45309' : '#999999'),\\n              weight: 'bold'\\n            },\\n            {\\n              type: 'text',\\n              text: keywordHit > 0 ? ` · keyword ${keywordHit.toFixed(1)}` : '',\\n              size: 'xs',\\n              color: '#0a6b3e'\\n            },\\n            {\\n              type: 'text',\\n              text: ` · chunk #${r.chunk_index || 0}`,\\n              size: 'xs',\\n              color: '#999999'\\n            }\\n          ]\\n        },\\n        // Match snippet with highlighted query\\n        {\\n          type: 'box',\\n          layout: 'vertical',\\n          margin: 'md',\\n          contents: buildMatchContent(r.content || '', query)\\n        }\\n      ]\\n    },\\n    footer: {\\n      type: 'box',\\n      layout: 'vertical',\\n      contents: [\\n        {\\n          type: 'button',\\n          style: 'primary',\\n          color: '#1a3a5c',\\n          action: {\\n            type: 'uri',\\n            label: '📂 เปิดในระบบ',\\n            uri: adminUrl\\n          }\\n        },\\n        {\\n          type: 'button',\\n          style: 'secondary',\\n          margin: 'sm',\\n          action: {\\n            type: 'uri',\\n            label: docNo ? ('ดู ' + docNo) : '📋 ดูเอกสารทั้งหมด',\\n            uri: adminUrl\\n          }\\n        }\\n      ]\\n    }\\n  };\\n});\\n\\nconst flex = {\\n  type: 'flex',\\n  altText: `🔍 ผลการค้นหา: ${query} (${orderedResults.length} รายการ)`,\\n  contents: {\\n    type: 'carousel',\\n    contents: bubbles\\n  }\\n};\\n\\nreturn [{\\n  json: {\\n    _flex: flex,\\n    _fallback: `🔍 ผลการค้นหา: ${query} (${orderedResults.length} รายการ)\\\\n\\\\nเปิดดูในระบบ: ${adminUrl}`,\\n    _result_count: orderedResults.length,\\n    _query: query,\\n    _ai_filtered: !!(aiSelected && aiSelected.length > 0)\\n  }\\n}];\\n"},"id":"code-ai-flex","name":"AI: Build Flex Card","type":"n8n-nodes-base.code","position":[2848,1920],"typeVersion":2},{"parameters":{"method":"POST","url":"https://api.line.me/v2/bot/message/reply","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"replyToken\\": {{ JSON.stringify($('Smart Router').first().json._replyToken) }},\\n  \\"messages\\": {{ JSON.stringify($('Build Safe Reply').first().json.messages) }}\\n}","options":{"timeout":15000}},"id":"ai-send-flex","name":"AI: Send Reply","type":"n8n-nodes-base.httpRequest","position":[3296,1920],"typeVersion":4.2,"credentials":{"httpHeaderAuth":{"id":"27fef0b4-9224-4a77-9741-c4f8e3d0aede","name":"LINE Bearer Auth"}}},{"parameters":{"operation":"executeQuery","query":"SELECT * FROM (SELECT doc_no, file_name, file_type, category, status, source, (SELECT COUNT(*) FROM contract_chunks WHERE contract_id = c.id) AS chunk_count, uploaded_at, FALSE AS _is_dummy FROM contracts c WHERE (($1::text IS NULL OR $1 = '') OR LOWER(file_name) LIKE '%' || LOWER($1) || '%' OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%') ORDER BY uploaded_at DESC LIMIT $2::int ) real_rows UNION ALL SELECT NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, TRUE AS _is_dummy WHERE NOT EXISTS (SELECT 1 FROM contracts) ORDER BY _is_dummy ASC, uploaded_at DESC NULLS LAST","options":{"queryReplacement":"={{ [$json._filter || null, $json._limit || 10] }}"}},"id":"ai-list-contracts","name":"AI: List Contracts","type":"n8n-nodes-base.postgres","position":[2512,2112],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed, (SELECT json_agg(json_build_object('category', COALESCE(category,'ไม่ระบุ'),'count', cnt) ORDER BY cnt DESC) FROM (SELECT category, COUNT(*) AS cnt FROM contracts GROUP BY category) x) AS by_category","options":{}},"id":"ai-get-stats","name":"AI: Get Stats","type":"n8n-nodes-base.postgres","position":[2512,2400],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Format list of contracts as readable Thai text\\nconst allItems = $('AI: List Contracts').all().map(i => i.json);\\nconst rows = allItems.filter(r => !r._is_dummy);\\nconst filter = $json._filter || '';\\nconst limit = $json._limit || 10;\\n\\nif (rows.length === 0) {\\n  const emptyText = filter\\n    ? `ไม่พบเอกสารที่ตรงกับ \\"${filter}\\"\\\\n\\\\nลองค้นหาด้วยคำอื่น หรือพิมพ์ \\"สรุปผล\\" เพื่อดูภาพรวม`\\n    : 'ตอนนี้ยังไม่มีเอกสารในระบบเลยครับ\\\\n\\\\nส่ง PDF/รูปภาพ เข้า LINE OA เพื่อเริ่มอัปโหลดได้เลย';\\n  return [{ json: { _text: emptyText } }];\\n}\\n\\nlet text = filter\\n  ? `📋 พบ ${rows.length} เอกสารที่ตรงกับ \\"${filter}\\" (แสดง ${rows.length}/${limit}):\\\\n\\\\n`\\n  : `📋 ตอนนี้มี ${rows.length} เอกสารในระบบ (แสดง ${rows.length}/${limit}):\\\\n\\\\n`;\\n\\nrows.forEach((r, i) => {\\n  const statusEmoji = r.status === 'ready' ? '✅' : r.status === 'pending' ? '⏳' : r.status === 'failed' ? '❌' : '❔';\\n  const date = r.uploaded_at ? new Date(r.uploaded_at).toLocaleDateString('th-TH', { year: 'numeric', month: 'short', day: 'numeric' }) : '';\\n  text += `${i+1}. ${statusEmoji} ${r.file_name}`;\\n  if (r.doc_no) text += ` (${r.doc_no})`;\\n  if (r.category) text += `\\\\n   หมวด: ${r.category} | chunks: ${r.chunk_count} | ${date}`;\\n  text += '\\\\n';\\n});\\n\\ntext += '\\\\n💡 พิมพ์ \\"หา[คำค้น]\\" เพื่อค้นหาแบบ semantic | \\"สรุปผล\\" เพื่อดูภาพรวม';\\n\\nreturn [{ json: { _text: text } }];\\n"},"id":"ai-format-list","name":"AI: Format List","type":"n8n-nodes-base.code","position":[2736,2112],"typeVersion":2},{"parameters":{"jsCode":"const rows = $('AI: Get Stats').all().map(i => i.json);\\nconst s = rows[0] || {};\\n\\nlet text = `📊 สรุปภาพรวมเอกสาร\\\\n\\\\n`;\\ntext += `📁 ทั้งหมด: ${s.total || 0} เอกสาร\\\\n`;\\ntext += `✅ พร้อมใช้งาน: ${s.ready || 0}\\\\n`;\\ntext += `⏳ กำลังประมวลผล: ${s.pending || 0}\\\\n`;\\ntext += `❌ ล้มเหลว: ${s.failed || 0}\\\\n\\\\n`;\\n\\nif (s.by_category && Array.isArray(s.by_category)) {\\n  text += `📂 แยกตามหมวดหมู่:\\\\n`;\\n  s.by_category.forEach(c => {\\n    text += `  • ${c.category}: ${c.count} ฉบับ\\\\n`;\\n  });\\n}\\n\\ntext += `\\\\n💡 พิมพ์ \\\\\\"list\\\\\\" เพื่อดูเอกสารทั้งหมด | \\\\\\"หา[คำค้น]\\\\\\" เพื่อค้นหา`;\\n\\nreturn [{ json: { _text: text } }];\\n"},"id":"ai-format-stats","name":"AI: Format Stats","type":"n8n-nodes-base.code","position":[2736,2400],"typeVersion":2},{"parameters":{"httpMethod":"POST","path":"vector-search-json","responseMode":"lastNode","options":{}},"id":"wh-vs-json","name":"JS-VS Webhook","type":"n8n-nodes-base.webhook","position":[48,112],"webhookId":"vs-json-wh","typeVersion":2},{"parameters":{"jsCode":"// Read q from either URL query OR body\\nconst wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst query = (q.q || body.q || '').toString().trim();\\nconst limit = parseInt(q.limit || body.limit || 10, 10) || 10;\\nreturn [{json: {query, _query: query, _limit: limit}}];\\n"},"id":"js-vs-parse","name":"JS-VS Parse","type":"n8n-nodes-base.code","position":[272,112],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || 'http://127.0.0.1:11434') }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.query) }} }","options":{"timeout":30000}},"id":"js-vs-embed","name":"JS-VS Embed","type":"n8n-nodes-base.httpRequest","position":[496,112],"typeVersion":4.1},{"parameters":{"operation":"executeQuery","query":"WITH q AS (SELECT $1::vector AS qvec, $3::text AS qtxt),\\nv AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         1 - (ch.embedding <=> q.qvec) AS v_sim,\\n         ROW_NUMBER() OVER (ORDER BY ch.embedding <=> q.qvec) AS v_rank\\n  FROM contract_chunks ch, q\\n  WHERE ch.embedding IS NOT NULL\\n  ORDER BY ch.embedding <=> q.qvec\\n  LIMIT $2::int * 2\\n),\\nt AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 1.0 ELSE 0 END)\\n         + (length(ch.content) - length(replace(ch.content, q.qtxt, '')))::float / greatest(length(q.qtxt), 1)::float * 0.1 AS t_sim,\\n         ROW_NUMBER() OVER (\\n           ORDER BY \\n             (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n             (length(ch.content) - length(replace(ch.content, q.qtxt, '')))::float DESC,\\n             ch.chunk_index ASC\\n         ) AS t_rank\\n  FROM contract_chunks ch, q\\n  ORDER BY \\n    (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n    (length(ch.content) - length(replace(ch.content, q.qtxt, '')))::float DESC\\n  LIMIT $2::int * 2\\n),\\nfused AS (\\n  SELECT COALESCE(v.contract_id, t.contract_id) AS contract_id,\\n         COALESCE(v.chunk_index, t.chunk_index) AS chunk_index,\\n         COALESCE(v.content, t.content) AS content,\\n         COALESCE(1.0/(60+v.v_rank), 0) + COALESCE(1.0/(60+t.t_rank), 0) AS rrf_score,\\n         COALESCE(v.v_sim, 0) AS vector_sim,\\n         COALESCE(t.t_sim, 0) AS keyword_sim\\n  FROM v FULL OUTER JOIN t USING (contract_id, chunk_index)\\n)\\nSELECT c.id AS contract_id, c.doc_no, c.file_name, f.chunk_index, f.content,\\n       f.rrf_score AS similarity, f.vector_sim, f.keyword_sim\\nFROM fused f JOIN contracts c ON c.id = f.contract_id\\nORDER BY f.rrf_score DESC\\nLIMIT $2::int","options":{"queryReplacement":"={{ [\\n  ($json.embeddings && $json.embeddings[0]) ? '[' + $json.embeddings[0].map(Number).join(',') + ']' : '[]',\\n  $json._limit || 10,\\n  $json._query || ''\\n] }}"}},"id":"js-vs-pg","name":"JS-VS PG","type":"n8n-nodes-base.postgres","position":[720,112],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Format hybrid search results as JSON\\nconst rows = $input.all().map(i => i.json).filter(r => r && r.contract_id);\\nreturn [{json: {\\n  ok: true,\\n  query: $('JS-VS Parse').first().json.query,\\n  count: rows.length,\\n  results: rows.map(r => ({\\n    contract_id: r.contract_id,\\n    doc_no: r.doc_no,\\n    file_name: r.file_name,\\n    chunk_index: r.chunk_index,\\n    content: r.content,\\n    similarity: parseFloat(r.similarity) || 0,\\n    vector_sim: parseFloat(r.vector_sim) || 0,\\n    keyword_sim: parseFloat(r.keyword_sim) || 0\\n  }))\\n}}];\\n"},"id":"js-vs-format","name":"JS-VS Format","type":"n8n-nodes-base.code","position":[944,112],"typeVersion":2},{"parameters":{"jsCode":"// Build LINE messages array: [text summary, flex cards]\\nconst bfc = $('AI: Build Flex Card').first().json || {};\\nlet aiSummary = '';\\ntry {\\n  const rr = $('Parse Re-rank Response').first().json;\\n  aiSummary = (rr && rr._summary ? rr._summary : '').toString().trim();\\n} catch (e) {}\\n\\nconst messages = [];\\n\\n// First: AI summary text (if available)\\nif (aiSummary) {\\n  messages.push({ type: 'text', text: aiSummary });\\n}\\n\\n// Second: Flex card or fallback text\\nlet cardMessage = null;\\nif (bfc._flex) {\\n  const flex = bfc._flex;\\n  if (flex.type === 'flex' && flex.altText && flex.contents) {\\n    cardMessage = flex;\\n  }\\n}\\nif (!cardMessage && bfc._fallback) {\\n  cardMessage = { type: 'text', text: bfc._fallback };\\n}\\nif (cardMessage) {\\n  messages.push(cardMessage);\\n}\\n\\n// Last resort: at least one message\\nif (messages.length === 0) {\\n  messages.push({ type: 'text', text: 'ไม่สามารถแสดงผลได้ในขณะนี้' });\\n}\\n\\nreturn [{ json: { messages } }];\\n"},"id":"build-safe-reply","name":"Build Safe Reply","type":"n8n-nodes-base.code","position":[3072,1920],"typeVersion":2},{"parameters":{"jsCode":"// Download LINE message content and expose both binary + base64 for storage.\\n// The channel token must come from the n8n runtime environment.\\nconst sm = $('Smart Router').first().json;\\nconst evt = sm._event || {};\\nconst messageId = evt.message?.id;\\nif (!messageId) {\\n  throw new Error('No message id from Smart Router event');\\n}\\n\\nconst token = ($env.LINE_CHANNEL_ACCESS_TOKEN || '').trim();\\nif (!token) {\\n  throw new Error('Missing LINE_CHANNEL_ACCESS_TOKEN in n8n environment');\\n}\\n\\nlet response;\\ntry {\\n  response = await this.helpers.httpRequest({\\n    method: 'GET',\\n    url: `https://api-data.line.me/v2/bot/message/${messageId}/content`,\\n    headers: { Authorization: `Bearer ${token}` },\\n    // n8n's helper maps 'encoding' -> axios 'responseType' (see\\n    // n8n-core/dist/execution-engine/.../http-request.js:60-62). 'encoding: null'\\n    // was silently coerced to axios 'responseType: null' which defaults to\\n    // 'json' -> UTF-8 decode + U+FFFD replacement for invalid bytes (verified June\\n    // 2026: 69,301 bytes -> 111,939 bytes with 21,746 U+FFFD chars).\\n    // 'encoding: arraybuffer' -> axios returns ArrayBuffer (raw bytes).\\n    encoding: 'arraybuffer',\\n    timeout: 30000,\\n  });\\n} catch (e) {\\n  throw new Error(`LINE content download failed: ${e.message} (message_id=${messageId})`);\\n}\\n\\n// responseType: 'arraybuffer' returns ArrayBuffer; wrap to Buffer for downstream ops.\\nconst buffer = Buffer.from(response);\\nif (!buffer || buffer.length === 0) {\\n  throw new Error('Empty response from LINE content API');\\n}\\n\\nconst msg = evt.message || {};\\nconst src = evt.source || {};\\nconst fname = msg.fileName || 'upload.pdf';\\nconst ext = fname.toLowerCase().split('.').pop();\\nlet mime = msg.type === 'image' ? 'image/jpeg' : 'application/octet-stream';\\nif (ext === 'pdf') mime = 'application/pdf';\\nelse if (ext === 'png') mime = 'image/png';\\nelse if (ext === 'jpg' || ext === 'jpeg') mime = 'image/jpeg';\\nelse if (ext === 'txt') mime = 'text/plain';\\nelse if (ext === 'docx') mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';\\n\\nconst b64 = buffer.toString('base64');\\nconst binaryData = await this.helpers.prepareBinaryData(buffer, fname, mime);\\n\\nreturn [{\\n  json: Object.assign({}, sm, {\\n    _event: evt,\\n    line_user_id: src.userId || '',\\n    line_group_id: src.groupId || '',\\n    line_message_id: messageId || '',\\n    file_type: ext || '',\\n    file_data_b64: b64,\\n    file_mime: mime,\\n    file_name: fname,\\n    file_size: buffer.length,\\n  }),\\n  binary: binaryData\\n}];\\n"},"id":"code-decode-prepare","name":"LINE Decode & Prepare Binary","type":"n8n-nodes-base.code","position":[944,464],"typeVersion":2},{"parameters":{"conditions":{"boolean":[{"value1":"={{ $json.has_chunks }}","value2":true}]}},"id":"node-300","name":"Has Chunks?","type":"n8n-nodes-base.if","position":[2064,464],"typeVersion":1},{"parameters":{"jsCode":"// Set _has_reply_token flag based on Smart Router's _replyToken\\nconst sr = $('Smart Router').first().json;\\nconst replyToken = sr._replyToken;\\nconst hasReplyToken = (typeof replyToken === 'string' && replyToken.length > 0);\\n\\n// Pass through input + add flag\\nconst input = $input.first().json;\\nreturn [{\\n  json: {\\n    ...input,\\n    _has_reply_token: hasReplyToken,\\n    _reply_token_value: replyToken || null\\n  }\\n}];"},"id":"code-check-rt","name":"Check Reply Token","type":"n8n-nodes-base.code","position":[1840,2336],"typeVersion":2},{"parameters":{"rules":{"values":[{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"equals"},"leftValue":"={{ String($json._has_reply_token) }}","rightValue":"true"}]},"renameOutput":true,"outputKey":"real_line"},{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":1},"combinator":"and","conditions":[{"operator":{"type":"string","operation":"notEquals"},"leftValue":"={{ String($json._has_reply_token) }}","rightValue":"true"}]},"renameOutput":true,"outputKey":"test_mode"}]},"options":{}},"id":"if-has-reply-token","name":"Has Reply Token?","type":"n8n-nodes-base.switch","position":[2064,2336],"typeVersion":3.2},{"parameters":{"jsCode":"// Rollback: collect the contract id we tried to save so we can DELETE it.\\nconst start = $('LINE Register Start').first();\\nconst id = start && start.json && start.json.id;\\nreturn [{ json: { contract_id: id, action: 'rollback' } }];\\n"},"id":"63098214-c190-4b93-8f32-4c94ffccb7fc","name":"LINE Rollback File","type":"n8n-nodes-base.code","position":[2736,624],"executeOnce":false,"typeVersion":2},{"parameters":{"operation":"executeQuery","query":"DELETE FROM contracts WHERE id = $1::uuid RETURNING id","options":{"queryReplacement":"={{ [$json.contract_id || ''] }}"}},"id":"4f9ec6d5-5947-4b71-8169-9d5b96595407","name":"LINE Delete Contract Row","type":"n8n-nodes-base.postgres","position":[2960,624],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Normalize Chunk text output to a boolean has_chunks field.\\n// IF v1 with strict typeValidation mis-evaluates Number($json.x) > 0\\n// when chunk_count is 0, so we do the comparison here in JS land.\\nconst info = $input.first().json || {};\\nconst chunkCount = Number(info.chunk_count || 0);\\nconst hasChunks = chunkCount > 0;\\nreturn [{\\n  json: Object.assign({}, info, {\\n    chunk_count: chunkCount,\\n    has_chunks: hasChunks,\\n  })\\n}];\\n"},"id":"node-301","name":"LINE: Normalize Has Chunks","type":"n8n-nodes-base.code","position":[1840,464],"typeVersion":2},{"parameters":{"httpMethod":"POST","path":"contract-rag-line","responseMode":"responseNode","options":{}},"id":"line-webhook-trigger","name":"LINE Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[48,1008],"webhookId":"contract-rag-line-webhook"},{"parameters":{"method":"POST","url":"http://127.0.0.1:8765/vision","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={{ JSON.stringify({ file_data_b64: $json.file_data_b64, file_mime: $json.file_mime, file_name: $json.file_name }) }}","options":{"timeout":180000}},"id":"line-extract-vision","name":"LINE Extract via Vision LLM","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[1168,464]},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || 'http://127.0.0.1:11434') }}/api/chat","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_AGENT_MODEL || 'qwen3.6:35b-a3b-q4_K_M' }}\\",\\n  \\"stream\\": false,\\n  \\"format\\": \\"json\\",\\n  \\"messages\\": {{ JSON.stringify([\\n    {role: 'system', content: 'คุณคือผู้ช่วยคัดเลือกเอกสาร (re-ranker) สำหรับสำนักงานกฎหมายไทย\\\\n\\\\nหน้าที่ของคุณ:\\\\n1. อ่าน search results ที่ได้รับ (อาจมี similarity ต่ำ เพราะ embedding model เป็น general purpose)\\\\n2. ดูชื่อไฟล์ + เนื้อหาตัวอย่าง แล้วเลือก 3-5 ฉบับที่เกี่ยวข้องกับ query จริงๆ (เรียงตามความเกี่ยวข้อง)\\\\n3. เขียนสรุปสั้นๆ 1-2 บรรทัดเป็นภาษาไทย บอกว่า:\\\\n   - พบเอกสารที่ตรง query กี่ฉบับ (ระบุ doc_no)\\\\n   - ถ้ามี noise (เอกสารไม่เกี่ยว) ให้บอกด้วยว่าเป็นประเภทอื่น\\\\n   - ถ้าไม่มีตรงเลย ให้บอกว่าไม่พบและแนะนำให้ลองคำอื่น\\\\n\\\\nตอบเป็น JSON เท่านั้น:\\\\n{\\"summary\\": \\"ข้อความสรุป 1-2 บรรทัด\\", \\"selected_doc_nos\\": [\\"DOC-XXX\\", \\"DOC-YYY\\"]}\\\\n\\\\nถ้าไม่มีเอกสารที่เกี่ยวข้องเลย ให้ selected_doc_nos เป็น array ว่าง'},\\n    {role: 'user', content: 'Query: ' + $('Parse AI Response').first().json._query + '\\\\n\\\\nSearch results:\\\\n' + JSON.stringify(($('AI: Call Vector Search').first().json.results || []).map((r, i) => '[' + (i+1) + '] doc_no=' + r.doc_no + ', file=' + r.file_name + ', sim=' + ((r.similarity || 0)*100).toFixed(1) + '%\\\\n    content: ' + (r.content || '').slice(0, 200).replace(/\\\\n/g, ' ')))}\\n  ]) }}\\n}","options":{"response":{"response":{"neverError":true}},"timeout":600000}},"id":"ai-rerank-http","name":"AI: Re-rank & Summarize","type":"n8n-nodes-base.httpRequest","position":[2624,1920],"typeVersion":4.2},{"parameters":{"jsCode":"// Parse Ollama re-rank response\\nconst resp = $('AI: Re-rank & Summarize').first().json;\\nconst msg = resp.message || {};\\nconst content = (msg.content || '').trim();\\nconst thinking = (msg.thinking || '').trim();\\nconst allText = content || thinking;\\n\\nlet summary = '';\\nlet selected = [];\\n\\n// Try to parse JSON from content\\nif (content) {\\n  try {\\n    // Ollama format:json sometimes wraps in ```json ... ```\\n    let cleanContent = content.replace(/^```json\\\\s*/i, '').replace(/```\\\\s*$/, '').trim();\\n    const parsed = JSON.parse(cleanContent);\\n    summary = (parsed.summary || '').toString().trim();\\n    if (Array.isArray(parsed.selected_doc_nos)) {\\n      selected = parsed.selected_doc_nos.map(s => s.toString().trim()).filter(Boolean);\\n    }\\n  } catch (e) {\\n    // Try to extract JSON object from text\\n    const jsonMatch = content.match(/\\\\{[\\\\s\\\\S]*\\\\}/);\\n    if (jsonMatch) {\\n      try {\\n        const parsed = JSON.parse(jsonMatch[0]);\\n        summary = (parsed.summary || '').toString().trim();\\n        if (Array.isArray(parsed.selected_doc_nos)) {\\n          selected = parsed.selected_doc_nos.map(s => s.toString().trim()).filter(Boolean);\\n        }\\n      } catch (e2) {\\n        // Give up on JSON - treat whole content as summary\\n        summary = content.slice(0, 300);\\n      }\\n    } else {\\n      summary = content.slice(0, 300);\\n    }\\n  }\\n}\\n\\nreturn [{\\n  json: {\\n    _summary: summary,\\n    _selected_doc_nos: selected,\\n    _raw_content: content\\n  }\\n}];\\n"},"id":"ai-rerank-parse","name":"Parse Re-rank Response","type":"n8n-nodes-base.code","position":[2736,1920],"typeVersion":2}]	{"JS-VS PG":{"main":[[{"node":"JS-VS Format","type":"main","index":0}]]},"Is stats?":{"main":[[{"node":"PG: Aggregate Stats","type":"main","index":0}],[{"node":"Respond Not Stats","type":"main","index":0}]]},"Embed Query":{"main":[[{"node":"Build Vector Params","type":"main","index":0}]]},"Has Chunks?":{"main":[[{"node":"LINE Embed all chunks (Ollama bge-m3)","type":"main","index":0}],[{"node":"LINE Rollback File","type":"main","index":1}]]},"JS-VS Embed":{"main":[[{"node":"JS-VS PG","type":"main","index":0}]]},"JS-VS Parse":{"main":[[{"node":"JS-VS Embed","type":"main","index":0}]]},"Mode Switch":{"main":[[{"node":"PG: List Docs","type":"main","index":0}],[{"node":"Embed Query","type":"main","index":0}]]},"Render HTML":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"Docs Webhook":{"main":[[{"node":"Smart Router","type":"main","index":0}]]},"Parse Search":{"main":[[{"node":"Mode Switch","type":"main","index":0}]]},"Route Switch":{"main":[[{"node":"LINE: Is file?","type":"main","index":0}],[{"node":"Prep Registry Row","type":"main","index":0}],[{"node":"Parse Stats Request","type":"main","index":0}],[{"node":"Parse Search","type":"main","index":0}]]},"Smart Router":{"main":[[{"node":"Route Switch","type":"main","index":0}]]},"AI: Get Stats":{"main":[[{"node":"AI: Format Stats","type":"main","index":0}]]},"JS-VS Webhook":{"main":[[{"node":"JS-VS Parse","type":"main","index":0}]]},"PG: By Status":{"main":[[{"node":"Render HTML","type":"main","index":0}]]},"PG: List Docs":{"main":[[{"node":"PG: Daily Activity","type":"main","index":0}]]},"Respond Stats":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: Reply Text":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: Send Reply":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"LINE: Is file?":{"main":[[{"node":"LINE Decode & Prepare Binary","type":"main","index":0}],[{"node":"AI Agent (Ollama)","type":"main","index":0}]]},"AI Route Switch":{"main":[[{"node":"AI: Call Vector Search","type":"main","index":0}],[{"node":"AI: List Contracts","type":"main","index":0}],[{"node":"AI: Get Stats","type":"main","index":0}],[{"node":"AI: Reply Text","type":"main","index":0}]]},"AI: Format List":{"main":[[{"node":"AI: Reply Text","type":"main","index":0}]]},"Format Response":{"main":[[{"node":"Respond Docs","type":"main","index":0}]]},"LINE Chunk text":{"main":[[{"node":"LINE: Normalize Has Chunks","type":"main","index":0}]]},"Needs generate?":{"main":[[{"node":"PG: Get Next Seq","type":"main","index":0}],[{"node":"Passthrough (use provided doc_no)","type":"main","index":0}]]},"AI: Format Stats":{"main":[[{"node":"AI: Reply Text","type":"main","index":0}]]},"Build Safe Reply":{"main":[[{"node":"AI: Send Reply","type":"main","index":0}]]},"Has Reply Token?":{"main":[[{"node":"AI Route Switch","type":"main","index":0}],[{"node":"Format Response","type":"main","index":0}]]},"LINE Reply Error":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"PG: Get Next Seq":{"main":[[{"node":"PG: Insert/Update Document","type":"main","index":0}]]},"Respond Registry":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI Agent (Ollama)":{"main":[[{"node":"Parse AI Response","type":"main","index":0}]]},"Check Reply Token":{"main":[[{"node":"Has Reply Token?","type":"main","index":0}]]},"Format Stats Text":{"main":[[{"node":"Respond Stats","type":"main","index":0}]]},"PG: Vector Search":{"main":[[{"node":"PG: Daily Activity","type":"main","index":0}]]},"Parse AI Response":{"main":[[{"node":"Check Reply Token","type":"main","index":0}]]},"Prep Registry Row":{"main":[[{"node":"Needs generate?","type":"main","index":0}]]},"Respond Not Stats":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: List Contracts":{"main":[[{"node":"AI: Format List","type":"main","index":0}]]},"LINE Reply Success":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"LINE Rollback File":{"main":[[{"node":"LINE Delete Contract Row","type":"main","index":0}]]},"PG: Daily Activity":{"main":[[{"node":"PG: Recent Activity","type":"main","index":0}]]},"AI: Build Flex Card":{"main":[[{"node":"Build Safe Reply","type":"main","index":0}]]},"Build Vector Params":{"main":[[{"node":"PG: Vector Search","type":"main","index":0}]]},"LINE Register Start":{"main":[[{"node":"LINE Chunk text","type":"main","index":0}]]},"PG: Aggregate Stats":{"main":[[{"node":"Format Stats Text","type":"main","index":0}]]},"PG: Recent Activity":{"main":[[{"node":"PG: By Status","type":"main","index":0}]]},"Parse Stats Request":{"main":[[{"node":"Is stats?","type":"main","index":0}]]},"LINE: Reply Non-File":{"main":[[{"node":"Format Response","type":"main","index":0}]]},"AI: Call Vector Search":{"main":[[{"node":"AI: Re-rank & Summarize","type":"main","index":0}]]},"LINE Delete Contract Row":{"main":[[{"node":"LINE Reply Error","type":"main","index":0}]]},"PG: Insert/Update Document":{"main":[[{"node":"Respond Registry","type":"main","index":0}]]},"LINE Decode & Prepare Binary":{"main":[[{"node":"LINE Extract via Vision LLM","type":"main","index":0}]]},"LINE Combine metadata + vectors":{"main":[[{"node":"LINE Build Store SQL","type":"main","index":0}]]},"Passthrough (use provided doc_no)":{"main":[[{"node":"PG: Insert/Update Document","type":"main","index":0}]]},"LINE Embed all chunks (Ollama bge-m3)":{"main":[[{"node":"LINE Combine metadata + vectors","type":"main","index":0}]]},"LINE: Normalize Has Chunks":{"main":[[{"node":"Has Chunks?","type":"main","index":0}]]},"LINE Webhook":{"main":[[{"node":"Smart Router","type":"main","index":0}]]},"LINE Extract via Vision LLM":{"main":[[{"node":"LINE Register Start","type":"main","index":0}]]},"LINE Build Store SQL":{"main":[[{"node":"PG: Store Embeddings","type":"main","index":0}]]},"PG: Store Embeddings":{"main":[[{"node":"LINE Reply Success","type":"main","index":0}],[{"node":"LINE Reply Error","type":"main","index":1}]]},"AI: Re-rank & Summarize":{"main":[[{"node":"Parse Re-rank Response","type":"main","index":0}]]},"Parse Re-rank Response":{"main":[[{"node":"AI: Build Flex Card","type":"main","index":0}]]}}	\N	f	\N	[]
4936517b-f48b-4073-9755-0467045e870c	AdM1nFlow12345678CD0cHub2	Fluke Jesadakorn	2026-06-23 22:45:37.633+07	2026-06-23 22:45:37.633+07	[{"parameters":{"path":"docs-admin-ui","responseMode":"responseNode","options":{}},"id":"wh-admin-ui","name":"Admin UI Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,0],"webhookId":"admin-ui-webhook"},{"parameters":{"jsCode":"// Return HTML page for Docs Admin\\nconst html = `<!doctype html>\\n<html lang=\\"th\\">\\n<head>\\n<meta charset=\\"utf-8\\">\\n<title>Docs Admin | Phuket Law</title>\\n<meta name=\\"viewport\\" content=\\"width=device-width,initial-scale=1\\">\\n<script>\\n  // No-flash theme bootstrap: set data-theme BEFORE <style> parses so first\\n  // paint uses the right colors. Order: localStorage > OS preference > dark.\\n  (function(){\\n    try{\\n      var saved = localStorage.getItem('lawpoc-admin-theme');\\n      var theme = saved || (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');\\n      document.documentElement.setAttribute('data-theme', theme);\\n    }catch(e){ document.documentElement.setAttribute('data-theme', 'dark'); }\\n  })();\\n</script>\\n<style>\\n:root{\\n  /* Core tokens (light defaults) */\\n  --bg:#f6f7f9;--card:#fff;--ink:#0f172a;--muted:#64748b;--muted-2:#94a3b8;\\n  --bd:#e2e8f0;--bd-soft:#f1f5f9;\\n  --pri:#0f766e;--pri-2:#0d9488;--warn:#b45309;--err:#b91c1c;--ok:#15803d;\\n\\n  /* Component tokens (light) */\\n  --header-bg:#0f172a;--header-fg:#fff;--crumb-fg:#94a3b8;\\n  --hover-bg:#f1f5f9;--th-bg:#f8fafc;\\n  --row-divider:#f1f5f9;--row-hover-bg:#fafbfc;\\n  --mono-fg:#475569;--chunk-text:#334155;\\n  --modal-overlay:rgba(15,23,42,.5);--modal-card:#fff;--modal-ft-bg:#f8fafc;\\n  --file-preview-bg:#f8fafc;--input-bg:#fff;\\n  --toast-bg:#0f172a;--toast-fg:#fff;\\n  --spinner-border:#fff;\\n  --sticky-act-shadow:rgba(15,23,42,.15);\\n\\n  /* Status badges (light = pastel solid; dark = semi-transparent tinted) */\\n  --badge-ready-bg:#dcfce7;     --badge-ready-fg:#15803d;\\n  --badge-pending-bg:#fef3c7;   --badge-pending-fg:#b45309;\\n  --badge-failed-bg:#fee2e2;    --badge-failed-fg:#b91c1c;\\n  --badge-processing-bg:#dbeafe;--badge-processing-fg:#1d4ed8;\\n\\n  /* Shadow tokens */\\n  --shadow-sm:0 1px 2px rgba(15,23,42,.06);\\n  --shadow-md:0 4px 12px rgba(15,23,42,.08);\\n}\\n[data-theme=\\"dark\\"]{\\n  --bg:#0e1422;--card:#161e35;--ink:#f1f5f9;--muted:#94a3b8;--muted-2:#64748b;\\n  --bd:rgba(148,163,184,.15);--bd-soft:rgba(148,163,184,.08);\\n  --pri:#2dd4bf;--pri-2:#14b8a6;--warn:#fbbf24;--err:#f87171;--ok:#4ade80;\\n\\n  --header-bg:#050a17;--header-fg:#f1f5f9;--crumb-fg:#64748b;\\n  --hover-bg:rgba(148,163,184,.08);--th-bg:rgba(148,163,184,.05);\\n  --row-divider:rgba(148,163,184,.08);--row-hover-bg:rgba(20,184,166,.05);\\n  --mono-fg:#cbd5e1;--chunk-text:#cbd5e1;\\n  --modal-overlay:rgba(0,0,0,.7);--modal-card:#161e35;--modal-ft-bg:#0e1422;\\n  --file-preview-bg:#0e1422;--input-bg:#0e1422;\\n  --toast-bg:#f1f5f9;--toast-fg:#0f172a;\\n  --spinner-border:#0e1422;\\n  --sticky-act-shadow:rgba(0,0,0,.5);\\n\\n  --badge-ready-bg:rgba(34,197,94,.18);     --badge-ready-fg:#4ade80;\\n  --badge-pending-bg:rgba(245,158,11,.18);   --badge-pending-fg:#fbbf24;\\n  --badge-failed-bg:rgba(239,68,68,.18);    --badge-failed-fg:#f87171;\\n  --badge-processing-bg:rgba(59,130,246,.18);--badge-processing-fg:#60a5fa;\\n\\n  --shadow-sm:0 1px 2px rgba(0,0,0,.4);\\n  --shadow-md:0 4px 12px rgba(0,0,0,.4);\\n}\\n*{box-sizing:border-box}\\nbody{font:14px/1.5 -apple-system,\\"SF Pro Text\\",\\"Inter\\",system-ui,sans-serif;margin:0;background:var(--bg);color:var(--ink);transition:background-color .2s ease,color .2s ease}\\nheader{background:var(--header-bg);color:var(--header-fg);padding:14px 24px;display:flex;align-items:center;gap:16px;box-shadow:0 1px 0 rgba(0,0,0,.2);transition:background-color .2s ease}\\nheader h1{font-size:16px;font-weight:600;margin:0;letter-spacing:.2px}\\nheader .crumb{color:var(--crumb-fg);font-size:12px;margin-left:auto}\\nheader .theme-toggle{margin-left:8px;background:transparent;color:var(--header-fg);border:1px solid rgba(255,255,255,.18);border-radius:8px;height:32px;width:32px;padding:0;cursor:pointer;font-size:14px;display:inline-flex;align-items:center;justify-content:center;transition:all .15s}\\nheader .theme-toggle:hover{background:rgba(255,255,255,.08);border-color:rgba(255,255,255,.35)}\\n.wrap{max-width:1280px;margin:0 auto;padding:24px}\\n.toolbar{display:flex;gap:8px;align-items:center;margin-bottom:16px;flex-wrap:wrap}\\n.toolbar input,.toolbar select{height:36px;padding:0 12px;border:1px solid var(--bd);border-radius:8px;background:var(--input-bg);font:inherit;color:var(--ink);outline:none;transition:border-color .15s,box-shadow .15s}\\n.toolbar input:focus,.toolbar select:focus{border-color:var(--pri-2);box-shadow:0 0 0 3px rgba(13,148,136,.2)}\\n.toolbar input.search{flex:1;min-width:200px}\\n\\n.similarity-bar{display:inline-block;height:6px;border-radius:3px;background:var(--bd);width:60px;vertical-align:middle;margin-right:6px;position:relative;overflow:hidden}\\n.similarity-bar>span{position:absolute;left:0;top:0;bottom:0;background:var(--pri)}\\n.chunk-preview{font-size:11px;color:var(--muted);margin-top:4px;line-height:1.4;max-width:420px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\\n.btn{height:36px;padding:0 14px;border:0;border-radius:8px;background:var(--pri);color:#fff;font:inherit;font-weight:500;cursor:pointer;display:inline-flex;align-items:center;gap:6px;transition:background-color .15s,box-shadow .15s,transform .05s}\\n.btn:hover{background:var(--pri-2)}\\n.btn:active{transform:translateY(1px)}\\n.btn.ghost{background:transparent;color:var(--ink);border:1px solid var(--bd)}\\n.btn.ghost:hover{background:var(--hover-bg)}\\n.btn.warn{background:var(--warn)}\\n.btn.danger{background:var(--err)}\\n.btn.sm{height:28px;padding:0 10px;font-size:12px;border-radius:6px}\\n.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}\\n.stat{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:14px;box-shadow:var(--shadow-sm);transition:background-color .2s ease,border-color .2s ease}\\n.stat .label{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}\\n.stat .num{font-size:24px;font-weight:600;margin-top:4px}\\n.stat .num.warn{color:var(--warn)} .stat .num.ok{color:var(--ok)} .stat .num.err{color:var(--err)}\\n.card{background:var(--card);border:1px solid var(--bd);border-radius:12px;overflow-x:auto;box-shadow:var(--shadow-sm);transition:background-color .2s ease,border-color .2s ease}\\ntable{width:100%;border-collapse:collapse;font-size:13px}\\nth{text-align:left;padding:12px 14px;background:var(--th-bg);font-weight:600;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.4px;border-bottom:1px solid var(--bd)}\\ntd{padding:12px 14px;border-bottom:1px solid var(--row-divider);vertical-align:middle}\\ntr:hover td{background:var(--row-hover-bg)}\\ntr:last-child td{border-bottom:0}\\ntd.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--mono-fg)}\\ntd .name{font-weight:500;color:var(--ink)}\\ntd .name small{display:block;color:var(--muted);font-weight:400;font-size:11px;margin-top:2px}\\n.badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:500}\\n.badge.ready{background:var(--badge-ready-bg);color:var(--badge-ready-fg)}\\n.badge.pending{background:var(--badge-pending-bg);color:var(--badge-pending-fg)}\\n.badge.failed{background:var(--badge-failed-bg);color:var(--badge-failed-fg)}\\n.badge.processing{background:var(--badge-processing-bg);color:var(--badge-processing-fg)}\\n.empty{padding:60px 20px;text-align:center;color:var(--muted)}\\n.empty h3{margin:0 0 6px;font-weight:500;color:var(--ink)}\\n.row-actions{display:flex;gap:6px;justify-content:flex-end;position:sticky;right:0;background:var(--card);padding-left:12px;box-shadow:-8px 0 12px -6px var(--sticky-act-shadow)}\\n.row-actions::before{content:'';position:absolute;left:-12px;top:0;bottom:0;width:12px;background:linear-gradient(to right,transparent,var(--card) 70%);pointer-events:none}\\nth.sticky-act{position:sticky;right:0;background:var(--th-bg);z-index:2;box-shadow:-8px 0 12px -6px var(--sticky-act-shadow)}\\n.modal{position:fixed;inset:0;background:var(--modal-overlay);display:none;align-items:center;justify-content:center;z-index:50;padding:20px}\\n.modal.on{display:flex}\\n.modal .box{background:var(--modal-card);border-radius:12px;width:100%;max-width:760px;max-height:90vh;display:flex;flex-direction:column;overflow:hidden;box-shadow:var(--shadow-md)}\\n#m-view .box{max-width:1180px}\\n.preview-grid{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(320px,.75fr);gap:16px}\\n.preview-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px}\\n.file-preview{height:min(66vh,720px);min-height:420px;border:1px solid var(--bd);border-radius:8px;overflow:hidden;background:var(--file-preview-bg)}\\n.file-preview iframe{width:100%;height:100%;border:0;background:var(--input-bg)}\\n.meta-grid{grid-template-columns:1fr 1fr}\\n@media(max-width:900px){.preview-grid{grid-template-columns:1fr}.file-preview{height:60vh;min-height:320px}.grid2,.meta-grid{grid-template-columns:1fr}}\\n.modal .hd{padding:16px 20px;border-bottom:1px solid var(--bd);display:flex;align-items:center;gap:12px}\\n.modal .hd h2{margin:0;font-size:16px;font-weight:600;flex:1}\\n.modal .bd{padding:20px;overflow-y:auto;flex:1}\\n.modal .ft{padding:14px 20px;border-top:1px solid var(--bd);display:flex;justify-content:flex-end;gap:8px;background:var(--modal-ft-bg)}\\n.field{margin-bottom:14px}\\n.field label{display:block;font-size:12px;font-weight:500;color:var(--muted);margin-bottom:4px}\\n.field input,.field select,.field textarea{width:100%;padding:8px 10px;border:1px solid var(--bd);border-radius:6px;font:inherit;background:var(--input-bg);color:var(--ink);transition:border-color .15s,box-shadow .15s}\\n.field input:focus,.field select:focus,.field textarea:focus{outline:none;border-color:var(--pri-2);box-shadow:0 0 0 3px rgba(13,148,136,.2)}\\n.field .hint{font-size:11px;color:var(--muted);margin-top:3px}\\n.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}\\n.chunk-list{margin-top:8px;max-height:340px;overflow-y:auto;border:1px solid var(--bd);border-radius:6px;background:var(--input-bg)}\\n.chunk{padding:10px 12px;border-bottom:1px solid var(--bd-soft);font-size:12px}\\n.chunk:last-child{border-bottom:0}\\n.chunk .ci{color:var(--muted);font-family:ui-monospace,monospace;font-size:11px}\\n.chunk .cp{color:var(--chunk-text);margin-top:4px;line-height:1.4}\\n.toast{position:fixed;bottom:20px;right:20px;background:var(--toast-bg);color:var(--toast-fg);padding:12px 18px;border-radius:8px;font-size:13px;opacity:0;transform:translateY(10px);transition:all .2s;z-index:100;max-width:360px;box-shadow:var(--shadow-md)}\\n.toast.on{opacity:1;transform:translateY(0)}\\n.toast.err{background:var(--err);color:#fff}\\n.toast.ok{background:var(--ok);color:#fff}\\nmark.match{background:#fef08a;color:#713f12;padding:0 3px;border-radius:3px;font-weight:500}\\n.match-cell{max-width:240px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px;color:var(--mono-fg)}\\n.spin{display:inline-block;width:14px;height:14px;border:2px solid var(--spinner-border);border-top-color:transparent;border-radius:50%;animation:spin 1s linear infinite}\\n@keyframes spin{to{transform:rotate(360deg)}}\\n.loading{padding:40px;text-align:center;color:var(--muted)}\\n</style>\\n</head>\\n<body>\\n<header>\\n  <h1>📑 Docs Admin</h1>\\n  <button class=\\"theme-toggle\\" id=\\"btn-theme\\" aria-label=\\"สลับโหมดมืด/สว่าง\\" title=\\"สลับโหมดมืด/สว่าง\\">\\n    <span id=\\"theme-icon\\">🌙</span>\\n  </button>\\n  <span class=\\"crumb\\" id=\\"crumb\\">Phuket Law Firm • LINE-fed document store</span>\\n</header>\\n<div class=\\"wrap\\">\\n  <div class=\\"stats\\" id=\\"stats\\">\\n    <div class=\\"stat\\"><div class=\\"label\\">Total</div><div class=\\"num\\" id=\\"stat-total\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Ready</div><div class=\\"num ok\\" id=\\"stat-ready\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Pending</div><div class=\\"num warn\\" id=\\"stat-pending\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Failed</div><div class=\\"num err\\" id=\\"stat-failed\\">—</div></div>\\n  </div>\\n  <div class=\\"toolbar\\">\\n    <input class=\\"search\\" id=\\"q\\" placeholder=\\"🔍 ค้นหาในเนื้อหา (semantic)\\">\\n    <select id=\\"f-status\\">\\n      <option value=\\"\\">สถานะทั้งหมด</option>\\n      <option value=\\"ready\\">ready</option>\\n      <option value=\\"pending\\">pending</option>\\n      <option value=\\"failed\\">failed</option>\\n      <option value=\\"processing\\">processing</option>\\n    </select>\\n    <button class=\\"btn ghost\\" id=\\"btn-refresh\\">↻ รีเฟรช</button>\\n  </div>\\n  <div class=\\"card\\">\\n    <table>\\n      <thead><tr>\\n        <th style=\\"width:130px\\">Doc No</th>\\n        <th>ชื่อไฟล์</th>\\n        <th style=\\"width:110px\\">ความเหมือน</th>\\n        <th style=\\"width:240px\\">Match</th>\\n        <th style=\\"width:110px\\">Category</th>\\n        <th style=\\"width:90px\\">Status</th>\\n        <th style=\\"width:60px;text-align:right\\">Chunks</th>\\n        <th style=\\"width:130px\\">อัปโหลด</th>\\n        <th class=\\"sticky-act\\" style=\\"width:200px\\"></th>\\n      </tr></thead>\\n      <tbody id=\\"tbody\\">\\n        <tr><td colspan=\\"9\\" class=\\"loading\\">กำลังโหลด…</td></tr>\\n      </tbody>\\n    </table>\\n  </div>\\n</div>\\n\\n<!-- View Modal -->\\n<div class=\\"modal\\" id=\\"m-view\\">\\n  <div class=\\"box\\">\\n    <div class=\\"hd\\"><h2 id=\\"v-title\\">รายละเอียดเอกสาร</h2><button class=\\"btn ghost sm\\" onclick=\\"closeModal('m-view')\\">✕</button></div>\\n    <div class=\\"bd\\" id=\\"v-body\\"></div>\\n    <div class=\\"ft\\"><button class=\\"btn ghost\\" onclick=\\"closeModal('m-view')\\">ปิด</button><button class=\\"btn ghost\\" id=\\"v-open-btn\\">เปิดไฟล์</button><button class=\\"btn\\" id=\\"v-edit-btn\\">แก้ไข</button></div>\\n  </div>\\n</div>\\n\\n<!-- Edit Modal -->\\n<div class=\\"modal\\" id=\\"m-edit\\">\\n  <div class=\\"box\\">\\n    <div class=\\"hd\\"><h2>แก้ไขเอกสาร</h2><button class=\\"btn ghost sm\\" onclick=\\"closeModal('m-edit')\\">✕</button></div>\\n    <div class=\\"bd\\">\\n      <input type=\\"hidden\\" id=\\"e-id\\">\\n      <div class=\\"grid2\\">\\n        <div class=\\"field\\"><label>Doc No</label><input id=\\"e-doc_no\\" disabled><div class=\\"hint\\">ไม่สามารถแก้ไขได้</div></div>\\n        <div class=\\"field\\"><label>Status</label>\\n          <select id=\\"e-status\\"><option value=\\"ready\\">ready</option><option value=\\"pending\\">pending</option><option value=\\"failed\\">failed</option><option value=\\"processing\\">processing</option></select>\\n        </div>\\n      </div>\\n      <div class=\\"field\\"><label>ชื่อไฟล์</label><input id=\\"e-file_name\\"></div>\\n      <div class=\\"grid2\\">\\n        <div class=\\"field\\"><label>Category</label><input id=\\"e-category\\" placeholder=\\"เช่น สัญญาเช่า, หนังสือมอบอำนาจ\\"></div>\\n        <div class=\\"field\\"><label>Source</label><input id=\\"e-source\\" placeholder=\\"เช่น LINE OA, web upload\\"></div>\\n      </div>\\n    </div>\\n    <div class=\\"ft\\">\\n      <button class=\\"btn ghost\\" onclick=\\"closeModal('m-edit')\\">ยกเลิก</button>\\n      <button class=\\"btn\\" id=\\"e-save\\">บันทึก</button>\\n    </div>\\n  </div>\\n</div>\\n\\n<div class=\\"toast\\" id=\\"toast\\"></div>\\n\\n<script>\\nconst BASE = location.origin;\\nlet allRows = [];\\nlet statsCache = null;\\nlet currentQuery = '';\\n\\n// =========================================================================\\n// Theme switcher (toggle dark/light, persist in localStorage, respect OS pref)\\n// =========================================================================\\nconst themeBtn = document.getElementById('btn-theme');\\nconst themeIcon = document.getElementById('theme-icon');\\nconst THEME_KEY = 'lawpoc-admin-theme';\\nconst themeMedia = window.matchMedia('(prefers-color-scheme: light)');\\n\\nfunction currentTheme(){ return document.documentElement.getAttribute('data-theme') || 'light'; }\\n\\nfunction syncThemeIcon(theme){\\n  // Show the icon of the CURRENT theme so the button reflects page state\\n  themeIcon.textContent = theme === 'dark' ? '🌙' : '☀️';\\n  themeBtn.setAttribute('aria-label', theme === 'dark' ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด');\\n  themeBtn.setAttribute('title', theme === 'dark' ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด');\\n}\\n\\nfunction applyTheme(theme, persist){\\n  document.documentElement.setAttribute('data-theme', theme);\\n  syncThemeIcon(theme);\\n  if(persist){ try{ localStorage.setItem(THEME_KEY, theme); }catch(e){} }\\n}\\n\\nthemeBtn.addEventListener('click', ()=>{\\n  applyTheme(currentTheme() === 'dark' ? 'light' : 'dark', true);\\n});\\n\\n// Sync icon to whatever the head bootstrap set\\nsyncThemeIcon(currentTheme());\\n\\n// If user hasn't explicitly chosen, follow OS theme changes live\\nthemeMedia.addEventListener('change', e=>{\\n  let saved = null;\\n  try{ saved = localStorage.getItem(THEME_KEY); }catch(err){}\\n  if(!saved) applyTheme(e.matches ? 'light' : 'dark', false);\\n});\\n// =========================================================================\\n\\nfunction toast(msg, kind=''){\\n  const t = document.getElementById('toast');\\n  t.textContent = msg;\\n  t.className = 'toast on ' + kind;\\n  setTimeout(()=>t.className='toast '+kind, 2200);\\n}\\n\\nasync function api(path, opts){\\n  const r = await fetch(BASE + path, opts);\\n  if (!r.ok) throw new Error('HTTP '+r.status);\\n  return r.json();\\n}\\n\\nfunction fmtDate(s){\\n  if(!s) return '—';\\n  const d = new Date(s);\\n  return d.toLocaleString('th-TH',{dateStyle:'short',timeStyle:'short'});\\n}\\n\\nfunction esc(s){return String(s??'').replace(/[&<>\\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\\"':'&quot;',\\"'\\":'&#39;'}[c]))}\\n\\nasync function loadStats(){\\n  try{\\n    const s = await api('/webhook/admin-stats');\\n    const v = (s && s.data) || s;\\n    if (typeof v === 'string') { try { v = JSON.parse(v); } catch {} }\\n    document.getElementById('stat-total').textContent = v.total??0;\\n    document.getElementById('stat-ready').textContent = v.ready??0;\\n    document.getElementById('stat-pending').textContent = v.pending??0;\\n    document.getElementById('stat-failed').textContent = v.failed??0;\\n  }catch(e){console.warn('stats',e)}\\n}\\n\\nasync function loadList(){\\n  const q = document.getElementById('q').value.trim();\\n  const st = document.getElementById('f-status').value;\\n  const params = new URLSearchParams();\\n  if(st) params.set('status', st);\\n  params.set('limit', '200');\\n  // Empty q → admin-list (full listing, no embedding). Non-empty q → admin-semantic-search.\\n  const endpoint = q ? '/webhook/admin-semantic-search' : '/webhook/admin-list';\\n  if (q) params.set('q', q);\\n  currentQuery = q;\\n  try{\\n    const data = await api(endpoint+'?'+params.toString());\\n    allRows = Array.isArray(data)?data:((data&&data.data)||[]);\\n    render(q ? 'semantic' : 'list');\\n  }catch(e){\\n    document.getElementById('tbody').innerHTML = \\\\`<tr><td colspan=\\"9\\" class=\\"empty\\"><h3>โหลดไม่สำเร็จ</h3>\\\\${esc(e.message)}</td></tr>\\\\`;\\n  }\\n}\\n\\nfunction render(mode){\\n  const tb = document.getElementById('tbody');\\n  if(!allRows.length){\\n    const msg = (mode === 'semantic') ? 'ไม่พบเอกสารที่คล้ายกัน' : 'ไม่มีเอกสาร';\\n    const hint = (mode === 'semantic') ? 'ลองค้นหาด้วยคำอื่น' : 'อัปโหลดผ่าน LINE OA เพื่อเริ่มต้น';\\n    tb.innerHTML = \\\\`<tr><td colspan=\\"9\\" class=\\"empty\\"><h3>\\\\${esc(msg)}</h3>\\\\${esc(hint)}</td></tr>\\\\`;\\n    return;\\n  }\\n  // Build match snippet: find query in top_chunk_content, show ~20\\n  // chars context on each side with <mark> wrapping the match.\\n  function buildMatch(r){\\n    if(mode !== 'semantic') return '<td style=\\"color:var(--muted)\\">—</td>';\\n    const q = (currentQuery||'').trim();\\n    const txt = r.top_chunk_content || '';\\n    if(!txt) return '<td style=\\"color:var(--muted)\\">—</td>';\\n    if(q){\\n      const safe = q.replace(/[.*+?^\\\\${}()|[\\\\]\\\\\\\\]/g, '\\\\\\\\$&');\\n      const re = new RegExp(safe, 'i');\\n      const m = re.exec(txt);\\n      if(m){\\n        const start = Math.max(0, m.index - 20);\\n        const end = Math.min(txt.length, m.index + q.length + 20);\\n        const before = (start > 0 ? '…' : '') + txt.slice(start, m.index);\\n        const matchTxt = txt.slice(m.index, m.index + q.length);\\n        const after = txt.slice(m.index + q.length, end) + (end < txt.length ? '…' : '');\\n        return \\\\`<td><div class=\\"match-cell\\" title=\\"\\\\${esc(txt.slice(0,200))}\\">\\\\${esc(before)}<mark class=\\"match\\">\\\\${esc(matchTxt)}</mark>\\\\${esc(after)}</div></td>\\\\`;\\n      }\\n    }\\n    if(r.keyword_sim && parseFloat(r.keyword_sim) > 0){\\n      return \\\\`<td style=\\"color:var(--muted);font-size:12px\\">semantic match · kw \\\\${(parseFloat(r.keyword_sim)).toFixed(1)}</td>\\\\`;\\n    }\\n    return '<td style=\\"color:var(--muted)\\">—</td>';\\n  }\\n  // Similarity: use vector_sim (cosine 0-1). RRF score is meaningless\\n  // for human display (always ~3% for top-ranked results).\\n  function buildSim(r){\\n    if(mode !== 'semantic') return '<td style=\\"color:var(--muted)\\">—</td>';\\n    const v = parseFloat(r.vector_sim != null ? r.vector_sim : (r.similarity || 0));\\n    const pct = Math.max(0, Math.min(100, Math.round(v * 100)));\\n    return \\\\`<td><div style=\\"display:flex;align-items:center\\"><div class=\\"similarity-bar\\"><span style=\\"width:\\\\${pct}%\\"></span></div><span style=\\"font-variant-numeric:tabular-nums;font-size:12px;color:var(--muted)\\">\\\\${pct}%</span></div></td>\\\\`;\\n  }\\n  tb.innerHTML = allRows.map(r=>{\\n    return \\\\`\\n    <tr>\\n      <td class=\\"mono\\">\\\\${esc(r.doc_no||'—')}</td>\\n      <td><div class=\\"name\\">\\\\${esc(r.file_name||'')}<small>\\\\${esc(r.file_type||'')}\\\\${r.size_bytes?' • '+Math.round(r.size_bytes/1024)+' KB':''}</small></div></td>\\n      \\\\${buildSim(r)}\\n      \\\\${buildMatch(r)}\\n      <td>\\\\${esc(r.category||'—')}</td>\\n      <td><span class=\\"badge \\\\${esc(r.status||'pending')}\\">\\\\${esc(r.status||'pending')}</span></td>\\n      <td style=\\"text-align:right;font-variant-numeric:tabular-nums\\">\\\\${r.chunk_count??0}</td>\\n      <td class=\\"mono\\">\\\\${fmtDate(r.uploaded_at)}</td>\\n      <td><div class=\\"row-actions\\">\\n        <button class=\\"btn ghost sm\\" onclick=\\"view('\\\\${esc(r.id)}')\\">ดู</button>\\n        <button class=\\"btn sm\\" onclick=\\"edit('\\\\${esc(r.id)}')\\">แก้ไข</button>\\n        <button class=\\"btn danger sm\\" onclick=\\"del('\\\\${esc(r.id)}','\\\\${esc(r.file_name||'')}')\\">ลบ</button>\\n      </div></td>\\n    </tr>\\n  \\\\`}).join('');\\n}\\n\\nasync function view(id){\\n  try{\\n    const data = await api('/webhook/admin-get?id='+encodeURIComponent(id));\\n    const r = (Array.isArray(data)?data[0]:((data&&data.data)||data));\\n    if(!r||!r.id){toast('ไม่พบเอกสาร','err');return}\\n    const chunks = r.chunks||[];\\n    const fileUrl = '/webhook/admin-file?id='+encodeURIComponent(id);\\n    document.getElementById('v-title').textContent = r.file_name||'(ไม่มีชื่อ)';\\n    document.getElementById('v-body').innerHTML = \\\\`\\n      <div class=\\"preview-grid\\">\\n        <section>\\n          <div class=\\"preview-bar\\">\\n            <div><div class=\\"hint\\">ไฟล์จาก Postgres</div><strong>\\\\${esc(r.file_name||'document')}</strong></div>\\n            <a href=\\"\\\\${esc(fileUrl)}\\" target=\\"_blank\\" class=\\"btn ghost sm\\" style=\\"text-decoration:none\\">เปิดแท็บใหม่</a>\\n          </div>\\n          <div class=\\"file-preview\\"><iframe src=\\"\\\\${esc(fileUrl) + '#toolbar=0&navpanes=0&scrollbar=0&view=FitH'}\\" title=\\"\\\\${esc(r.file_name||'document')}\\"></iframe></div>\\n        </section>\\n        <section>\\n          <div class=\\"grid2 meta-grid\\">\\n            <div><div class=\\"hint\\">Doc No</div><div class=\\"mono\\" style=\\"font-weight:500\\">\\\\${esc(r.doc_no||'—')}</div></div>\\n            <div><div class=\\"hint\\">Status</div><span class=\\"badge \\\\${esc(r.status)}\\">\\\\${esc(r.status)}</span></div>\\n            <div><div class=\\"hint\\">Category</div>\\\\${esc(r.category||'—')}</div>\\n            <div><div class=\\"hint\\">Source</div>\\\\${esc(r.source||'—')}</div>\\n            <div><div class=\\"hint\\">File Type</div>\\\\${esc(r.file_type||'—')}</div>\\n            <div><div class=\\"hint\\">Size</div>\\\\${r.size_bytes?(Math.round(r.size_bytes/1024)+' KB'):'—'}</div>\\n            <div><div class=\\"hint\\">Line User</div><div class=\\"mono\\" style=\\"font-size:11px\\">\\\\${esc(r.line_user_id||'—')}</div></div>\\n            <div><div class=\\"hint\\">Line Group</div><div class=\\"mono\\" style=\\"font-size:11px\\">\\\\${esc(r.line_group_id||'—')}</div></div>\\n            <div><div class=\\"hint\\">อัปโหลด</div>\\\\${fmtDate(r.uploaded_at)}</div>\\n            <div><div class=\\"hint\\">อัปเดต</div>\\\\${fmtDate(r.updated_at)}</div>\\n          </div>\\n          <div style=\\"margin-top:18px\\">\\n            <div class=\\"hint\\" style=\\"margin-bottom:6px\\">Chunks (\\\\${chunks.length})</div>\\n            <div class=\\"chunk-list\\">\\\\${chunks.length?chunks.map(c=>\\\\`<div class=\\"chunk\\"><div class=\\"ci\\">#\\\\${c.chunk_index} • \\\\${c.token_count||0} tokens</div><div class=\\"cp\\">\\\\${esc(c.preview||'')}</div></div>\\\\`).join(''):'<div class=\\"chunk\\" style=\\"color:var(--muted-2)\\">ยังไม่มี chunks</div>'}</div>\\n          </div>\\n        </section>\\n      </div>\\n    \\\\`;\\n    document.getElementById('v-edit-btn').onclick = ()=>{closeModal('m-view');edit(id)};\\n    document.getElementById('v-open-btn').onclick = ()=>window.open(fileUrl, '_blank');\\n    document.getElementById('m-view').classList.add('on');\\n  }catch(e){toast('โหลดรายละเอียดไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nfunction edit(id){\\n  const r = allRows.find(x=>x.id===id);\\n  if(!r){toast('ไม่พบเอกสาร','err');return}\\n  document.getElementById('e-id').value = id;\\n  document.getElementById('e-doc_no').value = r.doc_no||'';\\n  document.getElementById('e-file_name').value = r.file_name||'';\\n  document.getElementById('e-category').value = r.category||'';\\n  document.getElementById('e-source').value = r.source||'';\\n  document.getElementById('e-status').value = r.status||'pending';\\n  document.getElementById('m-edit').classList.add('on');\\n}\\n\\nasync function saveEdit(){\\n  const id = document.getElementById('e-id').value;\\n  const body = {\\n    id,\\n    file_name: document.getElementById('e-file_name').value.trim(),\\n    category: document.getElementById('e-category').value.trim(),\\n    source: document.getElementById('e-source').value.trim(),\\n    status: document.getElementById('e-status').value\\n  };\\n  if(!body.file_name){toast('กรุณากรอกชื่อไฟล์','err');return}\\n  try{\\n    await api('/webhook/admin-update',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});\\n    toast('บันทึกเรียบร้อย','ok');\\n    closeModal('m-edit');\\n    loadList();loadStats();\\n  }catch(e){toast('บันทึกไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nasync function del(id, name){\\n  if(!confirm('ลบ \\"'+name+'\\"?\\\\\\\\n\\\\\\\\n⚠️ chunks ทั้งหมดจะถูกลบด้วย (CASCADE)')) return;\\n  try{\\n    await api('/webhook/admin-delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})});\\n    toast('ลบเรียบร้อย','ok');\\n    loadList();loadStats();\\n  }catch(e){toast('ลบไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nfunction closeModal(id){document.getElementById(id).classList.remove('on')}\\n\\ndocument.getElementById('btn-refresh').onclick = ()=>{loadList();loadStats()};\\ndocument.getElementById('q').oninput = debounce(loadList, 300);\\ndocument.getElementById('f-status').onchange = loadList;\\ndocument.getElementById('e-save').onclick = saveEdit;\\n\\nfunction debounce(fn, ms){let t;return(...a)=>{clearTimeout(t);t=setTimeout(()=>fn(...a),ms)}}\\n\\n// Read URL query params (?q=, ?status=) and pre-fill inputs\\nconst urlParams = new URLSearchParams(window.location.search);\\nconst urlQ = urlParams.get('q');\\nconst urlStatus = urlParams.get('status');\\nif (urlQ) document.getElementById('q').value = urlQ;\\nif (urlStatus) document.getElementById('f-status').value = urlStatus;\\n\\nloadList();\\nloadStats();\\nsetInterval(()=>{loadStats()}, 60000);\\n</script>\\n</body>\\n</html>`;\\nreturn [{json: {html: html}}];\\n"},"id":"code-build-html","name":"Build HTML","type":"n8n-nodes-base.code","typeVersion":2,"position":[176,0]},{"parameters":{"respondWith":"text","responseBody":"={{ $('Build HTML').first().json.html }}","options":{"responseHeaders":{"entries":[{"name":"Content-Type","value":"text/html; charset=utf-8"}]}}},"id":"resp-ui","name":"Respond UI","type":"n8n-nodes-base.respondToWebhook","typeVersion":1,"position":[400,0]},{"parameters":{"path":"admin-list","responseMode":"lastNode","options":{}},"id":"wh-admin-list","name":"Admin List","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,224],"webhookId":"admin-list-wh"},{"parameters":{"path":"admin-get","responseMode":"lastNode","options":{}},"id":"wh-admin-get","name":"Admin Get","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,448],"webhookId":"admin-get-wh"},{"parameters":{"httpMethod":"POST","path":"admin-update","responseMode":"lastNode","options":{}},"id":"wh-admin-update","name":"Admin Update","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,896],"webhookId":"admin-update-wh"},{"parameters":{"httpMethod":"POST","path":"admin-delete","responseMode":"lastNode","options":{}},"id":"wh-admin-delete","name":"Admin Delete","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1120],"webhookId":"admin-delete-wh"},{"parameters":{"path":"admin-stats","responseMode":"lastNode","options":{}},"id":"wh-admin-stats","name":"Admin Stats","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1344],"webhookId":"admin-stats-wh"},{"parameters":{"operation":"executeQuery","query":"SELECT * FROM (\\n  SELECT id, doc_no, file_name, file_type, category, status, source, size_bytes, chunk_count, line_user_id, uploaded_at, updated_at, error_message\\n  FROM contracts c\\n  WHERE (($1::text IS NULL OR $1 = '')\\n      OR LOWER(COALESCE(file_name,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(source,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(doc_no,'')) LIKE '%' || LOWER($1) || '%')\\n    AND ($2::text IS NULL OR $2 = '' OR status = $2)\\n  ORDER BY uploaded_at DESC\\n  LIMIT $3::int OFFSET $4::int\\n) real\\nUNION ALL\\nSELECT NULL::uuid, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL\\nWHERE NOT EXISTS (SELECT 1 FROM contracts)\\nORDER BY 1 NULLS LAST","options":{"queryReplacement":"={{ [($json.query && $json.query.q) || null, ($json.query && $json.query.status) || null, parseInt(($json.query && $json.query.limit) || 200, 10), parseInt(($json.query && $json.query.offset) || 0, 10)] }}"}},"id":"pg-admin-list","name":"PG: Admin List","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,224],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT c.id, c.doc_no, c.file_name, c.file_type, c.category, c.status, c.source, c.size_bytes, c.chunk_count, c.line_user_id, c.line_group_id, c.line_message_id, c.uploaded_at, c.updated_at, (SELECT json_agg(json_build_object('id', ch.id, 'chunk_index', ch.chunk_index, 'preview', LEFT(ch.content, 200), 'token_count', ch.token_count) ORDER BY ch.chunk_index) FROM contract_chunks ch WHERE ch.contract_id = c.id) AS chunks FROM contracts c WHERE c.id = $1::uuid","options":{"queryReplacement":"={{ [$json.query.id] }}"}},"id":"pg-admin-get","name":"PG: Admin Get","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,448],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"UPDATE contracts SET file_name = COALESCE(NULLIF($2, ''), file_name), category = NULLIF($3, ''), source = NULLIF($4, ''), status = COALESCE(NULLIF($5, ''), status), updated_at = now() WHERE id = $1::uuid RETURNING id, doc_no, file_name, file_type, category, status, source, size_bytes, chunk_count, line_user_id, uploaded_at, updated_at","options":{"queryReplacement":"={{ [$json.body.id, $json.body.file_name, $json.body.category, $json.body.source, $json.body.status] }}"}},"id":"pg-admin-update","name":"PG: Admin Update","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,896],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"DELETE FROM contracts\\nWHERE id = $1::uuid\\nRETURNING id, file_name, storage_bucket, storage_path,\\n  CASE \\n    WHEN storage_path LIKE 'http%' AND storage_path LIKE '%/' || storage_bucket || '/%'\\n    THEN split_part(storage_path, '/' || storage_bucket || '/', 2)\\n    ELSE NULL\\n  END AS minio_key;","options":{"queryReplacement":"={{ [$json.body.id] }}"}},"id":"pg-admin-delete","name":"PG: Admin Delete","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1120],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed","options":{}},"id":"pg-admin-stats","name":"PG: Admin Stats","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1344],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Wrap list results - always output 1 item even if empty\\nlet items = $input.all().map(i => i.json);\\n// Filter out dummy rows (where id IS NULL)\\nitems = items.filter(it => it && it.id != null);\\nreturn [{json: {ok: true, action: 'list', count: items.length, data: items}}];"},"id":"wrap-list","name":"Wrap List","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,224]},{"parameters":{"jsCode":"// Wrap get result - returns null if no row found\\nconst items = $input.all().map(i => i.json).filter(it => it && it.id != null);\\nreturn [{json: {ok: items.length > 0, action: 'get', data: items[0] || null}}];"},"id":"wrap-get","name":"Wrap Get","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,448]},{"parameters":{"jsCode":"// Wrap update result\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'update', data: items[0] || null}}];"},"id":"wrap-update","name":"Wrap Update","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,896]},{"parameters":{"jsCode":"// Wrap delete result\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'delete', data: items[0] || null}}];"},"id":"wrap-delete","name":"Wrap Delete","type":"n8n-nodes-base.code","typeVersion":2,"position":[848,1120]},{"parameters":{"jsCode":"// Wrap stats result - always output 1 item\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'stats', data: items[0] || {total: 0, ready: 0, pending: 0, failed: 0}}}];"},"id":"wrap-stats","name":"Wrap Stats","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1344]},{"parameters":{"jsCode":"// minio_key is computed in SQL (short string, ~26 chars, not ref-compressed).\\n// Just copy it to _minio_key for MinIO Delete.\\nconst data = $input.first().json;\\nconst minioKey = data.minio_key;\\nreturn [{\\n  json: {\\n    ...data,\\n    _minio_bucket: data.storage_bucket,\\n    _minio_key: minioKey,\\n    _skip_minio_delete: !minioKey\\n  }\\n}];"},"id":"extract-minio-key-001","name":"Extract MinIO Key","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1120],"alwaysOutputData":true},{"parameters":{"operation":"delete","bucketName":"epsx-contracts","fileKey":"={{ $json._minio_key }}","options":{}},"id":"minio-delete-001","name":"MinIO Delete","type":"n8n-nodes-base.s3","typeVersion":1,"position":[624,1120],"credentials":{"s3":{"id":"f719a9dd-b576-4cd5-bde6-13fb6344c447","name":"MinIO Contracts"}}},{"parameters":{"path":"admin-file","responseMode":"responseNode","options":{}},"id":"wh-admin-file","name":"Admin File","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,672],"webhookId":"admin-file-webhook"},{"parameters":{"operation":"executeQuery","query":"SELECT id, file_name, file_type,\\n  COALESCE(\\n    file_mime,\\n    CASE\\n      WHEN lower(COALESCE(file_type, '')) = 'pdf' THEN 'application/pdf'\\n      WHEN lower(COALESCE(file_type, '')) = 'png' THEN 'image/png'\\n      WHEN lower(COALESCE(file_type, '')) IN ('jpg', 'jpeg') THEN 'image/jpeg'\\n      WHEN lower(COALESCE(file_type, '')) = 'txt' THEN 'text/plain; charset=utf-8'\\n      ELSE 'application/octet-stream'\\n    END\\n  ) AS file_mime,\\n  encode(file_data, 'base64') AS file_data_b64,\\n  octet_length(file_data) AS file_size\\nFROM contracts\\nWHERE id = $1::uuid","options":{"queryReplacement":"={{ [$json.query.id] }}"}},"id":"pg-admin-file","name":"PG: Admin File","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,672],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Build binary file response from contracts.file_data (Postgres bytea).\\nconst item = $input.first();\\nconst json = item?.json || {};\\nlet mime = json.file_mime || (json.file_type === 'pdf' ? 'application/pdf' : 'application/octet-stream');\\nlet fileName = json.file_name || 'document';\\nlet fileDataB64 = json.file_data_b64 || '';\\n\\nif (!fileDataB64) {\\n  const message = 'No file_data stored in Postgres for this document. Re-upload or backfill contracts.file_data.';\\n  fileDataB64 = Buffer.from(message, 'utf8').toString('base64');\\n  mime = 'text/plain; charset=utf-8';\\n  fileName = 'missing-file.txt';\\n}\\n\\nconst fileSize = Buffer.from(fileDataB64, 'base64').length;\\nreturn [{\\n  json: { file_name: fileName, file_mime: mime, file_size: fileSize },\\n  binary: {\\n    data: {\\n      data: fileDataB64,\\n      mimeType: mime,\\n      fileName,\\n      fileSize,\\n    }\\n  }\\n}];\\n"},"id":"wrap-file","name":"Wrap File","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,672]},{"parameters":{"respondWith":"binary","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Disposition","value":"={{ 'inline; filename=\\"' + (($json.file_name || 'document').replace(/\\"/g, '')) + '\\"' }}"},{"name":"Content-Type","value":"={{ $json.file_mime || 'application/octet-stream' }}"},{"name":"Cache-Control","value":"no-cache"}]}}},"id":"resp-file","name":"Respond File","type":"n8n-nodes-base.respondToWebhook","typeVersion":1.1,"position":[624,672]},{"id":"wh-admin-semantic","name":"Admin Semantic Search","type":"n8n-nodes-base.webhook","position":[440,880],"typeVersion":1,"parameters":{"path":"admin-semantic-search","httpMethod":"GET","responseMode":"lastNode","options":{}},"webhookId":"b55eade8-a4fa-4f89-b72c-199525e05146"},{"id":"parse-semantic","name":"Parse Semantic","type":"n8n-nodes-base.code","position":[660,880],"typeVersion":2,"parameters":{"jsCode":"const wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst query = (q.q || body.q || \\"\\").toString().trim();\\nconst limit = parseInt(q.limit || body.limit || 20, 10) || 20;\\nreturn [{json: {query, _query: query, _limit: limit}}];"}},{"id":"embed-semantic","name":"Embed Semantic","type":"n8n-nodes-base.httpRequest","position":[880,880],"typeVersion":4.2,"parameters":{"url":"={{ ($env.OLLAMA_URL || \\"http://127.0.0.1:11434\\") }}/api/embed","method":"POST","options":{"timeout":30000},"jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.query) }} }","sendBody":true,"sendHeaders":true,"specifyBody":"json","headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]}}},{"id":"pg-admin-semantic","name":"PG: Admin Semantic","type":"n8n-nodes-base.postgres","position":[1100,880],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}},"parameters":{"operation":"executeQuery","query":"WITH q AS (SELECT $1::vector AS qvec, $3::text AS qtxt),\\nv AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         1 - (ch.embedding <=> q.qvec) AS v_sim,\\n         ROW_NUMBER() OVER (ORDER BY ch.embedding <=> q.qvec) AS v_rank\\n  FROM contract_chunks ch, q\\n  WHERE ch.embedding IS NOT NULL\\n  ORDER BY ch.embedding <=> q.qvec\\n  LIMIT $2::int * 4\\n),\\nt AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 1.0 ELSE 0 END)::float\\n         + (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float\\n           / greatest(length(q.qtxt), 1)::float * 0.1 AS t_sim,\\n         ROW_NUMBER() OVER (ORDER BY\\n           (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n           (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float DESC,\\n           ch.chunk_index ASC) AS t_rank\\n  FROM contract_chunks ch, q\\n  WHERE length(q.qtxt) > 0\\n  ORDER BY (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n           (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float DESC\\n  LIMIT $2::int * 4\\n),\\nfused AS (\\n  SELECT COALESCE(v.contract_id, t.contract_id) AS contract_id,\\n         COALESCE(v.chunk_index, t.chunk_index) AS chunk_index,\\n         COALESCE(v.content, t.content) AS content,\\n         COALESCE(1.0/(60+v.v_rank), 0) + COALESCE(1.0/(60+t.t_rank), 0) AS rrf_score,\\n         COALESCE(v.v_sim, 0) AS v_sim,\\n         COALESCE(t.t_sim, 0) AS t_sim\\n  FROM v FULL OUTER JOIN t ON v.contract_id = t.contract_id AND v.chunk_index = t.chunk_index\\n  WHERE COALESCE(v.contract_id, t.contract_id) IS NOT NULL\\n),\\ncontract_ranked AS (\\n  SELECT *, ROW_NUMBER() OVER (PARTITION BY contract_id ORDER BY rrf_score DESC) AS in_contract_rank\\n  FROM fused\\n),\\nbest_per_contract AS (\\n  SELECT contract_id, chunk_index, content, rrf_score, v_sim, t_sim\\n  FROM contract_ranked\\n  WHERE in_contract_rank = 1\\n  ORDER BY rrf_score DESC\\n  LIMIT $2::int\\n),\\njoined AS (\\n  SELECT c.id, c.doc_no, c.file_name, c.file_type, c.category, c.status, c.source,\\n         c.size_bytes, c.chunk_count, c.line_user_id, c.uploaded_at, c.updated_at, c.error_message,\\n         b.chunk_index AS top_chunk_index, b.content AS top_chunk_content,\\n         b.rrf_score AS similarity, b.v_sim AS vector_sim, b.t_sim AS keyword_sim\\n  FROM best_per_contract b\\n  JOIN contracts c ON c.id = b.contract_id\\n)\\nSELECT COALESCE(\\n  (SELECT json_build_object(\\n    'ok', true,\\n    'mode', 'semantic',\\n    'query', $3::text,\\n    'count', (SELECT COUNT(*)::int FROM joined),\\n    'data', COALESCE((SELECT json_agg(row_to_json(j) ORDER BY similarity DESC) FROM joined j), '[]'::json)\\n  )::text),\\n  json_build_object('ok', true, 'mode', 'semantic', 'query', $3::text, 'count', 0, 'data', '[]'::json)::text\\n) AS result_json","options":{"queryReplacement":"={{ [($json.embeddings && $json.embeddings[0]) ? \\"[\\" + $json.embeddings[0].map(Number).join(\\",\\") + \\"]\\" : \\"[]\\", parseInt($(\\"Parse Semantic\\").first().json._limit || 20, 10), $(\\"Parse Semantic\\").first().json._query || \\"\\"] }}"}}},{"id":"wrap-semantic","name":"Wrap Semantic","type":"n8n-nodes-base.code","position":[1320,880],"typeVersion":2,"parameters":{"jsCode":"const row = $input.first().json;\\nlet result;\\ntry {\\n  result = JSON.parse(row.result_json || '{\\"ok\\":true,\\"count\\":0,\\"data\\":[]}');\\n} catch(e) {\\n  return [{json: {ok: false, error: \\"parse_failed\\", message: e.message, data: []}}];\\n}\\nreturn [{json: result}];"}},{"id":"resp-semantic","name":"Respond Semantic","type":"n8n-nodes-base.respondToWebhook","position":[1540,880],"typeVersion":1,"parameters":{"respondWith":"json","responseBody":"={{ $json }}"}}]	{"Admin Get":{"main":[[{"node":"PG: Admin Get","type":"main","index":0}]]},"Admin List":{"main":[[{"node":"PG: Admin List","type":"main","index":0}]]},"Build HTML":{"main":[[{"node":"Respond UI","type":"main","index":0}]]},"Admin Stats":{"main":[[{"node":"PG: Admin Stats","type":"main","index":0}]]},"Admin Delete":{"main":[[{"node":"PG: Admin Delete","type":"main","index":0}]]},"Admin Update":{"main":[[{"node":"PG: Admin Update","type":"main","index":0}]]},"PG: Admin Get":{"main":[[{"node":"Wrap Get","type":"main","index":0}]]},"PG: Admin List":{"main":[[{"node":"Wrap List","type":"main","index":0}]]},"PG: Admin Stats":{"main":[[{"node":"Wrap Stats","type":"main","index":0}]]},"Admin UI Webhook":{"main":[[{"node":"Build HTML","type":"main","index":0}]]},"PG: Admin Delete":{"main":[[{"node":"Extract MinIO Key","type":"main","index":0}]]},"PG: Admin Update":{"main":[[{"node":"Wrap Update","type":"main","index":0}]]},"Extract MinIO Key":{"main":[[{"node":"MinIO Delete","type":"main","index":0}]]},"MinIO Delete":{"main":[[{"node":"Wrap Delete","type":"main","index":0}]]},"Admin File":{"main":[[{"node":"PG: Admin File","type":"main","index":0}]]},"PG: Admin File":{"main":[[{"node":"Wrap File","type":"main","index":0}]]},"Wrap File":{"main":[[{"node":"Respond File","type":"main","index":0}]]},"Admin Semantic Search":{"main":[[{"node":"Parse Semantic","type":"main","index":0}]]},"Parse Semantic":{"main":[[{"node":"Embed Semantic","type":"main","index":0}]]},"Embed Semantic":{"main":[[{"node":"PG: Admin Semantic","type":"main","index":0}]]},"PG: Admin Semantic":{"main":[[{"node":"Wrap Semantic","type":"main","index":0}]]},"Wrap Semantic":{"main":[[{"node":"Respond Semantic","type":"main","index":0}]]}}	\N	f	\N	[]
f8af4454-0091-4412-bf10-19ddfd9c25d2	AdM1nFlow12345678CD0cHub2	Fluke Jesadakorn	2026-06-24 02:14:33.621+07	2026-06-24 02:14:33.621+07	[{"parameters":{"path":"docs-admin-ui","responseMode":"responseNode","options":{}},"id":"wh-admin-ui","name":"Admin UI Webhook","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,0],"webhookId":"admin-ui-webhook"},{"parameters":{"jsCode":"// Return HTML page for Docs Admin\\nconst html = `<!doctype html>\\n<html lang=\\"th\\">\\n<head>\\n<meta charset=\\"utf-8\\">\\n<title>Docs Admin | Phuket Law</title>\\n<meta name=\\"viewport\\" content=\\"width=device-width,initial-scale=1\\">\\n<script>\\n  // No-flash theme bootstrap: set data-theme BEFORE <style> parses so first\\n  // paint uses the right colors. Order: localStorage > OS preference > dark.\\n  (function(){\\n    try{\\n      var saved = localStorage.getItem('lawpoc-admin-theme');\\n      var theme = saved || (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');\\n      document.documentElement.setAttribute('data-theme', theme);\\n    }catch(e){ document.documentElement.setAttribute('data-theme', 'dark'); }\\n  })();\\n</script>\\n<style>\\n:root{\\n  /* Core tokens (light defaults) */\\n  --bg:#f6f7f9;--card:#fff;--ink:#0f172a;--muted:#64748b;--muted-2:#94a3b8;\\n  --bd:#e2e8f0;--bd-soft:#f1f5f9;\\n  --pri:#0f766e;--pri-2:#0d9488;--warn:#b45309;--err:#b91c1c;--ok:#15803d;\\n\\n  /* Component tokens (light) */\\n  --header-bg:#0f172a;--header-fg:#fff;--crumb-fg:#94a3b8;\\n  --hover-bg:#f1f5f9;--th-bg:#f8fafc;\\n  --row-divider:#f1f5f9;--row-hover-bg:#fafbfc;\\n  --mono-fg:#475569;--chunk-text:#334155;\\n  --modal-overlay:rgba(15,23,42,.5);--modal-card:#fff;--modal-ft-bg:#f8fafc;\\n  --file-preview-bg:#f8fafc;--input-bg:#fff;\\n  --toast-bg:#0f172a;--toast-fg:#fff;\\n  --spinner-border:#fff;\\n  --sticky-act-shadow:rgba(15,23,42,.15);\\n\\n  /* Status badges (light = pastel solid; dark = semi-transparent tinted) */\\n  --badge-ready-bg:#dcfce7;     --badge-ready-fg:#15803d;\\n  --badge-pending-bg:#fef3c7;   --badge-pending-fg:#b45309;\\n  --badge-failed-bg:#fee2e2;    --badge-failed-fg:#b91c1c;\\n  --badge-processing-bg:#dbeafe;--badge-processing-fg:#1d4ed8;\\n\\n  /* Shadow tokens */\\n  --shadow-sm:0 1px 2px rgba(15,23,42,.06);\\n  --shadow-md:0 4px 12px rgba(15,23,42,.08);\\n}\\n[data-theme=\\"dark\\"]{\\n  --bg:#0e1422;--card:#161e35;--ink:#f1f5f9;--muted:#94a3b8;--muted-2:#64748b;\\n  --bd:rgba(148,163,184,.15);--bd-soft:rgba(148,163,184,.08);\\n  --pri:#2dd4bf;--pri-2:#14b8a6;--warn:#fbbf24;--err:#f87171;--ok:#4ade80;\\n\\n  --header-bg:#050a17;--header-fg:#f1f5f9;--crumb-fg:#64748b;\\n  --hover-bg:rgba(148,163,184,.08);--th-bg:rgba(148,163,184,.05);\\n  --row-divider:rgba(148,163,184,.08);--row-hover-bg:rgba(20,184,166,.05);\\n  --mono-fg:#cbd5e1;--chunk-text:#cbd5e1;\\n  --modal-overlay:rgba(0,0,0,.7);--modal-card:#161e35;--modal-ft-bg:#0e1422;\\n  --file-preview-bg:#0e1422;--input-bg:#0e1422;\\n  --toast-bg:#f1f5f9;--toast-fg:#0f172a;\\n  --spinner-border:#0e1422;\\n  --sticky-act-shadow:rgba(0,0,0,.5);\\n\\n  --badge-ready-bg:rgba(34,197,94,.18);     --badge-ready-fg:#4ade80;\\n  --badge-pending-bg:rgba(245,158,11,.18);   --badge-pending-fg:#fbbf24;\\n  --badge-failed-bg:rgba(239,68,68,.18);    --badge-failed-fg:#f87171;\\n  --badge-processing-bg:rgba(59,130,246,.18);--badge-processing-fg:#60a5fa;\\n\\n  --shadow-sm:0 1px 2px rgba(0,0,0,.4);\\n  --shadow-md:0 4px 12px rgba(0,0,0,.4);\\n}\\n*{box-sizing:border-box}\\nbody{font:14px/1.5 -apple-system,\\"SF Pro Text\\",\\"Inter\\",system-ui,sans-serif;margin:0;background:var(--bg);color:var(--ink);transition:background-color .2s ease,color .2s ease}\\nheader{background:var(--header-bg);color:var(--header-fg);padding:14px 24px;display:flex;align-items:center;gap:16px;box-shadow:0 1px 0 rgba(0,0,0,.2);transition:background-color .2s ease}\\nheader h1{font-size:16px;font-weight:600;margin:0;letter-spacing:.2px}\\nheader .crumb{color:var(--crumb-fg);font-size:12px;margin-left:auto}\\nheader .theme-toggle{margin-left:8px;background:transparent;color:var(--header-fg);border:1px solid rgba(255,255,255,.18);border-radius:8px;height:32px;width:32px;padding:0;cursor:pointer;font-size:14px;display:inline-flex;align-items:center;justify-content:center;transition:all .15s}\\nheader .theme-toggle:hover{background:rgba(255,255,255,.08);border-color:rgba(255,255,255,.35)}\\n.wrap{max-width:1280px;margin:0 auto;padding:24px}\\n.toolbar{display:flex;gap:8px;align-items:center;margin-bottom:16px;flex-wrap:wrap}\\n.toolbar input,.toolbar select{height:36px;padding:0 12px;border:1px solid var(--bd);border-radius:8px;background:var(--input-bg);font:inherit;color:var(--ink);outline:none;transition:border-color .15s,box-shadow .15s}\\n.toolbar input:focus,.toolbar select:focus{border-color:var(--pri-2);box-shadow:0 0 0 3px rgba(13,148,136,.2)}\\n.toolbar input.search{flex:1;min-width:200px}\\n\\n.similarity-bar{display:inline-block;height:6px;border-radius:3px;background:var(--bd);width:60px;vertical-align:middle;margin-right:6px;position:relative;overflow:hidden}\\n.similarity-bar>span{position:absolute;left:0;top:0;bottom:0;background:var(--pri)}\\n.chunk-preview{font-size:11px;color:var(--muted);margin-top:4px;line-height:1.4;max-width:420px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\\n.btn{height:36px;padding:0 14px;border:0;border-radius:8px;background:var(--pri);color:#fff;font:inherit;font-weight:500;cursor:pointer;display:inline-flex;align-items:center;gap:6px;transition:background-color .15s,box-shadow .15s,transform .05s}\\n.btn:hover{background:var(--pri-2)}\\n.btn:active{transform:translateY(1px)}\\n.btn.ghost{background:transparent;color:var(--ink);border:1px solid var(--bd)}\\n.btn.ghost:hover{background:var(--hover-bg)}\\n.btn.warn{background:var(--warn)}\\n.btn.danger{background:var(--err)}\\n.btn.sm{height:28px;padding:0 10px;font-size:12px;border-radius:6px}\\n.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}\\n.stat{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:14px;box-shadow:var(--shadow-sm);transition:background-color .2s ease,border-color .2s ease}\\n.stat .label{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}\\n.stat .num{font-size:24px;font-weight:600;margin-top:4px}\\n.stat .num.warn{color:var(--warn)} .stat .num.ok{color:var(--ok)} .stat .num.err{color:var(--err)}\\n.card{background:var(--card);border:1px solid var(--bd);border-radius:12px;overflow-x:auto;box-shadow:var(--shadow-sm);transition:background-color .2s ease,border-color .2s ease}\\ntable{width:100%;border-collapse:collapse;font-size:13px}\\nth{text-align:left;padding:12px 14px;background:var(--th-bg);font-weight:600;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.4px;border-bottom:1px solid var(--bd)}\\ntd{padding:12px 14px;border-bottom:1px solid var(--row-divider);vertical-align:middle}\\ntr:hover td{background:var(--row-hover-bg)}\\ntr:last-child td{border-bottom:0}\\ntd.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--mono-fg)}\\ntd .name{font-weight:500;color:var(--ink)}\\ntd .name small{display:block;color:var(--muted);font-weight:400;font-size:11px;margin-top:2px}\\n.badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:500}\\n.badge.ready{background:var(--badge-ready-bg);color:var(--badge-ready-fg)}\\n.badge.pending{background:var(--badge-pending-bg);color:var(--badge-pending-fg)}\\n.badge.failed{background:var(--badge-failed-bg);color:var(--badge-failed-fg)}\\n.badge.processing{background:var(--badge-processing-bg);color:var(--badge-processing-fg)}\\n.empty{padding:60px 20px;text-align:center;color:var(--muted)}\\n.empty h3{margin:0 0 6px;font-weight:500;color:var(--ink)}\\n.row-actions{display:flex;gap:6px;justify-content:flex-end;position:sticky;right:0;background:var(--card);padding-left:12px;box-shadow:-8px 0 12px -6px var(--sticky-act-shadow)}\\n.row-actions::before{content:'';position:absolute;left:-12px;top:0;bottom:0;width:12px;background:linear-gradient(to right,transparent,var(--card) 70%);pointer-events:none}\\nth.sticky-act{position:sticky;right:0;background:var(--th-bg);z-index:2;box-shadow:-8px 0 12px -6px var(--sticky-act-shadow)}\\n.modal{position:fixed;inset:0;background:var(--modal-overlay);display:none;align-items:center;justify-content:center;z-index:50;padding:20px}\\n.modal.on{display:flex}\\n.modal .box{background:var(--modal-card);border-radius:12px;width:100%;max-width:760px;max-height:90vh;display:flex;flex-direction:column;overflow:hidden;box-shadow:var(--shadow-md)}\\n#m-view .box{max-width:1180px}\\n.preview-grid{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(320px,.75fr);gap:16px}\\n.preview-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px}\\n.file-preview{height:min(66vh,720px);min-height:420px;border:1px solid var(--bd);border-radius:8px;overflow:hidden;background:var(--file-preview-bg)}\\n.file-preview iframe{width:100%;height:100%;border:0;background:var(--input-bg)}\\n.meta-grid{grid-template-columns:1fr 1fr}\\n@media(max-width:900px){.preview-grid{grid-template-columns:1fr}.file-preview{height:60vh;min-height:320px}.grid2,.meta-grid{grid-template-columns:1fr}}\\n.modal .hd{padding:16px 20px;border-bottom:1px solid var(--bd);display:flex;align-items:center;gap:12px}\\n.modal .hd h2{margin:0;font-size:16px;font-weight:600;flex:1}\\n.modal .bd{padding:20px;overflow-y:auto;flex:1}\\n.modal .ft{padding:14px 20px;border-top:1px solid var(--bd);display:flex;justify-content:flex-end;gap:8px;background:var(--modal-ft-bg)}\\n.field{margin-bottom:14px}\\n.field label{display:block;font-size:12px;font-weight:500;color:var(--muted);margin-bottom:4px}\\n.field input,.field select,.field textarea{width:100%;padding:8px 10px;border:1px solid var(--bd);border-radius:6px;font:inherit;background:var(--input-bg);color:var(--ink);transition:border-color .15s,box-shadow .15s}\\n.field input:focus,.field select:focus,.field textarea:focus{outline:none;border-color:var(--pri-2);box-shadow:0 0 0 3px rgba(13,148,136,.2)}\\n.field .hint{font-size:11px;color:var(--muted);margin-top:3px}\\n.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}\\n.chunk-list{margin-top:8px;max-height:340px;overflow-y:auto;border:1px solid var(--bd);border-radius:6px;background:var(--input-bg)}\\n.chunk{padding:10px 12px;border-bottom:1px solid var(--bd-soft);font-size:12px}\\n.chunk:last-child{border-bottom:0}\\n.chunk .ci{color:var(--muted);font-family:ui-monospace,monospace;font-size:11px}\\n.chunk .cp{color:var(--chunk-text);margin-top:4px;line-height:1.4}\\n.toast{position:fixed;bottom:20px;right:20px;background:var(--toast-bg);color:var(--toast-fg);padding:12px 18px;border-radius:8px;font-size:13px;opacity:0;transform:translateY(10px);transition:all .2s;z-index:100;max-width:360px;box-shadow:var(--shadow-md)}\\n.toast.on{opacity:1;transform:translateY(0)}\\n.toast.err{background:var(--err);color:#fff}\\n.toast.ok{background:var(--ok);color:#fff}\\nmark.match{background:#fef08a;color:#713f12;padding:0 3px;border-radius:3px;font-weight:500}\\n.match-cell{max-width:240px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px;color:var(--mono-fg)}\\n.spin{display:inline-block;width:14px;height:14px;border:2px solid var(--spinner-border);border-top-color:transparent;border-radius:50%;animation:spin 1s linear infinite}\\n@keyframes spin{to{transform:rotate(360deg)}}\\n.loading{padding:40px;text-align:center;color:var(--muted)}\\n</style>\\n</head>\\n<body>\\n<header>\\n  <h1>📑 Docs Admin</h1>\\n  <button class=\\"theme-toggle\\" id=\\"btn-theme\\" aria-label=\\"สลับโหมดมืด/สว่าง\\" title=\\"สลับโหมดมืด/สว่าง\\">\\n    <span id=\\"theme-icon\\">🌙</span>\\n  </button>\\n  <span class=\\"crumb\\" id=\\"crumb\\">Phuket Law Firm • LINE-fed document store</span>\\n</header>\\n<div class=\\"wrap\\">\\n  <div class=\\"stats\\" id=\\"stats\\">\\n    <div class=\\"stat\\"><div class=\\"label\\">Total</div><div class=\\"num\\" id=\\"stat-total\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Ready</div><div class=\\"num ok\\" id=\\"stat-ready\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Pending</div><div class=\\"num warn\\" id=\\"stat-pending\\">—</div></div>\\n    <div class=\\"stat\\"><div class=\\"label\\">Failed</div><div class=\\"num err\\" id=\\"stat-failed\\">—</div></div>\\n  </div>\\n  <div class=\\"toolbar\\">\\n    <input class=\\"search\\" id=\\"q\\" placeholder=\\"🔍 ค้นหาในเนื้อหา (semantic)\\">\\n    <select id=\\"f-status\\">\\n      <option value=\\"\\">สถานะทั้งหมด</option>\\n      <option value=\\"ready\\">ready</option>\\n      <option value=\\"pending\\">pending</option>\\n      <option value=\\"failed\\">failed</option>\\n      <option value=\\"processing\\">processing</option>\\n    </select>\\n    <button class=\\"btn ghost\\" id=\\"btn-refresh\\">↻ รีเฟรช</button>\\n  </div>\\n  <div class=\\"card\\">\\n    <table>\\n      <thead><tr>\\n        <th style=\\"width:130px\\">Doc No</th>\\n        <th>ชื่อไฟล์</th>\\n        <th style=\\"width:110px\\">ความเหมือน</th>\\n        <th style=\\"width:240px\\">Match</th>\\n        <th style=\\"width:110px\\">Category</th>\\n        <th style=\\"width:90px\\">Status</th>\\n        <th style=\\"width:60px;text-align:right\\">Chunks</th>\\n        <th style=\\"width:130px\\">อัปโหลด</th>\\n        <th class=\\"sticky-act\\" style=\\"width:200px\\"></th>\\n      </tr></thead>\\n      <tbody id=\\"tbody\\">\\n        <tr><td colspan=\\"9\\" class=\\"loading\\">กำลังโหลด…</td></tr>\\n      </tbody>\\n    </table>\\n  </div>\\n</div>\\n\\n<!-- View Modal -->\\n<div class=\\"modal\\" id=\\"m-view\\">\\n  <div class=\\"box\\">\\n    <div class=\\"hd\\"><h2 id=\\"v-title\\">รายละเอียดเอกสาร</h2><button class=\\"btn ghost sm\\" onclick=\\"closeModal('m-view')\\">✕</button></div>\\n    <div class=\\"bd\\" id=\\"v-body\\"></div>\\n    <div class=\\"ft\\"><button class=\\"btn ghost\\" onclick=\\"closeModal('m-view')\\">ปิด</button><button class=\\"btn ghost\\" id=\\"v-open-btn\\">เปิดไฟล์</button><button class=\\"btn\\" id=\\"v-edit-btn\\">แก้ไข</button></div>\\n  </div>\\n</div>\\n\\n<!-- Edit Modal -->\\n<div class=\\"modal\\" id=\\"m-edit\\">\\n  <div class=\\"box\\">\\n    <div class=\\"hd\\"><h2>แก้ไขเอกสาร</h2><button class=\\"btn ghost sm\\" onclick=\\"closeModal('m-edit')\\">✕</button></div>\\n    <div class=\\"bd\\">\\n      <input type=\\"hidden\\" id=\\"e-id\\">\\n      <div class=\\"grid2\\">\\n        <div class=\\"field\\"><label>Doc No</label><input id=\\"e-doc_no\\" disabled><div class=\\"hint\\">ไม่สามารถแก้ไขได้</div></div>\\n        <div class=\\"field\\"><label>Status</label>\\n          <select id=\\"e-status\\"><option value=\\"ready\\">ready</option><option value=\\"pending\\">pending</option><option value=\\"failed\\">failed</option><option value=\\"processing\\">processing</option></select>\\n        </div>\\n      </div>\\n      <div class=\\"field\\"><label>ชื่อไฟล์</label><input id=\\"e-file_name\\"></div>\\n      <div class=\\"grid2\\">\\n        <div class=\\"field\\"><label>Category</label><input id=\\"e-category\\" placeholder=\\"เช่น สัญญาเช่า, หนังสือมอบอำนาจ\\"></div>\\n        <div class=\\"field\\"><label>Source</label><input id=\\"e-source\\" placeholder=\\"เช่น LINE OA, web upload\\"></div>\\n      </div>\\n    </div>\\n    <div class=\\"ft\\">\\n      <button class=\\"btn ghost\\" onclick=\\"closeModal('m-edit')\\">ยกเลิก</button>\\n      <button class=\\"btn\\" id=\\"e-save\\">บันทึก</button>\\n    </div>\\n  </div>\\n</div>\\n\\n<div class=\\"toast\\" id=\\"toast\\"></div>\\n\\n<script>\\nconst BASE = location.origin;\\nlet allRows = [];\\nlet statsCache = null;\\nlet currentQuery = '';\\n\\n// =========================================================================\\n// Theme switcher (toggle dark/light, persist in localStorage, respect OS pref)\\n// =========================================================================\\nconst themeBtn = document.getElementById('btn-theme');\\nconst themeIcon = document.getElementById('theme-icon');\\nconst THEME_KEY = 'lawpoc-admin-theme';\\nconst themeMedia = window.matchMedia('(prefers-color-scheme: light)');\\n\\nfunction currentTheme(){ return document.documentElement.getAttribute('data-theme') || 'light'; }\\n\\nfunction syncThemeIcon(theme){\\n  // Show the icon of the CURRENT theme so the button reflects page state\\n  themeIcon.textContent = theme === 'dark' ? '🌙' : '☀️';\\n  themeBtn.setAttribute('aria-label', theme === 'dark' ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด');\\n  themeBtn.setAttribute('title', theme === 'dark' ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด');\\n}\\n\\nfunction applyTheme(theme, persist){\\n  document.documentElement.setAttribute('data-theme', theme);\\n  syncThemeIcon(theme);\\n  if(persist){ try{ localStorage.setItem(THEME_KEY, theme); }catch(e){} }\\n}\\n\\nthemeBtn.addEventListener('click', ()=>{\\n  applyTheme(currentTheme() === 'dark' ? 'light' : 'dark', true);\\n});\\n\\n// Sync icon to whatever the head bootstrap set\\nsyncThemeIcon(currentTheme());\\n\\n// If user hasn't explicitly chosen, follow OS theme changes live\\nthemeMedia.addEventListener('change', e=>{\\n  let saved = null;\\n  try{ saved = localStorage.getItem(THEME_KEY); }catch(err){}\\n  if(!saved) applyTheme(e.matches ? 'light' : 'dark', false);\\n});\\n// =========================================================================\\n\\nfunction toast(msg, kind=''){\\n  const t = document.getElementById('toast');\\n  t.textContent = msg;\\n  t.className = 'toast on ' + kind;\\n  setTimeout(()=>t.className='toast '+kind, 2200);\\n}\\n\\nasync function api(path, opts){\\n  const r = await fetch(BASE + path, opts);\\n  if (!r.ok) throw new Error('HTTP '+r.status);\\n  return r.json();\\n}\\n\\nfunction fmtDate(s){\\n  if(!s) return '—';\\n  const d = new Date(s);\\n  return d.toLocaleString('th-TH',{dateStyle:'short',timeStyle:'short'});\\n}\\n\\nfunction esc(s){return String(s??'').replace(/[&<>\\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\\"':'&quot;',\\"'\\":'&#39;'}[c]))}\\n\\nasync function loadStats(){\\n  try{\\n    const s = await api('/webhook/admin-stats');\\n    const v = (s && s.data) || s;\\n    if (typeof v === 'string') { try { v = JSON.parse(v); } catch {} }\\n    document.getElementById('stat-total').textContent = v.total??0;\\n    document.getElementById('stat-ready').textContent = v.ready??0;\\n    document.getElementById('stat-pending').textContent = v.pending??0;\\n    document.getElementById('stat-failed').textContent = v.failed??0;\\n  }catch(e){console.warn('stats',e)}\\n}\\n\\nasync function loadList(){\\n  const q = document.getElementById('q').value.trim();\\n  const st = document.getElementById('f-status').value;\\n  const params = new URLSearchParams();\\n  if(st) params.set('status', st);\\n  params.set('limit', '200');\\n  // Empty q → admin-list (full listing, no embedding). Non-empty q → admin-semantic-search.\\n  const endpoint = q ? '/webhook/admin-semantic-search' : '/webhook/admin-list';\\n  if (q) params.set('q', q);\\n  currentQuery = q;\\n  try{\\n    const data = await api(endpoint+'?'+params.toString());\\n    allRows = Array.isArray(data)?data:((data&&data.data)||[]);\\n    render(q ? 'semantic' : 'list');\\n  }catch(e){\\n    document.getElementById('tbody').innerHTML = \\\\`<tr><td colspan=\\"9\\" class=\\"empty\\"><h3>โหลดไม่สำเร็จ</h3>\\\\${esc(e.message)}</td></tr>\\\\`;\\n  }\\n}\\n\\nfunction render(mode){\\n  const tb = document.getElementById('tbody');\\n  if(!allRows.length){\\n    const msg = (mode === 'semantic') ? 'ไม่พบเอกสารที่คล้ายกัน' : 'ไม่มีเอกสาร';\\n    const hint = (mode === 'semantic') ? 'ลองค้นหาด้วยคำอื่น' : 'อัปโหลดผ่าน LINE OA เพื่อเริ่มต้น';\\n    tb.innerHTML = \\\\`<tr><td colspan=\\"9\\" class=\\"empty\\"><h3>\\\\${esc(msg)}</h3>\\\\${esc(hint)}</td></tr>\\\\`;\\n    return;\\n  }\\n  // Build match snippet: find query in top_chunk_content, show ~20\\n  // chars context on each side with <mark> wrapping the match.\\n  function buildMatch(r){\\n    if(mode !== 'semantic') return '<td style=\\"color:var(--muted)\\">—</td>';\\n    const q = (currentQuery||'').trim();\\n    const txt = r.top_chunk_content || '';\\n    if(!txt) return '<td style=\\"color:var(--muted)\\">—</td>';\\n    if(q){\\n      const safe = q.replace(/[.*+?^\\\\${}()|[\\\\]\\\\\\\\]/g, '\\\\\\\\$&');\\n      const re = new RegExp(safe, 'i');\\n      const m = re.exec(txt);\\n      if(m){\\n        const start = Math.max(0, m.index - 20);\\n        const end = Math.min(txt.length, m.index + q.length + 20);\\n        const before = (start > 0 ? '…' : '') + txt.slice(start, m.index);\\n        const matchTxt = txt.slice(m.index, m.index + q.length);\\n        const after = txt.slice(m.index + q.length, end) + (end < txt.length ? '…' : '');\\n        return \\\\`<td><div class=\\"match-cell\\" title=\\"\\\\${esc(txt.slice(0,200))}\\">\\\\${esc(before)}<mark class=\\"match\\">\\\\${esc(matchTxt)}</mark>\\\\${esc(after)}</div></td>\\\\`;\\n      }\\n    }\\n    if(r.keyword_sim && parseFloat(r.keyword_sim) > 0){\\n      return \\\\`<td style=\\"color:var(--muted);font-size:12px\\">semantic match · kw \\\\${(parseFloat(r.keyword_sim)).toFixed(1)}</td>\\\\`;\\n    }\\n    return '<td style=\\"color:var(--muted)\\">—</td>';\\n  }\\n  // Similarity: use vector_sim (cosine 0-1). RRF score is meaningless\\n  // for human display (always ~3% for top-ranked results).\\n  function buildSim(r){\\n    if(mode !== 'semantic') return '<td style=\\"color:var(--muted)\\">—</td>';\\n    const v = parseFloat(r.vector_sim != null ? r.vector_sim : (r.similarity || 0));\\n    const pct = Math.max(0, Math.min(100, Math.round(v * 100)));\\n    return \\\\`<td><div style=\\"display:flex;align-items:center\\"><div class=\\"similarity-bar\\"><span style=\\"width:\\\\${pct}%\\"></span></div><span style=\\"font-variant-numeric:tabular-nums;font-size:12px;color:var(--muted)\\">\\\\${pct}%</span></div></td>\\\\`;\\n  }\\n  tb.innerHTML = allRows.map(r=>{\\n    return \\\\`\\n    <tr>\\n      <td class=\\"mono\\">\\\\${esc(r.doc_no||'—')}</td>\\n      <td><div class=\\"name\\">\\\\${esc(r.file_name||'')}<small>\\\\${esc(r.file_type||'')}\\\\${r.size_bytes?' • '+Math.round(r.size_bytes/1024)+' KB':''}</small></div></td>\\n      \\\\${buildSim(r)}\\n      \\\\${buildMatch(r)}\\n      <td>\\\\${esc(r.category||'—')}</td>\\n      <td><span class=\\"badge \\\\${esc(r.status||'pending')}\\">\\\\${esc(r.status||'pending')}</span></td>\\n      <td style=\\"text-align:right;font-variant-numeric:tabular-nums\\">\\\\${r.chunk_count??0}</td>\\n      <td class=\\"mono\\">\\\\${fmtDate(r.uploaded_at)}</td>\\n      <td><div class=\\"row-actions\\">\\n        <button class=\\"btn ghost sm\\" onclick=\\"view('\\\\${esc(r.id)}')\\">ดู</button>\\n        <button class=\\"btn sm\\" onclick=\\"edit('\\\\${esc(r.id)}')\\">แก้ไข</button>\\n        <button class=\\"btn danger sm\\" onclick=\\"del('\\\\${esc(r.id)}','\\\\${esc(r.file_name||'')}')\\">ลบ</button>\\n      </div></td>\\n    </tr>\\n  \\\\`}).join('');\\n}\\n\\nasync function view(id){\\n  try{\\n    const data = await api('/webhook/admin-get?id='+encodeURIComponent(id));\\n    const r = (Array.isArray(data)?data[0]:((data&&data.data)||data));\\n    if(!r||!r.id){toast('ไม่พบเอกสาร','err');return}\\n    const chunks = r.chunks||[];\\n    const fileUrl = '/webhook/admin-file?id='+encodeURIComponent(id);\\n    document.getElementById('v-title').textContent = r.file_name||'(ไม่มีชื่อ)';\\n    document.getElementById('v-body').innerHTML = \\\\`\\n      <div class=\\"preview-grid\\">\\n        <section>\\n          <div class=\\"preview-bar\\">\\n            <div><div class=\\"hint\\">ไฟล์จาก Postgres</div><strong>\\\\${esc(r.file_name||'document')}</strong></div>\\n            <a href=\\"\\\\${esc(fileUrl)}\\" target=\\"_blank\\" class=\\"btn ghost sm\\" style=\\"text-decoration:none\\">เปิดแท็บใหม่</a>\\n          </div>\\n          <div class=\\"file-preview\\"><iframe src=\\"\\\\${esc(fileUrl) + '#toolbar=0&navpanes=0&scrollbar=0&view=FitH'}\\" title=\\"\\\\${esc(r.file_name||'document')}\\"></iframe></div>\\n        </section>\\n        <section>\\n          <div class=\\"grid2 meta-grid\\">\\n            <div><div class=\\"hint\\">Doc No</div><div class=\\"mono\\" style=\\"font-weight:500\\">\\\\${esc(r.doc_no||'—')}</div></div>\\n            <div><div class=\\"hint\\">Status</div><span class=\\"badge \\\\${esc(r.status)}\\">\\\\${esc(r.status)}</span></div>\\n            <div><div class=\\"hint\\">Category</div>\\\\${esc(r.category||'—')}</div>\\n            <div><div class=\\"hint\\">Source</div>\\\\${esc(r.source||'—')}</div>\\n            <div><div class=\\"hint\\">File Type</div>\\\\${esc(r.file_type||'—')}</div>\\n            <div><div class=\\"hint\\">Size</div>\\\\${r.size_bytes?(Math.round(r.size_bytes/1024)+' KB'):'—'}</div>\\n            <div><div class=\\"hint\\">Line User</div><div class=\\"mono\\" style=\\"font-size:11px\\">\\\\${esc(r.line_user_id||'—')}</div></div>\\n            <div><div class=\\"hint\\">Line Group</div><div class=\\"mono\\" style=\\"font-size:11px\\">\\\\${esc(r.line_group_id||'—')}</div></div>\\n            <div><div class=\\"hint\\">อัปโหลด</div>\\\\${fmtDate(r.uploaded_at)}</div>\\n            <div><div class=\\"hint\\">อัปเดต</div>\\\\${fmtDate(r.updated_at)}</div>\\n          </div>\\n          <div style=\\"margin-top:18px\\">\\n            <div class=\\"hint\\" style=\\"margin-bottom:6px\\">Chunks (\\\\${chunks.length})</div>\\n            <div class=\\"chunk-list\\">\\\\${chunks.length?chunks.map(c=>\\\\`<div class=\\"chunk\\"><div class=\\"ci\\">#\\\\${c.chunk_index} • \\\\${c.token_count||0} tokens</div><div class=\\"cp\\">\\\\${esc(c.preview||'')}</div></div>\\\\`).join(''):'<div class=\\"chunk\\" style=\\"color:var(--muted-2)\\">ยังไม่มี chunks</div>'}</div>\\n          </div>\\n        </section>\\n      </div>\\n    \\\\`;\\n    document.getElementById('v-edit-btn').onclick = ()=>{closeModal('m-view');edit(id)};\\n    document.getElementById('v-open-btn').onclick = ()=>window.open(fileUrl, '_blank');\\n    document.getElementById('m-view').classList.add('on');\\n  }catch(e){toast('โหลดรายละเอียดไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nfunction edit(id){\\n  const r = allRows.find(x=>x.id===id);\\n  if(!r){toast('ไม่พบเอกสาร','err');return}\\n  document.getElementById('e-id').value = id;\\n  document.getElementById('e-doc_no').value = r.doc_no||'';\\n  document.getElementById('e-file_name').value = r.file_name||'';\\n  document.getElementById('e-category').value = r.category||'';\\n  document.getElementById('e-source').value = r.source||'';\\n  document.getElementById('e-status').value = r.status||'pending';\\n  document.getElementById('m-edit').classList.add('on');\\n}\\n\\nasync function saveEdit(){\\n  const id = document.getElementById('e-id').value;\\n  const body = {\\n    id,\\n    file_name: document.getElementById('e-file_name').value.trim(),\\n    category: document.getElementById('e-category').value.trim(),\\n    source: document.getElementById('e-source').value.trim(),\\n    status: document.getElementById('e-status').value\\n  };\\n  if(!body.file_name){toast('กรุณากรอกชื่อไฟล์','err');return}\\n  try{\\n    await api('/webhook/admin-update',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});\\n    toast('บันทึกเรียบร้อย','ok');\\n    closeModal('m-edit');\\n    loadList();loadStats();\\n  }catch(e){toast('บันทึกไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nasync function del(id, name){\\n  if(!confirm('ลบ \\"'+name+'\\"?\\\\\\\\n\\\\\\\\n⚠️ chunks ทั้งหมดจะถูกลบด้วย (CASCADE)')) return;\\n  try{\\n    await api('/webhook/admin-delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})});\\n    toast('ลบเรียบร้อย','ok');\\n    loadList();loadStats();\\n  }catch(e){toast('ลบไม่สำเร็จ: '+e.message,'err')}\\n}\\n\\nfunction closeModal(id){document.getElementById(id).classList.remove('on')}\\n\\ndocument.getElementById('btn-refresh').onclick = ()=>{loadList();loadStats()};\\ndocument.getElementById('q').oninput = debounce(loadList, 300);\\ndocument.getElementById('f-status').onchange = loadList;\\ndocument.getElementById('e-save').onclick = saveEdit;\\n\\nfunction debounce(fn, ms){let t;return(...a)=>{clearTimeout(t);t=setTimeout(()=>fn(...a),ms)}}\\n\\n// Read URL query params (?q=, ?status=) and pre-fill inputs\\nconst urlParams = new URLSearchParams(window.location.search);\\nconst urlQ = urlParams.get('q');\\nconst urlStatus = urlParams.get('status');\\nif (urlQ) document.getElementById('q').value = urlQ;\\nif (urlStatus) document.getElementById('f-status').value = urlStatus;\\n\\nloadList();\\nloadStats();\\nsetInterval(()=>{loadStats()}, 60000);\\n</script>\\n</body>\\n</html>`;\\nreturn [{json: {html: html}}];\\n"},"id":"code-build-html","name":"Build HTML","type":"n8n-nodes-base.code","typeVersion":2,"position":[176,0]},{"parameters":{"respondWith":"text","responseBody":"={{ $('Build HTML').first().json.html }}","options":{"responseHeaders":{"entries":[{"name":"Content-Type","value":"text/html; charset=utf-8"}]}}},"id":"resp-ui","name":"Respond UI","type":"n8n-nodes-base.respondToWebhook","typeVersion":1,"position":[400,0]},{"parameters":{"path":"admin-list","responseMode":"lastNode","options":{}},"id":"wh-admin-list","name":"Admin List","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,224],"webhookId":"admin-list-wh"},{"parameters":{"path":"admin-get","responseMode":"lastNode","options":{}},"id":"wh-admin-get","name":"Admin Get","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,448],"webhookId":"admin-get-wh"},{"parameters":{"httpMethod":"POST","path":"admin-update","responseMode":"lastNode","options":{}},"id":"wh-admin-update","name":"Admin Update","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1120],"webhookId":"admin-update-wh"},{"parameters":{"httpMethod":"POST","path":"admin-delete","responseMode":"lastNode","options":{}},"id":"wh-admin-delete","name":"Admin Delete","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1344],"webhookId":"admin-delete-wh"},{"parameters":{"path":"admin-stats","responseMode":"lastNode","options":{}},"id":"wh-admin-stats","name":"Admin Stats","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,1568],"webhookId":"admin-stats-wh"},{"parameters":{"operation":"executeQuery","query":"SELECT * FROM (\\n  SELECT id, doc_no, file_name, file_type, category, status, source, size_bytes, chunk_count, line_user_id, uploaded_at, updated_at, error_message\\n  FROM contracts c\\n  WHERE (($1::text IS NULL OR $1 = '')\\n      OR LOWER(COALESCE(file_name,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(category,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(source,'')) LIKE '%' || LOWER($1) || '%'\\n      OR LOWER(COALESCE(doc_no,'')) LIKE '%' || LOWER($1) || '%')\\n    AND ($2::text IS NULL OR $2 = '' OR status = $2)\\n  ORDER BY uploaded_at DESC\\n  LIMIT $3::int OFFSET $4::int\\n) real\\nUNION ALL\\nSELECT NULL::uuid, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL\\nWHERE NOT EXISTS (SELECT 1 FROM contracts)\\nORDER BY 1 NULLS LAST","options":{"queryReplacement":"={{ [($json.query && $json.query.q) || null, ($json.query && $json.query.status) || null, parseInt(($json.query && $json.query.limit) || 200, 10), parseInt(($json.query && $json.query.offset) || 0, 10)] }}"}},"id":"pg-admin-list","name":"PG: Admin List","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,224],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT c.id, c.doc_no, c.file_name, c.file_type, c.category, c.status, c.source, c.size_bytes, c.chunk_count, c.line_user_id, c.line_group_id, c.line_message_id, c.uploaded_at, c.updated_at, (SELECT json_agg(json_build_object('id', ch.id, 'chunk_index', ch.chunk_index, 'preview', LEFT(ch.content, 200), 'token_count', ch.token_count) ORDER BY ch.chunk_index) FROM contract_chunks ch WHERE ch.contract_id = c.id) AS chunks FROM contracts c WHERE c.id = $1::uuid","options":{"queryReplacement":"={{ [$json.query.id] }}"}},"id":"pg-admin-get","name":"PG: Admin Get","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,448],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"UPDATE contracts SET file_name = COALESCE(NULLIF($2, ''), file_name), category = NULLIF($3, ''), source = NULLIF($4, ''), status = COALESCE(NULLIF($5, ''), status), updated_at = now() WHERE id = $1::uuid RETURNING id, doc_no, file_name, file_type, category, status, source, size_bytes, chunk_count, line_user_id, uploaded_at, updated_at","options":{"queryReplacement":"={{ [$json.body.id, $json.body.file_name, $json.body.category, $json.body.source, $json.body.status] }}"}},"id":"pg-admin-update","name":"PG: Admin Update","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1120],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"DELETE FROM contracts\\nWHERE id = $1::uuid\\nRETURNING id, file_name, storage_bucket, storage_path,\\n  CASE \\n    WHEN storage_path LIKE 'http%' AND storage_path LIKE '%/' || storage_bucket || '/%'\\n    THEN split_part(storage_path, '/' || storage_bucket || '/', 2)\\n    ELSE NULL\\n  END AS minio_key;","options":{"queryReplacement":"={{ [$json.body.id] }}"}},"id":"pg-admin-delete","name":"PG: Admin Delete","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1344],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"operation":"executeQuery","query":"SELECT (SELECT COUNT(*) FROM contracts) AS total, (SELECT COUNT(*) FROM contracts WHERE status='ready') AS ready, (SELECT COUNT(*) FROM contracts WHERE status='pending') AS pending, (SELECT COUNT(*) FROM contracts WHERE status='failed') AS failed","options":{}},"id":"pg-admin-stats","name":"PG: Admin Stats","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,1568],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Wrap list results - always output 1 item even if empty\\nlet items = $input.all().map(i => i.json);\\n// Filter out dummy rows (where id IS NULL)\\nitems = items.filter(it => it && it.id != null);\\nreturn [{json: {ok: true, action: 'list', count: items.length, data: items}}];"},"id":"wrap-list","name":"Wrap List","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,224]},{"parameters":{"jsCode":"// Wrap get result - returns null if no row found\\nconst items = $input.all().map(i => i.json).filter(it => it && it.id != null);\\nreturn [{json: {ok: items.length > 0, action: 'get', data: items[0] || null}}];"},"id":"wrap-get","name":"Wrap Get","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,448]},{"parameters":{"jsCode":"// Wrap update result\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'update', data: items[0] || null}}];"},"id":"wrap-update","name":"Wrap Update","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1120]},{"parameters":{"jsCode":"// Wrap delete result\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'delete', data: items[0] || null}}];"},"id":"wrap-delete","name":"Wrap Delete","type":"n8n-nodes-base.code","typeVersion":2,"position":[848,1344]},{"parameters":{"jsCode":"// Wrap stats result - always output 1 item\\nconst items = $input.all().map(i => i.json);\\nreturn [{json: {ok: true, action: 'stats', data: items[0] || {total: 0, ready: 0, pending: 0, failed: 0}}}];"},"id":"wrap-stats","name":"Wrap Stats","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1568]},{"parameters":{"jsCode":"// minio_key is computed in SQL (short string, ~26 chars, not ref-compressed).\\n// Just copy it to _minio_key for MinIO Delete.\\nconst data = $input.first().json;\\nconst minioKey = data.minio_key;\\nreturn [{\\n  json: {\\n    ...data,\\n    _minio_bucket: data.storage_bucket,\\n    _minio_key: minioKey,\\n    _skip_minio_delete: !minioKey\\n  }\\n}];"},"id":"extract-minio-key-001","name":"Extract MinIO Key","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,1344],"alwaysOutputData":true},{"parameters":{"operation":"delete","bucketName":"epsx-contracts","fileKey":"={{ $json._minio_key }}","options":{}},"id":"minio-delete-001","name":"MinIO Delete","type":"n8n-nodes-base.s3","typeVersion":1,"position":[624,1344],"credentials":{"s3":{"id":"f719a9dd-b576-4cd5-bde6-13fb6344c447","name":"MinIO Contracts"}}},{"parameters":{"path":"admin-file","responseMode":"responseNode","options":{}},"id":"wh-admin-file","name":"Admin File","type":"n8n-nodes-base.webhook","typeVersion":2,"position":[-48,672],"webhookId":"admin-file-webhook"},{"parameters":{"operation":"executeQuery","query":"SELECT id, file_name, file_type,\\n  COALESCE(\\n    file_mime,\\n    CASE\\n      WHEN lower(COALESCE(file_type, '')) = 'pdf' THEN 'application/pdf'\\n      WHEN lower(COALESCE(file_type, '')) = 'png' THEN 'image/png'\\n      WHEN lower(COALESCE(file_type, '')) IN ('jpg', 'jpeg') THEN 'image/jpeg'\\n      WHEN lower(COALESCE(file_type, '')) = 'txt' THEN 'text/plain; charset=utf-8'\\n      ELSE 'application/octet-stream'\\n    END\\n  ) AS file_mime,\\n  encode(file_data, 'base64') AS file_data_b64,\\n  octet_length(file_data) AS file_size\\nFROM contracts\\nWHERE id = $1::uuid","options":{"queryReplacement":"={{ [$json.query.id] }}"}},"id":"pg-admin-file","name":"PG: Admin File","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[176,672],"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"// Build binary file response from contracts.file_data (Postgres bytea).\\nconst item = $input.first();\\nconst json = item?.json || {};\\nlet mime = json.file_mime || (json.file_type === 'pdf' ? 'application/pdf' : 'application/octet-stream');\\nlet fileName = json.file_name || 'document';\\nlet fileDataB64 = json.file_data_b64 || '';\\n\\nif (!fileDataB64) {\\n  const message = 'No file_data stored in Postgres for this document. Re-upload or backfill contracts.file_data.';\\n  fileDataB64 = Buffer.from(message, 'utf8').toString('base64');\\n  mime = 'text/plain; charset=utf-8';\\n  fileName = 'missing-file.txt';\\n}\\n\\nconst fileSize = Buffer.from(fileDataB64, 'base64').length;\\nreturn [{\\n  json: { file_name: fileName, file_mime: mime, file_size: fileSize },\\n  binary: {\\n    data: {\\n      data: fileDataB64,\\n      mimeType: mime,\\n      fileName,\\n      fileSize,\\n    }\\n  }\\n}];\\n"},"id":"wrap-file","name":"Wrap File","type":"n8n-nodes-base.code","typeVersion":2,"position":[400,672]},{"parameters":{"respondWith":"binary","options":{"responseCode":200,"responseHeaders":{"entries":[{"name":"Content-Disposition","value":"={{ 'inline; filename=\\"' + (($json.file_name || 'document').replace(/\\"/g, '')) + '\\"' }}"},{"name":"Content-Type","value":"={{ $json.file_mime || 'application/octet-stream' }}"},{"name":"Cache-Control","value":"no-cache"}]}}},"id":"resp-file","name":"Respond File","type":"n8n-nodes-base.respondToWebhook","typeVersion":1.1,"position":[624,672]},{"parameters":{"path":"admin-semantic-search","responseMode":"lastNode","options":{}},"id":"wh-admin-semantic","name":"Admin Semantic Search","type":"n8n-nodes-base.webhook","position":[-48,896],"typeVersion":1,"webhookId":"b55eade8-a4fa-4f89-b72c-199525e05146"},{"parameters":{"jsCode":"const wrapped = $input.first().json;\\nconst q = wrapped._query || wrapped.query || {};\\nconst body = wrapped._body || wrapped.body || wrapped || {};\\nconst query = (q.q || body.q || \\"\\").toString().trim();\\nconst limit = parseInt(q.limit || body.limit || 20, 10) || 20;\\nreturn [{json: {query, _query: query, _limit: limit}}];"},"id":"parse-semantic","name":"Parse Semantic","type":"n8n-nodes-base.code","position":[176,896],"typeVersion":2},{"parameters":{"method":"POST","url":"={{ ($env.OLLAMA_URL || \\"http://127.0.0.1:11434\\") }}/api/embed","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"{{ $env.OLLAMA_EMBED_MODEL || 'bge-m3' }}\\",\\n  \\"input\\": {{ JSON.stringify($json.query) }} }","options":{"timeout":30000}},"id":"embed-semantic","name":"Embed Semantic","type":"n8n-nodes-base.httpRequest","position":[400,896],"typeVersion":4.2},{"parameters":{"operation":"executeQuery","query":"WITH q AS (SELECT $1::vector AS qvec, $3::text AS qtxt),\\nv AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         1 - (ch.embedding <=> q.qvec) AS v_sim,\\n         ROW_NUMBER() OVER (ORDER BY ch.embedding <=> q.qvec) AS v_rank\\n  FROM contract_chunks ch, q\\n  WHERE ch.embedding IS NOT NULL\\n  ORDER BY ch.embedding <=> q.qvec\\n  LIMIT $2::int * 4\\n),\\nt AS (\\n  SELECT ch.contract_id, ch.chunk_index, ch.content,\\n         (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 1.0 ELSE 0 END)::float\\n         + (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float\\n           / greatest(length(q.qtxt), 1)::float * 0.1 AS t_sim,\\n         ROW_NUMBER() OVER (ORDER BY\\n           (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n           (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float DESC,\\n           ch.chunk_index ASC) AS t_rank\\n  FROM contract_chunks ch, q\\n  WHERE length(q.qtxt) > 0\\n  ORDER BY (CASE WHEN ch.content ILIKE '%' || q.qtxt || '%' THEN 0 ELSE 1 END),\\n           (length(ch.content) - length(replace(lower(ch.content), lower(q.qtxt), '')))::float DESC\\n  LIMIT $2::int * 4\\n),\\nfused AS (\\n  SELECT COALESCE(v.contract_id, t.contract_id) AS contract_id,\\n         COALESCE(v.chunk_index, t.chunk_index) AS chunk_index,\\n         COALESCE(v.content, t.content) AS content,\\n         COALESCE(1.0/(60+v.v_rank), 0) + COALESCE(1.0/(60+t.t_rank), 0) AS rrf_score,\\n         COALESCE(v.v_sim, 0) AS v_sim,\\n         COALESCE(t.t_sim, 0) AS t_sim\\n  FROM v FULL OUTER JOIN t ON v.contract_id = t.contract_id AND v.chunk_index = t.chunk_index\\n  WHERE COALESCE(v.contract_id, t.contract_id) IS NOT NULL\\n),\\ncontract_ranked AS (\\n  SELECT *, ROW_NUMBER() OVER (PARTITION BY contract_id ORDER BY rrf_score DESC) AS in_contract_rank\\n  FROM fused\\n),\\nbest_per_contract AS (\\n  SELECT contract_id, chunk_index, content, rrf_score, v_sim, t_sim\\n  FROM contract_ranked\\n  WHERE in_contract_rank = 1\\n  ORDER BY rrf_score DESC\\n  LIMIT $2::int\\n),\\njoined AS (\\n  SELECT c.id, c.doc_no, c.file_name, c.file_type, c.category, c.status, c.source,\\n         c.size_bytes, c.chunk_count, c.line_user_id, c.uploaded_at, c.updated_at, c.error_message,\\n         b.chunk_index AS top_chunk_index, b.content AS top_chunk_content,\\n         b.rrf_score AS similarity, b.v_sim AS vector_sim, b.t_sim AS keyword_sim\\n  FROM best_per_contract b\\n  JOIN contracts c ON c.id = b.contract_id\\n)\\nSELECT COALESCE(\\n  (SELECT json_build_object(\\n    'ok', true,\\n    'mode', 'semantic',\\n    'query', $3::text,\\n    'count', (SELECT COUNT(*)::int FROM joined),\\n    'data', COALESCE((SELECT json_agg(row_to_json(j) ORDER BY similarity DESC) FROM joined j), '[]'::json)\\n  )::text),\\n  json_build_object('ok', true, 'mode', 'semantic', 'query', $3::text, 'count', 0, 'data', '[]'::json)::text\\n) AS result_json","options":{"queryReplacement":"={{ [($json.embeddings && $json.embeddings[0]) ? \\"[\\" + $json.embeddings[0].map(Number).join(\\",\\") + \\"]\\" : \\"[]\\", parseInt($(\\"Parse Semantic\\").first().json._limit || 20, 10), $(\\"Parse Semantic\\").first().json._query || \\"\\"] }}"}},"id":"pg-admin-semantic","name":"PG: Admin Semantic","type":"n8n-nodes-base.postgres","position":[624,896],"typeVersion":2.4,"credentials":{"postgres":{"id":"a70ff3bd-3863-49c2-b2d4-e74d97d77c01","name":"PG Contracts - localhost:5432"}}},{"parameters":{"jsCode":"const row = $input.first().json;\\nlet result;\\ntry {\\n  result = JSON.parse(row.result_json || '{\\"ok\\":true,\\"count\\":0,\\"data\\":[]}');\\n} catch(e) {\\n  return [{json: {ok: false, error: \\"parse_failed\\", message: e.message, data: []}}];\\n}\\nreturn [{json: result}];"},"id":"wrap-semantic","name":"Wrap Semantic","type":"n8n-nodes-base.code","position":[848,896],"typeVersion":2},{"parameters":{"respondWith":"json","responseBody":"={{ $json }}","options":{}},"id":"resp-semantic","name":"Respond Semantic","type":"n8n-nodes-base.respondToWebhook","position":[1072,896],"typeVersion":1}]	{"Admin Get":{"main":[[{"node":"PG: Admin Get","type":"main","index":0}]]},"Admin List":{"main":[[{"node":"PG: Admin List","type":"main","index":0}]]},"Build HTML":{"main":[[{"node":"Respond UI","type":"main","index":0}]]},"Admin Stats":{"main":[[{"node":"PG: Admin Stats","type":"main","index":0}]]},"Admin Delete":{"main":[[{"node":"PG: Admin Delete","type":"main","index":0}]]},"Admin Update":{"main":[[{"node":"PG: Admin Update","type":"main","index":0}]]},"PG: Admin Get":{"main":[[{"node":"Wrap Get","type":"main","index":0}]]},"PG: Admin List":{"main":[[{"node":"Wrap List","type":"main","index":0}]]},"PG: Admin Stats":{"main":[[{"node":"Wrap Stats","type":"main","index":0}]]},"Admin UI Webhook":{"main":[[{"node":"Build HTML","type":"main","index":0}]]},"PG: Admin Delete":{"main":[[{"node":"Extract MinIO Key","type":"main","index":0}]]},"PG: Admin Update":{"main":[[{"node":"Wrap Update","type":"main","index":0}]]},"Extract MinIO Key":{"main":[[{"node":"MinIO Delete","type":"main","index":0}]]},"MinIO Delete":{"main":[[{"node":"Wrap Delete","type":"main","index":0}]]},"Admin File":{"main":[[{"node":"PG: Admin File","type":"main","index":0}]]},"PG: Admin File":{"main":[[{"node":"Wrap File","type":"main","index":0}]]},"Wrap File":{"main":[[{"node":"Respond File","type":"main","index":0}]]},"Admin Semantic Search":{"main":[[{"node":"Parse Semantic","type":"main","index":0}]]},"Parse Semantic":{"main":[[{"node":"Embed Semantic","type":"main","index":0}]]},"Embed Semantic":{"main":[[{"node":"PG: Admin Semantic","type":"main","index":0}]]},"PG: Admin Semantic":{"main":[[{"node":"Wrap Semantic","type":"main","index":0}]]},"Wrap Semantic":{"main":[[{"node":"Respond Semantic","type":"main","index":0}]]}}	\N	t	\N	[]
\.


--
-- Data for Name: workflow_publication_outbox; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_publication_outbox (id, "workflowId", "publishedVersionId", status, "errorMessage", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: workflow_publish_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_publish_history (id, "workflowId", "versionId", event, "userId", "createdAt") FROM stdin;
136	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 16:01:28.639+07
137	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 16:01:52.258+07
138	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 16:01:52.28+07
254	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:58:49.662+07
255	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:58:49.678+07
256	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:58:49.725+07
257	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:58:49.738+07
1	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 00:45:24.166+07
273	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 23:45:58.355+07
2	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 00:45:24.191+07
13	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 17:40:51.153+07
14	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 17:40:51.173+07
15	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 17:41:25.884+07
16	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 17:41:25.898+07
17	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:20:59.26+07
18	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:20:59.277+07
19	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:20:59.329+07
20	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:20:59.344+07
21	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:22:19.551+07
22	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:22:19.569+07
23	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:22:19.619+07
24	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:22:19.637+07
25	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:46:12.813+07
26	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:46:12.849+07
27	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:46:12.895+07
28	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:46:12.91+07
29	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:48:10.149+07
30	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:48:10.17+07
31	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:48:10.222+07
32	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 18:48:10.246+07
33	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.742+07
34	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.762+07
35	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.817+07
36	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.837+07
37	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.894+07
38	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.906+07
39	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.938+07
40	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:17:48.953+07
41	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:05.695+07
42	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:05.714+07
43	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:05.778+07
44	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:05.802+07
45	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:52.432+07
46	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:52.471+07
47	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:52.519+07
48	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:25:52.547+07
49	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:34:55.913+07
50	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:34:55.935+07
51	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:34:55.984+07
52	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 19:34:56.002+07
53	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:20:18.822+07
54	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:20:18.853+07
55	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:24:17.369+07
56	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:24:17.405+07
57	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:25:08.857+07
58	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:25:17.441+07
59	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:33:08.29+07
60	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 23:33:08.333+07
61	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 00:02:33.022+07
62	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 00:02:33.048+07
63	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 00:16:49.651+07
64	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 00:16:52.451+07
65	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 01:35:39.76+07
66	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 01:35:39.781+07
111	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:54:43.168+07
112	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:54:43.195+07
113	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:22:44.875+07
114	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:22:44.892+07
116	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:25:38.588+07
117	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:25:38.605+07
118	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:25:40.691+07
119	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:40:46.836+07
120	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:40:46.854+07
121	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:41:59.168+07
122	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:41:59.189+07
127	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:55:11.134+07
128	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:55:11.165+07
129	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 15:05:18.967+07
130	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 15:05:18.996+07
123	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:49:37.594+07
124	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:49:37.619+07
125	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:49:46.681+07
126	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:49:46.706+07
158	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:48:41.857+07
159	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:48:57.011+07
160	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:48:57.036+07
274	wb0BxLBPY80gSVpK	342bf076-f7ce-4690-884f-889a033db7d9	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-25 00:07:21.902+07
275	wb0BxLBPY80gSVpK	342bf076-f7ce-4690-884f-889a033db7d9	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-25 00:07:21.935+07
73	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 11:58:45.939+07
74	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 11:58:45.963+07
75	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:06:09.44+07
76	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:06:09.459+07
77	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:07:34.094+07
78	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:07:34.115+07
79	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:19:34.364+07
80	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:19:34.389+07
81	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:23:01.175+07
97	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:33:36.982+07
98	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:33:37.003+07
99	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:41:00.498+07
100	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:41:00.529+07
101	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:42:25.984+07
102	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:42:26.008+07
103	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:44:36.677+07
104	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:44:36.695+07
105	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:47:55.081+07
106	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:47:55.104+07
107	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:50:23.202+07
108	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:50:23.228+07
89	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:58:08.677+07
90	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:58:08.691+07
91	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:06:02.947+07
92	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:06:02.974+07
93	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:26:20.321+07
94	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:26:20.341+07
95	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:30:19.435+07
96	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:30:19.462+07
109	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:50:53.522+07
3	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 12:28:30.493+07
4	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 12:28:30.512+07
5	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:19:57.334+07
6	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:19:57.35+07
7	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:21:34.769+07
8	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:21:34.796+07
9	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:28:51.906+07
10	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:28:51.928+07
11	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:30:40.608+07
12	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-22 14:30:40.68+07
171	TL2qrOygnWKY69xe	9a290dc3-4ead-4606-adec-2f3df5650125	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:26:43.487+07
172	TL2qrOygnWKY69xe	9a290dc3-4ead-4606-adec-2f3df5650125	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:26:43.511+07
173	AdM1nFlow12345678CD0cHub2	4936517b-f48b-4073-9755-0467045e870c	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 22:45:37.686+07
174	AdM1nFlow12345678CD0cHub2	4936517b-f48b-4073-9755-0467045e870c	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 22:45:37.704+07
131	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 15:07:41.445+07
132	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 15:07:41.469+07
133	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 15:59:42.89+07
134	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 15:59:42.915+07
135	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 16:01:28.617+07
139	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:24:52.641+07
140	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:24:52.664+07
141	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:26:41.06+07
142	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:26:41.088+07
143	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:29:10.813+07
144	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:29:10.836+07
145	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:44:15.404+07
146	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 17:44:17.519+07
147	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:05:24.082+07
148	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:05:24.108+07
149	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:08:23.032+07
150	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:08:23.053+07
151	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:18:16.305+07
152	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:18:16.331+07
153	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:32:22.424+07
154	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:32:22.451+07
155	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:44:17.835+07
156	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:44:17.856+07
157	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 18:48:41.837+07
161	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:11:18.701+07
162	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:11:18.728+07
163	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:20:04.208+07
164	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:20:04.231+07
165	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:22:32.511+07
166	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:22:32.536+07
167	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:23:38.275+07
168	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:23:38.296+07
169	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:26:20.631+07
170	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 19:26:20.655+07
184	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:23.891+07
185	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:23.901+07
186	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:23.942+07
175	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:19.29+07
176	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:29.147+07
177	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:29.166+07
178	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:29.236+07
179	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:29.249+07
180	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:53.775+07
181	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:53.787+07
182	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:53.834+07
183	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:04:53.844+07
258	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:55:59.454+07
259	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:55:59.467+07
260	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:55:59.512+07
261	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:55:59.522+07
262	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:56:18.434+07
263	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:56:18.447+07
264	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:56:18.486+07
187	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:23.949+07
190	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:41.732+07
191	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:41.742+07
188	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:41.667+07
189	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:05:41.684+07
198	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:25.332+07
199	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:25.341+07
196	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:25.274+07
197	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:25.284+07
192	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:10.393+07
193	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:10.415+07
194	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:10.457+07
195	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:06:10.466+07
200	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:39:02.71+07
201	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:39:02.721+07
202	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:39:02.765+07
203	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:39:02.779+07
265	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:56:18.497+07
270	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 23:23:49.041+07
226	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:49:07.999+07
227	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:49:08.014+07
228	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:49:08.057+07
229	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:49:08.065+07
234	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:07:40.242+07
235	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:07:40.265+07
67	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 10:59:17.112+07
68	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 10:59:17.13+07
69	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 11:08:55.318+07
70	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 11:08:55.345+07
71	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 11:09:26.403+07
72	TL2qrOygnWKY69xe	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 11:09:26.425+07
115	TL2qrOygnWKY69xe	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 14:25:38.394+07
236	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:07:40.31+07
237	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:07:40.318+07
238	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:08:18.824+07
239	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:08:18.836+07
240	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:08:18.889+07
241	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:08:18.901+07
242	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:18:08.084+07
243	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:18:08.094+07
244	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:18:08.161+07
245	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:18:08.173+07
230	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:50:29.575+07
231	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:50:29.587+07
232	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:50:29.629+07
233	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:50:29.639+07
246	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:21:12.662+07
247	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:21:12.674+07
248	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:21:12.743+07
82	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:23:01.192+07
83	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:28:38.699+07
84	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:28:38.719+07
85	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:41:16.531+07
86	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:41:16.548+07
87	AdM1nFlow12345678CD0cHub2	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:46:19.104+07
88	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 12:46:19.121+07
204	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:51:46.669+07
205	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:51:46.681+07
206	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:51:46.741+07
207	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 11:51:46.751+07
216	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:18:26.519+07
217	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:18:26.531+07
218	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:18:26.582+07
219	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:18:26.593+07
208	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:02:26.828+07
209	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:02:26.843+07
210	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:02:26.895+07
211	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:02:26.909+07
220	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:21:41.518+07
221	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:21:41.528+07
110	AdM1nFlow12345678CD0cHub2	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-23 13:50:53.538+07
222	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:21:41.572+07
223	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:21:41.593+07
224	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:28:33.715+07
225	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:28:33.728+07
212	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:12:28.297+07
213	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:12:28.309+07
214	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:12:28.361+07
215	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 12:12:28.376+07
249	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:21:12.758+07
250	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:27:05.568+07
251	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:27:05.594+07
252	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:27:05.655+07
253	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 13:27:05.67+07
266	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:59:29.806+07
267	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:59:29.823+07
268	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:59:29.879+07
269	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 15:59:29.89+07
271	wb0BxLBPY80gSVpK	\N	deactivated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 23:34:45.863+07
272	wb0BxLBPY80gSVpK	\N	activated	35364927-4efa-4921-b395-25d6fee03c8d	2026-06-24 23:34:45.887+07
\.


--
-- Data for Name: workflow_published_version; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_published_version ("workflowId", "publishedVersionId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: workflow_statistics; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflow_statistics (count, "latestEvent", name, "workflowId", "rootCount", id, "workflowName") FROM stdin;
1	2026-06-21 16:44:29.597+07	data_loaded	AdM1nFlow12345678CD0cHub2	1	1	\N
1	2026-06-21 16:44:30.422+07	data_loaded	TL2qrOygnWKY69xe	1	4	\N
48	2026-06-23 16:13:57.093+07	production_error	AdM1nFlow12345678CD0cHub2	48	3	04 - Docs Admin (CRUD UI)
72	2026-06-25 00:15:14.392+07	production_success	wb0BxLBPY80gSVpK	72	4266	HR Line Agent Bot (State Machine + NLP)
43	2026-06-23 19:27:32.64+07	production_error	TL2qrOygnWKY69xe	43	5	03 - Docs Hub
92	2026-06-24 16:22:20.218+07	production_success	TL2qrOygnWKY69xe	92	8	03 - Docs Hub
1	2026-06-24 11:04:31.394+07	data_loaded	wb0BxLBPY80gSVpK	1	4260	\N
5069	2026-06-24 23:26:35.726+07	production_success	AdM1nFlow12345678CD0cHub2	5069	2	04 - Docs Admin (CRUD UI)
33	2026-06-24 23:39:47.531+07	production_error	wb0BxLBPY80gSVpK	33	4261	HR Line Agent Bot (State Machine + NLP)
\.


--
-- Data for Name: workflows_tags; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.workflows_tags ("workflowId", "tagId") FROM stdin;
\.


--
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_provider_sync_history_id_seq', 1, false);


--
-- Name: credential_dependency_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.credential_dependency_id_seq', 1, false);


--
-- Name: execution_annotations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.execution_annotations_id_seq', 1, false);


--
-- Name: execution_entity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.execution_entity_id_seq', 5390, true);


--
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.execution_metadata_temp_id_seq', 1, false);


--
-- Name: insights_by_period_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.insights_by_period_id_seq', 525, true);


--
-- Name: insights_metadata_metaId_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public."insights_metadata_metaId_seq"', 52, true);


--
-- Name: insights_raw_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.insights_raw_id_seq', 15977, true);


--
-- Name: instance_version_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.instance_version_history_id_seq', 1, true);


--
-- Name: migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.migrations_id_seq', 205, true);


--
-- Name: oauth_user_consents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth_user_consents_id_seq', 1, false);


--
-- Name: secrets_provider_connection_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.secrets_provider_connection_id_seq', 1, false);


--
-- Name: user_favorites_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_favorites_id_seq', 1, false);


--
-- Name: workflow_dependency_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.workflow_dependency_id_seq', 12649, true);


--
-- Name: workflow_publication_outbox_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.workflow_publication_outbox_id_seq', 1, false);


--
-- Name: workflow_publish_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.workflow_publish_history_id_seq', 275, true);


--
-- Name: workflow_statistics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.workflow_statistics_id_seq', 5392, true);


--
-- Name: test_run PK_011c050f566e9db509a0fadb9b9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run
    ADD CONSTRAINT "PK_011c050f566e9db509a0fadb9b9" PRIMARY KEY (id);


--
-- Name: project_secrets_provider_access PK_0402b7fcec5415246656f102f83; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_secrets_provider_access
    ADD CONSTRAINT "PK_0402b7fcec5415246656f102f83" PRIMARY KEY ("secretsProviderConnectionId", "projectId");


--
-- Name: installed_packages PK_08cc9197c39b028c1e9beca225940576fd1a5804; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installed_packages
    ADD CONSTRAINT "PK_08cc9197c39b028c1e9beca225940576fd1a5804" PRIMARY KEY ("packageName");


--
-- Name: instance_ai_run_snapshots PK_0a5fc9690a84950ebf1416fb146; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_run_snapshots
    ADD CONSTRAINT "PK_0a5fc9690a84950ebf1416fb146" PRIMARY KEY ("threadId", "runId");


--
-- Name: mcp_registry_server PK_12fd89a1fb8489513b0a91f5d31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mcp_registry_server
    ADD CONSTRAINT "PK_12fd89a1fb8489513b0a91f5d31" PRIMARY KEY (slug);


--
-- Name: instance_ai_messages PK_156c6f287225e9befe0181bb02b; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_messages
    ADD CONSTRAINT "PK_156c6f287225e9befe0181bb02b" PRIMARY KEY (id);


--
-- Name: agent_task_definition PK_1756c11c637903e97629a7a784a; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_definition
    ADD CONSTRAINT "PK_1756c11c637903e97629a7a784a" PRIMARY KEY (id);


--
-- Name: execution_metadata PK_17a0b6284f8d626aae88e1c16e4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_metadata
    ADD CONSTRAINT "PK_17a0b6284f8d626aae88e1c16e4" PRIMARY KEY (id);


--
-- Name: role_mapping_rule_project PK_198c5b5aea509d139274efcaf9a; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_mapping_rule_project
    ADD CONSTRAINT "PK_198c5b5aea509d139274efcaf9a" PRIMARY KEY ("roleMappingRuleId", "projectId");


--
-- Name: project_relation PK_1caaa312a5d7184a003be0f0cb6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "PK_1caaa312a5d7184a003be0f0cb6" PRIMARY KEY ("projectId", "userId");


--
-- Name: chat_hub_sessions PK_1eafef1273c70e4464fec703412; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "PK_1eafef1273c70e4464fec703412" PRIMARY KEY (id);


--
-- Name: agent_task_snapshot PK_2142a8bcda2360c3c5e34f82640; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_snapshot
    ADD CONSTRAINT "PK_2142a8bcda2360c3c5e34f82640" PRIMARY KEY ("versionId", "taskId");


--
-- Name: instance_ai_iteration_logs PK_21c2b214b44bc6c34a6d3551c90; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_iteration_logs
    ADD CONSTRAINT "PK_21c2b214b44bc6c34a6d3551c90" PRIMARY KEY (id);


--
-- Name: agent_execution_threads PK_22373dbf6ba6929d8ac50093309; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_execution_threads
    ADD CONSTRAINT "PK_22373dbf6ba6929d8ac50093309" PRIMARY KEY (id);


--
-- Name: instance_ai_pending_confirmations PK_25c38179c8d45095b168adfff80; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_pending_confirmations
    ADD CONSTRAINT "PK_25c38179c8d45095b168adfff80" PRIMARY KEY ("requestId");


--
-- Name: agents_memory_entry_sources PK_278f05e98e74baaaa93f52b4bab; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_sources
    ADD CONSTRAINT "PK_278f05e98e74baaaa93f52b4bab" PRIMARY KEY (id);


--
-- Name: folder_tag PK_27e4e00852f6b06a925a4d83a3e; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_tag
    ADD CONSTRAINT "PK_27e4e00852f6b06a925a4d83a3e" PRIMARY KEY ("folderId", "tagId");


--
-- Name: instance_ai_threads PK_35575100e45cdedeb89ae0643e9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_threads
    ADD CONSTRAINT "PK_35575100e45cdedeb89ae0643e9" PRIMARY KEY (id);


--
-- Name: role PK_35c9b140caaf6da09cfabb0d675; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT "PK_35c9b140caaf6da09cfabb0d675" PRIMARY KEY (slug);


--
-- Name: secrets_provider_connection PK_4350ae85e76f9ba7df1370acb5d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secrets_provider_connection
    ADD CONSTRAINT "PK_4350ae85e76f9ba7df1370acb5d" PRIMARY KEY (id);


--
-- Name: instance_ai_resources PK_45b5b0b6f715dae4292b86603d8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_resources
    ADD CONSTRAINT "PK_45b5b0b6f715dae4292b86603d8" PRIMARY KEY (id);


--
-- Name: agents_threads PK_4a3feb0a13ffe315c009cce64e5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_threads
    ADD CONSTRAINT "PK_4a3feb0a13ffe315c009cce64e5" PRIMARY KEY (id);


--
-- Name: project PK_4d68b1358bb5b766d3e78f32f57; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT "PK_4d68b1358bb5b766d3e78f32f57" PRIMARY KEY (id);


--
-- Name: instance_ai_observations PK_4d9b514cdf0f0b577650caf2ac2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observations
    ADD CONSTRAINT "PK_4d9b514cdf0f0b577650caf2ac2" PRIMARY KEY (id);


--
-- Name: agent_checkpoints PK_50a27cbafa6806c9b162304b5fd; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_checkpoints
    ADD CONSTRAINT "PK_50a27cbafa6806c9b162304b5fd" PRIMARY KEY ("runId");


--
-- Name: dynamic_credential_entry PK_5135ffcabecad4727ff6b9b803d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_entry
    ADD CONSTRAINT "PK_5135ffcabecad4727ff6b9b803d" PRIMARY KEY (credential_id, subject_id, resolver_id);


--
-- Name: workflow_dependency PK_52325e34cd7a2f0f67b0f3cad65; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_dependency
    ADD CONSTRAINT "PK_52325e34cd7a2f0f67b0f3cad65" PRIMARY KEY (id);


--
-- Name: instance_ai_checkpoints PK_5315a45f0846d1f9d128c18a2ed; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_checkpoints
    ADD CONSTRAINT "PK_5315a45f0846d1f9d128c18a2ed" PRIMARY KEY (key);


--
-- Name: invalid_auth_token PK_5779069b7235b256d91f7af1a15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invalid_auth_token
    ADD CONSTRAINT "PK_5779069b7235b256d91f7af1a15" PRIMARY KEY (token);


--
-- Name: evaluation_config PK_59c14dccf8989df94070c2dcfda; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_config
    ADD CONSTRAINT "PK_59c14dccf8989df94070c2dcfda" PRIMARY KEY (id);


--
-- Name: instance_ai_observation_cursors PK_5b6319b2e9a37c1064a72428f9a; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observation_cursors
    ADD CONSTRAINT "PK_5b6319b2e9a37c1064a72428f9a" PRIMARY KEY ("observationScopeId");


--
-- Name: shared_workflow PK_5ba87620386b847201c9531c58f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_workflow
    ADD CONSTRAINT "PK_5ba87620386b847201c9531c58f" PRIMARY KEY ("workflowId", "projectId");


--
-- Name: workflow_published_version PK_5c76fb7ee939fe2530374d3f75a; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_published_version
    ADD CONSTRAINT "PK_5c76fb7ee939fe2530374d3f75a" PRIMARY KEY ("workflowId");


--
-- Name: folder PK_6278a41a706740c94c02e288df8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder
    ADD CONSTRAINT "PK_6278a41a706740c94c02e288df8" PRIMARY KEY (id);


--
-- Name: agent_history PK_65ffcfe7a8e112fb826311fb092; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_history
    ADD CONSTRAINT "PK_65ffcfe7a8e112fb826311fb092" PRIMARY KEY ("versionId");


--
-- Name: data_table_column PK_673cb121ee4a8a5e27850c72c51; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_table_column
    ADD CONSTRAINT "PK_673cb121ee4a8a5e27850c72c51" PRIMARY KEY (id);


--
-- Name: agent_files PK_692920e59217af7d124cd95106f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_files
    ADD CONSTRAINT "PK_692920e59217af7d124cd95106f" PRIMARY KEY (id);


--
-- Name: chat_hub_tools PK_696d26426c704fba79b2c195ef5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_tools
    ADD CONSTRAINT "PK_696d26426c704fba79b2c195ef5" PRIMARY KEY (id);


--
-- Name: annotation_tag_entity PK_69dfa041592c30bbc0d4b84aa00; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.annotation_tag_entity
    ADD CONSTRAINT "PK_69dfa041592c30bbc0d4b84aa00" PRIMARY KEY (id);


--
-- Name: user_favorites PK_6c472a19a7423cfbbf6b7c75939; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT "PK_6c472a19a7423cfbbf6b7c75939" PRIMARY KEY (id);


--
-- Name: instance_ai_observational_memory PK_7192dd00cddba039bf1d3e6a098; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observational_memory
    ADD CONSTRAINT "PK_7192dd00cddba039bf1d3e6a098" PRIMARY KEY (id);


--
-- Name: oauth_refresh_tokens PK_74abaed0b30711b6532598b0392; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_refresh_tokens
    ADD CONSTRAINT "PK_74abaed0b30711b6532598b0392" PRIMARY KEY (token);


--
-- Name: dynamic_credential_user_entry PK_74f548e633abc66dc27c8f0ca77; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_user_entry
    ADD CONSTRAINT "PK_74f548e633abc66dc27c8f0ca77" PRIMARY KEY ("credentialId", "userId", "resolverId");


--
-- Name: chat_hub_messages PK_7704a5add6baed43eef835f0bfb; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "PK_7704a5add6baed43eef835f0bfb" PRIMARY KEY (id);


--
-- Name: execution_annotations PK_7afcf93ffa20c4252869a7c6a23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_annotations
    ADD CONSTRAINT "PK_7afcf93ffa20c4252869a7c6a23" PRIMARY KEY (id);


--
-- Name: agents_observation_locks PK_7e2e315162ac3d80587e15ac2c3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observation_locks
    ADD CONSTRAINT "PK_7e2e315162ac3d80587e15ac2c3" PRIMARY KEY ("agentId", "observationScopeId", "taskKind");


--
-- Name: credential_dependency PK_80212729ed0ffa0709417ab28f4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_dependency
    ADD CONSTRAINT "PK_80212729ed0ffa0709417ab28f4" PRIMARY KEY (id);


--
-- Name: agents_messages PK_81020dc608dfb0af1ede386d907; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_messages
    ADD CONSTRAINT "PK_81020dc608dfb0af1ede386d907" PRIMARY KEY (id);


--
-- Name: ai_builder_temporary_workflow PK_85a87a1ba0f61999fe11dc56325; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_builder_temporary_workflow
    ADD CONSTRAINT "PK_85a87a1ba0f61999fe11dc56325" PRIMARY KEY ("workflowId");


--
-- Name: oauth_user_consents PK_85b9ada746802c8993103470f05; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "PK_85b9ada746802c8993103470f05" PRIMARY KEY (id);


--
-- Name: instance_version_history PK_874f58cb616935bf49d9dbd67e9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_version_history
    ADD CONSTRAINT "PK_874f58cb616935bf49d9dbd67e9" PRIMARY KEY (id);


--
-- Name: chat_hub_session_tools PK_87aea76ff4c274c4a5ac838ebe3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_session_tools
    ADD CONSTRAINT "PK_87aea76ff4c274c4a5ac838ebe3" PRIMARY KEY ("sessionId", "toolId");


--
-- Name: migrations PK_8c82d7f526340ab734260ea46be; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT "PK_8c82d7f526340ab734260ea46be" PRIMARY KEY (id);


--
-- Name: installed_nodes PK_8ebd28194e4f792f96b5933423fc439df97d9689; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installed_nodes
    ADD CONSTRAINT "PK_8ebd28194e4f792f96b5933423fc439df97d9689" PRIMARY KEY (name);


--
-- Name: shared_credentials PK_8ef3a59796a228913f251779cff; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_credentials
    ADD CONSTRAINT "PK_8ef3a59796a228913f251779cff" PRIMARY KEY ("credentialsId", "projectId");


--
-- Name: test_case_execution PK_90c121f77a78a6580e94b794bce; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_case_execution
    ADD CONSTRAINT "PK_90c121f77a78a6580e94b794bce" PRIMARY KEY (id);


--
-- Name: instance_ai_workflow_snapshots PK_93f2696eb321dfe1d7defe7073f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_workflow_snapshots
    ADD CONSTRAINT "PK_93f2696eb321dfe1d7defe7073f" PRIMARY KEY ("runId", "workflowName");


--
-- Name: deployment_key PK_94bb7aeb5def5a0284a5fe9f9a0; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deployment_key
    ADD CONSTRAINT "PK_94bb7aeb5def5a0284a5fe9f9a0" PRIMARY KEY (id);


--
-- Name: user_api_keys PK_978fa5caa3468f463dac9d92e69; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_keys
    ADD CONSTRAINT "PK_978fa5caa3468f463dac9d92e69" PRIMARY KEY (id);


--
-- Name: execution_annotation_tags PK_979ec03d31294cca484be65d11f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_annotation_tags
    ADD CONSTRAINT "PK_979ec03d31294cca484be65d11f" PRIMARY KEY ("annotationId", "tagId");


--
-- Name: trusted_key_source PK_99e8908ce2c2cdccce487db7fc6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_key_source
    ADD CONSTRAINT "PK_99e8908ce2c2cdccce487db7fc6" PRIMARY KEY (id);


--
-- Name: agents_observations PK_9ad319654d12c2649f7caf27135; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observations
    ADD CONSTRAINT "PK_9ad319654d12c2649f7caf27135" PRIMARY KEY (id);


--
-- Name: agents PK_9c653f28ae19c5884d5baf6a1d9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT "PK_9c653f28ae19c5884d5baf6a1d9" PRIMARY KEY (id);


--
-- Name: agents_memory_entry_locks PK_a8e0f570d04a174292bea104ae6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_locks
    ADD CONSTRAINT "PK_a8e0f570d04a174292bea104ae6" PRIMARY KEY ("agentId", "resourceId");


--
-- Name: webhook_entity PK_b21ace2e13596ccd87dc9bf4ea6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_entity
    ADD CONSTRAINT "PK_b21ace2e13596ccd87dc9bf4ea6" PRIMARY KEY ("webhookPath", method);


--
-- Name: agents_memory_entry_cursors PK_b31a1d5c009a27f4cc5ef8f102a; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_cursors
    ADD CONSTRAINT "PK_b31a1d5c009a27f4cc5ef8f102a" PRIMARY KEY ("agentId", "observationScopeId");


--
-- Name: workflow_publication_outbox PK_b3e2eeee36a4bd044d56468d311; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_publication_outbox
    ADD CONSTRAINT "PK_b3e2eeee36a4bd044d56468d311" PRIMARY KEY (id);


--
-- Name: insights_by_period PK_b606942249b90cc39b0265f0575; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_by_period
    ADD CONSTRAINT "PK_b606942249b90cc39b0265f0575" PRIMARY KEY (id);


--
-- Name: workflow_history PK_b6572dd6173e4cd06fe79937b58; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_history
    ADD CONSTRAINT "PK_b6572dd6173e4cd06fe79937b58" PRIMARY KEY ("versionId");


--
-- Name: dynamic_credential_resolver PK_b76cfb088dcdaf5275e9980bb64; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_resolver
    ADD CONSTRAINT "PK_b76cfb088dcdaf5275e9980bb64" PRIMARY KEY (id);


--
-- Name: agent_execution PK_ba438acc8532addc12d1ef17049; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_execution
    ADD CONSTRAINT "PK_ba438acc8532addc12d1ef17049" PRIMARY KEY (id);


--
-- Name: agents_memory_entries PK_bfbc45dc88f66fae4e4b4a15fec; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entries
    ADD CONSTRAINT "PK_bfbc45dc88f66fae4e4b4a15fec" PRIMARY KEY (id);


--
-- Name: scope PK_bfc45df0481abd7f355d6187da1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scope
    ADD CONSTRAINT "PK_bfc45df0481abd7f355d6187da1" PRIMARY KEY (slug);


--
-- Name: oauth_clients PK_c4759172d3431bae6f04e678e0d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients
    ADD CONSTRAINT "PK_c4759172d3431bae6f04e678e0d" PRIMARY KEY (id);


--
-- Name: workflow_publish_history PK_c788f7caf88e91e365c97d6d04a; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_publish_history
    ADD CONSTRAINT "PK_c788f7caf88e91e365c97d6d04a" PRIMARY KEY (id);


--
-- Name: processed_data PK_ca04b9d8dc72de268fe07a65773; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_data
    ADD CONSTRAINT "PK_ca04b9d8dc72de268fe07a65773" PRIMARY KEY ("workflowId", context);


--
-- Name: chat_hub_agent_tools PK_cc8806fdea48297a7d497035d72; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_agent_tools
    ADD CONSTRAINT "PK_cc8806fdea48297a7d497035d72" PRIMARY KEY ("agentId", "toolId");


--
-- Name: role_mapping_rule PK_d772c8ec1a89b52d31c882bc560; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_mapping_rule
    ADD CONSTRAINT "PK_d772c8ec1a89b52d31c882bc560" PRIMARY KEY (id);


--
-- Name: token_exchange_jti PK_d8e8a6f737d530fdd2dd716e89c; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_exchange_jti
    ADD CONSTRAINT "PK_d8e8a6f737d530fdd2dd716e89c" PRIMARY KEY (jti);


--
-- Name: settings PK_dc0fe14e6d9943f268e7b119f69ab8bd; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT "PK_dc0fe14e6d9943f268e7b119f69ab8bd" PRIMARY KEY (key);


--
-- Name: trusted_key PK_dc7d93798f3dbb6959f974c97e1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_key
    ADD CONSTRAINT "PK_dc7d93798f3dbb6959f974c97e1" PRIMARY KEY ("sourceId", kid);


--
-- Name: oauth_access_tokens PK_dcd71f96a5d5f4bf79e67d322bf; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT "PK_dcd71f96a5d5f4bf79e67d322bf" PRIMARY KEY (token);


--
-- Name: data_table PK_e226d0001b9e6097cbfe70617cb; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_table
    ADD CONSTRAINT "PK_e226d0001b9e6097cbfe70617cb" PRIMARY KEY (id);


--
-- Name: instance_ai_mcp_registry_connections PK_e34e4d15d78eabbe8217e33ef03; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_mcp_registry_connections
    ADD CONSTRAINT "PK_e34e4d15d78eabbe8217e33ef03" PRIMARY KEY (id);


--
-- Name: workflow_builder_session PK_e69ef0d385986e273423b0e8695; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_builder_session
    ADD CONSTRAINT "PK_e69ef0d385986e273423b0e8695" PRIMARY KEY (id);


--
-- Name: evaluation_collection PK_e720b6efc1e45b878ebb0b2ca30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_collection
    ADD CONSTRAINT "PK_e720b6efc1e45b878ebb0b2ca30" PRIMARY KEY (id);


--
-- Name: user PK_ea8f538c94b6e352418254ed6474a81f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT "PK_ea8f538c94b6e352418254ed6474a81f" PRIMARY KEY (id);


--
-- Name: agents_observation_cursors PK_eb777ac57ab872d38f8ebd19317; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observation_cursors
    ADD CONSTRAINT "PK_eb777ac57ab872d38f8ebd19317" PRIMARY KEY ("agentId", "observationScopeId");


--
-- Name: insights_raw PK_ec15125755151e3a7e00e00014f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_raw
    ADD CONSTRAINT "PK_ec15125755151e3a7e00e00014f" PRIMARY KEY (id);


--
-- Name: chat_hub_agents PK_f39a3b36bbdf0e2979ddb21cf78; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_agents
    ADD CONSTRAINT "PK_f39a3b36bbdf0e2979ddb21cf78" PRIMARY KEY (id);


--
-- Name: insights_metadata PK_f448a94c35218b6208ce20cf5a1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_metadata
    ADD CONSTRAINT "PK_f448a94c35218b6208ce20cf5a1" PRIMARY KEY ("metaId");


--
-- Name: agent_task_run_lock PK_f593adaf7230e964d3c25deda64; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_run_lock
    ADD CONSTRAINT "PK_f593adaf7230e964d3c25deda64" PRIMARY KEY ("agentId", "taskId");


--
-- Name: agents_resources PK_fa6b20b2d31a9991529dbf8ef7d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_resources
    ADD CONSTRAINT "PK_fa6b20b2d31a9991529dbf8ef7d" PRIMARY KEY (id);


--
-- Name: oauth_authorization_codes PK_fb91ab932cfbd694061501cc20f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_authorization_codes
    ADD CONSTRAINT "PK_fb91ab932cfbd694061501cc20f" PRIMARY KEY (code);


--
-- Name: binary_data PK_fc3691585b39408bb0551122af6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.binary_data
    ADD CONSTRAINT "PK_fc3691585b39408bb0551122af6" PRIMARY KEY ("fileId");


--
-- Name: instance_ai_observation_locks PK_fc491dd378b9448655c3c683f85; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observation_locks
    ADD CONSTRAINT "PK_fc491dd378b9448655c3c683f85" PRIMARY KEY ("observationScopeId", "taskKind");


--
-- Name: role_scope PK_role_scope; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_scope
    ADD CONSTRAINT "PK_role_scope" PRIMARY KEY ("roleSlug", "scopeSlug");


--
-- Name: oauth_user_consents UQ_083721d99ce8db4033e2958ebb4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "UQ_083721d99ce8db4033e2958ebb4" UNIQUE ("userId", "clientId");


--
-- Name: evaluation_config UQ_3c3c99a712e971835c52292e44c; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_config
    ADD CONSTRAINT "UQ_3c3c99a712e971835c52292e44c" UNIQUE ("workflowId", name);


--
-- Name: data_table_column UQ_8082ec4890f892f0bc77473a123; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_table_column
    ADD CONSTRAINT "UQ_8082ec4890f892f0bc77473a123" UNIQUE ("dataTableId", name);


--
-- Name: data_table UQ_b23096ef747281ac944d28e8b0d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_table
    ADD CONSTRAINT "UQ_b23096ef747281ac944d28e8b0d" UNIQUE ("projectId", name);


--
-- Name: role_mapping_rule UQ_b33ac896ad3099fc8de36fdc1c4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_mapping_rule
    ADD CONSTRAINT "UQ_b33ac896ad3099fc8de36fdc1c4" UNIQUE (type, "order");


--
-- Name: user_favorites UQ_cf6ae658ead9ffc124723413c65; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT "UQ_cf6ae658ead9ffc124723413c65" UNIQUE ("userId", "resourceId", "resourceType");


--
-- Name: user UQ_e12875dfb3b1d92d7d7c5377e2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT "UQ_e12875dfb3b1d92d7d7c5377e2" UNIQUE (email);


--
-- Name: workflow_builder_session UQ_ec2aa73632932d485a1d5192ce1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_builder_session
    ADD CONSTRAINT "UQ_ec2aa73632932d485a1d5192ce1" UNIQUE ("workflowId", "userId");


--
-- Name: auth_identity auth_identity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_identity
    ADD CONSTRAINT auth_identity_pkey PRIMARY KEY ("providerId", "providerType");


--
-- Name: auth_provider_sync_history auth_provider_sync_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_provider_sync_history
    ADD CONSTRAINT auth_provider_sync_history_pkey PRIMARY KEY (id);


--
-- Name: credentials_entity credentials_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials_entity
    ADD CONSTRAINT credentials_entity_pkey PRIMARY KEY (id);


--
-- Name: event_destinations event_destinations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_destinations
    ADD CONSTRAINT event_destinations_pkey PRIMARY KEY (id);


--
-- Name: execution_data execution_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_data
    ADD CONSTRAINT execution_data_pkey PRIMARY KEY ("executionId");


--
-- Name: execution_entity pk_e3e63bbf986767844bbe1166d4e; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_entity
    ADD CONSTRAINT pk_e3e63bbf986767844bbe1166d4e PRIMARY KEY (id);


--
-- Name: workflows_tags pk_workflows_tags; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows_tags
    ADD CONSTRAINT pk_workflows_tags PRIMARY KEY ("workflowId", "tagId");


--
-- Name: tag_entity tag_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tag_entity
    ADD CONSTRAINT tag_entity_pkey PRIMARY KEY (id);


--
-- Name: variables variables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variables
    ADD CONSTRAINT variables_pkey PRIMARY KEY (id);


--
-- Name: workflow_entity workflow_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_entity
    ADD CONSTRAINT workflow_entity_pkey PRIMARY KEY (id);


--
-- Name: workflow_statistics workflow_statistics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_statistics
    ADD CONSTRAINT workflow_statistics_pkey PRIMARY KEY (id);


--
-- Name: IDX_02751202c9a2ad75f2d8e14f5e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_02751202c9a2ad75f2d8e14f5e" ON public.instance_ai_iteration_logs USING btree ("threadId", "taskKey", "createdAt");


--
-- Name: IDX_0468a9dc35597314e641d4722a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_0468a9dc35597314e641d4722a" ON public.agent_execution_threads USING btree ("agentId");


--
-- Name: IDX_069e791e428391a5569e7a96b2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_069e791e428391a5569e7a96b2" ON public.agents_memory_entry_cursors USING btree ("observationScopeId");


--
-- Name: IDX_070b5de842ece9ccdda0d9738b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_070b5de842ece9ccdda0d9738b" ON public.workflow_publish_history USING btree ("workflowId", "versionId");


--
-- Name: IDX_07cb1e4a302629c5fa5d74d2bb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_07cb1e4a302629c5fa5d74d2bb" ON public.agents_observations USING btree ("agentId", "observationScopeId", status);


--
-- Name: IDX_0babdf6e3b897a86fe4678355e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_0babdf6e3b897a86fe4678355e" ON public.instance_ai_pending_confirmations USING btree ("checkpointKey");


--
-- Name: IDX_0d5db648188d338df7fb2a8064; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_0d5db648188d338df7fb2a8064" ON public.instance_ai_observations USING btree ("observationScopeId", status, "createdAt", id);


--
-- Name: IDX_0e2f8bf92a7a9c88b89670f701; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_0e2f8bf92a7a9c88b89670f701" ON public.agent_execution_threads USING btree ("projectId");


--
-- Name: IDX_0edf1226b77ddc525eae493807; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_0edf1226b77ddc525eae493807" ON public.agents_memory_entries USING btree ("supersededBy");


--
-- Name: IDX_127ee1078ffa952bb37b511efa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_127ee1078ffa952bb37b511efa" ON public.agents_observations USING btree ("supersededBy");


--
-- Name: IDX_1443a75e59adbfb796071d6639; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_1443a75e59adbfb796071d6639" ON public.agents_memory_entries USING btree ("resourceId");


--
-- Name: IDX_14f68deffaf858465715995508; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_14f68deffaf858465715995508" ON public.folder USING btree ("projectId", id);


--
-- Name: IDX_16db3adb7b19df1ee55ff06b27; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_16db3adb7b19df1ee55ff06b27" ON public.instance_ai_mcp_registry_connections USING btree ("userId", "serverSlug", "credentialId");


--
-- Name: IDX_1d11050a381548c42c32cc25c4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_1d11050a381548c42c32cc25c4" ON public.user_favorites USING btree ("resourceType", "resourceId");


--
-- Name: IDX_1d8ab99d5861c9388d2dc1cf73; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_1d8ab99d5861c9388d2dc1cf73" ON public.insights_metadata USING btree ("workflowId");


--
-- Name: IDX_1dd5c393ad0517be3c31a7af83; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_1dd5c393ad0517be3c31a7af83" ON public.user_favorites USING btree ("userId");


--
-- Name: IDX_1e31657f5fe46816c34be7c1b4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_1e31657f5fe46816c34be7c1b4" ON public.workflow_history USING btree ("workflowId");


--
-- Name: IDX_1eeb64cb9d66a927988de759e6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_1eeb64cb9d66a927988de759e6" ON public.instance_ai_messages USING btree ("threadId");


--
-- Name: IDX_1ef35bac35d20bdae979d917a3; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_1ef35bac35d20bdae979d917a3" ON public.user_api_keys USING btree ("apiKey");


--
-- Name: IDX_2b23f3f24a70bebb990203b011; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_2b23f3f24a70bebb990203b011" ON public.instance_ai_checkpoints USING btree ("threadId");


--
-- Name: IDX_35a78869286c65d9330d02b88f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_35a78869286c65d9330d02b88f" ON public.role_mapping_rule_project USING btree ("projectId");


--
-- Name: IDX_39b07732e819fb561d74c38763; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_39b07732e819fb561d74c38763" ON public.ai_builder_temporary_workflow USING btree ("threadId");


--
-- Name: IDX_451d387a182fa8dd8002dfc3a7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_451d387a182fa8dd8002dfc3a7" ON public.agents_memory_entry_sources USING btree ("threadId");


--
-- Name: IDX_45dafc48fe2ce95eac30fc8ffd; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_45dafc48fe2ce95eac30fc8ffd" ON public.agent_files USING btree ("agentId", "createdAt");


--
-- Name: IDX_4c72ebdb265d1775bf61147af0; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_4c72ebdb265d1775bf61147af0" ON public.chat_hub_tools USING btree ("ownerId", name);


--
-- Name: IDX_4cfd8a70ebb0a5b0cf047dca3c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_4cfd8a70ebb0a5b0cf047dca3c" ON public.agents_observations USING btree ("observationScopeId");


--
-- Name: IDX_501e2d1701a10e24fb69ab5fc5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_501e2d1701a10e24fb69ab5fc5" ON public.agents_observations USING btree ("parentId");


--
-- Name: IDX_54fa1b94f34a409beafae567a4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_54fa1b94f34a409beafae567a4" ON public.agents_threads USING btree ("resourceId");


--
-- Name: IDX_56900edc3cfd16612e2ef2c6a8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_56900edc3cfd16612e2ef2c6a8" ON public.binary_data USING btree ("sourceType", "sourceId");


--
-- Name: IDX_5e31c210f896d539964bf99fe3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_5e31c210f896d539964bf99fe3" ON public.agent_checkpoints USING btree ("agentId");


--
-- Name: IDX_5ec8e8c8d3539f3696cf73b43b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_5ec8e8c8d3539f3696cf73b43b" ON public.credential_dependency USING btree ("credentialId");


--
-- Name: IDX_5f0643f6717905a05164090dde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_5f0643f6717905a05164090dde" ON public.project_relation USING btree ("userId");


--
-- Name: IDX_60b6a84299eeb3f671dfec7693; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_60b6a84299eeb3f671dfec7693" ON public.insights_by_period USING btree ("periodStart", type, "periodUnit", "metaId");


--
-- Name: IDX_61448d56d61802b5dfde5cdb00; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_61448d56d61802b5dfde5cdb00" ON public.project_relation USING btree ("projectId");


--
-- Name: IDX_62476b94b56d9dc7ed9ed75d3d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_62476b94b56d9dc7ed9ed75d3d" ON public.dynamic_credential_entry USING btree (subject_id);


--
-- Name: IDX_63d3c3a68b9cebf05f967f0b1c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_63d3c3a68b9cebf05f967f0b1c" ON public.agent_execution USING btree ("threadId", "createdAt");


--
-- Name: IDX_63d7bbae72c767cf162d459fcc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_63d7bbae72c767cf162d459fcc" ON public.user_api_keys USING btree ("userId", label);


--
-- Name: IDX_6b55089892e447c2f82e5ec60e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_6b55089892e447c2f82e5ec60e" ON public.agents_observation_locks USING btree ("observationScopeId");


--
-- Name: IDX_6edec973a6450990977bb854c3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_6edec973a6450990977bb854c3" ON public.dynamic_credential_user_entry USING btree ("resolverId");


--
-- Name: IDX_768189b506cc26c4fe878b87cb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_768189b506cc26c4fe878b87cb" ON public.instance_ai_checkpoints USING btree ("runId");


--
-- Name: IDX_76e212c6867fbaa06bf0decd6f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_76e212c6867fbaa06bf0decd6f" ON public.instance_ai_messages USING btree ("resourceId");


--
-- Name: IDX_87aa187d27ea67eafd16490515; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_87aa187d27ea67eafd16490515" ON public.agents_observation_cursors USING btree ("observationScopeId");


--
-- Name: IDX_87cd5a8da20304b089ea2f83fe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_87cd5a8da20304b089ea2f83fe" ON public.agent_history USING btree ("agentId");


--
-- Name: IDX_8e4b4774db42f1e6dda3452b2a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_8e4b4774db42f1e6dda3452b2a" ON public.test_case_execution USING btree ("testRunId");


--
-- Name: IDX_91ee85fa9619dd6776725e117b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_91ee85fa9619dd6776725e117b" ON public.credential_dependency USING btree ("dependencyType", "dependencyId");


--
-- Name: IDX_92f13cb6bc694227e069447f7b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_92f13cb6bc694227e069447f7b" ON public.instance_ai_observational_memory USING btree ("lookupKey");


--
-- Name: IDX_9594c0983cfee1c8ff49b05848; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_9594c0983cfee1c8ff49b05848" ON public.agents_memory_entry_locks USING btree ("resourceId");


--
-- Name: IDX_97f863fa83c4786f1956508496; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_97f863fa83c4786f1956508496" ON public.execution_annotations USING btree ("executionId");


--
-- Name: IDX_9c9ee9df586e60bb723234e499; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_9c9ee9df586e60bb723234e499" ON public.dynamic_credential_resolver USING btree (type);


--
-- Name: IDX_UniqueRoleDisplayName; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_UniqueRoleDisplayName" ON public.role USING btree ("displayName");


--
-- Name: IDX_a03e04e94bea8439dd166d4b52; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_a03e04e94bea8439dd166d4b52" ON public.agents_memory_entries USING btree ("agentId", "resourceId", "contentHash");


--
-- Name: IDX_a30d560207c4071d98aa03c179; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a30d560207c4071d98aa03c179" ON public.agents USING btree ("projectId");


--
-- Name: IDX_a353ac251315ef0af6ad3c9f0a; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_a353ac251315ef0af6ad3c9f0a" ON public.agents_memory_entry_sources USING btree ("memoryEntryId", "observationId", "evidenceHash");


--
-- Name: IDX_a3697779b366e131b2bbdae297; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a3697779b366e131b2bbdae297" ON public.execution_annotation_tags USING btree ("tagId");


--
-- Name: IDX_a36dc616fabc3f736bb82410a2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a36dc616fabc3f736bb82410a2" ON public.dynamic_credential_user_entry USING btree ("userId");


--
-- Name: IDX_a371ee6b8e0ebb5635f8baa46d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a371ee6b8e0ebb5635f8baa46d" ON public.instance_ai_workflow_snapshots USING btree ("workflowName", status);


--
-- Name: IDX_a48ce930c3bc7604894b8f0eaa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a48ce930c3bc7604894b8f0eaa" ON public.evaluation_collection USING btree ("workflowId");


--
-- Name: IDX_a4ff2d9b9628ea988fa9e7d0bf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a4ff2d9b9628ea988fa9e7d0bf" ON public.workflow_dependency USING btree ("workflowId");


--
-- Name: IDX_a680ac96aae02dc887bbaac512; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_a680ac96aae02dc887bbaac512" ON public.instance_ai_observational_memory USING btree (scope, "threadId", "resourceId");


--
-- Name: IDX_a80e0ee839a2f10ba4b86e1999; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a80e0ee839a2f10ba4b86e1999" ON public.instance_ai_observations USING btree ("supersededBy");


--
-- Name: IDX_ae51b54c4bb430cf92f48b623f; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_ae51b54c4bb430cf92f48b623f" ON public.annotation_tag_entity USING btree (name);


--
-- Name: IDX_aff2807b31eccbafe59d0474f0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_aff2807b31eccbafe59d0474f0" ON public.agents_memory_entries USING btree ("agentId", "resourceId", status, "createdAt", id);


--
-- Name: IDX_agent_execution_threads_taskVersionId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_agent_execution_threads_taskVersionId" ON public.agent_execution_threads USING btree ("taskVersionId");


--
-- Name: IDX_agents_messages_threadId_createdAt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_agents_messages_threadId_createdAt" ON public.agents_messages USING btree ("threadId", "createdAt");


--
-- Name: IDX_agents_projectId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_agents_projectId" ON public.agents USING btree ("projectId");


--
-- Name: IDX_ba67ee8dc311830a2eea89b6e9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_ba67ee8dc311830a2eea89b6e9" ON public.instance_ai_pending_confirmations USING btree ("threadId");


--
-- Name: IDX_bb66e404c35996b0d694617750; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_bb66e404c35996b0d694617750" ON public.role_mapping_rule USING btree (role);


--
-- Name: IDX_be9d0eca0b19fb93d4eb74b327; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_be9d0eca0b19fb93d4eb74b327" ON public.instance_ai_checkpoints USING btree ("resourceId");


--
-- Name: IDX_c1519757391996eb06064f0e7c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_c1519757391996eb06064f0e7c" ON public.execution_annotation_tags USING btree ("annotationId");


--
-- Name: IDX_cb7c15d22fd068a0806aa57fc0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_cb7c15d22fd068a0806aa57fc0" ON public.agents_memory_entry_sources USING btree ("observationId");


--
-- Name: IDX_cec8eea3bf49551482ccb4933e; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_cec8eea3bf49551482ccb4933e" ON public.execution_metadata USING btree ("executionId", key);


--
-- Name: IDX_chat_hub_messages_sessionId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_chat_hub_messages_sessionId" ON public.chat_hub_messages USING btree ("sessionId");


--
-- Name: IDX_chat_hub_sessions_owner_lastmsg_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_chat_hub_sessions_owner_lastmsg_id" ON public.chat_hub_sessions USING btree ("ownerId", "lastMessageAt" DESC, id);


--
-- Name: IDX_credential_dependency_credentialId_dependencyType_dependenc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_credential_dependency_credentialId_dependencyType_dependenc" ON public.credential_dependency USING btree ("credentialId", "dependencyType", "dependencyId");


--
-- Name: IDX_d3a2bc880e7a8626802e5474ad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d3a2bc880e7a8626802e5474ad" ON public.instance_ai_run_snapshots USING btree ("threadId", "createdAt");


--
-- Name: IDX_d61a12235d268a49af6a3c09c1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d61a12235d268a49af6a3c09c1" ON public.dynamic_credential_entry USING btree (resolver_id);


--
-- Name: IDX_d634a0c93fd7de68a87eab951b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d634a0c93fd7de68a87eab951b" ON public.evaluation_collection USING btree ("evaluationConfigId");


--
-- Name: IDX_d6870d3b6e4c185d33926f423c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d6870d3b6e4c185d33926f423c" ON public.test_run USING btree ("workflowId");


--
-- Name: IDX_d7a4aba7440449865e2b924377; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d7a4aba7440449865e2b924377" ON public.instance_ai_pending_confirmations USING btree ("expiresAt");


--
-- Name: IDX_d926c16c2ad9728cb9a81790c0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d926c16c2ad9728cb9a81790c0" ON public.instance_ai_run_snapshots USING btree ("threadId", "messageGroupId");


--
-- Name: IDX_daef2195a4a846eb70eed15e03; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_daef2195a4a846eb70eed15e03" ON public.instance_ai_observations USING btree ("parentId");


--
-- Name: IDX_deployment_key_data_encryption_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_deployment_key_data_encryption_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'data_encryption'::text));


--
-- Name: IDX_deployment_key_instance_id_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_deployment_key_instance_id_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'instance.id'::text));


--
-- Name: IDX_deployment_key_jwe_private_key_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_deployment_key_jwe_private_key_active" ON public.deployment_key USING btree (type, algorithm) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'jwe.private-key'::text));


--
-- Name: IDX_deployment_key_signing_binary_data_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_deployment_key_signing_binary_data_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'signing.binary_data'::text));


--
-- Name: IDX_deployment_key_signing_hmac_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_deployment_key_signing_hmac_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'signing.hmac'::text));


--
-- Name: IDX_deployment_key_signing_jwt_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_deployment_key_signing_jwt_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'signing.jwt'::text));


--
-- Name: IDX_df5fd25c8bbfd2b042602600d8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_df5fd25c8bbfd2b042602600d8" ON public.instance_ai_pending_confirmations USING btree ("userId");


--
-- Name: IDX_e48a201071ab85d9d09119d640; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_e48a201071ab85d9d09119d640" ON public.workflow_dependency USING btree ("dependencyKey");


--
-- Name: IDX_e7fe1cfda990c14a445937d0b9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_e7fe1cfda990c14a445937d0b9" ON public.workflow_dependency USING btree ("dependencyType");


--
-- Name: IDX_execution_entity_deduplicationKey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_execution_entity_deduplicationKey" ON public.execution_entity USING btree ("deduplicationKey") WHERE ("deduplicationKey" IS NOT NULL);


--
-- Name: IDX_execution_entity_deletedAt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_execution_entity_deletedAt" ON public.execution_entity USING btree ("deletedAt");


--
-- Name: IDX_f36dea4d38fe92e0e8f44d5a56; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_f36dea4d38fe92e0e8f44d5a56" ON public.instance_ai_threads USING btree ("resourceId");


--
-- Name: IDX_f45d0535a2ed59b6c2dd6da98a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_f45d0535a2ed59b6c2dd6da98a" ON public.agent_task_definition USING btree ("agentId");


--
-- Name: IDX_f9573af4ed653f13b0ba1f7b12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_f9573af4ed653f13b0ba1f7b12" ON public.agents_memory_entry_sources USING btree ("agentId", "threadId");


--
-- Name: IDX_fc7bf858660bfafd19181e8e35; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_fc7bf858660bfafd19181e8e35" ON public.agents_messages USING btree ("threadId", "createdAt");


--
-- Name: IDX_fd7542bb123074760285dc1bbf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_fd7542bb123074760285dc1bbf" ON public.evaluation_config USING btree ("workflowId");


--
-- Name: IDX_insights_raw_timestamp_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_insights_raw_timestamp_id" ON public.insights_raw USING btree ("timestamp", id);


--
-- Name: IDX_instance_ai_threads_projectId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_instance_ai_threads_projectId" ON public.instance_ai_threads USING btree ("projectId");


--
-- Name: IDX_role_scope_scopeSlug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_role_scope_scopeSlug" ON public.role_scope USING btree ("scopeSlug");


--
-- Name: IDX_secrets_provider_connection_providerKey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_secrets_provider_connection_providerKey" ON public.secrets_provider_connection USING btree ("providerKey");


--
-- Name: IDX_shared_workflow_projectId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_shared_workflow_projectId" ON public.shared_workflow USING btree ("projectId");


--
-- Name: IDX_test_run_collectionId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_test_run_collectionId" ON public.test_run USING btree ("collectionId");


--
-- Name: IDX_test_run_evaluationConfigId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_test_run_evaluationConfigId" ON public.test_run USING btree ("evaluationConfigId");


--
-- Name: IDX_workflow_dependency_publishedVersionId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_workflow_dependency_publishedVersionId" ON public.workflow_dependency USING btree ("publishedVersionId");


--
-- Name: IDX_workflow_entity_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_workflow_entity_name" ON public.workflow_entity USING btree (name);


--
-- Name: IDX_workflow_entity_sourceWorkflowId; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_workflow_entity_sourceWorkflowId" ON public.workflow_entity USING btree ("sourceWorkflowId") WHERE ("sourceWorkflowId" IS NOT NULL);


--
-- Name: IDX_workflow_publication_outbox_active_workflow_status; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_workflow_publication_outbox_active_workflow_status" ON public.workflow_publication_outbox USING btree ("workflowId", status) WHERE ((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('in_progress'::character varying)::text]));


--
-- Name: IDX_workflow_statistics_workflow_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_workflow_statistics_workflow_name" ON public.workflow_statistics USING btree ("workflowId", name);


--
-- Name: idx_07fde106c0b471d8cc80a64fc8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_07fde106c0b471d8cc80a64fc8 ON public.credentials_entity USING btree (type);


--
-- Name: idx_16f4436789e804e3e1c9eeb240; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_16f4436789e804e3e1c9eeb240 ON public.webhook_entity USING btree ("webhookId", method, "pathLength");


--
-- Name: idx_812eb05f7451ca757fb98444ce; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_812eb05f7451ca757fb98444ce ON public.tag_entity USING btree (name);


--
-- Name: idx_execution_entity_stopped_at_status_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execution_entity_stopped_at_status_deleted_at ON public.execution_entity USING btree ("stoppedAt", status, "deletedAt") WHERE (("stoppedAt" IS NOT NULL) AND ("deletedAt" IS NULL));


--
-- Name: idx_execution_entity_wait_till_status_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execution_entity_wait_till_status_deleted_at ON public.execution_entity USING btree ("waitTill", status, "deletedAt") WHERE (("waitTill" IS NOT NULL) AND ("deletedAt" IS NULL));


--
-- Name: idx_execution_entity_workflow_id_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execution_entity_workflow_id_started_at ON public.execution_entity USING btree ("workflowId", "startedAt") WHERE (("startedAt" IS NOT NULL) AND ("deletedAt" IS NULL));


--
-- Name: idx_workflows_tags_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_tags_workflow_id ON public.workflows_tags USING btree ("workflowId");


--
-- Name: pk_credentials_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pk_credentials_entity_id ON public.credentials_entity USING btree (id);


--
-- Name: pk_tag_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pk_tag_entity_id ON public.tag_entity USING btree (id);


--
-- Name: pk_workflow_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pk_workflow_entity_id ON public.workflow_entity USING btree (id);


--
-- Name: project_relation_role_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_relation_role_idx ON public.project_relation USING btree (role);


--
-- Name: project_relation_role_project_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_relation_role_project_idx ON public.project_relation USING btree ("projectId", role);


--
-- Name: user_role_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_role_idx ON public."user" USING btree ("roleSlug");


--
-- Name: variables_global_key_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX variables_global_key_unique ON public.variables USING btree (key) WHERE ("projectId" IS NULL);


--
-- Name: variables_project_key_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX variables_project_key_unique ON public.variables USING btree ("projectId", key) WHERE ("projectId" IS NOT NULL);


--
-- Name: workflow_entity workflow_version_increment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER workflow_version_increment BEFORE UPDATE ON public.workflow_entity FOR EACH ROW EXECUTE FUNCTION public.increment_workflow_version();


--
-- Name: workflow_builder_session FK_00290cdeee4d4d7db84709be936; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_builder_session
    ADD CONSTRAINT "FK_00290cdeee4d4d7db84709be936" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: agent_execution_threads FK_0468a9dc35597314e641d4722aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_execution_threads
    ADD CONSTRAINT "FK_0468a9dc35597314e641d4722aa" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entry_cursors FK_069e791e428391a5569e7a96b20; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_cursors
    ADD CONSTRAINT "FK_069e791e428391a5569e7a96b20" FOREIGN KEY ("observationScopeId") REFERENCES public.agents_threads(id) ON DELETE CASCADE;


--
-- Name: processed_data FK_06a69a7032c97a763c2c7599464; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_data
    ADD CONSTRAINT "FK_06a69a7032c97a763c2c7599464" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: workflow_entity FK_08d6c67b7f722b0039d9d5ed620; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_entity
    ADD CONSTRAINT "FK_08d6c67b7f722b0039d9d5ed620" FOREIGN KEY ("activeVersionId") REFERENCES public.workflow_history("versionId") ON DELETE RESTRICT;


--
-- Name: agents_observation_locks FK_093e44ae20f2518e97d83a95433; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observation_locks
    ADD CONSTRAINT "FK_093e44ae20f2518e97d83a95433" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: agents_messages FK_0a8057a61afabd2999608ffd0d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_messages
    ADD CONSTRAINT "FK_0a8057a61afabd2999608ffd0d9" FOREIGN KEY ("threadId") REFERENCES public.agents_threads(id) ON DELETE CASCADE;


--
-- Name: instance_ai_pending_confirmations FK_0babdf6e3b897a86fe4678355eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_pending_confirmations
    ADD CONSTRAINT "FK_0babdf6e3b897a86fe4678355eb" FOREIGN KEY ("checkpointKey") REFERENCES public.instance_ai_checkpoints(key) ON DELETE CASCADE;


--
-- Name: agents_memory_entry_locks FK_0ccf6d9ea6f44fa1c264fc2f795; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_locks
    ADD CONSTRAINT "FK_0ccf6d9ea6f44fa1c264fc2f795" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: agent_execution_threads FK_0e2f8bf92a7a9c88b89670f701c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_execution_threads
    ADD CONSTRAINT "FK_0e2f8bf92a7a9c88b89670f701c" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entries FK_0edf1226b77ddc525eae4938079; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entries
    ADD CONSTRAINT "FK_0edf1226b77ddc525eae4938079" FOREIGN KEY ("supersededBy") REFERENCES public.agents_memory_entries(id);


--
-- Name: instance_ai_observation_locks FK_103e2e5f454860b28ea05a82c74; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observation_locks
    ADD CONSTRAINT "FK_103e2e5f454860b28ea05a82c74" FOREIGN KEY ("observationScopeId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: agents_observations FK_127ee1078ffa952bb37b511efad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observations
    ADD CONSTRAINT "FK_127ee1078ffa952bb37b511efad" FOREIGN KEY ("supersededBy") REFERENCES public.agents_observations(id);


--
-- Name: agents_memory_entries FK_1443a75e59adbfb796071d66393; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entries
    ADD CONSTRAINT "FK_1443a75e59adbfb796071d66393" FOREIGN KEY ("resourceId") REFERENCES public.agents_resources(id) ON DELETE CASCADE;


--
-- Name: project_secrets_provider_access FK_18e5c27d2524b1638b292904e48; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_secrets_provider_access
    ADD CONSTRAINT "FK_18e5c27d2524b1638b292904e48" FOREIGN KEY ("secretsProviderConnectionId") REFERENCES public.secrets_provider_connection(id) ON DELETE CASCADE;


--
-- Name: agent_task_snapshot FK_1acedce6690392ef1611cca8b88; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_snapshot
    ADD CONSTRAINT "FK_1acedce6690392ef1611cca8b88" FOREIGN KEY ("versionId") REFERENCES public.agent_history("versionId") ON DELETE CASCADE;


--
-- Name: instance_ai_mcp_registry_connections FK_1d25707354d2012da256eb2ec0a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_mcp_registry_connections
    ADD CONSTRAINT "FK_1d25707354d2012da256eb2ec0a" FOREIGN KEY ("serverSlug") REFERENCES public.mcp_registry_server(slug) ON DELETE CASCADE;


--
-- Name: insights_metadata FK_1d8ab99d5861c9388d2dc1cf733; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_metadata
    ADD CONSTRAINT "FK_1d8ab99d5861c9388d2dc1cf733" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE SET NULL;


--
-- Name: user_favorites FK_1dd5c393ad0517be3c31a7af836; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_favorites
    ADD CONSTRAINT "FK_1dd5c393ad0517be3c31a7af836" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: workflow_history FK_1e31657f5fe46816c34be7c1b4b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_history
    ADD CONSTRAINT "FK_1e31657f5fe46816c34be7c1b4b" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: instance_ai_mcp_registry_connections FK_1e826120e7e53ebc4681f026de8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_mcp_registry_connections
    ADD CONSTRAINT "FK_1e826120e7e53ebc4681f026de8" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE CASCADE;


--
-- Name: instance_ai_messages FK_1eeb64cb9d66a927988de759e6e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_messages
    ADD CONSTRAINT "FK_1eeb64cb9d66a927988de759e6e" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: chat_hub_messages FK_1f4998c8a7dec9e00a9ab15550e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_1f4998c8a7dec9e00a9ab15550e" FOREIGN KEY ("revisionOfMessageId") REFERENCES public.chat_hub_messages(id) ON DELETE CASCADE;


--
-- Name: oauth_user_consents FK_21e6c3c2d78a097478fae6aaefa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "FK_21e6c3c2d78a097478fae6aaefa" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: insights_metadata FK_2375a1eda085adb16b24615b69c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_metadata
    ADD CONSTRAINT "FK_2375a1eda085adb16b24615b69c" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE SET NULL;


--
-- Name: chat_hub_messages FK_25c9736e7f769f3a005eef4b372; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_25c9736e7f769f3a005eef4b372" FOREIGN KEY ("retryOfMessageId") REFERENCES public.chat_hub_messages(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entries FK_28e981fb675e9b44ce02f0ec1dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entries
    ADD CONSTRAINT "FK_28e981fb675e9b44ce02f0ec1dd" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: instance_ai_checkpoints FK_2b23f3f24a70bebb990203b011e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_checkpoints
    ADD CONSTRAINT "FK_2b23f3f24a70bebb990203b011e" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: chat_hub_agent_tools FK_2b53d796b3dbae91b1a9553c048; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_agent_tools
    ADD CONSTRAINT "FK_2b53d796b3dbae91b1a9553c048" FOREIGN KEY ("agentId") REFERENCES public.chat_hub_agents(id) ON DELETE CASCADE;


--
-- Name: instance_ai_run_snapshots FK_2f63fa21d09d7918f347ddbdf70; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_run_snapshots
    ADD CONSTRAINT "FK_2f63fa21d09d7918f347ddbdf70" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: execution_metadata FK_31d0b4c93fb85ced26f6005cda3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_metadata
    ADD CONSTRAINT "FK_31d0b4c93fb85ced26f6005cda3" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE CASCADE;


--
-- Name: instance_ai_observational_memory FK_34018c303885cd37093458e6409; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observational_memory
    ADD CONSTRAINT "FK_34018c303885cd37093458e6409" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE SET NULL;


--
-- Name: role_mapping_rule_project FK_35a78869286c65d9330d02b88f5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_mapping_rule_project
    ADD CONSTRAINT "FK_35a78869286c65d9330d02b88f5" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: ai_builder_temporary_workflow FK_39b07732e819fb561d74c38763f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_builder_temporary_workflow
    ADD CONSTRAINT "FK_39b07732e819fb561d74c38763f" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: shared_credentials FK_416f66fc846c7c442970c094ccf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_credentials
    ADD CONSTRAINT "FK_416f66fc846c7c442970c094ccf" FOREIGN KEY ("credentialsId") REFERENCES public.credentials_entity(id) ON DELETE CASCADE;


--
-- Name: variables FK_42f6c766f9f9d2edcc15bdd6e9b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variables
    ADD CONSTRAINT "FK_42f6c766f9f9d2edcc15bdd6e9b" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: chat_hub_agent_tools FK_43e70f04c53344f82483d0570f6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_agent_tools
    ADD CONSTRAINT "FK_43e70f04c53344f82483d0570f6" FOREIGN KEY ("toolId") REFERENCES public.chat_hub_tools(id) ON DELETE CASCADE;


--
-- Name: chat_hub_agents FK_441ba2caba11e077ce3fbfa2cd8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_agents
    ADD CONSTRAINT "FK_441ba2caba11e077ce3fbfa2cd8" FOREIGN KEY ("ownerId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entry_sources FK_451d387a182fa8dd8002dfc3a77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_sources
    ADD CONSTRAINT "FK_451d387a182fa8dd8002dfc3a77" FOREIGN KEY ("threadId") REFERENCES public.agents_threads(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entry_sources FK_4706f6223313959b7437a2b48df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_sources
    ADD CONSTRAINT "FK_4706f6223313959b7437a2b48df" FOREIGN KEY ("memoryEntryId") REFERENCES public.agents_memory_entries(id) ON DELETE CASCADE;


--
-- Name: agents_observations FK_4cfd8a70ebb0a5b0cf047dca3cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observations
    ADD CONSTRAINT "FK_4cfd8a70ebb0a5b0cf047dca3cf" FOREIGN KEY ("observationScopeId") REFERENCES public.agents_threads(id) ON DELETE CASCADE;


--
-- Name: agents_observations FK_501e2d1701a10e24fb69ab5fc5f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observations
    ADD CONSTRAINT "FK_501e2d1701a10e24fb69ab5fc5f" FOREIGN KEY ("parentId") REFERENCES public.agents_observations(id);


--
-- Name: instance_ai_observation_cursors FK_5b6319b2e9a37c1064a72428f9a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observation_cursors
    ADD CONSTRAINT "FK_5b6319b2e9a37c1064a72428f9a" FOREIGN KEY ("observationScopeId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: workflow_published_version FK_5c76fb7ee939fe2530374d3f75a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_published_version
    ADD CONSTRAINT "FK_5c76fb7ee939fe2530374d3f75a" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE RESTRICT;


--
-- Name: agent_checkpoints FK_5e31c210f896d539964bf99fe32; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_checkpoints
    ADD CONSTRAINT "FK_5e31c210f896d539964bf99fe32" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: credential_dependency FK_5ec8e8c8d3539f3696cf73b43bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_dependency
    ADD CONSTRAINT "FK_5ec8e8c8d3539f3696cf73b43bf" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE CASCADE;


--
-- Name: project_relation FK_5f0643f6717905a05164090dde7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "FK_5f0643f6717905a05164090dde7" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: project_relation FK_61448d56d61802b5dfde5cdb002; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "FK_61448d56d61802b5dfde5cdb002" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: insights_by_period FK_6414cfed98daabbfdd61a1cfbc0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_by_period
    ADD CONSTRAINT "FK_6414cfed98daabbfdd61a1cfbc0" FOREIGN KEY ("metaId") REFERENCES public.insights_metadata("metaId") ON DELETE CASCADE;


--
-- Name: oauth_authorization_codes FK_64d965bd072ea24fb6da55468cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_authorization_codes
    ADD CONSTRAINT "FK_64d965bd072ea24fb6da55468cd" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: agents_observation_cursors FK_64e92819f4b413661ed6e2c3c3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observation_cursors
    ADD CONSTRAINT "FK_64e92819f4b413661ed6e2c3c3d" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: chat_hub_session_tools FK_6596a328affd8d4967ffb303eee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_session_tools
    ADD CONSTRAINT "FK_6596a328affd8d4967ffb303eee" FOREIGN KEY ("toolId") REFERENCES public.chat_hub_tools(id) ON DELETE CASCADE;


--
-- Name: chat_hub_messages FK_6afb260449dd7a9b85355d4e0c9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_6afb260449dd7a9b85355d4e0c9" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE SET NULL;


--
-- Name: agents_observation_locks FK_6b55089892e447c2f82e5ec60ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observation_locks
    ADD CONSTRAINT "FK_6b55089892e447c2f82e5ec60ed" FOREIGN KEY ("observationScopeId") REFERENCES public.agents_threads(id) ON DELETE CASCADE;


--
-- Name: insights_raw FK_6e2e33741adef2a7c5d66befa4e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insights_raw
    ADD CONSTRAINT "FK_6e2e33741adef2a7c5d66befa4e" FOREIGN KEY ("metaId") REFERENCES public.insights_metadata("metaId") ON DELETE CASCADE;


--
-- Name: workflow_publish_history FK_6eab5bd9eedabe9c54bd879fc40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_publish_history
    ADD CONSTRAINT "FK_6eab5bd9eedabe9c54bd879fc40" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: dynamic_credential_user_entry FK_6edec973a6450990977bb854c38; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_user_entry
    ADD CONSTRAINT "FK_6edec973a6450990977bb854c38" FOREIGN KEY ("resolverId") REFERENCES public.dynamic_credential_resolver(id) ON DELETE CASCADE;


--
-- Name: oauth_access_tokens FK_7234a36d8e49a1fa85095328845; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT "FK_7234a36d8e49a1fa85095328845" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: installed_nodes FK_73f857fc5dce682cef8a99c11dbddbc969618951; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installed_nodes
    ADD CONSTRAINT "FK_73f857fc5dce682cef8a99c11dbddbc969618951" FOREIGN KEY (package) REFERENCES public.installed_packages("packageName") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: agents_memory_entry_cursors FK_746780fd115e5e4352457a3c617; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_cursors
    ADD CONSTRAINT "FK_746780fd115e5e4352457a3c617" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: oauth_access_tokens FK_78b26968132b7e5e45b75876481; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT "FK_78b26968132b7e5e45b75876481" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: workflow_builder_session FK_7983c618db48f47bf5a4cc1e1e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_builder_session
    ADD CONSTRAINT "FK_7983c618db48f47bf5a4cc1e1e4" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: chat_hub_sessions FK_7bc13b4c7e6afbfaf9be326c189; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_7bc13b4c7e6afbfaf9be326c189" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE SET NULL;


--
-- Name: folder FK_804ea52f6729e3940498bd54d78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder
    ADD CONSTRAINT "FK_804ea52f6729e3940498bd54d78" FOREIGN KEY ("parentFolderId") REFERENCES public.folder(id) ON DELETE CASCADE;


--
-- Name: shared_credentials FK_812c2852270da1247756e77f5a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_credentials
    ADD CONSTRAINT "FK_812c2852270da1247756e77f5a4" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: ai_builder_temporary_workflow FK_85a87a1ba0f61999fe11dc56325; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_builder_temporary_workflow
    ADD CONSTRAINT "FK_85a87a1ba0f61999fe11dc56325" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: agent_history FK_8771675f44c58fb40e0feb9ee35; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_history
    ADD CONSTRAINT "FK_8771675f44c58fb40e0feb9ee35" FOREIGN KEY ("publishedById") REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: agents_observation_cursors FK_87aa187d27ea67eafd164905154; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observation_cursors
    ADD CONSTRAINT "FK_87aa187d27ea67eafd164905154" FOREIGN KEY ("observationScopeId") REFERENCES public.agents_threads(id) ON DELETE CASCADE;


--
-- Name: agent_history FK_87cd5a8da20304b089ea2f83fec; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_history
    ADD CONSTRAINT "FK_87cd5a8da20304b089ea2f83fec" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: instance_ai_mcp_registry_connections FK_8b42c08a531d76410980c639a5b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_mcp_registry_connections
    ADD CONSTRAINT "FK_8b42c08a531d76410980c639a5b" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: instance_ai_iteration_logs FK_8bfcc6c51fd3d69b1eae8aebd49; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_iteration_logs
    ADD CONSTRAINT "FK_8bfcc6c51fd3d69b1eae8aebd49" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: trusted_key FK_8c2938d746943dd8f608d23c891; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_key
    ADD CONSTRAINT "FK_8c2938d746943dd8f608d23c891" FOREIGN KEY ("sourceId") REFERENCES public.trusted_key_source(id) ON DELETE CASCADE;


--
-- Name: test_case_execution FK_8e4b4774db42f1e6dda3452b2af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_case_execution
    ADD CONSTRAINT "FK_8e4b4774db42f1e6dda3452b2af" FOREIGN KEY ("testRunId") REFERENCES public.test_run(id) ON DELETE CASCADE;


--
-- Name: data_table_column FK_930b6e8faaf88294cef23484160; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_table_column
    ADD CONSTRAINT "FK_930b6e8faaf88294cef23484160" FOREIGN KEY ("dataTableId") REFERENCES public.data_table(id) ON DELETE CASCADE;


--
-- Name: agents FK_940597dfe9753375309ce6aeea0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT "FK_940597dfe9753375309ce6aeea0" FOREIGN KEY ("activeVersionId") REFERENCES public.agent_history("versionId") ON DELETE SET NULL;


--
-- Name: dynamic_credential_user_entry FK_945ba70b342a066d1306b12ccd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_user_entry
    ADD CONSTRAINT "FK_945ba70b342a066d1306b12ccd2" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE CASCADE;


--
-- Name: folder_tag FK_94a60854e06f2897b2e0d39edba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_tag
    ADD CONSTRAINT "FK_94a60854e06f2897b2e0d39edba" FOREIGN KEY ("folderId") REFERENCES public.folder(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entry_locks FK_9594c0983cfee1c8ff49b05848b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_locks
    ADD CONSTRAINT "FK_9594c0983cfee1c8ff49b05848b" FOREIGN KEY ("resourceId") REFERENCES public.agents_resources(id) ON DELETE CASCADE;


--
-- Name: execution_annotations FK_97f863fa83c4786f19565084960; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_annotations
    ADD CONSTRAINT "FK_97f863fa83c4786f19565084960" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE CASCADE;


--
-- Name: chat_hub_agents FK_9c61ad497dcbae499c96a6a78ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_agents
    ADD CONSTRAINT "FK_9c61ad497dcbae499c96a6a78ba" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE SET NULL;


--
-- Name: chat_hub_sessions FK_9f9293d9f552496c40e0d1a8f80; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_9f9293d9f552496c40e0d1a8f80" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE SET NULL;


--
-- Name: agents FK_a30d560207c4071d98aa03c179c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT "FK_a30d560207c4071d98aa03c179c" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: execution_annotation_tags FK_a3697779b366e131b2bbdae2976; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_annotation_tags
    ADD CONSTRAINT "FK_a3697779b366e131b2bbdae2976" FOREIGN KEY ("tagId") REFERENCES public.annotation_tag_entity(id) ON DELETE CASCADE;


--
-- Name: dynamic_credential_user_entry FK_a36dc616fabc3f736bb82410a22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_user_entry
    ADD CONSTRAINT "FK_a36dc616fabc3f736bb82410a22" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: shared_workflow FK_a45ea5f27bcfdc21af9b4188560; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_workflow
    ADD CONSTRAINT "FK_a45ea5f27bcfdc21af9b4188560" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: evaluation_collection FK_a48ce930c3bc7604894b8f0eaad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_collection
    ADD CONSTRAINT "FK_a48ce930c3bc7604894b8f0eaad" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: workflow_dependency FK_a4ff2d9b9628ea988fa9e7d0bf8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_dependency
    ADD CONSTRAINT "FK_a4ff2d9b9628ea988fa9e7d0bf8" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: oauth_user_consents FK_a651acea2f6c97f8c4514935486; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "FK_a651acea2f6c97f8c4514935486" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_refresh_tokens FK_a699f3ed9fd0c1b19bc2608ac53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_refresh_tokens
    ADD CONSTRAINT "FK_a699f3ed9fd0c1b19bc2608ac53" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: dynamic_credential_entry FK_a6d1dd080958304a47a02952aab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_entry
    ADD CONSTRAINT "FK_a6d1dd080958304a47a02952aab" FOREIGN KEY (credential_id) REFERENCES public.credentials_entity(id) ON DELETE CASCADE;


--
-- Name: instance_ai_observations FK_a80e0ee839a2f10ba4b86e19998; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observations
    ADD CONSTRAINT "FK_a80e0ee839a2f10ba4b86e19998" FOREIGN KEY ("supersededBy") REFERENCES public.instance_ai_observations(id);


--
-- Name: folder FK_a8260b0b36939c6247f385b8221; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder
    ADD CONSTRAINT "FK_a8260b0b36939c6247f385b8221" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: oauth_authorization_codes FK_aa8d3560484944c19bdf79ffa16; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_authorization_codes
    ADD CONSTRAINT "FK_aa8d3560484944c19bdf79ffa16" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: agent_files FK_aca4514cb500494b64356c2e164; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_files
    ADD CONSTRAINT "FK_aca4514cb500494b64356c2e164" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: chat_hub_messages FK_acf8926098f063cdbbad8497fd1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_acf8926098f063cdbbad8497fd1" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE SET NULL;


--
-- Name: agent_execution FK_add2432fb6034cc18b6af299dce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_execution
    ADD CONSTRAINT "FK_add2432fb6034cc18b6af299dce" FOREIGN KEY ("threadId") REFERENCES public.agent_execution_threads(id) ON DELETE CASCADE;


--
-- Name: oauth_refresh_tokens FK_b388696ce4d8be7ffbe8d3e4b69; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_refresh_tokens
    ADD CONSTRAINT "FK_b388696ce4d8be7ffbe8d3e4b69" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: workflow_publish_history FK_b4cfbc7556d07f36ca177f5e473; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_publish_history
    ADD CONSTRAINT "FK_b4cfbc7556d07f36ca177f5e473" FOREIGN KEY ("versionId") REFERENCES public.workflow_history("versionId") ON DELETE SET NULL;


--
-- Name: agent_task_run_lock FK_b57a2862ae869aab24e54cefd48; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_run_lock
    ADD CONSTRAINT "FK_b57a2862ae869aab24e54cefd48" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: chat_hub_tools FK_b8030b47af9213f1fd15450fb7f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_tools
    ADD CONSTRAINT "FK_b8030b47af9213f1fd15450fb7f" FOREIGN KEY ("ownerId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: instance_ai_pending_confirmations FK_ba67ee8dc311830a2eea89b6e96; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_pending_confirmations
    ADD CONSTRAINT "FK_ba67ee8dc311830a2eea89b6e96" FOREIGN KEY ("threadId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: role_mapping_rule FK_bb66e404c35996b0d6946177501; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_mapping_rule
    ADD CONSTRAINT "FK_bb66e404c35996b0d6946177501" FOREIGN KEY (role) REFERENCES public.role(slug) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: project_secrets_provider_access FK_bd264b81209355b543878deedb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_secrets_provider_access
    ADD CONSTRAINT "FK_bd264b81209355b543878deedb1" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: workflow_publish_history FK_c01316f8c2d7101ec4fa9809267; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_publish_history
    ADD CONSTRAINT "FK_c01316f8c2d7101ec4fa9809267" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: execution_annotation_tags FK_c1519757391996eb06064f0e7c8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_annotation_tags
    ADD CONSTRAINT "FK_c1519757391996eb06064f0e7c8" FOREIGN KEY ("annotationId") REFERENCES public.execution_annotations(id) ON DELETE CASCADE;


--
-- Name: data_table FK_c2a794257dee48af7c9abf681de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_table
    ADD CONSTRAINT "FK_c2a794257dee48af7c9abf681de" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: agents_memory_entry_sources FK_c38e8a57a36b880e39a52ada2e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_sources
    ADD CONSTRAINT "FK_c38e8a57a36b880e39a52ada2e8" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: project_relation FK_c6b99592dc96b0d836d7a21db91; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "FK_c6b99592dc96b0d836d7a21db91" FOREIGN KEY (role) REFERENCES public.role(slug);


--
-- Name: agents_memory_entry_sources FK_cb7c15d22fd068a0806aa57fc03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_memory_entry_sources
    ADD CONSTRAINT "FK_cb7c15d22fd068a0806aa57fc03" FOREIGN KEY ("observationId") REFERENCES public.agents_observations(id) ON DELETE CASCADE;


--
-- Name: chat_hub_messages FK_chat_hub_messages_agentId; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_chat_hub_messages_agentId" FOREIGN KEY ("agentId") REFERENCES public.chat_hub_agents(id) ON DELETE SET NULL;


--
-- Name: chat_hub_sessions FK_chat_hub_sessions_agentId; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_chat_hub_sessions_agentId" FOREIGN KEY ("agentId") REFERENCES public.chat_hub_agents(id) ON DELETE SET NULL;


--
-- Name: agents_observations FK_d206432be97b7ed88d187479b1b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents_observations
    ADD CONSTRAINT "FK_d206432be97b7ed88d187479b1b" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: instance_ai_observations FK_d54fc84a6c8ac91b5e0db0378a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observations
    ADD CONSTRAINT "FK_d54fc84a6c8ac91b5e0db0378a4" FOREIGN KEY ("observationScopeId") REFERENCES public.instance_ai_threads(id) ON DELETE CASCADE;


--
-- Name: dynamic_credential_entry FK_d61a12235d268a49af6a3c09c13; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_credential_entry
    ADD CONSTRAINT "FK_d61a12235d268a49af6a3c09c13" FOREIGN KEY (resolver_id) REFERENCES public.dynamic_credential_resolver(id) ON DELETE CASCADE;


--
-- Name: evaluation_collection FK_d634a0c93fd7de68a87eab951b2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_collection
    ADD CONSTRAINT "FK_d634a0c93fd7de68a87eab951b2" FOREIGN KEY ("evaluationConfigId") REFERENCES public.evaluation_config(id) ON DELETE CASCADE;


--
-- Name: test_run FK_d6870d3b6e4c185d33926f423c8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run
    ADD CONSTRAINT "FK_d6870d3b6e4c185d33926f423c8" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: shared_workflow FK_daa206a04983d47d0a9c34649ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_workflow
    ADD CONSTRAINT "FK_daa206a04983d47d0a9c34649ce" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: instance_ai_observations FK_daef2195a4a846eb70eed15e039; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_observations
    ADD CONSTRAINT "FK_daef2195a4a846eb70eed15e039" FOREIGN KEY ("parentId") REFERENCES public.instance_ai_observations(id);


--
-- Name: folder_tag FK_dc88164176283de80af47621746; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_tag
    ADD CONSTRAINT "FK_dc88164176283de80af47621746" FOREIGN KEY ("tagId") REFERENCES public.tag_entity(id) ON DELETE CASCADE;


--
-- Name: role_mapping_rule_project FK_dd7ce4dfa09e95b36a626bd9de3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_mapping_rule_project
    ADD CONSTRAINT "FK_dd7ce4dfa09e95b36a626bd9de3" FOREIGN KEY ("roleMappingRuleId") REFERENCES public.role_mapping_rule(id) ON DELETE CASCADE;


--
-- Name: workflow_published_version FK_df3428a541b802d6a63ac56e330; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_published_version
    ADD CONSTRAINT "FK_df3428a541b802d6a63ac56e330" FOREIGN KEY ("publishedVersionId") REFERENCES public.workflow_history("versionId") ON DELETE RESTRICT;


--
-- Name: instance_ai_pending_confirmations FK_df5fd25c8bbfd2b042602600d8e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_pending_confirmations
    ADD CONSTRAINT "FK_df5fd25c8bbfd2b042602600d8e" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: user_api_keys FK_e131705cbbc8fb589889b02d457; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_keys
    ADD CONSTRAINT "FK_e131705cbbc8fb589889b02d457" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: chat_hub_messages FK_e22538eb50a71a17954cd7e076c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_e22538eb50a71a17954cd7e076c" FOREIGN KEY ("sessionId") REFERENCES public.chat_hub_sessions(id) ON DELETE CASCADE;


--
-- Name: test_case_execution FK_e48965fac35d0f5b9e7f51d8c44; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_case_execution
    ADD CONSTRAINT "FK_e48965fac35d0f5b9e7f51d8c44" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE SET NULL;


--
-- Name: chat_hub_messages FK_e5d1fa722c5a8d38ac204746662; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_e5d1fa722c5a8d38ac204746662" FOREIGN KEY ("previousMessageId") REFERENCES public.chat_hub_messages(id) ON DELETE CASCADE;


--
-- Name: chat_hub_session_tools FK_e649bf1295f4ed8d4299ed290f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_session_tools
    ADD CONSTRAINT "FK_e649bf1295f4ed8d4299ed290f9" FOREIGN KEY ("sessionId") REFERENCES public.chat_hub_sessions(id) ON DELETE CASCADE;


--
-- Name: chat_hub_sessions FK_e9ecf8ede7d989fcd18790fe36a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_e9ecf8ede7d989fcd18790fe36a" FOREIGN KEY ("ownerId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: user FK_eaea92ee7bfb9c1b6cd01505d56; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT "FK_eaea92ee7bfb9c1b6cd01505d56" FOREIGN KEY ("roleSlug") REFERENCES public.role(slug);


--
-- Name: agent_execution_threads FK_f00b52d74fe11838e1fe086deea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_execution_threads
    ADD CONSTRAINT "FK_f00b52d74fe11838e1fe086deea" FOREIGN KEY ("taskVersionId") REFERENCES public.agent_history("versionId") ON DELETE SET NULL;


--
-- Name: evaluation_collection FK_f4561f38b5a22a4f090d5cd3eae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_collection
    ADD CONSTRAINT "FK_f4561f38b5a22a4f090d5cd3eae" FOREIGN KEY ("createdById") REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: agent_task_definition FK_f45d0535a2ed59b6c2dd6da98a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_definition
    ADD CONSTRAINT "FK_f45d0535a2ed59b6c2dd6da98a0" FOREIGN KEY ("agentId") REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: evaluation_config FK_fd7542bb123074760285dc1bbf3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_config
    ADD CONSTRAINT "FK_fd7542bb123074760285dc1bbf3" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: instance_ai_threads FK_instance_ai_threads_projectId; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_ai_threads
    ADD CONSTRAINT "FK_instance_ai_threads_projectId" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: role_scope FK_role; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_scope
    ADD CONSTRAINT "FK_role" FOREIGN KEY ("roleSlug") REFERENCES public.role(slug) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: role_scope FK_scope; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_scope
    ADD CONSTRAINT "FK_scope" FOREIGN KEY ("scopeSlug") REFERENCES public.scope(slug) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: test_run FK_test_run_collection_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run
    ADD CONSTRAINT "FK_test_run_collection_id" FOREIGN KEY ("collectionId") REFERENCES public.evaluation_collection(id) ON DELETE SET NULL;


--
-- Name: test_run FK_test_run_evaluation_config_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run
    ADD CONSTRAINT "FK_test_run_evaluation_config_id" FOREIGN KEY ("evaluationConfigId") REFERENCES public.evaluation_config(id) ON DELETE SET NULL;


--
-- Name: auth_identity auth_identity_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_identity
    ADD CONSTRAINT "auth_identity_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."user"(id);


--
-- Name: credentials_entity credentials_entity_resolverId_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials_entity
    ADD CONSTRAINT "credentials_entity_resolverId_foreign" FOREIGN KEY ("resolverId") REFERENCES public.dynamic_credential_resolver(id) ON DELETE SET NULL;


--
-- Name: execution_data execution_data_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_data
    ADD CONSTRAINT execution_data_fk FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE CASCADE;


--
-- Name: execution_entity fk_execution_entity_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_entity
    ADD CONSTRAINT fk_execution_entity_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: webhook_entity fk_webhook_entity_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_entity
    ADD CONSTRAINT fk_webhook_entity_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: workflow_entity fk_workflow_parent_folder; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_entity
    ADD CONSTRAINT fk_workflow_parent_folder FOREIGN KEY ("parentFolderId") REFERENCES public.folder(id) ON DELETE CASCADE;


--
-- Name: workflows_tags fk_workflows_tags_tag_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows_tags
    ADD CONSTRAINT fk_workflows_tags_tag_id FOREIGN KEY ("tagId") REFERENCES public.tag_entity(id) ON DELETE CASCADE;


--
-- Name: workflows_tags fk_workflows_tags_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows_tags
    ADD CONSTRAINT fk_workflows_tags_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- Name: project projects_creatorId_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT "projects_creatorId_foreign" FOREIGN KEY ("creatorId") REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict maCD2TdT5Jf9wMncr685mrkZqsv9DR5979dhoJhljqPPScTrboHHOoeWIfJ7ljR

