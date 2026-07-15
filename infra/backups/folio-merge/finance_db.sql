--
-- PostgreSQL database dump
--

\restrict aBeKTxuxrgm3rmjmAREirHnm6L5hh84eCSHGiUcSEj3PfLsjOPbWDJeDTuUvuLA

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
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: perm; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA perm;


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: touch_updated_at(); Type: FUNCTION; Schema: perm; Owner: -
--

CREATE FUNCTION perm.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;


--
-- Name: ai_decrypt(bytea, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_decrypt(cipher bytea, key text) RETURNS text
    LANGUAGE sql
    AS $$
  SELECT pgp_sym_decrypt(cipher, key)
$$;


--
-- Name: ai_encrypt(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ai_encrypt(plain text, key text) RETURNS bytea
    LANGUAGE sql
    AS $$
  SELECT pgp_sym_encrypt(plain, key)
$$;


--
-- Name: backfill_exec_snapshot(date, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_exec_snapshot(target_date date, cash_val numeric, mtd_val numeric) RETURNS void
    LANGUAGE sql
    AS $$
  INSERT INTO exec_snapshots (
    snapshot_date,
    kpis,
    dept_budgets,
    stuck_count
  ) VALUES (
    target_date,
    jsonb_build_object(
      'cash', jsonb_build_object(
        'totalCash',               cash_val,
        'outstandingLiabilities',  0,
        'mtdExpenses',             mtd_val,
        'netIncome',               0
      ),
      'kpis',       jsonb_build_object('mtdExpenses', mtd_val),
      'cashTrend',  jsonb_build_array(cash_val),
      'mtdTrend',   jsonb_build_array(mtd_val)
    ),
    '[]'::jsonb,
    0
  )
  ON CONFLICT (snapshot_date) DO NOTHING;
$$;


--
-- Name: domain_events_fanout_notifications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.domain_events_fanout_notifications() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_owner        INT;
  v_actor        INT;
  v_supervisor   INT;
  v_uid          INT;
  v_payload      JSONB;
  v_recipients   INT[] := '{}';
  v_domain_id    TEXT;
  v_ref_type     TEXT := NEW.ref_type;
  v_ref_id       BIGINT := NEW.ref_id;
  v_scope_kind   TEXT;
  v_actor_dept   TEXT;
BEGIN
  -- NO_FANOUT filter (mirrors NO_FANOUT_TYPES in recipients.ts:11)
  IF NEW.type = 'policy.updated' THEN
    RETURN NEW;
  END IF;

  -- 1. Resolve ref owner (mirrors lookupRefOwner in recipients.ts:166-190)
  v_owner   := NULL;
  IF v_ref_type = 'expense' AND v_ref_id IS NOT NULL THEN
    SELECT submitter_id  INTO v_owner FROM expenses        WHERE id = v_ref_id;
  ELSIF v_ref_type = 'pr' AND v_ref_id IS NOT NULL THEN
    SELECT requester_id  INTO v_owner FROM purchase_requisitions WHERE id = v_ref_id;
  ELSIF v_ref_type = 'po' AND v_ref_id IS NOT NULL THEN
    SELECT pr.requester_id INTO v_owner
      FROM purchase_orders po JOIN purchase_requisitions pr ON pr.id = po.pr_id
     WHERE po.id = v_ref_id;
  END IF;
  v_actor := NEW.actor_id;

  -- 2. Owner + actor + supervisor (mirrors computeRecipients in recipients.ts:38-69)
  IF NEW.type LIKE 'ceo.override%' THEN
    IF v_owner IS NOT NULL THEN
      v_recipients := array_append(v_recipients, v_owner);
    END IF;
  ELSIF NEW.type LIKE ANY(ARRAY['expense.%','pr.%','po.%']) THEN
    IF v_owner IS NOT NULL THEN
      v_recipients := array_append(v_recipients, v_owner);
    END IF;
    IF v_actor IS NOT NULL AND v_actor <> v_owner THEN
      v_recipients := array_append(v_recipients, v_actor);
    END IF;
    IF v_owner IS NOT NULL THEN
      SELECT reports_to_user_id INTO v_supervisor FROM users WHERE id = v_owner;
      IF v_supervisor IS NOT NULL AND v_supervisor <> v_owner THEN
        v_recipients := array_append(v_recipients, v_supervisor);
      END IF;
    END IF;
  ELSE
    IF v_actor IS NOT NULL THEN
      v_recipients := array_append(v_recipients, v_actor);
    END IF;
  END IF;

  -- 3. Domain-scope expansion (mirrors mapEventToDomain + expandByDomainScope)
  v_domain_id := CASE
    WHEN v_ref_type = 'expense'    THEN 'expenses'
    WHEN v_ref_type = 'pr'         THEN 'pr'
    WHEN v_ref_type = 'po'         THEN 'po'
    WHEN v_ref_type = 'slip'       THEN 'slips'
    WHEN v_ref_type = 'user'       THEN 'users'
    WHEN v_ref_type = 'department' THEN 'departments'
    WHEN v_ref_type = 'audit'      THEN 'audit'
    WHEN v_ref_type = 'ai'         THEN 'ai_settings'
    WHEN v_ref_type = 'notification' THEN 'notifications'
    WHEN NEW.type LIKE 'expense.%'    THEN 'expenses'
    WHEN NEW.type LIKE 'pr.%'        THEN 'pr'
    WHEN NEW.type LIKE 'po.%'        THEN 'po'
    WHEN NEW.type LIKE 'slip.%'      THEN 'slips'
    WHEN NEW.type LIKE 'user.%'      THEN 'users'
    WHEN NEW.type LIKE 'audit.%'     THEN 'audit'
    WHEN NEW.type LIKE 'ai.%'        THEN 'ai_settings'
    WHEN NEW.type LIKE ANY(ARRAY['notification.%','notif.%']) THEN 'notifications'
    ELSE NULL
  END;

  -- Resolve anchor dept (mirrors anchorDept in recipients.ts:96-111)
  v_actor_dept := NULL;
  IF v_owner IS NOT NULL THEN
    SELECT dept_group_id INTO v_actor_dept FROM users WHERE id = v_owner;
  END IF;

  IF v_domain_id IS NOT NULL THEN
    FOR v_uid IN
      SELECT DISTINCT u.id
        FROM rbac.domain_scope ds
        JOIN rbac.roles r  ON r.id = ds.role_id
        JOIN users u       ON u.rbac_role_id = r.id
                           AND u.is_active IS NOT FALSE
       WHERE ds.domain_id = v_domain_id
         AND COALESCE(ds.scope_kind, r.scope_kind) NOT IN ('deny','self')
    LOOP
      v_recipients := array_append(v_recipients, v_uid);
    END LOOP;
  END IF;

  -- Dedupe (mirrors the Set in recipients.ts:40)
  SELECT COALESCE(array_agg(DISTINCT u ORDER BY u), '{}')
    INTO v_recipients FROM unnest(v_recipients) u WHERE u IS NOT NULL;

  IF array_length(v_recipients, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  -- 4. Build enriched payload + bulk insert
  v_payload := COALESCE(NEW.payload, '{}'::jsonb) || jsonb_build_object(
    'actorId',   NEW.actor_id,
    'actorName', (SELECT fullname FROM users WHERE id = NEW.actor_id),
    'severity',  NEW.severity
  );

  INSERT INTO notifications (user_id, type, target_type, target_id, payload_json, created_at)
  SELECT u, NEW.type, v_ref_type, v_ref_id, v_payload, NEW.created_at
    FROM unnest(v_recipients) u;

  RETURN NEW;
END $$;


--
-- Name: get_ar_aging_buckets(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_ar_aging_buckets() RETURNS TABLE(bucket text, days_from integer, days_to integer, amount_thb numeric, so_count bigint)
    LANGUAGE sql STABLE
    AS $$
  SELECT
    bucket,
    days_from,
    days_to,
    amount_thb,
    so_count
  FROM (
    SELECT
      CASE
        WHEN days_overdue BETWEEN 0 AND 30  THEN '0-30'
        WHEN days_overdue BETWEEN 31 AND 60 THEN '31-60'
        WHEN days_overdue BETWEEN 61 AND 90 THEN '61-90'
        ELSE '90+'
      END                                                AS bucket,
      CASE
        WHEN days_overdue BETWEEN 0  AND 30 THEN 0
        WHEN days_overdue BETWEEN 31 AND 60 THEN 31
        WHEN days_overdue BETWEEN 61 AND 90 THEN 61
        ELSE 90
      END                                                AS days_from,
      CASE
        WHEN days_overdue BETWEEN 0  AND 30 THEN 30
        WHEN days_overdue BETWEEN 31 AND 60 THEN 60
        WHEN days_overdue BETWEEN 61 AND 90 THEN 90
        ELSE 9999
      END                                                AS days_to,
      SUM(total_amount)::numeric(14,2)                   AS amount_thb,
      COUNT(*)::bigint                                   AS so_count
    FROM (
      SELECT
        so.id,
        so.total_amount,
        GREATEST(0, (CURRENT_DATE - so.due_date)::int) AS days_overdue
      FROM sales_orders so
      WHERE so.status IN ('so_invoiced', 'so_credit_check')
        AND so.due_date IS NOT NULL
        AND so.due_date <= CURRENT_DATE
    ) aged
    GROUP BY 1, 2, 3
  ) b
  ORDER BY days_from;
$$;


--
-- Name: get_cockpit_projection(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cockpit_projection(days_ahead integer DEFAULT 90) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
WITH series AS (
  SELECT
    snapshot_date                                         AS d,
    (kpis->'cash'->>'totalCash')::numeric                 AS cash,
    (kpis->'kpis'->>'mtdExpenses')::numeric               AS mtd,
    EXTRACT(EPOCH FROM snapshot_date)::numeric / 86400    AS x
  FROM exec_snapshots
),
regs AS (
  SELECT
    COALESCE(regr_slope    (cash, x), 0)::numeric AS cash_slope,
    COALESCE(regr_intercept(cash, x), 0)::numeric AS cash_intercept,
    COALESCE(regr_r2       (cash, x), 0)::numeric AS cash_r2,
    COALESCE(regr_slope    (mtd,  x), 0)::numeric AS mtd_slope,
    COALESCE(regr_intercept(mtd,  x), 0)::numeric AS mtd_intercept,
    COALESCE(regr_r2       (mtd,  x), 0)::numeric AS mtd_r2
  FROM series
),
proj AS (
  SELECT
    gs::int                                                       AS offset_days,
    (CURRENT_DATE + gs)::date                                     AS pd,
    EXTRACT(EPOCH FROM (CURRENT_DATE + gs)::date)::numeric / 86400 AS px,
    r.cash_slope, r.cash_intercept, r.mtd_slope, r.mtd_intercept
  FROM generate_series(1, days_ahead) gs
  CROSS JOIN regs r
)
SELECT jsonb_build_object(
  'historical', COALESCE(
    (SELECT jsonb_agg(
       jsonb_build_object('date', d::text, 'cash', cash, 'mtd', mtd)
       ORDER BY d)
     FROM series),
    '[]'::jsonb),
  'regression', jsonb_build_object(
    'cash', jsonb_build_object(
      'slope',     cash_slope,
      'intercept', cash_intercept,
      'r2',        cash_r2),
    'mtd',  jsonb_build_object(
      'slope',     mtd_slope,
      'intercept', mtd_intercept,
      'r2',        mtd_r2)
  ),
  'projection', COALESCE(
    (SELECT jsonb_agg(
       jsonb_build_object(
         'date',           pd::text,
         'cashProjected',  ROUND(cash_slope * px + cash_intercept, 2),
         'mtdProjected',   ROUND(mtd_slope  * px + mtd_intercept,  2),
         'isProjected',    true)
       ORDER BY offset_days)
     FROM proj),
    '[]'::jsonb),
  'summary', jsonb_build_object(
    'currentCash',     COALESCE((SELECT cash FROM series ORDER BY d DESC LIMIT 1), 0),
    'currentMtd',      COALESCE((SELECT mtd  FROM series ORDER BY d DESC LIMIT 1), 0),
    'projectedCash30', ROUND(cash_slope * (EXTRACT(EPOCH FROM (CURRENT_DATE + 30)::date)::numeric / 86400) + cash_intercept, 2),
    'projectedCash60', ROUND(cash_slope * (EXTRACT(EPOCH FROM (CURRENT_DATE + 60)::date)::numeric / 86400) + cash_intercept, 2),
    'projectedCash90', ROUND(cash_slope * (EXTRACT(EPOCH FROM (CURRENT_DATE + 90)::date)::numeric / 86400) + cash_intercept, 2),
    'monthlyBurn',     ROUND(cash_slope * 30, 2),
    'daysToZero',      CASE
                         WHEN cash_slope < 0
                           THEN ROUND(
                             ABS(
                               (0 - COALESCE((SELECT cash FROM series ORDER BY d DESC LIMIT 1), 0))::numeric
                               / cash_slope
                             )
                           )::int
                         ELSE NULL
                       END,
    'trend', CASE
               WHEN cash_slope < -1 THEN 'down'
               WHEN cash_slope >  1 THEN 'up'
               ELSE 'flat'
             END,
    'r2', cash_r2
  )
) FROM regs;
$$;


--
-- Name: get_dept_budget_status(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_dept_budget_status(p_fiscal_year integer, p_month integer) RETURNS TABLE(dept_id text, dept_name text, monthly_budget numeric, mtd_spend numeric, pct_used numeric, is_over_threshold boolean)
    LANGUAGE sql STABLE
    AS $_$
  WITH dept_users AS (
    SELECT DISTINCT regexp_replace(permission_id, '^user:dept:([^:]+)::allow$', '\1') AS dept_id,
           up.user_id
      FROM perm.user_permissions up
     WHERE permission_id LIKE 'user:dept:%::allow'
       AND revoked_at IS NULL
  ),
  depts AS (
    SELECT d.dept_id,
           COALESCE(MAX(r.monthly_budget), 0)::numeric AS monthly_budget,
           COALESCE(MAX(r.display_name), initcap(replace(d.dept_id, '-', ' '))) AS display_name
      FROM (SELECT DISTINCT dept_id FROM dept_users) d
      LEFT JOIN perm.roles r ON r.id = 'dept-' || d.dept_id
     GROUP BY d.dept_id
  )
  SELECT d.dept_id,
         d.display_name,
         d.monthly_budget,
         COALESCE(SUM(e.total_amount) FILTER (
           WHERE EXTRACT(YEAR  FROM e.created_at) = p_fiscal_year
             AND EXTRACT(MONTH FROM e.created_at) = p_month
             AND e.status NOT IN ('rejected','draft')
         ), 0)::numeric AS mtd_spend,
         CASE
           WHEN d.monthly_budget > 0
             THEN ROUND((COALESCE(SUM(e.total_amount) FILTER (
               WHERE EXTRACT(YEAR  FROM e.created_at) = p_fiscal_year
                 AND EXTRACT(MONTH FROM e.created_at) = p_month
                 AND e.status NOT IN ('rejected','draft')
             ), 0) / d.monthly_budget * 100)::numeric, 1)
           ELSE 0
         END AS pct_used,
         CASE
           WHEN d.monthly_budget > 0
             THEN COALESCE(SUM(e.total_amount) FILTER (
               WHERE EXTRACT(YEAR  FROM e.created_at) = p_fiscal_year
                 AND EXTRACT(MONTH FROM e.created_at) = p_month
                 AND e.status NOT IN ('rejected','draft')
             ), 0) > (d.monthly_budget * 0.9)
           ELSE false
         END AS is_over_threshold
    FROM depts d
    LEFT JOIN dept_users du ON du.dept_id = d.dept_id
    LEFT JOIN expenses e ON e.submitter_id = du.user_id
   GROUP BY d.dept_id, d.display_name, d.monthly_budget
   ORDER BY d.display_name;
$_$;


--
-- Name: next_purchase_order_number(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_purchase_order_number(p_year integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE n INT;
BEGIN
  SELECT COALESCE(MAX(
    CAST(regexp_replace(po_number, '^PO-'||p_year||'-', '') AS INT)
  ), 0) + 1 INTO n
  FROM purchase_orders
  WHERE po_number LIKE 'PO-'||p_year||'-%';
  RETURN 'PO-'||p_year||'-'||lpad(n::text, 6, '0');
END $$;


--
-- Name: next_sales_order_number(smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_sales_order_number(p_fiscal_year smallint) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  seq_name text := 'sales_orders_fy_' || p_fiscal_year || '_seq';
  next_n   int;
  result   text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = seq_name) THEN
    EXECUTE 'CREATE SEQUENCE ' || seq_name || ' START 1 INCREMENT 1 NO CYCLE';
  END IF;
  EXECUTE 'SELECT nextval(' || quote_literal(seq_name) || ')' INTO next_n;
  result := 'SO-' || p_fiscal_year::text || '-' || lpad(next_n::text, 6, '0');
  RETURN result;
END
$$;


--
-- Name: next_waybill_number(smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_waybill_number(p_fiscal_year smallint) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  seq_name text := 'waybills_fy_' || p_fiscal_year || '_seq';
  next_n   int;
  result   text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = seq_name) THEN
    EXECUTE 'CREATE SEQUENCE ' || seq_name || ' START 1 INCREMENT 1 NO CYCLE';
  END IF;
  EXECUTE 'SELECT nextval(' || quote_literal(seq_name) || ')' INTO next_n;
  result := 'WB-' || p_fiscal_year::text || '-' || lpad(next_n::text, 6, '0');
  RETURN result;
END
$$;


--
-- Name: slips_check_exactly_one_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.slips_check_exactly_one_parent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  current_row   slips%ROWTYPE;
  parent_count  INT;
  bad_cols      TEXT;
BEGIN
  SELECT * INTO current_row FROM slips WHERE id = NEW.id;

  -- pending slips may have zero parents — parent is assigned at confirm-time
  IF current_row.status = 'pending' THEN
    RETURN NEW;
  END IF;

  parent_count := (CASE WHEN current_row.expense_id IS NOT NULL THEN 1 ELSE 0 END) +
                  (CASE WHEN current_row.pr_id      IS NOT NULL THEN 1 ELSE 0 END) +
                  (CASE WHEN current_row.po_id      IS NOT NULL THEN 1 ELSE 0 END);
  IF parent_count <> 1 THEN
    bad_cols := concat_ws(',',
      CASE WHEN current_row.expense_id IS NOT NULL THEN 'expense_id' END,
      CASE WHEN current_row.pr_id      IS NOT NULL THEN 'pr_id'      END,
      CASE WHEN current_row.po_id      IS NOT NULL THEN 'po_id'      END);
    RAISE EXCEPTION 'slips_exactly_one_parent: expected exactly one parent, got % (set: %)',
      parent_count, COALESCE(bad_cols, '(none)')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessions (
    id text NOT NULL,
    user_id integer NOT NULL,
    impersonator_user_id integer,
    role text NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_ip inet,
    last_seen_ua text,
    locale text DEFAULT 'th'::text NOT NULL,
    CONSTRAINT sessions_locale_check CHECK ((locale = ANY (ARRAY['th'::text, 'de'::text])))
);


--
-- Name: user_permissions; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.user_permissions (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    permission_id text NOT NULL,
    granted_by text NOT NULL,
    reason text,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    revoked_by text,
    starts_at timestamp with time zone DEFAULT now() NOT NULL,
    ends_at timestamp with time zone,
    CONSTRAINT perm_user_perm_end_after_start CHECK (((ends_at IS NULL) OR (ends_at > starts_at)))
);


--
-- Name: active_user_permissions; Type: VIEW; Schema: perm; Owner: -
--

CREATE VIEW perm.active_user_permissions AS
 SELECT id,
    user_id,
    permission_id,
    granted_by,
    reason,
    granted_at,
    revoked_at,
    revoked_by,
    starts_at,
    ends_at
   FROM perm.user_permissions
  WHERE ((revoked_at IS NULL) AND ((ends_at IS NULL) OR (ends_at > statement_timestamp())));


--
-- Name: audit; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.audit (
    id bigint NOT NULL,
    kind text NOT NULL,
    actor text DEFAULT 'system'::text NOT NULL,
    target jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_id_seq; Type: SEQUENCE; Schema: perm; Owner: -
--

CREATE SEQUENCE perm.audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_id_seq; Type: SEQUENCE OWNED BY; Schema: perm; Owner: -
--

ALTER SEQUENCE perm.audit_id_seq OWNED BY perm.audit.id;


--
-- Name: permissions; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.permissions (
    id text NOT NULL,
    description text
);


--
-- Name: policies; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.policies (
    id text NOT NULL,
    name text NOT NULL,
    ast jsonb NOT NULL,
    description text,
    enabled boolean DEFAULT true NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: policy_decisions; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.policy_decisions (
    id bigint NOT NULL,
    actor_id integer,
    policy_id text,
    surface text NOT NULL,
    target text,
    decision text NOT NULL,
    reasons jsonb,
    resource jsonb,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: policy_decisions_id_seq; Type: SEQUENCE; Schema: perm; Owner: -
--

CREATE SEQUENCE perm.policy_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: policy_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: perm; Owner: -
--

ALTER SEQUENCE perm.policy_decisions_id_seq OWNED BY perm.policy_decisions.id;


--
-- Name: role_permissions; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.role_permissions (
    role_id text NOT NULL,
    permission_id text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_by text DEFAULT 'system'::text NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.roles (
    id text NOT NULL,
    display_name text NOT NULL,
    description text,
    is_system boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    parent_role_id text,
    display_name_th text,
    display_name_de text,
    monthly_budget numeric(14,2) DEFAULT 0 NOT NULL,
    head_user_id integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tiles; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.tiles (
    id text NOT NULL,
    display_name text NOT NULL,
    subtitle text DEFAULT ''::text NOT NULL,
    icon text DEFAULT '🧾'::text NOT NULL,
    accent text DEFAULT 'slate'::text NOT NULL,
    group_name text NOT NULL,
    sub_view text,
    href text NOT NULL,
    request_target text,
    sort_order integer DEFAULT 0 NOT NULL,
    is_system boolean DEFAULT true NOT NULL,
    owner_group_id text,
    view_perm_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_permissions_id_seq; Type: SEQUENCE; Schema: perm; Owner: -
--

CREATE SEQUENCE perm.user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: perm; Owner: -
--

ALTER SEQUENCE perm.user_permissions_id_seq OWNED BY perm.user_permissions.id;


--
-- Name: user_roles; Type: TABLE; Schema: perm; Owner: -
--

CREATE TABLE perm.user_roles (
    user_id integer NOT NULL,
    role_id text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_by text
);


--
-- Name: access_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_requests (
    id integer NOT NULL,
    actor_id integer NOT NULL,
    tile_id text NOT NULL,
    tile_title text,
    note text,
    status text DEFAULT 'pending'::text NOT NULL,
    target_user_id integer,
    target_role text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    resolved_by_user_id integer,
    resolved_note text
);


--
-- Name: access_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.access_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: access_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.access_requests_id_seq OWNED BY public.access_requests.id;


--
-- Name: ai_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_assignments (
    id integer NOT NULL,
    section_key text NOT NULL,
    task_type character varying(20) NOT NULL,
    provider_id integer,
    model_id integer,
    staff_id integer,
    params_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_assignments_task_type_check CHECK (((task_type)::text = ANY ((ARRAY['embed'::character varying, 'chat'::character varying, 'vision'::character varying])::text[])))
);


--
-- Name: ai_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_assignments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_assignments_id_seq OWNED BY public.ai_assignments.id;


--
-- Name: ai_invocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_invocations (
    id bigint NOT NULL,
    staff_id integer,
    section_key text,
    task_type character varying(20),
    provider_id integer,
    model_id integer,
    prompt_tokens integer,
    response_tokens integer,
    latency_ms integer,
    status character varying(20) NOT NULL,
    error text,
    prompt_excerpt text,
    response_excerpt text,
    actor_id integer,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: ai_invocations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_invocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_invocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_invocations_id_seq OWNED BY public.ai_invocations.id;


--
-- Name: ai_models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_models (
    id integer NOT NULL,
    provider_id integer NOT NULL,
    name text NOT NULL,
    capabilities text[] DEFAULT '{}'::text[] NOT NULL,
    context_window integer,
    defaults_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    description text
);


--
-- Name: ai_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_models_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_models_id_seq OWNED BY public.ai_models.id;


--
-- Name: ai_providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_providers (
    id integer NOT NULL,
    name text NOT NULL,
    type character varying(20) NOT NULL,
    base_url text NOT NULL,
    api_key_enc bytea,
    enabled boolean DEFAULT true NOT NULL,
    preset character varying(40),
    notes text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_providers_type_check CHECK (((type)::text = ANY ((ARRAY['ollama'::character varying, 'openai_compat'::character varying, 'minimax'::character varying])::text[])))
);


--
-- Name: ai_providers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_providers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_providers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_providers_id_seq OWNED BY public.ai_providers.id;


--
-- Name: ai_section_health; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_section_health AS
 SELECT a.id AS assignment_id,
    a.section_key,
    a.task_type,
    a.enabled AS assignment_enabled,
    a.priority,
    p.id AS provider_id,
    p.name AS provider_name,
    p.type AS provider_type,
    m.id AS model_id,
    m.name AS model_name,
    count(i.id) FILTER (WHERE ((i.status)::text = 'ok'::text)) AS ok_calls,
    count(i.id) FILTER (WHERE ((i.status)::text = 'error'::text)) AS err_calls,
    count(i.id) AS total_calls,
    max(i.created_at) AS last_invocation_at,
    min(i.created_at) AS first_invocation_at
   FROM (((public.ai_assignments a
     LEFT JOIN public.ai_providers p ON ((p.id = a.provider_id)))
     LEFT JOIN public.ai_models m ON ((m.id = a.model_id)))
     LEFT JOIN public.ai_invocations i ON ((i.section_key = a.section_key)))
  GROUP BY a.id, a.section_key, a.task_type, a.enabled, a.priority, p.id, p.name, p.type, m.id, m.name;


--
-- Name: ai_staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_staff (
    id integer NOT NULL,
    name text NOT NULL,
    role_label text,
    description text,
    system_prompt text NOT NULL,
    capabilities text[] DEFAULT '{}'::text[] NOT NULL,
    default_provider_id integer,
    default_model_id integer,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: ai_staff_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_staff_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_staff_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_staff_id_seq OWNED BY public.ai_staff.id;


--
-- Name: approval_override_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_override_audit (
    id bigint NOT NULL,
    target_type character varying(20) NOT NULL,
    target_id integer,
    actor_id integer,
    kind character varying(20) NOT NULL,
    attempted_stage character varying(50),
    required_role character varying(50),
    actor_role character varying(50),
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT approval_override_audit_kind_check CHECK (((kind)::text = ANY ((ARRAY['granted'::character varying, 'denied'::character varying])::text[]))),
    CONSTRAINT approval_override_audit_target_type_check CHECK (((target_type)::text = ANY ((ARRAY['expense'::character varying, 'pr'::character varying, 'po'::character varying])::text[])))
);


--
-- Name: approval_override_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_override_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_override_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_override_audit_id_seq OWNED BY public.approval_override_audit.id;


--
-- Name: approval_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_transitions (
    id bigint NOT NULL,
    target_type character varying(20) NOT NULL,
    target_id integer NOT NULL,
    actor_id integer,
    previous_status character varying(50),
    new_status character varying(50),
    comments text,
    stage character varying(50),
    chain_index integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT approval_transitions_target_type_check CHECK (((target_type)::text = ANY ((ARRAY['expense'::character varying, 'pr'::character varying, 'po'::character varying])::text[])))
);


--
-- Name: approval_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_transitions_id_seq OWNED BY public.approval_transitions.id;


--
-- Name: chart_of_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chart_of_accounts (
    code character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    name_th character varying(100) NOT NULL,
    account_type character varying(50) NOT NULL,
    embedding public.vector(1024)
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id integer NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    name_th text,
    tax_id text,
    billing_address text,
    shipping_address text,
    contact_name text,
    contact_email text,
    contact_phone text,
    credit_limit_thb numeric(14,2) DEFAULT 0 NOT NULL,
    payment_terms text DEFAULT 'Net 30'::text NOT NULL,
    blacklist boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    name_de text
);


--
-- Name: sales_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_orders (
    id integer NOT NULL,
    so_number text NOT NULL,
    customer_id integer NOT NULL,
    sales_rep_id integer NOT NULL,
    status text DEFAULT 'so_draft'::text NOT NULL,
    payment_terms text DEFAULT 'Net 30'::text NOT NULL,
    due_date date,
    invoice_number text,
    invoice_issued_at timestamp with time zone,
    ar_slip_id integer,
    vat_account_code text DEFAULT '210300'::text NOT NULL,
    ar_account_code text DEFAULT '110400'::text NOT NULL,
    cash_account_code text DEFAULT '110200'::text NOT NULL,
    revenue_account_code text DEFAULT '410100'::text NOT NULL,
    subtotal numeric(14,2) DEFAULT 0 NOT NULL,
    vat_total numeric(14,2) DEFAULT 0 NOT NULL,
    total_amount numeric(14,2) DEFAULT 0 NOT NULL,
    currency text DEFAULT 'THB'::text NOT NULL,
    rejection_reason text,
    rejection_actor_id integer,
    rejected_at timestamp with time zone,
    invoice_issuer_id integer,
    paid_by_id integer,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sales_orders_status_check CHECK ((status = ANY (ARRAY['so_draft'::text, 'so_sales_review'::text, 'so_credit_check'::text, 'so_invoiced'::text, 'so_paid'::text, 'rejected'::text])))
);


--
-- Name: customer_ar_history; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.customer_ar_history AS
 SELECT c.id AS customer_id,
    c.code AS customer_code,
    c.name AS customer_name,
    c.credit_limit_thb AS credit_limit,
    (COALESCE(sum(so.total_amount), (0)::numeric))::numeric(14,2) AS total_invoiced,
    (COALESCE(sum(
        CASE
            WHEN (so.status <> ALL (ARRAY['so_paid'::text, 'rejected'::text])) THEN so.total_amount
            ELSE (0)::numeric
        END), (0)::numeric))::numeric(14,2) AS outstanding_ar,
    (COALESCE(sum(
        CASE
            WHEN (so.status = 'so_paid'::text) THEN so.total_amount
            ELSE (0)::numeric
        END), (0)::numeric))::numeric(14,2) AS total_paid,
    (count(so.id))::integer AS so_count
   FROM (public.customers c
     LEFT JOIN public.sales_orders so ON ((so.customer_id = c.id)))
  GROUP BY c.id, c.code, c.name, c.credit_limit_thb;


--
-- Name: customer_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_contacts (
    id integer NOT NULL,
    customer_id integer NOT NULL,
    fullname text NOT NULL,
    role text,
    email text,
    phone text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customer_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customer_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customer_contacts_id_seq OWNED BY public.customer_contacts.id;


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: domain_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_events (
    id bigint NOT NULL,
    type character varying(80) NOT NULL,
    actor_id integer,
    ref_type character varying(40),
    ref_id bigint,
    payload jsonb,
    severity character varying(20) DEFAULT 'info'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: domain_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.domain_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: domain_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.domain_events_id_seq OWNED BY public.domain_events.id;


--
-- Name: exec_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exec_snapshots (
    id bigint NOT NULL,
    snapshot_date date NOT NULL,
    kpis jsonb NOT NULL,
    dept_budgets jsonb DEFAULT '[]'::jsonb NOT NULL,
    stuck_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: exec_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exec_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exec_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exec_snapshots_id_seq OWNED BY public.exec_snapshots.id;


--
-- Name: expense_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_items (
    id integer NOT NULL,
    expense_id integer,
    description character varying(255) NOT NULL,
    amount numeric(12,2) NOT NULL,
    mapped_account_code character varying(20),
    confidence_score double precision,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    qty numeric(12,2) DEFAULT 1.00 NOT NULL,
    unit_price numeric(12,2) DEFAULT 0.00 NOT NULL
);


--
-- Name: expense_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.expense_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: expense_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.expense_items_id_seq OWNED BY public.expense_items.id;


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id integer NOT NULL,
    submitter_id integer,
    vendor_name character varying(150),
    transaction_date date,
    subtotal numeric(12,2) DEFAULT 0.00,
    vat_amount numeric(12,2) DEFAULT 0.00,
    total_amount numeric(12,2) DEFAULT 0.00,
    payment_method character varying(50),
    status character varying(50) DEFAULT 'draft'::character varying,
    ocr_raw_json jsonb,
    is_corrupted boolean DEFAULT false,
    correction_notes text,
    document_url character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    rejection_reason text,
    rejection_actor_id integer,
    rejected_at timestamp without time zone,
    disbursed_at timestamp without time zone,
    disbursed_by integer,
    gl_confirmed_at timestamp without time zone,
    gl_confirmed_by integer,
    pr_id integer,
    po_id integer,
    journal_entry_id integer,
    created_to character varying(150),
    vendor_address text,
    created_to_address text,
    CONSTRAINT expenses_status_chk CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'submission'::character varying, 'dept_verification'::character varying, 'dept_authorization'::character varying, 'accounting_verification'::character varying, 'accounting_supervision'::character varying, 'accounting_authorization'::character varying, 'final_authorization'::character varying, 'disbursement_authorization'::character varying, 'cfo_authorization'::character varying, 'ceo_authorization'::character varying, 'awaiting_disbursement'::character varying, 'disbursed'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: expenses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.expenses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: expenses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.expenses_id_seq OWNED BY public.expenses.id;


--
-- Name: hook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hook_events (
    id bigint NOT NULL,
    provider_id text NOT NULL,
    external_id text,
    event_type text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    payload jsonb NOT NULL,
    headers jsonb NOT NULL,
    signature_ok boolean NOT NULL,
    status text DEFAULT 'received'::text NOT NULL,
    processed_at timestamp with time zone,
    processed_by text,
    error text,
    replay_count integer DEFAULT 0 NOT NULL,
    CONSTRAINT hook_events_status_check CHECK ((status = ANY (ARRAY['received'::text, 'processed'::text, 'failed'::text, 'rejected'::text])))
);


--
-- Name: hook_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hook_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hook_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hook_events_id_seq OWNED BY public.hook_events.id;


--
-- Name: hook_providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hook_providers (
    id text NOT NULL,
    display_name text NOT NULL,
    kind text NOT NULL,
    secret_env text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT hook_providers_kind_check CHECK ((kind = ANY (ARRAY['line'::text, 'generic'::text])))
);


--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id integer NOT NULL,
    expense_id integer,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    description character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_draft boolean DEFAULT false NOT NULL,
    finalized_at timestamp without time zone,
    finalized_by integer,
    draft_source text DEFAULT 'expense'::text NOT NULL,
    pr_id integer,
    po_id integer,
    step text DEFAULT 'reimbursement'::text NOT NULL,
    so_id integer,
    CONSTRAINT journal_entries_draft_source_chk CHECK (((draft_source IS NULL) OR (draft_source = ANY (ARRAY['expense'::text, 'pr'::text, 'po'::text, 'so'::text])))),
    CONSTRAINT journal_entries_step_check CHECK ((step = ANY (ARRAY['reimbursement'::text, 'accrual'::text, 'settlement'::text, 'sales_vat'::text, 'sales_accrual'::text, 'sales_settlement'::text])))
);


--
-- Name: journal_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.journal_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: journal_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.journal_entries_id_seq OWNED BY public.journal_entries.id;


--
-- Name: ledger_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_lines (
    id integer NOT NULL,
    journal_entry_id integer,
    account_code character varying(20),
    debit numeric(12,2) DEFAULT 0.00 NOT NULL,
    credit numeric(12,2) DEFAULT 0.00 NOT NULL,
    description character varying(255),
    CONSTRAINT chk_debit_credit CHECK ((((debit >= (0)::numeric) AND (credit = (0)::numeric)) OR ((credit >= (0)::numeric) AND (debit = (0)::numeric))))
);


--
-- Name: ledger_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ledger_lines_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ledger_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ledger_lines_id_seq OWNED BY public.ledger_lines.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id integer NOT NULL,
    user_id integer,
    type character varying(50) NOT NULL,
    target_type character varying(20),
    target_id integer,
    payload_json jsonb,
    read_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    cleared_at timestamp with time zone
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: po_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.po_items (
    id integer NOT NULL,
    po_id integer NOT NULL,
    description character varying(255) NOT NULL,
    qty numeric(12,2) DEFAULT 1,
    unit_price numeric(12,2) DEFAULT 0,
    mapped_account_code character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: po_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.po_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: po_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.po_items_id_seq OWNED BY public.po_items.id;


--
-- Name: policy_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policy_audit (
    id integer NOT NULL,
    policy_id integer,
    actor_id integer,
    before_json jsonb,
    after_json jsonb,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: policy_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.policy_audit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: policy_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.policy_audit_id_seq OWNED BY public.policy_audit.id;


--
-- Name: pr_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pr_items (
    id integer NOT NULL,
    pr_id integer,
    description character varying(255) NOT NULL,
    qty numeric(12,2) DEFAULT 1.00 NOT NULL,
    unit_price numeric(12,2) DEFAULT 0.00 NOT NULL,
    mapped_account_code character varying(20),
    confidence_score double precision,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: pr_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pr_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pr_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pr_items_id_seq OWNED BY public.pr_items.id;


--
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_orders (
    id integer NOT NULL,
    pr_id integer NOT NULL,
    po_number character varying(40) NOT NULL,
    vendor_name character varying(150),
    total_amount numeric(14,2) DEFAULT 0,
    currency character varying(10) DEFAULT 'THB'::character varying,
    status character varying(50) DEFAULT 'draft'::character varying,
    issued_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    issued_by integer,
    settled_at timestamp without time zone,
    settled_by integer,
    settled_slip_id integer,
    rejection_reason text,
    rejection_actor_id integer,
    rejected_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    vendor_country character(2),
    CONSTRAINT purchase_orders_status_chk CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'submission'::character varying, 'dept_verification'::character varying, 'dept_authorization'::character varying, 'accounting_verification'::character varying, 'accounting_supervision'::character varying, 'accounting_authorization'::character varying, 'final_authorization'::character varying, 'disbursement_authorization'::character varying, 'cfo_authorization'::character varying, 'ceo_authorization'::character varying, 'awaiting_disbursement'::character varying, 'disbursed'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: purchase_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchase_orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchase_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchase_orders_id_seq OWNED BY public.purchase_orders.id;


--
-- Name: purchase_requisitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_requisitions (
    id integer NOT NULL,
    requester_id integer,
    vendor_name character varying(150),
    need_by_date date,
    status character varying(50) DEFAULT 'draft'::character varying,
    total_estimate numeric(14,2) DEFAULT 0.00,
    currency character varying(10) DEFAULT 'THB'::character varying,
    justification text,
    document_url character varying(500),
    is_recurring boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    rejection_reason text,
    rejection_actor_id integer,
    rejected_at timestamp without time zone,
    dept_group_id text,
    pr_number text GENERATED ALWAYS AS (((('PR-'::text || (EXTRACT(year FROM created_at))::text) || '-'::text) || lpad((id)::text, 6, '0'::text))) STORED,
    vendor_country character(2),
    CONSTRAINT purchase_requisitions_status_chk CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'submission'::character varying, 'dept_verification'::character varying, 'dept_authorization'::character varying, 'accounting_verification'::character varying, 'accounting_supervision'::character varying, 'accounting_authorization'::character varying, 'final_authorization'::character varying, 'disbursement_authorization'::character varying, 'cfo_authorization'::character varying, 'ceo_authorization'::character varying, 'awaiting_disbursement'::character varying, 'disbursed'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: purchase_requisitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchase_requisitions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchase_requisitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchase_requisitions_id_seq OWNED BY public.purchase_requisitions.id;


--
-- Name: sales_orders_fy_2026_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sales_orders_fy_2026_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sales_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sales_orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sales_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sales_orders_id_seq OWNED BY public.sales_orders.id;


--
-- Name: slips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slips (
    id integer NOT NULL,
    expense_id integer,
    pr_id integer,
    file_path character varying(500) NOT NULL,
    mime_type character varying(100) NOT NULL,
    file_size integer NOT NULL,
    ocr_raw_json jsonb,
    ocr_confidence double precision,
    ai_reasoning text,
    uploaded_by integer,
    uploaded_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    po_id integer,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    confirmed_at timestamp with time zone,
    discarded_at timestamp with time zone,
    discarded_by integer,
    kind character varying(20) DEFAULT 'receipt'::character varying NOT NULL,
    bank_name character varying(150),
    account_number character varying(30),
    account_name character varying(150),
    bank_branch character varying(150),
    CONSTRAINT slips_kind_chk CHECK (((kind)::text = ANY ((ARRAY['receipt'::character varying, 'book_bank'::character varying])::text[])))
);


--
-- Name: COLUMN slips.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.status IS 'pending = uploaded + OCR done, no parent, uploader can still discard. confirmed = linked to expense/pr/po, in approval queue. Removal of a confirmed slip is blocked once the linked parent has any approved/rejected transition.';


--
-- Name: COLUMN slips.confirmed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.confirmed_at IS 'Timestamp the slip was linked to its parent expense/pr/po.';


--
-- Name: COLUMN slips.discarded_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.discarded_at IS 'Timestamp the slip was removed by the uploader (null = not discarded).';


--
-- Name: COLUMN slips.discarded_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.discarded_by IS 'User who discarded the slip (null = not discarded).';


--
-- Name: COLUMN slips.kind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.kind IS 'receipt = the typical receipt/ใบเสร็จ slip (default). book_bank = passbook image for a transfer payee — carries bank_name / account_number / account_name. Two slips per expense are permitted; each row has exactly one parent per the slips_exactly_one_parent trigger.';


--
-- Name: COLUMN slips.bank_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.bank_name IS 'For book_bank slips: issuing bank name (free text or one of Krungthai/SCB/Bangkok Bank/Kasikorn/TMBThanachai/Other).';


--
-- Name: COLUMN slips.account_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.account_number IS 'For book_bank slips: payee bank account number (digits, no dashes).';


--
-- Name: COLUMN slips.account_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.account_name IS 'For book_bank slips: payee name as printed on the passbook.';


--
-- Name: COLUMN slips.bank_branch; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.slips.bank_branch IS 'For book_bank slips: branch as printed on the passbook, e.g. ''0080 สาขาฟิวเจอร์พาร์ค รังสิต''. Free text. Optional.';


--
-- Name: slips_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.slips_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: slips_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.slips_id_seq OWNED BY public.slips.id;


--
-- Name: so_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.so_items (
    id integer NOT NULL,
    sales_order_id integer NOT NULL,
    description text NOT NULL,
    qty numeric(12,2) DEFAULT 1 NOT NULL,
    unit_price numeric(14,2) DEFAULT 0 NOT NULL,
    vat_amount numeric(14,2) DEFAULT 0 NOT NULL,
    line_total numeric(14,2) DEFAULT 0 NOT NULL,
    mapped_revenue_account_code text,
    confidence_score numeric(5,3),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: so_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.so_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: so_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.so_items_id_seq OWNED BY public.so_items.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    employee_code character varying(20) NOT NULL,
    fullname character varying(100) NOT NULL,
    line_user_id character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    hired_at date NOT NULL,
    secondary_locale text DEFAULT 'th'::text NOT NULL,
    CONSTRAINT users_secondary_locale_check CHECK ((secondary_locale = ANY (ARRAY['th'::text, 'de'::text])))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: waybill_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waybill_attachments (
    id bigint NOT NULL,
    waybill_id text NOT NULL,
    stage_key text NOT NULL,
    kind text NOT NULL,
    storage_backend text DEFAULT 'minio'::text NOT NULL,
    storage_key text NOT NULL,
    filename text NOT NULL,
    content_type text NOT NULL,
    byte_size integer NOT NULL,
    uploaded_by integer NOT NULL,
    uploaded_role text NOT NULL,
    caption text,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT waybill_attachments_byte_size_check CHECK ((byte_size >= 0)),
    CONSTRAINT waybill_attachments_kind_check CHECK ((kind = ANY (ARRAY['slip'::text, 'pr_doc'::text, 'po_doc'::text, 'payment_receipt'::text, 'signoff_memo'::text, 'invoice'::text, 'wht_cert'::text, 'photo'::text, 'memo'::text, 'other'::text]))),
    CONSTRAINT waybill_attachments_storage_backend_check CHECK ((storage_backend = 'minio'::text))
);


--
-- Name: waybill_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.waybill_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: waybill_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.waybill_attachments_id_seq OWNED BY public.waybill_attachments.id;


--
-- Name: waybill_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waybill_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    waybill_id text NOT NULL,
    sequence integer NOT NULL,
    previous_event_id uuid,
    kind text NOT NULL,
    stage_from text,
    stage_to text,
    actor_id integer,
    actor_role text,
    actor_signature bytea,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    payload jsonb,
    CONSTRAINT waybill_events_kind_check CHECK ((kind = ANY (ARRAY['created'::text, 'submitted'::text, 'advanced'::text, 'rejected'::text, 'corrected'::text, 'settled'::text, 'posted-to-gl'::text, 'gl-confirmed'::text, 'slip-attached'::text, 'attached'::text, 'signed-off'::text, 'reversed'::text, 'authorization-overridden'::text, 'resubmitted'::text, 'superseded'::text, 'pr-created'::text, 'po-issued'::text, 'posted-to-gl-accrual'::text, 'gl-confirmed-accrual'::text, 'posted-to-gl-settlement'::text, 'gl-confirmed-settlement'::text, 'created-draft-gl-accrual'::text, 'created-draft-gl-settlement'::text, 'so-created'::text, 'so-submitted'::text, 'so-auto-approved'::text, 'so-reviewed'::text, 'so-credit-checked'::text, 'so-invoiced'::text, 'so-paid'::text, 'so-rejected'::text, 'posted-to-gl-sales-vat'::text, 'gl-confirmed-sales-vat'::text, 'posted-to-gl-sales-accrual'::text, 'gl-confirmed-sales-accrual'::text, 'posted-to-gl-sales-settlement'::text, 'gl-confirmed-sales-settlement'::text, 'created-draft-gl-sales-vat'::text, 'created-draft-gl-sales-accrual'::text, 'created-draft-gl-sales-settlement'::text]))),
    CONSTRAINT waybill_events_sequence_check CHECK ((sequence >= 1))
);


--
-- Name: waybill_watchers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waybill_watchers (
    id bigint NOT NULL,
    waybill_id text NOT NULL,
    stage_key text NOT NULL,
    user_id integer NOT NULL,
    notified_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: waybill_watchers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.waybill_watchers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: waybill_watchers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.waybill_watchers_id_seq OWNED BY public.waybill_watchers.id;


--
-- Name: waybills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waybills (
    id text NOT NULL,
    origin text NOT NULL,
    origin_id integer NOT NULL,
    fiscal_year smallint NOT NULL,
    waybill_kind text NOT NULL,
    submitter_id integer,
    vendor_name text,
    total_amount numeric(14,2),
    currency text DEFAULT 'THB'::text NOT NULL,
    current_stage text NOT NULL,
    current_owner_role text,
    current_owner_user_id integer,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_to text,
    vendor_address text,
    created_to_address text,
    CONSTRAINT waybills_origin_check CHECK ((origin = ANY (ARRAY['expense'::text, 'pr'::text, 'po'::text, 'so'::text]))),
    CONSTRAINT waybills_status_check CHECK ((status = ANY (ARRAY['open'::text, 'completed'::text, 'rejected'::text, 'reversed'::text, 'superseded'::text]))),
    CONSTRAINT waybills_waybill_kind_check CHECK ((waybill_kind = ANY (ARRAY['reimbursement'::text, 'procurement'::text])))
);


--
-- Name: waybills_fy_2026_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.waybills_fy_2026_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit id; Type: DEFAULT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.audit ALTER COLUMN id SET DEFAULT nextval('perm.audit_id_seq'::regclass);


--
-- Name: policy_decisions id; Type: DEFAULT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.policy_decisions ALTER COLUMN id SET DEFAULT nextval('perm.policy_decisions_id_seq'::regclass);


--
-- Name: user_permissions id; Type: DEFAULT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_permissions ALTER COLUMN id SET DEFAULT nextval('perm.user_permissions_id_seq'::regclass);


--
-- Name: access_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_requests ALTER COLUMN id SET DEFAULT nextval('public.access_requests_id_seq'::regclass);


--
-- Name: ai_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_assignments ALTER COLUMN id SET DEFAULT nextval('public.ai_assignments_id_seq'::regclass);


--
-- Name: ai_invocations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_invocations ALTER COLUMN id SET DEFAULT nextval('public.ai_invocations_id_seq'::regclass);


--
-- Name: ai_models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_models ALTER COLUMN id SET DEFAULT nextval('public.ai_models_id_seq'::regclass);


--
-- Name: ai_providers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_providers ALTER COLUMN id SET DEFAULT nextval('public.ai_providers_id_seq'::regclass);


--
-- Name: ai_staff id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_staff ALTER COLUMN id SET DEFAULT nextval('public.ai_staff_id_seq'::regclass);


--
-- Name: approval_override_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_override_audit ALTER COLUMN id SET DEFAULT nextval('public.approval_override_audit_id_seq'::regclass);


--
-- Name: approval_transitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_transitions ALTER COLUMN id SET DEFAULT nextval('public.approval_transitions_id_seq'::regclass);


--
-- Name: customer_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts ALTER COLUMN id SET DEFAULT nextval('public.customer_contacts_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: domain_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_events ALTER COLUMN id SET DEFAULT nextval('public.domain_events_id_seq'::regclass);


--
-- Name: exec_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exec_snapshots ALTER COLUMN id SET DEFAULT nextval('public.exec_snapshots_id_seq'::regclass);


--
-- Name: expense_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_items ALTER COLUMN id SET DEFAULT nextval('public.expense_items_id_seq'::regclass);


--
-- Name: expenses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses ALTER COLUMN id SET DEFAULT nextval('public.expenses_id_seq'::regclass);


--
-- Name: hook_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hook_events ALTER COLUMN id SET DEFAULT nextval('public.hook_events_id_seq'::regclass);


--
-- Name: journal_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries ALTER COLUMN id SET DEFAULT nextval('public.journal_entries_id_seq'::regclass);


--
-- Name: ledger_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines ALTER COLUMN id SET DEFAULT nextval('public.ledger_lines_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: po_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.po_items ALTER COLUMN id SET DEFAULT nextval('public.po_items_id_seq'::regclass);


--
-- Name: policy_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_audit ALTER COLUMN id SET DEFAULT nextval('public.policy_audit_id_seq'::regclass);


--
-- Name: pr_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pr_items ALTER COLUMN id SET DEFAULT nextval('public.pr_items_id_seq'::regclass);


--
-- Name: purchase_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders ALTER COLUMN id SET DEFAULT nextval('public.purchase_orders_id_seq'::regclass);


--
-- Name: purchase_requisitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_requisitions ALTER COLUMN id SET DEFAULT nextval('public.purchase_requisitions_id_seq'::regclass);


--
-- Name: sales_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders ALTER COLUMN id SET DEFAULT nextval('public.sales_orders_id_seq'::regclass);


--
-- Name: slips id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips ALTER COLUMN id SET DEFAULT nextval('public.slips_id_seq'::regclass);


--
-- Name: so_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.so_items ALTER COLUMN id SET DEFAULT nextval('public.so_items_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: waybill_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_attachments ALTER COLUMN id SET DEFAULT nextval('public.waybill_attachments_id_seq'::regclass);


--
-- Name: waybill_watchers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_watchers ALTER COLUMN id SET DEFAULT nextval('public.waybill_watchers_id_seq'::regclass);


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.sessions (id, user_id, impersonator_user_id, role, issued_at, expires_at, revoked_at, last_seen_at, last_seen_ip, last_seen_ua, locale) FROM stdin;
OVx65km_tacutoGZMPIy67pMkwyjdsLQSBbt0r0xGFo	948	\N	manager	2026-07-08 14:05:57.016937+07	2026-08-07 14:05:57.016937+07	\N	2026-07-08 14:05:57.016937+07	\N	\N	th
_jLGuoV9bTi9qFOx1DN0nmvTxmUulDPlpRqeoWiUW2c	948	\N	manager	2026-07-08 12:37:02.104276+07	2026-08-07 12:37:02.104276+07	\N	2026-07-08 12:37:02.134871+07	\N	\N	th
Kl-aHE5GGSSTBEph1VeYaDtAAFCuHFERfloUkn698sU	949	\N	hr_manager	2026-07-08 12:37:02.24347+07	2026-08-07 12:37:02.24347+07	\N	2026-07-08 12:37:02.274266+07	\N	\N	th
LgjOw6wmV6gDmpbfbDZYuGGg8axDrmiWqu_5sPUmzrg	955	\N	account_supervisor	2026-07-08 12:37:02.398402+07	2026-08-07 12:37:02.398402+07	\N	2026-07-08 12:37:02.432365+07	\N	\N	th
mlSXnMq9fReh6iWXmn1UoFt3-gc2kb7fojzJvMMKZeA	964	\N	it	2026-07-08 12:37:02.546819+07	2026-08-07 12:37:02.546819+07	\N	2026-07-08 12:37:02.579911+07	\N	\N	th
akKD7pv-7ltsB6GsdR833rgxMoq3QR06XCftNAR2kP0	959	\N	staff	2026-07-08 12:37:02.776407+07	2026-08-07 12:37:02.776407+07	\N	2026-07-08 12:37:02.810232+07	\N	\N	th
_2gyU8icD07KE66ArDxvLBCGE113ipuMfa79gB_YIPM	951	\N	manager	2026-07-08 13:00:15.801462+07	2026-08-07 13:00:15.801462+07	\N	2026-07-08 13:00:15.851967+07	\N	\N	th
Z6PnP_u3OYgDV3oRi0FRP0KTo2ndKzYSvzPP71zM3zc	944	\N	ceo	2026-07-08 12:37:09.137636+07	2026-08-07 12:37:09.137636+07	2026-07-08 12:37:09.245717+07	2026-07-08 12:37:09.200571+07	\N	\N	th
Enk69Rx7aFQLJpCT7615f8dmHQifBytKe9MpCi374Pw	947	\N	manager	2026-07-08 12:47:21.634171+07	2026-08-07 12:47:21.634171+07	\N	2026-07-08 12:47:23.58887+07	\N	\N	th
wxaZUXLNzVvCM5XmqSeJL_TEAe75GeCEOFufRfd7BVQ	948	\N	manager	2026-07-08 12:58:47.216614+07	2026-08-07 12:58:47.216614+07	\N	2026-07-08 12:58:47.290898+07	\N	\N	th
QM4-8YL-PCLfPkBvC9voDHuO9rEvyUnMW2ONG8SG84o	944	\N	ceo	2026-07-08 12:34:01.44052+07	2026-08-07 12:34:01.44052+07	2026-07-08 12:34:10.768303+07	2026-07-08 12:34:03.582932+07	\N	\N	th
0H_nKtEFugateBfT9aHR2C7UoHIAaf9mv0HEI1WA5HU	944	\N	ceo	2026-07-08 12:34:10.672879+07	2026-08-07 12:34:10.672879+07	2026-07-08 12:34:10.768303+07	2026-07-08 12:34:10.714063+07	\N	\N	th
Q66yRt0DLDJHQDj_0Jg02aitXmnspyWQoqqYOGZp23Q	944	\N	ceo	2026-07-11 04:28:06.585458+07	2026-08-10 04:28:06.585458+07	\N	2026-07-11 04:28:06.585458+07	\N	\N	th
ohk6H0uNwGrs8H4qqoviNTrSQp-OZwr2Qf2GmWqAoYs	944	\N	ceo	2026-07-08 12:34:22.217856+07	2026-08-07 12:34:22.217856+07	2026-07-08 12:34:22.336666+07	2026-07-08 12:34:22.291711+07	\N	\N	th
kNFr7OvxwUGMYhvZX7yVFLFUhylyoO8UMldTZECJR50	948	\N	manager	2026-07-08 12:51:53.580241+07	2026-08-07 12:51:53.580241+07	2026-07-08 12:52:02.262791+07	2026-07-08 12:52:01.433536+07	\N	\N	th
Wftow_DNL6X2dXgHCKlAMszv5RRiG9C-EAQ9CUb2PiQ	944	\N	ceo	2026-07-08 12:34:56.854291+07	2026-08-07 12:34:56.854291+07	2026-07-08 12:34:56.997485+07	2026-07-08 12:34:56.944184+07	\N	\N	th
Y0n2Q_AYg7K74--NVbUuyZvUpjFQbN08bb10RyLhVFQ	944	\N	ceo	2026-07-08 12:35:13.328209+07	2026-08-07 12:35:13.328209+07	2026-07-08 12:35:13.459411+07	2026-07-08 12:35:13.411411+07	\N	\N	th
RsVlmvdCtv93GaTFJG_Xv_UHZ6iNjD9El1pkytgKUyo	944	\N	ceo	2026-07-08 12:48:16.082845+07	2026-08-07 12:48:16.082845+07	2026-07-08 12:51:42.650571+07	2026-07-08 12:51:31.111507+07	\N	\N	th
QPdeneIUvdGrBJLQInbVNEKGcj2TXLdv1MExPTKDka4	944	\N	ceo	2026-07-08 12:35:32.628878+07	2026-08-07 12:35:32.628878+07	2026-07-08 12:35:32.735092+07	2026-07-08 12:35:32.689243+07	\N	\N	th
t4Cz1xGIATz4fCa_RfuIshwCmeJG5DYAcP9lHIW-LDY	944	\N	ceo	2026-07-08 12:35:52.987915+07	2026-08-07 12:35:52.987915+07	2026-07-08 12:35:53.029434+07	2026-07-08 12:35:52.987915+07	\N	\N	th
-Z0_tgttUjV5Q43b7KId2JFM3BEe_8CDud1nshtiwYc	944	\N	ceo	2026-07-08 12:36:53.074805+07	2026-08-07 12:36:53.074805+07	\N	2026-07-08 12:36:53.074805+07	\N	\N	th
JzjgATsVXYKLQHaZB0wIENDn4hGf-5kuMWhZzlsGdBI	945	\N	cfo	2026-07-08 12:36:53.111377+07	2026-08-07 12:36:53.111377+07	\N	2026-07-08 12:36:53.111377+07	\N	\N	th
ebWz0V1kLHiuI4o78FOcDOCViMJRVL8rl69SVudQvS0	946	\N	finance	2026-07-08 12:36:53.147774+07	2026-08-07 12:36:53.147774+07	\N	2026-07-08 12:36:53.147774+07	\N	\N	th
lqjW1EGRdCIwf6PJBSIVoJhzwqy8tdEt-4MnaCAyUzI	948	\N	manager	2026-07-08 12:36:53.182998+07	2026-08-07 12:36:53.182998+07	\N	2026-07-08 12:36:53.182998+07	\N	\N	th
EcI8FyBfdbWM8jPduQR2P0NQmGxpXBnZf-m142IY5ms	949	\N	hr_manager	2026-07-08 12:36:53.216903+07	2026-08-07 12:36:53.216903+07	\N	2026-07-08 12:36:53.216903+07	\N	\N	th
i1DrcktfqYyR_T44oUXCzysiuK3UrQc9vxbxSAJ0wh8	955	\N	account_supervisor	2026-07-08 12:36:53.251357+07	2026-08-07 12:36:53.251357+07	\N	2026-07-08 12:36:53.251357+07	\N	\N	th
kpJh-dKbOYCXPB7a7gIebz_OjhnvAB-nl4FXlfwSOY4	964	\N	it	2026-07-08 12:36:53.284573+07	2026-08-07 12:36:53.284573+07	\N	2026-07-08 12:36:53.284573+07	\N	\N	th
iGY15DfUnLesvFKX1tmtMJnHokhuFjr1pLpxPnmnfDg	959	\N	staff	2026-07-08 12:36:53.317406+07	2026-08-07 12:36:53.317406+07	\N	2026-07-08 12:36:53.317406+07	\N	\N	th
pmVlpSjBzkgn2TJN2diLYGIblLv3GuNwx1JzOCL63yw	946	\N	finance	2026-07-08 12:52:08.593198+07	2026-08-07 12:52:08.593198+07	2026-07-08 12:52:12.6703+07	2026-07-08 12:52:09.04106+07	\N	\N	th
ZbOQYosbzwSNKn356zT8kEDR4wV5pNDetIkisj5JivQ	962	\N	hr	2026-07-08 13:00:16.036034+07	2026-08-07 13:00:16.036034+07	\N	2026-07-08 13:00:16.091862+07	\N	\N	th
krw3BbAUkY9YAAF1yFkRUAdB8lSeWGO_dhtVenRWKAY	956	\N	supervisor	2026-07-08 13:00:15.570513+07	2026-08-07 13:00:15.570513+07	\N	2026-07-08 13:00:15.622463+07	\N	\N	th
VxS2msraZ3V08dbQe60V61zt4bPwmMcgqonWiEgGGu0	945	\N	cfo	2026-07-08 12:47:10.87783+07	2026-08-07 12:47:10.87783+07	\N	2026-07-08 12:47:15.422704+07	\N	\N	th
FM4AEn90bH5I5kdwjCHmdxtPkBdft9_Jm1fFmI90Ncw	948	\N	manager	2026-07-08 12:58:22.897297+07	2026-08-07 12:58:22.897297+07	\N	2026-07-08 12:58:22.994984+07	\N	\N	th
7OJogFpLC0DxpKw5u3eohs8duK49cdcuZ5z7vzzmxvs	944	\N	ceo	2026-07-08 12:47:23.549169+07	2026-08-07 12:47:23.549169+07	\N	2026-07-08 12:47:29.772276+07	\N	\N	th
NYDDEJe5E2KlrWhZ0Umgibf0h6gOCO7M9-PJfhDnLgo	945	\N	cfo	2026-07-08 12:51:42.649432+07	2026-08-07 12:51:42.649432+07	2026-07-08 12:51:46.363643+07	2026-07-08 12:51:46.231477+07	\N	\N	th
0Cl69adBdfph-MheoS9kf_HGqVvzMiI4tCJrauzlIXM	944	\N	ceo	2026-07-08 12:36:53.3701+07	2026-08-07 12:36:53.3701+07	\N	2026-07-08 12:36:53.960264+07	\N	\N	th
qzFk_rtTjHeO_r8zjAvWTJ8OpwhOxlJ2-xPpWuPZB90	944	\N	ceo	2026-07-08 12:37:01.716999+07	2026-08-07 12:37:01.716999+07	\N	2026-07-08 12:37:01.757028+07	\N	\N	th
BKNjD7aDaf13wooHhgL3yv4YzKoajoAkKa4tjTSkCRk	945	\N	cfo	2026-07-08 12:37:01.828384+07	2026-08-07 12:37:01.828384+07	\N	2026-07-08 12:37:01.858756+07	\N	\N	th
YDJwLv_ZAJStoaJBFU5Qih7sSjuc77ovLzuuUA_n6us	946	\N	finance	2026-07-08 12:37:01.931319+07	2026-08-07 12:37:01.931319+07	\N	2026-07-08 12:37:01.960969+07	\N	\N	th
ff5qQc4mM0WdhmSSW9TLFXcDG651wvNApRqSw2P44qQ	962	\N	hr	2026-07-08 12:52:02.260917+07	2026-08-07 12:52:02.260917+07	2026-07-08 12:52:05.465095+07	2026-07-08 12:52:02.592401+07	\N	\N	th
wqtZdqBhcJE4Te8x1heAUDq9VekA_8vohl44LvqEbbM	944	\N	ceo	2026-07-08 12:47:15.383058+07	2026-08-07 12:47:15.383058+07	\N	2026-07-08 12:47:21.792116+07	\N	\N	th
Vv_iMKNcu49RdEy_9JpWuvxyV0ncl43ONDkYjavbQ9Q	944	\N	ceo	2026-07-08 12:47:38.359608+07	2026-08-07 12:47:38.359608+07	2026-07-08 12:48:14.203708+07	2026-07-08 12:48:09.414567+07	\N	\N	th
TdIRdoj2iS2WsrjfZCWvfpO8aPBkvR7Jeo-vGmZVM84	948	\N	manager	2026-07-08 12:58:31.032608+07	2026-08-07 12:58:31.032608+07	\N	2026-07-08 12:58:31.123253+07	\N	\N	th
VZw0COt_nI9Ag_jdy9yM8S7W0GnjFS9K_YWHHLWM7HU	944	\N	ceo	2026-07-08 12:51:46.361157+07	2026-08-07 12:51:46.361157+07	2026-07-08 12:51:53.582803+07	2026-07-08 12:51:46.65603+07	\N	\N	th
eqYBnbjT458GEnWGPT5ZX-ov7JsxvB9UVgKIAARTch8	944	\N	ceo	2026-07-08 13:21:17.237336+07	2026-08-07 13:21:17.237336+07	\N	2026-07-08 13:21:17.294792+07	\N	\N	th
EJ_iN9-obChqvJyl8a3Gp1DpeYcmHErzMlsDRX2sLbM	958	\N	supervisor	2026-07-08 12:52:05.463183+07	2026-08-07 12:52:05.463183+07	2026-07-08 12:52:08.595074+07	2026-07-08 12:52:05.743271+07	\N	\N	th
xjPDOOWC03sQbjsQ_QyxmnQlYqVFpRl2tcAqIFVOwj4	957	\N	supervisor	2026-07-08 13:00:15.916437+07	2026-08-07 13:00:15.916437+07	\N	2026-07-08 13:00:15.97161+07	\N	\N	th
kjHvibAsx27VOxLNldtuvGaOScd-ssDPPZR4M3Olk1U	948	\N	manager	2026-07-08 12:59:08.345172+07	2026-08-07 12:59:08.345172+07	\N	2026-07-08 12:59:09.462616+07	\N	\N	th
KK0dZ3kzk7tkwdTcPptiYxBTnIqJGLt3XkgflA-Lnwc	948	\N	manager	2026-07-08 12:58:41.920105+07	2026-08-07 12:58:41.920105+07	\N	2026-07-08 12:58:41.994925+07	\N	\N	th
AMLLwkKrpKlIG22XSDtnX2_KpOPEShlnvL1EgzfAnfQ	950	\N	manager	2026-07-08 12:58:02.188911+07	2026-08-07 12:58:02.188911+07	\N	2026-07-08 12:58:02.188911+07	\N	\N	th
U0yoTGD1_DuvwX1qVCzKcw7EXZ1oDMPujLrGNF59m2k	948	\N	manager	2026-07-08 13:00:08.802685+07	2026-08-07 13:00:08.802685+07	\N	2026-07-08 13:00:08.938663+07	\N	\N	th
h5LOpyO8v27vGKv0enUcpSXB1CVIuMkviWJF5_IuH1M	948	\N	manager	2026-07-08 13:02:39.469389+07	2026-08-07 13:02:39.469389+07	\N	2026-07-08 13:02:39.5455+07	\N	\N	th
zwM7FDzckwZKwv-ljzQrhI5aplx40x-NFdiRCv4Ztvs	961	\N	staff	2026-07-08 13:00:15.682672+07	2026-08-07 13:00:15.682672+07	\N	2026-07-08 13:00:15.733602+07	\N	\N	th
kFONA01hRIhoZS0FxkOcPSiQFb7N7ttQ9m3kCPraLsc	948	\N	manager	2026-07-08 12:59:15.718866+07	2026-08-07 12:59:15.718866+07	\N	2026-07-08 12:59:15.78904+07	\N	\N	th
D1Ir9YZdC-iDpn4KQ2e7bNsTa_8BrKpUP2bcEVWogkA	950	\N	manager	2026-07-08 13:00:15.358551+07	2026-08-07 13:00:15.358551+07	\N	2026-07-08 13:00:15.500935+07	\N	\N	th
DLFKjbo_vtJ-FsEII8GlE3Vfk4ycc3-joNQihD33YOo	964	\N	it	2026-07-08 13:00:16.154692+07	2026-08-07 13:00:16.154692+07	\N	2026-07-08 13:00:16.216026+07	\N	\N	th
G-H38Wk-av6yel3nEDa-cQIb6AD8--hXXfB9pMo0FgA	963	\N	staff	2026-07-08 13:06:28.991917+07	2026-08-07 13:06:28.991917+07	\N	2026-07-08 13:06:29.05975+07	\N	\N	th
aEEMpfqW3SjhYQD9azCKn7r_WEqzUlxl9VTpBuSJe-M	948	\N	manager	2026-07-08 13:06:29.102503+07	2026-08-07 13:06:29.102503+07	\N	2026-07-08 13:06:29.154446+07	\N	\N	th
SfCXr5gYp8CqUp9Sgq9TotzuVEUsy3osuDImzvIv85Y	963	\N	staff	2026-07-08 13:09:42.913399+07	2026-08-07 13:09:42.913399+07	\N	2026-07-08 13:09:42.965312+07	\N	\N	th
QuNDb5LB8D01habZtFs82UWkP_P-lWZvtMmpzo8NXTA	948	\N	manager	2026-07-08 13:09:42.814776+07	2026-08-07 13:09:42.814776+07	\N	2026-07-08 13:09:42.870728+07	\N	\N	th
ilHk5LRmREe2HTCiXGJ16-iiFCY7AKyJfutvUo0dMss	963	\N	staff	2026-07-08 13:09:42.671794+07	2026-08-07 13:09:42.671794+07	\N	2026-07-08 13:09:42.766245+07	\N	\N	th
TrocHKD9aix0mTh6nk_bht5Sg8v4qYLyooU8Cj6GbD8	963	\N	staff	2026-07-08 13:09:53.850977+07	2026-08-07 13:09:53.850977+07	\N	2026-07-08 13:09:53.920792+07	\N	\N	th
oQwj-31fg2DViDn_4aExpTR9qPg6L4KTdJ212UFmRAY	963	\N	officer	2026-07-08 13:21:06.764569+07	2026-08-07 13:21:06.764569+07	\N	2026-07-08 13:21:06.877258+07	\N	\N	th
HfGDf3qE5U-M_c0-6M-YV64jJwCK-JZoainIsh6_bRs	946	\N	finance	2026-07-08 13:21:06.959162+07	2026-08-07 13:21:06.959162+07	\N	2026-07-08 13:21:07.01797+07	\N	\N	th
OSOZPMa9mSsFSlpZzw30YP9Fd3EOUuP5tTo2C9HVmTk	959	\N	officer	2026-07-08 13:21:07.069476+07	2026-08-07 13:21:07.069476+07	\N	2026-07-08 13:21:07.129734+07	\N	\N	th
3FEsLqgOA4kkTbdW7rg0BIPaMrVWImfPBNF7qGBrw3c	945	\N	cfo	2026-07-08 13:21:17.370225+07	2026-08-07 13:21:17.370225+07	\N	2026-07-08 13:21:17.404892+07	\N	\N	th
nEDk6bxsklFtukrTjeeZKDMzxAx0IJMFOfV_2y3Oxw4	946	\N	finance	2026-07-08 13:21:17.474402+07	2026-08-07 13:21:17.474402+07	\N	2026-07-08 13:21:17.508243+07	\N	\N	th
csMiSq_Xgxo7iF6BRB24wU2oSYZqdbJPsJDyYokPK0I	948	\N	manager	2026-07-08 13:21:17.573384+07	2026-08-07 13:21:17.573384+07	\N	2026-07-08 13:21:17.604619+07	\N	\N	th
JvfqRSTYDOI_R-lZR317AjeBsM29tHtglHPZsrhc3Ow	949	\N	hr_manager	2026-07-08 13:21:17.68588+07	2026-08-07 13:21:17.68588+07	\N	2026-07-08 13:21:17.724806+07	\N	\N	th
NqrlGkQMyrMam-br7ylBLWEv-drjt4-GC80CgB9lACA	955	\N	account_supervisor	2026-07-08 13:21:17.823838+07	2026-08-07 13:21:17.823838+07	\N	2026-07-08 13:21:17.857149+07	\N	\N	th
jc7OUlsB2mRmbs63RI4wcniEG9-7guuSN-ZYbPLecI8	964	\N	it	2026-07-08 13:21:17.929955+07	2026-08-07 13:21:17.929955+07	\N	2026-07-08 13:21:17.964595+07	\N	\N	th
71RBsH5nkIjXcXYP4kLFMiqxxIfVEH6BWLygtYwsl2w	959	\N	officer	2026-07-08 13:21:18.038572+07	2026-08-07 13:21:18.038572+07	\N	2026-07-08 13:21:18.070972+07	\N	\N	th
947sWX_DzMfWA8O701YSPYKn4eEp7Pzajg2jtkCKSU8	963	\N	officer	2026-07-08 13:21:18.142672+07	2026-08-07 13:21:18.142672+07	\N	2026-07-08 13:21:18.175382+07	\N	\N	th
cTz1KimZpRLrXcAZH35-yM7BTXKYu9hY5YxpqsDFGU0	946	\N	finance	2026-07-08 17:16:32.663004+07	2026-08-07 17:16:32.663004+07	\N	2026-07-08 17:46:05.400872+07	\N	\N	th
VmP7RG6fVdi7t5i0VrbePLV67AsY5LywQSh8zqZo96Q	957	\N	supervisor	2026-07-08 16:44:14.375314+07	2026-08-07 16:44:14.375314+07	2026-07-08 16:44:37.21397+07	2026-07-08 16:44:28.088912+07	\N	\N	th
CKF0Fq_VN3Gm2UCQjpDDePbAdYO75npkrUQSrDUGlQg	957	\N	supervisor	2026-07-08 16:44:51.442667+07	2026-08-07 16:44:51.442667+07	2026-07-08 17:00:21.24174+07	2026-07-08 17:00:16.009947+07	\N	\N	th
em_1xhXR2-i_GLHHGKwxQJWzmbKOHAiF8khOrUDdf4c	966	\N	account_officer	2026-07-08 14:11:25.812128+07	2026-08-07 14:11:25.812128+07	2026-07-08 14:11:31.424668+07	2026-07-08 14:11:29.937654+07	\N	\N	th
HVPpWduUdl2zgL1dNygdnQlOqbSuKHws905FOZHZwUA	948	\N	manager	2026-07-08 14:06:02.769966+07	2026-08-07 14:06:02.769966+07	\N	2026-07-08 14:08:47.594697+07	\N	\N	th
PmD3Erept74gnuX499uh6oHJ3U3IBgoQd1M2SkfAeqk	966	\N	account_officer	2026-07-08 17:11:15.566948+07	2026-08-07 17:11:15.566948+07	2026-07-08 17:11:22.776363+07	2026-07-08 17:11:21.555286+07	\N	\N	th
pT75GJCKd-9J84SkSOK6JSQZVv97fnNpH_i0WnwWcOk	964	\N	it	2026-07-08 16:44:37.212944+07	2026-08-07 16:44:37.212944+07	2026-07-08 16:44:47.23527+07	2026-07-08 16:44:43.245451+07	\N	\N	th
XLGCZMBMD5P18Ybv3cKRU3cannefiz841Hj_goLVQWI	957	\N	supervisor	2026-07-08 17:11:22.774478+07	2026-08-07 17:11:22.774478+07	2026-07-08 17:19:58.654929+07	2026-07-08 17:19:50.756185+07	\N	\N	th
M3eB69S1NSXTLDnFWjB9emsBCefvW5pMKHhskoSYJL0	959	\N	officer	2026-07-08 16:35:37.914622+07	2026-08-07 16:35:37.914622+07	\N	2026-07-08 16:36:45.032441+07	\N	\N	th
YypIRQuVqVTQOy54ACMxyKhGRBYkX3DBj2q5YVl8xn4	959	\N	officer	2026-07-08 16:56:55.939907+07	2026-08-07 16:56:55.939907+07	\N	2026-07-08 16:57:00.364314+07	\N	\N	th
wa2aussQ27oyUvB7LuOCUGgeUHNV_W4CAfz7176C840	966	\N	account_officer	2026-07-08 17:19:58.653552+07	2026-08-07 17:19:58.653552+07	2026-07-08 17:31:00.869251+07	2026-07-08 17:30:57.845209+07	\N	\N	th
oDiylTSzL-Xm7JCg8e1XBM4XpA9i7Pkw5qaLqr_Junw	945	\N	cfo	2026-07-08 14:10:58.995901+07	2026-08-07 14:10:58.995901+07	2026-07-08 14:11:05.071146+07	2026-07-08 14:10:59.766656+07	\N	\N	th
RreL7CqOGJ-tMGGSC9l2VmNfpi4KDh8PvVnnhVOjzPg	945	\N	cfo	2026-07-08 18:11:44.695838+07	2026-08-07 18:11:44.695838+07	2026-07-08 18:11:49.063223+07	2026-07-08 18:11:45.081756+07	\N	\N	th
8Fz2_SUW_-VywPK-hkPH4Y-sVu5s2XVakpYW8fotsG0	968	\N	it	2026-07-08 16:44:47.233318+07	2026-08-07 16:44:47.233318+07	2026-07-08 16:44:51.444081+07	2026-07-08 16:44:47.471823+07	\N	\N	th
NtbSg1dyFhIbYwzPlJew3W9lw0t4BD0AesaxaWao8UI	947	\N	manager	2026-07-08 16:56:55.96325+07	2026-08-07 16:56:55.96325+07	\N	2026-07-08 16:59:00.856119+07	\N	\N	th
BBCMCGw0T1TB7YnMmH7Zos_504EqfKqoa5btbIo9KdA	968	\N	it	2026-07-08 17:00:21.236759+07	2026-08-07 17:00:21.236759+07	2026-07-08 17:00:24.497547+07	2026-07-08 17:00:21.477791+07	\N	\N	th
Whr0H6iQDnyu7OFnp47AZmqo3-w7sqEkAy4o680v8Jk	947	\N	manager	2026-07-08 14:11:05.069885+07	2026-08-07 14:11:05.069885+07	2026-07-08 14:11:10.068892+07	2026-07-08 14:11:05.695302+07	\N	\N	th
0j2LZAhdg5jO05PI85yWIjtIBAPtr_uYfcFWiZcAU-M	957	\N	supervisor	2026-07-08 17:00:44.060074+07	2026-08-07 17:00:44.060074+07	2026-07-08 17:00:55.225889+07	2026-07-08 17:00:48.236859+07	\N	\N	th
d4EYuBb9ZAF8VCVX30Ckcdg0YipcOR_Kvw2Wbsx72zI	951	\N	manager	2026-07-08 17:10:56.978782+07	2026-08-07 17:10:56.978782+07	2026-07-08 17:11:10.681727+07	2026-07-08 17:11:10.315949+07	\N	\N	th
i2nmuw0yP6kCEgdPPdcYwfoGIt4NU_dOsunBsAZXhVM	951	\N	manager	2026-07-08 17:17:40.484423+07	2026-08-07 17:17:40.484423+07	\N	2026-07-08 17:17:49.434288+07	\N	\N	th
KvzxT2G4rnPtMKViPgQPWslb8EkG0yzi8Vp6rkQcOJE	952	\N	accounting_manager	2026-07-08 17:31:03.120725+07	2026-08-07 17:31:03.120725+07	2026-07-08 17:31:23.722367+07	2026-07-08 17:31:22.499511+07	\N	\N	th
wt_izgLBIaQ8j9a9ytqZgmZLLuKS5bu-_SEmRCAdM38	947	\N	manager	2026-07-08 17:16:32.64936+07	2026-08-07 17:16:32.64936+07	\N	2026-07-08 17:18:07.291732+07	\N	\N	th
ZTEmI0xjmxXI7Su5n6ZX8DSG25Fbqvj_crZzHKcOaNA	946	\N	finance	2026-07-08 16:56:55.981009+07	2026-08-07 16:56:55.981009+07	\N	2026-07-08 16:59:35.53605+07	\N	\N	th
VcxbJzvIAtYCSR4k1Q7pUxy7aDJh5v_yh5uTikUjMtE	946	\N	finance	2026-07-08 14:11:10.067615+07	2026-08-07 14:11:10.067615+07	2026-07-08 14:11:14.462465+07	2026-07-08 14:11:10.424044+07	\N	\N	th
B7fCnGX_8YfgZ1n1SBNjeTHAR1qvuEoHEhWcnjgKO-w	954	\N	supervisor	2026-07-08 17:31:23.721078+07	2026-08-07 17:31:23.721078+07	2026-07-08 17:31:31.590562+07	2026-07-08 17:31:27.366478+07	\N	\N	th
mGObJuBUnlpiB5Mz8fyv-LE7BA5qINYsvMN04vmpN5M	959	\N	officer	2026-07-08 15:08:46.123491+07	2026-08-07 15:08:46.123491+07	\N	2026-07-08 15:51:54.291021+07	\N	\N	th
MA0QmlqQscCZWly_lhXIdECev4kC3cCW7TPu3bYCJlc	946	\N	finance	2026-07-08 15:09:28.315882+07	2026-08-07 15:09:28.315882+07	\N	2026-07-08 15:09:28.347713+07	\N	\N	th
LFyoOgKTC4imlyXgiqTOBnW5GwjM7PbH0bs98dg8yr0	964	\N	it	2026-07-08 14:11:31.422936+07	2026-08-07 14:11:31.422936+07	2026-07-08 16:22:54.08938+07	2026-07-08 16:22:50.726174+07	\N	\N	th
YlsvmAJ52gKPAfB7OUasgvVNvywbrfUipDb2MyatJ8k	948	\N	manager	2026-07-08 12:52:12.668257+07	2026-08-07 12:52:12.668257+07	2026-07-08 14:02:51.65176+07	2026-07-08 14:02:45.31138+07	\N	\N	th
qe_a4iw8IFMdafgLUrgtu4HNMbSfKS-KD6Z5v_VSDrY	946	\N	finance	2026-07-08 16:23:18.10111+07	2026-08-07 16:23:18.10111+07	2026-07-08 16:23:52.770045+07	2026-07-08 16:23:47.896277+07	\N	\N	th
0nAUZ8b6NFvrCIfBQU-OW_YKCyKXUKcKTxGYH4pseaU	952	\N	accounting_manager	2026-07-08 14:11:14.460046+07	2026-08-07 14:11:14.460046+07	2026-07-08 14:11:25.813023+07	2026-07-08 14:11:14.925642+07	\N	\N	th
Iv9ZhuPMk6Yp6SjAiuopVe0GHzpwpB06XaO9f9i_5r8	948	\N	manager	2026-07-08 17:31:54.144687+07	2026-08-07 17:31:54.144687+07	2026-07-08 17:32:00.304117+07	2026-07-08 17:31:59.335157+07	\N	\N	th
j964Sc04Q8RoBNLW1060S9ImWM6Hqrxqb9-r0GZ03k8	947	\N	manager	2026-07-08 15:07:05.871635+07	2026-08-07 15:07:05.871635+07	\N	2026-07-08 15:52:45.724694+07	\N	\N	th
o0taCxhg8v568ED4mPP6AKEVReIKGjMI4tCDRBqkMt4	947	\N	manager	2026-07-08 17:05:45.152368+07	2026-08-07 17:05:45.152368+07	\N	2026-07-08 17:07:14.536676+07	\N	\N	th
SRBGkwXhqE5dXYsnpgKdW9KNQOSYI-q0JiY5zv4q4ew	957	\N	supervisor	2026-07-08 16:22:54.087643+07	2026-08-07 16:22:54.087643+07	2026-07-08 16:23:05.042036+07	2026-07-08 16:22:54.731831+07	\N	\N	th
cY5nw3ibABsfiQXGkea59Zk7T2sRooQYFGYGiMoEuwM	951	\N	manager	2026-07-08 16:23:52.766965+07	2026-08-07 16:23:52.766965+07	2026-07-08 16:44:14.376261+07	2026-07-08 16:44:12.814899+07	\N	\N	th
ZFVNMbshIeDYV1c7HrrIUXiQD_Lxd2ZuhaYSWXxykOk	963	\N	officer	2026-07-08 17:11:10.679185+07	2026-08-07 17:11:10.679185+07	2026-07-08 17:11:15.568468+07	2026-07-08 17:11:10.995406+07	\N	\N	th
lCTlxrA1L_RdF2ViQDl_xNhMbR5m7WkploJ0EjJBP-s	951	\N	manager	2026-07-08 16:23:05.039126+07	2026-08-07 16:23:05.039126+07	2026-07-08 16:23:18.102551+07	2026-07-08 16:23:05.886665+07	\N	\N	th
uoIOC5kcftajssZdp9y9mqgxfeyxnnAbXqZrcRmeOMc	957	\N	supervisor	2026-07-08 17:10:27.805039+07	2026-08-07 17:10:27.805039+07	2026-07-08 17:10:56.980508+07	2026-07-08 17:10:54.313291+07	\N	\N	th
9eLLOXU4fw2B3AotR_Db_bx_w4CH5tXcqW5-DtwWM4o	959	\N	officer	2026-07-08 17:05:45.133222+07	2026-08-07 17:05:45.133222+07	\N	2026-07-08 17:05:45.133222+07	\N	\N	th
KXvZQn9Qeg1LgcFB2aeNKGChmwa0qqSWIaNLoWr4OH8	947	\N	manager	2026-07-08 16:35:37.941016+07	2026-08-07 16:35:37.941016+07	\N	2026-07-08 16:35:37.941016+07	\N	\N	th
LyUAxPCUPNpuioZsLHrjtzoKC7TN3pl8aahIfhw9piA	951	\N	manager	2026-07-08 17:00:55.224548+07	2026-08-07 17:00:55.224548+07	2026-07-08 17:10:27.806553+07	2026-07-08 17:10:22.487351+07	\N	\N	th
FnyT0C3jCgTpb--yfRlRkhLdaTbE3pcn8rallBfQptg	964	\N	it	2026-07-08 17:00:24.494607+07	2026-08-07 17:00:24.494607+07	2026-07-08 17:00:44.062317+07	2026-07-08 17:00:32.421066+07	\N	\N	th
CckveRyeFaJc81cipsWbCnFmhGph7v0wWevwGrpCdVM	959	\N	officer	2026-07-08 17:16:32.632219+07	2026-08-07 17:16:32.632219+07	\N	2026-07-08 17:18:53.70387+07	\N	\N	th
IoA2i15PD1ORPM-EKk0ywAaJOKibfAaGFgbFVA9Zd9A	950	\N	manager	2026-07-08 17:31:31.589324+07	2026-08-07 17:31:31.589324+07	2026-07-08 17:31:37.164759+07	2026-07-08 17:31:34.33521+07	\N	\N	th
jbrbF2RBOGUGkF68-QpuM6j3GVghaW99wAxHY3f_tmY	966	\N	account_officer	2026-07-08 17:22:43.214151+07	2026-08-07 17:22:43.214151+07	\N	2026-07-08 17:36:40.090581+07	\N	\N	th
AW_NLMr7C5W8rfZiPeZFAccT6ohy9qXX2SbIj2ZfeQI	957	\N	supervisor	2026-07-08 17:31:46.16751+07	2026-08-07 17:31:46.16751+07	2026-07-08 17:31:54.146317+07	2026-07-08 17:31:52.833407+07	\N	\N	th
SOX7fOHW8QJd0y1QquBkPiDzEdn8AjBTSWhXEJBsuFM	965	\N	account_officer	2026-07-08 17:32:02.637396+07	2026-08-07 17:32:02.637396+07	2026-07-08 17:33:07.946442+07	2026-07-08 17:33:03.582388+07	\N	\N	th
tATRGE5pHA7VNJPpqFcCrVsncDy81CxR1YuCA4ie5mE	963	\N	officer	2026-07-08 17:31:00.866598+07	2026-08-07 17:31:00.866598+07	2026-07-08 17:31:03.122205+07	2026-07-08 17:31:02.323179+07	\N	\N	th
LWVe4Fs1Du6v0A37abS6IjBSfLaHvNMxX7HSijDrlws	953	\N	manager	2026-07-08 17:32:00.299099+07	2026-08-07 17:32:00.299099+07	2026-07-08 17:32:02.638774+07	2026-07-08 17:32:00.54236+07	\N	\N	th
tSu1p5TMhu9H_aaDNK0kTahfRYKHMFqdmY6jqIRGouo	951	\N	manager	2026-07-08 17:31:37.162135+07	2026-08-07 17:31:37.162135+07	2026-07-08 17:31:46.169515+07	2026-07-08 17:31:43.335713+07	\N	\N	th
posvpPtC0DSvsNoyIF_86hmQa-xtGvEiql0k_uyxcdc	957	\N	supervisor	2026-07-08 17:33:07.944181+07	2026-08-07 17:33:07.944181+07	2026-07-08 17:39:43.153898+07	2026-07-08 17:39:34.329474+07	\N	\N	th
ZxivOrcprjpMCWADaeI-6YRcQBV3-XIApW13v8XczjE	951	\N	manager	2026-07-08 17:39:43.150932+07	2026-08-07 17:39:43.150932+07	2026-07-08 17:39:52.2882+07	2026-07-08 17:39:50.343008+07	\N	\N	th
NrSJRGiO39F8yi2bVHIxc4hEr8se3MnQSqEkaUIgKjs	957	\N	supervisor	2026-07-08 17:40:05.213779+07	2026-08-07 17:40:05.213779+07	2026-07-08 17:40:10.45438+07	2026-07-08 17:40:06.33887+07	\N	\N	th
V1PML8312Cc8lNzT-b80wZ6c3t8ezQ7VBNP8Hyata08	953	\N	manager	2026-07-08 17:39:52.287076+07	2026-08-07 17:39:52.287076+07	2026-07-08 17:40:05.215403+07	2026-07-08 17:40:00.320424+07	\N	\N	th
gLNLja846o1RxgHsujbzs9hSqYF4yzs0i7Odv0dsJQg	951	\N	manager	2026-07-08 17:40:10.45186+07	2026-08-07 17:40:10.45186+07	2026-07-08 17:40:42.320018+07	2026-07-08 17:40:38.499732+07	\N	\N	th
uPt7-Ek-bLAFoBsdC_FBOwIXL2WTjH_kNmAgHVYy0d8	963	\N	officer	2026-07-08 19:28:46.231698+07	2026-08-07 19:28:46.231698+07	2026-07-08 19:29:06.341615+07	2026-07-08 19:29:01.459219+07	\N	\N	th
JwDRpun7NvTvHcShz4HxrSON6E4_sRIVI0oZvlDRVxg	946	\N	finance	2026-07-09 08:30:33.754533+07	2026-08-08 08:30:33.754533+07	\N	2026-07-09 09:45:16.166952+07	\N	\N	th
vUy0UYlpumSNS0CQ5-VUyC6uOwZZlazNwbyAIy90cJI	946	\N	finance	2026-07-08 19:28:34.079463+07	2026-08-07 19:28:34.079463+07	2026-07-08 19:28:46.23339+07	2026-07-08 19:28:43.211713+07	\N	\N	th
Dnf-oPQ1-Dn8r73i7ozrCvak6Lo9aCmDUzvUEXowlMM	944	\N	ceo	2026-07-08 18:42:40.429209+07	2026-08-07 18:42:40.429209+07	\N	2026-07-08 18:42:45.112687+07	\N	\N	th
9mvHwx_VtVl4X3lNfqShSS-AHmpvnBg9xH46oj6tZpA	948	\N	manager	2026-07-08 17:42:37.965595+07	2026-08-07 17:42:37.965595+07	2026-07-08 17:42:40.3373+07	2026-07-08 17:42:39.342066+07	\N	\N	th
MBxSRh2QYhrx1GV0Yb_QnowKp-RVCpdpuqlwHzgGQ48	952	\N	accounting_manager	2026-07-08 17:42:46.063686+07	2026-08-07 17:42:46.063686+07	2026-07-08 18:11:39.405161+07	2026-07-08 18:11:34.785764+07	\N	\N	th
Ctlyl0sycLrwiPs11NxkyXtJ0Ke2w70NIxQBj_rJoxw	953	\N	manager	2026-07-08 17:40:42.317428+07	2026-08-07 17:40:42.317428+07	2026-07-08 17:40:49.553167+07	2026-07-08 17:40:47.336733+07	\N	\N	th
oGcxbYlE1tsi7rl8Ngd64Sf7PBWBamt2vUBLWLavSxM	945	\N	cfo	2026-07-09 14:47:34.099062+07	2026-08-08 14:47:34.099062+07	2026-07-09 14:47:35.764425+07	2026-07-09 14:47:34.427031+07	\N	\N	th
f0NOLnoG54kU29VA-YJme9akAxG2spjz4tCAeMeYw-o	955	\N	account_supervisor	2026-07-08 17:41:29.597472+07	2026-08-07 17:41:29.597472+07	2026-07-08 17:42:01.39652+07	2026-07-08 17:41:58.431474+07	\N	\N	th
-JYuRSARs6BFi9c726BiLO3vxOPHBaRXaSl9MDaIuT0	948	\N	manager	2026-07-08 18:11:39.40233+07	2026-08-07 18:11:39.40233+07	2026-07-08 18:11:44.699739+07	2026-07-08 18:11:40.104675+07	\N	\N	th
nIdJgg3SG8-HmjOUd0olCiB9bN9bBR0wna8qxPWYBm4	959	\N	officer	2026-07-09 14:47:38.870847+07	2026-08-08 14:47:38.870847+07	2026-07-09 14:47:41.126568+07	2026-07-09 14:47:39.171352+07	\N	\N	th
Z2RsejKgXYYFoyvBb_eboU5UoqM1fTGgFgGesgAFonA	944	\N	ceo	2026-07-08 18:43:29.751708+07	2026-08-07 18:43:29.751708+07	\N	2026-07-08 18:43:29.789596+07	\N	\N	th
UgujHhI3gvow3P-P7lcQLf2OauTwbhEew2nVajIRau4	955	\N	account_supervisor	2026-07-08 17:40:49.551152+07	2026-08-07 17:40:49.551152+07	2026-07-08 17:40:56.415162+07	2026-07-08 17:40:54.337891+07	\N	\N	th
3tjmpMS-APFnaUu_S7FtImPWoSofEv0Fpvbt8RZ_mz8	948	\N	manager	2026-07-09 00:46:50.521469+07	2026-08-08 00:46:50.521469+07	2026-07-09 00:47:02.457982+07	2026-07-09 00:46:59.152046+07	\N	\N	th
UPKvsXnNkDQ3q1l3R5KIhoWTL8WVrvUqkb8aZc0GFiw	953	\N	manager	2026-07-08 17:42:40.336287+07	2026-08-07 17:42:40.336287+07	2026-07-08 17:42:46.065305+07	2026-07-08 17:42:40.570255+07	\N	\N	th
SLqvgIetk-f9eMV59ubk8hKuzyxP0rIB-plYgfbhb_4	952	\N	accounting_manager	2026-07-08 23:58:21.250799+07	2026-08-07 23:58:21.250799+07	\N	2026-07-09 00:11:50.710329+07	\N	\N	th
mmHyh9OBn4N3o5Xhsxx3wBtIVHT8Gk7PVIcIlW2t_OY	944	\N	ceo	2026-07-10 13:27:46.155158+07	2026-08-09 13:27:46.155158+07	\N	2026-07-10 13:31:26.340633+07	\N	\N	th
HaaK6k4SaVYeKLLwdkxpILPLWN6xwvI_htucsSox_qY	966	\N	account_officer	2026-07-08 18:52:49.0629+07	2026-08-07 18:52:49.0629+07	2026-07-08 18:53:54.514346+07	2026-07-08 18:53:49.61382+07	\N	\N	th
1YMwC2XkZqjXY0jIrenxTAnswL6BF73ls5DKfYFgNyg	967	\N	account_officer	2026-07-08 18:56:20.077092+07	2026-08-07 18:56:20.077092+07	2026-07-08 18:56:24.427671+07	2026-07-08 18:56:23.057818+07	\N	\N	th
wZ67LUajDVrS9XdkR3-NTP9NA5ArkPi4mFVl_EbS55M	948	\N	manager	2026-07-08 18:11:49.061607+07	2026-08-07 18:11:49.061607+07	2026-07-08 18:11:50.845293+07	2026-07-08 18:11:49.921393+07	\N	\N	th
Fk6FdR2IpR7SeCIvse2mX6gA8BcEaif-yvN5O4IUjGg	946	\N	finance	2026-07-09 14:53:56.827898+07	2026-08-08 14:53:56.827898+07	2026-07-09 14:54:30.764782+07	2026-07-09 14:54:29.61143+07	\N	\N	th
cR1WsOhVx469l5m7FN_WOdvDVcYaEQwM_XU8lUizEpM	968	\N	it	2026-07-08 19:13:34.059612+07	2026-08-07 19:13:34.059612+07	2026-07-08 19:26:11.633477+07	2026-07-08 19:26:06.576666+07	\N	\N	th
gzTiP7WHaIUyD3uIhdDqqtwGT8WuwdoRlj4E2hvCYL8	946	\N	finance	2026-07-08 18:17:44.60956+07	2026-08-07 18:17:44.60956+07	2026-07-08 18:28:57.919893+07	2026-07-08 18:28:45.364057+07	\N	\N	th
EDHjH1Tr0aytcllOHE4mj4RCDdrLn3DSyXzVHCzfU6c	965	\N	account_officer	2026-07-08 17:40:56.41276+07	2026-08-07 17:40:56.41276+07	2026-07-08 17:41:15.548426+07	2026-07-08 17:41:10.469985+07	\N	\N	th
3yI-GHstBPiZBG4YcJY4cXII_PCwXdN0sUmhWINHotk	953	\N	manager	2026-07-09 17:32:27.858602+07	2026-08-08 17:32:27.858602+07	2026-07-09 17:32:57.342086+07	2026-07-09 17:32:51.480966+07	\N	\N	th
ESyl_ezNyFj0dLO0V-61Z3rJUeiOJgPrYFk7_iPHbTo	946	\N	finance	2026-07-08 18:11:50.842786+07	2026-08-07 18:11:50.842786+07	2026-07-08 18:17:38.268791+07	2026-07-08 18:17:33.320971+07	\N	\N	th
9BFnYSlpjYytlf64GAyeSHfPZ9xFjs5zQl6exmDieDg	944	\N	ceo	2026-07-08 18:42:38.07773+07	2026-08-07 18:42:38.07773+07	\N	2026-07-08 18:42:38.07773+07	\N	\N	th
IKliwv_z2MvOZTTJQKVzEhE1VbsF0FnyZBMpktL7DMM	945	\N	cfo	2026-07-08 18:56:24.424466+07	2026-08-07 18:56:24.424466+07	2026-07-08 19:13:34.061941+07	2026-07-08 19:13:23.900263+07	\N	\N	th
JmaUcn4TOXtpfhHa2RfMxF5vj1beqQWKfUu7mesZ4Cw	961	\N	officer	2026-07-08 18:17:38.267979+07	2026-08-07 18:17:38.267979+07	2026-07-08 18:17:42.042705+07	2026-07-08 18:17:38.468858+07	\N	\N	th
n4X5gz_dHdi7b71DBdu68TkQkP-uKIryk_bOJTVPvAc	950	\N	manager	2026-07-08 17:41:15.546566+07	2026-08-07 17:41:15.546566+07	2026-07-08 17:41:23.39437+07	2026-07-08 17:41:19.344691+07	\N	\N	th
IabHUHIU9dKnhJyQy3XpNgtWmatRe_LNuiC4l3j7lX4	966	\N	account_officer	2026-07-08 18:28:57.918337+07	2026-08-07 18:28:57.918337+07	2026-07-08 18:34:53.846215+07	2026-07-08 18:34:53.328981+07	\N	\N	th
sxpRjYyemy2XSuE8NV58b8niHmrCIwMaGTXYc7u186A	968	\N	it	2026-07-09 00:47:02.455439+07	2026-08-08 00:47:02.455439+07	2026-07-09 13:52:37.746947+07	2026-07-09 13:52:37.524992+07	\N	\N	th
O8Uk6y5C9cT4wqJNM-BRxAX6t3VERsJQ9IFZZ5TqIJ4	945	\N	cfo	2026-07-08 19:29:13.154935+07	2026-08-07 19:29:13.154935+07	2026-07-08 19:30:14.072602+07	2026-07-08 19:30:05.498388+07	\N	\N	th
PlTTxg0UgcWh2k29acf83fQj0ZkdnB3TEYsrZ1Dic8Q	952	\N	accounting_manager	2026-07-08 17:42:01.385978+07	2026-08-07 17:42:01.385978+07	2026-07-08 17:42:34.502035+07	2026-07-08 17:42:31.982927+07	\N	\N	th
lHbbL2IGKwCG7-RUgbmwyI91N0cgfJh2W4derfwLJys	948	\N	manager	2026-07-08 18:17:42.03943+07	2026-08-07 18:17:42.03943+07	2026-07-08 18:17:44.611184+07	2026-07-08 18:17:42.251236+07	\N	\N	th
N8xvIyx3MOwB7YnlyloVmfADOlRCjcTgULW1aHy2lVY	951	\N	manager	2026-07-08 17:41:23.391312+07	2026-08-07 17:41:23.391312+07	2026-07-08 17:41:29.600013+07	2026-07-08 17:41:26.369904+07	\N	\N	th
p9DUJCrHTKvZ83WdczRLeYfYEySGfZagb2eKC8KqviA	964	\N	it	2026-07-08 18:53:54.511489+07	2026-08-07 18:53:54.511489+07	2026-07-08 18:54:13.27225+07	2026-07-08 18:54:04.882046+07	\N	\N	th
PKfEh8xUo6jQYa0k7rQ1bnRzCbpXnZGUHHtnz2Us7jc	952	\N	accounting_manager	2026-07-08 17:50:24.211528+07	2026-08-07 17:50:24.211528+07	\N	2026-07-08 17:50:24.498436+07	\N	\N	th
J2cfMVSJxJ6-ctKLLXQU_KBrMWcEZSU1Uz60IhukTAQ	946	\N	finance	2026-07-08 17:42:34.499291+07	2026-08-07 17:42:34.499291+07	2026-07-08 17:42:37.967721+07	2026-07-08 17:42:34.853626+07	\N	\N	th
384Vwobvoi5vkmNXVXx4nuBu2dxWZPtG2KARMP2fO8s	949	\N	hr_manager	2026-07-08 18:54:13.230206+07	2026-08-07 18:54:13.230206+07	2026-07-08 18:56:18.00522+07	2026-07-08 18:56:07.945207+07	\N	\N	th
WTfhOPbGD7S4YNtldq_41rzwkKsNu6JmVjRcGQTA6wE	952	\N	accounting_manager	2026-07-09 13:52:42.59992+07	2026-08-08 13:52:42.59992+07	2026-07-09 14:20:11.833652+07	2026-07-09 14:20:10.4616+07	\N	\N	th
ep569vFwiuhkdFelLAJ21yYaaPuBpNOpTZ34DnCrl5Q	957	\N	supervisor	2026-07-08 19:26:11.632076+07	2026-08-07 19:26:11.632076+07	2026-07-08 19:26:16.281602+07	2026-07-08 19:26:11.827859+07	\N	\N	th
pLggRLnPNk6-N6SEJfIY5rX85mx83Idwa1ax0wYea6c	968	\N	it	2026-07-09 13:15:11.943027+07	2026-08-08 13:15:11.943027+07	\N	2026-07-09 13:15:11.943027+07	\N	\N	th
IV6UEoSxj8OPqVlMf6O1cRLKIv9Gqabhum_GK5grZG4	944	\N	ceo	2026-07-08 18:56:18.002795+07	2026-08-07 18:56:18.002795+07	2026-07-08 18:56:20.078213+07	2026-07-08 18:56:19.333732+07	\N	\N	th
2_2ZaJTT9-2zSML8aB-IJnRbABuof7eu46v3FdCRlpw	968	\N	it	2026-07-08 18:34:53.844697+07	2026-08-07 18:34:53.844697+07	2026-07-08 18:52:49.065644+07	2026-07-08 18:52:48.394422+07	\N	\N	th
wCQn04uz1LSRFmfCAtgR-rcNMK3bE_xzzr0jn5OxvMQ	955	\N	account_supervisor	2026-07-08 19:26:24.554343+07	2026-08-07 19:26:24.554343+07	2026-07-08 19:28:34.0811+07	2026-07-08 19:28:27.921991+07	\N	\N	th
Asa4AW24FU5UJy5buAAvaF-dTBUPM37ohPuZBU3m1YQ	946	\N	finance	2026-07-08 19:29:06.339916+07	2026-08-07 19:29:06.339916+07	2026-07-08 19:29:13.157209+07	2026-07-08 19:29:07.714832+07	\N	\N	th
D64XavaxTDVOmNLkZOc6neLu7KHD4CwCqxGtvq1Ey-s	951	\N	manager	2026-07-08 19:26:16.28+07	2026-08-07 19:26:16.28+07	2026-07-08 19:26:24.556688+07	2026-07-08 19:26:21.719492+07	\N	\N	th
evY6KQRh96ABOl6l7fnYW8UlZwHlqskcWvxyepvEITg	968	\N	it	2026-07-08 19:30:14.071002+07	2026-08-07 19:30:14.071002+07	2026-07-08 22:20:13.917406+07	2026-07-08 22:20:04.762473+07	\N	\N	th
WKivqgvKTYmQi8qVP7-8c1TIhvxKPJyrCMnj8wfsT_U	948	\N	manager	2026-07-09 13:52:37.744571+07	2026-08-08 13:52:37.744571+07	2026-07-09 13:52:42.601422+07	2026-07-09 13:52:39.453222+07	\N	\N	th
Nndw8A2VdyXGURKUKbCtg-nPs8gNyk7whboBwzm0D5Y	952	\N	accounting_manager	2026-07-09 11:38:59.424645+07	2026-08-08 11:38:59.424645+07	\N	2026-07-09 11:39:33.726558+07	\N	\N	th
gJiWLZscaK7DqSPqTxVSFpeXcQ6fpSIyXnalpERd5iw	946	\N	finance	2026-07-08 22:20:13.915846+07	2026-08-07 22:20:13.915846+07	2026-07-09 00:46:50.523436+07	2026-07-09 00:46:47.501195+07	\N	\N	th
QnbnDeB2YpFdCK3u2zRE0gxMZH7qwx6ti75SPMvcmAw	964	\N	it	2026-07-09 11:45:16.116105+07	2026-08-08 11:45:16.116105+07	\N	2026-07-09 11:45:17.243127+07	\N	\N	th
7Fh4lXZdSPYhdFJ3O23A1sLpwRciTV-0i8VMKpqMQO8	945	\N	cfo	2026-07-09 14:20:11.830045+07	2026-08-08 14:20:11.830045+07	2026-07-09 14:20:15.183607+07	2026-07-09 14:20:12.280282+07	\N	\N	th
w8t0HYn9Huz0YNchsukELes5WhG_2UtOO43Fkxk2L-4	947	\N	manager	2026-07-09 14:20:15.180386+07	2026-08-08 14:20:15.180386+07	2026-07-09 14:20:19.113432+07	2026-07-09 14:20:16.476032+07	\N	\N	th
vgJDvfEr6Dgjc2_ja1mr3itScLcXosETli07ZaDPeM0	944	\N	ceo	2026-07-09 08:32:12.124329+07	2026-08-08 08:32:12.124329+07	\N	2026-07-09 09:21:19.910947+07	\N	\N	th
2jz1SddxNz8HwglLrH68T_ACqDA1Y76hWSN6a-qgqNs	947	\N	manager	2026-07-09 13:47:30.889903+07	2026-08-08 13:47:30.889903+07	\N	2026-07-09 14:14:12.807353+07	\N	\N	th
IFeQC9X1reC126dDXU6_qh2CiYuOdqiyfc0acCweK8w	968	\N	it	2026-07-09 13:15:14.990323+07	2026-08-08 13:15:14.990323+07	\N	2026-07-09 13:20:11.33969+07	\N	\N	th
mTf65PK5EYL6oPkCKx9SydT6jopaNens1FPoHBaxEcY	964	\N	it	2026-07-09 11:43:49.485653+07	2026-08-08 11:43:49.485653+07	\N	2026-07-09 11:43:49.513908+07	\N	\N	th
BWjAlv1YBFaEadkh2X_Lezk8Ox9wQw9V6H5voywwGKQ	968	\N	it	2026-07-09 11:56:14.851335+07	2026-08-08 11:56:14.851335+07	\N	2026-07-09 12:40:39.843316+07	\N	\N	th
jnCfDqk54QxkrkKa490T47c6Kfqvw-ISHucHwTF_skw	968	\N	it	2026-07-09 13:15:06.089015+07	2026-08-08 13:15:06.089015+07	\N	2026-07-09 13:15:06.089015+07	\N	\N	th
E541HOMDEHs2kVOcme2N5QXsa-rBqtbYAi25FUSsPQE	964	\N	it	2026-07-09 14:20:19.111451+07	2026-08-08 14:20:19.111451+07	2026-07-09 14:20:25.266101+07	2026-07-09 14:20:24.832131+07	\N	\N	th
GWWQITs4cWLEQs1FSo0IVohNgolV5fPwveGqxhobDLY	968	\N	it	2026-07-09 14:20:25.263255+07	2026-08-08 14:20:25.263255+07	2026-07-09 14:20:36.028761+07	2026-07-09 14:20:32.468529+07	\N	\N	th
1JSoM9gcpfqYF99TpVU6KfTUF7Q0JKQwg7cKsfHcr0Q	966	\N	account_officer	2026-07-09 17:53:44.175951+07	2026-08-08 17:53:44.175951+07	2026-07-09 19:12:29.886577+07	2026-07-09 19:12:29.535635+07	\N	\N	th
cxAsy1ay0UnqDmmlF6bZ2W3PSMSsFpxF2P7Kz3vK0o4	950	\N	manager	2026-07-09 14:47:46.575239+07	2026-08-08 14:47:46.575239+07	2026-07-09 14:53:56.829428+07	2026-07-09 14:53:44.951863+07	\N	\N	th
7D9VI_nrH-8iNn4zs5x2xEPX2p9LX07DF0vP1VUqyFs	968	\N	it	2026-07-09 23:35:10.652365+07	2026-08-08 23:35:10.652365+07	2026-07-09 23:35:23.301947+07	2026-07-09 23:35:16.983719+07	\N	\N	th
brASEgw7nrr-AczKxTSxhU6SQiwdUIf3O1kEz0ZXB98	944	\N	ceo	2026-07-10 13:13:26.355391+07	2026-08-09 13:13:26.355391+07	\N	2026-07-10 13:15:04.822737+07	\N	\N	th
AgFy7Ut5Fi2U1IOfw-OZTdu1Ekh-Jl95wa10BrsProE	945	\N	cfo	2026-07-09 17:51:19.101001+07	2026-08-08 17:51:19.101001+07	2026-07-09 17:51:57.932913+07	2026-07-09 17:51:53.50129+07	\N	\N	th
OfBuBfCdwQVoICGRvT7SdncfH9-oiXVacN8zu_wNcSY	954	\N	supervisor	2026-07-09 22:10:53.734979+07	2026-08-08 22:10:53.734979+07	2026-07-09 22:11:07.557192+07	2026-07-09 22:10:59.640073+07	\N	\N	th
cIzApLhFKb3mzSUfIr1itZJ2ycw33TEwUynzD1zDG9w	967	\N	account_officer	2026-07-09 22:35:02.030708+07	2026-08-08 22:35:02.030708+07	2026-07-09 22:35:47.142729+07	2026-07-09 22:35:40.730724+07	\N	\N	th
yDJ-IJLiOXorMvEDF6eAJ74ukXGj-EA4KMZ6ANiWFvk	946	\N	finance	2026-07-09 22:36:40.660904+07	2026-08-08 22:36:40.660904+07	2026-07-09 23:07:07.824504+07	2026-07-09 23:07:02.577264+07	\N	\N	th
ssZ6AGY8-0FmE8jG2Iv2l3dJcgVXQnYlBwEb9g4-4Dg	944	\N	ceo	2026-07-10 13:31:26.176768+07	2026-08-09 13:31:26.176768+07	\N	2026-07-10 13:32:08.458332+07	\N	\N	th
uT4zOTsZHwWyg41PP5G6dfW3m2Hh85q-yeTiivwzr-Y	966	\N	account_officer	2026-07-09 17:50:04.925738+07	2026-08-08 17:50:04.925738+07	2026-07-09 17:51:17.446924+07	2026-07-09 17:51:07.012571+07	\N	\N	th
dVZoT9PDh1HMhbqaqa1vanK_HEdDZKasRldA2yvyq9A	946	\N	finance	2026-07-09 16:37:06.799562+07	2026-08-08 16:37:06.799562+07	2026-07-09 16:59:50.499625+07	2026-07-09 16:59:46.633078+07	\N	\N	th
BOxCYY9GUwPBNip828nj1o_spBre_tXnACsYrhSvnTc	952	\N	accounting_manager	2026-07-09 14:20:36.026241+07	2026-08-08 14:20:36.026241+07	2026-07-09 14:47:34.102788+07	2026-07-09 14:47:33.505917+07	\N	\N	th
B85Wx5Ivh6RJyHc0Dx5EJbISF087TOK3aRQMhTI1BMk	955	\N	account_supervisor	2026-07-09 22:22:00.96828+07	2026-08-08 22:22:00.96828+07	2026-07-09 22:22:30.823094+07	2026-07-09 22:22:27.117848+07	\N	\N	th
Z_vSpU4GjWsc0my7ZofbEoW8Dapxfg3Foscj8f-XcrE	944	\N	ceo	2026-07-11 04:32:49.54066+07	2026-08-10 04:32:49.54066+07	\N	2026-07-11 04:32:49.54066+07	\N	\N	th
2Kdhen8RCGY2tjyLjZpgBAHSVUQDf-WypVyfMjrQ01Q	950	\N	manager	2026-07-09 22:11:07.554098+07	2026-08-08 22:11:07.554098+07	2026-07-09 22:11:14.919064+07	2026-07-09 22:11:14.705366+07	\N	\N	th
c0qyBMVmtCVPqordFIgDmAmsN5-6VpGNRXBcagBQEWE	947	\N	manager	2026-07-09 17:51:17.441643+07	2026-08-08 17:51:17.441643+07	2026-07-09 17:51:19.103616+07	2026-07-09 17:51:17.47398+07	\N	\N	th
Kn-rEetLsqPEMNJtlfNtxGNZiqlmhY9N3tAeBCxHK6Q	944	\N	ceo	2026-07-09 14:47:35.763409+07	2026-08-08 14:47:35.763409+07	2026-07-09 14:47:38.872963+07	2026-07-09 14:47:35.940778+07	\N	\N	th
Bo0DkgqIIxhZENWpENMWHffroUoDoKZWC9W2P32p_jE	957	\N	supervisor	2026-07-09 23:35:04.860113+07	2026-08-08 23:35:04.860113+07	2026-07-09 23:35:10.654223+07	2026-07-09 23:35:04.959985+07	\N	\N	th
-8d2HFG5WDuCqI0_hPvRfiH0P0Cr2MEkHhiXnDFHFsI	964	\N	it	2026-07-10 11:39:47.275869+07	2026-08-09 11:39:47.275869+07	2026-07-10 11:40:46.938075+07	2026-07-10 11:40:33.509551+07	\N	\N	th
-ROjmrH7WzTuRA8Q9sgAevNrjoQcFg5VtdkwiLDqfHw	946	\N	finance	2026-07-10 12:15:26.111971+07	2026-08-09 12:15:26.111971+07	2026-07-10 12:15:31.937137+07	2026-07-10 12:15:26.447589+07	\N	\N	th
NUvMqFIVwbuC2gUR1vQPm0dU5xD4SM_e34x1KHYbtvY	945	\N	cfo	2026-07-10 18:06:33.923628+07	2026-08-09 18:06:33.923628+07	2026-07-10 18:06:36.571597+07	2026-07-10 18:06:34.20009+07	\N	\N	th
IZuYPKBH0EF5QapoQycKI92GJi_gmr23Cg1fxaFQWRM	944	\N	ceo	2026-07-11 04:35:59.157844+07	2026-08-10 04:35:59.157844+07	\N	2026-07-11 04:35:59.157844+07	\N	\N	th
G8Gbt5JIRth6ewaabH99GNB4zv-NSSET8kMo4qgHJFk	951	\N	manager	2026-07-10 11:28:07.094348+07	2026-08-09 11:28:07.094348+07	2026-07-10 11:39:47.280096+07	2026-07-10 11:39:43.084085+07	\N	\N	th
PbXX6YNN8uXkzzZVB4yjvxD4o1wGPqI6iCL5Qy4JoBs	946	\N	finance	2026-07-09 14:47:41.125359+07	2026-08-08 14:47:41.125359+07	2026-07-09 14:47:46.576249+07	2026-07-09 14:47:42.156518+07	\N	\N	th
XoEHSXTA2cqJL9xhwkmei094JRnKnOis9jGKn3GwAE8	966	\N	account_officer	2026-07-09 18:13:33.898234+07	2026-08-08 18:13:33.898234+07	\N	2026-07-09 19:03:38.423734+07	\N	\N	th
yCgaH94rc0EsNjp_1rGA1krZr5PWvVfE0EnM57J-i8U	950	\N	manager	2026-07-10 12:15:08.204172+07	2026-08-09 12:15:08.204172+07	2026-07-10 12:15:14.435157+07	2026-07-10 12:15:11.336765+07	\N	\N	th
O_kr9Txy7FXeOM9dxhEwH2C2nnM-XDL5f848Bmq4wBQ	952	\N	accounting_manager	2026-07-09 22:35:47.139934+07	2026-08-08 22:35:47.139934+07	2026-07-09 22:36:11.330423+07	2026-07-09 22:36:09.114193+07	\N	\N	th
vwoRPSuynpxjDmpnrLg2TTx0c_TCpfCQzfrvnXdGTWw	962	\N	hr	2026-07-09 17:43:16.871173+07	2026-08-08 17:43:16.871173+07	2026-07-09 17:49:34.921136+07	2026-07-09 17:49:32.301667+07	\N	\N	th
dWJ0MXFf3iZZrmvI2K6EKjJ9ZHlDARNK6TLe-dbYTWY	951	\N	manager	2026-07-09 19:29:54.228276+07	2026-08-08 19:29:54.228276+07	2026-07-09 22:10:37.346828+07	2026-07-09 22:10:36.694753+07	\N	\N	th
wrGpi8mV7tUelKnUQTG3Hjyu3dhJ5lah4XxuPvwbTvA	963	\N	officer	2026-07-09 17:49:34.918921+07	2026-08-08 17:49:34.918921+07	2026-07-09 17:49:44.345812+07	2026-07-09 17:49:38.497784+07	\N	\N	th
UhzAHYMI-j415g-yldfd0lwdaPmW8JPuR0W4ZvImVlA	951	\N	manager	2026-07-09 22:11:14.917547+07	2026-08-08 22:11:14.917547+07	2026-07-09 22:21:49.88592+07	2026-07-09 22:21:48.701199+07	\N	\N	th
vCCaRewJETINOe6OFLp6Ts0eM0MpEzwN4szPxqxUVhQ	945	\N	cfo	2026-07-09 22:10:37.344682+07	2026-08-08 22:10:37.344682+07	2026-07-09 22:10:46.102464+07	2026-07-09 22:10:44.509312+07	\N	\N	th
IZcHfVLh8DOHZNrRBZNda5dd5XwmeCXaQdhKIT5Pyd4	952	\N	accounting_manager	2026-07-09 22:22:30.820888+07	2026-08-08 22:22:30.820888+07	2026-07-09 22:35:02.033517+07	2026-07-09 22:34:53.725616+07	\N	\N	th
uD2eOpvbTREoS4ThwYqFZEGDyjFaJL3DXRl7TvwpmzI	952	\N	accounting_manager	2026-07-09 23:07:07.821522+07	2026-08-08 23:07:07.821522+07	2026-07-09 23:07:22.749486+07	2026-07-09 23:07:17.669611+07	\N	\N	th
XSmezr57H77EFZLff7CbxKAR3Bs3NSRHycYp-tR0-Cc	952	\N	accounting_manager	2026-07-09 17:32:57.340442+07	2026-08-08 17:32:57.340442+07	2026-07-09 17:43:16.872951+07	2026-07-09 17:43:15.677454+07	\N	\N	th
4iouTHcGVdfSvEJuKRMUXNNCWgKc7tkDLYhkKQ1LElM	944	\N	ceo	2026-07-09 22:10:46.0978+07	2026-08-08 22:10:46.0978+07	2026-07-09 22:10:49.672957+07	2026-07-09 22:10:46.241196+07	\N	\N	th
6frk8snE3JAvs9KAhp9J95K4NmlL3DgruyrCW6f549M	944	\N	CEO	2026-07-12 10:08:51.772415+07	2026-08-11 10:08:51.772415+07	\N	2026-07-12 10:08:51.772415+07	\N	\N	th
eCLWghMPqq2Xs6L9XHjS1IgSuMHyaYw_X_ekyXMKJ-k	946	\N	finance	2026-07-09 17:49:44.34409+07	2026-08-08 17:49:44.34409+07	2026-07-09 17:49:59.426409+07	2026-07-09 17:49:54.511813+07	\N	\N	th
GmrN6PieyPnqDSiUyJrYjfffOPRjgg87JpoKu4w3tls	946	\N	finance	2026-07-09 22:21:49.883412+07	2026-08-08 22:21:49.883412+07	2026-07-09 22:21:56.820911+07	2026-07-09 22:21:49.964034+07	\N	\N	th
RpdTqKQQC5ctc20shxqcigkTg8PyiTWxJ9G21ZoXsgc	964	\N	it	2026-07-09 19:12:42.523456+07	2026-08-08 19:12:42.523456+07	2026-07-09 19:29:54.229277+07	2026-07-09 19:29:49.045307+07	\N	\N	th
3J59zgsGqibTNSR259At5UZihVXZSy7phJ3Q9WLXCrI	968	\N	it	2026-07-09 16:59:50.497762+07	2026-08-08 16:59:50.497762+07	2026-07-09 17:32:27.860107+07	2026-07-09 17:32:25.406906+07	\N	\N	th
VfKjsr5LAy44sm4qaB4noUg_Sv_jaU3fM7jHbEEAhoE	968	\N	it	2026-07-09 14:54:30.762968+07	2026-08-08 14:54:30.762968+07	2026-07-09 16:37:06.801293+07	2026-07-09 16:37:04.667966+07	\N	\N	th
f5D32iFv7FsPxbS730A1cPw8oVpOEBwNiy4X9R6z6gk	947	\N	manager	2026-07-09 22:10:49.671083+07	2026-08-08 22:10:49.671083+07	2026-07-09 22:10:53.738677+07	2026-07-09 22:10:52.653356+07	\N	\N	th
jAlGMLc_8ZbK9oVMdnpcsE237dy_JdJKCIpBb1rwSBY	948	\N	manager	2026-07-09 17:49:59.42488+07	2026-08-08 17:49:59.42488+07	2026-07-09 17:50:04.927077+07	2026-07-09 17:50:01.502106+07	\N	\N	th
4LgxYw6XUP-usqirOxt_VL4KjJf_cAJXztiAq5QsRzQ	964	\N	it	2026-07-09 23:35:23.298765+07	2026-08-08 23:35:23.298765+07	2026-07-10 11:28:07.096032+07	2026-07-10 11:28:00.399734+07	\N	\N	th
LTf1PccDVHxoLWCrk-IegO1_cPiU1IjJniL2Vk-yH_E	962	\N	hr	2026-07-09 17:51:57.930006+07	2026-08-08 17:51:57.930006+07	2026-07-09 17:53:44.179325+07	2026-07-09 17:53:43.584346+07	\N	\N	th
BDoZtB8ag5AdhxArEkiAw5zfY9-t31-KSxK2t0hX-ME	948	\N	manager	2026-07-09 22:21:56.818049+07	2026-08-08 22:21:56.818049+07	2026-07-09 22:22:00.970605+07	2026-07-09 22:21:56.957525+07	\N	\N	th
qQXlJImBF7DH2uHcr8Pdg7C72bHm5pmgD-lwNVv4Oc0	963	\N	officer	2026-07-09 22:36:11.32911+07	2026-08-08 22:36:11.32911+07	2026-07-09 22:36:40.663153+07	2026-07-09 22:36:39.225918+07	\N	\N	th
uvA8jVpwopHxOJNNVX_Uo7ZLQA-_l7q_4ulbiXmh-Mk	946	\N	finance	2026-07-09 23:07:22.745799+07	2026-08-08 23:07:22.745799+07	2026-07-09 23:35:04.86139+07	2026-07-09 23:35:01.522094+07	\N	\N	th
lEreg9I2SRXqTuMwufBzGiqYEpOH000gwVkEk-KPt_M	957	\N	supervisor	2026-07-10 11:40:57.430715+07	2026-08-09 11:40:57.430715+07	2026-07-10 11:41:04.831771+07	2026-07-10 11:41:03.505039+07	\N	\N	th
8IDRmLL8ZAuw_F1VtLYzu2R05vu_jhcZFF0xYEMcIYc	947	\N	manager	2026-07-10 12:14:49.192743+07	2026-08-09 12:14:49.192743+07	2026-07-10 12:15:08.20598+07	2026-07-10 12:15:01.974086+07	\N	\N	th
vOXgUfQYjp2op-PaMr-lKsjlFutkNbzwYrhU_Donrm8	951	\N	manager	2026-07-10 12:15:14.431666+07	2026-08-09 12:15:14.431666+07	2026-07-10 12:15:26.114435+07	2026-07-10 12:15:17.217954+07	\N	\N	th
lrIdEKkMUXRwXruQaI4l6KzS6mmMw0KetUWE7vNqdwo	951	\N	manager	2026-07-10 11:40:46.935344+07	2026-08-09 11:40:46.935344+07	2026-07-10 11:40:57.433816+07	2026-07-10 11:40:48.321728+07	\N	\N	th
PG1v0wWM34Vw-tl_HFwdMegVpT34puXXP3EvGMdDNlo	951	\N	manager	2026-07-10 12:15:31.935221+07	2026-08-09 12:15:31.935221+07	2026-07-10 12:22:55.316773+07	2026-07-10 12:22:42.077897+07	\N	\N	th
LWbvpW1g08sFYwoT3ylmcMsn-Nn86--7qlzWzZ_JKfY	957	\N	supervisor	2026-07-10 12:23:05.462745+07	2026-08-09 12:23:05.462745+07	2026-07-10 12:28:19.270671+07	2026-07-10 12:28:11.981814+07	\N	\N	th
dlAAnSQchMIIaZ-0ir7_DvAKHtkOcbPt2wHeGe-zAuY	951	\N	manager	2026-07-10 11:41:04.829927+07	2026-08-09 11:41:04.829927+07	2026-07-10 12:14:49.195363+07	2026-07-10 12:14:45.363013+07	\N	\N	th
Cer8dmJ9JG9Ye3f6_eOe8LikqrhfjS0U2p0d3giSTzU	964	\N	it	2026-07-10 12:22:59.981551+07	2026-08-09 12:22:59.981551+07	2026-07-10 12:23:05.465637+07	2026-07-10 12:23:00.636973+07	\N	\N	th
test-7287	944	\N	ceo	2026-07-10 11:06:54.373055+07	2026-07-10 12:06:54.373055+07	\N	2026-07-10 11:18:56.548898+07	\N	\N	th
XJpAmjF4cpwCUwaSZyEpQy0mrs6GJ-qsak6YYt4usQc	954	\N	supervisor	2026-07-10 12:31:07.454689+07	2026-08-09 12:31:07.454689+07	2026-07-10 12:34:43.062787+07	2026-07-10 12:34:33.209046+07	\N	\N	th
iGWcArE2AV46KOJl4zYZO1fSvURhxQM4lxT3gxC5OL8	959	\N	officer	2026-07-10 12:34:43.059812+07	2026-08-09 12:34:43.059812+07	2026-07-10 12:34:46.205084+07	2026-07-10 12:34:43.688165+07	\N	\N	th
0CXm5TtvaP1SFrf7CQ-Jp8gSdiO9rT_veigfrrFpBn4	957	\N	supervisor	2026-07-10 12:22:55.31222+07	2026-08-09 12:22:55.31222+07	2026-07-10 12:22:59.982478+07	2026-07-10 12:22:57.22325+07	\N	\N	th
T22QbPZJwdpYQbpd-QYwFhLEX3OdQQ_mz0fBs50qUaA	959	\N	officer	2026-07-10 12:28:19.267395+07	2026-08-09 12:28:19.267395+07	2026-07-10 12:31:07.457383+07	2026-07-10 12:30:54.116183+07	\N	\N	th
jLx2YZV3tcQQ2NIMqpOfEWt25qNUWZyp86qOLv8X54c	947	\N	manager	2026-07-10 12:34:46.201991+07	2026-08-09 12:34:46.201991+07	2026-07-10 12:34:53.635012+07	2026-07-10 12:34:48.420565+07	\N	\N	th
LOIzsAtXQyU3vSCR2C0pUzHIEUpGFk55nUTRiVOvYSs	944	\N	CEO	2026-07-12 10:31:11.734535+07	2026-08-11 10:31:11.734535+07	\N	2026-07-12 10:31:11.788269+07	\N	\N	th
GmG_bcRrgC9vRygwuUR80WaJMEGUHwLYvWlbzFkKcgk	944	\N	CEO	2026-07-12 10:02:42.36599+07	2026-08-11 10:02:42.36599+07	\N	2026-07-12 10:03:38.729911+07	\N	\N	th
l4siOoFzHQSZnqAKk95lCpzGYHUAfY7dsQWUhOga5VM	944	\N	CEO	2026-07-12 10:09:03.146601+07	2026-08-11 10:09:03.146601+07	\N	2026-07-12 10:09:03.146601+07	\N	\N	th
Lm5iEHC-UsVKY1_gYOEQ-IpMgdho4mN4CrEs_-AwhME	944	\N	CEO	2026-07-12 10:09:03.199767+07	2026-08-11 10:09:03.199767+07	\N	2026-07-12 10:09:03.199767+07	\N	\N	th
umzEcBn1Q_OokcAnuU-D2q0YderyyzXMs9yX4rjdx24	944	\N	CEO	2026-07-12 10:09:07.922945+07	2026-08-11 10:09:07.922945+07	\N	2026-07-12 10:09:09.459262+07	\N	\N	th
8Apbw4MSyulg3thQM4PcPF_Xjebtb3T-x4w_QWrjlck	952	\N	Accounting Manager	2026-07-12 09:55:19.709403+07	2026-08-11 09:55:19.709403+07	\N	2026-07-12 10:12:49.32607+07	\N	\N	th
o6AGQ9WxeX5UIeIiie5LwUQ7xEvgqiEM_Piody9W1NM	953	\N	Manager	2026-07-12 10:13:02.651939+07	2026-08-11 10:13:02.651939+07	\N	2026-07-12 10:13:02.727565+07	\N	\N	th
tvgZETyB1JkMVM2Vek84PPefrxqLy7gWZ4VTMr9fsYk	944	\N	ceo	2026-07-10 14:41:37.174767+07	2026-08-09 14:41:37.174767+07	2026-07-10 18:06:33.925499+07	2026-07-10 18:06:24.351976+07	\N	\N	th
akJqvWdlidrsHTofDbemD5hzfyYaLHDmgIGREtDvs7o	944	\N	ceo	2026-07-10 13:32:35.452492+07	2026-08-09 13:32:35.452492+07	\N	2026-07-10 13:32:35.668319+07	\N	\N	th
IUINFWkqQj9e8wGioPZ3w26pP91ckBxYdTdAD84s390	961	\N	Officer	2026-07-12 10:13:06.018036+07	2026-08-11 10:13:06.018036+07	\N	2026-07-12 10:13:06.096904+07	\N	\N	th
bCbgjfLghnugzkjmtjgVTF8qL0k8TrAyIra72XDp5lY	944	\N	CEO	2026-07-12 10:31:31.498463+07	2026-08-11 10:31:31.498463+07	\N	2026-07-12 10:31:31.553784+07	\N	\N	th
0cBsc5TkvyykE2H1TqQTxJb4QLTWlqYvP3F957qPIXc	944	\N	CEO	2026-07-12 10:31:40.451849+07	2026-08-11 10:31:40.451849+07	\N	2026-07-12 10:31:40.49968+07	\N	\N	th
RWcctlekW4OsKhqY7rlnQsw2kmTE0QdgE9ch0vJVmVA	944	\N	CEO	2026-07-12 10:14:37.462276+07	2026-08-11 10:14:37.462276+07	\N	2026-07-12 10:14:37.515849+07	\N	\N	th
kuJ8Bkd-vtXPHjXkeUIXucvXQU-bTs37C3Osof_ndB4	944	\N	CEO	2026-07-12 10:14:51.317896+07	2026-08-11 10:14:51.317896+07	\N	2026-07-12 10:14:53.044565+07	\N	\N	th
2hZlhdy7XQ5tVXzKVYX77HejnXpwExOV5NlBKpAjILA	950	\N	manager	2026-07-10 12:34:53.63208+07	2026-08-09 12:34:53.63208+07	2026-07-10 13:16:07.520573+07	2026-07-10 13:16:04.311824+07	\N	\N	th
9upZUOt0TvbIaQ0h0xARFf16Z_MWK9N7RMJ9DnZ3KPA	944	\N	CEO	2026-07-12 10:15:20.653396+07	2026-08-11 10:15:20.653396+07	\N	2026-07-12 10:15:22.174784+07	\N	\N	th
1XzMfQHIL0rnvQllvn_InINGP7TvYr3_UwBfiQxSp3Y	944	\N	ceo	2026-07-11 04:34:09.483384+07	2026-08-10 04:34:09.483384+07	\N	2026-07-11 04:34:09.483384+07	\N	\N	th
3YvNZ8VQXx-uPq1DCRVDE4LtZZjRTisspTImSa3MrgE	944	\N	ceo	2026-07-10 13:16:07.518345+07	2026-08-09 13:16:07.518345+07	2026-07-10 13:36:20.25734+07	2026-07-10 13:36:10.310683+07	\N	\N	th
jk9YRtyGYp8gepLg7o8WewF8BPHaMWEE0J9qHZhq2bU	944	\N	ceo	2026-07-11 04:37:23.07064+07	2026-08-10 04:37:23.07064+07	\N	2026-07-11 04:37:23.07064+07	\N	\N	th
hPI2D6j25J9OIeQhx1Zh2hrCv6q8ShGIOcUoLWRfEN4	944	\N	CEO	2026-07-12 10:16:29.766502+07	2026-08-11 10:16:29.766502+07	\N	2026-07-12 10:16:31.425134+07	\N	\N	th
oTcznMLuoQSTpsIXjCVrwdi66j8tv6dULtmPXb8nDSM	944	\N	CEO	2026-07-12 10:31:47.449555+07	2026-08-11 10:31:47.449555+07	\N	2026-07-12 10:31:47.495099+07	\N	\N	th
gPmFq-xdZd1nmZ0AB9lKW3f7pVtT3WVEaeODJaZaAPo	944	\N	ceo	2026-07-11 04:38:09.424141+07	2026-08-10 04:38:09.424141+07	\N	2026-07-11 04:38:12.130573+07	\N	\N	th
1IW8cNzJt2v00vrdHKc86yzZoORGeJJMGNUQE8AYiw8	944	\N	CEO	2026-07-12 10:31:47.542731+07	2026-08-11 10:31:47.542731+07	\N	2026-07-12 10:31:47.582111+07	\N	\N	th
gVeKkjrWbJcxrevNuguYgNrgavmJK9_ZblZDGQTpPjU	944	\N	CEO	2026-07-12 10:32:11.398926+07	2026-08-11 10:32:11.398926+07	\N	2026-07-12 10:32:11.444955+07	\N	\N	th
fpA2O1xkwJ2v6McxZMfgLtL2cJ0MGDbC2tkSUMQyXXg	944	\N	ceo	2026-07-10 18:06:36.569702+07	2026-08-09 18:06:36.569702+07	\N	2026-07-11 09:36:31.701692+07	\N	\N	th
kqquOVl9UICzr-56UC4bxPBCvyrtxyiNeBUciRHDik0	944	\N	CEO	2026-07-12 09:54:06.121451+07	2026-08-11 09:54:06.121451+07	\N	2026-07-12 09:54:13.308254+07	\N	\N	th
LQjkYAFIfNKxjduZlFRy1f7d6abHYOFg_DxCl2HnW3U	944	\N	CEO	2026-07-12 10:17:14.210895+07	2026-08-11 10:17:14.210895+07	\N	2026-07-12 10:17:26.322014+07	\N	\N	th
Zz9AqrbRLXfhLmsccxq6qfdkM42lNuW2tk59sMCxcho	952	\N	Accounting Manager	2026-07-12 09:56:49.463248+07	2026-08-11 09:56:49.463248+07	\N	2026-07-12 09:56:49.514013+07	\N	\N	th
0XTKL92WR8XZag_evcsV4UYvhHz8wxBjDcbm8gP4hvk	946	\N	finance	2026-07-10 13:36:20.253922+07	2026-08-09 13:36:20.253922+07	\N	2026-07-10 14:41:09.830502+07	\N	\N	th
2NJllErGF5l9lJM1J79MoaaPOo04iacBLYHaR8PCxl0	944	\N	CEO	2026-07-12 10:32:19.026175+07	2026-08-11 10:32:19.026175+07	\N	2026-07-12 10:32:19.069936+07	\N	\N	th
dgH2_EFTJaedvykXqtyF0M8Z5S4z2TrZxv6YxMPbpy4	944	\N	CEO	2026-07-12 10:33:33.795612+07	2026-08-11 10:33:33.795612+07	\N	2026-07-12 10:33:34.004447+07	\N	\N	th
vl9r9VnhFLQsOE7WNCPxxThIwoibNwY-kykyfkP_TRw	951	\N	Manager	2026-07-12 17:31:44.81558+07	2026-08-11 17:31:44.81558+07	\N	2026-07-13 09:35:43.03805+07	\N	\N	th
kwCpmWsSAHBc8zLCK8c1OWZIJeNzAIfDcTWo7cPEHHY	944	\N	CEO	2026-07-12 10:33:51.285576+07	2026-08-11 10:33:51.285576+07	\N	2026-07-12 10:33:53.846961+07	\N	\N	th
fsypTmZmd87ZLIVEpLt-mOWC2lIxlv_K_YzcuD7vhos	952	\N	Accounting Manager	2026-07-12 09:59:04.975056+07	2026-08-11 09:59:04.975056+07	\N	2026-07-12 09:59:05.012565+07	\N	\N	th
0MbkdcxWz82cAAKVlmEx8sWfLRMT_Z1GCd_phQQXoZY	945	\N	cfo::2	2026-07-13 16:45:01.557213+07	2026-08-12 16:45:01.557213+07	\N	2026-07-13 16:45:01.771597+07	\N	\N	th
34uhT6f9MTSz2ztfoxwmxG_CewkIIeNfjQsWAJLyCmk	959	\N	Officer	2026-07-12 10:13:09.80304+07	2026-08-11 10:13:09.80304+07	\N	2026-07-12 10:30:41.32872+07	\N	\N	th
9X3vifW9fkUEKoRyMfYWrL7xpcsp2pKQTwnAZ_FXh4Q	950	\N	Manager	2026-07-12 17:23:41.55602+07	2026-08-11 17:23:41.55602+07	\N	2026-07-12 17:23:45.28064+07	\N	\N	th
e9hjcpZaO-nB0A0FJZ2F6RiJkNeCsFyUsu2z-TFTCko	944	\N	CEO	2026-07-12 10:30:54.197035+07	2026-08-11 10:30:54.197035+07	\N	2026-07-12 10:30:57.155784+07	\N	\N	th
tAj7_dxxbKFsE-8Hew_Afcfy7Fg0vTyBGnxQp6WXNVk	952	\N	Accounting Manager	2026-07-13 10:42:19.187375+07	2026-08-12 10:42:19.187375+07	\N	2026-07-13 13:14:59.429907+07	\N	\N	th
_K_hHfHiIBtJyyxfTOA8EcpZDS29LSBpFkADPmwn7zo	944	\N	CEO	2026-07-12 15:39:20.665682+07	2026-08-11 15:39:20.665682+07	\N	2026-07-12 15:39:20.665682+07	\N	\N	th
PJR621rFtQPunGtMoRUZMLTneGwhiHJoWeY_JsNAzhk	944	\N	CEO	2026-07-12 15:39:37.913836+07	2026-08-11 15:39:37.913836+07	\N	2026-07-12 15:39:37.913836+07	\N	\N	th
24S28vC4RKMaPEHfbvI8YrJ-YgwGilotB4amE31FBrU	951	\N	Manager	2026-07-12 17:24:06.727732+07	2026-08-11 17:24:06.727732+07	\N	2026-07-12 17:24:06.816932+07	\N	\N	th
1ilP6-mIF6_ozm9l-Rc8-5M0YgxB7qZ-yw0OIbKaF0k	957	\N	Supervisor	2026-07-12 17:24:17.640127+07	2026-08-11 17:24:17.640127+07	\N	2026-07-12 17:31:30.839686+07	\N	\N	th
cIDMHUgCI6o2LPLIvpglDUlWKoSr4v_6-Qd3MtfEHbc	944	\N	CEO	2026-07-12 15:45:05.540444+07	2026-08-11 15:45:05.540444+07	\N	2026-07-12 15:45:05.540444+07	\N	\N	th
zD0IxScyFq5E5ZxmxQtz1aymH32xIiiucy1RD1cfXyM	944	\N	CEO	2026-07-12 15:45:28.827861+07	2026-08-11 15:45:28.827861+07	\N	2026-07-12 15:45:28.827861+07	\N	\N	th
Mk6c9Tq03DaAABAigfRyDn9-zv-2oeCaT1nYdoKBk3o	944	\N	CEO	2026-07-12 15:46:39.338272+07	2026-08-11 15:46:39.338272+07	\N	2026-07-12 15:46:39.338272+07	\N	\N	th
6Gp-L0IKD1MfJriG2L-l21763QpwljyvPtxOEZixCcw	944	\N	CEO	2026-07-12 15:46:54.699677+07	2026-08-11 15:46:54.699677+07	\N	2026-07-12 15:46:54.699677+07	\N	\N	th
3oMTtWEq4lzgXDFsCWnJvkO3UFE_qyYMWv6O2YeQP7o	944	\N	CEO	2026-07-12 15:47:40.564428+07	2026-08-11 15:47:40.564428+07	\N	2026-07-12 15:47:40.564428+07	\N	\N	th
3hDozsVjnW1fImn7MxnUZAh2SMXxLAxuBy9vh93-8Cg	944	\N	CEO	2026-07-12 15:48:14.633645+07	2026-08-11 15:48:14.633645+07	\N	2026-07-12 15:48:14.633645+07	\N	\N	th
4nA31XjhCpYDkloIUfwDh8LDtb7-SWxT8ijyNsT7zA0	944	\N	CEO	2026-07-12 15:48:58.954255+07	2026-08-11 15:48:58.954255+07	\N	2026-07-12 15:48:58.954255+07	\N	\N	th
Y7cG9T_jHFlMolVCEVFnKvEsYEPaEIMOXX1qu2pcxzg	946	\N	Finance Lead	2026-07-12 14:56:08.889618+07	2026-08-11 14:56:08.889618+07	\N	2026-07-12 17:21:46.082242+07	\N	\N	th
G_mjMaoFCR4kcns5JH52uxMxoBCYKb3Dhkyhwp2GUBE	945	\N	cfo::2	2026-07-13 16:54:40.618027+07	2026-08-12 16:54:40.618027+07	\N	2026-07-13 16:54:41.673201+07	\N	\N	th
tzSoVaMGTGCmKOYHtNshLCUa7Tp0T8gVjdKV5eX618w	945	\N	cfo::2	2026-07-13 16:42:33.413439+07	2026-08-12 16:42:33.413439+07	\N	2026-07-13 16:42:51.518418+07	\N	\N	th
kwoEy3_ZpOwNTwEtPLMw5BukGssXoOzwidnq1ixAgco	945	\N	cfo::2	2026-07-13 16:45:25.872047+07	2026-08-12 16:45:25.872047+07	\N	2026-07-13 16:45:25.872047+07	\N	\N	th
8_r6z-a3592b2GSUnXl1fNitQa2K9h0CalkQX1rOHHg	945	\N	cfo	2026-07-13 16:45:25.891089+07	2026-08-12 16:45:25.891089+07	\N	2026-07-13 16:45:25.891089+07	\N	\N	th
SOfbRUvfLeHkdSBMcFglgd-3bvLdNWJ0Gj6O9N3WN6E	957	\N	Supervisor	2026-07-13 13:29:54.574558+07	2026-08-12 13:29:54.574558+07	\N	2026-07-13 14:27:54.529858+07	\N	\N	th
STqxaMc8opcHhTLsy0nomlGw1JYD5gBBl4-lVT4GP6E	945	\N	cfo::2	2026-07-13 16:41:51.533331+07	2026-08-12 16:41:51.533331+07	\N	2026-07-13 16:41:51.533331+07	\N	\N	th
XykkVVgoctazpZ7pOF3UfH24d4lXhn-AmKBG5akqGlI	945	\N	cfo::2	2026-07-13 16:41:51.570798+07	2026-08-12 16:41:51.570798+07	\N	2026-07-13 16:41:51.570798+07	\N	\N	th
0kr06ppkoNRe1T1BV22r9EfWruMtFYYz0UtKHHZXUTA	945	\N	cfo::2	2026-07-13 16:52:28.616147+07	2026-08-12 16:52:28.616147+07	\N	2026-07-13 16:52:28.616147+07	\N	\N	th
GpsB1q-vjbY7lRyQuyQTTZpT4a5oCWRaR-QWRxKmYXw	945	\N	cfo::2	2026-07-13 16:53:19.776669+07	2026-08-12 16:53:19.776669+07	\N	2026-07-13 16:53:19.776669+07	\N	\N	th
6pbOCWcC6PjbH_g96ll0xXyfJWXDAXkxfFE2Dr5nnqE	945	\N	cfo::2	2026-07-13 16:53:51.230003+07	2026-08-12 16:53:51.230003+07	\N	2026-07-13 16:53:51.230003+07	\N	\N	th
3gLKPZHIFO1ZqbXdwus2p4zNb0PN-kbs8FYuH1jL89E	951	\N	Manager	2026-07-13 14:32:36.401855+07	2026-08-12 14:32:36.401855+07	2026-07-13 17:32:32.634065+07	2026-07-13 17:28:27.584273+07	\N	\N	th
nX3UsRjOaqqAtgB7WLikYJmChq3QRzkBpt8h_lhPpEM	945	\N	cfo::2	2026-07-13 16:55:20.894331+07	2026-08-12 16:55:20.894331+07	\N	2026-07-13 16:55:22.154521+07	\N	\N	th
hv4Ujja01VLN-ABd4xIhil1uw3SpYY4_XdsB3-771zQ	964	\N	it::2	2026-07-13 16:55:27.264143+07	2026-08-12 16:55:27.264143+07	\N	2026-07-13 17:39:06.598282+07	\N	\N	th
5oE02TgOQY2BHJTDnvcgE1I4Jj_qDxxYuOadyqxgbGw	944	\N	ceo::1	2026-07-13 17:03:21.609388+07	2026-08-12 17:03:21.609388+07	\N	2026-07-13 17:03:22.162319+07	\N	\N	th
_l7DWEIZFiCaA2T5sVfo5K8tW1s53E_ttb04Yyjd4sU	944	\N	ceo	2026-07-13 17:37:23.68606+07	2026-08-12 17:37:23.68606+07	\N	2026-07-13 17:37:23.68606+07	\N	\N	th
ukAIrK_z0tRD0F9iOipgTT4ug-FVl2hLc0IXczpaQ84	944	\N	ceo	2026-07-13 17:37:26.82431+07	2026-08-12 17:37:26.82431+07	\N	2026-07-13 17:37:26.82431+07	\N	\N	th
K7iO846VknAOd90U8HW2NS-xwg0tglotgT1Aniu3MfE	948	\N	manager	2026-07-13 17:37:28.171363+07	2026-08-12 17:37:28.171363+07	\N	2026-07-13 17:37:28.171363+07	\N	\N	th
Q6XvDDGCrbB0ssutmTD_IL9eca_qdjkFrDKKvtSYiPc	955	\N	account_supervisor	2026-07-13 17:37:29.18471+07	2026-08-12 17:37:29.18471+07	\N	2026-07-13 17:37:29.18471+07	\N	\N	th
A11x0b4WHuzfeJUIaAVkmmFI4Q5tuzV0DXI28aihZEg	963	\N	officer	2026-07-13 17:37:30.603191+07	2026-08-12 17:37:30.603191+07	\N	2026-07-13 17:37:30.603191+07	\N	\N	th
RDRcNDOAP5oXLsVNCa5-ADVWtxpyIIThaTnkiRN2bek	961	\N	officer	2026-07-13 17:37:31.218429+07	2026-08-12 17:37:31.218429+07	\N	2026-07-13 17:37:31.218429+07	\N	\N	th
DkNH_2wHshIvC0yztXllNzMWVi_X6DKPek5NW1WYxSY	962	\N	hr	2026-07-13 17:37:31.852154+07	2026-08-12 17:37:31.852154+07	\N	2026-07-13 17:37:31.852154+07	\N	\N	th
offTea5vZJiLR0oUeNICzBaT9lOsLwAlu4ahfRZvBi8	956	\N	supervisor	2026-07-13 17:37:32.185368+07	2026-08-12 17:37:32.185368+07	\N	2026-07-13 17:37:32.185368+07	\N	\N	th
dUJVSqPGs5whG1-WgIT0JNwLryNpAXQEClhUtuWKqf8	951	\N	manager	2026-07-13 17:37:32.732499+07	2026-08-12 17:37:32.732499+07	\N	2026-07-13 17:37:32.732499+07	\N	\N	th
Alw7YiupisB8si69CEKKvC26PP_402ZI0Fx3xwfQ7io	949	\N	hr_manager	2026-07-13 17:37:33.02773+07	2026-08-12 17:37:33.02773+07	\N	2026-07-13 17:37:33.02773+07	\N	\N	th
8o344Om-rUUEx5a3jqFyIRXzZLSRYdTvwS3AaIEDg4E	944	\N	ceo	2026-07-13 17:37:41.542706+07	2026-08-12 17:37:41.542706+07	\N	2026-07-13 17:37:41.542706+07	\N	\N	th
R7StzXFZEIltdYkWab3oJIDq1_1KpoPEzre5sO_-Rjo	948	\N	manager	2026-07-13 17:37:42.690326+07	2026-08-12 17:37:42.690326+07	\N	2026-07-13 17:37:42.690326+07	\N	\N	th
kHwDlJMf2IbGdO1wZ3ajDwUT9v4Vjweewd0OEnpIJ8c	952	\N	accounting_manager	2026-07-13 17:37:43.029724+07	2026-08-12 17:37:43.029724+07	\N	2026-07-13 17:37:43.029724+07	\N	\N	th
nLOu0MOmVal26wp39KEJxFQ6OyjDhF3-ZzPYlp2NIFs	944	\N	ceo	2026-07-13 17:48:30.912271+07	2026-08-12 17:48:30.912271+07	\N	2026-07-13 17:48:30.912271+07	\N	\N	th
F_2oXjNXCoBE_9uFIqIHca6CGfYySnj5zwtAzwebKt8	944	\N	ceo	2026-07-13 17:48:43.096773+07	2026-08-12 17:48:43.096773+07	\N	2026-07-13 17:48:43.096773+07	\N	\N	th
qcIQ4RdLwmEIsJ5bQAGxDW1t0GD4GuPSA95ajdsek_Q	944	\N	ceo	2026-07-13 17:48:44.297755+07	2026-08-12 17:48:44.297755+07	\N	2026-07-13 17:48:44.297755+07	\N	\N	th
At6j-magNtPVGVMXtFFccb-Gjub9U0tk9YdPif9Mx2U	953	\N	manager	2026-07-13 17:48:55.740118+07	2026-08-12 17:48:55.740118+07	\N	2026-07-13 17:48:55.740118+07	\N	\N	th
lzzXSohWBMJO-IrV8RSYnbfh7Hx_1zp_lAM8wGB13V4	944	\N	ceo	2026-07-13 17:50:15.973861+07	2026-08-12 17:50:15.973861+07	\N	2026-07-13 17:50:15.973861+07	\N	\N	th
H7BHx3QqJYzNQG5O2YzKAw5-yHGwIKXzFt2F-AnwpJU	944	\N	ceo	2026-07-13 17:50:27.955345+07	2026-08-12 17:50:27.955345+07	\N	2026-07-13 17:50:27.955345+07	\N	\N	th
7LAABPpcN0C-Cza2RSG7IEOcGWcQ5P7njfDlnHv7-1M	944	\N	ceo	2026-07-13 17:50:33.709818+07	2026-08-12 17:50:33.709818+07	\N	2026-07-13 17:50:33.709818+07	\N	\N	th
Y4u6FXOS26N0qdixohdSeouMbkntNg76Ny2mOaWGfck	944	\N	ceo	2026-07-13 18:30:51.91254+07	2026-08-12 18:30:51.91254+07	\N	2026-07-13 18:31:55.213921+07	\N	\N	th
3UW6BDOTpSwh78CO4YpmLjwJoTJcsrSQFuyXYOJIw_4	959	\N	officer	2026-07-13 18:30:51.93342+07	2026-08-12 18:30:51.93342+07	\N	2026-07-13 18:31:55.306917+07	\N	\N	th
8g4iz2g2YOF6415gWex5heiGGUMlErxtgdWXJHWFaTQ	944	\N	ceo::1	2026-07-13 18:01:57.340372+07	2026-08-12 18:01:57.340372+07	\N	2026-07-13 18:01:57.340372+07	\N	\N	th
xYJeAtc2-LaxfM64md-CDbOrFJZ8cmVgz859HpxZZvc	959	\N	officer	2026-07-13 18:38:14.73072+07	2026-08-12 18:38:14.73072+07	\N	2026-07-13 18:38:14.73072+07	\N	\N	th
me_dKK8jg2ifLSct2wXdBOrB8jsehnn3fqQMYgGmteg	947	\N	manager	2026-07-13 18:40:20.194866+07	2026-08-12 18:40:20.194866+07	2026-07-13 22:15:30.705308+07	2026-07-13 18:40:20.194866+07	\N	\N	th
Ib8ZV8K7C3wDYrCx7qBPABTCEM480iBIzLXzik4JtK8	946	\N	finance	2026-07-13 22:15:36.872735+07	2026-08-12 22:15:36.872735+07	\N	2026-07-13 22:15:36.872735+07	\N	\N	th
UXSPPE2TpBlnK3q9oPsUkY6-vSdXVS-BHO-r8rSTBTQ	965	\N	account_officer	2026-07-13 22:15:46.358869+07	2026-08-12 22:15:46.358869+07	\N	2026-07-13 22:15:46.358869+07	\N	\N	th
spARCGJZ4rwp1JCS0d5Fyhxpr3Vqj4a6SmsbBRKYp60	944	\N	ceo	2026-07-13 22:19:17.834131+07	2026-08-12 22:19:17.834131+07	\N	2026-07-13 22:19:17.834131+07	\N	\N	th
SYBuvuKRtdAlGw2AeFxRUc6JPoWo5P1Zgn1T-e5Nbsg	944	\N	ceo	2026-07-13 22:26:41.824323+07	2026-08-12 22:26:41.824323+07	\N	2026-07-13 22:26:41.824323+07	\N	\N	th
MajPsGUijsjzAEnlzdGSFFzi60wPeUCeJ7jgECToMH8	944	\N	ceo	2026-07-13 18:01:48.785274+07	2026-08-12 18:01:48.785274+07	\N	2026-07-13 18:02:20.905856+07	\N	\N	th
RpshvjGEY6FwEtlaEFggUo9mXz9wW8grEvDZTadT0xg	944	\N	ceo	2026-07-13 18:04:07.088913+07	2026-08-12 18:04:07.088913+07	\N	2026-07-13 18:04:07.088913+07	\N	\N	th
-JF8ecQMoBRAfhZin2hCNrDp-W0PHqQZnrHZGMVKzeY	944	\N	ceo	2026-07-13 18:38:00.525368+07	2026-08-12 18:38:00.525368+07	\N	2026-07-13 18:38:28.036049+07	\N	\N	th
8L_J6N0GK0VJjzm91o91K-fNKTsEO9SVRuWmRluTLR0	944	\N	ceo	2026-07-13 22:27:34.651487+07	2026-08-12 22:27:34.651487+07	\N	2026-07-13 22:27:34.651487+07	\N	\N	th
eZWDeoFV1dC8mFQIcCzgNaqUxAFw9B9hrNdaNQXp06o	944	\N	ceo	2026-07-13 18:40:07.948254+07	2026-08-12 18:40:07.948254+07	\N	2026-07-13 18:40:13.44461+07	\N	\N	th
tW_Mxgltgd_CEMspwhJGtaPBMnWyffwbhnVRABbLTZI	944	\N	ceo	2026-07-13 18:05:45.041585+07	2026-08-12 18:05:45.041585+07	\N	2026-07-13 18:05:56.839363+07	\N	\N	th
7HeOJQ31ZDCaxTZCNcFFjioXbNB_aLVg1tKJAd5kxmY	944	\N	ceo	2026-07-13 18:41:26.604745+07	2026-08-12 18:41:26.604745+07	\N	2026-07-13 18:41:27.590588+07	\N	\N	th
LAI7k-WG7kSmhypmoUMQbfRGIjm_FNHQmsFBy0QLoiI	959	\N	officer	2026-07-13 18:41:26.626577+07	2026-08-12 18:41:26.626577+07	\N	2026-07-13 18:41:27.895299+07	\N	\N	th
J37e6ivAA7fU-hYLKzTEml6R8MlB2x2X56qkLExhKak	959	\N	officer	2026-07-13 18:06:05.739972+07	2026-08-12 18:06:05.739972+07	\N	2026-07-13 18:06:05.96322+07	\N	\N	th
c3uzDL_qHnvCcBchIoGtk_VSpIX7JVcTyicsMXxrgjc	959	\N	officer	2026-07-13 18:16:20.959005+07	2026-08-12 18:16:20.959005+07	\N	2026-07-13 18:16:20.959005+07	\N	\N	th
iVTUGOPZd52pDzXGYG320OkBAZFoemUo9mewAHKnPIQ	944	\N	ceo	2026-07-13 18:16:20.983366+07	2026-08-12 18:16:20.983366+07	\N	2026-07-13 18:16:20.983366+07	\N	\N	th
eV25-Apjv1402m4b1PD2GSJlKM-pTofuEPUKNGwQYEQ	944	\N	ceo	2026-07-13 17:55:15.446609+07	2026-08-12 17:55:15.446609+07	2026-07-13 18:19:05.440986+07	2026-07-13 17:55:15.446609+07	\N	\N	th
mdRkZ8uKUF8S2koSf3RMjDbg9bspKytJTjpHU_x9GIM	944	\N	ceo	2026-07-13 18:23:21.879181+07	2026-08-12 18:23:21.879181+07	\N	2026-07-13 18:23:21.879181+07	\N	\N	th
kekGvb7PQMJRD4XIvwlqezrrtBF0TPjRRhDKpk5LwFk	946	\N	finance	2026-07-13 18:19:07.434133+07	2026-08-12 18:19:07.434133+07	2026-07-13 18:28:06.776866+07	2026-07-13 18:19:07.434133+07	\N	\N	th
Lrxehl0-ZxZqG1SfC1q07A0OK9nt1VWUZQb1tphN9zI	964	\N	it	2026-07-13 18:28:09.744296+07	2026-08-12 18:28:09.744296+07	\N	2026-07-13 18:28:09.744296+07	\N	\N	th
nsBfvHLvtWvUjz6koxZb2MVp44HwBBB8zva_ysIZ-Ks	962	\N	hr	2026-07-13 18:41:38.531265+07	2026-08-12 18:41:38.531265+07	\N	2026-07-13 18:41:38.610212+07	\N	\N	th
6VvSteD9gva1CPymhMqSBEyZpy5NfAYNfXWH1RqzgXQ	954	\N	supervisor	2026-07-13 18:41:38.554838+07	2026-08-12 18:41:38.554838+07	\N	2026-07-13 18:41:38.718633+07	\N	\N	th
o5K78OKa8zZiYOuwW0JfBwmgfw5tP-RPl4eHV62FMys	949	\N	hr_manager	2026-07-13 18:41:38.572459+07	2026-08-12 18:41:38.572459+07	\N	2026-07-13 18:41:38.774967+07	\N	\N	th
5ZW1qEvW0pHmK1nx3uTsFfDHKUm11__8W1LZ8trkg94	944	\N	ceo	2026-07-13 22:30:44.658801+07	2026-08-12 22:30:44.658801+07	\N	2026-07-13 22:30:44.658801+07	\N	\N	th
GyoNq-b8LoZXl-flwMyD4DyOV-_vfALGOqoiQOb3_Rs	957	\N	supervisor::4	2026-07-14 00:08:07.849971+07	2026-08-13 00:08:07.849971+07	\N	2026-07-14 00:08:07.849971+07	\N	\N	th
X5pYzCHyB7phUoQ3wNESdQS45Ec7m-O0M3Qtbp8z30I	957	\N	supervisor::4	2026-07-14 00:27:48.095576+07	2026-08-13 00:27:48.095576+07	\N	2026-07-14 00:27:48.095576+07	\N	\N	th
jiSAQy5xlJqqQJtLuziD5ifzQD2sJdGVl6iFOVoTdx8	944	\N	ceo	2026-07-13 19:07:12.766878+07	2026-08-12 19:07:12.766878+07	\N	2026-07-13 19:07:13.407731+07	\N	\N	th
Y3Fc6yAjpUURYTFIpcBoq0k-RF3_NrCeRLfvpYVTT1U	944	\N	ceo	2026-07-13 19:13:49.860497+07	2026-08-12 19:13:49.860497+07	\N	2026-07-13 19:13:49.860497+07	\N	\N	th
5wY15anixLccuYsSjGxweDTV9UwmQsEW1WfpIhOjPWI	944	\N	ceo	2026-07-13 22:07:07.1783+07	2026-08-12 22:07:07.1783+07	\N	2026-07-13 22:07:07.1783+07	\N	\N	th
EPybsQn38a3XdcxvGGvKNe86K5OTBs-dfYaBWI3vUVM	959	\N	officer	2026-07-13 22:07:07.198566+07	2026-08-12 22:07:07.198566+07	\N	2026-07-13 22:07:07.198566+07	\N	\N	th
8aDR28U5Ug6pOZEVE57ANG0f2oemHq2gdcGtfP9Cq2Y	949	\N	hr_manager	2026-07-13 22:07:07.213372+07	2026-08-12 22:07:07.213372+07	\N	2026-07-13 22:07:07.213372+07	\N	\N	th
7Zcdw9sEnhSeJjU4B21Tqmg7HIIKDsiyPcpDWRuN3LE	944	\N	ceo	2026-07-13 22:10:12.640434+07	2026-08-12 22:10:12.640434+07	\N	2026-07-13 22:10:12.640434+07	\N	\N	th
-Dz7_Crz9rvjuSpVf07Qs1IPuH_gmAtEmuVH334mddE	964	\N	it	2026-07-13 22:10:22.985805+07	2026-08-12 22:10:22.985805+07	\N	2026-07-13 22:10:22.985805+07	\N	\N	th
Wg0h-J-oVKxIcLrTNau_7JH_CyIpIYr5YXb24cSuBm4	944	\N	ceo	2026-07-13 22:11:14.45519+07	2026-08-12 22:11:14.45519+07	\N	2026-07-13 22:11:14.45519+07	\N	\N	th
rU5enaZwBBc_yejb-JFcZOabL3fNfEdXronB0kOMoBY	944	\N	ceo	2026-07-13 22:11:14.870598+07	2026-08-12 22:11:14.870598+07	\N	2026-07-13 22:11:14.870598+07	\N	\N	th
TB6KacwVl3cQdy26NHMggzM3TKscxZVoSMCNn4flHrI	949	\N	hr_manager	2026-07-13 22:11:23.6188+07	2026-08-12 22:11:23.6188+07	\N	2026-07-13 22:11:23.6188+07	\N	\N	th
pUMVavQTa4mRsvuiBo4WUEJ_bpSctJBHJEkDmt-fVbk	964	\N	it	2026-07-13 22:11:23.832026+07	2026-08-12 22:11:23.832026+07	\N	2026-07-13 22:11:23.832026+07	\N	\N	th
kEO_jbgKRuyuuL_-1IKS4No7Y8icq4WvFWQP0bVntXc	957	\N	supervisor::4	2026-07-14 00:30:02.498964+07	2026-08-13 00:30:02.498964+07	\N	2026-07-14 00:30:02.498964+07	\N	\N	th
AJmbYyDryuc8xjgHZRvFpImGE-WDONPEQ5DKOmxppEU	957	\N	supervisor::4	2026-07-14 00:40:31.119179+07	2026-08-13 00:40:31.119179+07	\N	2026-07-14 00:40:31.119179+07	\N	\N	th
XnOtwUEjwArWWHmlI6XKGSXIKLyMPoD7vGfHHcRMD20	957	\N	supervisor::4	2026-07-14 00:41:46.013543+07	2026-08-13 00:41:46.013543+07	\N	2026-07-14 00:41:46.013543+07	\N	\N	th
8VekPoASI0vEaHHDdSAFRREqFGt0wfXP_OQRSknNLY0	957	\N	supervisor::4	2026-07-14 00:43:57.156702+07	2026-08-13 00:43:57.156702+07	\N	2026-07-14 00:43:57.156702+07	\N	\N	th
11msFDKm6uclEmMSX6xUN75NStCAAN_LB7FM8QZa7NA	957	\N	supervisor::4	2026-07-14 00:44:56.370176+07	2026-08-13 00:44:56.370176+07	\N	2026-07-14 00:44:56.370176+07	\N	\N	th
x0niqQbD_AYT-3QC9zvw9izhlf5uI_eS_DsguACQkr4	957	\N	supervisor::4	2026-07-14 00:45:01.750589+07	2026-08-13 00:45:01.750589+07	\N	2026-07-14 00:45:01.750589+07	\N	\N	th
4D2EI8IM2WhhgFCFVReveh4mj6hVj30aTDK_8lHAq6g	957	\N	supervisor::4	2026-07-14 00:45:01.887985+07	2026-08-13 00:45:01.887985+07	\N	2026-07-14 00:45:01.887985+07	\N	\N	th
qv5ryh3xPrTMWDM-ot375RiDD8EZBC5Qp0T7NHq1ZXo	957	\N	supervisor::4	2026-07-14 03:21:31.307103+07	2026-08-13 03:21:31.307103+07	\N	2026-07-14 03:21:31.307103+07	\N	\N	th
u8UB2I_EuTE3xqCJAFdu5Gv0jd2KS4YZ0d9JlPaewAo	957	\N	supervisor::4	2026-07-14 03:21:35.927731+07	2026-08-13 03:21:35.927731+07	\N	2026-07-14 03:21:35.927731+07	\N	\N	th
_C34ecI15XTZC8XiU-e57p8sa2Mpzs9ksZkYJDOqajE	957	\N	supervisor::4	2026-07-14 03:21:40.295285+07	2026-08-13 03:21:40.295285+07	\N	2026-07-14 03:21:40.295285+07	\N	\N	th
mrzEOpr_1zIOwSzHtg7y0FvErE0KVS-KiL4J4ehx94Q	957	\N	supervisor::4	2026-07-14 04:01:07.916611+07	2026-08-13 04:01:07.916611+07	\N	2026-07-14 04:01:07.916611+07	\N	\N	th
6bEFrzABdiebReB-SX22GjAGou92mL_fVy8crvLBuLk	957	\N	supervisor::4	2026-07-14 08:24:40.150334+07	2026-08-13 08:24:40.150334+07	\N	2026-07-14 08:24:40.150334+07	\N	\N	th
9gHWiceoQnylggEHcSVO83P0xTya2Otrk5tgIeG9PKk	944	\N	ceo	2026-07-14 10:08:17.646927+07	2026-08-13 10:08:17.646927+07	\N	2026-07-14 10:08:17.646927+07	\N	\N	th
Hn2YEkA1zXns8Qk8DxzDsei0uxy59QKFRz2d324dkyY	944	\N	ceo	2026-07-14 10:24:36.769455+07	2026-08-13 10:24:36.769455+07	\N	2026-07-14 10:24:36.769455+07	\N	\N	th
D0YJAb_fpR-QOHPOJNsdek-PD0zhlHg3_0AN_sTqd3Y	944	\N	ceo	2026-07-14 11:48:56.577238+07	2026-08-13 11:48:56.577238+07	\N	2026-07-14 11:48:56.577238+07	\N	\N	th
88lsxTtprDdEnFpR1UBmfGNpBIPNQVfkpvCi5nNqUNI	944	\N	ceo	2026-07-14 12:38:50.011439+07	2026-08-13 12:38:50.011439+07	\N	2026-07-14 12:38:50.011439+07	\N	\N	th
YpInhnXqZ41pgC2znOtGVq00uL0bWXQmxzA4yFwbEpc	944	\N	ceo::1	2026-07-14 12:43:27.408684+07	2026-08-13 12:43:27.408684+07	\N	2026-07-14 12:43:27.408684+07	\N	\N	th
HGAT1oGnxYyPgLAHQVNhptbo8ttP_Mg64x6yrEuGaGE	944	\N	ceo	2026-07-14 14:18:36.257955+07	2026-08-13 14:18:36.257955+07	\N	2026-07-14 14:18:36.257955+07	\N	\N	th
glwiP_iC3BNwrWC-uEFt2L897tKaoPu91RCwLzzq-HA	944	\N	ceo	2026-07-14 14:25:56.994944+07	2026-08-13 14:25:56.994944+07	\N	2026-07-14 14:25:56.994944+07	\N	\N	th
rMgPvt7kNTihuAROQpfofzt1M-2JXZfe9v7qTgyWHt4	968	\N	it	2026-07-14 14:25:58.56277+07	2026-08-13 14:25:58.56277+07	\N	2026-07-14 14:25:58.56277+07	\N	\N	th
-tlbSg78-MGW7JV1rl65jlBBBA5_6fsWhxT6ZS6lEi0	946	\N	finance	2026-07-14 17:39:59.014504+07	2026-08-13 17:39:59.014504+07	\N	2026-07-14 17:39:59.014504+07	\N	\N	th
8azQXopcNeY3fAikBFrNqVzIHi6Wyi2piV6aRcfoSdU	944	\N	ceo	2026-07-14 17:40:08.406488+07	2026-08-13 17:40:08.406488+07	\N	2026-07-14 17:40:08.406488+07	\N	\N	th
0oUyULXpbcj53jFtAh7-BkXLKYPo48lBkfBdhO4nhc0	947	\N	manager	2026-07-14 17:55:51.552166+07	2026-08-13 17:55:51.552166+07	\N	2026-07-14 17:55:51.552166+07	\N	\N	th
SRuGVPUPdQrQDs1G6QuoDG56eOObBYzW0GgkdqhMGeY	944	\N	ceo	2026-07-14 18:41:07.733571+07	2026-08-13 18:41:07.733571+07	\N	2026-07-14 18:41:07.733571+07	\N	\N	th
QFexaa3wi26vVdqJXnNCwpYnwqDiQ2yTltZeh_pes3Q	948	\N	manager	2026-07-14 18:50:22.405885+07	2026-08-13 18:50:22.405885+07	\N	2026-07-14 18:50:22.405885+07	\N	\N	th
efYJ5bTfq3XKf3foRFLSo4wGPenFld13gAHtNVyn9ZA	952	\N	accounting_manager	2026-07-14 18:50:28.043473+07	2026-08-13 18:50:28.043473+07	\N	2026-07-14 18:50:28.043473+07	\N	\N	th
l5KE5-lyU_g1jovkwL3lSjSJ8Wvcbkdzs0oukjo7raA	944	\N	ceo	2026-07-14 19:07:42.560546+07	2026-08-13 19:07:42.560546+07	\N	2026-07-14 19:07:42.560546+07	\N	\N	th
\.


--
-- Data for Name: audit; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.audit (id, kind, actor, target, occurred_at) FROM stdin;
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.permissions (id, description) FROM stdin;
admin:system:bypass::allow	\N
rbac:role:read::allow	\N
rbac:role:assign::allow	\N
rbac:matrix:view::allow	\N
rbac:matrix:edit::allow	\N
rbac:audit:view::allow	\N
user:directory:read::allow	\N
user:profile:create::allow	\N
user:profile:update::allow	\N
user:profile:delete::allow	\N
user:profile:deactivate::allow	\N
user:role:assign::allow	\N
user:manager:set::allow	\N
user:dept:edit::allow	\N
user:subtree:edit::allow	\N
org:tree:view::allow	\N
org:dept:read::allow	\N
org:dept:assign_head::allow	\N
org:dept_role:assign::allow	\N
org:dept_role:revoke::allow	\N
org:dept_role:list::allow	\N
org:auto_wire:propose::allow	\N
org:auto_wire:apply::allow	\N
finance:expense:view_own::allow	\N
finance:expense:view_all::allow	\N
finance:expense:create::allow	\N
finance:expense:update::allow	\N
finance:expense:review::allow	\N
finance:expense:approve::allow	\N
finance:expense:settle::allow	\N
finance:expense:override::allow	\N
finance:expense:override_approve::allow	\N
finance:expense:gl_confirm::allow	\N
finance:pr:create::allow	\N
finance:pr:update::allow	\N
finance:pr:approve::allow	\N
finance:pr:override_approve::allow	\N
finance:po:approve::allow	\N
finance:po:reject::allow	\N
finance:po:attach_payslip::allow	\N
finance:po:settle::allow	\N
finance:ledger:view::allow	\N
finance:report:executive::allow	\N
finance:budget:view::allow	\N
stage:submission:act::allow	\N
stage:dept_verification:act::allow	\N
stage:dept_authorization:act::allow	\N
stage:accounting_verification:act::allow	\N
stage:accounting_supervision:act::allow	\N
stage:accounting_authorization:act::allow	\N
stage:disbursement_authorization:act::allow	\N
stage:cfo_authorization:act::allow	\N
stage:ceo_authorization:act::allow	\N
stage:gl_confirmed:act::allow	\N
stage:final_authorization:act::allow	\N
stage:po_pending:act::allow	\N
stage:po_cfo:act::allow	\N
stage:so_draft:act::allow	\N
stage:so_sales_review:act::allow	\N
stage:so_credit_check:act::allow	\N
stage:so_invoiced:act::allow	\N
stage:so_paid:act::allow	\N
tile:inbox:view::allow	\N
tile:expense:view::allow	\N
tile:pr:view::allow	\N
tile:po:view::allow	\N
tile:sales:view::allow	\N
tile:customers:view::allow	\N
tile:search_coa:view::allow	\N
tile:reconciliation:view::allow	\N
tile:cockpit:view::allow	\N
tile:summary:view::allow	\N
tile:ledger:view::allow	\N
tile:policy:view::allow	\N
tile:settings:view::allow	\N
tile:org_chart:view::allow	\N
tile:roles:view::allow	\N
tile:tile_gates:view::allow	\N
tile:directory:view::allow	\N
tile:audit:view::allow	\N
tile:departments:view::allow	\N
tile:access_requests:view::allow	\N
tile:hook:view::allow	\N
tile:my_prs:view::allow	\N
tile:dash_am:view::allow	\N
tile:dash_exec:view::allow	\N
tile:dash_finance:view::allow	\N
tile:dash_it:view::allow	\N
tile:dash_manager:view::allow	\N
tile:dash_staff:view::allow	\N
hook:event:view::allow	\N
hook:event:replay::allow	\N
ai:provider:read::allow	\N
ai:provider:create::allow	\N
ai:provider:update::allow	\N
ai:provider:delete::allow	\N
ai:provider:test::allow	\N
ai:model:read::allow	\N
ai:model:create::allow	\N
ai:model:update::allow	\N
ai:model:delete::allow	\N
ai:staff:read::allow	\N
ai:staff:create::allow	\N
ai:staff:update::allow	\N
ai:staff:delete::allow	\N
ai:staff:invoke::allow	\N
ai:assignment:read::allow	\N
ai:assignment:create::allow	\N
ai:assignment:delete::allow	\N
ai:invocation:view::allow	\N
ai:section_health:view::allow	\N
access_request:request:list::allow	\N
access_request:request:resolve::allow	\N
user:dept:development::allow	Department membership: Development
user:dept:executive::allow	Department membership: Executive
user:dept:marketing::allow	Department membership: Marketing
user:dept:it::allow	Department membership: IT
system:authenticated:view::allow	Global access — every signed-in user
ai:chat:use::allow	Use AI chat (per-tile)
finance:sales:settle::allow	Settle sales receipt (attach AR)
customer:manage::allow	Create/update/blacklist customers
finance:gl:view::allow	View GL lines (read-only)
finance:gl:confirm::allow	Confirm GL posting
finance:gl:post::allow	Post GL accrual/settlement
finance:sales:submit::allow	Submit sales order
finance:sales:invoice::allow	Issue sales invoice
user:dept:finance::allow	Finance department membership
user:dept:hr::allow	HR department membership
\.


--
-- Data for Name: policies; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.policies (id, name, ast, description, enabled, version, created_at, updated_at) FROM stdin;
canActOnWaybillStage	Can act on waybill stage	{"kind": "and", "rules": []}	Actor may act on the current stage of the waybill	t	1	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
recallWaybill	Recall a waybill	{"kind": "and", "rules": []}	Submitter can recall a waybill before final approval	t	1	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
\.


--
-- Data for Name: policy_decisions; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.policy_decisions (id, actor_id, policy_id, surface, target, decision, reasons, resource, occurred_at) FROM stdin;
\.


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.role_permissions (role_id, permission_id, granted_at, granted_by) FROM stdin;
officer::5	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
it::2	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_supervisor::4	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
manager::3	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr_manager::3	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
accounting_manager::3	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_supervisor::2	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
finance::2	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
admin::2	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
cfo::2	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	finance:expense:view_own::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	finance:expense:create::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	finance:pr:create::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	finance:pr:update::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	baseline
ceo::1	tile:my_prs:view::allow	2026-07-13 16:15:41.200409+07	baseline
officer::5	tile:dash_staff:view::allow	2026-07-13 16:15:41.200409+07	baseline
hr::5	tile:dash_staff:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	tile:dash_staff:view::allow	2026-07-13 16:15:41.200409+07	baseline
supervisor::4	tile:dash_staff:view::allow	2026-07-13 16:15:41.200409+07	baseline
sales_rep::3	tile:dash_staff:view::allow	2026-07-13 16:15:41.200409+07	baseline
account_officer::5	stage:accounting_verification:act::allow	2026-07-13 16:15:41.200409+07	role
account_supervisor::4	stage:accounting_supervision:act::allow	2026-07-13 16:15:41.200409+07	role
supervisor::4	stage:dept_verification:act::allow	2026-07-13 16:15:41.200409+07	role
supervisor::4	stage:submission:act::allow	2026-07-13 16:15:41.200409+07	role
sales_rep::3	stage:so_sales_review:act::allow	2026-07-13 16:15:41.200409+07	role
sales_rep::3	stage:so_draft:act::allow	2026-07-13 16:15:41.200409+07	role
manager::3	tile:dash_manager:view::allow	2026-07-13 16:15:41.200409+07	role
manager::3	stage:po_pending:act::allow	2026-07-13 16:15:41.200409+07	role
manager::3	stage:dept_authorization:act::allow	2026-07-13 16:15:41.200409+07	role
manager::3	stage:dept_verification:act::allow	2026-07-13 16:15:41.200409+07	role
manager::3	finance:pr:approve::allow	2026-07-13 16:15:41.200409+07	role
manager::3	finance:expense:approve::allow	2026-07-13 16:15:41.200409+07	role
accounting_manager::3	tile:dash_am:view::allow	2026-07-13 16:15:41.200409+07	role
accounting_manager::3	tile:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
accounting_manager::3	stage:accounting_authorization:act::allow	2026-07-13 16:15:41.200409+07	role
sales_supervisor::2	stage:so_invoiced:act::allow	2026-07-13 16:15:41.200409+07	role
sales_supervisor::2	stage:so_credit_check:act::allow	2026-07-13 16:15:41.200409+07	role
finance::2	tile:dash_finance:view::allow	2026-07-13 16:15:41.200409+07	role
finance::2	tile:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
finance::2	stage:so_paid:act::allow	2026-07-13 16:15:41.200409+07	role
finance::2	stage:gl_confirmed:act::allow	2026-07-13 16:15:41.200409+07	role
finance::2	stage:disbursement_authorization:act::allow	2026-07-13 16:15:41.200409+07	role
finance::2	finance:expense:gl_confirm::allow	2026-07-13 16:15:41.200409+07	role
finance::2	finance:expense:settle::allow	2026-07-13 16:15:41.200409+07	role
finance::2	finance:expense:approve::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	tile:dash_finance:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	tile:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	stage:po_cfo:act::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	stage:cfo_authorization:act::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	finance:expense:override_approve::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	finance:expense:override::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	tile:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	stage:ceo_authorization:act::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	finance:expense:override_approve::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	finance:expense:override::allow	2026-07-13 16:15:41.200409+07	role
hr::5	tile:directory:view::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	access_request:request:resolve::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	access_request:request:list::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	tile:access_requests:view::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	tile:directory:view::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	org:auto_wire:apply::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	org:auto_wire:propose::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	org:dept:assign_head::allow	2026-07-13 16:15:41.200409+07	role
hr_manager::3	user:role:assign::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:provider:read::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:provider:create::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:provider:update::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:provider:delete::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:provider:test::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:model:read::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:model:create::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:model:update::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:model:delete::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:staff:read::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:staff:create::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:staff:update::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:staff:delete::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:staff:invoke::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:assignment:read::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:assignment:create::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:assignment:delete::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:invocation:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	ai:section_health:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	hook:event:replay::allow	2026-07-13 16:15:41.200409+07	role
it::2	hook:event:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:dash_it:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:hook:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:audit:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:tile_gates:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:roles:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:org_chart:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	tile:settings:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	org:dept:read::allow	2026-07-13 16:15:41.200409+07	role
it::2	org:tree:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	user:directory:read::allow	2026-07-13 16:15:41.200409+07	role
it::2	rbac:audit:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	rbac:matrix:edit::allow	2026-07-13 16:15:41.200409+07	role
it::2	rbac:matrix:view::allow	2026-07-13 16:15:41.200409+07	role
it::2	rbac:role:assign::allow	2026-07-13 16:15:41.200409+07	role
it::2	rbac:role:read::allow	2026-07-13 16:15:41.200409+07	role
admin::2	admin:system:bypass::allow	2026-07-13 16:15:41.200409+07	role
admin::2	finance:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	finance:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	finance:ledger:view::allow	2026-07-13 16:15:41.200409+07	role
admin::2	finance:report:executive::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	finance:report:executive::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	finance:report:executive::allow	2026-07-13 16:15:41.200409+07	role
admin::2	finance:budget:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	finance:budget:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	finance:budget:view::allow	2026-07-13 16:15:41.200409+07	role
admin::2	tile:reconciliation:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	tile:reconciliation:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	tile:reconciliation:view::allow	2026-07-13 16:15:41.200409+07	role
admin::2	tile:cockpit:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	tile:cockpit:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	tile:cockpit:view::allow	2026-07-13 16:15:41.200409+07	role
admin::2	tile:summary:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	tile:summary:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	tile:summary:view::allow	2026-07-13 16:15:41.200409+07	role
admin::2	tile:dash_exec:view::allow	2026-07-13 16:15:41.200409+07	role
cfo::2	tile:dash_exec:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	tile:dash_exec:view::allow	2026-07-13 16:15:41.200409+07	role
accounting_manager::3	tile:dash_finance:view::allow	2026-07-13 16:15:41.200409+07	role
admin::2	tile:dash_finance:view::allow	2026-07-13 16:15:41.200409+07	role
ceo::1	tile:dash_finance:view::allow	2026-07-13 16:15:41.200409+07	role
officer::5	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
hr::5	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
it::2	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
account_officer::5	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
account_supervisor::4	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
supervisor::4	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
sales_rep::3	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
manager::3	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
hr_manager::3	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
accounting_manager::3	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
sales_supervisor::2	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
finance::2	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
admin::2	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
cfo::2	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
ceo::1	system:authenticated:view::allow	2026-07-13 17:59:58.405188+07	baseline-9003
it::2	ai:chat:use::allow	2026-07-13 19:20:26.329145+07	migration-9005
officer::5	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
hr::5	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
account_officer::5	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
account_supervisor::4	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
supervisor::4	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
sales_rep::3	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
manager::3	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
hr_manager::3	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
accounting_manager::3	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
sales_supervisor::2	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
finance::2	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
admin::2	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
cfo::2	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
ceo::1	ai:chat:use::allow	2026-07-13 19:20:26.332985+07	migration-9005-baseline
sales_rep::3	finance:sales:settle::allow	2026-07-13 19:20:26.334964+07	migration-9005
sales_supervisor::2	finance:sales:settle::allow	2026-07-13 19:20:26.334964+07	migration-9005
admin::2	finance:sales:settle::allow	2026-07-13 19:20:26.334964+07	migration-9005
sales_rep::3	customer:manage::allow	2026-07-13 20:24:01.387339+07	migration-9007
sales_supervisor::2	customer:manage::allow	2026-07-13 20:24:01.387339+07	migration-9007
admin::2	customer:manage::allow	2026-07-13 20:24:01.387339+07	migration-9007
account_officer::5	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
account_officer::5	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
account_officer::5	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
account_supervisor::4	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
account_supervisor::4	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
account_supervisor::4	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
accounting_manager::3	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
accounting_manager::3	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
accounting_manager::3	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
finance::2	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
finance::2	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
finance::2	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
admin::2	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
admin::2	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
admin::2	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
cfo::2	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
cfo::2	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
cfo::2	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
ceo::1	finance:gl:view::allow	2026-07-13 20:24:01.390931+07	migration-9007
ceo::1	finance:gl:confirm::allow	2026-07-13 20:24:01.390931+07	migration-9007
ceo::1	finance:gl:post::allow	2026-07-13 20:24:01.390931+07	migration-9007
sales_rep::3	finance:sales:submit::allow	2026-07-13 20:24:01.394021+07	migration-9007
sales_supervisor::2	finance:sales:submit::allow	2026-07-13 20:24:01.394021+07	migration-9007
finance::2	finance:sales:submit::allow	2026-07-13 20:24:01.394021+07	migration-9007
admin::2	finance:sales:submit::allow	2026-07-13 20:24:01.394021+07	migration-9007
sales_supervisor::2	finance:sales:invoice::allow	2026-07-13 20:24:01.395047+07	migration-9007
finance::2	finance:sales:invoice::allow	2026-07-13 20:24:01.395047+07	migration-9007
admin::2	finance:sales:invoice::allow	2026-07-13 20:24:01.395047+07	migration-9007
officer::5	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
hr::5	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
it::2	tile:policy:view::allow	2026-07-13 23:59:51.803225+07	system-9009
it::2	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
account_officer::5	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
account_officer::5	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
account_officer::5	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
account_supervisor::4	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
account_supervisor::4	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
account_supervisor::4	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
supervisor::4	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
sales_rep::3	tile:customers:view::allow	2026-07-13 23:59:51.803225+07	system-9009
sales_rep::3	tile:sales:view::allow	2026-07-13 23:59:51.803225+07	system-9009
sales_rep::3	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	tile:po:view::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	stage:final_authorization:act::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	finance:po:reject::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	finance:po:approve::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	finance:expense:review::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
manager::3	user:subtree:edit::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	tile:departments:view::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	org:dept_role:list::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	org:dept_role:revoke::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	org:dept_role:assign::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	user:subtree:edit::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	user:dept:edit::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	user:manager:set::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	user:profile:deactivate::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	user:profile:update::allow	2026-07-13 23:59:51.803225+07	system-9009
hr_manager::3	user:profile:create::allow	2026-07-13 23:59:51.803225+07	system-9009
accounting_manager::3	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
accounting_manager::3	tile:po:view::allow	2026-07-13 23:59:51.803225+07	system-9009
accounting_manager::3	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
accounting_manager::3	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
sales_supervisor::2	tile:customers:view::allow	2026-07-13 23:59:51.803225+07	system-9009
sales_supervisor::2	tile:sales:view::allow	2026-07-13 23:59:51.803225+07	system-9009
sales_supervisor::2	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	tile:po:view::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:po:settle::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:po:attach_payslip::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:po:reject::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:po:approve::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:expense:review::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
finance::2	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	tile:departments:view::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	tile:policy:view::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	tile:customers:view::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	tile:sales:view::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	tile:po:view::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	finance:po:settle::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	finance:po:attach_payslip::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	finance:po:reject::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	finance:po:approve::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	org:dept_role:list::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	org:dept_role:revoke::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	org:dept_role:assign::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:subtree:edit::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:dept:edit::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:manager:set::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:profile:deactivate::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:profile:delete::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:profile:update::allow	2026-07-13 23:59:51.803225+07	system-9009
admin::2	user:profile:create::allow	2026-07-13 23:59:51.803225+07	system-9009
cfo::2	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
cfo::2	tile:po:view::allow	2026-07-13 23:59:51.803225+07	system-9009
cfo::2	finance:pr:override_approve::allow	2026-07-13 23:59:51.803225+07	system-9009
cfo::2	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
cfo::2	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
ceo::1	tile:search_coa:view::allow	2026-07-13 23:59:51.803225+07	system-9009
ceo::1	tile:po:view::allow	2026-07-13 23:59:51.803225+07	system-9009
ceo::1	finance:pr:override_approve::allow	2026-07-13 23:59:51.803225+07	system-9009
ceo::1	finance:expense:update::allow	2026-07-13 23:59:51.803225+07	system-9009
ceo::1	finance:expense:view_all::allow	2026-07-13 23:59:51.803225+07	system-9009
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.roles (id, display_name, description, is_system, sort_order, parent_role_id, display_name_th, display_name_de, monthly_budget, head_user_id, created_at) FROM stdin;
officer::5	Officer	Front-line operational staff	t	100	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
hr::5	HR Officer	Human-resources front-desk	t	101	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
it::2	IT Officer	Information technology	t	102	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
account_officer::5	Accounting Officer	Front-line accounting	t	103	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
account_supervisor::4	Accounting Supervisor	Accounting team lead	t	104	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
supervisor::4	Supervisor	Direct team supervisor	t	105	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
sales_rep::3	Sales Rep	Sales frontline	t	106	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
manager::3	Manager	Department-level manager	t	110	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
hr_manager::3	HR Manager	HR team manager	t	111	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
accounting_manager::3	Accounting Manager	Accounting team manager	t	112	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
sales_supervisor::2	Sales Supervisor	Sales team supervisor	t	113	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
finance::2	Finance Lead	Disbursement lead	t	120	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
admin::2	Admin	System administrator	t	130	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
cfo::2	CFO	Chief Financial Officer	t	131	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
ceo::1	CEO	Chief Executive Officer	t	132	\N	\N	\N	0.00	\N	2026-07-13 16:15:41.200409+07
dept-development	Development	\N	f	0	\N	\N	\N	2000000.00	\N	2026-07-14 12:45:13.408472+07
dept-marketing	Marketing	\N	f	0	\N	\N	\N	2000000.00	\N	2026-07-14 12:45:13.408472+07
dept-finance	Finance	\N	f	0	\N	\N	\N	2000000.00	\N	2026-07-14 12:45:13.408472+07
dept-executive	Executive	\N	f	0	\N	\N	\N	1000000.00	\N	2026-07-14 12:45:13.408472+07
dept-hr	HR	\N	f	0	\N	\N	\N	500000.00	\N	2026-07-14 12:45:13.408472+07
dept-it	IT	\N	f	0	\N	\N	\N	300000.00	\N	2026-07-14 12:45:13.408472+07
\.


--
-- Data for Name: tiles; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.tiles (id, display_name, subtitle, icon, accent, group_name, sub_view, href, request_target, sort_order, is_system, owner_group_id, view_perm_id, created_at, updated_at) FROM stdin;
inbox	Inbox	Approval queue	📥	sky	work	\N	/inbox	\N	10	t	\N	tile:inbox:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
expense	Expense	Submit / track claims	🧾	emerald	work	\N	/expense	\N	20	t	\N	tile:expense:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
pr	PR	Purchase requisitions	📝	violet	work	\N	/my-waybills?scope=mine&origin=pr	\N	30	t	\N	tile:pr:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
po	PO & Payslip	Purchase orders	📦	amber	work	\N	/my-waybills?scope=mine&origin=po	\N	40	t	\N	tile:po:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
sales	Sales Orders	Sales orders	💼	cyan	work	\N	/sales	\N	50	t	\N	tile:sales:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
customers	Customers	Customer master	👤	cyan	work	\N	/customers	\N	55	t	\N	tile:customers:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
search-coa	Search	Chart of accounts	🔍	slate	work	\N	/search-coa	\N	60	t	\N	tile:search_coa:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
reconciliation	Reconciliation	Bank reconciliation	🔀	amber	finance	\N	/reconciliation	\N	110	t	\N	tile:reconciliation:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
ledger	General Ledger	GL entries	📚	slate	finance	\N	/ledger	\N	120	t	\N	tile:ledger:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
cockpit	Executive Cockpit	CFO/CEO view	🛡	rose	exec	\N	/cockpit	\N	200	t	\N	tile:cockpit:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
summary	Cross-Slice Summary	Cross-cut dashboard	📊	slate	exec	\N	/summary	\N	210	t	\N	tile:summary:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
policy	RBAC Policy	Stage matrix	🎯	violet	admin	\N	/policy	\N	300	t	\N	tile:policy:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
org-chart	Org Chart	Org tree	🌳	sky	admin	\N	/org-chart	\N	310	t	\N	tile:org_chart:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
roles	Roles	Persona catalog	🪪	violet	admin	\N	/roles	\N	320	t	\N	tile:roles:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
tile-gates	Tile Gates	Visibility gates	🚪	slate	admin	\N	/tiles	\N	330	t	\N	tile:tile_gates:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
directory	User Management	User directory	👥	sky	admin	\N	/directory	\N	340	t	\N	tile:directory:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
audit	Audit	Audit log	📜	slate	admin	\N	/audit	\N	350	t	\N	tile:audit:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
departments	Departments	Dept registry	🏢	sky	admin	\N	/departments	\N	360	t	\N	tile:departments:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
access-requests	Access Requests	Pending access	🔑	amber	admin	\N	/access-requests	\N	370	t	\N	tile:access_requests:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
settings	AI Settings	Provider/model catalog	⚙️	slate	admin	\N	/settings	\N	380	t	\N	tile:settings:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
hook	Hook Events	Webhook log	🪝	slate	admin	\N	/hook	\N	390	t	\N	tile:hook:view::allow	2026-07-13 16:15:41.200409+07	2026-07-13 16:15:41.200409+07
\.


--
-- Data for Name: user_permissions; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.user_permissions (id, user_id, permission_id, granted_by, reason, granted_at, revoked_at, revoked_by, starts_at, ends_at) FROM stdin;
3	947	user:dept:development::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
4	956	user:dept:marketing::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
8	959	user:dept:development::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
9	950	user:dept:marketing::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
10	961	user:dept:marketing::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
11	964	user:dept:it::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
12	968	user:dept:it::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
14	951	user:dept:it::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
18	944	user:dept:executive::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
19	954	user:dept:development::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
23	945	user:dept:executive::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
24	960	user:dept:marketing::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
26	957	user:dept:it::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
2	967	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
7	955	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
13	952	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
15	965	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
16	946	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
17	948	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
20	953	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
22	963	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
25	966	user:dept:finance::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
5	949	user:dept:hr::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
6	958	user:dept:hr::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
21	962	user:dept:hr::allow	seed	department binding	2026-07-13 16:16:48.546793+07	\N	\N	2026-07-13 16:16:48.546793+07	\N
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: perm; Owner: -
--

COPY perm.user_roles (user_id, role_id, granted_at, granted_by) FROM stdin;
944	ceo::1	2026-07-13 16:16:48.546793+07	seed
945	cfo::2	2026-07-13 16:16:48.546793+07	seed
946	finance::2	2026-07-13 16:16:48.546793+07	seed
947	manager::3	2026-07-13 16:16:48.546793+07	seed
948	manager::3	2026-07-13 16:16:48.546793+07	seed
949	hr_manager::3	2026-07-13 16:16:48.546793+07	seed
950	manager::3	2026-07-13 16:16:48.546793+07	seed
951	manager::3	2026-07-13 16:16:48.546793+07	seed
952	accounting_manager::3	2026-07-13 16:16:48.546793+07	seed
953	manager::3	2026-07-13 16:16:48.546793+07	seed
954	supervisor::4	2026-07-13 16:16:48.546793+07	seed
955	account_supervisor::4	2026-07-13 16:16:48.546793+07	seed
956	supervisor::4	2026-07-13 16:16:48.546793+07	seed
957	supervisor::4	2026-07-13 16:16:48.546793+07	seed
958	supervisor::4	2026-07-13 16:16:48.546793+07	seed
959	officer::5	2026-07-13 16:16:48.546793+07	seed
960	officer::5	2026-07-13 16:16:48.546793+07	seed
961	officer::5	2026-07-13 16:16:48.546793+07	seed
962	hr::5	2026-07-13 16:16:48.546793+07	seed
963	officer::5	2026-07-13 16:16:48.546793+07	seed
964	it::2	2026-07-13 16:16:48.546793+07	seed
965	account_officer::5	2026-07-13 16:16:48.546793+07	seed
966	account_officer::5	2026-07-13 16:16:48.546793+07	seed
967	account_officer::5	2026-07-13 16:16:48.546793+07	seed
968	it::2	2026-07-13 16:16:48.546793+07	seed
\.


--
-- Data for Name: access_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.access_requests (id, actor_id, tile_id, tile_title, note, status, target_user_id, target_role, created_at, resolved_at, resolved_by_user_id, resolved_note) FROM stdin;
\.


--
-- Data for Name: ai_assignments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_assignments (id, section_key, task_type, provider_id, model_id, staff_id, params_json, priority, enabled, created_at, updated_at) FROM stdin;
9	staff-test:accountant-reviewer	chat	1	2	1	{}	50	t	2026-06-30 00:04:29.168203	2026-06-30 00:04:29.168203
1	acct:coa-search	embed	1	1	\N	{}	100	t	2026-06-29 23:59:23.12106	2026-07-09 11:46:09.256764
2	staff:submit	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.12343	2026-07-09 11:46:09.258308
23	acct:queue	chat	13	27	\N	{}	100	t	2026-07-01 00:22:55.992913	2026-07-09 11:46:09.258837
4	manager:approve	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.124294	2026-07-09 11:46:09.25935
3	am:review	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.123862	2026-07-09 11:46:09.25991
10	cfo:cockpit	chat	13	27	\N	{}	100	t	2026-06-30 00:04:41.773989	2026-07-09 11:46:09.26049
27	ceo:cockpit	chat	13	27	\N	{}	100	t	2026-07-01 00:22:55.994173	2026-07-09 11:46:09.260958
5	ledger:commentary	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.124694	2026-07-09 11:46:09.261444
6	policy:editor	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.125171	2026-07-09 11:46:09.261899
7	command:intent	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.125543	2026-07-09 11:46:09.262356
8	notification:digest	chat	13	27	\N	{}	100	t	2026-06-29 23:59:23.125779	2026-07-09 11:46:09.262794
93	waybill:settle	vision	13	27	\N	{}	100	t	2026-07-09 01:04:55.518676	2026-07-09 11:46:09.263215
94	waybill:assist	chat	13	27	\N	{}	100	t	2026-07-09 01:04:55.526189	2026-07-09 11:46:09.26361
21	staff:ocr	vision	13	27	\N	{"temperature": 0.1}	100	t	2026-07-01 00:22:55.991634	2026-07-09 12:13:00.053823
\.


--
-- Data for Name: ai_invocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_invocations (id, staff_id, section_key, task_type, provider_id, model_id, prompt_tokens, response_tokens, latency_ms, status, error, prompt_excerpt, response_excerpt, actor_id, created_at) FROM stdin;
203	\N	acct:coa-search	embed	1	1	3	0	1530	ok	\N	ค่าคอมมิชชัน		\N	2026-07-08 16:22:32.651905
204	\N	acct:coa-search	embed	1	1	3	0	147	ok	\N	ค่าแพนฟิเล		\N	2026-07-08 16:22:32.651905
211	\N	acct:coa-search	embed	1	1	4	0	1525	ok	\N	ค่าอาหารกลางวัน		\N	2026-07-08 19:16:52.303354
212	\N	acct:coa-search	embed	1	1	4	0	151	ok	\N	ค่าบริการอื่น		\N	2026-07-08 19:16:52.303354
215	\N	acct:coa-search	embed	1	1	4	0	1004	ok	\N	ค่าตอบแทนลางเสือ		\N	2026-07-08 19:25:47.780055
216	\N	acct:coa-search	embed	1	1	3	0	145	ok	\N	ค่าพัฒนาที่		\N	2026-07-08 19:25:47.780055
218	\N	staff:ocr	vision	13	27	\N	\N	1391	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 11:27:22.18904
220	\N	staff:ocr	vision	13	27	\N	\N	473	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 11:39:00.204009
223	\N	staff:ocr	vision	13	27	\N	\N	462	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 11:45:16.928548
226	\N	staff:ocr	vision	13	27	\N	\N	573	error	Request failed with status code 401	Parse this document text:\ntest payload\n	\N	\N	2026-07-09 11:56:46.870999
229	\N	staff:ocr	vision	13	27	\N	\N	770	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 12:02:49.762754
234	\N	staff:ocr	vision	13	27	\N	\N	459	error	Request failed with status code 401	Parse this document text:\ntest receipt sample\n	\N	\N	2026-07-09 12:11:41.223793
205	\N	staff:ocr	vision	1	\N	17	70	102689	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED",\n  "transactionDate": "2025-02-27",\n  "subtotal": 8094436,\n  "vatAmount": 0,\n  "totalAmount": 8094436,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": []\n}	\N	2026-07-08 17:53:45.247484
219	\N	staff:ocr	vision	13	\N	\N	\N	838	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 11:27:51.295168
225	\N	staff:ocr	vision	13	\N	\N	\N	1565	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 11:52:14.524346
228	\N	staff:ocr	vision	13	\N	\N	\N	874	error	Request failed with status code 401	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 12:02:26.506201
236	\N	staff:ocr	vision	13	27	12	149	3064	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user has provided a very minimal document text: "test receipt sample". There's no actual receipt data to parse - no vendor name, no date, no amounts, no items. I should return a valid JSON response with empty/zero fields and explain in correctionNotes that this is not a valid receipt.</think>\n\n{"vendorName":"","transactionDate":"","subtotal":0,"vatAmount":0,"totalAmount":0,"paymentMethod":"cash","currency":"THB","isCorrupted":true,"correctionNotes":"Document contains only the placehol	\N	2026-07-09 12:12:51.870769
237	\N	staff:ocr	vision	13	27	12	264	7036	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user wants me to parse a document text that says "test receipt sample". This is essentially no useful information for parsing a receipt. Let me return the appropriate JSON with empty/default values and note that it's corrupted/illegible.\n\nSince there's no real receipt data here, I should:\n- Set vendorName to ""\n- transactionDate to ""\n- subtotal, vatAmount, totalAmount to 0\n- paymentMethod to "cash" as default\n- currency to "THB" as default\n- isCorrupted to true since there's no actua	\N	2026-07-09 12:13:28.242252
238	\N	staff:ocr	vision	13	27	12	261	3335	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user has provided very minimal text: "test receipt sample". This appears to be a test or sample input with no actual receipt data. There's no vendor name, date, items, amounts, or any other useful information.\n\nI should return a JSON response with empty/zero values and note in correctionNotes that the input is not a real receipt - it's just a test sample.\n\nLet me construct the response:\n- vendorName: "" (empty)\n- transactionDate: "" (empty, can't determine)\n- subtotal: 0\n- vatAmount: 	\N	2026-07-09 12:13:31.683092
241	\N	staff:ocr	vision	13	27	17	1572	30000	ok	\N	Analyze the attached receipt image and return the structured JSON.	<think>Let me analyze this Thai receipt carefully.\n\n**Vendor Information:**\n- ชื่อลูกค้า (Customer Name): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- อีเมล์ (Email): hello@beamdigital.co.th\n- ผู้ติดต่อ (Contact): คุณเจนจิรา\n- เบอร์โทรศัพท์ (Phone): 098-765-4310\n\n**Receipt Details:**\n- เลขที่ (Receipt No.): 06987\n- วันที่ (Date): 4 สิงหาคม 2025 (4 August 2025)\n- กรกฎาคม (July?) 4 กันยา	\N	2026-07-09 12:16:51.278344
194	\N	staff:ocr	vision	1	\N	17	101	51203	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท บีมดิกัล จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าอุปกรณ์/สินค้า",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าคอมมิชชัน",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 14:56:32.295416
195	\N	staff:ocr	vision	1	\N	17	100	40981	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท เบิมดิจิทัล จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "credit_card",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าอีกแบบ",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าเพิ่ม",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 15:33:13.478253
196	\N	staff:ocr	vision	1	\N	\N	\N	1514	error	Request failed with status code 400	Analyze the attached bank passbook image and return the structured JSON.	\N	\N	2026-07-08 15:42:29.109828
197	\N	staff:ocr	vision	1	\N	\N	\N	155	error	Request failed with status code 400	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-08 15:42:40.482929
198	\N	staff:ocr	vision	1	\N	18	73	10933	ok	\N	Analyze the attached bank passbook image and return the structured JSON.	{\n  "bankName": "",\n  "bankBranch": "",\n  "accountNumber": "",\n  "accountName": "",\n  "isCorrupted": true,\n  "correctionNotes": "Image does not show a bank passbook page; only a document management interface visible. Please upload a valid Thai bank passbook cover or account-detail page."\n}	\N	2026-07-08 15:43:06.4398
199	\N	staff:ocr	vision	1	\N	17	103	25800	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท วิบูลย์มาร์เก็ติ้ง จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าตอบแทนลาสซี",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าพัฒนาแล้ว",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 15:45:46.633257
200	\N	staff:ocr	vision	1	\N	18	52	89067	ok	\N	Analyze the attached bank passbook image and return the structured JSON.	{\n  "bankName": "SCB",\n  "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต",\n  "accountNumber": "0123456789",\n  "accountName": "บริษัท ไออูเปฟเทคโนโลยี จํากัด",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-08 15:46:51.064716
201	\N	staff:ocr	vision	1	\N	17	101	47669	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท บีมแอนด์ ดีโกลล์ จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าคอมมิชชัน",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าแพนฟิเล",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 15:55:21.630295
202	\N	staff:ocr	vision	1	\N	18	49	116005	ok	\N	Analyze the attached bank passbook image and return the structured JSON.	{\n  "bankName": "SCB",\n  "bankBranch": "0080 สายาพิว เจอ้พา รัต รังสิต",\n  "accountNumber": "0123456789",\n  "accountName": "อุมาพิมพ์ จึงภูพิน",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-08 15:56:38.672528
240	\N	staff:ocr	vision	13	\N	\N	\N	2509	error	Request failed with status code 400	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 12:16:16.832602
206	\N	staff:ocr	vision	1	\N	17	105	43799	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท บีมดิจิตัล ได้โกว์ จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "credit_card",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "เกษท์แบบลายเลือด",\n      "amount": 5000\n    },\n    {\n      "description": "ต่ำที่ป่าเลือด",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 18:05:43.603509
207	\N	staff:ocr	vision	1	\N	17	101	77310	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท เดอะมอลล์ จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าตอบแทนรายเดือน",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าทําพลาฟี",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 19:07:37.004416
208	\N	staff:ocr	vision	1	\N	18	51	266459	ok	\N	Analyze the attached bank passbook image and return the structured JSON.	{\n  "bankName": "SCB",\n  "bankBranch": "0080 สาขาพีวิจาระจว่าทั้งตี",\n  "accountNumber": "0123456789",\n  "accountName": "บริษัท ไอวอล์พีเทคโนโลยี่ จำกัด",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-08 19:10:49.810216
209	\N	staff:ocr	vision	1	\N	17	100	26711	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท บิ๊กแมด จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าอาหารกลางวัน",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าบริการอื่น",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 19:14:18.551333
210	\N	staff:ocr	vision	1	\N	18	48	31684	ok	\N	Analyze the attached bank passbook image and return the structured JSON.	{\n  "bankName": "SCB",\n  "bankBranch": "0080 สาขาสาทิวเจอทรัค รังสิต",\n  "accountNumber": "0123456789",\n  "accountName": "บุญชัย เดิมคามนท์",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-08 19:16:13.932304
213	\N	staff:ocr	vision	1	\N	17	103	47414	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท ไปร์สแลนด์ ดีโกล จํากัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าตอบแทนลางเสือ",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าพัฒนาที่",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 19:24:54.538914
214	\N	staff:ocr	vision	1	\N	18	49	37979	ok	\N	Analyze the attached bank passbook image and return the structured JSON.	{\n  "bankName": "SCB",\n  "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต",\n  "accountNumber": "0123456789",\n  "accountName": "ไอแองพลอคโนโลยี จำกัด",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-08 19:25:42.019821
217	\N	staff:ocr	vision	1	\N	17	102	48677	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท บีมอเลนต์ ดีโกล จำกัด",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าตอบแทนเลือด",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าแพนเพลิโอ",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-08 19:27:34.312297
221	\N	staff:ocr	vision	1	\N	\N	\N	3253	error	Request failed with status code 400	Analyze the attached receipt image and return the structured JSON.	\N	\N	2026-07-09 11:39:19.610159
222	\N	staff:ocr	vision	1	\N	17	60	41658	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": true,\n  "correctionNotes": "No text detected on receipt",\n  "items": []\n}	\N	2026-07-09 11:40:15.411734
224	\N	staff:ocr	vision	1	\N	17	66	51856	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": true,\n  "correctionNotes": "Receipt image is completely blank; no data found.",\n  "items": []\n}	\N	2026-07-09 11:46:09.128085
227	\N	staff:ocr	vision	1	\N	12	69	7840	ok	\N	Parse this document text:\ntest receipt sample\n	{"vendorName":"test receipt sample","transactionDate":"","subtotal":0,"vatAmount":0,"totalAmount":0,"paymentMethod":"cash","currency":"THB","isCorrupted":true,"correctionNotes":"No actual receipt content provided; only placeholder text 'test receipt sample' found","items":[]}	\N	2026-07-09 11:58:13.993919
230	\N	staff:ocr	vision	1	\N	12	54	25643	ok	\N	Parse this document text:\ntest receipt sample\n	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": []\n}	\N	2026-07-09 12:05:35.462058
231	\N	staff:ocr	vision	1	\N	12	72	32433	ok	\N	Parse this document text:\ntest receipt sample\n	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": true,\n  "correctionNotes": "No valid transaction data found; document contains only placeholder text.",\n  "items": []\n}	\N	2026-07-09 12:06:12.633836
232	\N	staff:ocr	vision	1	\N	12	87	51726	ok	\N	Parse this document text:\ntest receipt sample\n	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": true,\n  "correctionNotes": "No vendor name, transaction date, or itemized details found. Receipt text only contains 'test receipt sample' with no numerical data.",\n  "items": []\n}	\N	2026-07-09 12:07:04.412697
233	\N	staff:ocr	vision	1	\N	12	54	40639	ok	\N	Parse this document text:\ntest receipt sample\n	{"vendorName":"", "transactionDate":"", "subtotal":0, "vatAmount":0, "totalAmount":0, "paymentMethod":"cash", "currency":"THB", "isCorrupted":true, "correctionNotes":"No valid receipt content provided.", "items":[]}	\N	2026-07-09 12:11:35.586418
235	\N	staff:ocr	vision	1	\N	12	66	35084	ok	\N	Parse this document text:\ntest receipt sample\n	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": true,\n  "correctionNotes": "No valid transaction details found; data is empty.",\n  "items": []\n}	\N	2026-07-09 12:12:16.393384
239	\N	staff:ocr	vision	1	\N	12	71	85196	ok	\N	Parse this document text:\ntest receipt sample\n	{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 0,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": true,\n  "correctionNotes": "No valid receipt data extracted; only 'test receipt sample' provided.",\n  "items": []\n}	\N	2026-07-09 12:14:56.964484
242	\N	staff:ocr	vision	13	27	12	204	4316	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user has provided minimal text: "test receipt sample". This is clearly not a real receipt - it's just a test/sample placeholder text. There's no vendor name, no date, no amounts, no items, no payment method.\n\nI need to return a valid JSON object matching the schema, with fields set to empty/0 where no data is available, and explain in correctionNotes why it's corrupted.</think>\n\n```json\n{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal": 0,\n  "vatAmount": 0,\n  "totalAmount": 	\N	2026-07-09 12:18:50.11478
244	\N	staff:ocr	vision	13	27	12	194	4559	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user has provided minimal text: "test receipt sample". This is not a real receipt with vendor name, date, items, totals, or any other usable information. I need to follow the rules: never guess, set fields to "" or 0 when illegible, and explain in correctionNotes.\n\nLet me construct the JSON response with empty/zero values where appropriate, mark isCorrupted=true, and explain in correctionNotes that the document text is insufficient/illegible.</think>\n\n{"vendorName":"","transactionDate	\N	2026-07-09 12:21:28.161278
245	\N	staff:ocr	vision	13	27	12	230	2658	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user has provided minimal text "test receipt sample" - this appears to be a placeholder or test input, not an actual receipt. There's no vendor name, no date, no line items, no totals, no payment method information.\n\nI need to follow the rules:\n- Never guess. If a field is illegible, set it to "" or 0 and explain in correctionNotes.\n- This is clearly corrupted/unusable data\n\nLet me return the JSON with empty/zero values and explain in correctionNotes that this is a test sample with no	\N	2026-07-09 12:21:30.928755
248	\N	staff:ocr	vision	13	27	17	696	20640	ok	\N	Analyze the attached receipt image and return the structured JSON.	<think>Let me analyze this Thai receipt carefully.\n\nVendor information:\n- ชื่อลูกค้า (Customer name): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- อีเมล์ (Email): hello@beamdigital.co.th\n- ผู้ติดต่อ (Contact person): คุณเจนจิรา\n- เบอร์โทรศัพท์ (Phone): 098-765-4310\n\nReceipt details:\n- เลขที่ (Number): 06987\n- วันที่ (Date): 4 สิงหาคม 2025 (4 August 2025) → 2025-08-04\n- กรกฎาคม 2025 (li	\N	2026-07-09 12:22:58.069709
249	\N	staff:ocr	vision	13	27	12	298	4983	ok	\N	Parse this document text:\ntest receipt sample\n	<think>The user wants me to parse a document, but they've only provided "test receipt sample" as the text. There's no actual receipt content to parse. I should indicate this in the response - there's no real receipt data to extract.\n\nSince this is a test/sample with no actual receipt data, I should return a response that indicates the document is essentially empty or has no parseable receipt data. The most appropriate response would be to return a JSON with empty/zero values and a note explainin	\N	2026-07-09 12:29:18.538882
251	\N	staff:ocr	vision	13	27	17	1167	34243	ok	\N	Analyze the attached receipt image and return the structured JSON.	<think>Let me analyze this Thai receipt carefully.\n\nVendor Name: Looking at the receipt, the top says "ใบเสร็จรับเงิน / Receipt" - this is the document type, not the vendor. The vendor info section shows:\n- ชื่อลูกค้า (Customer Name): บริษัท บีมเอ็กซ์ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- ผู้ติดต่อ (Contact): คุณเจนจิรา\n- อีเมล์: hello@beamdigital.co.th\n- เบอร์โทรศัพท์: 098-765-4310\n- เลขที่ (Rece	\N	2026-07-09 12:34:02.788026
243	\N	staff:ocr	vision	13	\N	\N	\N	286	error	Request failed with status code 400	Parse this document text:\ntest receipt sample\n	\N	\N	2026-07-09 12:18:50.497064
246	\N	staff:ocr	vision	13	\N	12	195	5589	ok	\N	Parse this document text:\ntest receipt sample\n	<think>\nThe user has provided just "test receipt sample" as the document text. This is not an actual receipt with any data to parse. I need to return a JSON response following the schema, but since there's no actual receipt data, I should indicate this appropriately.\n\nSince there's no actual receipt content to parse, I should return the JSON with isCorrupted set to true and a note explaining that no receipt data was provided.\n</think>\n\n{\n  "vendorName": "",\n  "transactionDate": "",\n  "subtotal":	\N	2026-07-09 12:21:36.623825
247	\N	staff:ocr	vision	13	\N	17	164	5758	ok	\N	Analyze the attached receipt image and return the structured JSON.	<think>\nThe user wants me to analyze a receipt image and return structured JSON. However, I don't see any image attached to this message. I need to let the user know that no image was provided and ask them to attach the receipt image.\n\nWait, let me re-read the message. The user says "Analyze the attached receipt image and return the structured JSON." but there's no image visible in the conversation. \n\nI should respond that I don't see any attached image and ask them to provide one.\n</think>\n\nNo 	\N	2026-07-09 12:22:26.817608
250	\N	staff:ocr	vision	13	\N	12	157	5840	ok	\N	Parse this document text:\ntest receipt sample\n	<think>\nThe user is asking me to parse a document text labeled "test receipt sample" but I don't see any actual image or document attached to this message. There's no receipt image, no OCR text, nothing for me to extract information from.\n\nI should respond that I don't see any receipt image or document attached, and ask the user to provide the actual receipt image/document they want me to parse.\n</think>\n\nI don't see any receipt image or document attached to your message. Please provide the actu	\N	2026-07-09 12:29:24.475494
252	\N	staff:ocr	vision	13	\N	17	180	8759	ok	\N	Analyze the attached receipt image and return the structured JSON.	<think>\nThe user wants me to analyze a receipt image and return structured JSON. However, I don't see any image attached to this message. Let me check again...\n\nLooking at the message, there's no image provided. I need to inform the user that no image was attached and cannot proceed with the analysis.\n\nWait, let me reconsider - sometimes images are embedded differently or there might be a URL I should look for. But as of now, I don't see any image data in the user's message.\n\nI should respond th	\N	2026-07-09 12:34:17.619542
253	\N	staff:ocr	vision	13	27	17	949	24126	ok	\N	Analyze the attached receipt image and return the structured JSON.	<think>Let me analyze this Thai receipt carefully.\n\n**Header:**\n- Title: "ใบเสร็จรับเงิน / Receipt"\n- Vendor info: บริษัท บีมเออนซี่ แอนด์ ดิจิทอล จำกัด (Beam Agency and Digital Co., Ltd.)\n- Address: 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- Tax ID: 098-765-4310\n- Email: hello@beamdigital.co.th\n- Customer: คุณเจนจิรา (Khun Jenjira)\n- Sales rep phone: 098-765-4310\n\n**Receipt details:**\n- เลขที่ (Receipt No.): 06987\n- วันที่ (Date): 4 สิงหาคม 2025 → 2025-08-04\n- ครบกำหนด (Due date):	\N	2026-07-09 12:36:32.067575
254	\N	staff:ocr	vision	1	612	17	104	68280	ok	\N	Analyze the attached receipt image and return the structured JSON.	{\n  "vendorName": "บริษัท นีวิน แอนด์ วัน เจ้าสิ้น",\n  "transactionDate": "2025-08-04",\n  "subtotal": 9000,\n  "vatAmount": 630,\n  "totalAmount": 9630,\n  "paymentMethod": "cash",\n  "currency": "THB",\n  "isCorrupted": false,\n  "correctionNotes": "",\n  "items": [\n    {\n      "description": "ค่าออมแผนล่าเลือด",\n      "amount": 5000\n    },\n    {\n      "description": "ค่าเพิ่มพันเลือด",\n      "amount": 4000\n    }\n  ]\n}	\N	2026-07-09 12:37:40.531845
255	\N	staff:ocr	vision	13	27	24	358	16271	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this receipt carefully.\n\nVendor information:\n- ชื่อลูกค้า (Customer name): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- อีเมล์ (Email): hello@beamdigital.co.th\n- ผู้ติดต่อ (Contact): คุณเจนจิรา\n- เบอร์โทรศัพท์ (Phone): 098-765-4310\n\nReceipt details:\n- เลขที่ (Receipt No.): 06987\n- วันที่ (Date): 4 สิงหาคม 2025\n- ครบกำหนด (Due date): 4 กันยายน 2025\n- อ้างอิง (Refer	\N	2026-07-09 12:38:22.957369
256	\N	staff:ocr	vision	13	27	24	393	13690	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>The user wants me to extract structured fields from this Thai receipt. Let me analyze it carefully.\n\nLooking at the receipt:\n- Title: ใบเสร็จรับเงิน / Receipt\n- Vendor name (ชื่อลูกค้า): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n- Address (ที่อยู่): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- Tax ID (เลขผู้เสียภาษี): 098-765-4310\n- Branch (สาขา): - (blank)\n- Email: hello@beamdigital.co.th\n- Contact (ผู้ติดต่อ): คุณเจนจิรา\n- Phone: 098-765-4310\n- Receipt number (เลขที่): 06987\n- 	\N	2026-07-09 12:39:20.800389
257	\N	staff:ocr	vision	13	27	24	246	14958	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>The user wants me to extract structured fields from this Thai receipt. Let me analyze the receipt carefully.\n\nVendor Name: บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด (Beam Agency and Digital Co., Ltd.)\n\nTransaction Date: 4 สิงหาคม 2025 = 2025-08-04\n\nItems:\n1. ค่าออกแบบลายเสื้อ - qty 1, price 5,000, total 5,000.00\n2. ค่าพิมพ์เสื้อ - qty 20, price 200, total 4,000.00\n\nSubtotal: 9,000.00\nVAT (7%): 630.00\nDiscount: 0.00\nTotal: 9,630.00\n\nCheck: 9,000 + 630 = 9,630 ✓\n\nPayment method: None of the ra	\N	2026-07-09 12:40:06.722883
258	\N	staff:ocr	vision	13	27	24	282	11928	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor name: บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n\nTransaction date: 4 สิงหาคม 2025 → 2025-08-04\n\nItems:\n1. ค่าออกแบบลายเสื้อ - quantity 1, unit price 5,000, amount 5,000.00\n2. ค่าพิมพ์เสื้อ - quantity 20, unit price 200, amount 4,000.00\n\nSubtotal (หมายเหตุ - which appears to mean total here): 9,000.00\nVAT (ภาษีมูลค่าเพิ่ม 7%): 630.00\nDiscount (ส่วนลด): 0.00\nTotal (จำนวนเงินรวมทั้งสิ้น): 9,630 บาท\n\nCurrency: THB\nPayment method: เงินสด is sele	\N	2026-07-09 12:41:30.798781
259	\N	staff:ocr	vision	13	27	26	141	13365	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	<think>The user wants me to extract information from a Thai bank passbook image. Let me analyze what I see:\n\n- Name: บริษัท ไอแอพพ์เทคโนโลยี จำกัด\n- Bank: ธนาคารไทยพาณิชย์ จำกัด (มหาชน) / SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED\n- Branch: 0080 สาขาฟิวเจอร์พาร์ค รังสิต\n- Account No: 012-345678-9\n- Type: บัญชีเงินฝากออมทรัพย์ (Savings Account)\n\nLet me format this as JSON.</think>\n\n{"bankName":"SCB","bankBranch":"0080 สาขาฟิวเจอร์พาร์ค รังสิต","accountNumber":"0123456789","accountName":"บริษัท ไ	\N	2026-07-09 12:42:00.705114
260	\N	acct:coa-search	embed	1	1	5	0	1528	ok	\N	ค่าออกแบบลายเสื้อ		\N	2026-07-09 12:42:11.902188
261	\N	acct:coa-search	embed	1	1	4	0	150	ok	\N	ค่าพิมพ์เสื้อ		\N	2026-07-09 12:42:11.902188
262	\N	staff:ocr	vision	13	27	24	505	13752	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>The user wants me to extract structured fields from this receipt image. Let me analyze what I see:\n\nThis appears to be a Siam Commercial Bank (SCB) savings account passbook, not a typical receipt. It shows:\n- Name: บริษัท ไอแอพพ์เทคโนโลยี จำกัด\n- Bank: ธนาคารไทยพาณิชย์ จำกัด (มหาชน) / SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED\n- Branch: 0080 สาขาฟิวเจอร์พาร์ค รังสิต\n- Account No: 012-345678-9\n- Account Type: SAVINGS ACCOUNT\n- Number at bottom: 8094436\n\nThis is a bank account passbook ent	\N	2026-07-09 13:53:56.812687
263	\N	staff:ocr	vision	13	27	24	344	10670	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>This is a Thai savings account passbook from Siam Commercial Bank. It's not a receipt in the traditional sense - it's a bank passbook showing account details. Let me analyze what's visible:\n\n- Name: บริษัท ไอแอพพ์เทคโนโลยี จำกัด\n- Bank: ธนาคารไทยพาณิชย์ จำกัด (มหาชน) / SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED\n- Branch: 0080 สาขาฟิวเจอร์พาร์ค รังสิต\n- Account No: 012-345678-9\n- Type: บัญชีเงินฝากออมทรัพย์ / SAVINGS ACCOUNT\n\nThere's no transaction date, no subtotal, no VAT, no total amou	\N	2026-07-09 16:37:28.689455
264	\N	staff:ocr	vision	13	27	24	332	9808	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor Name: บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด (Beam Agency and Digital Co., Ltd.)\n\nDate: 4 สิงหาคม 2025 → 2025-08-04 (Christian era)\n\nItems:\n1. ค่าออกแบบลายเสื้อ - 1 unit × 5,000 = 5,000.00\n2. ค่าพิมพ์เสื้อ - 20 units × 200 = 4,000.00\n\nSubtotal (หมายเหตุ - actually means "amount"): 9,000.00\nVAT (ภาษีมูลค่าเพิ่ม 7%): 630.00\nDiscount (ส่วนลด): 0.00\nTotal: 9,630 บาท\n\nLet me check: 9,000 + 630 = 9,630. ✓\n\nPayment method: No radio button is se	\N	2026-07-09 16:37:34.943415
265	\N	staff:ocr	vision	13	27	24	1054	32212	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully:\n\n**Vendor Information:**\n- ชื่อลูกค้า (Customer name): บริษัท บีมเอเจนซ์ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- อีเมล์ (Email): hello@beamdigital.co.th\n- ผู้ติดต่อ (Contact): คุณเจนจิรา\n- เบอร์โทรศัพท์ (Phone): 098-765-4310\n\n**Receipt Details:**\n- เลขที่ (Receipt No.): 06987\n- วันที่ (Date): 4 สิงหาคม 2025 (4 August 2025) - This is CE year\n- ครบกำห	\N	2026-07-09 17:00:44.700232
266	\N	staff:ocr	vision	1	612	24	77	86756	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท นวัตกรรม สื่อสาร จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"cash","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าออนไลน์","amount":5000},{"description":"ค่าพนักงาน","amount":4000}]}	\N	2026-07-09 17:02:16.68987
267	\N	staff:ocr	vision	1	612	24	79	52859	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท บันทึกอีสาน ติดข้อบุญ จังหวัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าตอบแทนลาวที่","amount":5000},{"description":"ค่าเพิ่มพัสดุ","amount":4000}]}	\N	2026-07-09 17:36:10.741047
268	\N	staff:ocr	vision	1	612	24	78	162548	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท เน็ตวอร์ค ดีจิทอล จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"cash","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าออมบุญมาเลือ","amount":5000},{"description":"ค่ามีที่","amount":4000}]}	\N	2026-07-09 17:40:15.605363
269	\N	staff:ocr	vision	1	612	24	80	24427	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท นิรันดร์ แล้ว ดีจูอล่า จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"cash","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าออลามูลม้าเลือ","amount":5000},{"description":"ค่าพัฒน์เลือ","amount":4000}]}	\N	2026-07-09 17:43:22.650471
270	\N	staff:ocr	vision	1	612	24	77	49931	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท เบมดิจิตอล จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าตอบแทนลายสือ","amount":5000},{"description":"ค่าเพิ่มทั้งสิ้น","amount":4000}]}	\N	2026-07-09 17:44:13.404844
271	\N	staff:ocr	vision	1	612	24	80	65717	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"cash","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"คำออลมาแลยเอือ","amount":5000},{"description":"คำพมพทเลือ","amount":4000}]}	\N	2026-07-09 17:44:52.302369
272	\N	staff:ocr	vision	13	27	26	164	7782	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	<think>\nThe user wants me to extract structured information from a Thai bank passbook image. Let me analyze the image carefully.\n\nFrom the image I can see:\n- Bank name: ธนาคารไทยพาณิชย์ จำกัด (มหาชน) / SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED → SCB\n- Branch: 0080 สาขาฟิวเจอร์พาร์ค รังสิต\n- Account Number: 012-345678-9 → 0123456789\n- Account Name: บริษัท ไอแอพพ์เทคโนโลยี จำกัด\n- Account type: บัญชีเงินฝากออมทรัพย์ / SAVINGS ACCOUNT\n\nLet me format this as JSON.\n</think>\n{"bankName":"SCB","bankB	\N	2026-07-09 17:49:02.202249
273	\N	acct:coa-search	embed	1	1	4	0	1256	ok	\N	คำออลมาแลยเอือ		\N	2026-07-09 17:49:14.654858
274	\N	acct:coa-search	embed	1	1	3	0	199	ok	\N	คำพมพทเลือ		\N	2026-07-09 17:49:14.654858
275	\N	staff:ocr	vision	1	612	26	51	289930	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	{\n  "bankName": "SCB",\n  "bankBranch": "0080 สายพิวเจอราล รังสิต",\n  "accountNumber": "0123456789",\n  "accountName": "บิ๊นท์ ไอแอดพัทธ์ จ้างดู (มหัส)",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-09 17:50:03.059892
276	\N	staff:ocr	vision	13	27	24	2193	40236	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor name (ชื่อลูกค้า - actually this seems to be the customer/vendor at top): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\nAddress: 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\nTax ID (เลขผู้เสียภาษี): 098-765-4310\nBranch (สาขา): สำนักงานใหญ่ (head office)\nRecipient name (ผู้รับเงิน): คุณเจนจิรา\n\nReceipt number (เลขที่): 06987\nDate (วันที่): 4 สิงหาคม 2025 = 2025-08-04\nBilling date (ครบกำหนด): 4 กันยายน 2025\n\nRecipient/Customer (ผู้ออก..	\N	2026-07-09 19:29:16.286311
277	\N	acct:coa-search	embed	1	1	5	0	1534	ok	\N	ค่าออกแบบลายเสื้อ		\N	2026-07-09 19:29:30.595067
278	\N	acct:coa-search	embed	1	1	4	0	141	ok	\N	ค่าพิมพ์เสื้อ		\N	2026-07-09 19:29:30.595067
279	\N	staff:ocr	vision	13	27	24	1004	21699	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>\nLet me analyze this receipt carefully.\n\nThe receipt is a Thai receipt (ใบเสร็จรับเงิน).\n\nVendor information (ผู้ขาย/ร้านค้า - which is the seller):\n- ชื่อลูกค้า (Customer name): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- ผู้ติดต่อ (Contact): คุณเจนจิรา\n- อีเมล (Email): hello@beamdigital.co.th\n- เบอร์โทรศัพท์ (Phone): 098-765-4310\n\nWait, looking more carefully. The "ชื่อลูกค้า	\N	2026-07-09 22:37:13.669892
280	\N	staff:ocr	vision	13	27	24	299	7356	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor name: บริษัท บีมเอเชนซ์ แอนด์ ดิจิทอล จำกัด (Beam Agency and Digital Co., Ltd.)\n\nTransaction date: 4 สิงหาคม 2025 = August 4, 2025 = 2025-08-04\n\nItems:\n1. ค่าออกแบบลายเสื้อ - จำนวน 1, ราคา/หน่วย 5,000, ราคารวม 5,000.00\n2. ค่าพิมพ์เสื้อ - จำนวน 20, ราคา/หน่วย 200, ราคารวม 4,000.00\n\nSubtotal: 9,000.00\nVAT (7%): 630.00\nDiscount: 0.00\nTotal: 9,630 บาท (nine thousand six hundred thirty baht only)\n\nCheck: 9000 + 630 = 9630 ✓\n\nPayment method: N	\N	2026-07-09 22:37:21.591011
281	\N	staff:ocr	vision	13	27	24	377	12544	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor name: บริษัท บีมเอจเจ แอนด์ ดิจิทอล จำกัด (Beam Age and Digital Co., Ltd.)\n\nReceipt number: 06987\nDate (วันที่): 4 สิงหาคม 2025 → 2025-08-04\nDue date (ครบกำหนด): 4 กันยายน 2025\n\nCustomer: บริษัท ไบรท์มิลล์ ดิจิตอล จำกัด\nTax ID: 0123456789123\n\nItems:\n1. ค่าออกแบบลายเสื้อ - qty 1, unit 5,000, total 5,000.00\n2. ค่าพิมพ์เสื้อ - qty 20, unit 200, total 4,000.00\n\nSubtotal (หมายเหตุ): 9,000.00\nVAT (ภาษีมูลค่าเพิ่ม 7%): 630.00\nDiscount (ส่วนลด):	\N	2026-07-09 23:06:31.55666
282	\N	staff:ocr	vision	13	27	24	1045	20289	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>The user wants me to extract structured JSON from this Thai receipt. Let me analyze the receipt carefully.\n\nReceipt details:\n- Title: ใบเสร็จรับเงิน / Receipt\n- Vendor name (ชื่อลูกค้า - which means "Customer name" - this is actually the issuer/vendor): บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\n- Address (ที่อยู่): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- Phone (เลขผู้เสียภาษี): 098-765-4310\n- Email (อีเมล์): hello@beamdigital.co.th\n- Customer (ผู้ติดต่อ): คุณเจนจิรา\n- Positi	\N	2026-07-09 23:07:47.92889
283	\N	staff:ocr	vision	13	27	24	303	9405	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor name: บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด (Beam Agency and Digital Co., Ltd.)\n\nTransaction date: วันที่ 4 สิงหาคม 2025 - This is "4 August 2025" - so 2025-08-04\n\nSubtotal: 9,000.00\nVAT (ภาษีมูลค่าเพิ่ม 7%): 630.00\nDiscount (ส่วนลด): 0.00\nTotal: 9,630.00\n\nCheck: 9000 + 630 = 9630 ✓\n\nPayment method: Looking at การชำระเงิน (payment method) section - there are radio buttons for:\n- เงินสด (cash)\n- บัตรเดบิต / บัตรเครดิต (debit/credit card)	\N	2026-07-10 11:38:50.246962
284	\N	staff:ocr	vision	13	27	26	194	11562	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	<think>The image shows a Thai bank passbook detail page. Let me extract the information:\n\n- Bank name: ธนาคารไทยพาณิชย์ จำกัด (มหาชน) / SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED → "SCB"\n- Name: บริษัท ไอแอพพ์เทคโนโลยี จำกัด\n- Branch: 0080 สาขาฟิวเจอร์พาร์ค รังสิต\n- Account No.: 012-345678-9 → digits only: 0123456789\n- Account type: บัญชีเงินฝากออมทรัพย์ / SAVINGS ACCOUNT\n- Number at bottom (likely MICR): 809436 (this appears to be the cheque/MICR number, not the account number)\n\nThe account nu	\N	2026-07-10 11:39:13.887607
285	\N	acct:coa-search	embed	1	1	5	0	1542	ok	\N	ค่าออกแบบลายเสื้อ		\N	2026-07-10 11:39:19.15769
286	\N	acct:coa-search	embed	1	1	4	0	151	ok	\N	ค่าพิมพ์เสื้อ		\N	2026-07-10 11:39:19.15769
287	\N	staff:ocr	vision	13	27	24	217	7410	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nVendor name: บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด (Beam Experience and Digital Co., Ltd.)\n\nTransaction date: 4 สิงหาคม 2025 (4 August 2025) = 2025-08-04\n\nItems:\n1. ค่าออกแบบลายเสื้อ (Shirt pattern design) - qty 1, unit 5,000, total 5,000.00\n2. ค่าพิมพ์เสื้อ (Shirt printing) - qty 20, unit 200, total 4,000.00\n\nSubtotal: 9,000.00\nVAT (7%): 630.00\nDiscount: 0.00\nTotal: 9,630 บาท\n\nCheck math: 9,000 + 630 = 9,630 ✓\n\nPayment method: เงินสด is check	\N	2026-07-10 11:40:08.072729
288	\N	staff:ocr	vision	13	27	26	208	10270	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	<think>The user wants me to extract information from this Thai bank passbook image. Let me analyze what I can see:\n\n1. Bank name: The image shows "ธนาคารไทยพาณิชย์ จำกัด (มหาชน)" / "SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED" - This is SCB (Siam Commercial Bank)\n\n2. Account holder name: "บริษัท ไอแอพพ์เทคโนโลยี จำกัด" (Company: iAppTech Company Limited)\n\n3. Branch: "0080 สาขาฟิวเจอร์พาร์ค รังสิต" (Branch 0080, Future Park Rangsit)\n\n4. Account Number: "012-345678-9" → digits only: "0123456789"\n\n	\N	2026-07-10 11:40:29.677711
289	\N	acct:coa-search	embed	1	1	5	0	176	ok	\N	ค่าออกแบบลายเสื้อ		\N	2026-07-10 11:40:32.085598
290	\N	acct:coa-search	embed	1	1	4	0	124	ok	\N	ค่าพิมพ์เสื้อ		\N	2026-07-10 11:40:32.085598
291	\N	staff:ocr	vision	13	27	24	2347	40248	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\nHeader information:\n- ชื่อลูกค้า (Customer name): บริษัท มันเจนช์ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เสียภาษี (Tax ID): 098-765-4310\n- อีเมล์ (Email): hello@beamdigital.co.th\n- ผู้ติดต่อ (Contact): คุณเจนจิรา\n- เบอร์โทรศัพท์ (Phone): 098-765-4310\n- เลขที่ (Number): 06987\n- วันที่ (Date): 4 สิงหาคม 2025 (4 August 2025)\n- กรกฎาคม (July) - ครบกำหนด (Due date): 4 กันยายน 2025 (4 S	\N	2026-07-10 12:29:13.772842
292	\N	staff:ocr	vision	13	27	26	112	8410	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	<think>The image shows an SCB (Siam Commercial Bank) passbook detail page.\n- Bank name: Siam Commercial Bank = SCB\n- Branch: 0080 สาขาฟิวเจอร์พาร์ค รังสิต\n- Account number: 012-345678-9 → 0123456789 (10 digits)\n- Account name: นริชัท ไอแอพพ์เทคโนโลยี จำกัด</think>\n\n{"bankName":"SCB","bankBranch":"0080 สาขาฟิวเจอร์พาร์ค รังสิต","accountNumber":"0123456789","accountName":"บริษัท ไอแอพพ์เทคโนโลยี จำกัด","isCorrupted":false,"correctionNotes":""}	\N	2026-07-10 12:29:35.280084
293	\N	staff:ocr	vision	13	27	24	1509	33081	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	<think>Let me analyze this Thai receipt carefully.\n\n**Vendor Information (ชื่อลูกค้า - which actually means "customer name" not vendor):**\nWait, the receipt says ชื่อลูกค้า (Customer Name): บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด\n\nHmm, but this is the customer, not the vendor. Let me re-read.\n\nActually, looking more carefully, the receipt has:\n- ชื่อลูกค้า (Customer Name): บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด\n- ที่อยู่ (Address): 559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\n- เลขผู้เส	\N	2026-07-10 12:29:53.915877
294	\N	staff:ocr	vision	1	612	24	78	46796	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท เนสซ์ เล่ห์ จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"cash","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าตอบแทนงานที่ได้","amount":5000},{"description":"ค่าพัฒนาสื่อ","amount":4000}]}	\N	2026-07-10 12:30:46.825238
295	\N	acct:coa-search	embed	1	1	5	0	1009	ok	\N	ค่าตอบแทนงานที่ได้		\N	2026-07-10 12:30:51.864669
296	\N	acct:coa-search	embed	1	1	3	0	143	ok	\N	ค่าพัฒนาสื่อ		\N	2026-07-10 12:30:51.864669
299	\N	ceo:cockpit	chat	13	27	44	1468	13144	ok	\N	Financial snapshot:\nCash position: -67,410 THB\nMTD expenses: 33,000 THB\nOutstanding liabilities: 0 THB\nNet cash flow (MTD): undefined THB\nTrial balance: balanced (Dr 0 / Cr 0)	<think>The user wants a 1-paragraph board-ready summary of company financial health for a CEO presenting to a board of directors. Let me analyze the financial snapshot:\n\n- Cash position: -67,410 THB (negative cash, which is concerning - this means the company is in an overdraft position)\n- MTD expenses: 33,000 THB\n- Outstanding liabilities: 0 THB\n- Net cash flow (MTD): undefined THB (this is a data quality issue worth noting)\n- Trial balance: balanced (Dr 0 / Cr 0) (balanced books)\n\nKey points t	944	2026-07-10 13:16:28.662178
306	\N	staff:ocr	vision	13	27	\N	\N	2125	error	Request failed with status code 429	Analyze the attached receipt (image/webp).	\N	\N	2026-07-12 16:42:56.750128
307	\N	staff:ocr	vision	1	612	24	80	36078	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท นันเช่นซ์ แอนด์ ดิจิทอล จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าออมทุนมาลาเอลี","amount":5000},{"description":"ค่าพิมพ์เลือ","amount":4000}]}	\N	2026-07-12 17:26:40.401943
308	\N	staff:ocr	vision	1	612	24	75	68860	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บุ๊ค เด็กน้อย จังหวัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าของใบสั่ง","amount":5000},{"description":"ค่าของใบสั่ง","amount":4000}]}	\N	2026-07-12 17:32:33.160407
309	\N	staff:ocr	vision	1	612	\N	\N	120014	error	timeout of 120000ms exceeded	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.	\N	\N	2026-07-12 17:35:03.901064
310	\N	staff:ocr	vision	1	612	24	74	49880	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.	{"vendorName":"บริษัท เดว์ลิส จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"cash","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าอื่นๆ","amount":5000},{"description":"คำพิมพ์เลือด","amount":4000}]}	\N	2026-07-13 11:02:41.837785
311	\N	staff:ocr	vision	1	612	125	79	54527	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nใบเสร็จรับเงิน\nReceipt\nชื่อลูกค้า\nบริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด\nที่อยู่\n559/21 ถนนพหลโยธิน แขวงจอมพล เขตจตุจักร กรุงเทพฯ 10900\nเลขผู้เสียภาษี\n098-765-4310\nอีเมล์\nhello@beamdigital.co.th\nผู้ติดต่อ\nคุ	{"vendorName":"บริษัท ไบร์ทมิลล์ ดิจิทอล จำกัด","transactionDate":"2025-08-04","subtotal":9000,"vatAmount":630,"totalAmount":9630,"paymentMethod":"","currency":"THB","isCorrupted":false,"correctionNotes":"","items":[{"description":"ค่าออกแบบลายเสื้อ","amount":5000},{"description":"ค่าพิมพ์เสื้อ","amount":4000}]}	\N	2026-07-13 11:26:00.009841
312	\N	staff:ocr	vision	1	612	125	89	29907	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nEast Repair Inc.\n1912 Harvest Lane\nNew York, NY 12210\nBILL TO\nJohn Smith\n2 Court Square\nNew York, NY 12210\nSHIP TO\nJohn Smith\n3787 Pineview Drive\nCambridge, MA 12210\nReceipt Total\nQTY\n1\n2\n3\nDESCRIPTION\nFront	{"vendorName":"East Repair Inc.","transactionDate":"2019-11-02","subtotal":145,"vatAmount":9.06,"totalAmount":154.06,"paymentMethod":"","currency":"USD","isCorrupted":false,"correctionNotes":"","items":[{"description":"Front and rear brake cables","amount":100},{"description":"New set of pedal arms","amount":30},{"description":"Labor 3hrs","amount":15}]}	\N	2026-07-13 12:16:04.28066
313	\N	staff:ocr	vision	1	612	125	116	26129	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nEast Repair Inc.\n1912 Harvest Lane\nNew York, NY 12210\nBILL TO\nJohn Smith\n2 Court Square\nNew York, NY 12210\nSHIP TO\nJohn Smith\n3787 Pineview Drive\nCambridge, MA 12210\nReceipt Total\nQTY\n1\n2\n3\nDESCRIPTION\nFront	{"vendorName":"East Repair Inc.","createdTo":"John Smith","transactionDate":"2019-11-02","subtotal":145,"vatAmount":9.06,"totalAmount":154.06,"paymentMethod":"","currency":"USD","isCorrupted":false,"correctionNotes":"","items":[{"description":"Front and rear brake cables","qty":1,"unitPrice":100.0,"amount":100.0},{"description":"New set of pedal arms","qty":2,"unitPrice":15.0,"amount":30.0},{"description":"Labor 3hrs","qty":3,"unitPrice":5.0,"amount":15.0}]}	\N	2026-07-13 12:33:35.473304
314	\N	staff:ocr	vision	1	612	125	140	53808	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nEast Repair Inc.\n1912 Harvest Lane\nNew York, NY 12210\nBILL TO\nJohn Smith\n2 Court Square\nNew York, NY 12210\nSHIP TO\nJohn Smith\n3787 Pineview Drive\nCambridge, MA 12210\nReceipt Total\nQTY\n1\n2\n3\nDESCRIPTION\nFront	{"vendorName":"East Repair Inc.","vendorAddress":"1912 Harvest Lane New York, NY 12210","createdTo":"John Smith","createdToAddress":"2 Court Square New York, NY 12210","transactionDate":"2019-11-02","subtotal":145,"vatAmount":9.06,"totalAmount":154.06,"paymentMethod":"","currency":"USD","isCorrupted":false,"correctionNotes":"","items":[{"description":"Front and rear brake cables","qty":1,"unitPrice":100,"amount":100},{"description":"New set of pedal arms","qty":2,"unitPrice":15,"amount":30},{"de	\N	2026-07-13 12:50:08.350259
315	\N	staff:ocr	vision	1	612	125	140	22596	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nEast Repair Inc.\n1912 Harvest Lane\nNew York, NY 12210\nBILL TO\nJohn Smith\n2 Court Square\nNew York, NY 12210\nSHIP TO\nJohn Smith\n3787 Pineview Drive\nCambridge, MA 12210\nReceipt Total\nQTY\n1\n2\n3\nDESCRIPTION\nFront	{"vendorName":"East Repair Inc.","vendorAddress":"1912 Harvest Lane New York, NY 12210","createdTo":"John Smith","createdToAddress":"2 Court Square New York, NY 12210","transactionDate":"2019-11-02","subtotal":145,"vatAmount":9.06,"totalAmount":154.06,"paymentMethod":"","currency":"USD","isCorrupted":false,"correctionNotes":"","items":[{"description":"Front and rear brake cables","qty":1,"unitPrice":100,"amount":100},{"description":"New set of pedal arms","qty":2,"unitPrice":15,"amount":30},{"de	\N	2026-07-13 13:16:30.641584
316	\N	staff:ocr	vision	1	612	125	49	89618	ok	\N	Return the structured JSON for this bank passbook image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nSUMMIT CITY BANK\nBanking Beyond Tomorrow\nTERMS AND CONDITIONS\nOF SAVINGS DEPOSIT\n1. PRESENTATION OF PASSBOOK\nThis passbook must be presented to the bank for every transaction.\n2. RESPONSIBILITY FOR PAS	{\n  "bankName": "Summit City Bank",\n  "bankBranch": "Sukhumvit Branch",\n  "accountNumber": "1234567890",\n  "accountName": "MR. JAMES ANDERSON",\n  "isCorrupted": false,\n  "correctionNotes": ""\n}	\N	2026-07-13 13:19:33.918151
317	\N	staff:ocr	vision	1	612	125	141	41993	ok	\N	Return the structured JSON for this receipt image. Output JSON only — no thinking, no preamble.\n\nUse the raw OCR text extracted below from the image to help you transcribe and verify all names, items, and values. Trust the OCR text spelling for Thai characters and tone marks:\n\n<raw_ocr_text>\nEast Repair Inc.\n1912 Harvest Lane\nNew York, NY 12210\nBILL TO\nJohn Smith\n2 Court Square\nNew York, NY 12210\nSHIP TO\nJohn Smith\n3787 Pineview Drive\nCambridge, MA 12210\nReceipt Total\nQTY\n1\n2\n3\nDESCRIPTION\nFront	{"vendorName":"East Repair Inc.","vendorAddress":"1912 Harvest Lane\\nNew York, NY 12210","createdTo":"John Smith","createdToAddress":"2 Court Square\\nNew York, NY 12210","transactionDate":"2019-02-11","subtotal":145,"vatAmount":9.06,"totalAmount":154.06,"paymentMethod":"","currency":"USD","isCorrupted":false,"correctionNotes":"","items":[{"description":"Front and rear brake cables","qty":1,"unitPrice":100,"amount":100},{"description":"New set of pedal arms","qty":2,"unitPrice":15,"amount":30},{"	\N	2026-07-13 23:42:32.532282
\.


--
-- Data for Name: ai_models; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_models (id, provider_id, name, capabilities, context_window, defaults_json, enabled, created_at, description) FROM stdin;
4	1	llama3.2:latest	{chat}	8192	{"temperature": 0.5}	t	2026-06-29 23:59:08.453437	\N
27	13	MiniMax-M3	{chat,vision}	128000	{"max_tokens": 2048, "temperature": 0.3}	t	2026-07-01 00:30:11.777571	MiniMax M3 — general reasoning + vision. Strong on Thai receipts, ~200ms typical latency.
612	1	qwen3-vl:4b	{vision}	262144	{}	t	2026-07-09 12:26:24.937079	Fast 4B vision. Good for clear printed receipts. Weaker on Thai handwriting — pick a larger model for accuracy.
613	1	qwen3.6:35b-a3b-q4_K_M	{vision}	262144	{}	t	2026-07-09 12:26:24.939495	Qwen 3.6 35B MoE (Q4). Strong general reasoning + vision, ~23GB RAM, slow.
614	1	qwen3.6:35b-mlx	{vision}	\N	{}	t	2026-07-09 12:26:24.939973	Qwen 3.6 35B MoE (MLX). Apple Silicon-tuned, vision capable, slow.
1	1	bge-m3:latest	{embed}	8192	{}	t	2026-06-29 23:59:08.450053	\N
2	1	qwen2.5:7b	{chat}	32768	{"temperature": 0.3}	t	2026-06-29 23:59:08.452687	\N
\.


--
-- Data for Name: ai_providers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_providers (id, name, type, base_url, api_key_enc, enabled, preset, notes, created_at, updated_at) FROM stdin;
13	MiniMax	minimax	https://api.MiniMax.io/v1	\\xc30d040703023b3a575b61ba0c776dd2ae01527ad3b185405aed89a55f5dd2e52057113fd3fc06f0b745214bcacac3b98e05c56fce58a0b96c0cf26b72772c1f8168de548702e9cf4eed6483fb3fc99c6789204ad44476ab029c6fccf35a13cb12ecf6b0efd60e711d615b686caccd367ab89fadc6ba29c5aa518c2ee8a82d03bebd1cac3afa4c57da634b8042711855678c7790a33dc02a9b492eea7b1f31b70ba773e194935d00c2e627b6162d0bab07280214a700f21b6acc0b90b0545f	t	minimax	MiniMax M3 — bootstrap key from env, editable via UI	2026-07-01 00:30:11.773303	2026-07-09 12:12:42.004748
1	local-ollama	ollama	http://localhost:11434	\N	t	\N	Local Ollama daemon	2026-06-29 23:59:08.444629	2026-06-29 23:59:08.444629
\.


--
-- Data for Name: ai_staff; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_staff (id, name, role_label, description, system_prompt, capabilities, default_provider_id, default_model_id, enabled, created_at, updated_at) FROM stdin;
1	Accountant Reviewer	Accountant Helper	ช่วยตรวจสอบใบเบิกและแนะนำรหัสผังบัชี	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-06-29 23:59:08.454249	2026-06-29 23:59:08.454249
2	Policy Drafter	Approval Policy Writer	ช่วยร่างนโยบายอนุมัติ	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-06-29 23:59:08.455378	2026-06-29 23:59:08.455378
3	Accountant Reviewer	Accountant Helper	ช่วยตรวจสอบใบเบิกและแนะนำรหัสผังบัชี	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-06-29 23:59:23.119315	2026-06-29 23:59:23.119315
4	Policy Drafter	Approval Policy Writer	ช่วยร่างนโยบายอนุมัติ	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-06-29 23:59:23.120114	2026-06-29 23:59:23.120114
5	Accountant Reviewer	Accountant Helper	ช่วยตรวจสอบใบเบิกและแนะนำรหัสผังบัชี	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-06-30 00:10:53.348198	2026-06-30 00:10:53.348198
6	Policy Drafter	Approval Policy Writer	ช่วยร่างนโยบายอนุมัติ	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-06-30 00:10:53.349698	2026-06-30 00:10:53.349698
7	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-01 00:22:55.988861	2026-07-01 00:22:55.988861
8	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-01 00:22:55.989948	2026-07-01 00:22:55.989948
9	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-01 00:23:11.924622	2026-07-01 00:23:11.924622
10	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-01 00:23:11.925814	2026-07-01 00:23:11.925814
11	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-01 00:30:11.77945	2026-07-01 00:30:11.77945
12	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-01 00:30:11.780371	2026-07-01 00:30:11.780371
13	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-01 00:31:27.388819	2026-07-01 00:31:27.388819
14	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-01 00:31:27.389928	2026-07-01 00:31:27.389928
15	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-02 14:33:24.425055	2026-07-02 14:33:24.425055
16	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-02 14:33:24.426496	2026-07-02 14:33:24.426496
17	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-09 00:57:33.732082	2026-07-09 00:57:33.732082
18	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-09 00:57:33.73302	2026-07-09 00:57:33.73302
19	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-09 00:57:36.649458	2026-07-09 00:57:36.649458
20	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-09 00:57:36.650492	2026-07-09 00:57:36.650492
21	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-09 01:06:06.120881	2026-07-09 01:06:06.120881
22	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-09 01:06:06.121976	2026-07-09 01:06:06.121976
23	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-09 11:37:03.920491	2026-07-09 11:37:03.920491
24	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-09 11:37:03.922724	2026-07-09 11:37:03.922724
25	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-09 11:42:44.907176	2026-07-09 11:42:44.907176
26	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-09 11:42:44.909	2026-07-09 11:42:44.909
27	Accountant Reviewer	Accountant Helper	Helps review expense claims and suggest chart-of-account codes	You are an expert accountant who reviews expense claims and suggests correct chart-of-account codes. Respond in Thai when the input is Thai.	{chat}	1	2	t	2026-07-09 11:46:09.253806	2026-07-09 11:46:09.253806
28	Policy Drafter	Approval Policy Writer	Helps draft approval policies	You help draft approval policies for a finance system. Output JSON only with conditions_json and action_json structure.	{chat}	1	2	t	2026-07-09 11:46:09.255285	2026-07-09 11:46:09.255285
\.


--
-- Data for Name: approval_override_audit; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.approval_override_audit (id, target_type, target_id, actor_id, kind, attempted_stage, required_role, actor_role, reason, created_at) FROM stdin;
\.


--
-- Data for Name: approval_transitions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.approval_transitions (id, target_type, target_id, actor_id, previous_status, new_status, comments, stage, chain_index, created_at) FROM stdin;
100	expense	135	964	\N	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-08 16:22:32.651905+07
101	expense	136	968	\N	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-08 19:16:52.303354+07
102	expense	137	968	\N	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-08 19:25:47.780055+07
103	expense	145	968	draft	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-09 12:42:11.902188+07
104	expense	147	962	draft	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-09 17:49:14.654858+07
105	expense	148	964	draft	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-09 19:29:30.595067+07
106	expense	149	951	draft	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-10 11:39:19.15769+07
107	expense	150	964	draft	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-10 11:40:32.085598+07
108	expense	151	959	draft	dept_verification	Submitted → initial stage	dept_verification	0	2026-07-10 12:30:51.864669+07
\.


--
-- Data for Name: chart_of_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chart_of_accounts (code, name, name_th, account_type, embedding) FROM stdin;
110100	Cash on Hand	Cash on Hand	asset	[0.0022836488,0.051115498,-0.05044212,-0.0060952986,-0.005050416,-0.020224554,0.049862806,0.05143055,0.002758322,0.0064171264,0.01709811,0.011942939,-0.003484556,-0.018284047,0.012660064,0.014799565,0.013602163,-0.0043454417,-0.0043046167,-0.03001775,0.01845588,0.006729877,0.015297168,0.029858481,-0.021898422,-0.011036623,-0.00023479707,0.012400584,0.00023635341,0.0056607164,0.004512157,-0.025314666,0.033578265,-0.015101778,-0.05548426,-0.00079030066,-0.011488158,-0.025929473,-0.043471232,0.036711745,-0.04103145,0.019839752,0.04145118,0.041907996,0.009898229,-0.03207023,-0.043132633,-0.018527837,-0.008168031,-0.0021299801,-0.018562937,0.013164354,0.04814916,-0.003780803,-0.015472978,0.035162102,-0.038913913,-0.02935215,-0.04626856,-0.010693023,0.002756861,-0.0028055648,-0.015492068,0.006465749,0.012131695,0.06264233,0.0052687046,0.029411577,-0.023389958,-0.049203023,0.015912583,0.015637416,-0.032161176,-0.030547418,-0.03840565,0.050963294,0.034797918,0.00045197862,0.0079773255,0.008126662,0.034704268,-0.016206333,0.005410015,0.0012599162,-0.012511771,0.04309083,0.03621559,-0.02934665,-0.016780296,0.0035353205,0.0037474236,-0.011202782,0.02552285,-0.0729915,0.00989501,-0.011864224,-0.050392464,-0.011635002,0.023082385,0.016329926,0.07195618,0.052216154,0.0052381726,-0.017390253,-0.018893968,0.014079003,0.023576831,0.035088588,0.009799065,-0.008776764,0.010277023,0.06240572,0.02562879,-0.006506834,-0.033276055,0.03126286,-0.017683165,-0.009180285,0.0020599442,-0.0008573576,0.0026169776,0.017628007,0.024353454,-0.0014102868,0.00082887395,-0.0155779505,-0.0204125,-0.0072219144,-0.009946811,0.018717319,-0.011024015,0.06716034,-0.030084131,0.05705121,-0.048897948,-0.011920436,0.017393125,-0.011988355,-0.0042918646,0.01819802,0.029145727,0.056724023,-0.028622018,-0.031719867,0.032248195,-0.018486736,0.0072530047,0.013152326,-0.013568813,-0.005434464,0.032816723,0.019696886,-0.012360259,-0.005738617,-0.035557978,-0.028804976,-0.012119029,0.001355063,-0.01073887,-0.0040150858,0.02695645,-0.05318405,0.02548682,-0.022720398,0.018255008,0.018700954,0.0040289424,0.009970485,-0.002227597,-0.0041011623,0.009345269,-0.059552215,-0.029634723,0.0026861283,0.03697138,0.03707477,0.07239603,-0.01172259,0.00059920416,-0.05596169,-0.019388383,0.009057993,-0.023328511,-0.062369376,-0.023316251,0.03738826,0.016432472,0.004919206,-0.011890237,0.0038000885,-0.0052080033,-0.018500676,0.046170842,-0.028629277,0.025857873,-0.055984724,0.06509317,-0.03843777,-0.01346241,-0.013418901,0.0029195757,0.0043538543,0.009799893,-0.03190041,-0.023280194,0.02004105,-0.008159554,0.009196175,0.029464073,-0.03410797,0.0035472547,-0.011493427,0.022170486,-0.056894004,-0.0010716749,0.025810802,0.035899978,-0.026532222,-0.0061265756,-0.023650184,0.0067170346,0.054246813,0.012628082,0.05982352,0.033878107,0.011190317,0.0029215636,0.068693876,-0.0003115587,-0.0396855,-0.0014103209,0.0004828242,0.015858352,0.011977962,0.028040517,0.011433979,-0.021896232,0.01432846,-0.014989391,0.05185605,-0.016576102,-0.016484093,0.016139014,0.048429813,-0.006773229,0.02444965,-0.025772078,-0.009207778,-0.048355248,-0.025202414,0.022192406,-0.02593154,-0.033326454,-0.015662894,-0.017771147,-0.012914362,-0.008453688,-0.016361482,0.0127725955,-0.016255789,0.006344732,-0.014495052,0.038671803,0.010240148,0.020716809,-0.008299646,-0.051563717,-0.03467481,0.035985146,0.022132127,0.006301205,-0.046138898,-0.017425667,-0.0022900752,0.0039065243,0.035422932,0.047364987,-0.004480145,0.048874706,0.0045136358,0.003969651,-0.0050858296,0.01589674,0.008367029,0.06401606,-0.0069225715,-0.031308305,-0.007429925,0.011464414,-0.032592334,0.0050949915,-0.036899354,0.051272087,-0.00839787,-0.038505897,-0.06496559,-0.0071496167,-0.14116222,0.06271265,0.013607969,-0.023815623,0.009031084,0.02407211,-0.022650471,-0.043742124,-0.075422846,0.03379316,0.051423118,-0.045210823,0.033772297,0.041647095,0.016970491,-0.014694787,-0.002033002,-0.012111985,0.043025285,-0.01768447,-0.003927963,-0.09619749,0.070762165,-0.018884182,-0.02188713,0.027371658,0.015191526,-0.029891552,-0.030502021,-0.01654861,-0.006827763,0.010736747,-0.0013604301,0.016699053,-0.001407982,0.05915187,0.026384939,-0.023786314,0.017021464,-0.042433094,0.048293106,0.017118488,-0.0014925537,0.019319985,-0.029391844,-0.03374207,-0.012616624,0.023293726,-0.0050022337,0.0024537507,0.013416775,0.006516096,-0.009227701,-0.017478628,-0.013424312,0.03319393,0.045421064,-0.005879209,-0.008710021,0.01539634,-0.012388492,-0.060090464,0.0018966089,-0.022778118,-0.025269995,0.018447,0.048738718,-0.0074324505,0.028703045,-0.04769524,0.03318197,-0.06158005,0.022512607,-0.014816864,0.020280907,0.05512469,-0.0811617,-0.08045638,-0.003977047,-0.113842405,-0.00486604,0.0104676,0.0017334785,-0.029712852,-0.018152814,0.02076477,-0.007030456,-0.024356116,0.08328032,0.21721883,0.04797138,0.03156027,0.02797324,0.06492779,0.044474535,-0.018485613,-0.019820718,-0.008331505,-0.044267792,0.036885057,-0.00056184444,-0.030154338,0.047233205,-0.0027775855,0.008101608,-0.02752474,0.029027877,0.080026425,-0.010086294,0.0012978038,-0.001973499,-0.0062880316,-0.0033742674,-0.07139819,-0.021052964,-0.03721487,0.05876656,-0.015952872,0.00037900632,-0.0021528741,-0.036271438,0.021528924,-0.019210562,0.024920925,-0.0052447366,-0.030036246,-0.019856565,-0.02749965,0.049036812,0.017756494,-0.07319069,0.04286249,0.005746978,-0.055666108,0.008197155,0.004470945,0.026426544,-0.043317676,-0.013033,-0.052064978,-0.019750178,-0.013162884,-0.0032173002,-0.01446625,-0.0151856635,-0.030010976,-0.019938841,-0.0070240344,0.060550958,-0.02428558,0.0009960608,-0.0030015656,0.066816255,-0.012230325,-0.028437912,-0.016557714,0.033149235,-0.02046771,0.009358961,0.029430537,0.009097211,-0.006124508,0.027681882,0.017737124,-0.01122928,0.004293295,0.011605112,0.049512386,0.01002615,-0.028480425,-0.029892458,0.01653531,0.034047324,0.0025862118,-0.03205021,-0.03112235,0.04633823,0.008721733,-0.04847721,0.001340384,0.037527412,-0.0055881976,0.028013647,0.023800643,-0.02223229,0.028037956,0.017613534,-0.049122952,0.034646574,0.043238826,-0.025082594,0.017072199,-0.05712451,-0.021032473,0.008412356,-0.010679546,-0.004304946,-0.008576792,-0.034339204,-0.00376838,-0.022344714,-0.005687281,-0.028420212,0.0054699564,0.044943977,0.03242782,0.035135586,0.05064477,0.07494692,0.0003282473,0.01676784,-0.03866601,0.028919013,-0.006501118,-0.028431894,-0.007588242,0.024372352,-0.02022824,0.03751014,0.02425295,-0.022649558,-0.012569696,-0.028236445,0.07596391,-0.016830526,0.07238546,-0.00018715198,0.031130524,0.060107917,0.020115305,0.011182332,-0.050265364,-0.032423485,0.038727183,0.036792673,-0.0006781871,0.0117686605,0.010837766,0.04570053,0.060691666,0.023929842,0.029489523,-0.058177914,0.0071562207,-0.080928065,-0.02858449,-0.019542933,0.0060873954,-0.035869207,0.0035433925,0.03145816,-0.035816297,0.08305946,0.05271187,0.030233512,-0.036347296,0.039309748,-0.014252359,-0.018566936,-0.0286757,-0.0454807,0.0011685533,0.0044490476,-0.04266449,-0.045327105,-0.005068701,0.028129114,0.019418566,-0.0009971514,0.0126819555,-0.007821035,0.0038321235,-0.053272195,-0.010498012,-0.02084273,0.02518284,-0.0035023622,-0.014328729,-0.04811144,-0.040419657,0.075930536,0.01622752,-0.003187187,-0.01608156,-0.017989008,0.03708344,-0.0053241476,0.019034797,-0.08362859,-0.026721928,-0.026397532,-0.03724711,0.03149934,-0.01915781,-0.01928907,0.028149514,0.020754496,-0.003565879,0.002139267,0.011854098,0.0005503956,0.03906087,-0.014469836,-0.015994603,-0.007956802,0.029790297,-0.015143237,0.027796345,-0.052690215,-0.036406275,-0.022910459,0.03148479,0.0041910256,-0.034296133,-0.03931586,-0.006400038,0.008957472,-0.027200487,-0.026911097,-0.006332881,-0.032781318,0.0355929,-0.039119836,0.041259006,0.00033063436,0.027803343,0.018634418,0.015126815,-0.021627095,0.0400078,0.0039386027,-0.04242521,0.022931825,0.017295746,0.020977423,-0.019433625,-0.011612552,0.045297667,0.0071152537,-0.00085972797,-0.015285521,0.004044806,-0.038104128,0.0061749797,-0.018612707,0.018942565,-0.018138302,-0.014389797,-0.01241383,0.0067283944,0.019449363,-0.0036842674,0.0060392655,0.01321757,-0.03506576,0.022835294,-0.0209679,-0.016942179,-0.04594532,0.014238988,-0.014760005,0.013560857,-0.031381957,0.00881233,-0.033417597,-0.01440537,0.0045530344,-0.0070854924,0.014379843,-0.04774039,-0.024345314,0.030599125,-0.013606951,-0.0116832405,0.04955545,-0.011710109,0.014291562,-0.008602128,-0.012954362,0.014669594,-0.0048388653,-0.025662359,0.019931724,-0.008677884,-0.02012298,-0.008670232,0.041132785,-0.030181775,-0.030270413,-0.016153986,0.037434444,-0.02913434,-0.04999428,0.011908331,0.0019109504,0.025503704,-0.04319684,0.03173127,-0.0043187374,0.010241907,-0.015022874,-0.03609096,0.012943632,0.026991883,0.008490584,0.019077862,0.006480272,0.022996671,0.0430073,-0.003176562,-0.02102379,0.031347536,-0.027254296,-0.004594348,0.035238694,-0.0050665974,-0.022454306,-0.021633312,0.008670402,0.012843393,0.0599518,-0.03429563,-0.005232541,0.029418053,-0.022793775,0.04784883,0.028243734,0.03575955,-0.031835396,-0.052426096,0.028688867,0.038007084,-0.0033516625,-0.010417966,-0.0074931104,-0.031996217,-0.011969613,-0.0022540884,0.011078554,0.010881497,-0.046123195,-0.007670073,-0.052027423,-0.0044748615,-0.05740287,-0.0038653377,-0.020329244,0.018566074,-0.0031588264,-0.016484406,0.033317626,0.0029302486,-0.023182658,-0.021381807,0.04731842,-0.0061397883,0.016637838,0.027924927,-0.014290867,-0.046285804,-0.003620545,-0.015164467,-0.03497254,-0.041032657,0.019018084,0.018877108,-0.018781114,0.04280569,-0.032872614,-0.015027752,0.0056774938,-0.033166092,-0.006203275,-0.0025728124,-0.0067904955,-0.015366086,0.0067609423,0.038854297,-0.017499182,-0.0041975784,-0.022583377,-0.021719662,0.016711019,-0.13543397,0.031608645,-0.0010922181,-0.047921337,-0.042089216,0.0050917114,-0.0678723,0.04113343,-0.012058832,0.012077327,-0.014478871,0.031690378,0.03555797,0.0018891069,-0.038231023,0.08573308,-0.025067525,-0.00027364894,0.00305371,0.027799604,0.02732995,-0.025796216,0.028267797,-0.024415137,0.03647537,0.0056301793,0.021860093,0.031720683,-0.025137901,-0.06139323,0.0033398713,-0.067449175,0.029117033,0.047099847,0.029030057,-0.01818026,0.006339392,-0.008574038,0.00668953,0.012242642,-0.06267565,0.01593232,-0.020815786,0.021585606,0.020694543,0.052971564,-0.01651135,0.004012852,-0.042202156,-0.03173377,-0.01928994,-0.009710104,1.3516673e-05,0.04871677,0.008337545,0.014222087,-0.0625641,0.009665924,0.0346781,0.035204567,-0.0011437337,0.014066191,-0.03406126,-0.03533207,0.0031529914,0.0073868786,-0.058536038,-0.00097258657,-0.011017382,-0.03836394,-0.023546932,0.005604059,0.02600467,-0.038049143,-0.011339935,-0.007936071,0.0074012037,0.00093507976,-0.070471294,-0.029515928,-0.008547861,-0.009903017,-0.0111379605,-0.025864627,-0.009637843,0.010576564,-0.008064151,0.006054453,-0.010082222,-0.01726993,-0.052576628,-0.0014159584,0.018608982,-0.00292641,-0.020485358,0.030223189,-0.025471624,0.018117389,-0.020552242,-0.0050800573,0.033931985,-0.008504334,0.0054989182,-0.024162281,-0.04962144,-0.008681779,-0.007232127,-0.044410754,-0.017820051,-0.0067834733,-0.0107063195,0.027821114,-0.05135712,0.011253581,-0.03244258,-0.050318647,-0.026302127,0.0375692,0.03645968,-0.026861964,0.05389101,0.016130783,0.07410353,-0.03201689,0.02782282,0.019025669,0.012616917,-0.01282482,0.027793959,-0.012874364,0.018771956,-0.07157229,0.059320524,0.04435986,0.030563723,0.06714986,-0.023716232,0.011941038,-0.048470467,-0.017507844,-0.009981087,-0.020009222,-0.01804032,-0.055343967,-0.037552454,-0.060015105,0.021237012,0.017723905,0.036951028,-0.029054563,0.0027996767,-0.007307955,0.02383221,0.017495612,0.009304314,0.01458483,-0.011799248,-0.023426125,0.013051666,-0.0013358791,-0.019569404,-0.009497628,0.0074266554,-0.03096072,0.024113888,0.025657378,-0.028771276,0.0035744198,-0.0069640083,-0.016989006,0.038057037,0.01990944,-0.013929591,0.012993542,0.04752365,-0.010721253,0.013682801,-0.012294749,0.030595217,-0.008321211,0.021912837,-0.0070916535,0.024807736,0.00087459374,0.0050590835,-0.008774449,-0.044279937,0.04463874,-0.030275948,-0.03659206,-0.0017630308,-0.017949658,-0.0086872885,0.012350489,0.021681443,0.06247514,-0.021105131,0.04780814,0.013790971,0.027292138,0.04777489,-0.004118239,-0.0062279487,-0.019782366,-0.010692474,0.015159031,0.018211192,0.043456208,-0.029236652,-0.03488667,-0.041123267,0.0020753941,0.0047828136,0.028905513,-0.008024172,-0.018844504,0.03984882,0.04853172,-0.010868916,-0.0005403857,-0.044545904,0.063135505,-0.04005415,0.0017901886,-0.00804435,-0.010541134,-0.05690956,-0.0013486722,0.0029608114,0.004354835,-0.036790293,-0.022901827,-0.04962324,0.06093734,-0.023996769,-0.014549287,-0.037073076,0.0021371034,-0.023417564,-0.019233085,0.04586128,0.019066563,-0.04019776,-0.055499177]
110200	Cash at Bank - Savings	Savings Deposits	asset	[0.030902756,0.0052835313,-0.0631699,0.0035235751,-0.03167106,-0.043072324,0.029286394,0.018880019,-0.0020511083,-0.006039256,0.016898248,-0.014067757,0.004988048,0.050847445,0.020894384,0.0065058647,-0.005137183,0.009640422,-0.032345537,0.0005974361,-0.008304713,-0.02426523,-0.00769757,-0.042816993,-0.05253204,-0.007896164,0.0030881194,-0.024727765,-0.005265666,0.045560874,-0.01330849,-0.04910834,0.028138291,-0.04656358,-0.03244625,-0.022873485,-0.03175175,0.014081735,-0.046855476,0.0199328,0.022760041,0.0040258686,0.05105149,0.06271888,0.029089145,-0.013605196,-0.039588574,-0.02790803,-0.018179458,-0.014419922,-0.010428343,0.008700756,0.030307908,-0.0041867862,0.03790027,0.033178397,-0.053647406,0.018904075,-0.030278375,-0.029907912,0.0070869755,-0.035945065,-0.050764862,0.0081915185,0.015733887,0.067768276,-0.009533752,0.013968917,-0.036191277,-0.023638321,0.0076097613,0.008418299,-0.005649793,-0.015905777,-0.036219466,0.006714399,0.07788621,0.0034070106,-0.007847475,-0.023059469,0.026140854,-0.011473184,0.03378624,-0.016245691,-0.020452302,0.040111344,0.018235322,-0.048767142,-0.021071877,0.03308384,0.034965515,-0.010755804,0.005352784,-0.029237535,-0.024215974,-0.015359496,-0.036456484,-0.0076233577,0.04122811,0.016778124,0.060495857,0.034752026,-0.026050488,0.025784103,0.007823233,-0.025258904,-0.0046951207,0.04171333,-0.025517037,-0.019859433,-0.017830538,0.056707345,0.012319898,0.030251581,-0.0057191206,-0.006988303,-0.0018044702,-0.03742873,0.0024288544,0.047255408,0.005475095,-0.00507872,0.021716725,-0.008236222,0.0033169172,-0.0048773084,-0.024468515,0.008722076,-0.020196756,0.018363839,0.014333522,0.06270856,-0.0668471,0.004434853,-0.04449863,-0.015494313,-0.0030797967,-0.0006073988,0.042565323,-0.064433806,-0.02560653,0.035234008,-0.047588225,-0.024759697,0.020435197,0.02056316,0.010371573,0.02038095,-0.028650627,-0.024334077,0.019492803,0.009819788,-0.0017520459,-0.035067037,-0.004007199,-0.037974842,-0.00795452,0.0021014726,0.008726221,0.0052638752,0.030132566,-0.07600372,0.010431003,0.013566693,0.0011520549,0.008369579,0.018214423,0.010218078,0.008347766,0.029553248,0.036034945,-0.046300825,-0.007885404,0.019251646,0.024431648,0.024689872,0.07703864,0.020240534,0.04175479,-0.071196504,-0.019031988,0.04365309,-0.015497865,-0.011592913,0.0048582987,0.04485996,-0.0019621663,-0.029398648,0.014570142,0.012646629,0.0066479263,-0.010973142,-0.0070881248,-0.05561806,0.053981185,-0.01693063,-0.022444151,-0.022772606,-0.0003521229,0.012942977,0.0020378947,0.03727751,-0.0075292946,-0.0024725078,-0.0023129564,-0.007909119,-0.0038502607,-0.021342097,0.050544843,-0.071942925,0.010802017,-0.016986687,0.024933906,-0.059576385,-0.012880767,0.0049753627,0.017345417,-0.009371826,-0.01665376,0.030823275,-0.02717738,0.04963259,0.014033425,0.0026583355,0.03862794,-0.015813978,0.012013574,0.039951157,0.039247297,-0.09503424,-0.041413154,-0.002248832,-0.0069451304,-0.006751384,0.047160666,0.012703427,-0.016056912,0.029977093,-0.034209058,0.0021881794,-0.016484838,0.0177809,-0.007476845,-0.00015996654,0.008335008,0.04134678,-0.021848299,0.02124366,-0.041449904,-0.025690792,-0.0037251038,-0.016473074,-0.046802443,-0.021334333,-0.024845842,0.0046966933,0.023102375,0.004256179,0.02482502,0.014990099,0.0020668001,0.013321812,0.005477127,0.027308026,-0.002454595,-0.03280305,-0.02958291,-0.033563916,-0.0020444011,0.011136198,0.014998998,-0.00812364,0.001727416,0.0041499324,0.02273867,0.040323604,0.04364787,0.035492394,0.04697268,-0.012380468,-0.0022284174,0.017168475,0.0028110715,-0.013707499,0.020539144,-0.023794068,-0.04336917,0.0037968538,-0.018408597,-0.04284537,-0.05995369,-0.009781237,0.06561348,-0.012612691,-0.04691496,-0.014826757,-0.007859192,-0.14954495,0.07640439,-0.0034222358,0.012038507,0.0053227986,0.031400494,-0.025791194,0.0078059407,-0.02318778,-0.0008229427,0.04850815,-0.06811209,0.04565937,0.03181613,0.0022813883,-0.027961925,0.012638579,0.015548262,0.034348667,-0.015726412,-0.012166595,-0.08296456,0.0116679445,0.00432286,-0.03220999,0.04143243,0.039069332,-0.0016918442,-0.04236212,0.002907987,-0.013503704,0.022148816,-0.00020275409,-0.004429855,-0.026065892,0.06782026,0.012718788,0.03561583,0.013550861,-0.029221032,0.02989905,0.019041782,-0.006125868,0.018731492,-0.020587388,-0.006721223,-0.007346726,-0.00020991881,0.0019785592,0.02676361,-0.016693175,-0.0025841803,0.009364846,-0.014623699,-0.037286077,0.0021638032,0.026862673,0.074464604,0.007992778,0.031702697,-0.01001875,-0.05126826,0.0017770291,-0.012773468,-0.033084653,0.015109122,0.019863414,-0.016086712,0.055537842,-0.04886335,0.051217917,-0.03942891,0.009544711,0.0014396249,-0.031291608,0.056707565,0.033003893,-0.04746103,-0.032502655,-0.08507876,0.019317077,0.006019363,0.005952003,-0.06580134,-0.034235694,0.00886338,0.0021678503,-0.011310739,0.004179608,0.22806717,0.030712873,0.0138901,0.033291854,0.025047418,0.0031927626,0.007407344,-0.014931772,0.013460542,-0.04166172,-0.036095638,0.035110004,-0.0127097275,0.011244801,0.015272755,0.05582163,-0.038444635,0.0037184018,0.09724526,0.0013725219,0.012637354,0.0037200286,-0.033427376,0.022545427,-0.056733705,-0.053790815,-0.021705732,0.061747618,-0.004231725,0.04403202,-0.024604524,-0.018038968,0.036293358,-0.056518037,0.0420437,-0.039583873,0.0054511074,-0.013865781,0.009483597,0.04848063,0.0074049598,-0.037520114,0.038440533,0.0066762706,-0.026190128,-0.0051820236,0.004025655,0.026214242,-0.011204992,-0.031186393,0.0010791109,-0.018078513,-0.001205872,0.0026834798,-0.0097450195,-0.036678717,-0.0021897103,-0.055275436,-0.034401722,0.027742513,-0.00013084237,0.008324159,0.03829643,0.06335951,-0.031746987,-0.021584658,-0.039801966,0.031090485,0.0117424065,0.078672,0.03659149,0.02834961,0.016433401,0.034981873,-0.00666359,0.015923513,0.005522165,-0.025708793,0.060978014,0.011064282,-0.046801317,-0.009422452,-0.024593746,-0.0055951835,0.02366316,-0.0072234734,-0.02831156,0.04460186,0.016644785,-0.05726311,9.359204e-05,0.01587113,0.03836369,-0.0094925,0.025627716,-0.016831458,0.04337625,0.0013395218,-0.027512189,0.06405098,0.045290235,-0.007840784,0.03979913,-0.046496265,0.0017972522,0.031558175,-0.0361573,-0.03813846,-0.0037058424,-0.027955046,-0.05528946,0.025733195,0.0009541013,-0.004646964,0.0055105924,0.029649751,0.023632808,0.01678834,0.044959918,0.015825052,-0.0039211055,-0.015985908,-0.005812164,0.01583762,0.019840512,-0.0072097564,-0.027430953,0.015857626,0.0018002709,0.044839274,-7.764017e-05,-0.01706473,-0.0048322245,0.015134058,0.05769464,-0.013386525,0.04696221,0.04935489,0.019992232,0.0115885995,0.038217865,0.018846737,-0.030026704,-0.04129066,0.02949646,-0.012030501,-0.008898979,0.009597412,-0.011260308,0.013472368,0.045770325,0.0072956444,0.020220798,-0.0389884,0.026964247,-0.05683659,-0.056213,0.015663609,0.05084078,-0.04580377,0.028591907,-0.02938995,-0.011287125,0.05027168,0.040507726,0.04785083,-0.041100394,0.09577578,-0.03283152,-0.010598788,0.030177772,-0.041436173,-0.022798307,-0.006388254,-0.054989785,-0.033214048,0.030360572,0.033064093,-0.047461014,0.012581828,0.011530056,-0.009221406,0.030408544,-0.043507,-0.00276497,0.042262327,0.023235789,-0.0072642756,0.0075776298,-0.028124506,0.0021004921,0.05188239,-0.018731501,-0.019316504,-0.04814806,-0.020105239,0.023206621,0.030316921,-0.008236632,-0.048989728,-0.03989116,0.0030259248,-0.004111788,-0.023997081,-0.023543261,-0.031886034,0.043383315,0.009981777,0.010936549,-0.026298644,-0.008368157,0.00066982576,0.0050479355,-0.014177375,0.035580523,-0.014888421,-0.03475657,-0.01922336,0.01053765,-0.08073272,-0.025645902,-0.017848335,-0.0011884095,0.007426327,-0.030189859,-0.040915012,-0.009013835,0.009657794,-0.01053619,-0.004934798,0.008557124,-0.039277714,-0.016033137,-0.043753836,0.041902687,-0.0056724986,0.01490633,0.031223264,0.037188835,-0.033965044,0.07032254,0.010315554,-0.014356026,0.046659473,0.0054006367,0.00084232155,-0.034430128,0.06391354,0.042297214,0.0033877422,0.0037726522,0.004074799,0.009000148,-0.023416987,0.022240905,0.0071487674,0.045400433,-0.03234037,-0.018140396,-0.026828757,-0.010524067,0.046966933,-0.049776923,-0.003206005,-0.010897086,-0.04297363,0.0076986225,-0.051778782,-0.011731778,-0.011101877,-0.044821862,-0.0016526422,0.0057772677,-0.030019723,0.028192855,-0.044961017,-0.028107561,-0.028270354,0.029171556,0.035554755,-0.0060410155,-0.030851224,0.035903398,0.030718448,-0.031199923,0.011641106,-0.005156037,0.012511659,-0.03387495,-0.0014916356,0.0038197096,0.0007993792,-0.024935048,0.0013033742,-0.024208155,-0.009298889,0.022193918,0.03866574,-0.008082858,0.018507069,-0.016819373,0.0119311875,-0.04963537,0.002666488,-0.013092835,-0.034664907,0.004508789,-0.06129475,0.015699616,0.0073733157,0.034944925,0.026177019,0.02137173,-0.012836848,0.017073998,0.009408519,0.023148114,0.009137783,0.019100554,0.016147943,0.010121687,-0.035349675,-0.00041300742,-0.025037616,-0.030577103,-0.014719258,0.014596378,-0.024111755,-0.018011676,-0.0069425213,0.024320656,0.022742087,-0.045266066,0.013073906,0.029139172,0.0005965125,0.020925354,0.0162686,0.029808093,-0.00783774,-0.030420441,0.029308446,0.04111166,-0.017733326,-0.0016565786,-0.02296338,-0.0033289297,-0.01490024,-0.027546285,-0.0033069395,0.0009895242,0.022119949,-0.029969,-0.042078104,0.016867606,-0.0595323,-0.043916415,-0.0013283056,-0.005517645,-0.025113055,-0.010306364,0.029365847,-0.022116823,-0.02841037,0.00078691926,0.015669703,-0.026859714,-0.008264825,-0.029180642,-0.015024369,-0.028293265,-0.016772313,-0.0051808134,-0.0065711574,-0.027074983,0.041082937,-0.0029939734,-0.031022526,0.0049975645,-0.013300143,-0.00046713863,0.004217757,-0.012880963,-0.01477583,0.028076777,0.0014541158,-0.013423399,0.025725735,0.035983965,0.024512816,-0.022576278,-0.037971895,0.012517087,0.016630983,-0.123913,0.019291766,-0.022593524,-0.0045622955,-0.021995932,-0.010802723,-0.06826239,-0.010337939,-0.0555223,0.01432955,-0.019408202,0.03390855,-0.008617584,-0.011793529,-0.06250033,0.029023668,0.0086099645,-0.03524352,-0.035524946,0.051850326,0.039085627,-0.01610171,0.05440591,0.002768724,0.009252505,0.040120944,0.037946813,-0.0148869045,-0.028391441,-0.063733235,0.020700494,-0.026011417,0.03622585,0.007700533,0.03770294,-0.03517359,0.01841522,-0.047511782,0.0035936034,-0.016747063,-0.043417808,0.012120518,-0.019135352,0.0007678559,0.04054943,0.008255617,-0.021233553,-0.011789629,-0.016250437,-0.014176986,0.009470204,-0.04936379,0.011032347,0.004334873,0.006127883,-0.0075665666,-0.050754327,-0.04552768,0.09297094,0.037245948,0.016257754,0.06784277,-0.042702165,-0.028090673,-0.009587217,0.028094588,-0.03998967,0.0118847545,0.0044996166,-0.038822133,-0.012815461,0.028029677,0.006094594,0.012350624,0.023960805,-0.012740719,0.026982514,-0.036650095,-0.021307094,-0.029471077,-0.0026715228,0.00097601477,0.009280123,-0.052799832,0.014761332,-0.0029938894,-0.04539813,0.014619746,-0.0065829726,-0.034896933,-0.05922569,-0.035754118,0.026529474,-0.0035658777,0.0066477545,0.071623445,0.007052982,0.005700868,-0.03553838,-0.01081034,0.061822537,0.0017673719,0.0021185644,-0.024625491,-0.05128057,-0.051080823,0.0048571606,-0.03020273,-0.0058392608,0.003708273,-0.0124916425,-0.013340405,-0.012733891,0.006394687,-0.052231066,-0.029609341,-0.026332263,0.005665046,-0.005519379,-0.025385004,0.018492416,0.0028484866,0.011125872,-0.010871192,0.06603018,-0.007151554,-0.0020928106,-0.019324055,0.016008664,-0.025997438,0.057570037,-0.0851179,-0.011804662,0.003986454,0.031006878,0.033238914,-0.09418174,0.046380896,-0.031940214,-0.012605248,0.029393328,0.032529484,0.025012834,-0.005762101,0.0006376631,-0.057197303,0.0018725882,0.0015690189,0.043329924,-0.024206217,-0.0049393843,-0.018386105,0.027770005,0.028892258,0.013811732,0.0074063772,0.014726433,-0.01074555,0.0034503923,0.010522478,0.021420227,-0.015902769,-0.0019186874,-0.061533496,-0.03486194,0.012304537,-0.049809042,0.04524884,-0.010133497,0.05405572,-0.0052517112,-0.02442941,-0.008966913,0.00798207,-0.00042903775,-0.05420295,-0.009599515,0.021457838,0.014913285,-0.028397175,0.0069341892,0.0088081295,0.031199232,-0.022386216,0.011090131,-0.010352571,0.034542236,0.060511235,-0.047340892,-0.043882243,-0.0016418662,-0.043506272,0.0057230336,-0.02141151,0.04558644,0.03880334,-0.008757149,0.023215847,0.012067776,-0.011902397,0.023428353,0.010972986,-0.02605162,-0.0055927997,0.007883822,-0.010019423,0.03939013,0.032458067,-0.017014073,0.022531928,-0.036136873,0.035203274,0.02021147,-0.0015019182,-0.039845545,-0.0026045018,0.012417754,0.06379719,-0.021901388,0.023915403,-0.031155186,0.027513733,-0.017804652,0.019959392,0.022297636,-0.007862651,-0.043099362,7.0713446e-05,0.03185708,0.008314274,-0.00058117794,0.011391363,-0.04956905,0.075150564,0.011846078,0.00046278138,-0.029685004,0.013099142,-0.0025837498,-0.018714603,-0.012990992,0.028712023,-0.018150881,-0.018850867]
110300	Cash at Bank - Current	Current Account Deposits	asset	[-0.02666253,0.021874815,-0.04908786,-0.01243634,-0.03911195,-0.0015013913,0.029266184,0.027175339,0.003005572,-0.0032448834,0.03463774,-0.010930685,0.0024410447,0.05398287,-0.013855195,0.0032639808,-0.00084694644,0.02592082,-0.0035347268,-0.023336278,0.016206918,-0.009355005,0.0055223983,-0.035817534,-0.011740607,0.012214682,-0.028499963,-0.015962508,-0.003128316,0.034453526,0.0049007535,-0.043418672,0.0150243975,-0.051288906,-0.02455842,-0.011254659,-0.024373155,0.011215271,-0.043882255,0.030298555,0.023926105,-0.041794058,0.03892924,0.0760693,0.020342277,-0.04171394,-0.022429185,-0.018444316,-0.038233504,-0.009544949,-0.037236758,-0.0070405947,0.038819335,-0.0042980467,0.0075669745,0.019975638,-0.06990346,-0.0051312475,-0.037414182,-0.0076619666,0.00563423,-0.024563085,-0.04610869,0.018769652,0.023804234,0.057837155,0.015479264,0.026468156,-0.0178874,0.0022737158,-0.0017623769,-0.016341668,0.0077996827,-0.039313912,-0.033780172,0.01163477,0.07986673,0.013810065,0.011492556,-0.020809472,0.00068892626,-0.017937424,0.025553059,0.011553292,-0.00056582666,0.06457848,0.023395373,-0.019426307,-0.01689262,0.03153888,-0.012710144,-0.025362898,-0.0077201054,-0.04579842,0.0060858494,-0.035760522,-0.017359013,-0.0006109654,0.033501294,0.020109035,0.0901588,0.049381215,-0.028233562,0.030633237,-0.017749552,-0.030575681,0.039102517,0.007582879,-0.020370016,0.014245483,-0.011688479,0.040195983,0.007799424,0.044735696,0.013564761,-0.017049301,-0.043505732,-0.037736353,-0.010339646,0.012994905,-0.031120826,0.02239826,0.031856608,0.0033113896,0.0010290538,-0.01093471,-0.008439962,0.031657934,-0.024905313,0.06256953,-0.0066975025,0.099379465,-0.017728217,-0.0013731895,-0.06032677,0.013366094,-0.00742912,-0.0009670172,0.032545593,-0.034670968,-0.019340191,0.04298957,-0.01823256,-0.027816787,0.011022109,-0.0021800064,-0.009091452,0.014406545,0.00037252568,-0.023829581,0.05331374,0.0083716875,0.005168059,-0.016146315,-0.03558725,-0.0116805155,-0.000834839,0.01566998,-0.010285104,0.024516223,0.019170336,-0.047292896,0.017056411,0.016158126,-0.009451842,-0.018341308,0.020791786,-0.0028227696,-0.008043557,0.04925935,0.004685964,-0.03811741,0.028917084,0.009488111,0.029901963,0.036252648,0.08345159,0.015118454,-0.013028637,-0.04957554,-0.024619441,0.037397914,-0.010837374,-0.014284147,-0.020196171,0.024728945,-0.014696275,-0.020755393,-0.0035981159,-0.019194903,0.0025332312,0.021278597,0.0034227923,-0.026996322,0.060287114,-0.042349726,-0.008105501,0.015190212,-0.008420856,0.009571071,0.0036023753,0.03740236,-0.0054116035,0.049865656,0.022614988,0.0034588242,0.0075693754,-0.055493068,0.04636287,-0.03351992,-0.017054986,-0.05029383,-0.0018337448,-0.056887526,0.002955374,0.0075488733,0.011821902,-0.004798146,0.017251255,0.00023201988,-0.012528253,0.032868057,0.0053305067,-0.009449494,0.020860665,-0.024886297,-0.007614896,0.0752299,0.002011637,-0.08035563,-0.056963064,0.005917888,0.018296817,-0.017139286,0.027288765,0.024957104,-0.00037494898,0.045062825,-0.02646418,0.022167379,-0.020164106,-0.007022688,0.03139908,0.0069789663,0.0026769135,0.056820486,-0.009359211,0.014324002,-0.061733533,-0.014281383,0.010629883,-0.038796835,-0.051945385,-0.04243575,-0.03666606,0.0070793084,6.903619e-05,0.00877112,0.02951751,0.01650907,0.017828014,0.009603596,-0.00999293,0.009201956,-0.007774324,-0.026016286,-0.027962485,-0.009504016,0.0012973264,-0.022234507,0.006252248,-0.018698353,0.0057114577,-0.0048850365,-0.021926127,0.043289907,0.043925088,0.0042587877,0.03794672,-0.0053930897,0.0040994394,0.016281238,0.018682936,-0.020300597,0.017528877,-0.029597739,-0.038144358,0.004376266,-0.013078487,-0.05677469,-0.01708298,-0.0065239514,0.082350284,-0.028780626,-0.023482379,-0.031532213,0.002848419,-0.157229,0.044364598,0.00017118843,0.019590225,0.0005941706,0.0070974915,-0.033544756,0.0074453466,-0.014430585,0.008022013,0.044480983,-0.08128966,-0.010638488,0.027872676,-2.7560748e-06,-0.012251609,0.0007046213,0.0016165185,0.008687098,-0.021764329,-0.0045700804,-0.031439155,0.036336422,-0.0036700603,-0.059308443,0.073143326,0.04521998,0.0071156016,-0.033353984,-0.02709399,-0.01545199,0.031919066,-0.0018746415,-0.018549796,-0.040685993,0.06169438,0.015843337,0.05347527,0.006633006,-0.033544317,0.01772974,0.020358765,-0.0085261995,0.013586452,-0.0066301795,0.021765461,0.0017545738,-0.030054072,-0.012297057,0.027151275,0.0004115591,0.0023627528,0.013316972,-0.016893692,-0.056786187,-0.012570136,0.033876218,0.040087465,0.0017322054,0.028652241,-0.04215792,-0.04485934,0.021893997,-0.0064813592,-0.045441464,0.0037231678,0.0029324489,-0.009027264,0.06463246,-0.043532804,0.016048646,-0.03422346,-0.03446887,-0.027671855,-0.029166887,0.061160844,0.026914999,-0.036721446,-0.035063017,-0.08279056,-0.016438628,0.019684015,-0.005086131,-0.04175078,-0.038217433,0.011241823,-0.005134623,-0.025034329,0.009792948,0.2161501,0.017666603,0.015862286,0.04131354,0.04665549,-0.00292212,-0.011996707,-0.02353122,0.003053644,-0.04039783,0.011319729,0.046792895,-0.045212787,0.020174671,0.0033270316,0.058679514,-0.02408569,-0.008429635,0.11357021,-0.017832119,0.010498414,0.018518602,-0.004497352,0.02453761,-0.045971975,-0.049504798,0.013631751,0.025358222,0.00977668,0.053321496,-0.026832925,-0.0095229605,0.016980553,-0.05066081,0.010251437,-0.016516611,-0.012490323,-0.013747829,0.00019436974,0.034222536,-0.003398644,-0.039829697,0.037024193,0.011766793,-0.024169654,0.0040916177,-0.016267793,-0.0145595865,-0.02362074,-0.008553083,0.027239624,-0.021426376,-0.006086725,-0.0010744,0.03465945,-0.060340583,-0.0120971445,-0.0500827,-0.013397356,0.057021525,-0.024317764,0.0116437515,0.002479758,0.07299039,-0.007963809,-0.016012799,-0.017323386,0.029649591,-4.837611e-06,0.037124477,0.0027877716,-0.0029573306,0.026974864,0.029694261,0.0058751763,0.014379209,-0.026522571,0.010490129,0.046164256,0.028165588,-0.014871676,-0.01934075,-0.042684294,0.033228144,0.015140701,-0.0029033094,-0.05583422,0.03204214,0.02054211,-0.027794385,-0.009458656,0.017255014,0.0073354035,0.016152993,-0.02097018,-0.0068139182,0.012691799,-0.0024419029,-0.024360841,0.05792452,0.008386646,0.00039943587,0.024794228,-0.05301079,0.009116917,0.04427791,-0.033892248,-0.040264647,-0.02957273,-0.058561817,-0.054663785,0.011390304,-0.040372536,0.001980094,0.03759115,0.041091796,0.051326092,0.009192504,0.04487468,0.011032073,0.009646406,-0.032342765,0.01373938,0.019991301,-9.60283e-05,0.005439683,-0.020016216,0.031296,0.006523299,0.06824006,0.009738207,-0.017201727,-0.022468241,-0.016881876,0.045934826,-0.006184672,0.0818859,0.027728435,0.004144082,0.03776726,0.05212523,0.0122818155,-0.031032687,-0.03406417,0.032533176,0.0104295565,0.06951479,0.023658846,0.0037496989,0.040952776,0.0472097,0.027003685,0.03424013,-0.06159453,0.015375236,-0.054826867,-0.076920465,0.021289129,-0.007264761,-0.023750389,0.017201453,0.0003953651,0.022676442,0.05087008,0.033708762,0.022111427,-0.0071667675,0.06957617,0.0039535183,-0.007925259,0.006597561,-0.003488631,-0.02704624,-0.051242325,-0.013513858,-0.060715597,-0.03211099,0.024890307,-0.046534233,0.025571484,0.034276627,0.017698336,0.009460269,-0.06824272,-0.019592496,0.030852605,0.036756746,-0.010580668,-0.010663799,-0.032267034,0.007229135,0.076174,-0.0014867908,-0.014368273,-0.0037039886,-0.017269347,0.028444747,0.011064471,-0.0023480072,-0.048053496,-0.035608683,0.008404429,-0.0035121043,-0.026775753,0.004717788,-0.016997874,0.032652006,-0.00895076,0.0020276906,0.0025529594,6.0814364e-05,-0.03494422,0.006449498,-0.017478397,0.01246784,0.0018034002,0.025439426,0.0064232517,0.013086738,-0.07104643,-0.03437757,-0.01686311,0.027968306,-0.020444475,0.0073076743,-0.051049568,-0.008632375,0.029171182,-0.016490603,-0.00037792715,0.0031452838,0.008686447,-0.032732077,-0.053243157,0.01751382,-0.039087653,0.027209248,0.04274496,0.016174462,-0.017948706,0.032909427,-0.00085029076,-0.0136287855,0.055326745,0.022445874,0.033953927,-0.014723466,0.032668706,0.049514532,0.028481402,0.021004299,0.0018935014,0.016133973,-0.0114215445,0.053210802,0.011503683,0.039847832,-0.01436451,-0.017425431,-0.049984246,-0.025304984,0.044630494,-0.05147929,0.01511725,-0.061580066,-0.039774343,0.03100251,-0.030625636,0.006032645,-0.029789332,-0.01108796,-0.0028222033,0.0151226735,-0.0022882815,0.016695973,-0.03062052,0.0041212705,-0.001154326,0.013362489,0.028656134,-0.039299164,-0.029309174,0.041115716,0.029268464,-0.03252829,0.045701157,0.0075791106,-0.008475877,-0.042409908,0.008876338,0.009387117,-0.009199653,-0.039608892,-0.0032168592,-0.014857175,-0.010688348,0.022032436,0.04379966,-0.021304142,0.010664421,-0.022845658,-0.0010401692,-0.055334173,-0.00036635567,-0.042738512,-0.0011696123,0.0054584956,-0.03449587,0.03306384,0.03670628,0.007083325,0.0018789448,0.0266003,0.013023173,0.04222265,-0.013902009,0.023566844,-0.016504137,0.013616115,0.004214999,0.019441186,-0.023068529,-0.014194713,0.012220788,-0.017556697,-0.05112966,0.0141737405,-0.03173095,-0.001093464,-0.043753766,0.014698473,-0.013599595,-0.031200457,-0.0076439534,0.020218413,-0.017077854,0.020247288,0.041496214,0.027016288,-0.01842281,-0.03400382,0.020423826,0.01798671,-0.054753233,-0.022023099,-0.0017713511,-0.015180119,-0.031903584,-0.03193756,-0.009964808,0.010053916,0.054526813,-0.026759466,-0.066347145,-0.0138487965,-0.03856662,-0.01559594,0.0027708458,0.008484177,-0.0046964153,-0.02258081,0.034137454,-0.015339561,-0.02028942,-0.011857424,0.016670248,0.008912182,-0.00028052414,0.00648343,-0.022623764,-0.033319578,-0.0053080847,0.010366338,-0.009407275,-0.016111687,0.053587046,0.019020958,-0.037099563,-0.009988307,0.012240188,3.379811e-05,0.0059166816,-0.015350016,0.013456102,0.029411012,-0.0065485737,0.005643886,-0.015950186,0.04580432,-0.005885599,-0.023887327,-0.045297284,-0.008488932,0.006851091,-0.12586159,0.03074545,-0.021986386,-0.02470272,-0.009225246,0.007951871,-0.09405051,0.016183358,-0.028849082,0.03088444,-0.015520188,0.0029345108,-0.008481728,-0.024116129,-0.053769477,0.033069305,0.0027858007,0.002187773,0.0031251204,0.005742878,0.017478302,-0.02633333,0.04459797,0.021147227,-0.000111154855,0.032143302,-0.010878269,0.032456458,-0.014811259,-0.034219753,0.042310618,-0.024823144,0.03695186,-0.0066495636,0.03335686,-0.040164996,0.022479758,-0.03475108,0.013998384,0.0014427319,-0.0342552,0.0066178306,-0.037067212,0.0009823306,0.020955719,-0.016809655,0.0042743413,-0.01385802,-0.024790144,-0.01753434,0.015197945,-0.00983054,-0.027422879,-0.03265195,-0.0036823004,0.016575394,-0.062455416,-0.021962008,0.033093225,-0.012434423,0.006194972,0.05634036,-0.050721925,-0.05512872,-0.04985365,0.009132358,-0.08632428,0.035631776,-4.232897e-05,-0.033761602,-0.022320837,-0.007962969,-0.0026494565,0.009464629,-0.00075710093,-0.035014547,0.026031975,-0.02969487,-0.039551888,-0.024915576,-0.039904624,0.01455236,-0.02364288,-0.034985326,0.012324429,-0.006956391,-0.023163086,-0.0023930469,0.010647522,-0.026403256,-0.04585494,-0.028262137,0.009826543,0.02801558,0.018118994,0.07150758,-0.012657107,0.05184237,-0.014119929,0.013183472,0.06564472,-0.011904612,0.021404253,-0.0135932565,-0.019153418,-0.030282967,0.005676182,-0.002359149,-0.006215818,-0.0014873728,-0.023706183,-0.011056057,-0.018905139,0.02799624,-0.05135728,-0.035670966,-0.021257836,-0.012087456,-0.0043583903,-0.03714878,-0.0032335396,-0.01476505,0.043723248,-0.032305304,0.04651646,-0.017281698,-0.0049375794,0.011333158,-0.007704159,-0.0063411924,0.049292445,-0.076691285,0.007323918,0.057739474,0.023897491,0.08095728,-0.09867087,0.041741785,-0.022317633,-0.003878398,-0.010456545,0.004187075,0.0056426353,-0.039447755,0.0023834456,-0.015077551,0.021637866,0.0023347607,0.020567369,-0.018096644,0.0030648105,-0.023731839,0.033217084,0.010219328,0.0144749535,0.031132815,0.0093391575,0.02800317,-0.032026395,0.01026416,0.0120370425,-0.0448565,0.020129686,-0.050912872,-0.013711149,0.0298623,-0.044572927,0.016299361,0.0048344997,0.014091891,0.014567523,0.00010560807,-0.0153986,-0.0068781325,0.015784256,-0.044194523,0.0068253716,-0.018133271,0.03565107,-0.024024673,0.021253526,0.017787674,0.025175955,-0.016029848,0.0057599535,-0.02004976,0.036035318,0.047561966,-0.009321157,-0.043285623,-0.014769085,-0.019628271,0.004379953,0.0022493885,0.043777775,0.023700485,-0.027959483,0.030688977,-0.011999738,0.018870283,0.03833974,-0.012338463,0.0044402895,-0.007124462,0.019040452,-0.030602206,-0.00033484376,0.055677436,-0.039813194,-0.00663545,-0.03574375,0.026110515,-0.008373551,0.0091576455,-0.07012829,-0.009676898,-0.0075955605,0.07066099,-0.0098706875,0.04618089,-0.0028950209,0.044182293,-0.0032910218,0.009757567,0.005874528,-0.04171203,-0.046478085,-0.015400582,0.015945096,0.04251843,-0.024342364,0.0050341696,-0.046617847,0.07927056,0.0078195045,-0.010183503,-0.018400101,0.0024404267,0.007628868,-0.030548627,0.03069517,0.022627672,-0.04996468,-0.059077896]
110400	Accounts Receivable	Accounts Receivable	asset	[-0.064698994,0.011249136,-0.016835835,-0.0007888831,-0.031307235,-0.011134172,0.004056805,0.00050651067,-0.015865073,0.009813999,0.032838985,-0.008234483,-0.03382364,0.033865344,-0.0050507463,-0.024029398,-0.00022472368,-0.030688077,-0.030147288,-0.018555192,-0.0004502945,0.0040635746,-0.010418054,-0.0068097855,-0.016001105,0.007282315,-0.032628357,-0.009606756,0.0033065844,0.015881557,0.025508435,-0.0053835083,0.0073040896,-0.0260569,0.030261816,0.008620401,-0.017357023,0.02792482,-0.052555922,0.010895162,-0.032532677,0.0005838348,0.010566365,-0.041071583,0.017468952,-0.0041638054,-0.037112467,-0.0041186665,-0.019673761,0.028313827,-0.024569184,-0.020749148,0.07302767,-0.026510825,0.01956544,0.026291883,0.0060655433,-0.029075028,-0.048157774,0.012505325,-0.0053391713,0.017526012,-0.0654305,0.0038182242,-0.007196349,0.061994318,0.011645911,-0.00795181,-0.01050947,-0.0030998304,-0.021764774,0.007348902,-0.054809142,-0.0016166866,-0.08389345,0.004571288,0.038920138,0.027960243,-0.012107627,-0.025063766,0.014156954,0.0013509678,-0.012097659,-0.010533166,-0.045497637,0.08117594,-0.014071936,0.055611305,-0.03562845,0.006184583,-0.029587783,-0.005259346,0.008263063,-0.025323661,-0.014690105,-0.014992253,-0.043403074,0.012534162,0.015040129,0.017909199,0.043904144,0.0023346634,0.007002484,-0.00020236264,-0.022835894,-0.032145157,0.0342913,0.013105233,-0.016481688,-0.029632777,-0.044618253,-0.012249916,0.014689182,0.02246519,0.022274064,0.010627228,0.02042899,-0.0051102405,-0.002487673,-0.01760489,-0.0023043894,0.040035337,-0.021214712,-0.05162948,0.00772512,-0.060978714,0.06175074,0.07252741,0.0014894786,0.024638781,0.049291365,0.024494953,-0.035514835,0.024479369,-0.01984172,0.0011063676,0.023610193,-0.0033535038,0.037193548,-0.04485035,0.058645524,0.07164698,-0.04017384,-0.031803105,0.0734815,-0.025717966,-0.010767729,-0.023220688,-0.011132909,-0.044248227,-0.008386635,-0.013281745,0.061855204,0.005840943,-0.029789671,-0.066134505,-0.040820073,0.008401458,0.03058412,0.030742006,0.017125878,0.06660249,0.049657587,-0.021013057,0.0005493455,0.032423057,0.026636494,0.023236694,0.0006865711,0.0014313421,0.034118958,-0.043099146,0.01729456,-0.036016304,0.0019987742,0.020436507,0.017928766,0.0040962505,0.05614803,-0.043889146,-0.0053957533,0.03189616,-0.01535704,0.019482315,0.023639323,0.036733236,0.0082909735,0.012345013,0.023300206,0.015526759,0.0021418794,-0.018808274,0.005360716,0.003405248,0.010160938,-0.02720661,-0.01757401,-0.02959293,-0.031018734,-0.008961048,-0.029181503,0.011543373,-0.030677607,0.007798689,-0.018749056,0.022983072,0.004039214,0.007314942,-0.023578534,-0.077528924,-0.023503281,-0.03232652,-0.0034195457,-0.0028636414,-0.022139281,-0.053239018,0.008110522,0.024362393,-0.0068995114,0.0082511185,0.03474777,0.01993538,0.0045791985,0.112103485,-0.018823542,-0.01446251,0.013211431,0.01492076,0.025993876,-0.055795077,0.0011025735,0.018001331,0.027162554,-0.021280617,0.04158955,0.036563966,-0.008933009,0.036557253,0.022185266,-0.008264838,-0.047429148,-0.047680657,-0.0052021258,-0.032935232,-0.02781294,-0.00551183,-0.031925432,0.0631722,-0.036442254,-0.007045354,0.0027554184,-0.009792996,-0.011967547,0.040386338,-0.010420134,0.013268562,-0.026736915,0.0070662727,0.039225675,0.034974538,0.029779155,0.007579539,0.006553229,0.03105293,-0.03722455,0.038444508,-0.042046998,-0.015089606,0.039942738,-0.0002478034,-0.010122926,-0.015086258,-3.3009019e-06,0.011255415,-0.010114118,0.046525132,-0.017164335,-0.0049332255,0.045180973,-0.01217291,-0.013402102,0.059861325,0.0021210036,-0.08773762,0.044246398,0.0017425052,-0.045426168,-0.0030935283,0.014432592,-0.03294432,-0.021597277,0.046398852,0.05988645,-0.017976081,-0.038222622,-0.035979874,0.0015593052,-0.13997024,-0.033356123,-0.015407411,0.0106158955,-0.024414854,0.036453377,-0.04439932,0.021720307,-0.030246427,0.012158426,0.046665598,-0.06968423,-0.011106984,0.021660574,-0.0070990426,-0.026234522,-0.06276585,0.04888547,0.027115908,-0.00571097,-0.018748214,-0.018610459,0.04156326,-0.036268704,-0.025377532,0.046069853,0.0582857,0.064556085,-0.034005895,-0.0041813105,0.033549428,0.010830072,0.0047523007,0.009170165,0.005971288,0.026990479,0.0056847297,0.03870306,0.026977401,-0.037857305,0.024220373,0.041584544,-0.03263021,0.022241848,-0.0077440348,0.008640476,0.013761377,0.019726312,0.0004704962,0.013135792,-0.02272253,-0.023043772,-0.009235128,-0.055954363,-0.018738464,-0.021376614,-0.016287271,0.020928103,0.001418526,-0.0006579911,-0.009618156,-0.09064249,0.021779994,0.03953148,-0.013534342,-0.045991607,0.037780404,-0.019638944,0.027603973,-0.025405025,0.03480276,0.026020318,0.035063248,-0.037760437,-0.021148553,0.046361063,0.0077388138,-0.0037790958,-0.025343211,-0.061414126,-0.06140175,0.03641652,-0.049764574,0.024560964,-0.043014072,0.0227966,0.027148359,0.042481806,0.06022845,0.22692226,0.040878076,-0.023450337,0.0476268,0.057940118,-0.017467938,0.028483758,0.00027382697,-0.012557271,-0.024219556,-0.0052769026,-0.0013488923,-0.0046103476,0.030777434,-0.051931053,0.013680695,-0.062370967,0.01090671,0.05470233,0.030288387,0.015744155,-0.0047050025,0.015652414,-0.03642744,-0.0491815,-0.008019904,-0.032748953,0.022318488,-0.013272665,0.040252432,-0.03800079,0.01801973,0.0636267,-0.0028483253,-0.0033883494,-0.029212935,-0.0015869599,-0.0035471062,0.031053375,0.036755193,-0.025843859,-0.062072836,-0.022987809,0.0433039,-0.029940318,-0.026431946,0.014362657,0.048339583,0.016788099,-0.01618201,-0.044316962,-0.052548192,-0.038984437,0.0003757764,-0.009465462,-0.030950062,0.0081613045,-0.014670168,-0.03602961,0.050430417,0.018348588,-0.015075457,-0.008583462,0.040488165,-0.0073784613,-0.012551914,-0.019086933,0.009164242,0.012888889,0.03337378,0.0053583058,0.02428896,-0.0012109368,-0.033980217,0.037111394,-0.018843692,0.029181791,0.011911267,0.014683483,0.01257314,-0.014476541,-0.0102217905,-0.028723102,0.05382327,0.017022658,-0.020083392,-0.003033609,0.031658802,-0.028893612,-0.001040603,-0.013825814,0.0035376586,-0.0086876275,0.006437745,0.030685497,-0.039627336,0.021430273,-0.0074374666,-0.056232493,0.0047829817,0.038566362,-0.010809725,-0.02511295,-0.033988193,0.012424032,-0.012936805,0.022222027,0.0040464858,-0.016202014,0.006232101,-0.03650445,0.0073655476,-0.022019869,0.0038478049,0.031528234,0.019304847,-0.009798992,0.015552395,0.0941839,-0.0018818135,0.029851591,-0.008609479,-0.025796626,-0.0039883927,-0.008518795,-0.0580979,-0.0035918024,0.0030011192,-0.00023752196,0.0046230387,0.04011126,-0.0077105872,-0.013231856,-0.0052673584,0.03424948,0.017999625,0.00886367,0.0074754003,-0.050357625,0.027315907,-0.04661657,0.04502175,-0.020789366,-0.01248009,0.010082305,0.02644963,-0.026502185,0.025752867,0.023854215,0.039970893,0.010313201,0.014507585,0.025427802,-0.044335067,0.009248115,-0.04456979,-0.008729771,-0.012729734,0.038264066,-0.028287278,0.0077544088,0.012602064,-0.018428931,0.06574123,0.0022690515,0.05146081,-0.013430231,0.03505432,-0.012881747,-0.04570239,0.0017832147,-0.03763896,-0.037449412,-0.008626823,-0.010061148,0.01230876,0.008679405,-0.023068009,0.0029444972,-0.006904607,0.046133123,0.022435848,-0.0038547658,-0.006896097,0.012751166,-0.010947351,-0.05301373,-0.0035465627,-0.048171792,-0.05863453,-0.012810989,0.05028835,0.043315943,-0.034507923,-0.037458364,-0.004449918,0.015725289,0.016678546,-0.011096828,-0.008573691,0.02764491,-0.036281954,0.008336893,-0.049176574,-0.0058153365,-0.0019135623,0.019546557,0.03380632,-0.036180444,0.024477359,0.036018685,0.037401583,-0.02238188,-0.009124822,0.010700647,0.0031770384,0.04601903,-0.009373417,-0.015527046,-0.05207111,-0.04890314,-0.0070804027,0.019379448,0.0068521774,-0.040181268,-0.025813231,-0.016072767,0.033740744,-0.05257733,0.017357795,0.0009349767,0.0066132396,0.062827595,-0.015206336,-0.0023862687,-0.00249606,0.0014662269,0.012022344,0.009233249,0.014107014,0.019456016,0.0127097685,0.0062754704,0.027887324,0.010394771,0.0033222765,-0.027614063,-0.021183483,0.051563635,0.0071375864,0.030517045,-0.047514774,0.025166536,-0.039450776,0.048543654,0.025160775,-0.003363376,-0.008397658,-0.06986204,-0.00639325,0.018753473,-0.009648574,-0.026525043,-0.00038989857,0.02036416,-0.043215156,0.020974558,-0.0069083255,0.00533953,-0.01717196,-0.010249858,0.0008842135,0.015985928,-0.047170445,-0.012645343,-0.04302607,-0.020173596,0.013878271,0.015926681,-0.00069656875,-0.055709604,-0.048608005,0.043709144,0.019429693,-0.05495259,0.016250318,-0.020332793,-0.00248533,-0.0069850697,0.021360807,-0.007060221,0.018609937,-0.03698211,0.06983392,-0.014102123,-0.0037706995,-0.003560881,0.05729879,-0.05549204,-0.0054623117,-0.009164104,0.0022008752,-0.030386968,-0.022496123,0.0022171503,0.013311818,-0.020326884,-0.03569649,0.0104857255,0.03667718,0.014083624,-0.05514501,0.0013972236,-0.029196352,0.06572645,-0.019946154,0.050206445,0.0060901176,0.0045148474,-0.0012978793,-0.004563499,-0.026189689,-0.016468987,-0.034246743,-0.027677555,0.028231926,0.021633375,-0.03656837,0.026918372,0.013793454,-0.06609653,-0.017339697,-0.016171755,-0.02221994,-0.0036236127,0.04030015,0.025179114,-0.016918238,0.033221424,-0.027461039,-0.02494642,-0.025986021,0.054821756,0.026145779,0.010503141,-0.029424066,-0.016746378,0.025682686,0.0048865858,-0.03292901,-0.012034902,0.040803466,-0.014412622,-0.036179323,0.03635468,-0.014417541,-0.005146933,0.013310281,0.014516267,0.048126496,-0.04033121,0.007395385,-0.054547403,-0.01537565,0.04008391,0.0061196247,-0.0131359305,-0.015096629,0.010307995,0.00083872926,0.037804607,-0.009485056,-0.016530953,0.029823076,-0.041899893,0.05919373,-0.008878955,0.020719262,0.003720413,0.009567042,-0.0003964425,-0.029006857,-0.030004263,-0.010965383,0.038889144,0.022221103,0.008886421,-0.0037038387,0.0019602894,0.019504739,0.003381651,0.0070953476,-0.00055364735,-0.0054591037,-0.14233613,-0.027067661,-0.007246777,-0.052868746,-0.042478375,-0.038447928,2.5495963e-05,-0.005464424,0.0050070644,0.013041359,-0.042302407,-0.003824012,0.033313807,-0.017043047,-0.013246273,0.04814378,0.01473172,0.014000239,-0.03090409,0.022736026,-0.006197158,0.014459807,0.06423167,-0.020532645,0.0068323924,0.017881064,0.009772551,0.045186523,-0.031851113,-0.01873942,0.01690968,-0.0116810575,0.048992362,0.010816679,0.016148686,-0.019278362,0.02096927,-0.050849214,-0.030329654,-0.030757926,-0.02577926,0.016163304,-0.01871498,0.009353272,0.044831667,0.0332488,-0.0071611037,-0.0150800785,-0.023564821,-0.061254695,-0.019968005,0.035073288,-0.057349212,-0.0098865125,0.02504697,-0.04762092,-0.014035397,-0.008245559,0.0126955705,0.037640892,-0.009974017,-0.006637025,-0.045804027,-0.0452061,0.0065158,-0.004259355,-0.013503208,-0.012268002,-0.003780825,-0.039180703,-0.011824534,-0.010115227,0.04976952,-0.060382437,0.0029646812,-0.036733106,0.028340416,0.004239153,-0.035206795,0.006388164,-0.018376784,-0.005695839,-0.027569331,-0.01586694,0.029686037,0.022148162,-0.019526996,0.0073223384,-0.06780742,0.006866901,-0.057665985,-0.017937737,0.011174822,0.046773564,-0.00840141,0.015572204,-0.012715473,0.0068284413,-0.0027578943,-0.016671155,0.031463046,-0.058927782,0.033328373,0.041374106,-0.036794867,-0.043256365,0.036644936,0.020147298,0.013117142,-0.02846692,-0.0071794433,0.010786478,-0.04151747,-0.022656916,-0.07684624,0.015854755,-0.02251206,0.031469252,-0.019354213,-0.0012797096,0.04480209,0.014540998,0.036598463,-0.03509873,-0.0019140595,0.058413148,0.014368002,-0.017108105,0.044725794,-0.023992306,0.007471846,-0.007547561,-0.02768925,0.009019132,0.042680364,0.059563085,-0.02879199,0.041935097,-0.03488515,-0.053242926,0.018355647,-0.0018079497,0.004710936,-0.019468693,0.025707861,0.018040588,-0.007863294,0.046367638,0.0029380172,-0.007945972,-0.032018006,-0.0046099112,0.04542575,-0.0034419426,0.018364396,-0.014274976,-0.006704322,-0.040883273,0.013985631,-0.0137477415,-0.017314691,-0.044985864,-0.021548541,-0.024500255,-0.035076685,0.057440992,-0.047295466,-0.011662283,-0.003975641,-0.008124005,-0.017058156,0.004322243,-0.029583188,0.0079541635,0.025288008,-0.017844992,-0.024298266,0.020947533,0.041297108,0.015190357,0.043777782,0.04772613,-0.002311453,0.015995013,0.013726521,0.07014988,0.021665612,0.01331061,-0.0035563083,-0.009105843,-0.010827349,-0.02834605,-0.037628017,0.05424694,0.045869224,-0.0027135368,-0.0055784476,0.05596022,0.021791767,0.04666714,0.017586771,-0.047502287,-0.067211814,-0.029747851,-0.061095186,0.044466052,0.019290859,-0.0036931264,-0.013586058,0.0507348,0.015046295,0.008500011,-0.029993689,0.025302533,-0.022354493,-0.02678593,0.0004862989,0.0072669378,0.002604081,0.045019273,-0.040949266,0.05865679,-0.022772625,0.00013774418,-0.012714017,0.009719917,0.01461913,-0.0013614286,0.037834812,-0.02644233,-0.022158537,0.00031214053,-0.0016577368,0.05792302,-0.031019336,-0.0016590398,-0.031134762,0.0053828764,-0.011891288,-0.009886768,0.016725898,0.0046870587,-0.054341372,-0.006001245]
110500	Input VAT	Input VAT	asset	[-0.024925368,0.025598163,-0.03437047,0.05417194,-0.012968739,0.008504503,-0.004358944,0.007801093,0.00915961,0.00824868,0.011059216,-0.008841569,0.027557973,-0.0015356747,-0.029482087,-0.051387135,-0.0152353775,0.008994755,0.0028419115,-0.026555452,0.030896194,0.012875629,0.0009500633,-0.016876388,0.016213788,0.005154628,-0.0465599,-0.010328157,0.010520832,-0.026399722,0.028191682,-0.0056171133,-0.07439499,-0.08147975,0.009594357,0.0149812,-0.00037332077,0.020182274,-0.040471558,0.03463119,-0.0130348075,-0.009575458,0.025630668,-0.028871007,0.029872114,0.013172886,-0.05190498,-0.03241793,-0.04843567,0.021849262,0.0024082426,0.02120301,0.05728365,-0.029274374,0.04711767,0.04175992,-0.022631709,-0.016545102,-0.058431186,0.01309762,-0.019845646,0.024496242,-0.010929368,-0.010251257,0.011935966,0.061594695,-0.0029443828,0.004746019,-0.024296418,0.00049415644,-0.01728303,0.056067124,-0.02770622,0.010483244,-0.04469273,-0.00039426913,0.031992253,0.013708865,-0.010948461,-0.01035714,0.01842372,-0.05367355,0.0005565812,-0.003902604,-5.3307005e-05,0.04339321,-0.027305413,-0.022415878,-0.041443422,0.00898586,-0.014541729,-0.02839315,0.035908,-0.017208837,-0.030459404,-0.038959127,0.006612467,0.032999843,-0.018177493,0.018701727,0.06950928,0.065822996,0.03193001,0.014823836,0.030596666,-0.020028554,0.02570591,0.0044430885,-0.00793341,-0.049208116,-0.002231593,0.010727978,0.038381904,0.018886186,-0.002392415,0.0038476016,-0.015688103,0.02348698,0.032282487,-0.005756461,0.08609522,-0.03267274,0.037329543,-0.017942753,0.032985076,-0.0055383705,0.030232819,0.0124819605,-0.00014234132,-0.013316818,-0.022418488,0.023201482,-0.0456836,0.033538546,-0.03663315,-0.03261999,0.038429312,0.018780418,-0.0133847315,-0.04069478,0.032157365,0.047408406,-0.046163872,-0.057868674,0.081648394,-0.041400544,0.007247733,-0.007871201,0.020454977,-0.021260545,-0.027832933,0.009549286,0.03148716,-0.019368717,-0.0015535416,-0.01160246,-0.074589334,0.030055875,-0.011664274,0.044560827,0.033741597,0.014779168,-0.0020215518,-0.038955446,-0.033037137,0.02864081,-0.02469711,0.032474864,0.013876249,0.009959412,0.029570602,0.002192341,0.02943158,-0.007011284,0.055505734,0.03242475,0.05750133,0.009904895,-0.01615038,-0.02746189,-0.011295081,-0.005519558,-0.009445997,0.0028545435,0.0035657655,0.006156922,0.04540393,0.018723428,0.0048664166,0.051239178,-0.024487985,0.0072447285,0.02011828,-0.04212409,0.048809115,-0.0034754705,-0.030948276,-0.002034332,-0.0326001,0.023573672,-0.033695444,0.040605847,-0.014384943,-0.030087743,-0.013772921,0.0059100403,-0.01119565,-0.023433419,0.020403462,-0.02511442,0.01395526,-0.014494094,0.031609092,-0.05152662,0.0066659423,-0.019813545,0.020251002,0.01340834,0.004419238,-0.05617946,0.005726646,0.017632358,0.02229504,0.015092771,0.03658686,-0.016999539,-0.0090963775,0.018469984,0.039157275,-0.013073747,-0.023423862,0.013315653,-0.031095937,-0.03000691,0.02066816,0.0007730354,0.025843024,0.03481079,-0.044121865,-0.001660403,0.0020931147,0.01963078,-0.0059839156,0.01760829,0.005840392,0.0026207836,-0.060220458,0.08665298,-0.012355726,-0.021374915,0.031730156,-0.0002726043,0.00043233737,0.035827767,-0.0037638245,0.008792928,-0.002584713,-0.009726365,-0.009748564,-0.010876069,0.021996913,0.0034421624,0.033778656,0.026087342,-0.033916708,-0.022949286,-0.036821246,-0.026452787,0.049036272,-0.011062044,-0.024007387,-0.005738211,0.0039315284,0.032134015,0.003011585,0.09027029,-0.0059595685,-0.037170462,0.034108613,0.03262665,0.045778465,0.001352352,-0.024024712,-0.066043474,0.03948303,0.007867104,-0.0058246306,-0.021458788,0.01688272,-0.07048306,-0.025709787,-0.028310826,0.05300156,-0.011078906,-0.074681215,-0.01458368,-0.023624627,-0.15801051,-0.02383951,-0.0397099,0.0056761075,-0.0087692365,-0.002184823,-0.05155948,-0.024022685,-0.0372132,0.010076769,0.03074688,-0.06542039,0.0021932935,-0.0083942,0.013905262,0.0033347253,0.023081318,0.007224363,0.014821008,-0.014008521,-0.014097932,-0.063526526,0.02139755,-0.026969101,-0.022829417,0.026951307,0.024524018,-0.022944408,-0.06308265,0.010400286,0.007248878,0.0014406512,0.016432425,0.006713809,0.045061607,0.044124093,0.00644492,0.021231377,0.005741671,0.040338244,0.01832529,-0.011150223,-0.011417213,0.047334753,-0.012487047,0.017272338,-0.008130281,0.0070813335,-0.01890176,0.02151948,-0.02537626,0.008879561,0.026035205,-0.011459961,-0.032189246,-0.0016657644,-0.018926265,0.04553592,-0.03161524,0.01665919,-0.026437324,-0.09460412,0.009146132,0.0033640093,0.036304295,-0.019671332,0.037655454,0.016943445,0.025115656,-0.0068033044,0.086537,-0.050309848,-0.024229204,-0.0351344,-0.015231488,0.015835471,-0.049734596,0.004741104,0.0057376516,-0.12615164,0.00063296437,0.0050420994,-0.014065015,0.01200102,0.002053955,0.009486877,-0.017275376,0.03997484,0.009710361,0.21159978,0.058834676,0.03328144,0.0139427455,0.014911078,-0.024103938,-0.04587827,0.004693213,-0.026837435,-0.031704698,0.010832739,0.016448935,0.0064333878,-0.002249654,-0.05349405,0.054414134,-0.028746134,0.06214932,0.07331954,-0.046179343,-0.02767864,-0.022766335,-0.00047705922,-0.0053600576,-0.043232113,0.0033111225,-0.034843262,-0.0031529458,-0.015276891,-0.007666202,-0.056106932,0.021688484,0.013947212,0.022189088,0.008149855,-0.053694155,-0.008786589,-0.01489927,0.020916667,0.0049993554,0.0306277,-0.030101012,0.018810434,-0.0019055152,0.012488181,-0.01078505,0.029301723,-0.012812479,-0.019968068,0.002022843,0.008479736,-0.072275154,-0.021850344,-0.001868981,0.018894572,-0.00062512344,-0.026519982,-0.0069910907,-0.032916136,0.0026448965,-0.0038446,0.0047609042,0.006930129,0.014375838,0.0030932503,-0.0054022227,-0.0105628045,0.029176094,0.025530247,0.015953138,-0.022218475,0.047129072,0.01601641,-0.015228331,0.02135532,0.021852294,-0.041728914,0.0002492584,-0.023756694,0.029297533,-0.03878729,-0.016563313,-0.0005475352,-0.007328157,0.010374761,-0.060719937,-0.027008373,0.024791408,0.039528705,-0.003332098,0.015617632,-0.028628623,0.026821807,-0.0178419,-0.0067392453,-0.054926734,0.035878204,0.0024638665,-0.023814544,0.028083235,0.022832673,-0.028932981,0.03401691,-0.0076924725,0.028172681,-0.040846936,0.012411713,-0.012919987,-0.035469033,-0.006492508,0.020269658,0.034536187,-0.023161985,0.031184345,-0.0011795633,0.003918208,0.022990791,0.03285262,0.056062356,0.013994682,0.015117691,0.012796834,-0.022547688,-0.03437744,-0.0199526,-0.05532033,0.014008381,-0.0045532165,-0.018061215,-0.012415869,-0.018244904,0.0014710041,-0.05358242,-0.0038902746,0.06465555,-0.011703142,0.005686704,0.003668242,0.031165872,0.04949687,-0.034788653,-0.014506798,-0.055930194,-0.026483074,0.043419383,0.016240317,-0.024604186,-0.0053653964,-0.013373532,0.061632413,-0.0041971533,0.018182164,0.030554144,-0.018457139,-0.009969729,-0.05085061,0.01759263,-0.004692724,-0.010428403,-0.032124978,0.00057350565,0.013380601,-0.017275961,0.08166068,0.0122986045,0.014709238,-0.024785133,0.020538459,-0.03533144,-0.026720615,-0.014623913,-0.017709032,-0.04042005,0.04767543,-0.009017014,-0.0064792554,-0.0323555,-0.032436527,-0.034377366,-0.0064624683,0.040589843,-0.0018180151,-0.024571402,-0.014246206,0.010100298,0.0069807842,-0.020803446,-0.01795874,0.0514174,0.014224176,-0.040339734,0.10164917,-0.001175205,-0.024468593,-0.013301244,0.025330376,0.032445207,-0.01011116,-0.021804811,-0.06446348,0.025999252,-0.011663061,0.0013926177,-0.020772833,0.04989918,-0.0005242189,-0.020637413,0.028803315,0.011696745,0.004313679,-0.016917363,-0.014263376,-0.027746437,-0.009812008,0.025559459,-0.0025503587,0.030894306,0.025655096,-0.025569722,-0.04903213,-0.006294799,-0.004285018,-0.02202417,-0.05797652,-0.049189467,0.021175928,0.007809238,0.0059172413,-0.0319422,0.032911625,0.007774357,-0.04319565,0.006741975,-0.01275609,0.007823169,0.024507528,-0.025376251,0.024265882,0.00700051,-0.019745676,0.036072213,-0.0024864965,0.052833326,0.037272617,-0.01198663,0.020923678,-0.046330713,0.008732796,0.012289927,0.02527933,-0.04133463,-0.03183777,0.026312253,-0.020599844,0.0032208615,0.008512026,-0.006811608,-0.006162596,-0.00628023,-0.030612865,0.03395614,0.0023749708,-0.01922859,-0.025427822,0.03569603,-0.075900435,0.015184342,-0.048312426,-0.0051315865,-0.023885548,0.022830052,-0.025023134,-0.0020181637,-0.024079077,0.030535167,0.049270928,0.057730637,-0.0066890437,0.028938698,-0.00045986223,0.029369926,-0.027302075,0.0077958154,0.038127016,-0.018791756,0.037483558,-0.040059872,0.022498542,0.013472463,-0.05356365,-0.022332925,0.008926651,-0.017155869,0.015790122,-0.021013113,-0.0148732085,-0.014696396,0.0045440523,-0.020271242,0.036374975,-0.036237348,0.0070356578,-0.061671104,-0.0021024677,-0.015492874,-0.0012679916,0.029074341,0.005053153,0.036258813,0.016004972,0.030736782,-0.027105732,-0.03338916,0.08179619,-0.0070845895,0.027255269,0.09393724,0.021591892,-0.0035104488,0.0035186235,-0.009243391,-0.030844204,-0.0064370385,-0.048479423,-0.032740347,0.016271273,-0.008951762,-0.00020101691,0.0054905135,0.009535725,-0.01858243,0.03963312,-0.037066154,-0.006249495,0.0003248626,0.0060152193,0.01908923,0.0018178058,-0.019380441,-0.014929188,-0.00314383,0.013352098,0.09734119,-0.01648582,0.014155067,0.0018015464,-0.054247107,0.0019617034,0.04574734,0.027094925,-0.058990236,-0.005408399,-0.04589997,-0.027610136,0.00980087,-0.017575603,0.0050481325,0.06405434,0.010552775,-0.027191747,-0.04847257,0.0026733056,-0.011063951,0.0031036392,0.0060477094,0.05001923,0.05525529,-0.006946288,0.042701777,-0.0022420876,-0.0008163113,-0.0053492105,-0.029993633,0.018451182,-0.007238034,0.023544628,0.034665655,-0.022206817,0.005746132,-0.045103293,-0.024289496,-0.007814716,-0.05631463,-0.034438,0.03265639,-0.03646319,0.001800849,-0.017185576,0.0028751527,0.024268044,-0.024789099,-0.024323253,0.014808212,-0.009414606,-0.1418716,-0.02374738,-0.027482089,-0.011569723,-0.049258087,-0.0074431407,-0.005073644,-0.02705042,0.0026124963,-0.0035581512,-0.004783394,0.010227015,0.016024288,0.008576961,-0.006540813,0.029112302,0.006912225,0.00062747736,-0.006078928,0.0101315705,0.0034451862,-0.009325706,0.062688455,0.014005515,0.03114636,0.0013653793,0.023341553,0.05413697,-0.037932165,-0.046825685,0.029830864,0.034827713,0.0047353203,0.05880327,-0.012162202,-0.016864397,0.014686706,0.036836337,-0.012975988,0.00018674642,-0.020557094,0.048049036,-0.00047252252,0.010008427,0.054363362,0.05041078,-0.0035552676,-0.0031668504,-0.0222733,-0.039751966,0.023749836,0.02666932,-0.0022381698,0.012372924,-0.007919831,-0.029578973,-0.034450673,-0.037041724,0.020942021,0.0040473863,0.0035738877,0.0055578975,-0.035466027,-0.07894033,0.01944829,-0.028447744,-0.05519223,0.019429952,0.022883782,-0.021503963,0.015928704,0.03151246,0.03599789,-0.0351261,-0.0041552065,0.017693574,0.05608895,-0.006760382,0.030688217,-0.0033038147,-0.052434333,0.014278133,-0.054060325,0.02766838,0.024773384,0.014973135,-0.017116355,0.059009954,-0.0526618,-0.02664185,-0.017625488,-0.026838468,0.0062023313,-0.046019405,-0.016147152,0.007931126,-0.0466883,0.027991703,-0.012632719,-0.012437289,0.0077392287,-0.015525075,0.014806009,0.015256884,-0.03486276,-0.010699837,-0.011096959,-0.059588335,-0.007911742,-0.019427322,0.038545553,0.017785536,-0.008977401,0.018527124,-0.044528756,-0.037698302,-0.00996309,-0.018864535,-0.033601776,0.038362484,0.03130193,-0.017621519,0.0397926,-0.024543682,0.036237717,0.00596484,-0.020098438,-0.01813347,-0.008784729,0.009251441,0.047262073,-0.017189698,0.052302904,0.004465809,0.01382448,0.009336674,-0.0071458016,0.0686257,-0.012336017,-0.06016489,0.0049626273,-0.014764909,-0.021696998,0.009081811,-0.026824001,-0.010034893,0.031230077,0.008921797,-0.028543465,-0.048690595,-0.023506373,-0.033772066,0.036028933,-0.009255498,-0.017009024,-0.019366235,-0.022602435,-0.0004312498,-0.019201811,0.031764142,-0.015932065,0.050367758,0.03482599,-0.031309642,0.009647656,0.0036557168,-0.049289547,-0.0055588563,-0.0049462207,-0.021121224,0.010067991,-0.0067033693,-0.030526146,0.06269509,-0.02425154,0.007945961,-0.03346168,0.002339274,0.041911747,0.007527184,0.019221453,0.026188977,0.012046628,-0.002972437,0.057930235,0.03883913,0.031896442,0.020153943,0.016579064,0.0016816535,-0.036375985,-0.0005013347,0.013138555,0.014430916,0.038468912,0.012269376,-0.02984095,0.020651972,-0.037982665,0.08425094,0.03512462,-0.04825543,-0.046449576,-0.06434182,0.0022109603,0.015658202,-0.0018265061,0.0024157471,-0.013597295,0.034440655,-0.02947874,-0.005748221,-0.0070255054,0.036666077,0.020345334,-0.04399657,0.016208176,0.011409719,0.019264964,-0.03696344,0.0149420425,0.025742343,-0.02389154,0.005458438,-0.005507898,-0.034581296,-0.01762448,-0.01688206,0.008900929,0.01227738,-0.008502333,0.053301014,-0.047947887,0.009012791,-0.02338295,0.009789367,0.028686153,0.028673043,-0.05859946,-0.051804543,-0.0045303316,0.025816493,-0.077853695,-0.02007838]
110600	Prepaid Expenses	Prepaid Expenses	asset	[-0.03540273,0.001268118,-0.03310168,0.015686044,-0.012065128,0.018533982,0.03584362,0.045916874,-0.023969017,0.0115993,0.021878444,0.0048039276,-0.037285935,0.013511211,-0.012665977,-0.022755155,0.035967454,0.0005841364,-0.013188297,-0.008909309,0.013084195,-0.021587845,-0.019809505,0.0059763384,0.0048135067,-0.010198427,-0.009903709,0.02067044,0.032145135,-0.035636596,0.012472356,-0.053676397,0.025555499,0.0048226765,-0.042333722,-0.013923756,-0.035048038,-0.015095164,-0.062171046,0.030035589,0.012277137,0.011917594,0.002173946,0.0001283585,0.01061917,-0.005043252,-0.049433686,0.0057900385,0.0071433103,-0.035670355,0.006373318,-0.058969304,0.051554903,-0.06647778,0.023420617,0.034966026,-0.044597276,0.011579761,-0.043314148,0.013744884,-0.06071343,0.01057585,-0.0048259324,-0.012993887,0.04436323,0.04539546,-0.0064493637,0.018314801,-0.010793568,-0.0150583545,0.022440458,0.0012703623,-0.028338691,-0.014809915,-0.058630493,0.038271345,0.009399609,-0.044726565,0.023847217,-0.015837079,-0.008161322,-0.042704258,0.018356062,0.004450254,0.02266174,0.05722437,-0.040800393,0.035132542,-0.021499256,-0.059129395,0.0012856913,0.014912881,0.034966733,-0.04077981,0.011355364,-0.002377276,-0.03942182,0.0037678801,0.046994023,-0.0071650874,0.025308192,0.0013437383,0.06858026,-0.0075611463,9.1462265e-05,-0.011361736,-0.0074786176,0.01131992,-0.017147098,-0.02755116,-0.018431647,0.08083748,0.020291794,0.00080316793,0.011271662,-0.02738442,0.009124341,-0.030577496,-0.046552528,-0.019732501,0.06844567,0.011744098,0.0057643442,-0.0021293827,0.011122578,0.027632568,0.019703211,0.037698425,-0.005847216,0.020235911,-0.018274305,-0.0014403178,-0.045903567,0.038976837,-0.080291085,-0.042815305,0.025055233,-0.015183496,0.0015116201,-0.029585643,0.023680802,0.06721449,-0.011314579,-0.006080594,0.022942925,-0.025387174,0.004332105,0.00060315535,0.023475116,-0.04129896,-0.056690898,0.008288731,-0.012257163,0.000208618,0.036336467,-0.017386604,-0.016343178,0.017998712,-0.020030877,-0.00079497223,-0.031781916,-0.0035306762,-0.036638852,-0.030155566,0.0028154077,0.00054521067,-0.005816716,-0.0006784771,-0.027954526,0.009311114,0.055465356,-0.056568943,0.0152161615,-0.030370628,-0.0037988622,0.008476872,0.051184062,0.0028911734,0.036916435,-0.050001554,-0.06619543,0.03095495,0.0326442,-0.02769859,-0.0041444763,0.012696432,0.026743114,-0.02376196,0.022044523,0.036223214,-0.0073720026,-0.036725838,0.028593667,-0.05551361,0.022081943,-0.04501695,-0.014607241,-0.03108178,-0.0051402994,0.0590043,-0.0020652108,0.022187905,-0.02156792,0.016703546,-0.027212141,-0.0028182063,-0.012898217,0.01020713,-0.019875204,-0.047691055,0.027443368,0.017143799,0.030146122,0.022774437,0.05027688,0.030999793,0.050370786,0.0049939393,0.027153661,-0.014329006,-0.019958401,0.011127883,0.016415507,0.056102622,0.026158838,0.042090442,0.013511107,0.03272733,0.0012275965,0.016726108,-0.019835494,0.024529586,0.026054418,-0.025534702,0.021648651,0.010807372,0.033539377,0.08099428,-0.0489854,0.030944405,-0.020548971,0.019433578,-0.03334357,0.023579724,-0.016438903,0.0077475132,-0.026406892,0.036194313,-0.005514523,0.027036157,0.0043704365,-0.019439662,-0.04853863,0.02422945,-0.008057281,0.023192972,-0.036517557,-0.021112846,0.013826278,0.007976649,0.015083251,0.0065698903,0.043238353,0.022812873,-0.015612783,-0.006247784,-0.054924715,-0.002617848,0.027783731,0.025318526,0.028224304,-0.031654198,0.008027691,0.012846564,0.025314044,0.02723755,0.021209689,0.02639607,0.036323454,-0.019106325,0.010497085,0.02207822,-0.0017939081,-0.030081252,0.009494232,-0.01606808,-0.049805697,-0.0221174,-0.010665818,-0.03448552,-0.022153182,0.04756957,0.066583514,-0.0047943,-0.05290773,-0.0104838,0.013112941,-0.13972218,0.012108735,-0.0003596743,-0.0033262942,-0.019537225,0.024150843,-0.0024448747,-0.022869106,-0.0011719643,0.03661655,0.03130322,-0.06259594,0.040890194,0.015825769,-0.008729836,-0.0004597105,-0.009728774,0.008396154,0.010166906,-0.013572413,-0.017704632,-0.041118298,-0.006846565,-0.021751164,-0.08007218,0.030873092,0.00703527,-0.003685456,-0.035032384,-0.020898245,-0.009723528,0.070596896,-0.0005563339,0.029646719,-0.004342538,0.009005333,0.007882185,-0.022690376,0.022662444,0.0074334866,0.020568939,0.04229516,-0.012298635,0.029832294,-0.004266827,0.017394109,-0.03190505,0.03490847,-0.014418887,0.009347544,0.004591833,0.010878136,-0.054530766,0.0355562,-0.028012939,0.009672107,0.0011594337,0.041541163,-0.009379049,0.031303268,0.019719595,-0.06135859,0.020628354,-0.02475853,0.0082888715,-0.0009721681,-0.002728557,-0.023638947,0.03571247,-0.042296115,0.0005833589,0.0010048309,0.02341714,0.034783624,0.008192852,0.042810146,-0.025604881,-0.011022053,0.0051089437,-0.08866757,-0.03152121,0.034660883,-0.03833404,-0.019090112,-0.03418885,-0.058260005,-0.024185589,-0.020132134,0.012042051,0.22157967,-0.009118677,0.07407641,0.032911517,0.046933502,0.011229875,-0.032515965,-0.0026762073,-0.0029440082,-0.033833615,0.0056136437,-0.022487612,0.012546558,0.008488031,-0.029716585,0.0062957215,-0.042662747,0.02013324,0.08593841,-0.0292489,-0.010232521,0.017675506,-0.012839232,-0.0053146463,-0.067719765,-0.06510776,-0.015077143,0.035080723,0.0028001138,0.04721308,-0.022666553,-0.043114178,0.04686448,-0.02438427,-0.0029776285,0.029518366,0.020862605,0.00036940086,-0.008105613,0.016581187,0.00319638,-0.02391482,-0.029302156,-0.033217657,0.0046679066,-0.04097308,0.026447395,0.028219346,-0.046519253,-0.03893368,-0.015110633,0.029641533,-0.0169728,-0.0023019498,0.021090908,0.016516821,-0.00965061,-0.018626353,-0.0022896708,0.054899715,0.02688915,-0.017594673,-0.022515703,0.014790652,-0.016435912,0.031448625,-0.047230147,0.022542836,-0.018757733,-0.020817334,-0.0133026475,-0.011676408,0.015134097,-0.02226035,0.046642613,0.00229944,0.0382255,0.017171355,0.038767885,-0.0030110995,-0.042387843,-0.003964208,0.00543622,-0.021199731,-0.014648042,-0.040038902,-0.01866415,0.05364685,-0.021027926,-0.032947335,-0.045353018,0.020445613,0.028026408,0.041059848,-0.02716208,-0.04114266,0.08605851,-0.0030760607,-0.002019724,0.01826642,0.056493647,-0.015300476,0.009170348,-0.02078276,-0.015672648,-0.017653218,-0.006503612,-0.033949908,-0.04468497,-0.0072881267,-0.015287227,-0.01932876,-0.012902967,-0.060731623,0.008095544,0.059750006,-0.00020269961,0.003963566,0.02330017,-0.016743712,0.0005288025,-0.023726732,0.026237674,0.0439488,-0.015721677,-0.018183915,-0.046758432,0.036007356,0.017435761,0.010879908,0.031409055,-0.0050190547,-0.049495637,0.04900357,0.084892735,0.016553476,0.0152662955,0.005697877,0.031618487,-0.04796852,0.03822706,0.0026315623,-0.052715167,-0.011783727,0.026375506,-0.0016898515,-0.009607221,0.03614876,-0.021952447,0.054018475,0.042903252,0.00189075,0.039919432,-0.034495946,0.0036851407,-0.004769584,0.0028205959,-0.006770993,0.0071863914,-0.0025796476,-0.004663082,0.025859071,0.012833199,0.043754745,0.055179473,0.015376139,-0.003919007,0.024108006,0.015549432,-0.022624305,0.0031441886,-0.026306126,0.006624184,0.00046387696,0.022479817,0.051358726,0.03815941,0.025202254,0.0056834165,-0.0355903,0.013522698,0.020885747,-0.021242172,-0.031684123,0.0060798964,-0.06028862,-0.037413307,-0.031803202,-0.021301843,-0.04488094,-0.019600507,0.10774165,-0.01631657,-0.021318477,-0.01996562,0.015696002,0.03789589,-0.01296225,-0.0005662452,0.012576805,0.015643872,0.011604103,0.0054865023,-0.009887194,-0.008623314,0.001590935,0.034048453,0.028463177,-0.029096887,0.004520561,-0.0039355154,0.0239718,0.014585437,0.027016543,-0.0070425617,-0.012918821,0.019343285,0.03631662,-0.041230377,-0.028523315,-0.031780425,0.013911316,-0.02120519,-0.07375812,-0.017793732,0.016258746,0.0027478728,0.017656218,0.03991867,-0.0068193628,-0.007980474,0.027862908,0.03723403,-0.023798116,-0.008490343,-0.005024293,-0.00783153,0.022496669,-0.017479746,-0.00025681863,-0.00063819374,-0.030081807,-0.05140999,0.036630526,0.028963601,0.01002508,-0.04509333,0.024404138,0.033142347,0.004963465,0.033848874,-0.026962457,-0.021132195,-0.0122830225,0.053498756,-0.0052219634,-0.0009066338,-0.03548695,-0.043536432,-0.007464812,0.0028695299,0.049446125,0.013412628,0.0022357064,0.0074946014,-0.07563735,0.049444124,-0.027406564,0.0024564127,0.0024523952,0.02597413,-0.045333188,-0.022166448,-0.0092705935,0.015321209,-0.0479189,-0.019696217,-0.007146723,0.0470549,0.0065668104,-0.0120135285,0.0017639083,0.061278597,-0.02557058,-0.016288772,0.020649461,0.010413099,0.016100029,-0.020931454,0.022158114,0.043045223,0.011185377,-0.03818371,0.035829976,0.026472637,0.008451763,0.0014732603,0.0067086807,-0.013130753,-0.025659515,-0.020889642,-0.043699328,-0.05695605,-0.0060713454,0.026640909,0.01935519,0.02608774,-0.03643339,0.007384622,0.028409295,-0.0033282395,-0.055141617,-0.005186269,-0.028563216,0.023917848,0.0026403284,0.040474236,-0.026615346,0.056428287,0.014614633,-0.01226513,-0.021924742,-0.007692867,-0.012894117,-0.039659243,0.039060354,-0.018734314,-0.023221165,-0.021317558,0.02288195,-0.0068715764,-0.03571778,-0.012735157,-0.03915807,0.047217812,-0.0105995415,0.036850184,0.03669569,0.038098462,-0.03433733,-0.01589591,-0.06848925,0.08166069,0.0011855587,-0.0047476306,-0.0515271,-0.02099891,0.0014272887,-0.015252433,0.009005115,-0.033643577,-0.02484306,0.012888285,-0.056086335,0.006680017,-0.075173214,0.00404412,-0.0068998667,0.024531124,0.05326163,-0.047939662,0.0082253115,-0.030502569,-0.020386958,-0.029888164,0.033758756,-0.008098827,0.003424579,-0.019461114,-0.011930481,0.004303464,0.002483129,-0.0021952377,0.006060195,0.0025798404,0.008166001,0.034371886,0.001824605,0.07655739,-0.017586688,-0.01211743,-0.014331093,-0.0267074,0.010621612,0.058374733,0.006561351,-0.008156035,-0.004848034,-0.0064258003,0.014676182,-0.013597486,-0.013670347,-0.041439015,0.024466788,-0.14961532,0.026161792,0.0011678986,-0.004966224,-0.038479757,-0.037159305,0.013925361,-0.047503155,0.015177668,-0.0037770611,0.020594204,0.03305246,0.0064330967,-0.016063638,-0.016732678,0.07321993,-0.013911973,0.0093977405,-0.003151605,0.041846372,0.0034090239,-0.0039692265,-0.011150257,0.023312157,-0.02827044,0.028623462,-0.005345401,0.0268235,-0.028612247,-0.002996124,-0.02525979,-0.0033740653,0.012332431,0.04593686,0.021818269,-0.025991812,-0.0010768364,-0.04864575,-0.01959829,-0.025518188,-0.02575884,0.030408714,-0.03381981,0.0068265884,0.022819756,0.0139274085,-0.019850226,0.007929686,-0.020473463,-0.063672364,-0.03846873,-0.025872365,-0.031539626,-0.003399929,0.027718883,-0.024803432,-0.007421367,-0.009267408,0.02724498,0.04293444,-0.01579397,0.027910562,-0.0178887,-0.0642095,-0.0037015306,0.014943331,-0.026784666,-0.01107997,0.011765242,-0.032810315,-0.018758798,-0.0080938535,-0.0059737205,-0.030659525,-0.003848905,-0.0007938272,0.040032893,-0.012793011,-0.029719453,-0.025552617,-0.0808493,-0.010760653,-0.0019813422,-0.019094972,0.029941322,-0.006084564,-0.05031489,0.04583602,-0.050491337,0.00031264796,-0.052132234,-0.03835457,0.024887942,0.0151820695,0.036611132,0.03338771,-0.026777586,0.017961454,-0.025603,-0.11142119,0.02305677,-0.020650087,0.0023558375,-0.003231132,-0.06440227,0.031610593,-0.025878515,0.030116677,0.0010386929,0.008693989,-0.023549968,-9.2758826e-05,-0.049548782,-0.015512979,-0.049475353,0.021439645,-0.013507327,0.06297898,0.0053974376,-0.032881804,0.030235942,-0.00027562914,-0.011573574,-0.023784384,0.06364341,0.033155095,0.01858046,-0.012451358,0.015904043,0.021579389,0.030363308,-0.065948315,-0.018986937,-0.049216207,0.024178522,0.05564752,-0.017031651,0.05904745,-0.06485081,0.02067013,-0.027222438,0.023185806,0.008324005,-0.03436186,-0.0009374892,-0.018633274,0.040008917,-0.025568377,-0.0076510846,-0.023304423,-0.036605567,0.017725224,0.007485143,0.0032736089,-0.009974553,-0.002134271,-0.0247475,0.037371617,-0.002469329,0.04647914,-0.020837426,-0.022719607,0.018611457,-0.050033264,-0.013747619,0.06514297,-0.019070849,-0.0071852226,0.012254939,0.044941016,-0.017714752,0.0218531,-0.031751834,0.004114844,-0.029412495,-0.0058620158,-0.009780719,-0.016560815,0.04172814,0.01027666,0.014738257,0.00018471642,0.059260864,0.023030892,0.01525323,0.047305726,-0.021817576,-0.012515145,-0.03521414,-0.04069902,0.015803665,-0.055811644,-0.025350329,-0.0017371952,0.031231575,-0.019705858,0.037055716,0.052966658,0.009437902,0.015054694,0.024132293,-0.02029719,0.010271218,-0.009012088,-0.046365228,0.0015031904,0.01269181,-0.0009543066,-0.042066842,-0.0066096066,-0.03336198,0.014961689,-0.0010194755,0.010172906,-0.04783965,-0.0093707675,0.06662261,-0.033034027,0.044113956,-0.008859534,-0.02317121,0.046733666,-0.009351927,0.007713472,-0.013097515,-0.014726681,0.02247513,-0.0015596512,0.01288654,-0.011156943,0.05030873,-0.0043139146,-0.0055925595,0.028342176,0.0076902676,-0.037753887,-0.027362289,0.044137396,-0.032987706,0.001357837,0.058110878,-0.036833245,-0.018874615,0.004994115]
210100	Accounts Payable	Accounts Payable	liability	[-0.042672396,0.0005285531,-0.011002251,0.011446652,-0.01746414,0.0037568668,-0.009826446,0.01367599,-0.026513932,0.030168356,0.02729987,0.0124483425,-0.027989307,0.030624587,-0.015383405,-0.046068408,0.014245253,-0.032014966,-0.021001263,-0.014127169,0.0033918712,0.0091407895,0.0019786246,-0.009063418,-0.00984241,-0.016012488,-0.03153071,-0.00633209,0.027636055,0.0029884463,0.022761548,0.021011341,-0.013712756,-0.036058016,0.012685372,-0.0031823677,-0.017448364,0.0045162253,-0.05955331,0.010478688,0.0052887793,-0.010672014,-0.010436258,-0.033989754,0.01556946,-0.019599237,-0.036107104,-0.0013894051,-0.021799015,0.0059918514,-0.016882896,-0.033541612,0.06267048,-0.021616345,0.014800278,0.036813334,-0.011617774,-0.024755612,-0.060140762,-0.0075858827,-0.02687548,-0.0014843135,-0.04525705,0.027822481,-0.00038055368,0.082338795,-0.0010733455,-0.014167714,-0.0076448033,0.018883953,0.0017733087,0.014192241,-0.04943659,0.015036387,-0.07951171,-0.0042872448,0.03683922,0.020053057,0.023295946,-0.051655058,0.018758968,-0.020525202,-0.0020306963,-0.011657454,-0.03625953,0.11862227,-0.0013709858,0.07398558,-0.012591603,-0.021526191,-0.0058182213,-0.009527334,0.04350714,-0.032194726,-0.020053249,-0.051127564,-0.05648603,0.011520677,0.014557227,0.03558373,0.029861655,-0.018259132,0.0077775656,0.0050943284,-0.014996681,-0.040051423,0.011324959,0.014664195,-0.011477148,-0.014687528,-0.033225246,-0.01371756,0.0290862,0.020147124,-0.0032348156,-0.0009997856,0.02520837,0.038448997,-0.02335653,0.005835046,0.0069520473,0.032563843,-0.03239638,-0.03800387,0.016972795,-0.03765095,0.043631338,0.06945306,-0.040079303,0.014761856,0.0391341,0.01557459,-0.040195525,-0.004294173,-0.023462856,-0.010862532,0.018546728,-0.00043293112,0.042726908,-0.048098363,0.03202878,0.06346547,-0.038204532,-0.039085902,0.056766935,-0.048555873,0.021546582,-0.043770086,-0.01765807,0.005443789,-0.002060207,-0.0011304792,0.038337868,0.004810816,-0.00800766,-0.0620479,-0.03008336,-0.0051485156,0.03482883,-0.007829019,0.0039000865,0.030798405,0.051848326,0.00067600806,0.00090296334,0.029469728,0.0021794124,0.025221458,-0.00866009,-0.0031804517,0.028590737,-0.0049598766,0.005254164,-0.0076020695,0.0076277684,0.024060193,0.022376433,0.026993686,0.057519257,-0.027455946,-0.028630726,0.041927233,-0.019440627,0.016523462,0.0273892,0.044072878,0.024643116,-0.010583755,0.032510947,0.0022708245,-0.007004533,-1.648471e-05,-0.022776831,0.0066364175,-0.023003768,-0.019118166,-0.0098826885,-0.031060318,-0.008317741,-0.018945595,-0.028740546,0.033484932,-0.021818563,-0.024624662,-0.007335188,0.008262287,1.9514457e-05,0.01043737,-0.03400305,-0.061480224,-0.0070424834,-0.025644539,0.0076461593,0.000892713,-0.034093603,-0.046171345,-0.010123,0.039123613,-0.010905496,0.0044609667,0.033135578,0.025437815,0.021887477,0.122460134,-0.0018254824,-0.017165603,0.034342777,0.0055023544,0.009888538,-0.032044873,-0.011204271,0.035845757,0.013149804,-0.0048764646,0.023819033,0.042199,-0.017686399,0.037378665,0.024898376,-0.01503215,-0.048197143,-0.056516413,-0.0026241688,-0.009708253,-0.021350766,0.030701004,-0.05485857,0.06920616,-0.016542966,-0.020890033,-0.0049725906,-0.00035043346,-0.020182973,0.0130581735,0.010530106,0.0033442143,-0.0019441501,0.0017183024,0.04470118,0.02553621,0.007837289,-0.0031536596,0.01374723,0.02463048,-0.03802611,0.037416857,-0.090373,0.006992584,0.019982954,0.03387726,0.014827377,-0.015213938,-0.0067221397,0.016810734,-0.028327294,0.054126382,-0.005319067,0.010393697,0.05776715,0.013690762,0.025235001,0.040918577,0.0016041831,-0.069904715,0.032313284,-0.0046339408,-0.05519372,-0.025910111,-0.004078095,-0.043732025,-0.021211922,0.053233653,0.07493348,-0.011358251,-0.057968967,-0.04172446,0.007012903,-0.14048202,-0.03515635,-0.031102069,0.02627274,-0.028622737,0.03133378,-0.042717997,0.05212739,-0.036597542,-0.0063257837,0.061140627,-0.067799725,0.01628272,0.02074137,-0.024430413,-0.037745476,-0.06819937,0.041401558,0.026283592,-0.010510781,-0.027631233,-0.010624601,0.014815995,-0.041977994,-0.012296898,0.045671366,0.04515919,0.07717488,-0.05456701,0.0015548677,0.018728897,0.034779944,-0.0016068313,0.015437861,0.012088485,0.016522031,0.018650314,0.03836925,0.014971946,-0.04708753,0.030760901,0.027622975,-0.042842533,0.031254664,-0.005066607,-0.0074443966,0.01790234,0.047808472,-0.01770566,0.029069906,-0.01237745,0.005546852,-0.025857704,-0.04369018,-0.037031226,-0.028959153,-0.011647969,0.016667023,0.0038958339,-0.010079237,-0.005542799,-0.06495782,0.00090207474,0.015078208,-0.005363703,-0.029792355,0.026212836,-0.02257136,0.049346607,-0.032595146,0.017630545,-0.010014998,0.014983241,-0.050641086,-0.04371189,0.03285867,0.032223925,0.00882902,-0.03886947,-0.06274336,-0.026743695,0.011778611,-0.04444715,0.032596048,-0.046760313,-0.0018980496,0.004426192,0.028397152,0.06672119,0.2102119,0.033473305,-0.019833341,0.046687882,0.05533414,-0.01131256,-0.0054562897,0.0142579265,-0.008215775,-0.018086933,-0.0037542263,0.0034553001,-0.012047162,0.021632073,-0.019388316,0.026268367,-0.048505247,0.00951848,0.06591187,-0.0036685918,-0.0016411883,0.004701685,0.012151089,-0.023829892,-0.03828744,-0.03695391,-0.02502201,0.02149236,-0.007946046,0.043383837,-0.029782394,-0.012096728,0.046726815,-0.019810047,-0.008111412,-0.022608655,-0.018470692,0.0034310864,0.057333894,0.03862799,-0.040195234,-0.050512217,-0.00851948,0.042143274,-0.052442327,-0.0152947735,0.026518025,0.057240352,-0.005880796,-0.03127691,-0.049604412,-0.039901033,-0.05181175,0.0059105707,-0.0019104547,-0.039162714,0.028683716,-0.024785921,-0.0297806,0.0053410395,0.014822787,-0.0075724213,-0.0013748888,0.05921896,-0.0073808585,-0.016914593,-0.025328485,-0.009126072,0.019090159,0.016972957,0.014380607,0.036821973,0.016744941,-0.029825883,0.047420256,0.0033311849,0.044106603,0.03939949,0.014979135,0.00902234,-0.02626075,-0.013257923,-0.047380626,0.036831636,0.011760512,-0.028233329,-0.019726457,0.05379237,-0.03123696,-0.013235195,-0.017668279,0.032524336,0.025843544,0.03888474,0.013894489,-0.050903007,0.012622685,-0.017607287,-0.046780623,0.017654482,0.045257375,-0.023805121,0.006325888,-0.03334933,0.020238752,0.0002626952,0.054175377,0.007931688,-0.030690072,-0.014257898,-0.051784202,0.020922605,-0.05254343,-0.009400427,0.019725824,0.0077995923,-0.00063158857,0.032032974,0.06874361,-0.0077678226,0.021296244,0.017950153,-0.004887984,-0.016897144,0.003907179,-0.0304793,-0.025995435,0.010731364,0.008316352,0.009867164,0.011280838,-0.0008227727,-0.014960071,0.0028985285,0.02148477,0.0022561303,0.015089403,-0.0071164933,-0.03321384,0.014776214,-0.059690274,0.021524884,-0.016020741,-0.012503255,0.026131736,0.008218487,-0.024986608,0.04883728,0.0041528475,0.050475802,-0.00092886685,0.0024336649,0.004964449,-0.029284183,0.02272798,-0.04735478,-0.0061523765,-0.037417356,0.06151476,-0.014334577,-0.0077084135,0.022073157,-0.037471116,0.05777754,0.010532871,0.044698775,0.03339575,0.014640188,-0.0090196375,-0.05175452,-0.018336711,-0.037612267,-0.032738075,0.0015238064,-0.00902258,0.030595327,0.0055404534,0.013979667,0.0137668615,-0.011902015,0.052195095,0.024562752,8.132131e-06,-0.04330162,0.014341222,-0.009144087,-0.043309856,0.0031080695,-0.057634145,-0.048191935,-0.02131701,0.047934122,0.0324452,-0.033207618,-0.043385215,-0.0015826625,-0.003974884,0.029743155,-0.006628283,0.0019879758,0.025088558,-0.018259985,-0.012560469,-0.032129984,-0.007235762,0.018150026,0.0330817,0.032234836,-0.032985006,0.018535603,0.0074417177,0.014515676,-0.030440612,-0.008876158,0.009675868,-0.00481035,0.04571934,0.019294772,0.012206964,-0.020381128,-0.047810387,0.0040599727,0.0015824484,0.01068296,-0.039048344,-0.03897473,-0.018384991,0.026169842,-0.02487757,0.005105019,0.00036750094,0.009371963,0.03656952,-0.01226231,-4.947295e-05,9.195225e-05,0.012017226,0.020961154,-0.01029809,-0.0063379197,0.019083375,0.020269133,0.009509366,0.015089953,0.03384009,-0.01043793,-0.042809904,-0.024736837,0.022084944,-0.0019431077,0.028175363,-0.055287957,0.044267192,-0.02297755,0.06041639,0.022258988,0.0028933273,0.009378713,-0.09792726,0.012221824,0.023658078,-0.012910159,-0.03355194,-0.0034324108,0.000787471,-0.02211007,0.02770662,-0.016890176,-0.016414158,-0.023359783,-0.021455659,-0.0038652006,0.0028402652,-0.026979227,0.008434757,-0.03534012,-0.013857869,0.016462732,0.004083699,0.00052023504,-0.059882555,-0.047345955,0.040419634,0.023888962,-0.068210624,-0.005137319,-0.013857833,-0.0008546291,-0.024784677,0.020704221,-0.00830486,0.019322751,-0.03756382,0.036728878,-0.011395148,-0.018750025,-0.02553465,0.034967083,-0.034126546,-0.018317284,-0.012033864,-0.014300137,-0.046110496,-0.005933031,-0.0031865188,0.04503544,0.010916375,-0.022074021,-0.0004793223,0.03662007,-0.0024954956,-0.062153377,0.017035438,-0.03127716,0.03745835,-0.016795201,0.059266675,0.006726615,0.021656109,2.0153513e-05,-0.028529331,-0.028255852,-0.0076292586,-0.043097842,0.00066696777,0.02854721,0.046703815,-0.05004951,0.02010956,-0.004801616,-0.048072048,-0.015679255,-0.0038716304,-0.0045985267,0.037365794,0.06507923,0.02506536,-0.0072451727,0.01559485,-0.050075952,-0.04230601,-0.025179973,0.06460779,-0.010410649,0.0103747435,-0.026663106,-0.020586006,0.02783924,0.0036584323,-0.028976044,-0.01125681,0.028303891,-0.020387452,-0.036372617,0.006796548,-0.0145377675,0.01271822,-0.016705813,0.009621369,0.025109941,-0.050577633,0.010854438,-0.039267264,-0.032176837,0.031421024,-0.0069465553,-0.0023688495,-0.03216701,0.030761732,-0.01557799,0.029218197,0.0004408541,-0.0036209226,0.033639047,-0.018262269,0.026901139,-0.032920904,0.022780625,0.014416079,0.017985933,-0.022228451,-0.015111053,-0.020039812,-0.0074789054,0.020195976,-0.014202734,0.014931986,-0.027152373,0.0007828662,0.03937779,0.014526562,0.00019713478,0.013764818,-0.010202995,-0.13666503,-0.017404782,0.007114723,-0.032287985,-0.0340536,-0.048202448,-0.02086822,0.0066913916,0.027666312,0.031376775,-0.05075876,0.020791598,0.015880384,-0.0025501149,-0.015134572,0.034841202,0.011340054,0.029340656,-0.018510336,0.008308985,-0.007903237,0.012945884,0.063721225,0.00084426516,-0.0002883061,0.011419741,0.024110429,0.045168605,-0.026031727,-0.0027877598,0.021287777,-0.032943655,0.05115901,0.027484668,0.021486346,-0.016578851,0.02222401,-0.026393414,-0.040937465,-0.037823606,-0.029349882,0.026037546,-0.012825949,-0.0140336305,0.060091447,0.044602364,-0.0029083672,-0.020110842,-0.027777955,-0.051495496,-0.0055884477,0.028278336,0.004629343,0.024677299,0.017708786,-0.019770596,-0.036631484,0.02844729,-0.0041119168,0.048961136,-0.026243472,-0.018911554,-0.026283126,-0.019263916,-0.011267528,0.03349963,-0.015556055,-0.020096352,0.005853409,-0.05814819,0.0067559835,-0.022667838,0.051437248,-0.07220312,0.019175591,-0.013897126,0.06930714,0.025882976,-0.0421986,0.010515236,-0.03149354,0.0023230815,-0.03336902,0.00026051365,0.030337855,0.008975351,-0.0017837328,0.018329106,-0.025560763,-0.030719692,-0.05909577,-0.02016421,0.034131687,0.024666853,-0.0090476815,0.052050676,0.008075961,0.0071469364,-0.0071312985,-0.028520158,0.014553425,-0.082459696,0.012321366,0.028324515,-0.05463482,-0.02329926,0.039635353,0.014387218,0.00971179,-0.01469472,0.012324248,-3.5016346e-05,-0.040183485,-0.01871477,-0.09933978,0.02949971,-0.004735575,0.04032222,-0.02716238,-0.027939752,0.016981274,0.01238565,0.0145687,-0.048695948,0.028200433,0.07024289,0.0039513735,-0.012731871,0.072754614,0.0074848356,-0.008945307,-0.023735581,-0.026766097,0.01545213,0.041763883,0.016864806,-0.025294507,0.03905639,-0.032130234,-0.048343517,0.0017959949,0.014941347,-0.014425216,-0.0085951695,0.010379186,0.024700267,-0.009369685,0.029298428,0.048280735,0.0008092075,-0.038867768,0.0010409721,0.034571495,0.010631701,0.01383907,0.001686207,-0.029690707,-0.016910054,0.026718844,0.005696004,0.019334316,-0.04141882,-0.029309055,-0.02839737,-0.027211668,0.04343655,-0.04200099,-0.0075062755,0.00806844,0.004102605,-0.021129733,0.012520166,-0.021106258,-0.0019626932,0.009993972,-0.047131993,-0.012824848,0.0303455,0.033056214,0.004209835,0.040267825,0.027833423,-0.015021213,0.014016032,0.010661095,0.05855934,0.0016224064,-0.008369967,-0.008822045,-0.038476158,-0.027854618,-0.028487759,-0.05629323,0.030281158,0.038381036,-0.015421317,0.018869182,0.033418633,-0.013819882,0.020934382,0.012895188,-0.033777606,-0.04448988,-0.021133972,-0.03105277,0.027700694,-9.661198e-05,0.015328885,-0.023731073,0.05285288,-0.0039084232,0.002491349,-0.05583604,0.027550342,-0.046553347,-0.018658808,0.02211523,0.02199914,0.007455703,0.064075805,-0.026560657,0.06414836,-0.033810124,0.010645378,-0.0021512809,0.011511439,-0.0055777957,0.026561212,0.03221883,0.0036227414,-0.013891928,-0.012040974,-0.0023978986,0.07061706,-0.03261223,-0.025173841,-0.02729283,0.0006261988,-0.021014685,-0.006387491,0.007985544,0.01394044,-0.030309564,-0.022861583]
210200	Accrued Expenses	Accrued Expenses	liability	[-0.03500368,-0.0062058377,-0.007998903,-0.010150184,-0.011638137,0.0124591235,0.03556211,0.021115294,-0.03571767,0.009507401,0.056741748,-0.0056232642,-0.009060489,0.038113452,-0.01995025,-0.020791968,0.021842657,0.010141512,-0.04976038,0.010389593,0.04779731,-0.022916649,0.02847372,-0.01930225,-0.009819399,0.032623887,-0.023360949,0.019333517,0.010751765,-0.025851343,0.0009062328,-0.041183364,0.053972818,-0.011098772,-0.05023742,-0.03094356,-0.021494042,0.01998053,-0.051150832,0.06462551,0.0044714813,0.021350518,0.0020987287,-0.02939991,0.043789443,-0.013360017,-0.028523277,-0.010839514,-0.00978794,0.019546153,-0.021774232,-0.05739057,0.054783262,-0.03569398,0.035696294,0.040647704,-0.056648694,0.027464036,-0.04072154,-0.006050873,-0.029463971,-0.014540607,-0.014466956,0.0111349365,0.027290504,0.08189623,-0.004121434,0.008123111,-0.030106654,-0.027402269,-0.027064241,0.018674826,-0.026595464,-0.015549359,-0.096439175,0.035360985,0.03577445,-0.028946163,-0.041865677,-0.013198219,0.010547483,-0.07486828,0.039978646,-0.0013113004,-0.005159203,0.040144965,-0.03969072,0.011037288,-0.017613405,-0.052814845,0.008313307,-0.014607394,0.0068629617,0.009684519,-0.014122013,-0.020383172,-0.060609274,0.047329783,0.036636673,0.008578384,0.007792654,-0.02759107,0.07095686,-0.012589306,-0.027960572,-0.058415204,0.037069317,-0.028205266,-0.031431906,-0.018180048,-0.026243297,0.07170885,0.007656861,-0.025260966,-0.0030656357,0.013787446,-0.0032923976,-0.018809598,-0.018793456,-0.005956168,0.05151585,0.026548961,0.039662495,0.0043052686,0.011803086,0.01828227,0.035083443,0.050558835,0.0099309515,0.034065057,0.022538327,0.04649305,-0.07288945,0.025501048,-0.03649832,-0.0358379,0.03845975,-0.046309944,0.009877617,-0.042231053,0.002590868,0.060134355,-0.039863124,-0.011709505,0.04169351,-0.008922822,0.0067209196,-0.0021929434,0.029927399,-0.024295378,-0.03810434,-0.02085981,-0.015248958,-0.008341415,0.011005368,-0.009826557,-0.005928726,0.01704788,0.0067528156,-0.013886641,-0.04506401,0.04580805,0.0044615883,-0.042813025,0.014696291,0.008475341,-0.005208887,0.0352946,-0.017534338,-0.00011614036,0.055918958,-0.081324376,0.016982632,-0.021500252,-0.008857507,0.024939641,0.11674645,0.0047458718,0.027387394,-0.062023964,-0.027828991,0.0010035179,0.025348023,-0.053907037,-0.009945913,0.03375284,-0.007358951,-0.018932002,0.01710779,0.030596275,-0.020236094,-0.031678855,0.03577864,-0.01733406,0.020349056,-0.044195253,-0.012647588,-0.023772405,-0.035263285,0.009847521,-0.013075237,0.029279603,-0.024971858,0.024212932,-0.014553134,-0.013929656,0.0032545151,0.0074411896,0.006641611,-0.04761809,0.0071195355,0.037810642,0.019668587,0.033999223,0.00091794156,-0.027219662,0.049834695,0.04518159,0.024076838,-0.0026848412,-0.035267703,0.016516022,0.010066509,0.05382443,0.043855812,0.017301532,0.019305352,0.010324518,-0.0013724738,-0.014428591,0.0054252017,-0.023980198,0.039951444,-0.01631587,0.055280525,0.0034790167,0.06643327,0.057864223,-0.05440559,-0.0038410008,-0.048249345,-0.030541342,-0.023453552,0.010602121,0.014615546,-0.053804155,-0.0026625188,0.020982461,-0.0152511075,0.028238524,-0.024632702,-0.038791504,0.01233852,0.017301647,-0.009429406,0.009595817,-0.039563254,-0.0054018116,0.021091077,0.031933043,-0.0059816167,0.010128061,0.019651582,0.029140359,-0.028463496,-0.01394914,-0.03002865,-0.024656413,-0.012186064,0.0024052444,-0.0025583121,-0.024377242,0.014097369,0.003825388,0.00761396,0.015703602,0.004633405,-0.0012971052,0.05838182,-0.022404734,0.04643125,0.044522244,-0.023680242,-0.04386435,0.01988893,-0.005021981,-0.029959222,-0.049474247,-0.021002486,-0.04694213,-0.020240767,-0.0015198612,0.06922451,0.01724583,-0.03767479,-0.04207115,0.021373766,-0.15219946,-0.043008912,-0.012478567,0.025707172,-0.01653729,0.003893214,0.008657908,-0.01520625,-0.03063805,0.0048687733,-0.0040826933,-0.07007168,0.0085294815,0.026287736,0.01062356,-0.0059574456,-0.023973644,0.024885532,0.020206504,-0.0054919994,-0.029600114,-0.016782627,-0.013924026,-0.022062115,-0.061091553,0.05095899,0.0056614904,0.029697021,-0.03370107,0.001980301,-0.021960467,0.024755178,-0.00015562214,0.005898266,0.015221033,0.027580386,0.030643241,0.009106746,0.026323058,0.0009747961,0.019918201,0.04625381,-0.0010021942,0.045833655,-0.015562855,0.0042629284,0.012197646,0.023259314,-0.022220133,0.014143879,-0.034526926,-0.022012929,-0.036407907,0.012357662,-0.035286933,0.007682393,-0.0012064542,0.0229697,-0.01982085,0.0149634695,-0.020216228,-0.05663283,-0.006805919,0.035878643,-0.010049315,-0.019264689,-0.034245215,-0.0042932974,0.033301596,-0.049397606,0.031890083,0.0037024617,0.023627067,0.014265195,-0.02370071,0.059724838,-0.009259583,0.0014778012,0.0010795812,-0.07290168,-0.019484043,0.027871585,-0.025015334,0.009636338,-0.05013706,-0.008289288,0.01087933,-0.018200126,0.022046736,0.22917919,-0.03407378,0.0571069,0.046438757,0.004412415,0.009226306,-0.014044477,0.014264613,0.020365776,-0.041722663,0.0037878226,-0.044273987,-0.010979915,-0.009203597,-0.01946127,0.030460153,-0.050530404,0.02728532,0.07627612,-0.047349896,-0.0077405646,-0.03362354,0.008548862,-0.023619227,-0.047550917,-0.08769297,-0.01849828,0.030082611,0.0075914036,0.05504106,0.004499631,-0.026140923,0.038172845,-0.0056781666,-0.01808721,0.01539789,-0.00033678702,-0.012883013,0.006679576,-0.010198755,-0.0045280815,-0.020165376,-0.006782653,-0.0012362405,-0.018794542,-0.031432085,0.02823954,0.019983094,-0.004422547,-0.037428495,-0.0066365427,0.023066213,-0.0013816085,0.0006701364,-0.032972805,-0.017735973,0.013226069,-0.041461878,-0.022058466,0.06346904,-0.006959062,-0.008386149,-0.013441679,0.024691287,-0.008183794,0.0015706441,-0.06798055,0.019615227,0.01762984,-0.010551848,-0.0018911912,-3.0510118e-05,-0.016340936,-0.003331593,0.04692657,-0.031429086,-0.002911586,0.024018878,0.00866989,-0.01081137,-0.020528795,-0.004269431,-0.041045766,-0.015301413,0.015503389,-0.016388614,-0.018463396,0.09256604,-0.012118621,-0.017262658,-0.021037025,0.02686378,-0.0018012078,0.041198395,-0.022692094,-0.027104545,0.06804842,-0.03736665,-0.008299697,-0.000279138,0.0025702182,-0.04267743,0.0038743832,-0.0411083,-0.035761487,-0.040164962,-0.0023964127,-0.009631382,-0.05945362,-0.029647844,-0.021150181,0.001416616,-0.041385196,-0.046400454,0.032978002,0.032541595,0.019565614,0.007456295,0.053140122,0.025812944,-0.020786328,-0.016858332,-0.030173555,0.011536024,0.015034886,-0.0077912295,-0.021205831,0.030219303,0.012360151,0.010896395,0.018840075,0.0029303716,-0.01415547,0.014538412,0.04085821,0.022668593,0.013925588,-0.011258099,-0.009546468,0.021334045,0.032625955,0.0011128056,-0.051641982,0.015778018,0.022939043,0.011484584,-0.00012091754,0.050710395,-0.025865367,0.026019521,0.04833208,0.028794443,0.035118278,-0.041505266,-0.029710151,-0.022719812,0.011833085,0.024026422,-0.0024304911,-0.008856478,0.016094448,0.007433363,-0.02189437,0.05565225,0.033026226,0.036370248,-0.020786986,-0.00806888,0.005336481,-0.0054070484,0.01808507,-0.022165176,-0.011126029,0.01939315,0.013345605,0.016853195,0.035580557,0.0122742625,0.07097683,-0.013542361,0.020276742,0.0197228,-0.0021330288,-0.02024983,-0.006177719,-0.020568503,-0.061609972,-0.028646398,-0.029476888,-0.047497276,-0.0274195,0.096518226,-0.04285122,-0.008004459,-0.0280369,-0.024552206,0.026799588,-0.0007662274,-0.018972004,-0.021106573,0.039719295,-0.0075566396,0.018057788,-0.0044540493,0.0033184013,0.0286664,0.033159,0.007292167,-0.034696903,-0.0059391377,0.014328437,0.016978864,0.008164554,0.018258255,-0.016709981,0.009707202,0.03213247,-0.013353616,-0.01162516,-0.06538419,-0.034554243,-0.0014008026,0.0047060284,-0.04914636,0.020487728,0.035116002,-0.03415274,0.022833347,0.018761132,-0.0039179013,-0.0024711061,0.009282785,0.01041412,-0.02948792,-0.020232674,-0.029483099,0.030247957,0.01253908,-0.015869962,-0.0038365352,0.010272636,-0.038915567,-0.022977574,0.030522475,0.028247401,0.02935182,-0.059070446,9.096534e-05,0.040584687,-0.0030683507,0.047167733,-0.016605942,0.017857512,0.0016484251,0.05209574,0.04013486,-0.036298614,-0.012625048,-0.022422846,-0.013034889,0.010117585,0.057900507,-0.03348008,0.011896678,-0.015853722,-0.06562083,0.02903887,-0.018492546,-0.0027882343,0.012354218,0.0030751894,-0.035068404,-0.0160559,0.014444263,0.023729054,-0.026863964,-0.043158855,0.010236702,0.071011156,0.025544677,-0.010647386,-0.036157496,0.04196586,0.018844401,-0.044030573,0.021811439,0.03178717,0.015186758,-0.014456115,-0.0044008465,0.016063776,-0.0024193735,-0.040455777,-0.00246518,0.034470506,-0.0018366557,-0.020864325,0.0375132,-0.02730539,-0.019473596,-0.019078078,-0.02244523,-0.049939625,-0.026997203,-0.026024466,0.019255525,0.03420356,-0.010213652,0.041340888,0.027929112,-0.015074293,-0.056260206,0.013170878,0.008757494,0.05305045,0.0046894406,0.030398738,-0.0034078723,0.05507961,0.01772322,-0.0020764137,-0.017064728,-0.0031385755,0.00052979216,-0.049033552,0.017424665,0.013323074,-0.031004114,-0.003336434,0.012583729,-0.012388957,-0.016578967,-0.03946182,-0.04050922,0.023948247,-0.0046587046,-0.016965086,0.013114975,0.04006247,-0.0055567734,-0.0377014,-0.028950697,0.040827066,-0.020647515,-0.0070468895,-0.05503254,-0.00091082114,-0.009536243,-0.021118592,0.029219955,-0.015538073,0.011061407,-0.018911762,-0.06431115,0.011440691,-0.06223111,0.0053621805,-0.00028856678,-0.008967499,0.031993955,-0.023185033,0.03230941,0.000106293,-0.010539981,0.0112046935,0.030290203,-0.006241901,0.022319296,-0.011880025,-0.023378573,0.0074458495,-0.013537486,0.0075473706,0.019394696,0.030743962,0.028345278,-0.0012016553,-0.019987883,0.05134447,-0.0067630485,-0.031529337,-0.045895588,-0.031316403,-0.0013006792,0.06333605,0.01712457,0.009970189,-0.012471163,0.02331272,0.062388293,0.0011786858,0.033114992,-0.042101916,0.02171027,-0.16052496,0.056988575,0.010401339,0.001085205,-0.05981237,-0.010188845,-0.009176878,-0.01189396,0.00082613836,0.0018693728,-0.0072009596,0.0054790494,0.003662582,0.0034210908,-0.03920268,0.062231,0.026283858,0.022590427,0.005991925,0.023046115,0.008643806,0.005286027,0.011590614,-0.0041491236,-0.022945985,0.0090201935,0.01101258,0.01521264,-0.017420093,0.017550347,-0.013146702,-0.019490514,0.032060426,0.015601527,0.005736973,0.021327307,0.009841976,-0.05192562,-0.024140814,0.0033343444,-0.04917994,0.030994866,-0.0070052776,-0.011535022,0.030858826,0.03260155,-0.011056887,-0.0021321166,-0.031121202,-0.06423825,-0.03241931,-0.001558343,-0.07091461,0.0035320201,0.02981722,0.011937333,-0.008091719,0.008951875,-0.0030384038,0.016226428,-0.023764875,0.0030053812,-0.044768974,-0.08546175,0.03561531,0.029632842,-0.010626103,-0.012906163,0.0027677072,-0.031706676,0.014082577,0.027441273,0.031133395,-0.033414647,-0.008156854,0.008915703,0.08015571,-0.019507512,-0.04163043,-0.030513277,-0.060116976,0.023558566,-0.011943188,-0.019002797,0.011502794,-0.02253938,-0.052552097,0.013583788,-0.020258145,0.0028152533,-0.060365476,-0.00029204186,0.04925736,0.030437775,0.02289215,0.02849836,0.0041060164,0.03371673,-0.027024716,-0.06939209,0.026145825,-0.035608318,0.01860757,-0.009575093,-0.049070783,0.025406983,-0.032147963,-0.0019499956,-0.00016058628,-0.002930351,-0.018629713,-0.03292684,-0.08086936,-0.014709815,-0.051697925,0.008400027,0.028345836,0.028498916,0.0003448729,0.002154176,0.028680012,0.010940325,-0.00451482,-0.026260402,0.048845228,0.020766508,0.05806361,-0.022079512,0.060245693,-0.00512778,0.033341452,-0.061117563,-0.045213483,-0.016433649,0.02949831,0.044878677,0.023009643,0.050095435,-0.02709447,-0.016457235,-0.017737282,0.016474212,0.026573952,-0.0064521055,-0.030234095,-0.02133996,0.0014276813,0.006427499,0.015236962,-0.028166743,-0.034236763,0.028436363,0.030580383,0.014039207,0.017984364,0.00044296213,-0.012896761,0.01454407,0.01972691,0.012847789,0.030564718,-0.046089448,0.015232773,-0.04346364,-0.04127353,0.066260144,-0.05518014,0.00012702703,-0.027808772,0.0040561836,-0.012348621,0.031672984,-0.020950695,0.022182504,0.009029224,-0.036609173,-0.018037375,-0.005887116,0.016783042,0.0056922487,0.032247547,0.027218577,0.00751126,0.026550436,0.005152165,0.03303906,0.024728274,0.033777863,-0.010837021,-0.029234529,-0.00078765384,-0.042545874,-0.037394144,0.031908643,0.02966314,0.011192432,0.015461333,0.032936383,0.01025146,0.009169467,0.02838715,-0.03826427,-0.037685648,-0.013002503,-0.014855319,-0.0123646185,0.032997888,0.02354629,-0.030847695,0.005898302,-0.035010666,0.0005997497,-0.0006554565,0.025815446,-0.06764154,-0.016765023,0.016212825,-0.0192507,0.03283462,0.020703964,-0.042920664,0.050388537,-0.0015157841,-0.010742147,0.0076769977,0.00045566924,0.022379886,0.00882753,0.006649793,0.029531093,0.01025921,0.0025164948,-0.014452692,0.041585486,0.014256086,-0.0013030887,-0.032203604,0.0141085265,-0.030771233,0.0006011382,0.043134287,-0.033862855,-0.012198842,-0.0009730151]
210300	Accrued Output VAT	Accrued Output VAT	liability	[-0.034535218,-0.007923278,-0.025319846,0.03696536,-0.008635748,0.0011321276,-0.0015539537,0.036616668,-0.019701198,0.016828418,0.005452631,0.00992788,-0.0032764287,0.028496893,-0.014329065,-0.033813138,0.017232949,0.020155488,-0.03141743,0.022934943,0.030718017,0.005786021,0.030715935,-0.0053201164,-0.013726125,0.003492869,-0.029380161,-0.006344136,0.032061636,-0.019279927,0.043259416,0.0039181667,-0.0043067043,-0.035158362,-0.054298565,-0.0008961713,-0.010110269,0.026248772,-0.040892866,0.0688544,-0.0020091287,0.030194532,0.0050201286,-0.04642593,0.05171805,-0.010726339,-0.048892334,-0.027659373,-0.04494074,0.03753576,-0.012936918,-0.025317974,0.058078032,-0.0270278,0.062364105,0.06377176,-0.012774808,0.02786994,-0.041342836,0.014151726,-0.0062841834,-0.009801589,-0.015677456,0.01056025,-0.021822182,0.04766735,-0.00088997296,0.03423262,-0.02509454,0.021926725,-0.009076799,0.054283902,-0.023297431,-0.018296601,-0.07773172,-0.023273788,0.030846188,-0.004282508,-0.023523815,-0.013670171,0.014012614,-0.06422591,0.039600383,0.0095855845,-0.024742559,0.050527804,-0.034993783,-0.013835158,-0.01330236,-0.007837347,0.00033524557,-0.047248043,0.024965663,-0.019051114,-0.019686358,-0.057496384,-0.059369616,0.059173506,0.014428904,0.030303858,0.045194823,0.022442592,0.029160146,-0.0039417753,-0.021879533,-0.07422038,0.037472315,-0.03706246,-0.04627245,-0.031012993,-0.014361861,0.040574282,0.023727708,0.0028889612,-0.02279706,0.022188155,-0.0036755588,-0.013332611,-0.035375576,0.011680719,0.04624098,0.024969783,0.048590366,-0.0114784865,0.030565444,0.0076005366,0.047368564,0.05544912,0.005968963,0.032470193,0.010773522,0.031417847,-0.09321809,0.023728756,-0.02985509,-0.035017777,0.02698406,-0.038083717,0.0007534101,-0.04783921,0.00829722,0.03893695,-0.06257911,-0.016796688,0.079057164,-0.049390253,0.030651651,-0.010870496,0.013310251,-0.014671012,0.00843744,-0.010851334,0.01988456,-0.029881226,0.029905893,-0.004512973,-0.036433283,0.023545789,-0.0036349776,-0.0023829783,-0.060442965,0.01637126,0.043493215,-0.050580807,0.019545639,0.04291874,-0.017258545,0.057794325,-0.035895437,0.0071961693,0.05422749,-0.036679577,-0.00019113376,-0.026026951,0.02517201,0.029154526,0.0960369,-0.010559782,-0.01174512,-0.03956001,0.015220572,0.026338875,0.033214826,-0.01030856,0.02370937,0.0035257032,0.021009862,0.0006289142,0.01400408,0.03975813,-0.03663638,0.01090825,0.041671913,-0.016183117,0.02130326,-0.019456163,-0.048309375,-0.003270313,-0.0318795,0.0069905175,-0.0463675,0.046555515,0.0024994647,0.024760947,-0.005808409,-0.0014625688,-0.005423145,-0.005275522,-0.00022825104,-0.02030882,-0.014031318,-0.0061529027,0.03840671,-0.0027382812,-0.019543089,-0.02037454,0.024041709,0.016976774,0.01420102,-0.02107602,0.010198812,0.033229206,0.027798818,0.05052493,0.013501418,0.0147820655,0.013326775,0.001172655,0.0045015244,-0.024458542,0.007634595,-0.046582516,-0.014152507,-0.028349187,0.06778872,0.0026660806,0.053978663,0.05491659,-0.045502163,-0.004090333,-0.033180617,-0.009490082,-0.0072952034,-0.008769507,0.04337535,-0.030772287,-0.03638929,0.018846095,-0.04659706,-0.00094382185,0.0074365065,-0.020392621,0.015448074,0.045472473,-0.00039925385,0.014500028,-0.015011434,0.01756712,0.032675486,0.0029040151,0.0038070024,0.03315131,0.024310295,0.014244212,-0.047560986,-0.011563815,-0.03667321,-0.016245514,-0.00020028994,-0.016884316,0.0071118367,-0.036381777,0.0029476858,0.021915425,0.0229004,0.054716997,-0.017482491,-0.0152755845,0.085267626,0.0212256,0.07477608,0.022903267,-0.017500915,-0.06823261,0.036350563,0.0057864264,-0.06942278,0.017302953,-0.0081205,-0.06920103,-0.03961507,-0.012477701,0.06205074,-0.013920768,-0.037002686,-0.035857033,-0.0024158861,-0.15333761,-0.05818369,-0.04009473,0.013003876,-0.008422505,0.0158586,0.0045930836,-0.0129465,-0.039719418,-0.0036017492,-0.019340893,-0.08308017,-0.006193256,0.010547571,0.00861837,-0.011027524,0.0048372177,0.01699896,0.014055503,0.0004768501,-0.015153663,-0.018783184,-0.0037908931,-0.027948301,-0.047730453,0.05954163,0.031156624,0.02040006,-0.015266076,0.005373124,-0.015188597,-0.002190956,0.004506761,-0.0030293383,0.038769726,0.008720434,0.003500893,0.009520127,0.031591713,0.023869183,0.013085586,0.040748004,-0.023925548,0.041878812,-0.029939214,0.008659581,0.011268053,0.021200998,-0.011629385,0.04578064,-0.024796251,-0.0063318657,0.017900398,-0.03592717,-0.03690509,0.00029091112,0.003056795,0.02202037,-0.03912291,-0.0018628275,-0.0060406798,-0.08066626,-0.011308425,0.007261127,0.004617962,-0.035076935,-0.0044920337,0.015357264,0.018175608,-0.031481706,0.06497891,-0.024468813,-0.00017897417,-0.0029742124,-0.046659924,0.05537332,0.0015623675,0.0060720555,-0.005291892,-0.07885475,-4.0841496e-05,0.02425184,-0.0026716136,0.01795176,-0.017870177,-0.012477044,0.0145511795,-0.024300657,0.0021656489,0.21465798,0.005580072,0.0077094124,0.014923037,-0.036794268,-0.0017559824,0.003253381,-0.016259803,0.009914484,-0.0481671,0.019139564,-0.010062632,0.0049819103,-0.0039051168,-0.06270952,0.05140087,-0.025235843,0.03947291,0.07689512,-0.06267063,-0.029200785,-0.05048183,0.019714003,0.018907035,-0.05072202,-0.07668316,0.0029412142,0.022610575,0.026170542,0.036958832,-0.017815515,-0.008186666,0.05107624,0.005014865,-0.010465621,-0.009909101,-0.00053436327,-0.039537,0.006349744,0.0065445113,-0.028235784,-0.025461186,-0.02661253,0.01670724,-0.007356254,-0.030005185,0.016569294,0.021759285,-0.0017283811,-0.047720965,0.0035072605,-0.015837109,0.019601725,-0.009719889,-0.024990242,-0.026979392,0.025041677,0.019652145,-0.012298716,0.012706845,-0.018623156,-0.023329485,-0.011960823,-0.018708216,0.011271231,-0.012837671,-0.061470058,0.02074595,0.050827153,-0.0011960912,0.010957436,0.060370598,-0.008832095,-0.0098904,0.03363174,-0.023729216,-0.032456327,0.027836375,0.00067911355,-0.002816519,-0.008969784,-0.009620775,-0.035108555,-0.00475094,0.0038635295,-0.015886813,-0.008097677,0.08022352,0.0043939394,0.0050429762,-0.00088913884,-0.024982097,-0.0015158162,0.029545061,-0.0036528136,-0.0442366,0.015581571,-0.028181167,0.016704652,0.026675446,0.022196198,-0.036570884,0.033945747,-0.02520109,0.018039031,-0.047792215,-0.015954327,-0.018242003,-0.04877792,-0.03344247,-0.03639433,0.009921966,-0.047713924,-0.027106576,0.027208202,0.023915773,0.010974183,0.021249041,0.07382746,0.021633588,-0.018267985,-0.025546666,-0.029382708,-0.011110505,0.02550859,-0.0466566,0.006403677,0.023330515,0.00946405,-0.01096161,-0.044726092,0.01812174,0.017586157,0.01445722,0.0071288683,0.0016767783,0.0048214686,0.006194783,0.019187069,0.05250212,0.009486843,0.019868823,-0.03353583,-0.021856815,0.038848937,0.0043005007,0.009305125,0.061374094,-0.042703528,0.021731114,0.026241,0.039902598,0.044826895,-0.028154524,-0.0048672697,-0.050924234,0.013037508,-0.0011608853,-0.013781338,0.009150771,0.010713859,-0.0139053175,-0.037252184,0.059064757,-0.0075906115,0.049922127,-0.035834633,0.009422243,-0.022208517,-0.012102963,0.029326031,-0.04679397,-0.013776601,0.037992213,0.0031970758,0.041226514,0.0014462422,0.0014001768,0.020756172,0.02579465,0.01531201,0.023913449,-0.005820773,-0.0297166,-0.016490106,-0.026027275,-0.023174992,-0.02561552,0.010773329,-0.016091384,-0.03586944,0.08604091,-0.0394277,0.00056312006,-0.040726088,-0.04831197,0.040740494,0.0002730113,-0.032255445,-0.041386925,0.037860487,-0.016613353,0.027614871,-0.029851794,0.023975397,0.008654627,0.018968014,-0.008213509,-0.010711835,-0.030753518,-0.01108444,-0.0051822625,-0.006010141,-0.0108611975,0.015973551,0.034116812,0.044329505,-0.020617872,0.009752585,-0.08744115,-0.038348567,-0.012335812,-0.013583944,-0.033576626,0.002597999,0.030575443,-0.046033844,-0.0029612542,0.013643883,0.00405203,0.00361745,-0.042042613,0.045329195,-0.017179154,-0.030933507,-0.011291328,0.005395385,0.01571951,-0.044478126,0.0050160387,0.020585692,0.005754325,0.021802878,0.03584289,0.01789472,0.015769372,-0.057558164,0.0052546496,0.048522465,-0.0012987576,0.03949281,-0.0048869047,0.028236412,-0.013799114,0.011792622,0.059210584,-0.005344108,0.011542762,-0.03442978,0.00287363,0.006325644,0.027541403,-0.045750488,-0.015479095,0.03032181,-0.080801874,0.011926913,-0.03587759,-0.019526625,-0.004779514,-0.026274119,-0.01792507,0.0019393764,0.014139602,0.025665782,0.008170922,0.004962379,-0.018423723,0.046943933,0.03819243,0.038507834,-0.0289524,0.0037645218,0.03907469,-0.011286147,0.033175953,0.012252302,0.010985271,-0.014442245,-0.06825527,-0.022694556,-0.010373385,-0.012003035,-0.01226898,0.026916469,-0.026694717,-0.015361735,0.046899613,-0.016982852,-0.009026455,-0.026490543,0.01902128,-0.07039906,-0.0047684987,-0.03517627,0.022249479,0.03159546,-0.0103816595,0.02239375,-0.0020246408,-0.021806234,-0.045407865,-0.014118771,0.038489647,0.041225046,-0.0042295796,0.07685716,0.016029969,0.04188111,-0.003814922,-0.00430325,-0.0110377455,-0.0038038688,-0.0025174706,-0.02952385,0.01485123,0.03772421,-0.010533332,0.011412034,-0.0067910594,0.015154942,-0.0044260183,-0.038383864,-0.061912373,0.010758812,0.017626809,-0.021672692,0.024124386,0.041160543,0.00012867423,-0.024790129,0.013748704,0.029143684,-0.013633455,-0.018495224,-0.053760055,-0.010489297,-0.004424199,0.004664309,-0.004214875,-0.0386599,0.009396183,-0.048281062,-0.077175364,0.014377654,-0.008156359,0.018089062,0.021693299,0.023634706,0.016491063,-0.03369491,0.015031014,0.015648637,-0.023661608,0.053906653,0.025858011,0.013237458,0.010191782,0.013701341,-0.02220897,0.009124688,0.0071056555,-0.027677812,0.025873108,0.0391897,0.025428062,0.004409505,-0.008192445,0.011749082,-0.027137995,-0.02279464,-0.019124636,-0.05689404,0.0045908075,0.044526,-0.006775082,0.03879409,0.00458202,-0.017569872,0.058685713,-0.024135789,0.009441052,-0.021782618,0.010277666,-0.1391383,0.010112305,0.002640955,-0.015669748,-0.054081418,-0.0024504145,-0.033169948,-0.038911477,0.014047225,-0.0055000964,-0.004181853,0.012962995,-0.00819177,0.011107608,-0.012225259,0.042222477,0.007820159,-0.00020246694,-0.009649084,-0.007399268,0.0060502263,-0.007533598,0.042532448,-0.040203236,-0.0397231,-0.0035011717,-0.02330726,0.04674399,-0.013528523,-0.01569217,0.013100443,-0.0010241071,0.035965983,0.054314133,-0.012094809,0.006054742,0.010040275,0.016409041,-0.047834672,-0.0041183974,-0.06737051,0.032732897,-0.006004629,0.0057979724,0.01695259,0.015651658,-0.011521207,0.024935754,-0.04334526,-0.013643143,0.0054149386,0.022746705,-0.03497811,-0.0028550576,0.011456912,0.01151589,-0.022084977,0.0019066912,0.018662268,0.008504603,-0.0067132222,-0.0057748607,-0.055227935,-0.05779311,0.06025461,-0.0045089615,-0.032544367,0.0024838932,0.033011127,-0.027685212,0.016770182,0.027783377,0.027154358,-0.04430872,0.00677806,-0.016970092,0.094130695,-0.017190674,-0.00080172496,-0.005691905,-0.041148856,0.012913475,-0.05344699,-0.0063246596,0.0075185588,0.02293495,-0.037820905,0.034409635,-0.06891994,0.002205246,-0.049146228,0.011000834,0.036086675,0.052053023,-0.039141227,0.0035801246,-0.011950472,0.031057423,-0.035515282,-0.032104354,0.011731798,-0.033296444,0.028518148,-0.0048732474,-0.035871815,-0.0035013836,-0.016812071,-0.032190114,0.021367505,-0.01598088,-0.028241977,-0.00867778,-0.049141776,0.02016687,-0.04969943,-0.012859548,0.061047573,-0.016159363,-0.025293956,0.022753675,0.044654842,-0.00731363,0.023677465,-0.030181743,0.0034587278,0.016959785,0.05694302,-0.0037877283,-0.0025017934,-0.008194727,0.03525693,-0.036754522,-0.037896026,-0.0014452589,0.01834715,0.061979353,0.00600476,0.06075331,-0.00010398332,-0.06870825,-0.007880427,-0.017649699,-0.0071972306,0.015209146,-0.039206367,0.010846255,0.010194538,0.0017994341,-0.022738934,-0.014344421,-0.010518812,0.037231755,0.03342056,0.012532055,0.012119656,-0.033822827,-0.003979554,0.010945592,0.0005054453,-0.02786811,0.00047194675,-0.008413444,0.0396224,-0.03301751,-0.030121846,0.024299907,-0.078569084,0.016533269,0.018995803,0.0041975905,-0.025440784,0.03136844,-0.04470146,0.013116811,-0.022598334,-0.009781982,-0.02997591,-0.012757726,0.035314824,0.014992956,0.019185562,0.015511197,-0.001139501,0.01849673,-0.019681416,0.01144036,0.035409857,0.01988778,-0.015319782,0.010656387,-0.014976021,-0.02999234,-0.025144989,0.030846803,0.044096146,0.00079292466,-0.022399098,0.04890671,-0.026509862,0.046179783,0.046805058,-0.04702334,-0.03192322,-0.027137337,-0.008786208,-0.034116853,0.024271049,0.00057784043,-0.019720932,0.018956749,-0.0019418619,-0.005853428,-0.018947532,0.033841968,-0.037064675,-0.032391593,0.005730823,-0.020791134,0.013144457,0.011049536,-0.032851174,0.054786187,-0.030512832,-0.00050166115,0.009544502,-0.00471716,0.023104645,0.020341834,0.028499115,0.025245277,-0.042673644,0.012098769,-0.013897764,0.079876274,-0.017109837,0.005142841,-0.022836475,0.024113804,-0.0065013906,-0.019707637,0.0006734944,0.0004059853,-0.0200112,-0.026024334]
210400	Withholding Tax Payable	Withholding Tax Payable	liability	[-0.048798803,0.012961309,-0.005834951,0.019457703,-0.011389357,0.010170617,0.025258062,0.038357258,-0.014794208,0.014926783,0.017533118,0.018913446,0.005188835,0.020263143,-0.05415087,-0.02614276,-0.00013183549,0.01116922,-0.026374394,0.018079413,0.034053236,-0.04080699,0.004142836,0.019896735,-0.012608549,0.0021476708,-0.047693275,0.025313584,-0.007926878,0.009056728,0.010397934,-0.016507411,-0.004868356,-0.04026737,-0.03426019,-0.040894046,-0.02279281,0.029993843,-0.03829836,0.021507317,0.012476726,0.015180005,0.0026487773,-0.003139088,0.050390992,-0.007510241,-0.044580992,-0.0061613834,-0.014488921,0.014202491,-0.006441347,-0.005734658,0.051626664,-0.055463567,0.012576595,0.024959339,-0.020414075,-0.022703683,-0.07286201,0.02848656,-0.0024487819,0.0006935981,-0.03798838,0.02537945,0.0047348565,0.060520682,-0.020956425,0.037512872,-0.014372934,-0.005176048,0.0065800026,0.031186562,-0.025226206,-0.02194082,-0.082942046,-0.008087251,0.008130454,0.014569099,0.009214216,-0.0629903,0.014441193,-0.021035617,0.020413559,-0.0034662208,-0.01708913,0.078329444,-0.013214681,0.028003076,-0.023892228,-0.021358516,0.016003108,0.0090661375,-0.015103602,-0.024164513,-0.036046136,-0.024022747,-0.030011334,0.039419066,0.0057154736,0.007369928,0.04379301,-0.015859036,0.034411605,0.021616424,-0.0033470474,-0.06683817,0.050096698,0.019495446,0.005698435,-0.040660802,-0.03166338,0.023307048,0.025892071,0.01902525,-0.016375188,0.00014754353,-0.013346937,0.00078952627,-0.015207009,-0.024395328,0.052093472,0.06544053,0.037991345,-0.02667382,-0.011030707,-0.039576605,0.047052346,0.03526945,-0.0030098213,0.02121808,0.0100773275,0.02336516,-0.046094727,0.016779892,-0.003327302,-0.018776039,0.054689057,-0.025353225,0.013251776,-0.026384028,-0.0094195325,0.050156757,-0.022308508,-0.06465546,0.0480541,-0.065526895,0.053894103,-0.017372543,0.010175893,-0.054071166,0.015753519,0.047498398,0.07513875,-0.015548844,0.022978468,-0.03417518,-0.007792798,0.026827043,-0.008970994,0.035750505,-0.0108197145,0.0070095565,0.038371384,-0.008369172,0.0029097497,0.049120955,0.009936887,0.034706667,-0.020252587,4.8218746e-05,0.03371373,-0.027917434,0.067663334,-0.011310118,0.024002459,0.04306257,0.05397846,0.016958829,-0.0120037235,-0.033067703,-0.008240652,0.051765308,0.037248496,-0.022833582,0.0031083506,0.030652765,0.024560446,-0.04402666,0.0025368284,0.014063258,-0.062292498,-0.0052598566,0.011804006,0.041871313,0.018599015,-0.022806125,-0.02191867,-0.050933093,-0.023140954,0.040313706,-0.027725378,0.03228009,-0.009090111,0.013117122,0.0138369575,-0.03111493,-0.04209662,0.0008613327,0.0047475654,-0.04101275,0.022289362,-0.024281971,0.005451843,0.024284992,-0.047297813,-0.047367994,-0.0031759213,-0.0003441891,-0.0069950214,-0.017832257,0.004274288,0.028515894,0.002139311,0.07090345,0.029223794,0.021253297,-0.010551919,0.018286478,0.03970682,-0.05599114,-0.0100254575,-0.013342304,0.008945834,-0.028981613,0.035975955,0.00933071,0.020856205,0.044895917,-0.031973317,0.02096608,0.025159258,-0.039906856,-0.0064825956,-0.0036666135,0.026631437,-0.007210895,0.020752328,0.041376103,-0.034957033,-0.0039707175,0.022353522,0.015801687,0.010148682,0.05244645,-0.0033665416,0.02274763,-0.013131989,0.009334827,0.032107614,-0.0060687037,-0.0025258963,0.029627997,0.006513842,0.017164346,-0.02421416,0.016343514,-0.03663044,-0.03224032,-0.004135994,-0.01281917,0.00126049,-0.03262706,-0.025990538,0.0027974495,0.03509208,-0.008274626,0.015286488,0.0051744855,0.06889051,0.017401177,0.033866912,0.050349243,0.0139320735,0.015684443,0.052637592,0.006535026,-0.050932135,0.019515108,0.014375401,-0.056110915,-0.04163974,0.017992575,0.049708225,0.005537532,-0.04066025,-0.014309479,-0.0035264888,-0.15584214,0.001577481,0.0012256334,-0.0072036125,-0.028632896,0.008047941,0.007144653,-0.03964695,-0.057599694,0.011441991,0.028202975,-0.07156445,0.012898891,0.022982238,0.04662445,-0.017508507,-0.033424765,0.04617038,-0.013712642,-0.012019826,0.0038739466,-0.007704567,0.050405383,-0.03149443,-0.018668292,0.035730273,0.019650325,0.028148448,-0.030694075,0.030921523,-0.03789585,0.03134891,0.007843298,-0.016085604,-0.0043831803,0.0087231165,-0.014777272,0.025209097,0.008596605,0.015392082,0.0069307005,0.0275472,-0.035522647,0.035997134,0.0024619023,0.03854557,-0.0057991357,-0.015476448,0.0008105737,0.004158524,0.0044773337,-0.031868983,-0.0023852664,-0.027694188,-0.025980962,0.0046604294,0.034809425,0.01066643,-0.023256725,-0.011293037,-0.0032190436,-0.06393731,-0.015454668,0.021661822,-0.0061030216,-0.024790531,-0.0019615828,0.027341997,0.05538165,-0.03829733,0.05694671,-0.026607977,0.028637988,-0.014265155,-0.027228372,0.004426691,-0.036481585,0.010195491,-0.026924517,-0.089685656,-0.0012243463,0.018861584,-0.07037393,0.038044263,-0.03964927,-0.011500894,0.0037413423,-0.006292412,0.027038895,0.2417145,0.040065322,0.021932254,0.015883695,-0.028346743,-0.05609237,-0.03875699,0.030243985,0.012307645,-0.03125903,-0.01850971,0.009908315,-0.00957608,0.0093145855,-0.045174766,0.062158123,-0.040148694,0.042023554,0.08680928,-0.030509721,-0.0075615062,-0.027235927,0.016378868,0.010652124,0.006485972,-0.02434229,-0.041367676,-0.016978726,0.0037820593,0.009928851,-0.0148044,-0.01581394,0.06654829,-0.06109067,0.01573045,-0.013344206,0.012887156,-0.008144611,0.005645204,-0.018357024,0.011719403,-0.02940496,-0.0123765385,0.029584322,-0.019649718,-0.01420008,-0.003783613,0.007832791,0.0046706772,-0.05757032,0.013908265,-0.03773166,-0.012840462,-0.0046115736,-0.0720241,0.0048938673,0.025384542,-0.035127714,-0.018408444,0.036080357,0.013062218,-0.013971785,-0.0058801044,-0.025255017,0.020673038,-0.03280238,-0.013628135,0.006911247,0.0553838,0.0012604893,-0.021748837,0.013895346,0.01632998,-0.018668555,0.015744545,-0.042061932,-0.017413337,0.029793339,0.006524993,0.031430215,-0.047089174,-0.03643432,-0.05892635,0.044514887,-0.0049802684,0.012146041,0.024668794,0.043097317,0.011385951,-0.020831682,-0.012034236,0.026568132,-0.005299562,0.03678525,-0.018569065,-0.034560423,-0.009449011,-0.01098149,-0.01641024,0.0035139548,-0.023520753,-0.009124436,0.027694268,-0.038277272,0.0017063445,-0.0059991917,0.033223204,0.0028345562,-0.049876664,-0.033006005,-0.0049012904,0.0041279714,-0.08405527,-0.016044458,0.03593377,0.014936906,0.033686977,0.05194168,0.08575283,0.01555611,-0.028872568,0.008120198,-0.03614616,0.0034953174,0.0021069404,-0.0022671265,0.016826065,0.00924132,0.008505445,-0.010149863,0.004503534,-0.015560073,-0.008376961,0.007631204,0.017698724,-1.5185186e-06,0.055016,-0.008470447,0.0016137154,0.017039279,-0.008218264,0.023716338,-0.047328837,-0.033057224,0.027350746,0.009776744,0.0040882626,0.051640213,-0.022755655,0.023502674,0.01503617,0.030347863,0.031674854,-0.031602707,-0.007078062,-0.051915586,0.0012815327,-0.02981144,0.01657526,-0.01231985,-0.001393342,0.02807668,-0.041320734,0.076360695,-0.0022455386,0.034364652,-0.03263459,0.01030335,-0.00881888,-0.008415596,-0.034225825,-0.053707913,-0.006163686,-0.02105641,-0.06422304,0.03500418,0.02838688,0.0036446096,0.05075673,0.014761144,0.0069064302,-0.012321852,-0.0012922828,-0.05145006,0.020976327,0.011905245,-0.04868576,-0.02534925,-0.007388128,-0.062611036,-0.027407754,0.08635938,-0.007218648,-0.021008506,-0.027345484,0.007567977,0.049801048,0.02573298,0.036275115,-0.037296757,0.016961759,-0.051823568,0.0015189357,-0.019345008,0.001048364,0.0069217137,-0.01732288,0.035119858,-0.0138007905,-0.033246513,0.014546565,0.004824907,-0.04438312,0.0166583,0.0006353198,-0.0002457917,0.010951692,0.03812566,0.028104845,-0.052840937,-0.040387746,-0.012425348,0.0047013913,-0.017257266,0.030982215,0.007282005,-0.008536337,0.019494468,-0.022394244,0.012603271,0.0069682826,-0.06653104,0.047443688,-0.03660139,-0.024128444,-0.01528138,0.0392171,0.00885924,0.0306409,-0.011912606,0.046912245,-0.0033689048,0.0071308007,0.057179987,0.004644542,0.003947819,0.028198492,-0.014960619,0.040432487,-0.02266824,0.017775582,-0.023413362,-0.0015587138,0.01114377,0.019240322,0.041637614,-0.007385011,-0.009526729,-0.025205567,-0.02590738,0.010196723,0.018949496,-0.017263912,-0.009977462,0.065692835,-0.018048733,0.033595517,-0.0118661905,-0.006894987,-0.016573066,0.012257158,-0.026835134,-0.013530292,-0.036745578,-0.000877592,-0.012224918,-0.002613648,0.014529287,0.024427362,0.00049788674,0.012704261,-0.06966479,0.036101475,0.046675533,-0.051230848,0.05170193,0.00065715215,-0.022000907,-0.002775518,-0.023685854,-0.0062328237,0.0005023938,-0.027591925,-0.0026323248,0.014262561,-0.00015433994,0.0083582625,0.05395194,-0.037444398,-0.028522264,-0.027508104,-0.040619515,-0.081697285,-0.04619366,-0.014932106,0.020370902,0.024917746,-0.0073393034,-0.0047961515,0.04779579,-0.015632773,-0.032604404,0.025418997,0.027634596,-0.0003249385,-0.008311,0.037761416,0.015518797,0.03564832,-0.039794657,-0.021535,0.0067665703,0.0076601114,-0.019294364,-0.024853555,0.026569506,0.005640158,-0.009195314,-0.021907754,-0.021628158,0.0030441785,-0.03266761,-0.0018521363,-0.04107298,0.012620409,0.06349664,0.03534036,0.008202219,0.037850153,-0.015024345,-0.055300858,-0.062080715,-0.0045388946,-0.0062035085,0.024614682,-0.060968652,-0.021873552,0.017697262,-0.025172945,-0.026969738,-0.012641455,0.036542885,-0.010278721,-0.04440472,-0.018234475,-0.048156746,0.008379687,0.025463,0.027530795,0.00145805,-0.0065043494,0.0070594684,-0.035536923,-0.009654299,0.031562526,0.011985407,0.01344104,-0.014248128,0.010893399,-0.02870961,-0.0019447459,-0.014793566,-0.017788138,0.015036026,0.016392246,0.051345676,-0.018592268,0.0272355,0.015388583,0.01398921,-0.021225937,-0.002543031,-0.0138528375,-0.02658233,0.02724839,0.0065664477,-0.0097386325,-0.008659864,-0.03253877,0.04098801,-0.021632414,0.013937648,-0.027729442,0.024676425,-0.16283795,-0.0068562785,-0.01099835,-0.022643734,-0.05585492,-0.009325593,-0.058803573,0.03815259,-0.020464042,0.02598925,-0.037893474,-0.026243085,0.0129324235,-0.006037027,-0.023809705,0.08118616,-0.03652846,0.015180275,0.01832741,0.047934283,0.018313648,0.013444904,0.012948662,-0.0067235404,0.022179227,-0.017333586,0.027177379,0.027609255,-0.014043166,-0.06117279,0.043445762,-0.04184264,0.018683067,0.06413497,0.0064253868,-0.014856943,0.037876904,-0.013600525,-0.018168516,-0.010826288,-0.055822335,0.03127284,-0.02136282,0.021304538,0.014590097,0.026805757,-0.036828004,-0.012663052,-0.044558134,-0.04327489,0.012388166,0.035313375,0.0008968978,0.016004233,-0.007390322,-0.014454858,-0.017521605,-0.020513635,0.0016671348,0.013392739,0.003320279,-0.0018231969,-0.035469826,-0.029001947,0.03141385,0.0039287833,-0.006752643,-0.006606948,-0.0011761131,-0.028311124,-0.024116242,0.011177885,0.04377816,-0.02910006,0.029910346,0.0064068288,0.06558077,-0.0059535396,-0.016826356,0.005915004,-0.061174497,0.014584469,-0.04501665,-0.0280407,0.024653256,-0.005743264,-0.022568254,0.008399811,0.012824624,-0.016455512,-0.051500537,0.013046605,0.01627107,0.032981224,-0.00704298,0.056000628,0.0025972708,-0.0065325047,-0.0108993165,-0.040024865,0.0109276585,-0.028016578,0.0092539815,-0.021093983,-0.047386214,-0.012488444,0.018063135,0.01908818,0.020946104,-0.03610299,-0.00030996857,-0.0065259486,-0.08005317,-0.01777933,-0.038760185,0.003300779,-0.012607445,0.01685883,0.024624873,0.039252706,0.018898012,-0.023279214,0.0661595,-0.028126027,-0.0034432295,0.024748523,0.016917607,-0.04256823,0.0063202693,-0.0014839253,0.0031229537,-0.0581864,-0.036872465,0.028366894,0.013831246,0.0036047949,-0.018881237,0.067465745,-0.013975834,-0.051460855,-0.010368275,0.019922797,-0.0060356874,-0.0023411678,-0.012516515,0.0047053616,0.03973599,0.041882563,0.012237597,0.0029368894,-0.009943758,0.018012054,0.022292288,-0.0031020332,-0.027579978,-0.010442902,-0.016418707,0.019830165,-0.008097863,-0.041799933,0.020531781,-0.04350964,0.0022691179,-0.043087907,-0.009205755,0.038748406,-0.059941374,0.008915169,0.003779254,0.008450415,-0.025602464,0.018830268,-0.05415128,0.029127624,0.015828183,-0.04819645,-0.018047653,0.012926354,0.059918676,0.0049730027,0.01941265,0.03910556,0.023705866,0.026945336,0.021987047,0.009859033,0.012787985,0.029881123,0.00119778,-0.020051463,-0.018253585,-0.029839013,-0.054115757,0.03561573,0.05143821,0.0021779125,-0.006501301,0.0048394855,-0.01495285,0.0064575025,0.06987759,-0.033269975,-0.039274856,-0.024849707,-0.019217037,-0.004678696,0.0044932677,0.005028135,-0.017581997,0.0010952661,-0.035278503,0.020809779,-0.02137058,0.051687725,-0.03214836,-0.039285574,0.023832181,-0.046260796,-0.0056371535,0.008073953,-0.019511223,0.0615862,-0.0348975,-0.008123408,-0.023079565,-0.020338455,-0.0031597363,0.01751255,0.01399584,-0.011723496,-0.008981132,-0.009769249,-0.005356533,0.0676324,-0.011609586,-0.04002439,-0.022444252,0.039950944,-0.027079662,0.018415798,0.055474326,0.012468193,-0.045574028,-0.0310274]
210500	Employee Reimbursement Payable	Employee Reimbursement Payable	liability	[-0.062130187,0.0321511,0.0022843273,-0.033938378,-0.024015497,-0.00043051146,0.008415981,0.038827498,0.00047187685,0.0041524507,0.007264875,0.013788348,-0.01842614,0.036309358,-0.0036822082,-0.04414892,0.013260494,-0.022545464,-0.0138299605,-0.013285416,0.021314485,-0.001242023,-0.008307597,0.0037484507,-0.037468415,-0.016543064,0.029976055,-0.009380475,0.012230128,-0.013610399,-0.012838319,0.026403446,0.013456025,-0.018379739,-0.002093124,-0.020334255,-0.0059452695,0.0025031236,-0.055475038,-0.0078052985,0.0021631205,0.005082852,0.016772475,-0.038587384,0.016394049,-0.011298897,-0.021772597,-0.017582094,-0.021557167,-0.042371582,-0.033769246,0.013074645,0.06313135,-0.010856012,-0.0031302013,0.035972796,-0.019545749,0.0029495445,-0.036897007,-0.0027938306,-0.011750111,0.014278578,-0.06100971,0.017029323,0.004389124,0.07684657,-0.020513622,0.019272434,0.0059052813,0.0066079083,-0.0026278477,0.0090175,-0.053642232,0.0040300037,-0.07087369,0.005837092,0.04870802,0.03104339,0.007813336,-0.040822994,0.025565991,-0.008632992,-0.0005760405,0.0085262535,-0.03729182,0.08082073,0.0015895208,0.007068612,-0.0028917124,-0.024463765,0.00060817937,-0.017480643,0.007778694,-0.030873967,-0.04422424,-0.03934164,-0.04341832,0.020154122,0.014164881,0.029683057,0.029334685,-0.050976798,0.0094463425,-0.008316234,-0.03218135,-0.039332718,0.04407684,0.023388634,-0.0031535598,-0.014074868,-0.025992624,0.020686788,0.04546955,0.033696245,0.0002511215,0.006589878,-0.014163937,0.0026795655,-0.0076690754,-0.008172719,-0.03925547,0.0115113985,0.02137885,-0.008368979,-0.027345918,-0.047147807,0.07471156,0.03589578,-0.03123146,0.015326758,0.030616613,0.013169052,-0.024752496,-0.018347027,-0.041766223,-0.021973971,0.032584418,-0.029953385,0.0031855144,-0.04580571,0.0531363,0.06968203,-0.058310006,-0.030759636,0.021556007,-0.009147215,0.020089,-0.026221042,0.014175901,0.0019148994,0.016146526,-0.00051463855,0.018225307,0.02865357,0.010693804,-0.03528036,-2.8559758e-05,-0.016160756,-0.0063346224,0.004460863,-0.024792328,0.04937839,0.04724799,0.013429149,0.02499111,-0.021708002,-0.009653005,-0.0037700324,-0.018133892,-0.009558037,0.024369068,-0.0011285889,0.0067944387,0.023621606,0.018980369,0.020990092,0.02501773,0.0077038207,0.011944526,-0.024746591,-0.036114957,0.046237707,0.0077829966,-0.0236829,-0.014084828,0.028637342,-0.018763693,-0.0376822,0.02286839,-0.008165247,-0.009818621,0.0033003944,-0.025565682,0.01726366,0.008680275,-0.045387678,-0.020854698,-0.04614761,0.000985517,-0.008618731,-0.03698804,0.0077172625,-0.02772271,-0.00343884,0.0018350525,0.008078482,-0.018406097,0.017385917,-0.022564162,-0.08378492,-0.019987976,-0.005347477,0.009602637,0.011339093,-0.040265225,-0.027812012,0.027611917,0.0048738006,0.06967763,-0.022946943,-0.0005111509,0.0112587465,-0.04153465,0.09770752,-0.010230833,-0.03866744,0.02805076,0.000995998,0.057969444,-0.037245367,-0.023723895,-0.006569605,0.0110744815,0.002427767,0.030874379,0.021706773,-0.020456918,0.056489997,0.02833584,-0.014173816,-0.010652557,-0.025751807,-0.0130750965,0.0005521805,0.0004538795,0.02490729,-0.024132827,0.0062999357,-0.035077862,-0.0029373458,-0.0026937262,-0.025007945,-0.028165175,-0.014462685,-0.004292648,0.04440022,-0.002782574,0.009859786,0.055263165,0.053166647,0.0036594565,-0.012409905,0.032893214,0.038114917,-0.0031417543,0.03651823,-0.038281,0.013005753,-0.008986474,-0.012826962,0.018151967,-0.039123144,0.021612104,0.018071195,0.015625248,0.0342746,0.024260093,0.035114232,0.032915514,0.015631385,-0.010566524,0.058784086,-0.006607783,-0.04980044,0.025971187,-0.016800016,-0.06793366,-0.047771454,-0.010683195,-0.013292798,-0.010028346,0.062931016,0.081417926,-0.015910715,-0.06580674,-0.025972446,0.025500786,-0.1521725,-0.0051623657,-0.015567158,0.040741853,-0.021303782,0.007373164,-0.033163875,0.02503651,-0.031845104,0.020069527,0.022663385,-0.045495603,0.042057093,0.0037783638,0.014935395,0.00024349804,-0.047323246,0.03139114,0.021154137,-0.017346734,-0.06975433,0.025347311,0.04824048,-0.05953904,-0.058182552,0.018439827,0.046438426,0.01730065,-0.032579437,0.004518031,-0.018049873,0.05955908,-0.008565932,0.038923137,0.016444638,0.029308973,0.0037480607,0.003045816,0.023182798,-0.040053032,0.017152641,0.02789104,-0.0049926857,0.017410845,-0.0036187575,-0.01511709,0.0036892255,0.04363852,-0.038164828,0.064469226,0.009552576,0.016716015,-0.014393957,-0.040931474,-0.036712818,-0.012180901,-0.010682809,0.0012430222,-0.009274922,-0.011519734,-0.043750092,-0.042307727,-0.028567387,0.004524874,-0.06263786,0.017535055,0.031007858,0.014477736,0.0585374,-0.04369476,0.0033517883,-0.053272784,0.028937466,-0.0012899666,0.022868153,0.025371067,-0.0008403937,-0.003833063,-0.021376062,-0.07004921,-0.015581758,0.026165934,-0.022441877,0.035145313,-0.047895137,0.024339367,0.014379367,0.016634088,0.036054492,0.22334065,0.013634178,-0.018059533,0.055497862,0.008531434,-0.02967416,-0.014424172,-0.009109196,-0.021396976,-0.023742283,-0.011351448,0.02267141,0.023896737,0.034232285,0.013674812,0.07211147,-0.053989206,-0.011372275,0.06584177,-0.021669464,9.645275e-06,0.0042725005,-0.012605956,0.009592283,-0.02428076,-0.014418001,-0.017139152,-0.0033345332,-0.018267654,0.075253054,-0.012949794,-0.0076840785,0.057432286,0.015394004,0.0016611274,-0.0052618296,-0.01861444,-0.009931353,0.029153867,0.01510509,-0.033403967,-0.038308628,-0.010471273,0.011807424,0.0019069719,-0.002134889,0.00014795264,0.01656916,-0.029960724,0.016078223,-0.07457433,-0.022357943,-0.0037206744,0.0140169365,-0.027928963,-0.027796814,-0.01685927,0.026181038,0.005174553,0.018256558,0.032592833,0.0073582055,-0.041507844,0.04839196,0.010786961,-0.006915249,-0.012893781,-0.0022208774,-0.0055481032,-0.011372937,0.008212021,0.033133894,0.034465257,-0.048452385,0.07518661,-0.012275313,0.025333755,0.060310043,0.013535542,0.030981911,-0.059913743,-0.013185749,-0.01028397,0.02485394,-0.0024844538,-0.007516846,-0.034341425,0.013771259,-0.01872065,0.009742802,-0.025294768,0.03526797,-0.0057965377,0.057096098,-0.010630053,-0.03288854,0.0101793045,-0.033808842,-0.02157419,-0.0037652524,0.0024162375,-0.025229374,0.01271712,-0.035486396,0.0046399888,0.01714802,0.015198925,0.002676198,-0.009672367,-0.020160418,-0.02493687,0.015828717,-0.054585323,-0.028639315,0.04173677,0.033212025,-0.011984021,0.04643422,0.053561296,-0.025274092,-0.015640436,0.02383709,-0.01368305,0.01883806,0.011119781,-0.012258436,0.026464429,0.02558604,0.006670371,0.017148564,-0.014739633,0.0031470638,0.020129135,-0.03209365,0.023811925,-0.044696443,0.009363079,-0.014244491,0.027139213,0.021187628,-0.034216847,-0.0023712076,-0.04293284,0.0034275434,0.01591974,0.004105633,-0.039184637,0.028130075,-0.011501555,0.039422464,0.013907691,0.028937994,0.011510794,-0.0055410806,0.019173553,-0.07311523,-0.012770529,-0.07903354,0.041450437,-0.042187348,0.005852296,0.030947093,-0.019866262,0.060600385,0.029284708,0.07103372,0.007934854,-0.0008545314,0.0025079565,-0.04284227,-0.028192906,-0.021028098,-0.017178463,-0.005406963,-0.017160557,0.051245086,0.022321949,0.037170198,0.008739473,-0.037785515,0.008477193,0.007877001,-0.0360647,0.01581875,0.03452778,0.005006848,-0.00085766934,-0.009804523,-0.04125821,-0.065581135,-0.03133157,0.06817057,0.022563811,-0.0042748116,-0.020497585,0.01658918,-0.012616517,0.003802777,0.015897414,-0.025376368,0.007064635,-0.03177611,0.044823684,0.014718905,-0.0033438604,0.040679827,0.0077539394,0.03687377,-0.04167284,0.03201582,-0.020877715,0.04108233,-0.017145678,0.014189284,0.017269118,0.008918101,0.032256227,0.0017244532,0.01915463,0.038822353,0.008277093,-0.0123922955,0.027700376,-0.0061515113,-0.024244064,-0.003951739,-0.009714705,0.010091237,0.001053938,0.00021129187,0.0028009908,-0.027134001,-0.022313505,-0.05737849,-0.034611497,0.02311234,0.009837905,0.04232611,-0.014201269,-0.029278494,0.027479121,-0.03154554,-0.010220401,0.038166597,0.03737025,-0.007875266,-0.07487521,-0.014770779,0.04021156,0.0057712644,0.032023747,-0.050867558,0.010734806,-0.016231576,0.03381282,0.013345931,-0.01245618,0.013786483,-0.08539304,-0.054117657,0.05506954,0.0030966653,-0.029113544,0.002109377,0.03183064,-0.01693263,0.030603128,0.0023143354,0.0012525051,-0.01476102,-0.014883703,-0.00531133,-0.017813971,-0.0059094066,0.0020110414,-0.0091435835,0.0056690024,0.03847574,0.07771999,0.0023686618,-0.048064347,-0.060449082,0.009779095,0.0058343485,-0.014762246,-0.007143302,0.011225116,-0.047882926,-0.013024422,0.034261554,0.035318304,0.036132842,-0.012207818,0.027820736,-0.00069381855,-0.023601687,-0.008576346,0.024139797,-0.04695946,-0.039386384,-0.023509448,-0.01819719,-0.026890434,-0.01230249,0.0004963623,0.03519848,0.013991167,-0.015534441,0.013163638,0.041724544,0.0016208958,-0.057597794,0.052898757,-0.02897025,0.0036969252,0.0005307028,0.022458158,-0.030632673,0.020298926,0.011278057,-0.01730217,-0.01984949,0.002144953,-0.06044196,-0.005051913,0.031860057,0.025164576,-0.03313005,-0.017698802,-0.030183576,-0.02769996,-0.02960094,-0.006203566,-0.0011051905,0.053954206,0.03733527,0.014288728,0.017013038,0.026736576,-0.06877939,-0.030404696,-0.06579482,0.0510867,-0.010411437,0.0119565595,-0.017911326,-0.026430296,0.01731734,-0.0020906797,-0.04646118,-0.0051071164,0.031213138,-0.04050605,-0.026789144,-0.008998271,-0.004152774,0.044553813,-0.010304089,0.015657019,0.028242104,-0.029266458,0.020392554,-0.02849687,-0.013980666,-0.0098037645,0.004202326,0.0241931,-0.023431893,0.022424862,-0.012857328,0.01991443,-0.013291506,-0.0063007483,0.030226361,-0.032673642,0.008867427,-0.009437771,0.033166368,0.037681065,0.02153712,-0.013644006,-0.01313914,-0.026890961,0.010108125,0.0106522655,-0.014103946,-0.01645059,-0.024491666,-0.016503252,0.048284702,0.006593518,-0.018280443,-0.00065525493,-0.023518017,-0.15121661,-0.03318247,-0.0017522073,0.006361926,-0.054616697,-0.048828755,-0.03323874,0.055541392,0.024121737,0.015720474,-0.032520577,-0.02430654,0.027311461,0.013573836,-0.043322627,0.031476617,0.015491798,0.014210817,-0.014350539,0.032389913,-0.017208716,-0.0052353484,0.021132084,-0.00021683951,0.011494939,-0.0027669256,0.025537325,0.0040215314,-0.005690168,0.035524663,-0.0044594593,-0.044232428,0.04247779,0.04208738,-0.002527862,0.010964978,0.01609482,-0.035927072,-0.044530936,-0.024120145,-0.0011118995,0.031201897,-0.012116973,-0.0012471057,0.016438846,0.041418254,0.00413,0.012759131,-0.04449157,-0.051241487,-0.004451286,0.012656394,0.012558032,0.0062313126,0.02217406,-0.017757993,-0.01525694,0.013527746,0.059068076,0.04113651,-0.028778195,0.035443,-0.04446069,-0.004489444,-0.0034531103,0.021858338,0.005647402,-0.033552304,0.0063243974,-0.033089843,0.012173092,-0.05116969,0.032548904,-0.08487255,0.017711945,0.013446718,0.042931687,0.040999733,-0.07988758,-0.0073923427,-0.058844253,-0.002879071,0.021952638,-0.00059422234,0.04542205,-0.032129988,0.013042547,-0.008307237,0.0028620102,0.01630738,-0.07705073,-0.004982448,0.036955703,-0.015522824,-0.007951017,0.037504558,-0.0357923,0.030963643,-0.033239733,-0.038227055,0.021795366,-0.050485887,-0.004789766,-0.013278951,-0.054552585,-0.0026146763,0.031427182,0.018238313,-0.0047484734,-0.037602015,0.02184756,-0.022218058,-0.058498994,-0.028460834,-0.09462307,0.05963929,0.00910907,0.04138102,-0.031336673,0.01562967,0.022519972,-0.01213181,-0.007243951,-0.03246027,0.01607907,0.021292172,0.02363148,-0.028407484,0.056494974,0.0076301335,-0.0037702073,-0.060121916,-0.039169576,0.022751618,0.007601369,0.059544247,-0.040705796,0.019627262,0.02981284,-0.07013335,0.028202392,0.0064830505,-0.04337787,-0.035117134,0.00033592078,0.017768562,-0.038800925,-0.013338496,0.04168219,0.005344799,-0.011952606,0.019262172,0.024784496,0.027930306,0.015688196,-0.009705711,-0.0054648356,-0.0092077525,0.055353645,0.005631948,0.00085685635,-0.03780808,-0.043900985,-0.031571474,-0.012102997,0.055354636,-0.025106063,0.0007142858,-0.021132853,0.019459883,-0.018970799,0.023438552,-0.016097171,-0.023861576,0.02683403,-0.0151523035,0.009485714,0.03705432,0.047146395,-0.010562449,0.027517054,0.034076516,-0.022099273,-0.01814848,0.040987514,0.033715263,0.0068099992,-0.0066383523,-0.014803704,-0.024277523,0.00961431,-0.04872561,-0.03275857,0.00935852,0.0355782,-0.013789858,0.043311805,0.06635975,-0.02886919,0.026005134,0.0076741236,-0.04203685,-0.02913398,0.001638085,-0.03917617,-0.006362182,-0.005908547,0.03949931,-0.04251411,0.0136230355,-0.005704506,0.011189484,-0.09217097,0.008461318,-0.046540976,-0.0032677054,0.06296606,0.024704004,-0.00083224836,0.03710661,0.0002896022,0.04333949,-0.020023473,-0.019691115,0.0020057615,-0.018519055,0.0041711265,-0.0184894,0.006204885,0.013738136,-0.019712403,0.022393005,-0.034290023,0.044729434,0.0062285075,-0.005317275,-0.013122142,-0.003531081,-0.034251045,-0.017215567,0.03535502,-0.009377234,-0.03207104,-0.015723215]
310100	Share Capital	Share Capital	equity	[-0.028558979,-0.0015081563,0.020616483,0.019413833,-0.001886139,0.034016684,0.04028823,0.0022761128,0.006978505,0.017554339,0.034803502,0.018534489,-0.026549146,0.00017144818,-0.0016098069,-0.06408974,0.033311825,0.012949451,-0.018492498,-0.011040394,0.027058853,0.023839006,0.04125025,-0.021244988,-0.02677113,0.014345097,-0.020363338,-0.00063430524,-0.017128283,0.057582818,-0.013194962,-0.01945306,0.01870227,-0.053296637,-0.015025928,-0.040162686,-0.0031474617,-0.05766024,-0.040067732,0.028541723,-0.042633772,-0.013327318,-0.008425206,-0.026888981,0.015105555,-0.035581052,-0.038081385,-0.00585866,-0.02515,0.011316559,0.02523369,0.0034102956,-0.009286319,-0.054413863,-0.011621296,0.019400747,-0.027422043,-0.009439793,-0.08276561,-0.0568548,-0.030813342,0.008793585,-0.061235793,0.0052980473,0.021649526,0.021698475,-0.0007229364,0.038364682,-0.0016100899,-0.019896321,-0.018914478,0.0039969524,-0.02418838,-0.043575373,-0.033231486,0.01390509,0.0064955824,-0.03480026,-0.039283447,-0.04051916,0.0025025685,-0.024200648,-0.024808524,0.025420344,-0.010119548,0.012300695,0.005629959,0.003906108,-0.04928689,-0.013909685,-0.012538369,-0.040563993,0.015119418,-0.016968906,-0.042135328,-0.030300224,-0.0056119007,0.0153122675,-0.011347113,-0.007840284,0.004589578,-0.012431672,0.03654281,-0.02683103,0.028546982,-0.029269852,0.0118508935,-0.00021494894,0.011894731,0.011291969,-0.032878242,0.056309193,0.051588368,-0.0025705246,-0.0064327996,-0.0023270063,0.015130116,-0.0045556645,0.011688065,0.014700684,-0.0029349432,-0.029192373,0.05719646,-0.035874236,0.036427673,-0.027855203,0.03163291,-0.013178434,-0.0005199542,-0.012100252,-0.024527427,0.010058562,-0.02924776,-0.007444182,-0.01187868,-0.0040135034,-0.017751798,0.0137098245,0.006329154,-0.037841015,-0.0031213788,0.052950345,0.008489339,-0.05432815,0.048947364,-0.024210978,0.010235097,0.008033537,-0.023707641,-0.014256738,0.042119987,0.0009761978,0.035416942,0.02646038,-0.0018079504,0.016710423,-0.033103183,-0.03607051,0.02616511,0.009001419,0.050788797,-0.008684726,0.036381554,0.052322447,0.017235644,0.048468288,0.02966383,0.03653386,-0.027927604,-0.0036634451,-0.03454168,-0.023798509,0.00061837374,-0.068388626,-0.033171594,-0.0042939777,0.033067867,0.00931555,-0.00412165,-0.026519401,0.0013066262,0.010382538,-0.06439162,-0.012551234,-0.02790946,-0.004580486,-0.018985664,-0.033150494,0.025792154,0.0356978,-0.025657495,-0.00473757,0.022890426,-0.044986457,0.02010205,-0.044171356,-0.026770156,-0.038829606,0.009273497,-0.008380609,-0.041908458,0.022257475,0.048088256,-0.012282421,-0.023543825,0.022532407,-0.0021262225,0.023315592,0.003831112,-0.012153439,-0.013550301,-0.024390848,0.0055957674,0.016205758,0.002870756,3.502496e-05,-0.010385119,-0.003957481,0.030189332,-0.0134594245,-2.5599733e-05,0.07114033,-0.0138476305,0.007603921,-0.035254773,-0.04145063,-0.035923354,0.030376315,0.04321817,-0.019323027,-0.027116539,-0.02971858,-0.030674752,-0.007991362,0.018272037,-0.0030170414,0.0007350326,0.041117113,0.019492676,-0.011282434,-0.0294646,0.007544581,0.030638447,-0.050833996,-0.053508077,0.04283364,-0.01450131,0.01265381,-0.014800341,-0.000233539,0.016863989,0.020044181,-0.024852708,0.019252522,-0.0014319485,0.01009988,0.023457061,0.0052524,0.03874746,0.032488637,0.021090878,0.02395233,0.013273461,0.021578219,0.011785436,0.04462642,-0.03491868,0.03170157,-0.011009602,-0.0106236935,0.0074627507,0.020010289,-0.006966737,0.014276032,-0.03197449,-0.0031484955,0.02646623,-0.010153308,0.060499147,0.051922534,0.03620048,0.13506867,0.04721227,-0.013568393,0.015465617,-0.028641766,0.02065558,-0.04876717,0.011788453,-0.066028096,-0.047639243,-0.02229117,0.041605018,0.0044852635,-0.01184304,-0.005320114,-0.004193462,-0.15073219,0.06444626,-0.013360826,0.019925188,-0.0073104477,0.015305881,-0.051964264,0.056999702,0.07881591,0.031063352,-0.003811611,-0.06915997,-0.021893607,0.056148846,0.0101712,-0.0016989985,0.025559114,0.025070284,0.019645905,-0.0023832493,-0.022811158,-0.05072295,-0.0035184121,0.0055808737,-0.038689677,0.021693096,-0.0056071016,0.046846345,-0.03353926,-0.013448744,-0.0060262647,-0.02423236,0.008993339,0.015467194,0.030220043,0.051851667,-0.026498318,0.011166653,0.005812871,-0.028168874,0.013527404,0.013069889,-0.01667291,0.0005612896,0.021663863,-0.011658167,-0.013735711,0.009000487,-0.06267271,0.029340873,-0.04692126,-0.030699736,-0.03072525,-0.04705753,-0.030047175,-0.015747873,0.039683513,0.027228031,0.013269981,0.028855637,0.0063883415,-0.004432893,0.031957276,0.011455406,-0.026749948,0.027720211,0.056422923,-0.02087056,0.027814874,-0.046420883,0.0049138567,-0.054405153,0.0089641595,-0.007403537,-0.03489241,0.04567897,-0.043875303,-0.056982268,-0.019167813,-0.059798047,0.0685332,-0.00813405,0.011991971,-0.008752334,-0.03374858,0.011571858,0.0015738948,-0.022920527,0.01276656,0.19539699,0.022458956,0.05853509,-0.0027306867,0.046494454,0.0045921616,0.01581623,0.026879363,-0.04619907,-0.014213631,-0.036432315,0.0595995,0.002564315,0.007422321,-0.000610316,0.034074765,-0.0076116542,-0.010057912,0.059632808,-0.004610746,-0.036346696,0.035714738,-0.007824196,-0.011768943,-0.038071178,-0.036651876,-0.028566388,0.046003103,-0.0020954267,0.03026885,-0.028958336,-0.00036373566,0.057133205,0.019971676,-0.006310869,-5.86187e-05,0.028813941,-0.010199328,0.022199998,0.06765738,-0.02008866,-0.054076497,-0.028983744,-0.029205374,-0.02807306,0.013984239,0.027339749,0.014137931,-0.027609322,-0.0135823665,-0.022897022,-0.03559319,-0.03498025,0.029560894,-0.011570658,0.015868355,-0.06988538,0.000362727,-0.0371709,-0.026880438,-0.022525365,-0.017701248,-0.029931042,-0.017777154,-0.017745996,0.0007503678,-0.006501425,0.019832684,-0.003475189,0.033771604,0.047125682,0.037973918,0.017790563,0.035489436,0.0026874829,0.0034046404,-0.013086884,0.0724738,0.02225064,-0.0681478,-0.032975357,-0.05464407,-0.019651234,-0.049600594,0.013668585,0.00907743,-0.026355062,0.018638013,0.032865938,-0.014082869,-0.0226121,0.010507791,0.031075142,0.041485637,-0.029188853,0.013869055,0.030401835,-0.0030302422,-0.03022278,0.041563474,0.05348695,0.003683456,-0.018811194,-0.044422526,0.034169715,-0.043005355,-0.0070230444,0.0011715106,-0.020337272,0.019559167,-0.0074107437,-0.0126187615,-0.032325324,-0.03972959,0.031263873,0.047014344,0.011456243,-0.0024978714,0.05839262,-0.0044346377,-0.002081392,-0.04282738,-0.011950448,0.022474246,0.007204498,-0.008343446,-0.010776277,-0.00093188416,-0.063872896,0.057408627,-0.019665647,-0.023308132,-0.024949407,-0.011593279,0.035532825,-0.0018310976,0.012796907,0.041928854,-0.06018895,0.0113800615,-0.027447829,0.058397517,-0.011563736,-0.065323085,0.0358266,0.025968093,-0.037287626,-0.0025193812,-0.0017622386,0.020493632,0.014824291,0.019975295,0.008075486,-0.022147547,0.043094937,-0.03419201,-0.021983901,0.036681283,0.038962193,-0.0075032916,0.01108059,0.02396421,-0.025042456,0.06980055,-0.020131432,0.040778104,-0.045583483,0.06044983,0.028028516,-0.020531937,-0.0594293,-0.025440902,-0.024455186,0.03262794,0.013153987,0.0027156996,-0.00828648,0.05786413,-0.005743939,-0.009396391,0.028707782,0.0012831247,-0.039340746,-0.07081149,-0.017304756,-0.010197101,0.020177517,0.008204005,-0.010950995,-0.015169033,0.010023976,0.06131453,-0.010716337,-0.017479585,-0.0088101365,0.015644189,0.023517676,0.048251983,0.032311875,-0.04250218,0.02201836,0.0009824053,-0.02179366,-0.033257324,-0.009488614,0.012046594,-0.00473583,0.033162832,-0.01138283,-0.018550698,-0.039299984,0.04619968,0.010334688,-0.00041322643,0.0220951,-0.0092165675,-0.072916485,-0.018301098,0.062849365,-0.01144712,0.047872115,0.005836309,-0.026076581,-0.093368635,-0.014532174,-0.028619777,0.022708073,-0.0015862274,-0.031893507,0.03453568,0.006433088,-0.0071543315,0.006495287,-0.02193077,-0.010208529,-0.02087981,0.0054385355,0.035531,-0.011272387,-0.009499631,0.04563424,0.045923453,-0.0042013833,0.047182523,0.008507289,0.020979598,-0.038501352,0.060421947,0.02205547,-0.013624862,-0.016735498,-0.0037609246,0.0429891,0.0020307393,-0.0015332514,0.044488873,-0.04523258,-0.016805587,-0.055157375,-0.051516756,-0.008004774,0.014453751,-0.003437826,-0.0015212272,-0.050655212,0.026969936,0.014557058,-0.011781815,-0.014625307,0.027642159,0.034143917,-0.004157909,-0.036310833,0.014859937,0.09210488,0.002457935,-0.004139033,0.026012937,0.0031728877,0.011301532,-0.025709644,-0.0056573586,0.018807562,0.03914016,0.010173831,0.0023774744,0.027315734,0.02833645,-0.01876874,0.0023105082,0.019564012,-0.019488363,-0.020076985,0.00585199,-0.028632317,-0.0030521879,0.0050864974,0.027941471,-0.008161707,0.02172434,-0.011857931,-0.047018874,-0.014597209,-0.003888392,-0.047109913,0.038966183,0.024736311,-0.05584197,-0.004591346,0.0014104692,0.0134805,-0.041865136,-0.05168406,0.0010594673,0.012247854,-0.025318418,0.063799545,-0.01436052,0.03407598,-0.022075554,-0.02525852,-0.026621666,-0.030083999,-0.0675094,0.00982912,-0.0016180912,-0.021844538,0.011088571,-0.008404795,-0.051788438,-0.031559903,-0.01854668,0.04469226,0.011028945,0.025363931,0.04357617,0.012426001,0.0057080067,0.02187723,0.03909686,-0.007514498,-0.016633369,0.012041503,-0.047055837,0.03936243,0.040880848,-0.009770874,0.009147324,0.00073495007,-0.05160294,-0.0064834384,-0.0065705227,-0.047638092,-0.011187267,-0.029864859,-0.038134508,0.027919363,-0.0055087684,-0.003208535,-0.041718606,-0.024114028,0.008544812,-0.0025234828,0.00016726732,0.0081232395,0.007626104,0.0009629557,0.004313021,0.0048744604,-0.000109969194,-0.015439494,-0.029317902,-0.0026324445,0.02750082,0.017341277,0.041686874,0.002794028,-0.02342815,-0.0008409435,-0.03620043,-0.053404666,-0.040466364,-0.037533507,-0.014851212,0.003345234,-0.059233975,-0.0134962285,0.011476205,0.060004577,0.0023490281,-0.025127642,-0.031893767,-0.026997365,-0.02907963,-0.13152397,-0.048869103,0.0038675312,-0.037114345,-0.062007625,-0.00690784,-0.0080195805,0.001999189,0.025800182,0.008150506,0.006553184,0.009352755,-0.0032409371,-0.025479747,0.0103140585,0.006069851,-0.000684564,-0.026932463,-0.0046711867,0.06398083,0.00047432692,0.02962356,-0.0038445585,0.0191721,0.016275514,-0.04413979,-0.01224566,-0.027004154,-0.03126127,-0.03274394,0.052488573,-0.044326957,0.06278202,0.02353373,0.026715236,0.025360119,-0.005317382,-0.005826165,0.03183798,0.013574942,0.009601788,0.018124174,-0.0086246515,-0.041898414,0.026437143,0.056626834,0.03955682,-0.017618181,-0.022713065,-0.016415669,0.012889446,-0.037335817,0.03450701,0.00975053,0.011405424,-0.030593378,-0.0398322,-0.055910826,0.02746937,0.040105656,-0.03741009,0.03599746,-0.037032727,-0.046323854,0.032470834,0.04121514,0.006041974,-0.01893503,0.017428255,-0.00085504435,-0.010392796,-0.04479295,0.023359308,-0.009710233,-0.025684208,-0.038203895,-0.0011143229,0.004626212,-0.0033535527,-0.010906447,0.010857199,1.0038963e-05,-0.016622847,0.037608147,0.01694436,0.008282642,-0.013950656,-0.032890115,-0.042201392,-0.022808338,0.0016610879,-0.04868654,0.024014225,0.0924932,-0.055472333,0.026708014,0.0022320417,0.009191347,-0.030883484,-0.018550897,0.015972443,-0.022836065,-0.008418592,-0.0444749,-0.024604954,0.007193157,0.024841115,-0.022876622,0.0074079144,-0.026591642,-0.027124953,0.00906845,0.01934164,-0.0041249967,-0.13035005,-0.004296014,0.0076206303,0.011366517,-0.0113562485,-0.0016002196,-0.01830447,0.04581796,0.03167814,-0.038809486,0.01053486,0.02705545,0.008709454,0.016079847,0.02176935,0.000749558,0.03403441,-0.02268336,0.0026007402,0.010796489,0.02740035,0.0072341035,-0.041562453,0.03387127,-0.016256878,-0.064322,-0.018513016,-0.0059192004,0.014224804,-0.0097424975,0.027219228,0.020528922,0.009364615,-0.0047439123,0.03570738,-0.02351918,0.015780976,-0.0071115694,0.02536028,0.009465977,0.011004714,0.007941934,0.0057261074,0.03190417,-0.023852704,-0.011727842,0.003755041,-0.03733779,0.011537016,-0.032243095,0.008560964,0.023950765,-0.016345719,0.021191906,0.0200467,0.02784126,0.025164364,-0.011932396,-0.010237556,0.03853725,0.025543207,-0.03868564,0.020685233,0.041979786,0.06771163,0.005264674,0.008198146,0.030645913,0.035874344,-0.022105593,-0.026691694,0.0041046664,-0.0059820013,-0.009142809,-0.043373927,-0.048456497,-0.0064002713,-0.027897466,-0.036039557,0.0325327,0.04434804,0.043241773,0.008785586,0.052492406,-0.025870774,0.103938594,-0.024104962,-0.03362374,0.018795637,-0.05603701,0.010496243,-0.0050218385,0.0070569008,0.044746753,-0.015015549,0.045772485,-0.007935536,0.0006631346,-0.017061759,0.035521876,0.004180892,0.027205613,0.0037710425,-0.014830623,0.00086587947,0.045577183,-0.040154964,0.08261466,-0.02466911,0.020414548,0.012752155,0.010330312,-0.024556434,-0.011411227,0.021276256,-0.008071323,0.018393846,-0.024826623,0.008960345,0.034971446,0.009679259,-0.003671197,-0.040787198,0.019993799,0.0012892406,-0.049285993,-0.012347234,0.03176096,-0.007302532,0.012789952]
310200	Retained Earnings	Retained Earnings	equity	[-0.07218693,0.030720519,-0.0013701802,0.017950995,-0.049157515,-0.010974155,0.007426972,0.041143306,-0.0018232032,0.009938936,0.0023742886,0.0038007786,-0.057822414,0.049561415,-0.0042977263,-0.03670375,0.021591442,0.018399328,-0.045248643,-0.0029587273,0.034173127,-0.0202385,0.018182576,0.012464743,-0.009603859,0.004626498,-0.02013306,-0.009884146,-0.0069034505,0.032971896,-0.01174479,0.044600423,-0.05534284,-0.016280178,-0.047086835,-0.03413201,-0.020400539,-0.007997519,-0.033314183,0.04480156,0.011827294,0.031061133,0.012071211,-0.034550842,0.0065798364,-0.013199005,-0.024681928,0.0033472397,-0.008487362,0.029347006,0.016033899,-0.018437417,0.06119779,-0.03459559,0.05180985,0.041812178,-0.04566034,0.027473075,-0.043456692,0.005367484,0.0011604024,0.03843314,-0.06636337,-0.00939144,0.034765176,0.03970096,0.023436956,0.041444853,-0.020570742,-0.0032567158,-0.018571878,0.01751875,-0.031077316,-0.025495537,-0.08421803,-0.00055601384,0.026058923,-0.019665813,-0.021647124,-0.03141747,-0.024065612,-0.009644866,0.034774587,0.008896306,-0.040065482,0.058523748,-0.019347835,-0.00832113,-0.019234607,-0.025546711,6.942061e-05,-0.077300854,0.0051458525,-0.04510854,-0.010949795,-0.036796562,-0.04622948,0.039229203,0.0027215644,0.00014558175,0.056348324,0.023089092,0.0002567242,-0.009832004,0.03819726,-0.027060442,0.07163631,0.023298774,-0.016597206,-0.02491499,-0.018395606,0.03469481,0.023147145,0.023112543,-0.01272443,-0.0112178335,0.0048081214,-0.014637517,0.015421339,-0.0021014297,0.031647414,0.031083632,0.044352505,0.0023472423,0.016600402,-0.02244712,0.06570534,0.010056073,-0.00095360837,-0.009851043,0.028267467,0.043653805,-0.06733798,0.0090559665,-0.04700828,-0.052252818,0.018346507,-0.0047569093,0.057455897,-0.06095342,0.014363862,0.00764089,-0.05244585,-0.012068927,0.047267023,-0.017554143,-0.017584013,0.0021202392,-0.0019374535,-0.03501497,0.0022545063,0.028704762,0.0051159696,0.00084545405,0.023238983,-0.019373465,-0.028004983,0.021198148,-0.03191858,0.03372978,-0.0177651,-0.00020670544,0.026981251,-0.0022252426,-0.0062755984,0.02311509,0.008071946,0.045756936,-0.009778429,0.015170856,0.01610989,-0.03372248,0.017958954,-0.0016332342,0.011668127,0.025668804,0.06637664,0.003807505,0.008472236,-0.05874462,-0.035536338,0.04683993,0.030440345,-0.061146412,-0.0023872186,0.029731296,0.031651177,-0.0061701215,0.043877073,0.02339663,-0.017318211,-0.005154425,-0.016799845,-0.005057481,-0.0004192335,-0.054928534,-0.0014238865,-0.018870078,-0.013738928,0.032542154,-0.05940753,0.014499384,0.02960388,0.01411037,-0.06219366,-0.0047678994,0.021883529,-0.014247181,0.002272382,-0.01076542,-0.029093744,-0.041686047,-0.010068824,-0.011692344,0.04190778,-0.0048405402,0.0031753185,0.04590737,-0.006020324,-0.01345747,-0.05043183,0.059542514,-0.0389072,0.031589307,-0.01021761,-0.046000116,0.050322235,0.022157636,0.015464329,-0.03586339,-0.014886434,-0.01115591,0.012647295,-0.029338837,0.04487991,-0.020153802,0.061296698,0.04748619,0.0032362076,0.043104626,-0.003388164,-0.04382258,-0.01157618,0.008847112,0.008756276,0.020715347,0.016449338,0.0179715,-0.03191427,0.022324016,-0.00553437,-0.0057913675,-0.0210686,0.005963289,-0.021966437,0.013476917,-0.012739942,-0.020278169,-0.002900978,-0.0044460637,0.0063698585,0.012236119,-0.015540408,0.015528154,-0.024490315,-0.007992468,-0.018171085,-0.020637782,0.0022426872,-0.0144429,0.026595835,0.0051252083,0.052246813,0.00858029,0.0018232677,0.006657482,-0.0071937055,-0.007285196,0.0141896885,-0.02553458,-0.030541526,0.019331632,0.0032793628,-0.031075291,0.036330763,-0.010729779,-0.033508796,0.0487931,-0.0075339577,-0.030121231,-0.041741513,0.037505906,0.049679466,-0.0020481655,-0.00021798298,0.00015637928,-0.0077894204,-0.14008297,0.0016603004,0.00031605028,-0.001933599,0.0029891448,-0.003194543,-0.0059194807,-0.0026124113,-0.039008927,0.010932191,-0.021210542,-0.078342825,-0.009410303,0.043717273,0.027748182,0.004907701,-0.010159029,0.013992761,0.012902632,-0.021344524,0.011225422,-0.012609176,0.010032852,0.0031176317,-0.030704163,0.006294621,0.016099693,0.014983042,-0.05976766,-0.0035044062,0.012301179,0.06709911,0.010586761,0.033048145,0.020262895,0.040191203,0.0026920568,0.010291434,0.030234491,-0.009481904,0.02682306,0.034137037,0.026623437,0.034018178,0.0072118114,0.03608746,-0.053230725,0.020645186,-0.011750391,0.027521957,-0.007149049,-0.059758328,-0.037481863,0.013268443,-0.025200965,-0.0029278898,-0.004291947,0.030165588,0.00095382414,0.01492452,-0.026988136,-0.0029033655,0.004856167,0.013884669,-0.0051643164,0.00073691545,-0.0045709396,0.014432168,0.0697816,-0.04738755,0.033556335,-0.0028057427,0.024932617,0.008394532,0.004382066,0.05527893,-0.029595707,-0.052370418,0.033411425,-0.06342982,-0.006274419,0.03670879,0.0038518647,0.024777489,-0.066280976,0.030077001,0.006182336,-0.011375148,-0.014070433,0.19568922,-0.005462397,0.022953087,0.01859057,-0.01080051,-0.032698948,0.030470094,0.0075098253,-0.028838165,-0.034969628,-0.06421302,0.009417741,-0.016571306,0.009943258,-0.022521613,0.0560285,-0.035437934,0.042273205,0.087854326,-0.00084727857,0.013453823,0.0319079,-0.009606219,-0.007886761,-0.013034019,-0.06594793,-0.021915937,-0.0029233254,0.015764885,0.04400702,-0.016653026,0.027738724,0.034456614,-0.0085256435,-0.020761684,0.024561245,-0.01430066,-0.023998605,0.05396987,0.0073466757,-0.007283813,-0.030964352,-0.048556082,0.00670148,-0.012754982,-0.011423156,0.032401927,0.01019579,-0.04395733,-0.019982718,-0.02414523,0.0031948246,0.025226153,-0.023505768,-0.020405745,-0.009300312,0.0024919072,0.00084758847,-0.00012288064,0.051488813,0.004302868,-0.012231605,-0.014514751,0.004759772,-0.04489158,0.0012545107,-0.016589899,0.028546803,0.011042947,0.034958918,0.014486613,0.045822207,0.019240098,-0.010355023,0.018382164,0.019204978,0.0028375303,0.046300553,-0.016444715,-0.010773001,-0.039415523,-0.0399441,-0.06096725,0.024125421,-0.009105481,-0.01952227,-0.041120145,0.06591635,0.02029973,-0.048717264,-0.0057760905,-0.0058686454,0.0057773585,-0.007849197,-0.009125556,-0.034917746,-0.010491267,0.0047423514,-0.0417547,0.057984237,-0.004906818,0.002003682,0.01769773,-0.05053846,0.02764671,0.02943572,-0.0071860407,-0.009434877,0.0054308022,0.0043568416,-0.00849146,0.0021324228,0.009737537,-0.027532429,0.03915715,0.012022758,0.021843236,0.05898064,0.018293887,-0.023090957,-0.013116153,-0.041465446,-0.053120725,-0.01270368,0.026528938,-0.015436679,0.025134766,-0.015528454,0.024685616,0.0286131,-0.02247898,0.005018058,0.023702439,0.012933373,0.020802924,0.00552405,0.092085116,0.013149552,0.0238966,0.07585763,0.022123953,0.015780298,-0.022290513,-0.023471827,0.004466507,0.031440776,0.010399147,0.01637152,-0.008908996,0.019263275,0.0457422,0.04429763,0.029240694,-0.029815478,0.030502137,-0.012720764,0.004356831,0.029134814,0.012961616,-0.015650162,0.007761395,-0.013209617,0.009180478,0.037661385,-0.030827219,0.046440594,-0.022227386,0.009934546,-0.005139311,-0.03255262,0.0047037834,-0.01851453,-0.021042058,-0.02595268,-0.031118091,0.0062236283,0.04946948,0.0052402285,-0.02140328,0.01136849,0.013664382,0.010852632,0.023680843,-0.051113237,0.012104266,0.027696839,-0.025719352,-0.017749738,0.022350205,-0.035186917,-0.012880256,0.092289135,0.021392576,-0.02634037,-0.03497761,-0.015521152,0.0020520415,0.0141421165,-0.0030455748,-0.08618452,-0.014525433,0.01561654,0.03568825,-0.034588482,0.007877054,0.026798265,-0.03435402,0.03433489,-0.008459405,-0.05618094,0.0026175124,0.023581654,-0.019055482,0.032926265,0.014259345,-0.00507429,-0.004644023,-0.00250157,0.005573552,-0.06934202,0.0063134884,-0.018105071,0.0072553703,-0.039318558,-0.011051621,-0.0047995117,-0.012072357,-0.0029838933,0.01283747,0.002393372,-0.00087670743,-0.007489856,0.01474828,-0.023940448,-0.0005193479,-0.019079499,-0.009292465,0.013871217,0.017956398,-0.047410876,-0.037217982,0.0045232954,0.02920068,-0.0017729163,0.010999243,0.002134353,-0.032627292,-0.0058255508,0.03324299,-0.03373566,0.04902499,0.04480446,0.023099827,0.0235332,-0.021204567,0.06558304,-0.008468934,-0.018362863,-0.0058191763,-0.0261849,-0.01160686,0.03779706,-0.045671064,-0.0175425,-0.0038949193,-0.00048129106,0.042198952,-0.04809156,0.01429818,0.020064315,-0.01458535,-0.0052678236,-0.04966531,-0.026416803,0.078488216,-0.0075609167,-0.034081627,-0.04989051,-0.014327296,0.031131836,-0.062352445,-0.024907462,0.0046617156,0.000805298,-0.06922669,0.046092138,0.0060452227,-0.00073439133,-0.020666845,-0.030356364,0.016707197,0.0034471832,-0.04964838,0.0040691462,-0.02132801,-0.01810976,0.050822645,0.049651437,-0.036193203,-0.023896426,-0.030570341,-0.004176847,-0.047696166,-0.020972187,-0.023942128,-0.0135267135,-0.015629852,-0.0700844,0.026549984,0.017435493,0.010593062,-0.064591534,0.058724236,-0.017828776,0.01696639,0.0146527765,0.07341738,0.0023597148,0.0047666845,-0.04774054,-0.05672709,-0.012787418,-0.012610975,-0.036991164,-0.06814531,0.0028050041,-0.03208041,-0.0075872424,-0.0034305665,0.006773423,0.0066831335,-0.04527356,-0.024597866,-0.0018357527,0.016060028,0.03664526,0.021807134,-0.005723009,0.026761375,-0.0209608,-0.004692048,-0.059275776,0.049451187,-0.014599078,0.025562108,-0.02421552,-0.03273938,-0.022916688,0.0032370368,-0.0152931465,0.0006768401,0.023076382,-0.029001094,-0.06618049,0.039380714,-0.06444833,-0.03010978,-0.010473928,0.036867246,0.031140419,-0.059776958,0.0021438065,-0.061481245,-0.019298956,0.004871805,0.037402086,0.034440108,0.012069503,0.0004934852,0.0020966765,-0.002291166,-0.007909065,0.00081492687,0.02939374,-0.023224207,0.0657691,-0.0010030911,0.015128708,-0.006676419,-0.024812395,0.00990034,-0.026073953,-0.049350448,-0.011239615,-0.004303642,0.02029677,-0.00356642,0.005983376,0.03044598,0.023421355,-0.024106553,0.003394555,-0.019634785,-0.0023253055,-0.15697944,0.0147023415,0.00040937788,-0.020668456,-0.05232167,-0.008722515,0.02403463,0.004699637,-0.023149988,0.030332496,0.009383839,-0.036113888,0.026836826,-0.012227082,0.01026826,-0.0007591531,-0.012657184,-0.020011447,-0.0028892155,0.047522023,0.009772433,-0.014588195,0.020809865,-0.0130092995,-0.014537262,0.01645887,0.032233525,0.061797764,-0.03363619,-0.0009263028,0.03898749,0.0023667084,0.042601652,0.0017627415,0.07545535,0.000800983,-0.050347593,-0.03613494,0.011795013,-0.027693925,0.014102464,0.025236916,-0.032139406,-0.0061593875,0.017264834,0.04189295,-0.017634014,-0.008483762,-0.043162625,-0.001518424,0.027801933,-0.023767598,0.019330755,-0.028395392,-0.011543648,-0.01980967,-0.012473199,-0.011494019,0.013794438,0.021673637,-0.04184374,0.014890119,-0.056666713,-0.07163744,0.06173286,0.0031833632,-0.06272079,-0.019251209,-0.02373899,-0.015491357,0.0018424887,0.05552123,0.035481513,-0.03718433,0.03309352,-0.041005578,0.03458899,-0.03847586,-0.00014669541,-0.02339273,-0.044831295,0.021435237,0.0012640733,0.004795176,0.06020501,0.039400954,-0.052546073,0.01931123,-0.045969754,-0.0052102003,0.0035911181,-0.00018680148,0.009963579,0.025172662,-0.011230676,0.044480868,-0.02553423,0.017081242,-0.04391468,-0.047859438,0.0456735,-0.021925986,0.009472094,-0.014254704,-0.038826562,-0.07440445,0.0047104196,-0.001051953,-0.0023366625,-0.036932588,-0.017944284,-0.042112824,-0.03793409,0.0046340507,-0.055472698,0.002617646,-0.009899447,0.041479755,0.036600668,0.043410357,0.021291096,0.027672632,0.052284922,-0.02207118,-0.009075866,0.0016237062,0.011398904,-0.024410797,0.0147598805,-0.012190335,0.020752834,-0.075044915,-0.055989597,-0.020037347,0.02598652,0.044116452,-0.03826004,0.06596866,0.000522782,-0.060103312,-0.004137294,-0.0016420573,0.0009208125,0.0009527579,-0.0035972632,-0.030068565,0.03985886,0.035840936,-0.00088919315,-0.04515254,0.024785833,0.057620734,0.021920763,0.04760852,0.015005357,0.006684922,-0.030385753,-0.0041881325,0.0219918,-0.025151165,-0.010136268,-0.044893645,0.007389047,-0.049535222,-0.012535908,0.043965425,-0.047759745,0.0010722944,-0.011318487,-0.024160238,-0.028172072,0.030592086,-0.019041594,0.036053736,2.872964e-05,-0.019340327,0.017309744,0.021069877,0.01657683,-0.016006423,-0.0059391265,0.043136176,0.028901055,0.017304575,0.0059056277,0.020266155,-0.009291711,0.045598496,0.004382151,-0.022796374,-0.026251657,-0.05394214,-0.10141605,0.036839638,0.038891025,-0.01657123,0.0259103,0.0031350506,-0.00886129,0.024464617,0.01679425,-0.037363138,-0.038599923,-0.017460836,0.002723536,-0.011463358,0.04083224,0.047213737,0.007676402,-0.008912347,-0.006044082,0.0041285474,-0.021034185,0.030047266,-0.020777458,0.0087477565,-0.010270555,-0.02217871,0.022852613,0.0025933636,-0.03095583,0.048553042,-0.009266448,0.011305311,0.008551194,-0.05275127,-0.0019846312,-0.01539939,0.04578362,-0.016611751,-0.011976188,0.06742804,-0.003764365,0.05179457,0.032583944,0.010189419,-0.0065654106,0.06416652,-0.027455615,-0.022000339,0.013355815,-0.00050568784,-0.025895813,-0.011628608]
410100	Sales Revenue	Sales Revenue	revenue	[-0.033612724,0.014562689,-0.03924981,0.02009309,-0.02731117,0.026523728,0.027954662,0.034255635,0.0006216216,-0.009203103,-0.012207867,0.0066815396,-0.023875182,0.008069903,0.00011285818,-0.057000358,0.038447663,-0.043145057,-0.012073716,0.006387276,0.04136944,0.0013423277,0.036509268,0.00034448554,0.03681566,-0.023019614,-0.023337685,0.0039744615,0.008447422,-0.012794729,-0.010510902,-0.0075243167,0.0028768734,-0.020501575,-0.048662122,-0.03563658,-0.03457078,0.016487518,-0.04992876,0.051303912,-0.030596692,0.022586748,0.017472373,-0.041415565,0.026019853,-0.00752424,-0.039896466,-0.020566028,-0.07389507,0.006204535,-0.021371512,0.0056138374,0.059224047,-0.030277459,0.025433341,0.03943704,0.015941301,0.032140236,-0.04698953,-0.00775131,-0.03586661,0.031987492,-0.048119325,0.0046764403,0.06848318,0.04431318,-0.00947261,0.04243067,-0.015849687,-0.013087478,-0.016720008,-0.008430209,0.0031613954,-0.0084527265,-0.070221074,0.008843917,-0.0019501627,-0.0064493995,-0.021048268,-0.033493046,-0.0074558463,0.0021925396,-0.0050274446,0.007832754,-0.042287294,0.07090093,-0.010661741,-0.047254052,-0.02803334,0.010285169,-0.011932036,-0.025344728,0.03242754,-0.028056022,-0.02825526,-0.0653824,-0.053120494,-0.0024027457,-0.0021481651,-0.022865942,0.03635285,0.0064192917,0.024312679,-0.05285628,0.021015052,-0.0144113805,-0.0018141229,0.022988318,0.0009977324,-0.018414538,0.0036285326,0.026586358,0.029875822,-0.00094275107,0.01134909,-0.017201504,0.010737483,-0.0020780119,0.03276301,-0.0035402416,-0.0011974016,0.040316854,0.013872618,-0.018743215,0.031455323,-0.028690908,0.052335195,0.06313321,0.0013834147,-0.0114742145,0.0093316045,0.024351375,-0.09437625,0.038492933,-0.04796147,-0.01923639,0.055522196,-0.0202931,0.03216088,-0.021281308,0.03436927,0.017051771,-0.01750103,-0.026792787,0.08322776,-0.025203267,0.024733342,0.011950265,0.012443676,-0.055567622,-0.042378023,0.017119126,0.06500444,0.009586641,-0.029330937,-0.009857997,-0.03361531,0.025746442,-0.0047996696,0.03340394,0.031990595,0.01304806,0.0059556374,0.01167497,0.014578302,0.06342283,-0.02756345,0.03544974,0.00018126037,0.04182628,0.00012018652,-0.057524834,0.020996854,-0.023414591,-0.008586779,0.027327452,0.07715823,-0.0056482344,-0.042859696,-0.030355295,-0.03175831,0.014577483,-0.032663208,-0.020176763,-0.0074816705,0.047489356,0.025397103,0.02233028,0.025105804,0.03662394,0.009509259,-0.0152019495,0.08537628,-0.006357216,0.03957007,-0.07236822,0.008698921,0.017608158,-0.014736584,-0.0009304354,-0.029292576,0.019663708,-0.007999615,0.021143781,-0.027831897,0.00086274376,-0.0005970572,0.02356896,0.009590859,-0.014982196,0.010094757,-0.02590192,0.006556883,-0.04134316,-0.0024224534,0.0045048804,0.014735187,0.0056607956,0.010619247,-0.047128506,0.021571217,0.05590983,-0.038092554,0.010133062,0.006973373,0.0012489145,-0.00026835303,-0.004222304,0.043219924,-0.007821509,0.011046092,-0.036972173,0.010648808,-0.0016200192,0.031767502,-0.008119802,0.039929107,0.020985292,-0.026248924,0.07624925,-0.024761012,-0.031153275,0.01978644,-0.0054845293,5.469147e-05,0.010296923,0.018350858,0.015330723,-0.049591612,-0.045106325,0.00053229264,-0.028126735,-0.008298271,0.027688742,-0.010907256,-0.01063436,-0.027803838,-0.010135989,0.0040823855,-0.003200271,0.013677745,0.010498421,-0.028073708,0.0400805,0.001945618,-0.010050741,-0.058902,0.030555671,0.03055745,-0.009473026,0.008905616,-0.018893197,0.009665988,0.020710714,0.00053075055,-0.007534748,-0.013775574,-0.016667167,0.0478476,-0.023573788,-0.014119262,-0.006525943,-0.016599927,-0.04733311,0.03288975,-0.0302317,-0.017206775,0.015124247,0.042854536,-0.060601864,-0.033363003,0.0018428579,0.06335348,-0.019800603,-0.024344161,-0.0153358,-0.04378877,-0.14652161,-0.006993223,-0.042464014,0.019841509,0.010792077,-0.013445314,-0.0245253,-0.042756423,-0.021993352,0.00074183044,0.024396138,-0.06514943,-0.034657832,0.008231015,-0.01289328,0.008768716,-0.023908,0.028017208,0.032802604,-0.04513635,-0.01694138,-0.03355715,0.03453183,0.008841383,-0.029734744,-0.024685942,0.01656583,0.019014813,-0.048462328,-0.03653217,0.040043883,-0.0032950463,0.009995617,0.0055984925,0.038991034,0.03732039,-0.004353266,0.0035961552,0.03561775,-0.016083037,-0.016873876,0.009161358,-0.03020699,0.008679125,-0.0018315754,0.0023218265,-0.030019788,0.012051383,-0.023039041,0.007769042,-0.024735836,-0.019112859,-0.04055843,0.02045816,-0.033239447,0.034481775,0.03497957,0.057264138,0.01849957,0.023402408,-0.014975459,-0.06782545,0.056215,0.0038108574,0.012845623,-0.017430287,0.03698921,0.05957591,0.04952003,-0.016423214,0.030348852,-0.0015811338,-0.022749517,-0.022365957,0.00046075947,0.043769576,-0.045313794,-0.048147928,0.041485284,-0.0711082,-0.03891976,0.010994595,-0.013704142,-0.014419438,-0.03609782,-0.01807397,-0.0020399953,-0.032547344,0.034314044,0.23339571,0.02334901,0.076671176,0.027961351,0.01799996,-0.01922141,0.02076179,-0.010518526,-0.049140885,-0.035922468,-0.0011368857,-0.029232524,0.018335616,0.001286669,-0.031845257,0.05464772,-0.0641674,0.04255522,0.0613422,-0.001168787,-0.04892066,-0.0715129,0.0044383374,-0.032315902,-0.02505432,-0.007280982,-0.032173563,0.0037109759,0.004670878,0.060642313,-0.028679118,-0.015814083,0.033890367,0.0011346233,0.00796711,-0.0025937092,0.067657106,-0.038682573,0.04709713,0.038333546,-0.012947472,-0.044410326,0.0031201113,-0.016295545,-0.01804442,-0.02096505,0.0396651,-0.008545678,-0.00497537,-0.026896585,-0.006547456,-0.043268286,-0.018773148,0.0031292406,0.008451794,-0.020334331,-0.009835445,0.025524313,-0.020206658,0.04408502,0.019744104,-0.0016409601,0.0044019674,0.005359913,-0.0127375,-0.048166666,-0.024020197,0.00859939,0.037143443,0.05725941,-0.011675329,0.03629291,0.031677615,-0.0044786357,-0.007451248,0.0373791,-0.032259293,-0.004084452,0.034014273,-0.0121929115,-0.0027429955,-0.018101962,-0.014039933,0.010872889,0.01620804,-0.031638253,-0.01899973,0.018923897,0.022897836,-0.004432881,0.0049229898,-0.013692361,-0.045471232,0.0065984456,-0.007556138,-0.033689562,-0.039411947,0.012262808,-0.06560277,0.0054690023,0.030734565,0.0075704693,0.029926956,0.010694848,-0.042647194,-0.0075908457,0.016090712,-0.03641352,-0.020565508,-0.00836013,-0.016044771,-0.0053810156,-0.028500259,-0.005562557,0.044491388,-0.0020688027,-0.01573894,0.019950327,0.054776624,0.044014692,0.017722998,-0.018541833,-0.01108158,2.8217908e-05,-0.014334174,-0.05582174,-0.021822287,-0.0043369653,0.00779925,0.010614384,0.010206302,-0.008256189,-0.009378024,-0.0050634183,0.03267361,0.017953599,-0.0014015798,-0.019572645,0.01682967,0.030710734,-0.029991632,0.04326395,-0.013175861,-0.056357652,0.023122715,-0.003869056,0.001491426,0.015620809,0.007996154,0.0002341079,0.06645518,0.02060831,0.05734611,-0.01760953,0.009716568,-0.047902137,-0.0057708784,-0.01449536,0.043107864,-0.0061994293,-0.012039397,0.024490695,-0.0015419121,0.09190539,0.010913428,0.021959987,-0.020848963,0.016168691,-0.019976245,-0.012701778,0.022987716,-0.042725485,-0.023204425,0.025290122,-0.017889325,-0.017385239,-0.039767507,-0.002753684,-0.042338528,-0.035835605,0.018107288,0.0058991653,-0.008448203,-0.057265148,0.026599398,0.006937194,0.0018185423,-0.012484646,0.036394227,-0.03708214,-0.0025182678,0.06609562,-0.043787826,-0.016108572,0.032718007,-0.0070804325,-0.00076801877,0.010465128,0.03347523,-0.07877876,0.013317052,0.03965026,0.02003453,-0.051192343,0.022362424,-0.0024934558,0.012388393,0.028730987,-0.030490126,0.004597545,0.004997209,-0.00028175447,0.018667141,0.023090867,0.015221184,-0.033502642,0.03815538,-0.024333345,-0.014965764,-0.05534782,-0.011502139,-0.020858979,0.023727957,-0.03116706,-0.02143835,-0.011741966,0.029727796,0.03358376,-0.015563059,0.03604572,0.004040344,-0.023293879,0.056476336,-0.029040124,0.0015866283,0.006967171,-0.011758615,0.016063519,-0.00085661054,-0.0114233075,-0.012851543,-0.025320735,0.069223605,0.03274719,-0.04741968,-0.0020260948,-0.07588146,0.016799165,0.053372916,0.023424821,-0.010418374,-0.039009355,0.027128762,0.010583774,-0.07029997,0.042243954,0.021807613,0.009022959,-0.04249703,0.031012526,0.005196182,0.018986208,-0.0034026983,0.0022963637,0.03502253,0.007769075,0.0820779,-0.05465273,0.0040543494,0.011539082,0.0137975635,0.007010479,-0.0405265,-0.015749754,0.058901187,-0.013777083,-0.025461948,0.03445853,-0.00011152426,0.009203565,-0.023494039,-0.029231433,0.0044383435,0.036180366,0.01018337,0.009148128,0.0011820083,0.019693928,0.008384842,-0.022132274,-0.017371466,0.004845574,-0.03456508,0.056164194,0.034304377,-0.021465085,0.01568761,0.014696048,-0.0046721105,-0.008535512,-0.0147554055,0.011007617,-0.019440442,-0.010430551,0.0036398722,-0.0010949551,-0.01027482,-0.049363248,0.00630043,0.016978899,-0.016354246,0.011162928,0.02051831,0.02055436,-0.004479533,0.029259311,0.059081182,-0.011612896,0.0005818985,-0.013140159,0.03161132,-0.02329573,-0.011262134,-0.0349766,-0.04278654,0.035961792,0.030918697,0.006877777,0.005442867,0.0025963322,0.003642702,-0.013504801,-0.029772893,-0.01800383,0.0011360431,-0.031406198,0.045861054,0.0013877611,0.048274405,0.02511533,-0.00071197894,-0.03257622,0.081569165,-0.0065452093,0.025744325,0.0015391248,-0.034150783,-0.023413263,0.01588161,-0.024683272,-0.027291747,0.043840386,-0.018834028,-0.044993464,0.026043875,-0.036099218,0.053123534,-0.03178337,0.019548902,0.02824181,-0.05011762,0.030378282,-0.034670077,-0.010780406,-0.003375962,0.023073273,0.007310779,0.020540465,0.04258648,0.007417452,0.0019562417,0.020811137,-0.028052412,0.0032013056,-0.009168076,0.035455287,-0.030756611,0.014491115,-0.024977291,-0.023483275,0.01661919,-0.039768998,-0.08600785,-0.030521883,-0.035732735,-0.028608613,0.0058011822,0.0022303944,0.027141808,0.04009693,-0.03141856,-0.02169196,-0.033429,0.027146695,-0.15251069,0.011693634,0.0016419087,-0.009629414,-0.025685221,-0.032613486,0.019185483,-0.036923427,-0.013901829,0.019996528,-0.0006285425,0.025898583,-0.011546036,-0.029770551,-0.015142107,0.0321832,-0.014066214,0.003677546,0.002155952,0.012516317,-0.013030794,-0.010695409,0.06739057,0.0029383455,0.020657202,-0.004297548,0.05192704,0.047566883,-0.022963354,0.00074145367,0.05398634,-0.0048540696,0.013105759,0.030054424,-0.005645167,0.0017048989,-0.029011488,-0.02267195,0.02391043,0.017000923,0.007295536,0.012323572,-0.015012937,-0.024998076,0.08945005,0.049904495,-0.016892297,0.0034183497,-0.02236717,-0.043867815,0.027585492,0.010961877,0.03038241,0.01830586,-0.037154462,-0.031792164,-0.045430582,0.013540101,-0.0035755152,0.017554162,-0.044590212,0.018067352,-0.027323956,-0.078370474,0.060366567,0.0043402016,-0.04821699,0.020996723,-0.010251713,-0.01628595,-0.0036063457,0.022347657,0.03398662,-0.054577723,0.010037147,-0.032043017,0.008947284,-0.0031006802,-0.02499176,-0.011463157,0.017792514,-0.007643778,-0.0054100617,0.024481509,0.0035725604,0.060684863,-0.02502715,-0.03542124,-0.06497093,-0.021985816,-0.01402362,-0.038943756,-0.045511987,0.00015394065,-0.03653829,0.031390965,-0.066542245,0.013625539,-0.0019372867,-0.008770688,0.052484937,-0.033653416,0.0080111595,0.020513928,-0.048006423,-0.05317435,0.0125924675,-0.012493871,0.00871788,-0.007508128,-0.015205936,-0.01835361,-0.0075952625,-0.018140474,-0.054972038,-0.0039970535,-0.040864136,0.026496455,0.0058260174,0.012246645,0.037514556,-0.0040537585,0.039166592,-0.020231657,0.0011787155,0.03976342,0.02307782,-0.008345772,-0.009972803,0.03993483,0.012120507,-0.04791835,0.0039393976,0.016801557,0.026571358,0.03666037,0.008232201,0.05194142,-0.016783746,-0.014292224,0.019506996,-0.025742257,0.0019403793,-0.016899845,-0.008327685,0.028747654,0.058919776,0.0041164258,0.008613563,-0.05316291,-0.019695302,-0.0075984,0.014743628,0.02635094,-0.022581803,-0.0027347154,0.007882831,-0.03442779,0.004629702,-0.025762025,-0.038462568,-0.03513953,0.0052052187,-0.046631433,-0.021627817,0.048052747,-0.0036961962,0.01906663,0.03346497,-0.038575593,-0.034633294,0.01819501,0.0041473866,-0.007942985,0.0023996627,-0.012385774,-0.012028298,0.013359777,0.060144506,0.0018470382,-0.004793225,0.036217224,0.0029468543,-0.017277677,-0.0029017297,0.04066808,-0.025671277,-0.019658292,0.020182988,-0.03088033,0.012304112,-0.040317193,-0.037082683,0.034773752,0.012906621,0.040662907,0.022870276,0.024434509,-0.04591132,0.03565136,0.009497861,-0.03953033,-0.034951355,-0.021766663,-0.030212587,-0.010765593,0.022054112,0.01961718,-0.049533363,0.029722134,-0.0077471216,-0.018622268,-0.040587742,0.04785247,0.011024967,0.012602725,0.016481068,-0.005337687,0.010840235,-0.02358267,-0.0455415,-0.009891393,0.012124182,0.03149198,0.047686923,-0.07628394,0.009264941,0.0029981122,-0.0022501003,-0.012252906,0.023896394,-0.0092440555,-0.007808999,0.043029964,-0.0043935175,-0.0029062135,-0.006574936,0.034147006,-0.0030826395,0.023148378,0.059043244,-0.013966649,-0.042316183,-0.024359057]
410200	Service Revenue	Service Revenue	revenue	[-0.060952872,0.04171913,-0.020607727,-0.0070623015,-0.008761602,0.015985407,0.021384923,0.035198253,0.014764114,0.0030161005,0.031126548,-0.0025456867,-0.017196057,-0.012259086,0.015815347,-0.01446237,0.03564268,-0.013568134,0.020638976,-0.009319349,0.044773616,0.018499374,0.0075641964,0.037552577,0.045864478,-0.010103373,-0.019650847,-0.007725366,0.017714469,0.034740187,0.008210039,-0.037334464,-0.015262849,-0.029973801,-0.057155296,-0.06858276,-0.057452995,-0.0017446118,-0.04907713,0.03600969,-0.046958312,0.03971103,-0.011202035,-0.050675403,0.049806006,-0.019543173,-0.03695513,-0.022146551,-0.085123636,0.046752457,0.00043902887,0.029637625,0.07152309,-0.03130255,-0.024155809,0.027972888,0.0071464777,0.026589088,-0.043060265,0.01547331,-0.014213019,0.038351163,-0.03194129,-0.017937176,0.061095614,0.046176147,-0.017871043,0.04257379,-0.013240616,-0.014987355,-0.009397584,-0.0037582128,-0.045417987,-0.0150593985,-0.082073845,0.023649663,0.0037746415,0.020877395,-0.024919173,-0.030184783,-0.024925992,-0.019965721,0.0034422793,0.012514074,-0.055753075,0.07308361,-0.004365587,-0.042306643,-0.004460717,0.0067289225,-0.031151542,-0.033973977,0.018125307,-0.028607387,-0.056718312,-0.03168542,-0.04929496,0.02516837,0.02448152,0.0015655181,0.07101669,-0.0054789945,0.01163977,-0.056273516,0.024180155,-0.04133844,0.029176706,0.010735384,-0.03234644,-0.018838374,-0.01840767,0.044677056,0.0033626978,0.027215209,0.0042786202,-0.028915938,0.015859367,-0.024346573,0.012535483,-0.010276993,0.027301198,0.029350363,0.03668848,0.005881621,0.019925436,0.0022122243,0.015303198,0.064275235,0.000735449,-0.0036995234,0.009031443,0.04727023,-0.03834655,0.04974686,-0.030131873,-0.00970562,0.040803526,-0.033376094,0.013286013,-0.007969397,0.042788327,0.04627577,-0.035893917,-0.049678534,0.06156554,-0.03630983,0.02809842,0.045259003,-0.03669842,-0.035628162,-0.0088600125,-0.0019122567,0.0351204,-0.029818412,-0.0057041086,-0.0014266414,-0.050375722,-0.0010518285,-0.0013157496,-0.0017760749,0.02568508,0.023312358,-0.010467043,-0.012983739,0.009136053,0.009449766,0.009751504,0.01202757,-0.009223152,0.033589885,0.0020695606,-0.048490565,-0.009207792,-0.00514088,0.013218479,0.025492968,0.069671094,0.004687383,-0.015022691,-0.05977007,-0.052167,0.030213675,-0.014989825,-0.031599347,0.032314435,0.014990996,-0.0021029878,0.044871397,0.0076930956,0.015469545,-0.019407105,0.0046078856,0.050582245,0.002102096,0.011314263,-0.08012685,-0.0051637352,-0.018642286,0.005278285,0.030372888,-0.02024384,0.016610026,-0.021984087,-0.00016102378,-0.023415985,0.017816303,-0.012220813,0.05486003,-0.0027501304,-0.024698311,-0.0089859,-0.05259247,-0.010650119,-0.023330497,-0.01882633,0.0024695173,0.040999215,0.021288803,0.033525255,-0.0003460098,0.020768259,0.049518965,-0.0006527364,-0.0028219714,0.013956796,-0.0017298457,0.019683685,-0.011265582,0.032220658,-0.031949148,-0.025645569,-0.017861541,0.0036378724,-0.018973,0.011926638,-0.014635028,0.014467228,0.016420266,-0.024201937,0.05567963,-0.041709084,-0.017139843,0.0037657593,-0.011962581,-0.01677049,0.05114396,0.04934195,0.0071388893,-0.048884094,-0.033336278,0.02798275,-0.033074856,-0.027313117,0.021307038,0.003422736,-0.0058837817,-0.0009647794,-0.002492471,0.01555827,-0.01818528,-0.017761366,0.0068840203,-0.02728297,0.02429935,0.0070645586,-0.017109482,-0.07227366,0.011036575,0.014092131,0.003933063,0.03570788,-0.032107398,0.038695507,0.016459161,0.0031948425,0.00031507591,-0.018577008,-0.01315961,0.05566392,-0.00962982,-0.025732657,0.02460109,-0.011135936,-0.0023490249,0.004948562,-0.020455882,-0.006526774,0.002519171,-0.0023777182,-0.070424385,-0.006155777,-0.0011882948,0.0757341,-0.036476187,-0.024316464,-0.012628812,-0.03279361,-0.14226268,0.017621962,-0.0029456166,0.022329612,0.011038998,0.0026254873,0.0076694908,0.0002660734,-0.014461624,-0.011300174,-0.0061724083,-0.0662083,-0.04541278,-0.018578365,-0.022089873,-0.00015992277,0.00033967473,0.008723617,0.022701982,-0.025134023,-0.03192491,0.00451156,0.021408752,0.017544799,-0.05166945,-0.024202876,0.012208845,0.034887895,-0.006471522,-0.0452695,0.031776816,0.030549215,0.011903407,0.0005108722,0.02937016,0.013224285,0.020915162,0.016629336,0.011626378,0.009382063,-0.030983815,0.030898655,-0.03818196,-0.023732387,0.009693607,-0.0014748941,-0.010371784,0.01639171,0.012634285,0.033203878,-0.016041752,-0.048167046,-0.034550723,0.00089905894,-0.04702309,0.03633583,-0.0041102674,0.0513871,0.008370783,0.020572001,-0.047274005,-0.031247713,0.044755362,0.007536308,-0.010922473,0.0047117956,0.036615234,0.03875751,0.07851293,-0.035449397,0.030605549,-0.01519039,-0.026920754,0.01692278,-0.028941154,0.035694152,-0.017616684,-0.073419966,0.024281755,-0.065047316,-0.031181268,0.023959119,-0.028613102,0.008742957,-0.037410505,-0.010261016,-0.025636774,-0.07272609,0.012997264,0.22364946,0.018070316,0.08401705,0.027100114,0.018163342,-0.012081236,0.0058165924,-0.021178322,-0.016617017,-0.01155633,0.017191846,-0.0060239974,-0.004802688,0.006140815,-0.026815858,0.03466243,-0.084005974,0.028487522,0.080391236,0.0005613445,-0.05376089,0.041610114,-0.017360998,-0.028117005,-0.040324185,0.007021681,-0.028148055,0.0027748242,-0.009495817,0.039303124,-0.019343717,-0.030647902,0.012971925,0.0007482975,-0.0013818548,-0.044796053,0.010357899,-0.022916744,0.052514385,0.016415501,0.028199708,-0.0284741,0.017518774,-0.011338092,-0.038643993,-0.020498632,0.00067984633,-0.022553753,-0.023788176,-0.023471655,-0.0050054304,-0.023115562,-0.0040151286,0.01286092,-0.022942925,-0.046777252,0.002325545,-0.02415942,-0.01895683,0.038603313,0.032960508,-0.0021563908,0.0001839778,0.0058566774,0.0047222385,0.0021304497,-0.061709944,-0.01256178,0.034537517,0.047406986,-0.052486997,0.009041916,0.041259434,-0.0146695785,0.011502416,0.01858698,0.009635462,0.02953109,-0.005405405,0.005736913,-0.017914874,-0.014409583,-0.013904231,0.01828812,0.012660368,-0.016960092,-0.047757786,0.033160824,0.013073532,0.0027158905,-0.019825341,-0.015339839,-0.0029784788,0.027701108,0.019489542,-0.036157545,-0.017014412,0.02642202,-0.031594086,0.0020310404,0.014449052,0.023190482,0.024540564,0.00563035,0.02380684,0.0030616694,0.007949609,-0.040901866,-0.019762222,0.0016197113,-0.0069126235,0.007073342,0.008401454,-0.027666766,0.029997112,-0.01318206,0.023191765,0.031192819,0.07830049,0.014720637,0.006071554,-0.018844282,0.015126893,-0.018047763,0.008434582,-0.04643392,-0.026927985,-0.021163441,0.024967972,0.0071811224,0.04252553,0.004354302,0.019600507,-0.0003356556,0.03932156,0.0015417092,0.004277419,0.0032906334,0.036019202,0.0036540383,0.009357984,0.027099682,0.0026561727,-0.015016797,0.025507499,0.0054130047,-0.022902818,0.02491813,-0.03220566,-0.019491278,0.05430173,0.04249565,0.06513108,-0.035117134,0.026608203,-0.06935691,-0.034131743,-0.051750064,0.027602706,-0.029750455,0.0024154934,0.028303249,-3.609604e-05,0.07610262,0.029118754,0.049749374,-0.029132493,0.014558111,-0.00276598,-0.0018909615,0.053067274,-0.032875106,-0.01669127,0.030572224,-0.0221721,-0.053060424,-0.03892763,0.020644823,-0.008376924,-0.0117202755,0.004753087,0.013037025,-0.006936722,-0.075745516,-0.0029850346,0.015913349,0.022741385,-0.019837208,0.01835551,-0.06375235,0.004815044,0.07965819,-0.012850855,-0.003579557,0.01332696,-0.01499781,0.042841338,0.057025548,0.024856817,-0.054058384,0.021640917,0.035175476,0.039475884,-0.018953113,-0.0065815737,-0.0026420455,0.0003627209,0.0068244566,-0.008899466,0.0055074776,0.0035341782,0.03135765,0.013710059,0.026516704,0.016717965,-0.02880995,0.0019853222,-0.005569929,0.02252077,-0.026401106,0.0012131183,-0.0110834725,0.03329111,-0.017918274,0.0076378477,-0.017809778,0.010509009,0.021106532,0.016863106,0.033307925,0.007954636,0.0067989556,0.044577148,-0.03852186,0.01137654,0.0033847238,-0.038777877,0.0013701961,-0.008926696,-0.018069303,-0.028773865,-0.02738807,0.038378406,0.013376064,-0.02267281,-0.004625504,-0.083648056,-0.009893426,0.008687267,0.036380198,-0.020634819,-0.049527053,0.04701148,-0.005260376,-0.042421862,0.06042956,-0.027874263,-0.01752582,-0.029239982,0.017928885,0.01747556,0.038364977,0.0054024365,-0.029307013,0.061720617,-0.014107056,0.058893222,-0.0433693,-0.0016322581,-0.0022238675,0.02941426,-0.031660825,-0.05555373,-0.04528087,0.06489522,-0.024375241,-0.026307043,0.0032621676,-0.017687729,0.015155099,-0.040362123,-0.042419583,0.018728081,-0.0063198972,0.009775392,0.0058243102,-0.0101280045,-0.035625324,0.014888319,-0.0068503055,0.012833184,-0.0205617,-0.03401541,0.0541001,0.017912088,-0.0045145466,0.041740544,0.021874608,-0.019619508,-0.056514964,-0.026673751,0.019722639,-0.032427832,-0.033191647,0.0009591473,0.0014353476,-0.03465462,-0.05759875,0.029748885,0.0334534,0.026336458,0.0026975004,0.022445012,0.01623923,0.012594896,0.0031541116,0.040887773,-0.015304681,0.014507419,-0.036574773,0.018197984,-0.028309565,-0.032237407,-0.0160592,-0.05739506,0.039076906,0.02012161,0.035809133,0.004495911,0.0065549253,-0.016969362,-0.011588817,-0.025315236,-0.040619332,0.01774934,0.0064068665,0.031454172,-0.0035850005,0.040234014,-0.0067377,0.012654998,-0.05096373,0.07558494,-0.004181034,0.028725296,-0.028363546,-0.039431937,-0.0018842638,-0.024606895,-0.02074789,-0.027391573,0.04988514,0.019561695,-0.07736644,-0.004187845,-0.03410508,0.017699571,-0.039728392,-0.014224016,0.0038449022,-0.060557663,0.055808235,-0.013244743,-0.024121458,-0.026347084,0.038661476,0.016360376,-0.021631699,0.036506742,-0.0064257765,0.01902639,0.009707878,-0.0076630884,0.018014982,-0.028525185,0.043972258,-0.0068861395,0.020155553,-0.028334891,0.0010822909,-0.0056242645,-0.03510867,-0.037327204,-0.005587359,-0.02959364,-0.0056677638,0.0010815726,-0.018772138,0.02052743,0.053390894,-0.06432634,-0.036027923,-0.010349432,0.012269904,-0.13889974,0.012234366,0.0361138,-0.02824813,-0.022136366,-0.0024328018,0.0069576036,-0.028859356,-0.013786753,0.015703587,0.005711038,0.033617724,0.016343419,-0.006460414,-0.014210681,0.03715367,-0.008073729,0.0015417795,-0.0047756783,0.011023426,-0.0053623444,-0.036364585,0.08320016,0.023615586,-0.0038103864,-0.03581845,-0.015461269,0.08722141,-0.042486075,0.02955994,0.043178417,-0.003242776,0.028713666,-0.01767703,0.0018059191,0.013306419,-0.006609636,-0.030738005,0.0067352387,0.0006151419,-0.023132354,0.030734312,-0.061628815,-0.0077890614,0.031642783,0.04799929,-0.029191878,-0.012735883,0.004820603,-0.039164253,0.025612436,0.00078067306,-0.0006234766,-0.0040142136,-0.027489189,-0.016522773,-0.04753778,-0.024556002,0.0008949845,0.016236452,-0.040266424,0.014781908,-0.04419321,-0.058466446,0.068850234,-0.0008982631,-0.011384016,0.039267033,0.005129823,-0.033407725,-0.001229599,0.029942846,0.005805533,-0.045213237,0.017226547,-0.02962203,0.013431969,0.04019966,-0.055238463,-0.013570983,0.00091558055,-4.7725254e-05,-0.041528616,0.012862851,0.018193074,0.049093314,-0.019412072,-0.0141883725,-0.02893881,0.0035871284,-0.02797513,-0.032196213,-0.035272747,0.028365033,-0.021547195,0.013229813,-0.02397402,0.026914738,0.011464617,-0.036332585,0.046646886,-0.017294966,0.00087285426,0.017531112,-0.036118418,-0.022689402,0.0013510698,-0.03247635,-0.016907886,-0.028446602,-0.0056296983,-0.009771491,-0.010404955,-0.003955863,-0.0626889,0.012640103,-0.050274488,0.02959529,-0.0007235634,0.023616275,0.03687991,0.0037317735,-0.010765788,-0.033620458,0.049332835,0.048505384,0.0239102,-0.01266111,0.015362913,0.035054978,0.019611342,-0.057103872,0.011423162,0.008776347,0.0031849088,0.033689536,-0.0023840182,0.053471766,-0.011582255,-0.022816408,-0.0127043575,0.0171009,-0.009414499,-0.022855286,-0.0010346773,0.0012636464,0.021340486,0.009235848,0.05737919,-0.049479272,-0.0049320715,-0.013284026,0.007901177,0.04288738,0.0036992985,0.008218144,-0.02158657,-0.033285823,7.457534e-05,-0.010238552,-0.030097676,-0.030927552,-0.0004293552,-0.051289998,-0.022808626,0.01621582,-0.006012524,0.0026586177,0.04486551,-0.024102338,-0.018911729,0.0057803583,-0.0075502745,-0.002367468,-0.027786197,0.013269815,-0.009199853,0.008245763,0.071967915,-0.0021217274,-0.01062716,0.012652643,0.020903321,-0.04140754,-0.017856365,0.06833696,-0.009205664,0.0004297612,0.042584382,-0.037255395,0.03014874,0.0041698017,-0.031116404,0.0491315,0.018814253,0.050202396,0.042611774,0.057184935,-0.0224464,0.056785382,0.035617232,-0.034985937,-0.010319613,-0.02356294,-0.04167084,-0.008986488,0.014102941,0.02343322,-0.05341201,0.004812769,-0.0058729425,-0.002203026,-0.006289109,0.05614352,0.009767936,0.014835237,0.014908244,-0.02299144,0.019437786,-0.01879921,-0.045219682,0.015496437,0.04144725,-0.013121378,0.004875054,-0.033534624,0.010414437,-0.0029018733,-0.0036975197,-0.03569658,0.013971817,-0.03101717,-0.024249699,0.05916637,-0.034687147,-0.004407517,-0.009067386,0.026876524,-0.019818537,0.018880617,0.050643746,-0.04288628,-0.03593336,0.0054016346]
410300	Other Income	Other Income	revenue	[-0.022900725,0.055109847,-0.017657937,0.014477033,-0.01693162,0.025968669,-0.0009769042,0.056009367,0.012697129,0.007709437,0.0027783718,-0.018271575,-0.021515986,-0.026938416,0.04017617,-0.04502217,0.0072812415,-0.0036499044,-0.04230503,0.011328758,0.008474709,0.034038603,0.04593593,0.024184337,-0.011026913,0.0014011157,-0.010891451,-0.042086974,0.051824063,0.014227448,0.007948874,-0.017307566,0.0007861161,-0.042765506,-0.057902478,-0.009280907,0.0054667834,0.019310925,-0.05325181,0.0703516,-0.010054793,0.024450311,0.033883695,-0.0330638,0.05856399,-0.01716436,-0.012764992,0.0005086856,-0.01398924,-0.029497407,0.018884053,0.0061915717,0.05646557,-0.027237654,0.0062975897,0.02411208,0.0068448232,0.014940377,-0.047619935,-0.03086571,0.0027235593,0.035351694,-0.029573092,-0.026184747,0.025362365,0.07011334,0.014263826,0.059390407,-0.0098308325,-0.030237598,-0.027671121,-0.007607747,-0.029675083,-0.028929412,-0.03235107,0.01419434,0.016214667,-0.010400342,0.014707324,-0.015980242,-0.020962216,-0.001385927,0.009753391,0.038205087,-0.044869404,0.04584869,0.0015623416,0.0040018894,-0.011363206,0.022086404,-0.06741932,-0.050111946,0.033182137,-0.043338004,-0.038755577,-0.021014644,-0.005732869,0.024793426,0.012179372,0.0008806774,0.05019432,0.023120278,0.009190232,-0.01377207,-0.008141827,-0.031504888,0.029555513,-0.0020973147,-0.043907493,-0.02197737,0.010407295,0.07697821,0.039757628,-0.014005351,-0.015445839,-0.021236517,-0.0011549648,-0.015171248,-0.013763796,-0.0405968,0.04034746,0.044221483,0.0900832,-0.0062094433,0.06618499,-0.0073012887,0.008205417,0.026389288,-0.060437214,-0.0134061305,-0.0011910786,0.01917281,-0.046084337,0.035197765,-0.030091489,-0.04838106,-0.02104407,-0.01850467,0.030362928,-0.014551529,0.027763272,0.04553844,0.0031393738,-0.01882276,0.059599698,0.0029728431,0.05333087,0.033667386,-0.00441989,-0.07606294,-0.005676532,0.02930823,0.0063192947,-0.026583845,-0.0024824038,-0.0047036,-0.0100230025,-0.008607981,0.018030705,0.041933633,-0.028794143,0.002723038,-0.026170628,-0.013214145,-0.01861686,0.021479849,-0.018027311,0.021368844,-0.0031478084,0.0087511595,0.0067583104,-0.026356358,0.01771304,0.015433584,-0.020315917,0.031061864,0.05520537,0.0045072204,0.0076482682,-0.051865116,-0.019980948,0.037695274,0.002084614,-0.04311953,0.007163044,0.008019048,-0.039984297,0.028219515,-1.8564528e-05,-0.0028812962,-0.018933397,-0.013710918,0.04947381,0.010913306,0.068989314,-0.05886096,0.021824297,-0.04302613,-0.03571511,0.003647316,-0.019547379,0.00737815,-0.0469598,0.0013825482,0.0024814415,0.015739374,0.010975033,0.024044972,-0.0036829999,0.0043504317,-0.015588047,-0.0056732274,-0.021559933,-0.025180925,0.006723755,-0.016148752,0.030683484,0.013159919,-0.007016035,0.024597548,0.018585881,0.04486528,-0.016646627,0.044960216,-0.0029534984,0.017428642,0.0012887325,0.042872224,0.049789608,0.009797892,-0.002172224,-0.024250442,0.017700238,-0.0073404494,0.023246044,0.004683889,0.04008825,-0.0016812568,-0.06625894,0.034683704,0.0093012955,-0.014457227,0.013838981,0.031937383,0.017917203,0.029009111,-0.003224733,0.0047500283,-0.041209545,0.010370216,0.011961913,-0.019095298,-0.034209322,0.023378186,-0.024267135,0.043123264,-0.039108057,0.0007393155,-0.020512555,0.029438186,0.00728865,0.057898443,-0.02203123,0.012851372,-0.026884552,0.011361789,-0.040950123,-0.022928711,0.012547366,-0.023060862,-0.0074471333,-0.004642069,0.025845112,0.01124428,0.013290853,0.004426022,-0.01122461,-0.035445042,0.042159006,-0.022096906,0.013574269,0.056429558,0.010216317,0.0041988925,0.015279788,-0.012683816,-0.007486314,0.029482018,0.011016585,-0.028805496,-0.033077434,-0.0067285383,0.049940046,-0.030027518,-0.04708183,-0.002216081,-0.009102598,-0.16074598,0.017460339,0.00726811,0.02226762,0.009888624,0.021013256,-0.018400958,-0.033670332,0.0038352278,0.004609452,-0.0032465782,-0.060033962,-0.013478915,0.018045152,-0.004659016,0.012137835,-0.021295927,0.006176893,-0.02792931,-0.029115258,-0.011382303,0.02205489,0.017120035,-0.019930637,-0.031771526,0.0044527766,0.042714234,0.008428139,-0.012071467,-0.031925365,0.0138466535,0.022025524,0.005266474,-0.01155155,0.021819837,0.051866394,-0.04379154,-0.014664208,0.023370638,0.029836176,0.010830815,0.0053868564,-0.0229843,0.026528921,-0.0080598425,-0.036526013,-0.0024498552,0.058776584,-0.03752809,0.044232983,-0.03516698,-0.007693245,-0.048813805,0.022610081,-0.028057639,0.024902988,0.023863327,0.010440502,0.024066376,-0.018207094,-0.041821864,-0.075930916,0.021713866,0.0003058288,-0.019927783,0.022277413,0.035562966,0.02627462,0.0573226,-0.049498368,0.0073682545,-0.046440363,0.049207184,0.0038496198,0.009064852,0.0526932,-0.08698138,-0.053231493,0.024264442,-0.112106256,0.0047527715,0.063066944,-0.0027086404,0.024764255,-0.047380336,0.01474976,-0.0122306235,-0.059345756,0.052283965,0.2170539,0.01593696,0.046441276,-0.023020525,-0.009969642,-0.045092255,0.01659646,0.011317047,-0.009334762,-0.05447499,0.012086203,0.0021387604,-0.01906871,0.017756274,-0.02878189,0.021632573,-0.120158985,0.028021865,0.08302077,-0.016274203,-0.016090347,-0.020770362,0.010515317,-0.04752873,-0.06694215,0.0118020885,-0.04595591,-0.008735452,0.014082211,0.0325955,-0.0274284,-0.025667908,0.03844446,0.019065578,-0.029990368,0.019235345,-0.012284308,-0.05146037,0.030307584,0.048097283,0.031277098,-0.0068480335,0.004602565,0.0312867,-0.046865657,0.02069883,-0.0037486039,0.008678948,-0.03622083,-0.008270795,-0.0130948005,-0.03761215,-0.012134623,-0.020543586,-0.0075437585,-0.025747634,-0.0011202821,-0.008949392,-0.033949398,0.069919735,-0.0022704303,0.022474168,-0.020436255,-0.0037367935,-0.033979196,-0.013739275,0.013313393,-0.0024206212,0.028445398,0.049197197,0.0006591854,0.030113377,0.003971568,0.0226033,0.010354541,0.02454806,0.02904212,-0.0039197076,-0.026715301,-0.0015241302,-0.029577747,-0.008286966,-0.002666363,0.008374286,0.0066726883,-0.012974876,0.024392832,0.06323531,0.056285445,-0.055313684,-0.028465062,-0.01073762,0.0113951815,0.023247372,-0.030650675,-0.06927146,0.016271757,-0.008989859,-0.038860157,-0.0052214307,0.027726678,0.009403252,0.027210211,-0.024072394,0.007980776,0.031082978,-0.0128558865,0.012588502,-0.020215133,-0.0015358438,-0.013617622,-0.014538347,0.0071880408,-0.037151046,0.03009379,0.003141432,0.0046109473,0.02714725,0.05520465,-0.032985993,-0.0063372613,0.0075614927,-0.013073264,0.025120532,0.0073920493,-0.020931173,-0.027940027,0.03554195,-0.0075346837,0.016206287,0.0010287225,-0.0012261622,-0.04630529,-0.0300645,0.017848847,0.011293062,0.08803538,0.015680976,0.019583112,0.020414451,0.0058690687,0.044701684,-0.014658366,-0.04264983,-0.0049382485,0.033091493,-0.025507864,0.018236388,-0.0049714483,0.042846173,0.048789263,0.010804722,0.054726332,-0.0400662,0.008197802,-0.02511727,-0.016568571,-0.03447509,0.028043585,-0.003205209,0.029493485,0.04000221,-0.0143832695,0.088355735,-0.010759683,0.05013511,-0.011064873,0.0025916258,-0.022154469,-0.010927368,-0.028040037,-0.01924044,0.005255809,0.046467535,-0.04068666,-0.023286387,-0.053624637,-0.007079876,-0.015284621,-0.04416574,0.036172222,0.010423253,-0.005179318,-0.05020274,0.045503616,-0.00069865776,-0.03726214,-0.017335976,0.018182186,-0.09354199,-0.016673913,0.104040354,-0.0018149393,-0.024863308,-0.022742083,0.023294497,0.032460995,0.0002903554,0.0021396829,-0.07053038,-0.0027281202,0.03409897,-0.012911215,-0.0107828155,0.0006896832,0.037320532,-0.0001710161,0.024532484,-0.03715577,-0.014012981,-0.022780979,0.0013915439,-0.014982715,0.0022286715,0.017824568,0.015527464,0.05623199,-0.025671795,0.00060051307,-0.04651319,-0.006230666,-0.0058779605,0.0249517,-0.07722099,-0.032037638,0.019023187,-0.011002632,0.056112375,-0.016973095,0.012348792,-0.0031973573,-0.011790424,0.052761167,-0.0260917,0.0092545375,-0.0075327842,0.008967637,0.040269285,-0.0035703352,-0.048310198,-0.007991378,0.006210627,-0.00819923,0.030857144,0.005195647,0.014795367,-0.0755715,0.016553663,0.060813583,0.03662264,-0.0039061857,-0.04706652,-0.026652038,0.0037007,0.006207565,0.027461365,-0.039965194,0.017142761,-0.05006259,-0.01083457,0.030412449,0.025077391,0.0050575193,-0.035291724,0.051238976,-0.011405631,0.017019857,-0.016774256,0.028668545,0.0011880818,0.009586544,-0.028355286,-0.008179707,0.002097181,0.06773871,-0.011707903,0.0019184274,-0.019994361,0.018752081,0.0006802977,-0.024934765,0.0023846608,0.017401045,0.02686184,-0.03569012,0.037194654,0.018975647,0.02954897,-0.015956916,-0.016955333,0.02184687,0.0049481825,-0.022344017,0.026031476,0.030378407,0.009688627,0.012453484,0.035417233,-0.033147737,-0.03462232,-0.033525642,-0.026207566,-0.021508578,-0.043211468,-0.029826425,0.013573467,-0.03491339,-0.06211014,0.03943257,0.012998806,-0.0246023,-0.030286778,-0.0006660365,0.0013342941,0.011892351,0.019776052,0.070617236,-0.0074381027,0.031269316,-0.028896244,-0.04690511,0.020824483,-0.024202729,-0.0040254383,-0.003711396,0.029608173,-0.011838522,-0.016317097,-0.028507844,0.008832507,-0.01549033,-0.015803274,0.004651805,-0.049342316,0.027208189,-0.009107569,0.03828938,-0.013341234,0.009608841,-0.024351075,-0.023366464,-0.018976016,0.07116508,-0.01963602,-0.016755678,-0.00013568313,-0.026794812,0.0054722265,0.05256704,0.009101645,-0.026937148,0.025989782,7.848017e-05,-0.010513059,0.008533202,-0.04437656,0.02552115,-0.035710745,0.044003326,0.032668933,-0.03657847,0.02857792,0.0067620147,-0.020359335,-0.030077538,0.0010999041,-0.0016380143,-0.01074932,-0.0006445775,-0.036240168,0.0088162115,-0.03741679,0.035960548,0.004212177,-0.039833747,0.0482874,0.025485307,-0.0038721988,-0.014971192,-0.026733179,-0.016418487,-0.029218027,-0.030499997,-0.019587627,0.009843352,-0.0105148,0.011340893,-0.011685428,0.010702105,0.011011834,-0.047458217,0.0049518743,-0.032232776,-0.024594756,-0.1454007,0.004525137,0.013481946,-0.022866031,-0.06475319,-0.012161196,-0.0052760523,0.0012441361,-0.010037304,0.021643233,-0.0221315,0.009081339,0.018127102,-0.0056140046,-0.009933278,0.049998384,-0.00645412,0.012435647,0.011333384,0.06211364,0.0073600183,-0.033360817,0.03564165,0.010747027,-3.3708686e-05,0.0058226897,-0.0038957153,0.07066709,0.00632408,-0.009770701,0.018135067,-0.06358363,0.012876619,0.03851769,0.03069884,0.027032401,0.008857879,-0.020932976,0.033753496,-0.017581034,-0.010882242,0.02976764,-0.020087922,-0.012640991,0.029243669,0.032638285,-0.012552705,-0.013758588,-0.009042967,-0.036576252,0.014471326,-0.0028003803,-0.008856385,0.021545503,-0.02947868,-0.013597394,-0.05611012,-0.023028808,0.007667681,0.035537306,-0.03980199,-0.014811919,-0.020870786,-0.047257375,0.01609864,0.008246184,-0.03320423,-0.0064262105,-0.013859239,-0.027131418,-0.04904577,0.0070629204,0.016546573,-0.051278904,0.0031480673,-0.031036463,0.052300602,0.004838808,-0.051795367,-0.019522702,-0.043049473,-0.0076475358,0.011096829,-0.02519508,0.004876955,0.031132864,-0.014063283,-0.020318672,-0.040310904,-0.030569606,-0.013566225,-0.035768893,0.0106665315,-0.0007312453,-0.03199838,0.037507806,-0.027103705,0.012009787,-0.03078888,-0.017098865,0.00017517326,-0.024623517,0.034897756,-0.030447485,-0.050903652,-0.009793393,0.00037416452,0.0087115895,-0.0042846706,-0.016836211,-0.01586598,-0.01712851,-0.055717904,-0.017854622,-0.03199153,-0.015699744,-0.0046865717,0.059585486,0.020657197,-0.0072840634,0.022759186,-0.024802914,0.039191727,-0.029007442,0.047425922,0.0035058772,0.0010324364,-0.004953159,0.04760338,0.0049988353,0.023064071,-0.10133856,-0.007373637,-0.010739824,0.011807245,0.06041388,-0.029922975,0.04724619,-0.0039010965,-0.0048236577,0.020495227,-0.017431377,-0.041481994,-0.048534043,-0.02160396,-0.026151216,0.06134593,0.0212744,0.017019952,-0.041033998,0.0037510232,0.004501056,0.003718499,0.026459442,0.0016706237,0.006058807,-0.037747663,-0.03911945,0.028034603,0.015832085,-0.0050227144,-0.038701568,0.02484756,-0.07066968,0.0011462334,0.04442533,-0.022409072,-0.011193861,-0.010561792,-0.030331338,-0.006584831,0.022527559,-0.00651463,0.0054895557,0.0029644084,0.028831875,-0.018544454,-0.016374739,0.03797264,0.018993989,-0.004991608,-0.0070656254,0.015897222,0.04381307,0.022848645,-0.004021969,-0.014615489,0.026690183,-0.0024319843,-0.025312636,0.004927406,-0.006022202,-0.04853678,0.034046546,0.044545695,0.036209557,0.016909499,0.013103675,-0.03225453,0.047005028,0.016428448,-0.024394002,-0.019891996,-0.015949752,-0.017108632,-0.03207448,0.044139743,0.026703048,-0.061754256,0.029005406,-0.035950318,-0.019993596,0.012751962,0.021236626,0.004308412,-0.008749817,0.017811012,-0.019237831,-0.00085534534,0.036193267,0.007311068,0.037832126,0.0026048727,0.027540827,-0.0068021896,0.00526842,-0.026871178,-0.005996988,0.035689652,-0.022605823,0.002026271,-0.013698762,-0.011185981,0.07280307,-0.050129168,-0.0014909622,0.0033757088,0.0064197723,-0.025327789,-0.0072175683,0.039425794,-0.0146199735,-0.015639883,-0.03380919]
510100	Salaries & Wages	Salaries and Wages	expense	[-0.042585365,0.030252552,-0.0526209,0.0051517873,-0.022218255,0.009650197,0.034204647,-0.0022163596,0.0028214282,-0.0075397976,0.049818195,-0.011792658,0.025604771,0.0024151949,0.005559182,-0.042750284,-0.012357692,-0.03133367,-0.019737635,-0.033405777,0.005188372,-0.012182082,0.018623617,0.018471332,-0.0014271912,-0.025121946,-0.011668081,0.008292689,0.0143575,-0.022733632,-0.0046171458,-0.002204838,0.026461184,-0.0064897244,-0.0114405155,-0.03084348,-0.0019329257,-0.039687183,-0.076112576,0.036445994,-0.020642681,-0.014359513,-0.0043641017,-0.053882666,0.035066735,0.006977034,-0.06150699,-0.008789922,-0.04089528,0.016285982,0.025308631,-0.038960285,0.064077094,-0.010698317,0.017974291,0.025871197,-0.017322782,0.012971741,-0.08233921,-0.01770566,-0.02407953,-0.017239774,0.018838054,-0.012260234,0.03895172,0.05395867,-0.03326606,0.038873028,-0.017260592,0.002054809,0.056010593,-0.0018743069,-0.0620508,-0.023066256,-0.04960513,0.040748317,0.024323644,-0.05580871,-0.020311091,0.020870682,0.005101317,-0.013144799,-0.010074887,-0.0352993,-0.04635928,0.041939873,-0.017082201,-0.0054300544,-0.0239304,0.0048548784,-0.0019093194,-0.02021698,0.02975881,-0.04054018,-0.07212019,-0.029638495,-0.08450646,0.032891657,-0.0017739064,0.0022105074,0.049388226,0.0416345,0.009464344,-0.017245967,0.03280474,-0.009886754,-0.007156888,0.0052746227,-0.010618868,-0.01231541,-0.0027805332,0.0284601,0.006020371,0.0028455185,-0.0078012696,0.019413333,-0.03713309,-0.0013248211,0.018810555,0.012185297,0.055893645,0.023776935,0.042293116,-0.0168566,0.047966108,-0.013222107,0.024452742,0.008394392,-0.012977639,-0.00037590784,-0.029321589,-0.0056223636,-0.008875416,0.017743265,-0.016908208,-0.026293416,-0.001298104,-0.04419304,-0.03155454,-0.051459223,0.017943185,0.054529883,0.0012602018,-0.020745657,0.028215552,-0.03356591,0.048980545,0.04029737,-0.015534938,-0.0086596925,7.029213e-05,-0.014721238,0.04456192,-0.03290223,-0.044780716,0.005224469,-0.000700683,0.04118453,-0.0050092842,-0.0010149853,-0.00717698,0.0003626396,-0.036077578,-0.018714996,0.03935267,-0.005045071,-0.016418172,-0.0139962565,-0.014939582,0.0037767114,0.01793389,-0.05678016,0.03721016,-0.017060053,0.023152027,0.031614617,0.07542286,0.029249325,-0.0065126275,-0.049607884,-0.081947945,-0.021342708,-0.021060253,-0.020494632,-0.014489743,0.031560488,-0.029531173,-0.018697413,0.014372914,0.009868468,0.029858546,0.015887229,0.015818572,0.025609639,0.020338153,-0.013738507,0.005969235,-0.019709125,-0.020325573,-0.018515443,-0.051006094,-0.012607907,-0.04116602,-0.007756431,-0.039608542,0.0036983013,0.032125358,0.0044912836,0.00919178,0.0019027307,0.0012762581,-0.011458515,0.0070508276,0.010592384,-0.0017260711,0.014491377,0.036053065,0.01945726,0.0116539495,-0.039248988,-0.011386808,0.022543602,0.029642068,0.04555394,0.020560103,-0.015497759,0.033665054,0.056743726,0.04539937,-0.045772534,-0.040800184,-0.029218132,0.06321558,-0.035445035,0.02241874,-0.022148797,-0.010294182,0.069808796,-0.019374963,0.0017093269,-0.048997816,-0.020564368,0.009483246,0.02616816,-0.028101055,-0.023229422,0.036482625,0.0053925086,-0.046104744,-0.039131682,0.07807101,-0.03668911,0.017700687,-0.05540355,0.015274178,0.014590834,0.0152380075,-0.017447822,-0.0023855248,0.019698245,0.011481459,-0.024640694,0.017115444,0.045914713,0.006996627,0.011179834,-0.049038656,0.010476742,-0.0014730587,0.027274959,0.0055150627,-0.01039473,0.048131574,0.012215075,0.0036864998,0.05446826,0.0268932,-0.024100844,0.035529405,-0.06767991,0.022189364,0.07359583,-0.0033170737,0.0058748825,-0.0002804524,-0.02296118,-0.0014376612,-0.03282353,-0.012398822,-0.033440426,-0.008847449,-0.031503703,0.042340558,-0.028380672,-0.033396326,-0.01102986,0.032778047,-0.15510184,0.0055000824,-0.024206005,0.06348276,-0.0164901,0.0038458607,0.0023800328,-0.019739341,-0.012767058,0.019604946,0.067232855,-0.039298795,-0.025770525,0.008772107,0.017387267,0.027301164,-0.02736716,0.030176282,0.018988144,-0.041705843,-0.04176033,-0.052685592,0.041353323,-0.06423431,-0.0531979,0.05729291,0.0051112827,-0.011070298,-0.019162888,-0.006833036,-0.006003596,0.017972458,0.010171899,0.038904116,-0.02090586,0.039769057,0.024066024,-0.04625369,0.014976057,0.0052281483,-0.0066284584,0.053440705,-0.0071873353,0.02615995,-0.008826706,0.02399692,0.01284948,0.0041218475,-0.026586475,-0.009613529,-0.040318158,-0.043100055,-0.031314988,-0.022179674,-0.044748936,-0.010597043,-0.029935468,0.026424648,0.013433816,0.04505849,-0.029771645,-0.03358527,0.04893665,0.006292309,-0.027435899,-0.011165706,0.012047398,0.00497583,0.03696234,-0.03005439,0.03347258,-0.041136764,0.014857326,0.011386159,0.026984356,0.041211735,-0.02972792,-0.030841503,0.02040337,-0.12347281,0.01889419,0.0016172782,-0.00077508844,0.011557581,-0.04205822,0.012481134,-0.012416563,-0.059223052,-0.0019792637,0.19757219,-0.008512412,0.0064053233,-0.017506406,0.040890675,-0.015416503,-0.0023445773,0.026127728,0.016781507,-0.048451874,-0.017416224,-0.038726304,-0.007376576,-0.020674903,0.028361142,0.017190982,-0.0657983,0.004968007,0.07690401,0.011291138,0.0387017,-0.022723509,-0.010548257,-0.017980544,-0.07130781,-0.00079209404,-0.05779333,0.028133942,0.004510429,0.06800115,-0.03516757,-0.015973413,0.016052226,-0.010914753,-0.032534108,-0.016313437,0.016338892,-0.036456354,0.03839225,0.05481424,-0.03454519,-0.060788576,0.019422643,0.03113458,-0.021906972,-0.052762836,0.06374515,0.016224554,-0.045657743,-0.03119909,-0.03382584,-0.019660003,-0.052548558,0.006628989,0.003517309,-0.024504576,-0.028898055,-0.015174557,-0.01430421,0.083329335,-0.012795791,-0.007893891,-0.04312826,-0.0009975845,-0.014379897,0.0073200464,-0.03366704,-0.021696262,0.03548413,0.05513974,0.00985468,0.0633053,0.018717943,0.027667413,0.05772301,-0.010353497,0.048754156,0.002056189,0.028225409,0.014105002,-0.06885728,0.014316116,-0.014326718,0.00927427,0.007103462,-0.016039243,-0.012720618,0.018722143,0.020384485,-0.017113794,0.0031625256,0.03357412,0.024909977,-0.032454684,-0.005117553,-0.01410098,0.023689862,-0.011383407,-0.015029156,-0.019555934,0.035707213,0.034775823,-0.004346395,-0.07414476,-0.015102136,-0.012147638,-0.015386955,0.005736233,0.01801577,-0.008931489,-0.038277004,-0.0139239095,0.0040060775,-0.035968564,0.019466402,0.02172645,0.007970499,0.028207455,0.03880048,0.004513767,0.0006198044,0.0068366183,-0.021411436,0.015691279,0.0073306444,0.013307867,0.01362328,0.002886913,-0.017193543,0.035036385,-0.013777386,-0.024846833,-0.04681944,-0.008190881,0.06080571,-0.015734911,0.08040097,0.0108309435,0.0162162,0.0030203534,0.033681475,0.03918391,-0.0056356955,-0.03774753,0.02810674,-0.008130606,-0.009113224,0.04599588,-0.009945479,0.0657122,0.041100036,0.0035618797,0.010362643,0.009098043,0.014594866,-0.057553217,-0.0057102772,0.008014179,-0.0045895055,-0.028965453,-0.00518029,-0.006409215,-0.019605402,0.08636748,0.0444286,0.012639247,0.024624756,-0.046864476,-0.066766195,-0.0062171617,-0.05079125,-0.03026935,-0.021256013,0.08473907,0.019393483,-0.00024482308,-0.033911932,0.024745256,-0.012244151,-0.03001984,0.01945065,0.0020896334,-0.030437991,-0.0054186326,-0.015135132,0.0273694,0.023142662,-0.012750558,-0.04530429,-0.02458266,0.004717316,0.0966532,-0.01273811,-0.014929555,0.013058726,-0.013197934,0.014444395,0.010530553,0.023417573,-0.04594191,-0.02243108,0.009831634,0.029449174,0.015031597,0.013451384,-0.011683834,-0.00036260075,0.055497583,-0.0074737757,0.026948828,-0.0009868616,0.01730906,0.009480095,0.0034149236,0.015864868,-0.02713705,-0.006232535,0.013662026,0.031158566,-0.03779772,-0.044778798,-0.017439792,0.02805291,-0.015099817,-0.02140629,0.016351461,0.006455208,0.028004283,-0.007588842,-0.0057612956,-0.0023354082,-0.0082965065,0.025294654,0.009885911,-0.01779486,-0.015402906,0.03861787,0.02218551,-0.019975916,-0.037622858,0.019092409,-0.0026814542,0.008789205,0.005292152,0.008150996,0.016715093,-0.0346038,-0.028668778,0.013461632,0.017069973,-0.028378239,-0.02438027,0.0131041715,-0.017899342,-0.04257013,-0.0017289018,-0.043316238,-0.015081418,-0.04154461,-0.003428805,0.029190356,0.027794147,-0.0030410578,-0.01234036,0.018642966,-0.012890387,0.014692592,-0.010227687,0.007293413,0.01505895,0.020300489,-0.01100012,-0.065759875,-0.0039689224,0.05189647,0.036160253,-0.022336101,0.014993323,0.0047608404,-0.0034995861,-0.050251696,-0.00669883,-0.0274252,0.03810008,0.026220905,0.06384492,-0.005947517,-0.011325332,-0.0109252995,0.020883527,0.035674118,-0.025377503,-0.0392332,0.025718408,0.017320406,-0.016494676,-0.006083102,0.031615432,-0.040156923,-0.010236268,-0.020464633,0.008723882,-0.007002853,-0.03526008,-0.009700778,-0.0003652242,-0.023898233,-0.059472412,0.0017209457,-0.013572036,-0.013127468,0.0023851537,-0.0068650357,0.027208356,0.027831703,0.00860812,0.041430537,-0.012756252,0.0035462524,0.038498804,0.054820184,-0.0082449755,-0.043696802,0.0078048897,-0.002840137,0.019229427,-0.0114930235,-0.0042265584,-0.028139452,0.017181601,-0.050606687,0.0072711343,-0.039968025,-0.008292459,0.0026258037,-0.04374537,0.0688682,0.021292014,0.0114911655,-0.048241697,-0.011437816,-0.031068353,0.031070985,-0.0132771935,0.063258946,0.009397893,-0.03738417,-0.02701452,-0.022522423,-0.011124975,-0.014458964,-0.011574582,-0.03571872,-0.018502424,-0.019270923,-0.028746536,-0.026893634,-0.0013484765,0.0081074275,0.037820105,0.00200696,0.03464789,0.029003305,0.0052488223,0.024957856,0.035046734,0.00803058,-0.0015682383,-0.003218191,-0.025185015,-0.01945305,0.002710876,-0.008944444,-0.007479659,0.0036620446,0.046015114,0.025988722,0.02809478,0.046050493,-0.037964262,-0.0032153444,-0.016987383,0.009616699,-0.020507334,0.0019131693,-0.028301882,-0.0011795901,0.010682162,-0.010578174,0.04023688,0.008974761,-0.016061518,-0.031099182,-0.005982755,-0.14647898,0.0046841954,-0.030851163,0.012585176,-0.054006472,-0.015686901,-0.005411022,0.019514503,0.016741019,-0.02085328,-0.01786985,0.015035399,0.031148432,0.0126476055,-0.01721858,0.03818768,0.0068755536,-0.040020287,0.0074441084,0.07165224,-0.01931657,-0.027535418,-0.004368571,0.058022007,0.022116901,-0.004651293,0.027633019,0.029035337,-0.035927337,-0.0036552884,0.008399909,-0.03688046,0.0059074773,0.05003931,0.03925813,0.041851033,-0.024164263,0.022799188,0.02458878,-0.0012504214,-0.0061618285,0.019554155,-0.013769913,0.044198018,0.050426137,0.07955256,0.021670617,-0.0073095765,0.010858942,-0.032458626,0.02991214,-0.022121193,-0.0011011114,0.06482777,-0.0013286312,-0.013929234,-0.028861972,0.005059935,0.010036157,0.055524025,0.008678909,0.077790104,-0.028979113,-0.054293565,-0.010147935,0.030851487,-0.034800302,-0.0024164203,0.0018588329,-0.03527582,-0.011259173,0.010581675,0.015198332,-0.019172158,0.008707666,-0.049127337,0.052614767,0.023301981,-0.017760808,-0.011176538,-0.0076757716,-0.027260689,-0.05526745,-0.005291791,-0.011078437,-0.00531546,0.0071784123,-0.013012152,-0.05206706,0.024369538,-0.015167262,-0.020390768,0.003669995,0.049761645,0.006793943,0.03746779,-0.034000423,0.00026590837,-0.03854904,-0.05375245,0.012870984,-0.03864923,-0.00018031106,-0.012897497,-0.057009835,0.026775498,-0.03605736,-0.04650979,0.014666794,0.029817456,0.001054958,0.03039305,-0.022332847,-0.032364864,-0.068739966,0.011190702,-0.0047755344,0.061696935,0.008262189,0.0010377357,0.00383035,-0.03945516,0.00899708,-0.025802856,0.05066972,0.020900212,0.027220871,0.03811219,-0.024273647,-0.019932628,0.024388453,-0.021166304,-0.0046053897,-0.009352757,0.010154153,0.03529135,-0.035022102,0.024534516,-0.07166124,-0.041722998,0.027893875,0.023768684,-0.0215143,-0.023526823,-0.008621451,-0.057259273,0.028994292,-0.028432041,0.024482151,-0.021050628,0.035046585,-0.010482557,0.0010843909,0.024595771,0.035527837,-0.01680393,-0.016575873,0.026862256,-0.013784626,0.02423601,-0.02691185,-0.012942887,-0.01162675,-0.048507392,-0.0053084497,0.03350314,-0.014043171,0.03077503,-0.01679988,0.01467563,0.0006678103,0.025487933,-0.009221255,-0.025115868,0.03684432,-0.009183516,1.7560362e-05,-0.018605359,0.054486804,0.04719818,0.0005595733,0.006143018,0.039569978,0.035193846,0.008128451,0.025731692,-0.038169906,-0.018839017,-0.023342874,-0.034010142,0.029540198,-0.013567999,0.016505867,0.035975777,0.048313327,0.02329858,-0.009128169,0.040835403,-0.047515646,0.04189117,0.011693657,-0.013572875,-0.05322456,-0.019033281,-0.04481958,-0.03654961,0.03461391,-0.018748032,-0.027081853,0.009779571,-0.008936554,0.00046254398,-0.0022107922,-0.0013919026,0.018016499,0.018403085,0.0155233275,0.00322353,0.0025853862,0.0029713835,-0.01601695,0.061503373,0.009301296,-0.033826247,0.006096511,-0.043573722,-0.01651598,0.004708869,0.028371874,-0.013647104,0.018517453,-0.046049114,-0.058711372,0.037678685,-0.0027986872,0.02700049,-0.015342362,-0.017544074,-0.039582305,0.020760356,0.061496377,0.011435826,-0.023546645,-0.013763112]
510200	Travel & Transportation	Travel and Transportation Expenses	expense	[-0.041416027,-0.0035270315,-0.005663549,0.03327264,-0.030053215,0.007152884,0.025716983,0.0011122399,-0.024796749,0.0038240615,0.025027381,-0.002670247,0.020067269,-0.01313552,-0.009657365,-0.037224084,-0.016613504,0.0068188556,-0.027203614,-0.04127211,0.03262071,-0.032329813,-0.012808905,0.065586135,0.0065431185,-0.009741775,0.0022386163,0.031914283,0.01889262,-6.422901e-05,0.030039174,-0.04574767,0.011552101,-0.029685525,-0.04791812,-0.06406842,-0.027603652,-0.039602038,-0.0768465,0.035203826,-0.006816358,-0.044895645,0.016519114,-0.011851004,0.026589755,0.0037976503,-0.059369437,-0.0017422951,-0.032153014,0.008241569,-0.018491669,-0.034464654,0.08193334,-0.060010627,0.033046007,0.028918147,-0.038564503,-0.012816029,-0.09260625,-0.037036512,-0.02333069,0.009323335,0.005097243,-0.037780765,0.025798677,0.061763402,-0.011863524,0.022128878,0.003244515,-0.036543917,0.017242188,0.007863895,-0.07702374,-0.06967366,-0.055840526,0.033291597,0.03041477,-0.014187359,0.008792515,0.0132163325,-0.01979321,-0.021676375,-0.023342514,-0.012465282,0.004166992,0.041223638,0.00021170739,-0.010732586,-0.009115663,-0.02152312,-0.009643942,-0.036146004,0.050915252,-0.026316429,-0.049863093,-0.044442855,-0.04130335,0.05897462,-0.004925055,0.016779598,0.090269394,0.022952696,0.01587918,-0.025088131,-0.005904262,-0.039922904,0.0575041,0.009795097,-0.010902625,-0.014526457,-0.02290843,0.013795176,-0.009590428,0.014152506,-0.010554429,0.012774999,-0.0055901925,0.001477147,-0.010433032,-0.029992132,0.04833047,-0.0029090773,0.04087115,-0.0090991305,0.03559093,0.010916646,0.019217603,0.023938293,0.0390432,-0.008987546,0.005806065,0.0064946944,-0.039457157,0.041745022,-0.028180992,-0.036117055,0.053845633,-0.048328627,-0.037153743,-0.06249566,-0.007626574,0.0389623,-0.0016307904,-0.062268134,0.047803834,-0.024762059,0.06661518,0.034826074,-0.008941077,-0.045353815,0.015534421,0.017904265,0.045759976,-0.012512725,-0.02241031,-0.01259559,-0.026800748,0.039000537,0.014267912,-0.042274013,-0.002737838,-0.0032812168,-0.019728728,-0.046396118,0.034733742,0.011373255,0.012028207,0.005906372,-0.0035161788,-0.013193945,0.007886184,-0.036249623,0.03850798,0.0042153695,0.029005175,0.033930454,0.1073209,0.018171769,-0.0040344396,-0.058378197,-0.06765599,0.033935167,-0.019221751,-0.015093878,-0.02013282,0.017837469,-0.008523897,-0.018866226,-0.0058474545,0.013408474,0.010642423,0.005603521,0.011508718,-0.014304888,0.010123075,0.008918003,0.02427456,-0.030527899,-0.009121557,-0.035501797,-0.031543344,0.006274224,0.034542076,-0.019637404,-0.0023640138,-0.017857634,0.050587174,-0.0034911642,0.008032458,-0.055276554,-0.004378849,-0.01614186,-0.016033411,-0.016605215,-0.023513699,0.007309187,0.015552157,-0.018694475,0.021799408,0.019833291,-0.0025545354,0.007361483,0.021103906,-0.0012394293,0.0010167705,-0.025089787,0.0028957142,0.031523805,0.02204113,-0.021429429,-0.029689252,0.018268041,0.020906614,-0.047109377,0.0053608427,-0.008770138,0.0019947556,0.053619143,-0.03923571,0.0070855124,-0.03442798,-0.015504742,0.0284442,-0.005100805,-0.009908415,0.009605769,0.024159998,0.08849397,-0.05376436,-0.0429485,0.02360433,-0.028786097,-0.016238365,-0.012908205,0.03316074,0.007131907,0.01162137,0.010467654,-0.018146813,-0.014429266,0.00023914498,-0.003967246,0.019493263,0.013979577,-0.0021375946,0.0056959437,-0.07693433,-0.02875122,0.025370821,0.00033196344,-0.0045760754,0.039891332,0.030185778,-0.015075018,-0.014751469,0.08492086,-0.008308279,-0.009734745,0.041412856,0.0013134026,0.026612192,0.059770495,0.008384833,-6.4191096e-05,0.01660381,-0.0255711,-0.0059696184,-0.019024232,0.012853029,-0.04618065,-0.015392165,-0.011701637,0.053463366,-0.021796,-0.041522622,0.009409813,0.03733207,-0.13688354,0.03539539,0.04247515,0.0062018572,0.0042499527,0.033688456,-0.029473532,-0.009816452,0.00043042045,-0.015490726,0.03881096,-0.04685981,-0.014964006,-0.008528278,0.0021768971,0.025020484,0.013748326,0.028702602,-0.024926156,-0.008019725,-0.008196927,-0.027639678,0.016826749,-0.009930569,-0.03353112,0.0233568,0.006621296,0.031779587,-0.027604101,-0.028073166,-0.001970046,0.025566926,0.0220515,0.016502382,-0.007694406,0.007328294,0.0427203,0.009341353,0.05056575,0.023432117,-0.002518789,0.06594757,-0.011600452,0.011180026,0.01702493,-0.024579417,-0.0016968123,0.0034844303,0.006697845,0.002855832,-0.00038465488,0.006178564,-0.022879157,-0.0526873,-0.061641358,0.0045856577,0.016933972,0.033257995,0.02021872,-0.002178985,-0.019579308,-0.037934616,0.024832696,-0.016356401,-0.01910536,-0.012443476,0.02568897,-0.016858306,0.032988362,-0.02998114,0.0130043905,-0.019417934,0.043250233,0.028146053,-0.0119253425,0.025963709,-0.006209446,-0.0037442464,-0.017489815,-0.0829196,0.0039802836,0.010443853,-0.020629503,-0.007911775,-0.0405922,-0.018195523,-0.010778499,-0.03215433,0.051243164,0.21206254,0.004538224,0.02420806,0.015299303,0.057887815,-0.007774831,-0.052804068,-0.0026194525,0.008090118,-0.024206962,-0.016280951,0.003360182,-0.0019988592,-0.010284531,-0.016337853,0.0073775146,-0.049570374,0.013147868,0.06199847,-0.016213212,-0.020677561,-0.049123712,-0.021271702,0.0392372,-0.0248981,0.021384249,-0.022470087,0.012620525,0.00889894,-0.01274357,-0.03181424,-0.022408932,0.00028240314,-0.013908478,-0.055487927,-0.0076522953,-0.034880616,-0.056239292,0.077621,0.036422294,-0.043696452,-0.03301992,-0.0060608927,0.007855282,0.0009479031,-0.05846346,0.041231774,0.00089708157,-0.039603382,0.00038658138,-0.002414383,0.014146733,-0.053161062,0.0519065,0.01266186,-0.008813007,-0.025997996,-0.015043651,-0.011595769,0.06366978,0.015373134,-0.01138294,-0.030991524,-0.014289033,0.04397777,0.000774473,-0.0027961603,-0.020630965,0.06998721,0.050099537,0.004380801,0.032510262,0.041811965,0.023007428,0.01008729,-0.0014924402,0.024831278,-0.01764371,0.019137219,-0.02112433,-0.029763307,-0.008977535,-0.01678935,-0.022358205,0.020339431,-0.035992913,0.047126766,0.019622065,0.044277437,-0.018804679,-0.0030526996,-0.0296365,0.057002332,-0.0339016,-0.04207629,-0.01722158,0.021413108,-0.011574741,-0.03570025,-0.00076036784,0.019839851,0.0022018724,-0.009475401,-0.04723679,0.03437604,0.0042757336,0.013068816,-0.016460087,-0.027191568,-0.049257904,-0.021874914,-0.008809428,0.02104522,-0.036370832,-0.013319179,0.00654293,0.017834835,0.031737305,-0.008791292,0.021844931,-0.005018684,0.017231796,0.037783697,-0.026216865,0.017944595,0.0075183627,-0.00858385,-0.01674954,0.019160736,0.04773528,-0.0065835547,-0.012883237,-0.10122375,0.014714844,0.086707465,-0.011264341,0.0005469128,0.045791272,-0.026651895,-0.059410054,0.0050981725,0.065133944,-0.017146697,-0.03824203,0.027916174,-0.011895948,-0.045768652,0.02543221,-0.044371616,0.06615319,0.043904196,-0.021121124,0.046958335,-0.025331777,-0.030800523,-0.055227537,-0.022987409,-0.024057465,-0.008412883,0.00081824366,0.015048767,0.014056893,-0.008043523,0.075909704,0.03936958,0.0023101054,0.031816974,0.009503802,-0.021861903,0.01958319,-0.01119561,-0.044577826,-0.06855877,0.021867981,0.032765083,0.032213014,0.010115323,0.025821242,-0.028400416,0.013812707,0.002572625,0.019804586,-0.010977878,-0.053592138,-0.004352486,0.012055327,-0.03647715,-0.019733733,-0.03365755,-0.035171647,-0.022641523,0.081364304,0.0012586475,-0.017419731,-0.0013870456,0.0037680666,0.053411994,-0.012632964,0.0067106816,-0.04298793,-0.008062458,0.0075827967,0.039499708,0.021289067,0.004373879,-0.025868153,0.027682194,0.04289174,0.011484373,0.02344705,-0.030642375,-0.0044193026,-0.021914536,0.02229287,-0.002993125,-0.0048734234,0.025467452,0.022512795,-0.023043765,-0.06179606,-0.015210157,-0.020233538,0.015774582,-0.005173168,-0.01913134,0.006144551,-0.0034179452,0.025665196,0.035481557,0.022955708,-0.0056166016,0.0035940479,0.032360848,0.017629562,0.01426337,-0.033783756,0.022609992,0.031236617,0.013998771,-0.02408039,0.0042194007,-0.010399468,0.0071195206,0.017062616,0.022487164,0.016273059,-0.050793312,-0.048112918,0.034287825,0.02926956,-0.027677732,-0.010121249,0.053853106,-0.03284902,0.023415383,0.010003933,0.011854999,0.03007132,-0.05691845,-0.016320743,-0.021382626,0.05139226,0.0051508383,-0.05690465,0.035159636,-0.051363923,0.04321531,0.0032373853,-0.0018814402,-0.011011151,0.02298679,-0.019950507,-0.030503422,0.031602964,0.047561653,0.009610278,0.0097406525,0.019060759,-0.035732158,0.013144367,-0.06409929,-0.022752536,0.013345552,0.028333025,0.023370344,0.04217788,0.010157694,0.0058041867,0.014024597,0.0150353415,0.007258961,0.02022982,-0.044237874,0.02953496,-0.007645761,-0.016169552,-0.016738104,0.046526182,-0.029387236,-0.03713924,0.0031683405,0.00095599814,-0.025406895,-0.022781769,0.0052301157,-0.0134204505,0.0044268537,-0.05325571,0.031925563,0.006094078,0.01735246,-0.030833365,0.013494511,0.014979285,0.020736696,-0.03895498,0.01969243,0.005333868,0.032461617,0.009099163,-0.02084267,0.009197194,-0.017045949,-0.0033118576,-0.025700165,0.019353168,0.071531154,-0.01966757,-0.04671341,-0.00013897677,-0.01323162,0.02115871,-0.017300133,-0.003560609,-0.00463647,0.003534752,0.05612032,0.018779363,0.013026304,-0.008407416,-0.046920013,-0.032723784,0.07816789,-0.017010253,0.04585063,-0.07799975,-0.021755707,-0.0135612935,0.011591768,0.00244623,-0.0034958269,0.019560084,-0.015548023,-0.0609631,-0.012365672,-0.070729114,-0.018354425,0.0019405837,0.03890206,0.040478185,0.01651237,0.013814409,-0.015229141,-0.015935874,0.0015123577,0.023143573,-0.0002391202,-0.021793418,0.02919905,-0.024570588,-0.008745647,0.018174587,0.0092518,0.017799139,0.00016289353,0.02221772,0.018619535,0.0134832105,0.012556944,-0.0002985322,0.008778023,-0.03135131,-0.026524238,0.0011079817,0.030978383,-0.010562977,0.016179282,0.0066110613,-0.007972803,0.0073226984,-0.031723466,-0.048493244,-0.033972494,0.014313426,-0.12899654,0.010587386,-0.021823568,-0.012398952,-0.037204675,0.017471012,-0.019015862,-0.01446024,0.029955085,-0.032661825,-0.015918938,-0.012052436,0.07688759,-0.011068287,0.008857603,0.045647036,-0.03363373,-0.00052253186,0.0242734,0.04287619,-0.006787322,-0.023029922,-0.012050265,0.028375996,-0.012187968,-0.034419376,-0.00032657565,-0.0071932,-0.03755151,0.02198761,-0.006698674,-0.070913166,0.020653317,0.055858728,0.027957292,0.015773503,0.021598674,-0.014574217,-0.037789945,0.009441637,0.009790171,0.012055862,-0.03228496,0.024235375,-0.0066462904,0.057899017,-0.02591754,-0.028104246,-0.03427755,-0.019452991,-0.02627935,0.009033847,0.010507944,0.027902374,-0.0011171673,0.01675555,-0.028332269,0.005327972,-0.0137566915,0.03512601,-0.023788257,0.039264005,-0.033767693,-0.04265003,0.029552074,0.035596695,-0.002592419,0.041852433,0.035850354,-0.04030115,-0.04072715,0.02675959,0.03587254,-0.01055607,0.008945142,-0.028744847,0.05870181,0.0037709556,-0.04191133,-0.013118216,-0.03610324,0.0039948593,-0.05891245,-0.04598596,-2.0405448e-06,0.010871492,0.006681063,0.020722782,-0.031524576,0.010364251,-0.031266898,-0.039595816,-0.012509396,0.059408095,0.005878926,0.033969063,-0.012509314,-0.022314627,-0.015445353,-0.038934346,0.0022919795,-0.037225053,0.007597506,-0.016530653,-0.0032205803,0.037829857,-0.016965788,-0.031827804,-0.018003136,-0.02084676,-0.03672849,0.011365945,-0.023226684,0.017258171,-0.016057698,-0.021710945,-0.028015163,-0.017410778,-0.01702111,-0.0036397693,0.011645286,-0.047885787,0.041393276,-0.030160895,0.018198147,0.058959804,0.053730458,-0.009217282,0.007746439,-0.030268379,0.009206118,-0.0016970718,0.025730642,-0.027648233,-0.0006186872,0.009721226,0.0037227594,0.036420174,-0.057555582,-0.020220192,0.003972487,-0.0017184941,-0.009337489,-0.029700486,-0.0073054824,-0.018950924,0.04652588,0.0060359314,0.0312739,-0.05708619,-0.007414967,-0.0046541234,0.0013168559,0.06979606,-0.03714855,0.00331563,-0.045521636,-0.026843358,-0.0027433354,0.014742174,-0.04547431,-0.03568356,0.017918553,-0.041963063,0.004894317,0.11681561,-0.034870323,0.02817404,-0.013978391,-0.0012061248,0.021068431,0.029170347,-0.010858218,-0.0065280576,0.03054446,-0.016628148,-0.031284787,0.02277658,0.017644009,0.00460386,-0.008646497,0.005807821,0.064418204,0.0064068255,-0.00088230806,0.060804278,-0.029378463,-0.014802689,-0.010405628,0.0015730256,-0.0045307036,0.01693007,-0.00142301,0.062808655,0.01635501,0.015035299,0.015217613,0.04814347,-0.009287325,0.023302453,0.01827982,-0.0017188324,-0.0019144516,-0.06246605,-0.059706446,0.005493898,0.04659347,0.008547907,-0.01858044,0.05005906,-0.016948314,-0.0012450775,0.0049302247,0.057931077,0.005298633,-0.0027848894,0.04073339,-0.007202263,0.026433313,0.011970441,-0.02275433,0.05311631,0.001321733,-0.030215643,-0.036017668,-0.037434377,-0.02994274,0.02937926,0.014206503,-0.003411382,0.008719385,-0.047979895,-0.042410333,0.051475946,-0.039148904,-0.0009935602,-0.0140304165,0.010214167,0.008473462,-0.00034719968,0.019482259,0.0016070384,-0.020151187,-0.023375707]
510300	Office Supplies & Stationery	Office Stationery and Supplies	expense	[-0.037982695,0.027220482,-0.03518512,-0.00808092,0.018647715,-0.042648982,-0.021813069,-0.0046810308,0.06763894,-0.03226758,0.03679675,0.00821622,0.023166943,-0.024212092,0.017704798,-0.024702225,0.00028922944,-0.004544442,0.0012175095,-0.016379097,0.021148773,-0.014728559,0.06151045,0.040028825,-0.0059511424,0.015458525,0.039474465,0.009202478,0.046012398,-0.030253135,-0.01908511,-0.028382007,0.050606817,0.011130812,-0.0119135715,-0.016585127,0.005004675,-0.02151187,-0.06835798,0.033177268,-0.02660854,-0.016864266,0.02506568,-0.03483055,0.009705068,0.0017616458,-0.026337605,-0.01547712,-0.04604422,-0.029852549,-0.006226709,0.0092743775,0.06979069,-0.025674324,0.021753296,0.025600359,-0.08423367,-0.03064845,-0.084115274,-0.04502036,-0.047158822,0.009955559,-0.013696777,-0.0025999155,-0.0069683306,0.0330001,-0.025038393,0.012738973,-0.0041248156,-0.0058895815,-0.0013505192,-0.0040639555,-0.03987344,0.01173217,-0.087273374,0.015187429,0.02397283,-0.035240978,-0.01808118,0.022687873,-4.5971312e-05,-0.03243687,0.010830216,-0.02544668,-0.0114707565,0.025453495,0.000900042,-0.010902952,-0.049969576,0.02851668,-0.02593272,0.013541608,0.012805737,-0.014645617,-0.058574226,0.005805786,-0.016860362,0.034779668,0.014977742,-0.0072596874,0.03285893,0.034084678,0.026060719,0.014783947,0.044632446,-0.011040518,-0.010770269,-0.003730983,0.049181588,0.013336321,-0.010255747,0.048276205,0.03861223,-0.0004139333,0.011901404,-0.028971033,0.0009656664,0.015432374,0.04720252,0.0036622991,0.021165323,0.015236706,0.014472387,-0.05314576,0.010002994,-0.028411472,0.04464939,-0.0023517096,0.05273553,-0.02192031,0.021086792,-0.013793566,-0.062175065,0.025095537,-0.03290244,0.013400848,-0.001638271,-0.044897314,-0.013211757,-0.05984474,0.011942452,0.0253682,0.00015336937,-0.022495411,0.016992444,-0.0003053967,0.046239223,-0.006166783,-0.0068356334,-0.020108066,0.024712121,0.0300527,0.017489752,-0.006510009,0.023668878,-0.022289807,0.004516483,0.06841144,0.021296889,-0.036781162,-0.0046568024,0.005524031,-0.0070905993,0.0067298715,0.047248203,0.026371945,0.010616822,0.04003571,0.020725306,0.02167513,0.077338144,-0.07357278,0.02294335,-0.002552603,-0.0011375783,0.0024552795,0.035253152,0.010511094,0.036685184,-0.04593474,-0.031779833,0.0014218377,-0.06732921,-0.035415716,-0.028685054,-0.003812809,0.005407457,-0.05413572,-0.0048514334,0.005326943,-0.003705957,-0.020081958,-0.0024142445,0.01676967,0.047294855,-0.004451412,-0.0082541965,0.008520367,-0.019432973,-0.026800068,-0.026682852,0.04709202,0.013890459,-0.0059854873,-0.055889323,0.008043102,0.037963692,-0.049253143,-0.007977899,-0.044570107,-0.0047277394,0.0017450354,0.04059181,0.009151501,-0.014847229,0.03110851,0.043992177,-0.004342735,-0.029124402,-0.032531872,0.027820501,0.03431215,0.03273153,0.048204962,-0.00077024347,-0.008006527,0.0289563,0.027785826,0.016436528,0.014256712,-0.014105987,-0.013066835,0.0139595745,0.0014325724,0.0018070398,-0.011611009,0.011990662,0.0516152,0.03516764,0.006495745,-0.025388232,-0.0014046456,-0.0044799177,-0.032930523,-0.012453905,-0.021285564,0.024459291,0.0053899162,-0.0021870518,0.009055378,-0.0062747416,-0.002951964,0.022285376,-0.000942225,0.009251145,0.0075645205,-0.016235944,0.008246535,0.03928611,0.010656307,-0.00888675,0.0068669277,-0.010474635,0.016257858,0.022089222,-0.03460807,-0.02476239,-0.008811082,-0.011563645,0.007820341,-0.0524633,-0.030661358,0.035187535,0.026683426,0.038891803,0.07050453,-0.021100815,-0.021937814,0.023989249,0.0037038168,0.04035283,0.060924996,0.0040119253,0.01719938,0.0089275455,0.01601676,0.0287116,-0.013193192,-0.004256936,-0.038412757,-0.020059152,-0.023807516,0.04381995,0.054112654,-0.021548478,-0.0039090496,-0.023866154,-0.13202298,-0.040833484,-0.026370784,0.04258967,0.0012327571,0.0013235537,-0.040020462,-0.03173529,-0.031135038,-0.0073279254,0.012618156,-0.05662629,-0.06276676,0.030254818,0.00070612767,0.014783685,-0.00012630335,0.03616783,0.013263053,-0.014652657,-0.036520097,-0.047441497,0.04103482,-0.03342209,-0.015331814,0.013500012,0.043810196,-0.047015857,-0.033157967,-0.016947422,-0.015114479,0.0058868565,0.013551715,0.019592904,-0.00993972,0.018272024,0.035996012,-0.0389418,0.00094328955,-0.011945429,-0.013709875,0.06577167,0.013402756,0.013217952,0.014985097,-0.022544011,0.017618133,-0.002876065,0.007413383,-0.053763017,-0.037901286,-0.0019354592,-0.021318743,0.013450846,-0.04628617,0.005308707,0.01328119,0.030213445,0.04842505,0.020454193,0.024787037,-0.050587013,-0.018528894,-0.03654318,-0.018354177,-0.029813595,0.012864423,-0.01849963,0.01690475,-0.022507202,0.032083016,-0.010597897,-0.017503908,0.01263009,0.0041340063,0.027221104,0.026598154,-0.03965821,-0.0044178963,-0.09085215,0.0001600261,0.011410226,-0.0022069095,-0.00415747,-0.029188244,0.016677976,0.029298965,-0.025511624,0.050919823,0.20954862,0.003502672,0.005507701,-0.03850548,0.044030394,-0.0013356311,-0.011125241,0.029958352,0.042817112,-0.044397946,0.016279466,0.029330108,0.024750456,0.027780423,0.047973435,0.039641228,-0.038315862,0.013418177,0.08479956,0.032748956,-0.03337787,-0.06969623,-0.008890594,-0.004469659,-0.021169983,-0.021418149,-0.021123534,0.06478757,-0.010550559,-0.0010353101,-0.054150343,-0.019362887,0.019939017,-0.02150844,-0.0014942111,-0.044911373,0.027298471,-0.009566184,0.022873973,0.04423088,-0.045808703,-0.045630284,0.054033868,0.025432292,-0.07055875,-0.017891882,0.03132069,-0.020345526,-0.0095785735,-0.022850275,0.03782473,-0.013158542,-0.042023297,0.010780859,-0.0034093705,-0.02065468,-0.043886892,-0.067650616,-0.050221,0.094059065,0.01616832,0.0061618458,-0.04190892,-0.0071400157,0.03993606,-0.0027685713,-0.02261346,0.01995453,0.021437343,0.035426214,0.050207473,0.046786997,-0.010175021,0.006373214,0.035183888,0.0135120815,-0.0125278635,0.043374967,0.020600466,0.04784168,-0.02570552,0.013244976,-0.012281788,0.021652257,0.033413406,-0.0013954982,-0.00065821403,0.025412578,0.037584826,0.019643197,-0.033864163,-0.00667691,0.016927868,-0.0012196215,-0.035668924,-0.0119311195,0.020804383,-0.009097866,-0.030126745,-0.030516053,0.05872543,0.002282858,-0.014839737,-0.092480704,0.0405497,-0.027556356,-0.0009580346,-0.034337446,0.037796304,0.03958434,-0.05342868,0.039763674,0.021559935,0.0084325215,0.033708666,0.020786267,-0.008698394,0.009411189,0.0020714083,-0.0028394903,0.0454541,-0.005090395,0.01175897,-0.039020907,0.039660186,-0.014742588,0.015500053,-0.03909961,-0.0581362,0.049767386,-0.029735416,-0.036108904,-0.030514756,0.016379898,0.06040706,-0.022208372,0.021560412,0.031474832,-0.018252501,-0.019990163,-0.028344372,0.032909025,-0.00059290574,0.006276763,0.026844682,-0.0025266206,0.0031726,0.033841062,-0.03205174,0.0389973,0.033206604,0.038105793,0.0040268847,-0.013278214,-0.002549115,-0.029745355,0.0057153725,-0.0034541895,0.05257562,0.0017784945,0.039122827,0.016786652,0.021678993,0.056711398,-0.004735764,0.026382124,0.006798846,-0.027958443,-0.033717655,0.01285955,-0.03079242,-0.08006671,-0.033247434,0.042752884,0.03577042,-0.014040892,0.017279325,0.02006685,0.012349624,-0.006010663,-0.0064864974,0.04781903,-0.015071438,-0.055766817,-0.035778515,0.024253283,-0.028090725,-0.0023391233,-0.018881507,-0.022862334,-0.0038305814,0.036944665,0.008981255,-0.012878134,0.012520052,-0.0032055248,0.06277467,-0.023893965,0.047112305,-0.033505153,-0.033319958,0.0021987841,0.018415395,-0.008635826,-0.024006745,-0.048115585,-0.031544805,0.06676985,-0.013644969,0.0065076184,0.0076226126,-0.0005963912,-0.039075527,0.046103634,0.008988567,-0.015199538,0.053135183,0.056474935,0.035307642,-0.083992496,-0.012019666,-0.006718695,0.00039297275,-0.036346998,-0.01301421,0.02107216,0.015777593,0.019418158,-0.022095421,-0.021144932,-0.0026462094,-0.031778775,0.03315774,-0.038251657,0.02917901,0.017777119,0.032834023,0.013785353,-0.02772609,0.02395976,0.0016661126,0.001177379,0.03118638,0.04972027,-0.02168464,0.029313857,-0.053958308,-0.01621049,0.03158908,0.044450734,0.013194516,-0.036583036,0.016373988,-0.038698614,-0.022516867,-0.022895882,-0.016074017,-0.04120563,-0.046308566,-0.011844547,-0.011541309,0.079635605,-0.0084386775,-0.008504757,-0.022030178,-0.03933416,0.018648062,-0.060042657,0.0052590817,-0.0008647742,-0.017792193,-0.021497438,-0.022419708,0.008887596,0.08866021,-0.0035612818,-0.009621386,0.044594493,0.0071164556,0.032124657,-0.021670172,-0.069653384,-0.021501653,0.021041559,0.027241224,-0.004685683,0.018583603,0.016507838,-0.036900125,0.031494565,0.008827149,-0.028884573,-0.029046027,0.051632605,-0.033973634,-0.020103619,-0.04455937,-0.0027578173,0.0015072277,-0.017225854,-0.0099750515,0.037759047,-0.001726143,-0.010608851,-0.035830773,-0.0064955666,0.043278776,-0.018321319,-0.036096264,0.011065343,0.01953229,-0.008361445,-0.027683312,-0.019726152,0.06177757,-0.013361021,0.027861632,0.009810706,0.024378885,-0.007649951,-0.028193552,0.001992399,-0.034029204,-0.03791628,-0.028433831,0.0024735953,0.019833943,-0.01716373,-0.03192056,0.04246843,-0.038342852,0.04598759,-0.034836944,-0.03416705,0.011612166,-0.006498365,0.050302763,0.0077825147,0.02425202,-0.022968637,-0.052553136,0.0006763551,0.035550836,-0.016739527,0.039243177,-0.035093773,-0.049272116,0.03818255,0.027296335,-0.028257478,0.009769964,-0.060374066,0.00070495135,-0.0149136465,0.025449572,-0.028190505,-0.01725025,0.007826423,0.010611199,-0.013007811,-0.032049708,0.00010969876,0.012786829,0.014299268,-0.017838448,0.021522924,0.018097064,-0.048148807,-0.029437201,-0.027837165,0.0007050515,-0.05362721,0.01922263,0.03578611,0.00042270482,0.040034875,0.009203382,-0.025212463,0.034857433,-0.006996187,-0.04448483,-0.057321128,0.01587166,-0.020167422,0.048570894,-0.053921983,-0.014390456,0.01009275,0.021440629,0.030493366,-0.007403164,-0.007597479,-0.035645097,0.0110345585,-0.120250605,0.027075473,-0.017370116,0.0011518933,-0.002797674,-0.008821754,-0.020748507,-0.0061521623,-0.010264123,-0.038412184,-0.022524066,-0.011534357,0.01866358,-0.011195423,0.018733164,0.046352394,0.011106309,0.0037749568,-0.031248838,0.0791262,-0.0065094945,-0.023459595,0.008290155,0.035610046,-0.0063891257,0.030842174,0.031988308,0.020965176,-0.05641931,0.033426493,-0.0015689259,-0.053930704,0.036500085,0.0055610943,-0.018378152,0.052269313,0.020702263,-0.020201769,0.024168279,-0.00590006,-0.027944474,0.015982674,-0.0012428496,0.027656298,0.029827878,0.03571268,-0.03334842,0.020195488,-0.005816607,0.023591075,0.009042926,-0.029232142,-0.043988306,0.035870425,-0.019067788,0.0038393165,-0.07138787,-0.006528116,0.0033955276,0.04611341,-0.022123408,0.071857065,-0.010294119,-0.032198433,0.0048732692,0.009532303,-0.0014050989,0.035654005,0.04711574,0.00082158326,-0.013526597,0.037081208,-0.018672029,-0.045547158,0.017343674,0.019791035,0.022522625,-0.06869467,-0.034380812,-0.002540773,-0.013502982,-0.04969248,-0.026018728,-0.03161855,-0.006413834,0.016791912,-0.028616365,-0.026670538,-0.049934544,0.006757628,-0.041583154,-0.028922845,-0.014930892,0.048290253,-0.016745638,0.020129042,-0.031578172,-0.0016235776,-0.025504876,-0.04331922,-0.035050023,-0.041975122,-0.016508335,-0.012434527,-0.03245601,0.0011971986,0.043487627,-0.04448345,0.024792977,0.026974635,0.0037320564,-0.004049851,-0.037445255,-0.01630126,-0.045728162,0.028880013,-0.014646096,0.009418742,-0.018655285,0.010865466,0.037234772,-0.012902935,-0.01229394,-0.043213084,0.06080359,-0.009437466,0.0407818,-0.027807387,-0.012519739,0.048129637,-0.0007780103,-0.028757567,-0.04291313,0.0066250777,0.013678582,0.013813369,-0.015932795,0.036197618,-0.06343819,-0.019166721,-0.018811403,0.030887263,-0.03540069,-0.02075687,-0.013994415,-0.0047807265,0.008480911,0.01754306,-0.005755026,-0.05340983,-0.0057436083,-0.03149083,0.0056160917,0.01901093,0.029258,-0.020114284,0.002837066,-0.0010671922,0.015232016,0.02622154,-0.0069056144,-0.02696993,-0.007868111,-0.0098612225,0.008843508,0.06608803,-0.012550153,0.011057411,-0.029313363,-0.008474499,0.013431996,-0.019516136,-0.028410388,-0.045537785,0.046408694,0.00047225668,-0.008350492,-0.017305901,0.00032318183,-0.03077598,0.025131928,0.001021753,0.036533676,0.05582249,0.01909524,0.030688899,0.017011324,-0.015524287,-0.019226609,-0.05024927,-0.021028347,-0.00932705,0.021719197,0.025019372,0.007447614,0.019858927,0.014894525,0.06635619,-0.017240511,0.04769569,-0.023894982,0.015849201,-0.019350985,-0.035124127,-0.021818018,0.01858559,0.037084702,-0.030473975,-0.026661377,0.0165535,-0.03418945,0.007665141,0.047145277,-0.0273312,0.026514558,-0.015475511,0.025188806,0.011686434,-0.01569051,0.023770059,-0.017368997,0.021129224,-0.042537495,-0.014860315,-0.03278602,-0.026750218,-0.0006606912,0.0150817195,-0.011673536,0.007994904,0.025962576,-0.059092924,-0.03450681,0.016465915,0.0109466575,-0.011676771,-0.043926872,0.003203676,-0.01735181,-0.042882543,0.025914062,-0.001534184,-0.05468619,-0.0030738716]
510400	Entertainment & Client Meal	Client Entertainment and Meals	expense	[-0.08687912,-0.030504044,-0.0032208785,-0.008136582,0.0017891357,-0.029773783,0.035429984,-0.022017764,0.0011844104,-0.022086537,0.06761751,-0.027418569,-0.029091949,0.00085906644,0.019982472,0.0029525715,0.027128536,-0.019756835,0.005430223,-0.034366377,-0.022645276,-0.006491965,-0.012930656,-0.0076353755,-0.0005540022,-0.013340613,-0.039670695,-0.011498348,0.023420228,0.0059959884,-0.0086469585,-0.026307747,0.028765662,-0.027720155,0.003140031,-0.05329764,-0.0047505586,0.00251072,-0.04867088,-0.0011435981,-0.0063837846,-0.030916091,0.013865769,-0.028781218,0.016775386,-0.0126281595,-0.017802728,-0.012579212,-0.042747527,0.020708758,-0.007351504,0.013518732,0.06755847,-0.03419095,0.021567237,0.08052891,0.008481227,0.0008187149,-0.068441525,0.045233715,0.0030598333,0.012123286,-0.003953213,0.02146576,-0.012370443,0.030757176,-0.0034430174,0.029202107,-0.008370377,-0.028430803,0.011454767,-0.02010733,-0.034367062,0.00013941208,-0.074029654,0.039073154,0.027028853,0.0090790605,0.0032673706,0.00782984,-0.036622442,-0.049082767,-0.023991473,0.008865914,-0.0036500813,0.020130182,-0.0055825687,0.03305065,0.012340657,-0.008285066,0.0025440194,-0.0031578655,0.02278498,-0.016533235,-0.06056065,-0.03240688,-0.05375848,0.026171796,0.03494021,0.0051044696,0.030626884,0.012115977,0.017318917,-0.0016196648,-0.039121326,0.014904711,0.018213145,0.027932731,0.013595512,-0.015031703,-0.018902577,0.017571641,-0.018363828,0.033909593,0.026021129,-0.006594448,0.009406445,-0.044170946,0.023506282,0.0142271435,0.01800428,0.0018120565,0.002999834,-0.021041758,0.04152307,-0.016476301,0.03828966,0.020323468,0.04284923,-0.009939888,0.042691402,-0.008306627,-0.00082180905,-0.022064436,-0.014710697,-0.0075883027,0.0155338915,-0.010937743,-0.03938999,-0.023043297,0.01678522,0.044947475,-0.02568693,-0.0054110475,0.021217288,0.005400332,-0.0044270847,-0.026357677,0.011902369,-0.025900982,0.00642546,0.028445745,-0.014512455,-0.028911147,-0.06236951,-0.021206025,-0.032398794,0.034792777,0.023425447,-0.034024782,0.028552273,0.017167335,-0.017770734,0.004270797,0.014572043,-0.011547697,-0.010460074,0.009207112,-0.014052978,0.007874424,0.00685488,-0.06255693,0.006087469,-0.0019937684,0.0046964767,0.020737387,0.045737095,0.037665363,-0.019716443,-0.040647496,-0.09080724,-0.014898833,-0.02769959,-0.021160515,0.021522924,0.034011852,0.0018629117,0.0023431065,0.015963923,0.03145839,0.00624806,-0.008162002,0.035241116,-0.039957568,0.042588092,-0.016005237,0.010457085,-0.051741965,-0.019818163,0.011410192,-0.072642386,0.0041716853,-0.028111052,-0.0038712146,-0.022614053,0.009360337,0.017636996,0.028717158,0.01730474,-0.01708961,-0.02778492,-0.00031598797,0.03610562,-0.03286786,-0.02803922,-0.020120574,0.05190018,0.014173162,0.031863216,0.014729113,-0.01936512,0.007850097,0.027716212,0.03608863,0.047081426,0.011610325,0.020926345,0.045833442,-0.010842917,-0.022812733,-0.01853033,0.012150704,0.010006456,-0.014562293,0.020505063,0.08171906,0.010128076,0.042600613,-0.014678235,-0.0034857902,-0.0073972293,0.015831362,-0.026144333,0.03227254,-0.00670694,0.0041355556,0.03629442,0.10585658,-0.04187279,-0.017439373,-0.016005963,-0.032496504,-0.01905936,-0.0037441053,-0.002808055,0.006421241,-0.022864036,0.014235075,0.034061197,0.02130193,0.016198153,-0.06568103,0.02868408,0.026815254,0.023592792,0.015317887,-0.069063954,0.0029855254,0.01873942,0.036467586,-0.023449881,-0.011487416,0.024749193,0.04279603,0.012980145,0.07982549,0.0023305342,-0.011368726,0.052728564,0.018612623,0.0008549069,0.042863805,0.0005083693,-0.035993733,-0.0048975153,-0.0034873325,-0.03934486,0.0064443788,-0.020107834,-0.06267539,-0.01139144,0.012171042,0.08167567,-0.005633613,-0.039045915,-0.019555828,0.008340787,-0.15276845,-0.010024293,0.0121197,0.01250824,0.002062277,-0.0046721315,-0.04140417,-0.05456998,-0.03554426,0.030628577,-0.008907208,-0.06181296,-0.027568206,0.004758109,0.009242578,0.019983193,-0.028151281,-2.1514546e-05,0.015557921,-0.026946917,0.0065673226,0.0077660745,0.04707125,-0.034499597,0.0023427233,0.028349243,0.032333396,-0.030580191,-0.013046962,-0.021249136,0.012311055,0.04661977,0.00393204,0.04873253,-0.003272942,-0.030261401,0.02066378,-0.04548522,0.052018728,0.02102575,0.008446603,0.01788916,-0.04468968,0.02074534,0.020147191,-0.030853588,-0.013355265,0.019974014,0.027014194,0.008686983,-0.014688593,-0.006017596,-0.011889279,-0.034722682,-0.044277146,0.007090992,-0.062211182,0.055295076,-0.0111599,-0.016145475,-0.013509907,-0.044593737,0.007863542,-0.004654864,-0.029038947,-0.036269903,-0.04178643,0.019332206,0.023394696,-0.021921093,0.024112014,-0.0026027623,-0.01815537,-0.037510443,0.010183047,0.028186448,-0.02446014,-0.014496825,-0.013938621,-0.08396259,-0.07127757,0.05079181,-0.021497643,-0.0053107524,-0.07003332,0.0154899545,0.016021453,-0.020376239,0.022163298,0.1870877,-0.00992642,0.04693117,0.033922724,0.040119994,-0.0052341954,-0.034670804,0.048414927,-0.023264715,-0.042414438,-0.010415776,-0.017466,0.005582493,0.029133905,0.021171922,-0.004571796,-0.0903809,0.025029276,0.064749345,-0.04149772,-0.02021668,-0.036935125,-0.018782968,-0.009347599,0.007619641,-0.004949105,0.01572029,0.06515023,-0.028262112,0.01637798,-0.039117813,0.012101767,0.033837087,-0.0053053116,-0.019230751,-0.015245588,-0.016796632,-0.010043143,0.026502887,0.038394075,-0.008627891,-0.035517905,0.040407054,-0.03448171,-0.03573376,-0.041708585,0.020741584,-0.005776498,-0.037290182,0.003974275,-0.014916635,0.00725335,-0.036925986,-0.0062314006,0.033967897,-0.025186667,-0.009708782,-0.013066801,-0.027702024,0.044171795,0.03422203,-0.0053526564,-0.037041478,0.05284029,0.018436654,0.015029698,-0.023512771,-0.0005233762,0.009265219,0.000408407,-0.031001028,-0.03053479,0.02456125,0.010864058,0.025053987,0.0061259926,0.02284211,0.049844217,0.004166857,-0.0074965204,-0.013693439,-0.004455124,-0.0064726523,0.077950425,0.004677374,-0.036328577,-0.0168901,0.031258322,0.015698757,-0.04152275,-0.0033884686,0.01607882,0.0030544417,-0.02107413,0.036609445,-0.008239235,-0.0007045679,-0.029835438,-0.022269351,-0.003715956,-0.006206368,0.039687846,-0.005106419,-0.049268704,0.019441875,0.023997456,0.015191113,-0.012958702,-0.013816091,-0.03191464,0.014337673,0.029597303,0.008847882,-0.02517658,0.006308095,0.0208194,-0.00463873,-0.006652725,0.08176903,0.028479636,0.013402949,0.053722497,-0.003432383,0.023924893,-0.0007848797,-0.02172558,-0.010917319,-0.0022249483,0.008468194,0.023132164,0.015493202,-0.0003234871,-0.023228133,0.0021764152,0.060216136,0.003623115,0.015197103,-0.015628893,-0.017303342,-0.01639947,-0.02846893,-0.0050397487,-0.023711747,-0.0037796586,0.0042922683,-0.00039716187,-0.04270251,0.008650105,-0.02196232,0.022993883,0.056213118,0.03955201,-0.0017813678,-0.0533891,0.007083078,-0.05090386,-0.0147208525,-0.03541729,0.017817557,-0.0011659439,0.02042725,-0.004086676,0.022014761,0.088735804,0.0037358783,-0.012577172,0.016773138,-0.024345623,-0.009994964,0.0108301295,0.02149454,-0.0052793263,-0.029501282,0.078269675,0.034551453,-0.025763948,-0.040071163,0.021848459,0.06684501,-0.045795184,0.02246585,0.026307488,-0.038651656,-0.06366153,0.022040853,0.005057711,-0.01679587,-0.043590255,0.015502508,-0.047776658,-0.008234589,0.062075187,-0.019667452,-0.009454373,-0.005110543,0.08440025,0.0117957005,0.021551384,0.014157406,-0.038083266,-0.010714431,0.034149174,0.01500338,-0.010662461,-0.033843033,0.025555843,-0.02624915,0.044386223,-0.011883993,0.060608625,-0.016687844,0.06326435,-0.03647736,0.008347001,0.01374522,0.02067302,0.0066105654,0.021008702,-0.005981134,-0.02195623,-0.011570983,-0.042226795,0.018835275,-0.040173635,0.007906852,-0.038041685,0.025198737,0.0012277853,0.010408862,-0.0027265337,-0.000490124,-0.043407902,0.020597165,-0.026409902,0.017417783,-0.0024917314,-0.017201668,0.03475425,0.020827929,-0.027408384,-0.03678055,-0.07032134,0.004378406,0.009667601,0.012324548,0.024988146,-0.049242828,-0.043583907,0.03018086,0.011073364,0.015858022,-0.03837303,0.010828759,-0.0537064,0.06288456,0.014473296,0.020927578,-0.018478122,-0.08637905,-0.0118778525,0.016208794,0.03859251,0.014704585,-0.04810629,0.023060478,-0.07262335,0.054683946,-0.03581424,-0.017178489,0.045910615,0.021785695,-0.0036443374,-0.052822474,-0.022496182,0.025381297,-0.019836843,-0.05986044,0.041505925,-0.02262117,0.004192562,-0.007970219,-0.0134286685,0.025504982,-0.021655357,-0.030221187,0.046046812,-0.032430995,0.02568719,0.0010112402,0.019074665,-0.025039345,0.01606559,-0.06272209,0.020914393,-0.027387109,-0.00074555824,0.0048901574,-0.0017215946,-0.022464678,-0.01140291,-0.0241386,0.0017300094,-0.035999626,0.01271192,-0.0016791658,-0.001606914,-0.019028613,-0.040079936,0.068202026,0.027507033,0.007916738,-0.04454995,0.00818866,-0.026734442,-0.022943683,-0.037379466,0.00776854,-0.003592331,0.0072319796,-0.009465338,0.019808907,-0.010255562,0.0061041526,0.007541636,0.014639532,0.0013871585,0.03490707,-0.020625032,0.015959978,0.04265839,-0.04576342,-0.005627113,0.00022841818,-0.026066013,0.0035285375,0.0066252453,0.06637787,-0.014628504,0.046966292,-0.002536216,-0.015732137,-0.043162555,0.08422268,0.006273875,-0.001057769,0.0028022495,-0.040540118,-0.020181116,-0.0058544055,-0.0077921054,-0.0053391866,-0.0017363249,0.007234316,-0.055571686,0.0057620406,-0.04838337,9.856523e-05,0.014033186,-0.006427805,0.022696942,0.0030076855,0.057228655,-0.04928601,-0.007695928,0.01742629,0.005372046,-0.016574316,0.009172584,0.002390097,0.007833712,-0.0056625344,0.033465296,-0.008155299,0.054094873,-0.037896037,0.0627948,-0.007958878,-0.007844504,0.0507714,-0.035542194,-0.0018837185,-0.02668125,-0.033836238,-0.019671716,0.08528845,-0.02657693,0.026192777,-0.0485043,0.03374119,0.02134029,0.01982405,-0.0046912325,-0.01578021,-0.028902588,-0.14032505,0.010674148,0.042089757,-0.019762877,-0.03594445,0.0037511927,0.0057077506,-0.0035787413,0.042674042,0.011688004,-0.030724127,-0.019276481,0.059739918,0.012023103,0.030337218,0.010516839,-0.035290234,0.014876685,0.009479511,0.03698962,0.026043158,0.004390435,-0.0046046954,-0.0051563494,-0.011201082,0.0043552364,-0.0109595945,0.054217074,-0.015342211,-0.0061841113,-0.038610324,-0.0035146882,0.008172392,0.00016852953,0.026455779,0.021462036,-0.020804515,0.029433487,-0.035152435,-0.05339286,0.028702872,0.054265067,-0.044300787,-0.019909162,0.031654786,0.046513,-0.07538868,-0.0023218496,-0.05709833,-0.021488834,-0.058949374,-0.0310701,-0.04106161,-0.01720253,0.020805098,-0.042926867,-0.010679779,0.005770481,-0.029818002,0.052532487,0.0037335309,0.024288712,-0.015268612,-0.028966459,0.0355283,0.034137063,-0.062543415,0.0029121037,0.019525034,-0.009371124,-0.03158839,0.030760549,0.020912547,-0.059968844,0.0038226824,0.012144227,0.028417107,0.00015979422,-0.025452174,-0.020264234,-0.053041235,-0.021265162,-0.0011380783,-0.041172992,0.035884395,0.017861659,0.0057326085,-0.0003624379,-0.07056232,0.028016513,-0.06719294,-0.032230373,0.044370454,0.019496737,0.03879754,0.028980866,-0.026678065,0.006969942,0.036140926,-0.02144085,0.017783564,-0.025046214,-0.030978916,0.046317663,-0.0071047214,-0.022962086,-0.0011414655,-0.046494473,0.013370778,-1.6166943e-05,-0.06110126,0.01636107,-0.038227845,0.0038204312,-0.04393656,-0.0057762885,-0.010823483,0.024521204,-0.03311598,0.0053626667,0.048529666,-0.035129476,-0.006984086,-0.045359857,0.022178313,0.03131017,0.030461693,0.033968836,0.05507488,0.020468792,0.02803382,-0.0025944447,-0.031655706,-0.0055563003,0.010689557,0.0018109375,-0.0038872387,0.023566004,-0.0117487805,-0.03339678,-0.013395748,0.010127312,-0.03433262,-0.01633249,0.012975831,0.008028725,0.012347832,0.00092997606,0.022706123,-0.06203807,-0.0010645544,0.0064634103,-0.009760116,0.009130791,-0.010228294,0.029372009,0.010498088,0.005852199,0.033982415,0.0043366835,-0.036492508,-0.01704748,-0.006174984,-0.03227457,-0.008477537,0.02081674,-0.035667717,-0.023298625,0.008402342,-0.042708345,0.007235185,0.05311781,-0.034484256,-0.00875278,0.03252269,0.055558454,-0.011998628,-0.025945818,0.026738932,0.026518285,0.006301709,0.022069588,-0.013635595,0.0017678184,0.031527873,0.08164458,-0.0024507812,-0.024733584,0.04057569,-0.018668817,-0.0064806356,0.01199364,0.030907897,0.047339555,0.029742679,-0.012160649,0.030387776,0.055365458,-0.019494578,0.054655764,0.051477164,-0.04232995,-0.0058185672,-4.916032e-05,-0.0113610765,-0.031121526,0.020324698,0.022693653,-0.0052132104,-0.0012092222,-0.03357624,0.024548285,0.02459539,0.0058000847,-0.01080094,-0.002038573,0.046495534,-0.030187817,0.046248686,-0.054289334,-0.021616487,0.03375735,0.042781483,-0.003141671,-0.028700735,-0.0388703,-0.042781543,-0.034831192,0.005051772,-0.021571169,0.02981256,-0.035338853,-0.022783313,0.029524855,-0.0059837434,-0.026392769,0.011741232,-0.024279812,-0.026902169,0.0044359285,0.049001746,-0.03866528,-0.03643666,0.0269652]
510500	Internet & Utilities	Internet and Utilities	expense	[-0.065363735,0.058821492,-0.01790178,-0.0028990684,-0.0044635735,-0.017879425,0.04475313,0.019532584,0.009894294,-0.0024000527,0.02768583,0.014067169,0.006459926,-0.038019348,0.0018338937,0.007037898,0.006369323,0.013274347,0.0024253794,-0.029225564,0.022890007,-0.05029972,-0.037180506,0.02680178,-0.0071185343,0.027707616,0.053622205,0.0041565676,0.0219136,0.03908217,-0.002077241,-0.042963512,0.058537476,-0.045309477,-0.06409319,-0.06519148,-0.06599533,-0.032605715,-0.05159113,0.014388687,-0.008879316,-0.018290829,-0.030058052,-0.021604592,0.055128217,-0.006122732,-0.029526,0.008878853,-0.049903803,0.007361903,0.020236738,-0.0043763365,0.058780707,-0.037082773,0.024018396,-0.00042545874,-0.03714267,0.016328705,-0.1049417,-0.0072099636,-0.042837683,0.03888247,-0.028715193,-0.04883045,0.0015423294,0.03984078,-0.026177544,0.024635118,-0.02799925,-0.022502717,-0.0019758649,0.04018245,-0.05391366,-0.01979893,-0.036459576,0.025236843,0.04489428,-0.01706646,0.023241328,0.014706611,0.0151417535,-0.055248264,-0.004151666,-0.0247732,-0.033110183,0.029390428,0.006643203,-0.0026785298,0.0049252464,-0.021506129,-0.039055943,-0.016571967,0.006708289,-0.023686158,-0.037153643,0.0015162257,-0.030029919,0.0044112494,8.040959e-05,-0.00077451405,0.05478905,0.0038309328,0.018533133,-0.02713858,-0.0006349916,-0.00068943406,0.0066749724,-0.036541473,0.0032419807,0.01246833,-0.018425232,0.01879134,0.007870923,0.0045131785,-0.014370097,0.009047893,-0.0024166564,0.033986047,0.0038353347,-0.03643798,0.05977246,-0.006748719,0.02462329,-0.021885434,0.05899998,0.020829048,0.0051108045,0.0049197357,0.0072936565,0.0069512273,-0.03585955,-0.0019479417,-0.026204953,0.04208129,-0.056777302,-0.019592464,0.038492568,-0.017369146,-0.039563842,-0.07123286,0.031629376,0.036480106,-0.009621066,-0.05538821,0.045505412,-0.040035732,0.046356216,0.0029926086,0.0011938469,-0.07645468,-0.0115722325,-0.018601567,0.064065345,-0.03801454,-0.0065894257,0.028424956,-0.00036312433,0.0048859715,0.02854182,-0.023563892,-0.064174846,-0.015611697,-0.014493439,-0.06985093,-0.0021315275,0.008707383,-0.017161045,0.0034181045,-0.008756716,-0.0030586133,0.032738913,-0.008731451,-0.007804826,0.007868895,0.0026997018,0.027493265,0.053119708,0.012572997,-0.025022805,-0.053355712,-0.07551544,-0.032110155,-0.058803886,-0.019366978,-0.027642839,0.00517344,-0.030158836,0.002306836,-0.005963459,0.028676163,0.0143342605,0.030769117,0.0064113094,-0.011675289,-0.02318402,-0.027313141,-0.008505054,-0.018427338,-0.01200784,-0.033495132,-0.017969485,0.028808942,0.023340436,-0.018285561,-0.02041092,0.023810906,0.06212549,-0.003541845,-0.007120763,-0.035929196,-0.0328058,-0.012580087,0.011118365,0.0043212036,-0.012554792,0.02870413,0.04649989,0.012095364,0.0004500828,0.013686574,-0.010121135,0.0035262154,0.050801087,0.014230143,0.023730408,0.011124383,-0.0015674889,-0.009660017,0.00064356637,0.010887228,-0.05830254,0.022547016,0.0061439006,-0.03726178,-0.006561879,-0.022389768,0.032426864,0.044484448,-0.07960839,0.014306227,0.0017294282,-0.0031388937,-0.009897645,0.012222396,-0.017382536,0.019539608,0.008936315,0.055815116,-0.037987653,-0.013996891,0.017649122,-0.0299584,-0.019559104,0.025167309,0.029180795,-0.0030515264,0.010270507,0.0130240135,0.0041519227,0.03363868,0.03611983,-0.028270062,0.013637406,0.014027281,-0.019445809,-0.009468028,-0.05033675,-0.020462733,0.013590394,-0.04084093,-0.04616943,-0.0030466034,0.040848486,0.012346382,0.021780286,0.04568802,0.00845425,-0.017960152,0.008806789,0.016965741,0.01674916,0.09582311,0.0025874376,0.0032400545,-0.006769591,-0.009515669,-0.0012788617,0.0402308,0.0046235807,-0.09651278,-0.03689309,-0.034921933,0.056892924,0.0035754135,-0.041123357,-0.015031673,0.04157438,-0.15194187,0.011281398,0.004244393,0.019476753,0.00048206717,0.0061251647,-0.030137701,0.0010768663,0.02809326,0.026207808,0.012521956,-0.06197636,-0.028498458,0.009539414,0.00046541414,0.022068681,-0.0023794416,0.018279297,-0.0075487737,-0.014933826,-0.036883608,-0.04706048,0.055087775,-0.0057641477,-0.047867283,0.042184383,0.032819025,0.02162054,-0.029743833,-0.012133192,-0.011411455,0.0076524806,0.016357215,0.017185593,0.026311072,0.009042286,0.056124926,0.0028698605,0.028658865,-0.017365584,0.00318532,0.07033507,-0.02751828,0.019462762,0.027107516,0.0124594625,-0.023106573,-0.031101545,-0.00096659805,-0.0075811786,-0.023901187,-0.020065,-0.012019196,-0.05078246,-0.03542753,0.0057292855,0.010591796,0.06828034,0.034411624,0.025868427,-0.02940181,-0.006511196,0.015934108,0.010273738,-0.004730805,-0.020106934,0.022665864,-0.02349898,0.01776916,-0.045271456,0.031265114,0.0050918995,-0.00654221,0.03122681,-0.01714968,0.016840534,-0.003848566,-0.008031859,-0.013543815,-0.094965406,0.037517548,0.0148865115,-0.030409079,-0.0041822777,-0.020879097,-0.009475474,0.011348435,-0.044622388,0.0006163432,0.22350644,0.020889526,0.030773675,0.018360542,0.014534984,0.002838896,0.0016599811,0.042700753,-0.006247749,-0.019911902,0.026592905,0.0247478,0.002622533,-0.017936593,0.023948774,0.017268524,-0.06888709,0.0032138263,0.060496327,0.01993258,-0.028728426,-0.017470239,-0.029323796,0.005019451,-0.029209446,-0.009468497,0.015687922,0.07753517,-0.023371194,-0.008744732,-0.023457669,-0.03877699,0.0152696725,-0.019610593,0.0015682064,0.020581227,-0.027780246,-0.07051686,0.08691283,0.04941624,-0.024534069,-0.06517603,-0.011168868,0.02002126,-0.038714793,-0.076100804,0.025484905,-0.0022011932,-0.0606805,-0.0179072,0.036066424,0.014294029,0.0020039738,0.026098525,-0.026123403,-0.026463035,-0.03302561,-0.053746082,-0.035174172,0.072329745,-0.029779384,-0.012523613,-0.0033516325,0.011476654,0.028516589,0.016820576,-0.015657492,-0.009880692,0.034869753,0.04623491,-0.029499479,0.050911073,-0.007986491,0.020965569,0.016212935,-0.031528704,0.04286827,0.006890937,-0.022131063,-0.035318207,-0.038643487,-0.027288586,-0.0040999204,-0.0011015673,0.018594978,-0.036697157,0.025651308,0.039672982,0.01672997,-0.05443207,-0.0015153812,0.020968802,0.01356428,-0.005583847,-0.0071067465,-0.03878128,0.058644403,0.0020363422,-0.017796034,-0.049900524,-0.019169413,0.035596043,-0.013588141,-0.060393866,0.03574619,0.02689327,-0.016547399,0.029381681,-0.07075652,-0.0096891755,-0.019199772,0.018486058,0.04070292,-0.08137459,0.030625857,0.029403508,0.0042413366,0.025333595,0.030371202,-0.013477998,0.0036439667,-0.034276776,0.03139047,-0.011779933,2.8442797e-05,0.0071020103,-0.03102403,-0.021364044,-0.033514246,0.06211265,6.288091e-05,-0.013009674,-0.06510666,0.013882946,0.09163157,0.008754643,0.0031242254,0.015060933,-0.0053315773,-0.009240452,0.0054535493,0.031147022,-0.029495668,-0.017569557,0.024921078,-0.023926985,0.0060935104,0.040056568,-0.016776862,0.04873375,0.004543983,-0.0043358975,0.008946778,-0.0114995055,-0.00786485,-0.081784576,-0.024600847,0.0015941549,0.0034191813,-0.032228332,0.008541097,0.018019307,-0.037701666,0.068536066,0.032105364,0.020586226,0.04316023,0.022850797,-0.022992847,-0.0036398915,-0.018644307,-0.047156505,-0.077635944,0.0042386274,-0.018280756,-0.04475653,-0.029178958,0.0090135075,0.017561937,-0.009184027,0.039636474,0.034347832,-0.0114219,-0.06499576,0.0021287575,0.043635648,-0.010259889,-0.0256463,0.0005777507,-0.023130734,0.030694766,0.07713471,-0.0158622,-0.0069826148,0.011837781,0.022091515,0.002498181,0.037231382,0.019714013,-0.03732234,-0.0052826074,-0.02662673,0.029575454,0.029033953,0.010273859,-0.051948808,0.021266378,0.035916377,0.002488986,-0.012513336,0.015129506,0.04248215,-0.029619755,0.022969494,0.02044602,0.010859546,-0.028539063,0.03182431,0.025179561,-0.011979108,-0.009941339,0.010359381,0.011265329,-0.044616003,-0.0026720723,0.03301693,0.031043945,0.0023457771,0.033567604,0.026109692,-0.007904478,-0.03872441,0.07604549,-0.0028304402,-0.0069099898,-0.015234281,-0.010780552,0.015743375,-0.053496916,-0.010767342,0.004024336,-0.022887185,0.041871265,0.0663544,0.018637592,0.054867882,-0.05655129,-0.012987953,0.0051293243,0.034639046,-0.04713521,-0.0096394755,0.034944493,-0.027605651,0.01974876,0.029647449,-0.0077705677,-0.016219735,-0.0539329,-0.05056879,0.022477405,0.039785624,0.014386073,-0.018041467,0.008734877,-0.036139186,0.026935514,-0.0067262207,-0.0129836835,0.008158725,0.06997246,-0.008576498,-0.054036118,-0.0012287362,0.044048566,-0.006392863,0.010229186,0.004264545,0.008687986,0.035386406,-0.017555038,-0.018908897,0.0274422,0.020813756,-0.0029017546,0.020562783,-0.0050265957,-0.01172855,-0.002626408,0.004168503,-0.009577549,-0.037214167,-0.050390813,0.043761633,0.004600125,-0.011034513,-0.016351113,-0.008527629,-0.002987471,0.008604665,0.004692079,0.019592814,-1.8930594e-05,-0.041898876,-0.056929614,-0.015934637,-0.018530231,-0.037595753,0.032756303,0.024240803,-0.022033554,0.0018439159,-0.01494856,0.016607258,0.0033199566,-0.015749907,0.062318683,-0.01590308,0.039118562,-0.022826988,-0.004563032,0.009997841,-0.03085966,-0.020866727,-0.003809545,0.011884554,-0.003946766,-0.03791939,-0.045214035,0.016353581,-0.009310006,-0.0119304545,-0.015988376,-0.028962865,0.010552866,0.0069287047,0.036819436,-0.009265738,0.02805041,-0.029624587,-0.023378326,-0.014320915,0.049076434,-0.018910889,0.019100117,-0.021915993,0.0049672616,0.03994947,-0.0088500725,0.006982703,-0.016451426,-0.003980863,-0.009523168,-0.04748585,0.0041101477,-0.042921476,0.012312461,-0.027556993,0.0050967196,0.06852095,-0.045895457,0.023964144,0.037799988,0.05122518,-0.0055858735,-0.0032130901,-0.01591586,0.0047482867,0.013815275,0.013180858,-0.02835468,0.007767934,0.015148932,0.03764019,-0.009924185,0.059654996,0.01766126,-0.005802613,0.057922505,-0.00826944,-0.010552577,-0.039997835,-0.008627381,-0.009161099,0.015020459,0.0020237474,0.021913646,-0.033021465,0.02525749,0.021046964,-0.007813413,-0.033499107,-0.022284703,0.01455153,-0.12557323,0.006663701,-0.007788152,-0.0062270947,-0.01436734,0.020091126,-0.0072553772,-0.049502403,0.043240808,0.0029663586,-0.012747507,-0.017120289,0.039336868,-0.018649846,0.0376661,0.0026253504,0.027215201,-0.00052434165,0.013103132,0.03129343,0.004117913,-0.023457875,0.019767556,0.038591944,0.012135575,-0.020265149,0.05089436,0.012474463,-0.04829753,0.0019649996,0.017665906,-0.036284223,0.0076407343,0.027185338,0.015454527,0.058394104,0.01586309,-0.02511595,-0.0012119613,0.032478847,-0.05267002,0.04121021,-0.03799708,-0.008780738,-0.020017633,0.06619556,0.0057214038,0.017943118,-0.00910639,0.007223954,-0.022220906,-0.00068801816,-0.021380555,0.044222757,-0.014504379,0.0014373916,-0.032551713,-0.009998932,0.0011824424,0.03738231,-0.026599055,0.012091455,-0.014141581,-0.039437987,0.00975674,0.011765745,-0.015741292,-0.00395621,0.025521949,-0.019447902,-0.021227546,0.010888306,0.024526807,-0.021519974,0.03217054,-0.020107983,0.028882533,0.005431862,-0.040180206,-0.0054770717,-0.025969055,-0.027888656,-0.01415208,-0.033633888,0.008651133,0.012431621,-0.021407252,-0.013955161,-0.024989722,0.027262961,-0.04114969,-0.04589343,0.0003938715,0.06431789,0.0033132376,-0.0104120895,-0.0012040453,0.011883808,0.041705713,-0.012598087,0.008602586,-0.02746723,-0.008285312,-0.015108292,-0.019270187,0.029744387,0.006304171,-0.030759104,0.037942976,0.01455679,-0.023772301,0.019494312,-0.05237377,0.037474003,-0.04792102,0.01084282,0.0038026064,0.03285417,-0.041427903,-0.004171789,0.0018666775,-0.008964245,0.023894416,-0.032596324,0.054173764,0.0018353516,0.038341563,0.002374746,0.035109907,0.0032241694,0.007075883,-0.013467249,-0.0029536863,-0.00190318,-0.020026475,0.0016354526,0.015789686,0.020933693,-0.026906751,-0.050641365,-0.022882886,0.020322677,-0.024027212,-0.018354086,0.0005472072,-0.02024368,0.05852078,-0.019752555,0.04894651,-0.045802608,0.008785895,-0.04911595,-0.010027872,0.029932154,-0.0019021995,0.014419718,-0.048882004,-0.030008193,0.016883893,0.020517362,-0.034496903,-0.0093026385,-0.043231778,-0.039987154,-0.0003495045,0.056408305,-0.037490178,0.013556847,-0.013038548,-0.029178567,-0.022486906,0.012952269,-0.022839587,-0.011706348,0.014980664,0.010220523,-0.026160324,-0.0010300005,0.03364292,0.060805142,0.003770635,-0.013903095,0.078409314,0.012776645,0.031428847,0.044909123,-0.04811147,0.00953636,0.020398105,-0.003880938,-0.046647746,-0.027049031,-0.026246222,0.035732247,-0.006868295,0.012092353,0.022744777,0.054776616,-0.01447887,0.05309983,0.013831868,0.02098307,-0.0165224,-0.046091773,-0.02089208,-0.013109777,0.006926464,-0.022500418,-0.029729664,0.056955516,0.001006837,-0.012474476,0.020228732,0.05225969,-0.011840545,0.011612258,0.009442993,-0.016636424,0.017542666,0.0018128038,0.009461156,0.027241135,-0.020450588,2.7790715e-05,-0.0150820175,-0.03326032,0.023586152,0.027324714,-0.014339655,-0.014552708,0.044568215,-0.034909237,-0.052155204,0.008594303,0.012992004,-0.005086644,-0.015576003,-0.030068457,-0.010130099,0.0309487,0.040648676,-0.019020189,0.011027115,-0.009434637]
510600	Post & Delivery	Postage and Delivery	expense	[-0.05166711,-0.017130174,-0.0046738666,0.01935012,0.007535806,-0.0074442085,0.0035329908,-0.01603077,0.016708432,-0.01847819,0.024855785,0.013763977,-0.011229758,0.009927086,-0.024530433,-0.00062594464,0.016107444,-0.03043841,0.0062153013,-0.057734918,0.029323313,-0.04324052,-0.03436711,0.057431545,0.056763206,-0.016927063,0.010170356,0.040906433,0.0319079,-0.016814329,-0.008565136,-0.009301292,0.060633324,-0.03115422,-0.008855552,-0.031000728,-0.013462106,-0.03931218,-0.067915685,0.013560617,0.020342847,-0.037330218,0.0041752467,-0.042890746,0.039373953,-0.0076334467,-0.038168844,0.0070722164,-0.069167204,-0.0038746472,0.024238888,-0.002553981,0.071117766,-0.009673046,0.023595808,0.047157284,-0.0006166964,0.031624902,-0.093055956,-0.026196133,-0.024262529,0.0068127215,-0.021539658,9.8653894e-05,0.004771688,0.057949197,-0.02192653,-0.0037143906,-0.009988919,-0.00075557356,0.01562452,-0.007642917,-0.040400736,-0.022155896,-0.05149306,0.0441631,0.038830508,-0.018503767,0.0064974953,-9.2473594e-05,0.00053562416,-0.050594725,0.0024848094,-0.053533047,-0.012164287,0.036909424,-0.016228242,-0.009420773,-0.01018095,-0.0073625,-0.027994309,0.04827144,0.0074374946,-0.0382162,-0.061193842,-0.026195608,-0.034165934,0.0030084064,0.0057329866,-0.00090347463,0.04689164,0.0025758543,0.014406374,-0.03681064,0.00089268223,-0.0039852173,0.035749815,-0.0004899462,-0.000948312,0.0016457294,-0.002840448,0.0069454513,0.022175608,-0.020871073,-0.0016386017,0.005996873,-0.024260525,0.012906514,-0.00891634,-0.03247721,0.052014705,0.040561117,0.03987442,0.0017692391,0.027647808,-0.016423225,0.012817653,0.042367313,0.020965476,0.009956845,0.045214817,0.011450235,-0.0033522095,0.020920265,-0.017406732,-0.022556223,0.03463393,-0.0003581644,0.006744195,-0.03820887,0.011026953,-0.026511475,0.02095463,-0.022584511,0.021675665,-0.026813898,0.058244545,-0.0011678085,0.01815748,-0.052533124,0.0028310555,0.034446087,0.042354282,-0.048159312,-0.03919373,0.00320072,0.019795595,0.030722206,0.033926155,-0.001208663,-0.011276043,-0.012450934,-0.013529465,-0.050077837,-0.0052001136,-0.018163202,0.024778994,0.03068284,-0.014220051,-0.0018599338,0.017583122,-0.030032042,0.079642,-0.023010429,0.011042967,0.0394554,0.07110053,0.010624921,-0.056823105,-0.050829098,-0.044785935,0.020646764,-0.028425649,-0.01727566,-0.018147618,0.01586977,-0.02447259,-0.025472473,-0.021227513,0.0007836499,-0.007247803,-0.011173746,0.0080254525,0.00405551,0.025188409,0.0040861787,0.06331972,-0.043867864,-0.004617189,-0.040527612,-0.024038179,0.008139263,0.011767237,-0.010695259,-0.024264337,-0.003926098,0.030644218,-0.027838588,0.0135629345,-0.045351762,-0.00054956425,-0.037298582,0.010402526,-0.00793363,-0.0020228112,0.028494628,0.03838123,-0.009733197,-0.024269767,0.0069211638,0.0066747474,0.015238008,0.057272527,0.009826969,0.04439949,0.0009668144,0.023399077,0.0057945065,0.033565167,-0.028689085,-0.016351137,0.033196,-0.0077497787,-0.028711457,-0.014026056,-0.019807134,0.026622303,0.051957857,-0.03752297,0.010296903,-0.0026910973,-0.026671724,-0.0015612239,0.014751958,0.0036187903,-0.010180129,0.0072542555,0.02978294,-0.003816128,-0.052249722,0.03311474,-0.009117829,0.003590989,-0.018604767,0.015968774,-0.001986948,-0.0015670042,0.0008162787,0.030933036,0.011103679,0.040712815,-0.053275693,-0.009109287,0.012719976,0.008378458,-0.009708271,-0.06626944,-0.012414865,0.026186785,-0.029987436,-0.011222477,-0.045566697,0.025344977,-0.009821377,0.019193385,0.079848506,-0.0043231556,-0.025432328,0.0023367987,-0.048127376,0.034425095,0.06239134,0.012601891,0.021610107,-0.0025227303,-0.00298049,0.031233137,-0.021240355,0.016247936,-0.047882065,-0.036175694,0.0021862148,0.057735533,0.0008313492,-0.04709662,-0.0058894735,0.0412968,-0.16203614,-0.034067426,0.00435701,0.0010543895,0.001617905,-0.019771354,-0.010466068,-0.009292457,-0.030828176,0.030538017,0.043764487,-0.05281497,-0.018651184,0.01072647,0.010486592,0.0013590417,-0.03902563,-0.0027043398,0.02295512,-0.027518677,-0.027325448,-0.02488067,0.03449261,-0.014911383,-0.07107523,0.06563286,0.028015524,-0.03834783,-0.03045175,-0.011524428,-0.017451877,0.021520875,0.01297239,0.016785616,-0.0025856567,-0.008490979,0.025274687,-0.00561031,0.054869458,0.02864479,-0.00023344732,0.07314808,-0.048190344,-0.012342374,0.022983938,-0.014863683,-0.0336438,-0.00023661435,-0.0007975164,0.005091534,-0.047689762,-0.017113257,-0.013188494,-0.020451045,-0.054791313,0.023328349,0.0044365306,0.0468201,0.017799031,0.07530125,-0.0035824433,-0.04817333,0.028499508,-0.00998317,0.022598976,-0.041682363,-0.011178077,0.027260156,0.031314835,-0.04433954,0.035689343,-0.0017765785,0.006664185,-0.0083077345,-0.03289102,0.034085944,-0.030997798,-0.02695468,-0.00993747,-0.07746849,0.01427063,0.0010165224,-0.05438872,-0.0336261,-0.05221129,-0.005515838,0.019266635,-0.057736415,0.043362867,0.21684231,-0.005529817,0.058455057,-0.006320632,0.0008901193,-0.049454212,0.007139903,-0.0052377135,-0.02592692,-0.042630237,0.024611644,0.015771948,-0.041900545,0.0028787234,3.5044228e-05,0.02656232,-0.06877645,0.0087785935,0.06578774,0.026325906,-0.04865733,-0.022310425,-0.02778889,0.0004706319,0.010883398,-0.003994191,-0.028699856,0.048329905,0.0055747717,-0.02897505,-0.020149244,-0.023022026,0.03286353,0.041969143,-0.024839023,-0.0108336015,0.030063897,-0.059265222,0.0599611,0.016076377,-0.016161637,-0.044146474,0.032515947,-0.007854035,-0.024434077,-0.0676955,0.008705513,0.0021171998,-0.03517401,-0.034955062,0.034668677,0.021214563,-0.032792207,-0.012749239,0.0018279391,-0.0353127,-0.028634533,-0.040429726,-0.05995005,0.065152,-0.0038113706,-0.002030019,-0.008878652,-0.0013386137,0.025345085,0.022794198,-0.005512507,0.006490179,-0.019529095,0.05828242,-0.029045071,0.02023385,0.026667206,-0.018244505,0.0022958417,-0.00027975324,0.013096511,0.04172004,0.021455871,0.026264789,-0.0640586,0.0022500455,-0.0384984,0.031913385,0.017731728,-0.010540366,0.040126476,-0.0022574158,0.014071055,-0.021651367,-0.022990959,0.01235503,0.009975635,-0.021211058,-0.023171226,-0.049777478,0.017323669,0.012260299,-0.03573731,-0.058772054,-0.03094395,0.04354033,0.010346772,-0.060406085,0.060475413,0.007965755,-0.034004036,0.0020855614,-0.06655094,-0.02648865,-0.02117993,0.041576408,-0.021982323,0.016477033,0.04152768,0.011465833,-0.013838068,0.018532699,0.02465306,0.018473227,0.008674307,-0.0067909355,0.04051668,0.0054920227,-0.004354148,-0.030175596,0.011673006,-0.053859014,0.011622086,0.04970139,-0.0007026464,-0.014829568,-0.059276294,0.008041534,0.07618738,0.00083954795,0.046891715,0.03293504,-0.05159555,-0.031031461,0.009338432,0.055631936,-0.046195954,0.016045602,0.044695005,0.0012057925,0.009763378,0.032580856,-0.036657248,0.060692478,0.024107432,0.0121142,0.035491697,0.0011082729,-0.00035430395,-0.07566321,0.0017903377,-0.03327907,0.016414102,-0.010072816,0.0070334175,0.015149251,-0.030948468,0.09175274,0.046726696,-0.023496505,0.018217051,0.002738317,-0.048900876,-0.017963259,-0.008195009,-0.014507413,-0.050691232,-0.0016003505,0.0064686565,0.018028429,-0.008922035,-0.0003345575,0.0140032,0.008013177,0.01191321,0.050081614,-0.013976378,-0.029929198,0.009519995,0.01795416,-0.015496338,-0.022667518,-0.03000612,-0.024952887,-0.024975069,0.08319413,-0.010325018,-0.017845629,0.035903677,-0.0011080435,0.044965878,-0.002971939,0.0050727683,-0.037718087,0.016216205,0.004303041,-0.004730988,0.009100426,-0.016476605,-0.037260205,-0.0071773445,0.02785507,0.014086646,-0.0015248067,-0.0024362707,0.022013117,-0.030858189,0.004526007,0.035728592,0.011992952,0.044228964,0.036041837,-0.024231397,-0.053621996,-0.014095566,-0.013916226,0.00480108,-0.027791021,-0.014503951,0.017827557,0.010262591,-0.00019485939,-0.0412429,-0.029887933,0.0008415106,-0.0467242,0.040739298,-0.011003191,0.064393334,-0.014951951,0.03570459,0.025951901,0.0031862254,0.005625622,0.026204199,-0.0102370735,0.051053848,0.066393256,0.019383658,0.03626174,-0.036709707,-0.05964434,0.04134317,0.043489985,-0.0023262445,-0.029529164,0.005124691,-0.031600785,-0.00079040055,0.016322864,-0.02860704,0.012305783,-0.05268756,0.011685743,-0.016610965,0.037577886,0.013452846,-0.016796948,0.0183055,-0.017546633,0.038914375,0.013559854,0.014163723,0.005398678,0.038176674,-0.0022669951,-0.0399609,-0.019469796,0.08643052,-0.008041449,0.011349418,0.049527876,0.0011596545,0.022606594,-0.04224506,0.0056839124,-0.0009255107,0.016893575,0.04977505,0.058132384,-0.029914474,0.011755333,-0.0087770745,0.014238446,-0.0015984175,0.012944186,-0.035149787,0.058307596,-0.016372083,-0.023559757,0.0010970047,-0.0006004668,-0.008312916,-0.0044050813,-0.02661622,-0.00399731,-0.036018018,0.007103173,-0.03030647,-0.0027024283,-0.018176794,-0.03782263,-0.005523907,0.014639354,-0.0027571071,0.0006792771,-0.016608583,-0.027862458,-0.00713273,-0.033802938,0.043835267,0.02018564,0.00063340575,-0.0028116892,0.026181007,0.004884809,0.0010100709,-0.017868306,-0.0037532477,0.021448048,0.036354534,-0.0020572066,-0.02082624,-0.00873059,-0.020663586,0.030068846,5.0021456e-05,0.009921126,0.013010247,-0.024644833,0.0560367,-0.047847543,0.017544314,-0.07134076,-0.07196927,-0.006667028,0.015966024,0.015503538,0.03485692,-0.069367535,-0.023917025,0.037721816,4.6101446e-05,0.02304639,-0.018044638,0.015690852,-0.019407487,-0.063838,-0.012500445,-0.06679485,-0.02708695,0.028226808,0.0578692,0.022874305,-0.02792023,0.019517519,-0.005121604,-0.0047668745,-0.013549361,0.036580045,-0.0024571398,0.0016352785,-0.0059575043,-0.00798286,0.0008283336,0.042642385,0.01545656,0.031094272,-0.0039411583,0.015470592,0.024812168,0.011672031,0.06636368,-0.061837196,-0.044355888,-0.02189744,-0.01986698,-0.028330455,0.017160632,0.007748438,0.020823732,-0.018832706,0.02228647,0.00060813583,-0.026293876,-0.00056321174,-0.05376296,-0.009305432,-0.13234268,0.009831742,-0.010631736,-0.011842553,-0.05061997,0.00888286,0.024559908,-0.005931944,0.016670445,0.033615347,-0.05054951,-0.0061617782,0.044548567,0.0048104287,0.025412612,0.03732539,-0.029171584,0.029726656,0.02129738,0.042978212,-0.008757808,-0.010507626,-0.034973457,0.058938276,0.0023938534,-0.0025154073,0.03803566,0.022649592,-0.03303266,-0.030452589,-0.028347468,0.0029512804,0.044675298,0.0035484044,-0.01648654,0.017369753,0.008167619,0.0071418257,-0.0166902,-0.009205398,-0.019359166,0.032750398,-0.012374871,-0.0058417744,-0.0010820791,0.03347213,-0.037369616,-0.022354495,-0.041754514,-0.01693198,-0.029353937,0.00167464,0.0012804859,0.010157905,-0.02873701,-0.016670452,-0.041443467,0.010793351,0.016419997,0.047922567,-0.050557602,0.07082328,-0.017992336,-0.06015144,0.006536003,-0.022925815,0.010396404,0.0010668276,0.012061083,-0.0120439725,-0.049953777,0.030623673,0.014996883,-0.011017013,0.040227775,-0.0089677675,0.03300571,-0.026099743,0.0028449893,-0.011733391,-0.02587029,-0.012846036,-0.074427955,-0.061404396,0.014787014,0.037287794,-0.024497868,-0.0114862155,-0.0216615,-0.019776314,-0.011069227,-0.028295755,0.0134574,0.016285148,0.008295709,0.026893703,0.008309417,0.052735247,-0.03519214,0.0049069757,0.039198905,-0.048937812,-0.0012697378,-0.0034024112,-0.04062481,-0.033872884,-0.0142606795,9.7345626e-05,0.02162048,0.008553003,-0.0022325392,0.033262048,-0.048308484,-0.00068403286,0.00016730832,0.0052877865,-0.0069633797,0.040514793,-0.0407989,0.0106754135,-0.0059004296,-0.008686094,0.043942064,-0.04984436,0.032135338,0.009401628,0.027792031,0.0059334286,0.025945682,-0.010017655,0.024437279,-0.012590677,0.010396181,0.0045413487,0.014678647,-0.012962681,-0.029458268,0.023197934,-0.04319809,-0.026334776,0.0048342184,-0.016269274,-0.009820141,-0.026881738,-0.0018644102,0.0036153127,0.053060424,0.05291769,0.055237874,-0.030310873,-0.005515116,-0.007590311,0.0171714,0.03917777,0.0058565126,0.005748189,-0.013004653,0.008954749,0.023692966,-0.031518992,-0.019287534,-0.048515156,-0.017058419,-0.010326232,-0.003431543,0.07668491,-0.049966756,0.004137507,0.013098829,-0.015143658,0.041351944,-0.007076108,-0.01468148,-0.023404144,0.020389926,-0.006170849,-0.011506757,-0.019183164,0.04038998,0.025320461,0.009843674,0.008365272,0.053883847,0.061568853,0.021618769,0.04456131,-0.024405004,-0.003665522,-0.023245694,0.015189857,-0.014485942,-0.00015767956,-0.022215825,0.042881157,0.011048605,-0.0030560482,0.02088711,0.072355546,-0.0294726,0.037087277,-0.0016295626,-0.012079737,-0.032889977,-0.05635122,-0.0565588,-0.031000923,0.014149774,-0.024342837,-0.029527482,0.041319028,-0.020627817,0.0009818139,0.014491171,0.019139456,-0.007862065,-0.014402787,0.039173715,-0.002114667,0.031283837,-0.025048802,-0.026070198,0.025828408,-0.034524556,-0.022575516,-0.002910289,-0.028936937,0.010988182,0.008492778,0.0005325542,0.004300913,0.0031367675,-0.03431363,-0.020599335,0.046467796,0.0017782567,0.016506426,-0.02948039,-0.010704062,-0.0155088985,-0.0043108356,0.03316256,-0.016196517,-0.04669878,-0.000321374]
510700	Software & Subscriptions	Software and Cloud Services	expense	[-0.07313078,0.023587115,-0.030176591,0.0063613104,0.0044308132,0.022385167,0.024964415,-0.0075914906,0.014599597,0.0013613784,0.037208207,-0.018942375,0.003737019,0.0014744411,0.010481172,-0.0012402629,0.005529984,0.0036025264,0.004844372,-0.018533316,0.037264757,-0.03239847,-0.011876241,0.020052098,0.021717869,0.030873496,-0.018382436,0.008723361,0.024828745,0.008771371,0.0061537046,-0.009780273,0.0643342,-0.040389705,-0.053220764,-0.046510383,-0.024446439,-0.03770102,-0.06759569,0.0034198365,-0.022496948,-0.021584535,-0.02149191,-0.05302113,0.06027708,-0.003007979,-0.019582056,-0.01650451,-0.053050082,-0.0038097836,0.014522778,-0.04209488,0.065994665,-0.035961974,0.047164652,0.017153827,-0.06508678,0.0046358122,-0.12709747,0.0261425,-0.05163394,-0.0019198757,-0.017388664,0.010043432,0.026159877,0.04631807,-0.046808764,0.010686127,-0.00866654,0.0031587386,0.041888684,-0.004517073,-0.022267945,-0.0028074002,-0.044535283,0.022987738,0.016527513,-0.0060295705,-0.0014670268,0.026868735,0.006921513,-0.050849054,-0.019172492,-0.035800673,-0.03507109,0.01512573,0.0035727026,0.04975295,-0.012849137,-0.026799435,0.0015533883,-0.00027137078,0.022090236,-0.01904509,-0.057423674,-0.0029657518,-0.040289704,0.03807254,0.007949877,-0.0031352146,0.012755435,0.020538982,0.043572754,-0.0042748027,0.020573633,0.040469766,0.004306369,-0.033272296,-0.02797165,-0.014782665,-0.0121417185,0.04012893,-0.009010064,0.0057487115,-0.005876717,-0.0045356574,-0.0061635193,-0.018901873,0.031491768,0.00858374,0.01755686,0.003317314,0.037651647,-0.017267343,0.05368425,0.008533671,0.015629098,0.009693047,0.053042624,-0.019663528,0.002772729,-0.009462631,-0.025156282,0.015775947,-0.045162603,-0.026303403,0.0020174896,-0.03922994,-0.014970139,-0.047184926,-0.0010312245,-0.0008510927,0.012222939,-0.016607706,0.051182337,-0.024540523,0.036061525,0.025937075,-0.01776352,-0.06589938,0.009304552,-0.0033001436,-0.012690374,-0.02698149,-0.0006167972,0.0067066792,-0.01795826,0.006019427,0.0129878605,-0.01533053,-0.023429101,0.027632704,-0.036995515,-0.017974652,0.025945036,-0.020449478,-0.0099056475,0.010255531,-0.007907624,0.0021370202,0.017105712,-0.02629824,0.039102085,-0.039227266,0.010066028,0.033736236,0.06852866,0.020179236,0.0125144,-0.061372142,-0.07205824,-0.019598838,-0.0749358,-0.0686634,-0.017210582,-0.0147207845,0.04126495,-0.0024730628,-0.007179412,0.032109063,0.022531506,-0.005668065,0.034886125,0.0017733636,-0.01335078,0.043918777,-0.0052415347,-0.03298633,-0.025786549,-0.018932838,-0.0938692,0.0244145,0.0035276464,-0.0113596395,-0.035580497,0.03332341,0.04587107,-0.019393062,-0.011009036,0.0065957513,0.009636148,0.021548426,0.029630803,-0.010715596,-0.01693928,0.016505824,0.031346265,0.0021545852,-0.01011162,-0.01475037,-0.041203294,0.026798155,0.03148056,0.037286073,0.030377384,0.017036509,-0.023491051,0.032734513,0.058583215,0.03360541,-0.076726414,-0.027558291,0.015345958,-0.0447719,0.03764251,-0.033664327,-0.00835716,0.044906307,-0.038503658,-0.015250692,-0.05841053,-0.03333144,0.005936639,0.013067134,-0.0100218365,0.07084812,0.015677772,0.018558616,-0.02891787,-0.04454391,0.0314701,-0.011378579,0.03533758,-0.0029381344,0.033815645,-0.013975889,0.009955297,0.019222435,0.02062139,0.0018659027,0.009179533,-0.024509467,0.034900256,0.029358404,0.021689484,0.026804633,-0.057401218,-0.040932015,0.0033857017,-0.03338631,-0.012926499,0.0044983774,0.019053917,0.02012945,-0.00037931825,0.025949018,0.02041158,-0.04069852,0.029933693,0.016325088,0.004081294,0.084501825,-0.0010095382,-0.010894342,-0.025406357,0.0049028094,0.010346188,-0.02299294,-0.0316199,-0.08043595,-0.05690621,-0.031896688,0.06733892,-0.00395621,-0.06384335,-0.017466648,0.020649668,-0.14275487,0.0024980009,-0.015429513,0.04629395,-0.018414311,-0.017781658,-0.010531285,0.0271792,0.00056361605,0.04932975,0.019842355,-0.054668818,-0.0032873529,-0.030005213,0.0047545093,0.0005241026,0.013261665,0.0038133834,0.037825275,-0.024390604,0.0027965107,-0.0030041588,0.009769922,0.0018823904,-0.03742733,0.04100866,0.002323239,0.0077931713,-0.016553096,-0.04372803,0.009597337,0.030520933,0.009183165,0.049956348,0.029512497,-0.02628241,0.04600086,0.013627846,0.060510293,-0.0037706606,0.013944678,0.035309393,-0.02451846,0.033676505,0.025468701,0.016951552,0.025583256,-0.020420467,0.055048503,-0.046968907,-0.024193032,-0.01887284,0.018030293,-0.030961754,-0.034771062,0.014922393,0.022715226,0.074598536,0.034558024,0.0036345164,-0.009344087,-0.04639252,0.041294295,-0.018889152,-0.02220556,-0.028587941,-0.007205317,0.02664613,0.05010966,-0.028923819,0.05116071,0.004631405,-0.002675247,-0.0076214336,-0.015475066,0.011452737,-0.022962144,-0.013208975,-0.016527785,-0.0844421,-0.0012282447,0.012617396,-0.018132977,0.027721725,-0.047440007,-0.0022028554,0.0051863203,-0.033953354,-0.028684065,0.18601258,0.0008810952,0.06865735,0.011971961,0.029942283,0.005282435,0.025137495,0.052540917,-0.0046012597,-0.0338875,0.025102992,-0.00028273845,-0.020245273,-0.017217714,0.01188529,0.014077139,-0.0781946,-0.011799752,0.082592845,0.021619586,-0.015370665,-0.03173257,-0.013293074,-0.0075820233,-0.04692936,-0.0104439845,-0.043047193,0.06701434,-0.008891414,0.018860497,-0.013486589,-0.012507328,-0.009395226,-0.014615031,-0.031263772,0.012732083,0.008626149,-0.025524197,0.03671579,0.042251404,-0.01546302,-0.018038748,-0.0038116744,0.013132336,0.016873911,-0.051001508,0.049426626,-0.00038848596,-0.06550417,-0.0480586,-0.008927201,-0.0038539476,-0.028789671,0.034167312,0.009248051,-0.044317003,-0.038123652,-0.05014505,-0.028572822,0.051953346,0.014540351,0.018002477,-0.023499716,-0.0015843278,0.015811892,0.016328823,-0.017370801,-0.018481387,0.039164092,0.04915679,-0.014537055,0.024963932,0.00599228,0.01193835,0.025547056,-0.021471778,0.038834352,0.030146426,-0.0009690215,0.0014513499,-0.04443235,0.027373714,-0.021060614,0.014737254,0.022606105,-0.031462956,-0.013668339,0.031038597,-0.0015813934,-0.06616571,-0.005909919,0.01575323,7.221014e-05,-0.021313563,0.00030555367,0.019844774,0.0072506727,-0.036512464,-0.03214078,-0.018708287,-0.01150127,0.038031273,0.0023881695,-0.07651174,-0.0022288065,0.008936438,0.008297253,-0.009425708,-0.03002621,0.0078997165,0.006275586,0.01101731,-0.023159025,0.01613167,0.018745715,0.030994436,-0.022068454,0.0054343482,0.072054215,-0.01629723,0.002205932,-0.016055034,0.00877015,0.041917294,0.05937444,-0.01220951,-0.08189297,-0.0046742973,-0.017563643,0.03310026,0.018238414,-0.019906608,0.014583086,0.019192733,0.028232815,0.0031112062,-0.0058101458,0.044393707,-0.016102863,-0.032748606,0.00048285408,0.011901251,-0.051351562,0.011925612,0.016821478,0.0012219663,0.00046945963,0.024655243,-0.039477915,0.033823915,0.0042181727,0.015903832,0.023662185,-0.051867966,0.008810679,-0.07866698,-0.031810112,0.01622284,0.00840258,-0.043381426,0.0012205663,0.02634316,0.032893825,0.074234486,0.0571546,-0.024356741,0.018116524,-0.04471541,-0.051391672,-0.018678771,0.01669322,-0.013004844,-0.017967246,0.04846934,0.03541584,-0.07088095,-0.046025507,0.026894588,-0.0017091043,-0.051720865,0.021303302,0.03885157,-0.016166711,-0.036458537,-0.027609805,0.011908656,0.00050643197,-0.022005389,-0.0579523,-0.022677572,0.014065749,0.07088655,-0.01813498,-0.021811396,0.017758956,0.034810547,0.023092866,0.033327688,-0.003860123,-0.012652731,0.028945524,0.042322274,0.024747834,-0.036425523,-0.0022290323,-0.019706933,0.049825005,0.03916763,-0.005066616,0.009033617,0.016622528,0.0111639295,-0.024470557,0.00037543298,0.039280806,-0.018864295,-0.009648017,0.020463314,0.030267585,-0.013041099,-0.017266562,-0.013010078,-0.012955524,-0.07450997,0.016839856,0.03005118,0.022292508,0.028257858,0.009074341,0.017983634,-0.012244586,-0.014067718,0.022362722,-0.011112534,0.037802793,-0.02466689,0.0026788122,0.03437797,-0.014143663,-0.01146487,-0.0077476855,-0.0001636583,0.054307856,0.030887382,0.018277686,0.046211768,-0.047778346,-0.017334232,0.014530813,0.07163526,0.0040178117,-0.043106798,0.028418355,0.0012180719,0.019671455,0.02406031,-0.0039550452,-0.014582366,-0.06804048,-0.025351673,-0.015762674,0.05365375,0.0055065616,0.0014301211,0.028429115,-0.023847213,0.022464631,0.007710378,-0.00893116,0.02223581,0.008142261,-0.02665502,-0.08773707,-0.0047988147,0.03483465,-0.00043714597,-0.036492325,0.018588627,-0.027041586,0.02959348,-0.08143706,0.0042949663,0.040132023,0.035193227,0.013130556,-0.00086263416,0.019972686,-0.007568162,-0.0076001827,-0.024251916,0.0155239785,-0.005233045,-0.040367026,0.007486483,-0.0051899077,-0.01783531,0.0032418359,-0.03704457,-0.018433716,0.011345883,-0.011465283,0.020022895,-0.0064410907,-0.033006463,-0.015384365,-0.0042632488,-0.022756342,-0.08549882,0.029016169,0.043635804,-0.012600405,-0.021338813,-0.024878582,0.032211248,0.0059914635,0.012080609,0.0378266,-0.0048540495,0.0070958454,-0.02302013,0.00060732587,0.0021495596,-0.015374436,-0.008257108,0.0112290075,-0.011063368,0.027162775,-0.015455981,-0.0544351,0.00091283006,-0.02256729,0.0061376533,0.014450445,-0.030851616,0.037319902,-0.0083542755,0.028018741,-0.042893197,0.017293565,0.033653572,-0.009611642,-0.044475578,0.033043664,-0.01600581,0.03194587,-0.040692005,0.015223617,0.006660032,-0.08296237,0.013159236,-0.012704687,-0.02406675,-0.039118864,-0.057273783,-0.03172624,-0.030364174,0.010608972,0.010677544,-0.033109695,0.046020765,-0.055767402,0.038754433,0.048973754,0.0063635316,-0.0011938848,0.0019554636,-0.0011464804,0.024895515,-0.004601104,0.009755151,0.036747478,-0.011732519,-0.0064037996,0.02719577,0.0058882926,0.007968345,0.013333642,0.016892668,0.046416417,-0.0567971,-0.042168856,-0.07323892,-0.018166868,-0.044169053,0.05733923,-0.01516166,0.0036317094,-0.0077941646,0.037692465,0.048038878,-0.010880639,-0.016234692,-0.0449358,-0.004854306,-0.12617147,0.0014207452,-0.012460117,0.012601202,-0.003614842,-0.0075012385,0.030159976,-0.0008501785,0.017961515,-0.014286144,-0.054478776,0.022597684,0.025377499,-0.027951056,0.018471083,0.01446796,-0.03741565,0.0012334598,0.0028556832,-0.008362044,-0.029739195,-0.0095521975,0.008213922,0.042447887,0.044831853,-0.013092954,0.004547924,0.013215232,-0.04076435,0.036632385,-0.017453143,-0.017371573,0.0053244275,0.0020573155,-0.017517341,0.027767554,-0.030019304,-0.008569365,-0.049448553,-0.0018788695,-0.013840469,0.04039045,-0.032732554,0.024398748,-0.004579996,0.10298625,-0.019811936,-0.0048460695,-0.013348085,-3.619398e-05,-0.015249302,0.018562647,-0.03239086,0.028754905,-0.0067950804,-0.028328728,-0.020064358,0.0023522233,0.008910763,0.058896188,-0.025708336,0.08491324,-0.024603346,-0.03071493,0.030481566,0.0044850325,0.000915592,0.018086767,0.0024151101,0.0392117,0.0016214362,0.04937486,0.014644534,-0.012939861,0.025327897,-0.043478917,0.05533607,0.02019267,-0.03903595,0.0034861558,0.0041985703,-0.02358513,-0.06797446,-0.03049322,0.00013973589,-0.0144428285,-0.0117791025,0.0020540806,-0.02036177,-0.010428946,-0.01883381,-0.034126975,-0.009403206,0.031905368,0.0041827746,0.036447316,-0.016753213,0.041344274,0.028571974,-0.007890512,0.039090622,-0.018426724,-0.025399687,-0.041110616,0.008146647,0.02180578,-0.0071856724,-0.047100954,0.042109106,0.0035136684,-0.019132305,0.002613697,-0.021281946,0.03435978,-0.031307854,0.0053269626,0.031250153,0.020437498,-0.038466204,-0.006646743,0.00704488,-0.0062675974,0.01930468,-0.038100746,0.08790241,0.022567274,0.04456206,0.025581302,0.017467735,0.00095434405,0.008757461,0.0049104234,-0.018656656,-0.0038649244,0.000616176,0.0041341805,0.04136317,0.045425285,-0.051704876,-0.018158415,-0.012341487,0.0036777614,0.0029409607,-0.010897778,-0.023393743,-0.053983655,0.027868722,0.010293789,0.034480534,-0.047655318,0.013532286,-0.0046498636,-0.007647771,0.0370206,0.0057880892,-0.0036177197,-0.04121357,-0.023682589,-0.016266204,0.014522299,0.04387435,-0.00032507972,-0.01859794,-0.033706393,-0.016545696,0.020209152,-0.035690036,0.0055772257,0.034734547,0.009301653,-0.030308504,0.0027157373,-0.006538027,0.0131725045,0.01392458,0.0005296071,-0.025775753,0.0004140306,0.043673407,0.02840703,0.0067548,0.008040439,0.050269082,0.025525445,-0.0066075763,0.055942655,-0.019386357,-0.025346491,0.010731767,-0.0039716475,0.00032691224,-0.0015202502,-0.011906038,0.04802897,-0.022231705,0.021401595,0.010521636,0.027287066,-0.028979043,0.05267312,0.0089875255,-0.041778054,-0.026760299,-0.034491215,-0.009663483,-0.037923545,0.0010417184,-0.06782947,-0.03137056,0.03830884,0.013819749,0.036296837,0.013348329,-0.03356518,-0.017888147,0.0007507048,0.0017439467,-0.0060779797,0.012123702,-0.029785741,-0.039907224,0.02267559,-0.017187241,-0.014088679,-0.018712414,-0.033986166,0.026435481,0.0065714386,-0.016370453,-0.020160373,0.016827714,-0.03147201,-0.05450401,0.03451184,-0.005332109,-0.018053275,0.011983833,0.012198791,-0.028362848,-0.0054922323,0.038699795,-0.008396385,0.01379052,0.015809046]
510800	Maintenance & Repairs	Repairs and Maintenance	expense	[-0.0338599,0.011275106,-0.01460073,0.025573658,0.005904911,-0.0034003193,0.04383168,0.025035545,-0.006286046,0.009275526,-0.00023933337,0.0036390072,0.0090089375,0.007016346,-0.043696262,-0.05136868,-0.0056689335,-0.008942152,-0.0055494094,-0.056421004,0.018268606,-0.045117155,0.0141200535,0.006392642,0.016821356,0.030708272,-0.025516793,0.021107946,0.03137235,-0.0113860015,-0.037055764,-0.041657154,0.02392331,-0.030260611,-0.017373938,-0.06329848,-0.049420167,-0.03405403,-0.055188116,0.029697224,0.008757339,-0.053014673,0.03372664,-0.011589849,0.032809027,-0.009798068,-0.021549884,0.002725264,-0.034448706,-0.0154260965,0.007993908,-0.040856123,0.07112366,-0.052077767,0.021269498,0.029004673,-0.03299017,0.030935682,-0.069944784,0.00730341,-0.053177003,-0.0025296502,-0.02095225,-0.0065961005,0.029409416,0.077985525,-0.034699757,0.027582884,-0.008800561,-0.019373378,0.011330625,-0.0063887904,-0.05094185,-0.024353258,-0.036531184,0.042134278,0.013985978,-0.03217611,0.0016058519,-0.004640875,0.008605983,-0.023272771,-0.027521659,-0.024107048,-0.025059272,0.04404173,-0.010306072,-0.029266564,0.004810377,-0.07028981,-0.015614079,-0.004770765,0.01578304,-0.0042393478,-0.05254307,0.014158942,-0.061032698,0.0054847426,0.007935028,-0.013531437,0.06515322,0.0026184677,0.038036056,-0.020172248,0.0124670435,-0.05622844,0.03418149,-0.0037294652,0.017020702,-0.01841524,-0.006897038,0.018680044,-0.029530099,-0.011306155,0.0012628181,0.0078011397,0.008892698,-0.033751097,0.0381806,-0.016673405,0.023320612,0.044525076,0.056418747,-0.039493915,0.035474785,-0.023884876,0.014856688,0.028431484,0.009491008,0.0015306671,-0.010981152,0.010732809,-0.019711172,0.05526058,-0.030146005,-0.032023843,0.01933693,-0.014356132,-0.004882149,-0.034231234,0.0056896494,0.022894623,0.013052179,-0.01681929,0.042726558,-0.010266922,0.019302914,-0.039358877,0.007879012,-0.010325001,-0.014882699,0.013486905,0.029914357,-0.013387996,-0.03765476,0.012724893,-0.020469459,0.018146183,-0.01818549,-0.03704657,-0.025598563,0.037792705,-0.062279806,-0.04598652,0.021827983,-0.010152144,-0.007452396,-0.015979083,-0.018139562,0.021042213,0.016104028,-0.030385645,0.033957288,0.0074076178,0.0055732825,0.02832985,0.081692554,0.012909732,0.023999777,-0.025741432,-0.040712062,0.006412523,-0.018892849,-0.02726701,0.005976914,0.046679005,0.042971358,0.0024070574,0.023548473,0.0044913082,0.025287135,-0.008078141,0.016351964,-0.00751866,0.030189823,-0.03277983,0.024620065,-0.015255394,0.01664505,-0.012031562,-0.008830114,0.008282616,0.01216281,-0.019777039,-0.04266423,0.025346877,0.020290686,-0.04555647,0.031162543,-0.061421324,-0.0070221107,-0.026326552,0.008990878,0.0005551401,-0.021817127,0.03477295,0.046082903,-0.010544426,-0.022523079,0.040738326,-0.06258753,0.03536065,0.013452032,0.01823802,0.0008073219,-0.027904931,0.0010668652,-0.0058861016,0.018596265,0.0081547955,-0.052099578,0.027881643,0.027200997,-0.0392142,0.01161146,-0.0031115233,0.0061297426,0.028183706,-0.0439109,0.0005527267,-0.008486957,-0.017860195,-0.0035499353,0.005206244,-0.023763448,0.028045166,0.029253324,0.049859818,-0.023115762,-0.03422367,0.005882876,-0.045051247,0.004610904,-0.009951438,0.01637648,-0.024435323,-0.0018812927,-0.018741392,-0.01661609,-0.016837051,-0.011741697,0.022728235,0.009052287,0.017653741,-0.014183404,0.0076341545,-0.057241444,-0.03786796,-0.011903885,0.01706369,0.007045597,-0.004307828,0.016281364,0.019944912,0.032357827,0.07845405,0.0297012,-0.024888737,0.023405217,-0.02297296,0.025403986,0.063936524,0.0065370556,-0.026101338,-0.016044538,-0.004289182,-0.036858264,-0.0102935005,-0.014984988,-0.0970023,-0.03522129,-0.04273209,0.0658985,0.00067523064,-0.048730582,0.0027499204,0.019388922,-0.1635608,0.022896748,-0.009107453,0.062027995,-0.0020134049,-0.0038090732,-0.020051831,0.02792879,0.0018726852,0.0022114003,-0.008533908,-0.06499981,0.0131729,0.033025105,0.016040547,0.0040383036,-0.0071283826,0.019316709,0.00933087,-0.018944442,-0.029684318,-0.06919773,0.026218465,-0.004650638,-0.064603046,0.03587813,-0.0018611054,0.013029254,-0.03724611,-0.018626159,-0.023704916,0.021258123,0.012276263,0.038935725,0.0067283954,0.004173696,0.037587877,-0.0068619386,0.037567873,0.0036489854,0.017035915,0.05675785,-0.023511294,0.06428767,0.0003587523,0.003421474,-0.015765766,0.0031888841,-0.00020840311,0.015841877,-0.049732395,-0.038597986,-0.008421417,-0.0051859724,-0.043835074,-0.009537274,-0.00030097945,0.031510618,-0.0068814005,0.056343455,-0.03482862,-0.03990613,0.018650567,0.007432018,-0.031103827,-0.036031,-0.016663238,-0.024205375,0.028252538,-0.048433963,0.009885645,0.0079237735,0.022775901,-0.012394228,-0.05569239,0.051118392,-0.023942431,-0.0068177087,-0.014419133,-0.11577385,0.00878326,0.010384614,-0.036941364,-0.026762426,-0.023115804,-0.0088235065,-0.0038623274,-0.011215055,0.015055491,0.24215816,-0.008836031,0.015215491,0.02873511,0.050176848,-0.013539419,0.015904246,0.02119457,0.010923993,-0.03653712,-0.032339547,-0.0047053695,-0.025811337,-0.012390163,0.017496692,-0.003907011,-0.04331649,0.035018083,0.06587353,-0.0141557325,-0.017521981,-0.0024834839,-0.032558914,0.010775223,-0.062063858,-0.028046433,-0.02040295,0.055873934,-0.044627994,0.01824357,-0.0060700383,-0.00824101,0.018328108,-0.022622531,-0.07639796,-0.0047055907,-0.0006978091,-0.015348863,0.076861605,0.055724133,-0.016733529,-0.030774703,0.021706102,-6.5210865e-05,-0.012738997,-0.069490455,0.037975322,0.0031657163,-0.0384906,-0.005728555,-0.013350903,0.040394235,-0.011257301,0.04320465,-0.038508438,-0.006520612,-0.009661609,-0.043721173,-0.029507365,0.05279943,-0.016184354,-0.01175963,-0.025569072,0.01136234,0.0012857028,0.011787458,0.007395592,0.0052115447,0.02954081,0.03419912,-0.029134138,0.021418082,0.010601055,0.037145015,0.019010784,-0.011228663,0.01172819,0.054627247,-0.002055537,-0.04938057,-0.07775441,-0.036378436,-0.005325371,-0.022778329,0.018490944,-0.037103653,-0.03212863,-0.00035016212,0.0005907118,-0.04531579,-0.031832006,0.019563576,0.005160452,-0.04510625,-0.010289048,-0.018089484,0.04031993,-0.037359197,-0.027862573,-0.040226832,0.002309336,0.00326134,0.000972367,-0.03831761,0.029055046,0.016686633,-0.013656187,0.034390803,-0.054763608,-0.021718375,0.0067792283,0.0071412562,-0.017993266,-0.016375622,0.0062398277,-0.0047195945,0.008359649,0.049620025,0.012517384,0.013013734,-0.009694587,-0.0055590235,0.009321841,-0.02919742,0.00021138992,-0.011845176,-0.032788582,-0.032747306,-0.022447493,0.049203318,0.019411014,-0.019640416,-0.019241689,0.0313181,0.08223224,0.009846224,-0.030613525,0.009534467,0.036807146,-0.01288805,0.0068343966,-0.012807731,-0.06180918,-0.017001705,0.024570474,-0.03235792,0.0076702326,0.02664565,-0.023206085,0.057982814,0.028032599,0.019314164,0.031146199,-0.037880603,-0.007169863,-0.07020352,-0.01692672,0.026079295,0.020679306,-0.03975256,0.024217483,0.00059834163,-0.03919903,0.08608169,0.09077957,-0.007683362,0.057187308,0.00024655164,0.00049649464,0.0074244253,-0.01634459,-0.026728656,-0.039851986,0.04579165,0.0040158695,-0.030025624,-0.022252059,0.042417597,0.022747153,0.046623398,0.022445638,0.04660895,0.0085238125,-0.045226336,-0.028054306,0.02197756,-0.02395803,-0.022507945,0.009942147,-0.01842683,-0.026842205,0.08496118,-0.01119284,-0.0059625506,0.019676458,-0.013384773,0.038536157,-0.018890398,0.019331034,-0.03500481,-0.037099436,0.030179128,0.030030485,0.03960594,-0.0026867087,-0.03640714,0.009979399,0.02817435,-0.010146235,-0.0073855068,0.013450358,0.014081907,0.012124974,0.023939854,-9.1461035e-05,-0.016674412,-0.013659059,0.049325608,-0.0033209184,-0.020603929,0.0005979649,-0.02356502,0.039688922,-0.044380084,-0.0057589933,0.023440316,0.0113532115,0.0013684013,0.016625445,-0.002927085,0.005189532,0.021716429,0.023331014,0.014431325,0.021894448,-0.028404923,0.025432624,0.029983906,-0.0027600133,0.0054877363,0.004663528,-0.005202037,0.048106775,0.032123562,-0.0108463485,0.025909666,-0.09335055,-0.025036266,0.010180682,0.03394202,-0.050934404,-0.013192093,0.0587028,-0.0017358258,0.0041990736,0.028118806,0.0043764813,0.00026415518,-0.0598816,-0.0415637,-0.0025075043,0.044430368,0.005362359,-0.0069540413,0.014560672,0.016207732,0.02375141,0.038518958,0.010083414,0.0188609,0.03882778,-0.022098219,-0.081951916,0.003023577,0.017187592,0.003721728,-0.008741666,0.032148764,-0.030584699,0.04046885,-0.038749717,-0.008154224,0.020036858,0.0062998706,0.023638137,0.024607798,0.015788587,-0.022642728,-0.0035997462,-0.035560865,-0.035893176,0.009589493,-0.02584755,0.010883756,0.017220408,-0.013576009,-0.011840472,0.005174379,0.0012481693,0.005363483,-0.006176894,0.02585768,-0.024623161,-0.012599789,-0.0022392848,-0.02413607,0.0029399174,-0.04352674,0.0017666725,0.015016355,0.011801416,-0.042052656,0.009406022,0.049855303,0.022940567,0.008957092,0.020755192,-0.012298082,0.040296957,-0.0013108943,0.032330185,-0.009924086,-0.04357239,-0.024106383,-0.034824144,0.0159382,0.022068212,-0.0038261022,-0.04309412,0.021776771,-0.032266054,0.010875611,-0.010220508,-0.014321915,0.060105357,-0.042436074,0.07275805,0.022130415,0.038738787,-0.047865655,-0.055044238,-0.03242571,0.059656892,0.0074976874,0.043107647,-0.051508687,-0.021880668,-0.0037504195,0.012586413,0.014155381,0.014504054,0.012840949,-0.02596307,-0.06173571,-0.009271181,-0.05978041,-0.020876294,-0.023184882,-0.02626234,0.03053746,-0.020835323,0.007715605,0.0076357783,0.02293524,0.010106143,-0.0029672687,0.0012385044,0.010926427,0.00888409,-0.00319622,-0.02865172,0.018818846,-0.020097317,0.03784876,-0.001165234,0.039066777,-0.000923573,0.011973561,0.06352941,-0.004296798,-0.017096331,-0.059452888,-0.0010475053,-0.011954368,0.0038187753,0.027664088,-0.007695646,-0.008048128,0.021807505,0.019958397,-0.017674286,-0.03241574,-0.05211388,0.005647344,-0.13912004,0.00665762,0.009070741,-0.006304747,-0.042510256,0.007001222,0.010694066,0.0043116827,0.007253625,0.020494701,-0.011517064,0.006655204,0.080307946,0.008965913,0.0101133585,0.050014816,-0.018837515,-0.027047548,0.021284083,0.042268977,-0.0052933944,-0.0035063003,-0.056057386,0.04243974,0.030122442,-0.026453556,0.04210824,0.008251426,-0.017545179,0.026779791,-0.015798932,-0.025184896,0.014452609,0.01991171,0.00282047,0.0012852062,-0.01068833,0.0001789372,-0.041983873,-0.008177018,-0.0002905125,0.015408982,-0.02839063,0.015142081,0.0057093296,0.0708282,-0.03478264,-0.008836303,-0.039502826,0.0065506273,-0.028696356,-0.0027649987,-0.020608967,0.0053457073,0.0047729327,-0.0029196036,-0.018695317,-0.001435917,0.0047512315,0.04846468,-0.06684638,0.048681594,-0.015593403,-0.05681758,0.048320513,0.03522943,0.005977315,-0.0072614434,0.020077534,-0.03736435,0.016270773,0.020807425,-0.00051574514,-0.01774241,0.041712206,-0.0262601,0.02460626,-0.004223577,-0.0067673577,0.020316046,0.0075352467,0.01999045,-0.029402588,-0.009754427,0.03265052,0.031120282,-0.027083106,-0.00953579,0.02535946,0.030283852,-0.01168329,-0.04243218,-0.0028488177,0.03180321,0.041631132,0.028856263,-0.011820172,0.02612259,-0.016449358,-0.018390046,0.034531865,-0.025144834,-0.04742414,0.0063729617,-0.024633339,0.035993606,-0.072154336,-0.043619584,0.011648128,-0.015422438,-0.023880074,-0.02276423,-0.0061929952,-0.006168525,-0.04768826,0.0031092975,-0.015641836,0.0057713105,-0.041672938,0.022341182,0.010793478,-0.0095820725,0.021272033,-0.04131386,0.04211446,0.010677333,0.026798952,-0.008921835,0.045516822,-0.002459885,0.027849505,-0.040847354,0.011111006,0.019117862,0.0020916956,0.0060168076,-0.014965508,0.040515255,-0.05279974,-0.024252422,0.009273484,0.016333079,0.0011743847,-0.04081616,-0.013681988,-0.018387647,0.028257823,-0.022961155,0.06590713,-0.03254945,-0.0047815824,-0.016760767,0.017125515,0.04900644,-0.01649523,-0.0033057902,0.0052829995,-0.013972016,0.00714742,0.023152288,0.00969922,-0.030193482,-0.024958508,-0.02777298,-0.010355598,0.046267603,-0.025119998,0.018345872,-0.005338728,-0.02740125,-0.0056609674,-0.005773436,0.004685955,-0.019319149,0.0016462248,-0.009682704,0.0024099797,0.018770726,0.042528667,0.015367429,-0.01851185,0.03160747,0.068676725,0.019093981,0.035052333,0.031153603,-0.027290506,0.0077008167,-0.03023219,-0.039396748,-0.019429011,-0.02348007,-0.0694202,0.026738044,-0.01829437,0.006073413,0.031816334,0.08017004,0.009190933,0.055408813,0.033518802,0.0055659157,0.006077863,-0.044385288,-0.0015294277,-0.034509156,0.026571497,-0.0016311611,-0.053962216,0.012768418,-0.022898423,-0.0026172618,0.012528138,0.032086484,-0.030315073,0.039875932,0.019696653,0.0017276758,0.031940855,-0.010875726,0.0043137185,0.042705603,-0.0012449041,-0.025123931,0.031588342,-0.038654152,0.022148822,-0.021487562,-0.025569798,-0.014961022,0.029797656,-0.014083628,-0.030840013,0.028955296,0.029834652,-0.012490398,-0.005060708,0.014936576,0.023842743,0.0060305516,0.07570729,-0.009318138,0.01682832,0.009453846]
510900	Training & Seminar	Training and Seminars	expense	[-0.062054947,-0.028635044,-0.060579512,-0.008442546,-0.0030095612,0.017514989,0.002505235,-0.0055820304,-0.0014889966,-0.0007636825,0.029787589,-0.026281377,-0.023777364,0.019788954,0.01447669,-0.044449084,0.025718857,-0.0129118785,0.021700375,-0.029148692,-0.0048125926,-0.026992517,0.049458213,0.013566142,0.0038744956,0.025465041,-0.02073376,0.003595166,0.013295005,-0.019998385,-0.013672987,-0.0075565977,0.056652438,0.009498859,-0.0118372,-0.049750593,0.003999682,-0.017649816,-0.06335938,0.03647195,-0.0025304994,-0.044571713,-0.010316752,-0.003433782,0.053318165,0.022067396,-0.02735116,-0.0124218175,0.0011957451,-0.011019763,0.008965133,-0.02912822,0.07275934,-0.010514556,0.042935457,0.00869165,-0.052235417,0.015077408,-0.113798186,-0.016202185,-0.0568894,0.01876764,-0.004905849,0.014943708,0.018900495,0.036235817,-0.032870438,-0.004513266,-0.0026961828,-0.023374062,0.07636517,-0.008435521,0.00473636,-0.020984782,-0.085418105,0.04215013,-0.02237441,-0.011315296,0.004935267,0.018183047,-0.00910404,-0.032821197,-0.08328853,-0.04240118,-0.011473496,-0.012218547,0.04405861,-0.012137623,-0.018630842,-0.00943352,0.014048832,0.010576195,-0.017181301,-0.01196711,-0.014954954,-0.055843122,-0.033747617,0.01500592,-0.026553484,0.004127424,0.04638821,-0.013264648,0.030080907,-0.014833555,-0.0024698838,-0.025518063,-0.0067663817,0.011073958,-0.011796822,-0.011940582,-0.019403078,0.04097451,-0.02199044,0.02232001,0.033070013,0.023616549,0.032104585,-0.0029299331,0.044812787,-0.024262074,0.04629482,-0.024864914,0.06381877,-0.05068031,0.0487907,-0.05320916,0.030102184,-0.0003460316,0.0072281077,0.03266105,0.01406932,0.007628291,-0.02481188,0.024512082,-0.0013369999,-0.020588484,0.013973345,-0.038211025,-0.007914948,-0.030346883,0.0012224603,-0.0020108745,-0.007591653,0.020379584,0.008456318,-0.058281105,0.008228879,0.014566915,0.015710479,0.0054921205,-0.032380275,0.034352798,0.044033,-0.024075577,-0.018423926,0.024682116,-0.02846073,0.0018905975,-0.006501556,-0.02704218,0.021319201,0.06125084,-0.03717005,-0.017607952,0.03634746,0.013379468,-0.018375639,-0.0074830675,-0.015091366,0.024922373,0.018169094,0.0016892812,0.037774857,-0.0191403,0.011930658,0.02639989,0.073932044,0.029578075,-0.04464249,-0.04152443,-0.04511129,0.0033219173,-0.043781884,-0.035029527,-0.009770584,0.027922506,-0.0047300295,-0.0234184,-0.007279052,0.016044935,0.030987002,-0.02873394,0.028232597,-0.015850892,0.06464016,0.011454362,-0.01009792,-0.018973375,0.041785147,-0.0079056155,-0.056278713,-0.007933247,-0.034326658,-0.016583523,-0.026053814,0.013059996,0.0320271,-0.00029518042,0.021216996,-0.01571819,-0.0057610096,0.019072354,0.03186436,-0.04054856,-0.00041621854,0.051951494,0.028255854,-0.009746559,0.0056182067,-0.009479002,-0.03372196,0.05950909,0.025805082,0.025099225,0.0031465697,-0.028722795,-0.003195476,0.019516531,0.0479832,-0.020950537,-0.03267575,-0.008575639,0.026437173,-0.041180417,0.020622304,0.0033235475,0.01449219,0.06367616,-0.0045355344,-0.02612672,-0.003330811,-0.028799817,-0.0026133016,0.018077817,0.03202375,0.019551476,0.03271813,0.09166817,-0.020436767,-0.039821252,0.018745618,-0.016100744,0.020043196,-0.021359198,0.004833895,-0.012539668,0.017185098,-0.0041713873,-0.018625485,0.017864171,0.01627484,-0.032023128,0.03390335,0.017509626,0.011759343,-0.007056781,-0.04254902,0.015185404,-0.031486724,0.007724193,-0.003743982,-0.050333522,0.018141512,0.010829349,-0.011629133,0.07685699,0.02609813,-0.013521364,0.05799559,0.019926313,-0.032870017,0.044553112,-0.005883686,0.0067789326,-0.02669396,0.006998537,-0.028940467,0.02549891,0.01103717,-0.029589392,-0.037143413,-0.011973758,0.07774189,-0.034409266,-0.02942841,-0.0013562136,0.042845733,-0.13865502,-0.014287168,-0.011324949,0.013924025,-0.014290155,-0.019907817,-0.01955758,-0.029045451,-0.005298772,0.01575772,0.017568788,-0.06739174,-0.021750612,0.019604875,0.021354591,0.016172444,-0.033632554,-0.015136373,-0.01612273,-0.024742316,0.00041387288,-0.07833398,0.059659533,0.02485431,-0.047278117,0.067304865,0.024522811,-0.036617562,-0.0015374663,-0.041015703,-0.020105679,0.04865021,0.010119844,0.014785318,0.030221986,0.034402028,0.016420849,-0.017522018,0.05505558,0.0033549813,0.04466423,0.02702368,-0.03732524,0.056003794,0.0050641745,-0.0023025994,-0.005316907,-0.0070867203,-0.024040947,-0.017738398,-0.007896618,-0.009869607,-0.01576605,-0.045827907,-0.030712336,-0.069411315,-0.030999845,0.00794563,0.011271813,0.017530464,-0.0013852075,-0.09155919,-0.0038848054,-0.039744206,-0.015601769,-0.008875187,0.01896305,-0.017633837,0.016091682,-0.043181635,0.029960142,-0.013689652,-0.024068294,-0.008775751,-0.0012812772,0.033614326,0.014197393,0.0055654566,-0.023431329,-0.09187878,-0.013136393,0.008447818,-0.037947923,-0.018242897,-0.04168066,-0.020367935,0.02979153,-0.03337832,0.0072059203,0.20249292,-0.002228385,0.040498346,-0.013982855,0.002121119,-0.01789232,-0.030564243,0.010966904,-0.004128468,-0.023885401,-0.011397848,0.012589532,-0.006449072,0.011829994,0.00036316563,-0.015738403,-0.044760708,0.016275784,0.055072032,0.010773591,0.0025837182,-0.0023764572,-0.04180093,-0.017546859,-0.074203715,-0.010434882,0.0017664529,0.040531315,-0.02984722,0.025723018,-0.015560884,0.018215757,0.008607929,0.023345035,0.04195051,-0.015612762,0.011539711,-0.029703856,0.057285246,0.026046064,-0.022167359,-0.013596513,0.034396764,0.009035291,0.0047494494,-0.052066885,0.029709771,-0.013282194,-0.03026249,-0.028909886,-0.011677948,0.0054585747,-0.04505091,0.012841428,0.027502865,-0.0045347125,-0.018873813,-0.044814784,-0.048687063,0.045348026,0.0026433605,0.0074220784,-0.016501814,0.0058119777,0.019516747,0.0019950331,-0.009734796,-0.008926566,0.028978383,0.034566395,0.033828206,0.015839523,0.040292535,0.015593686,-0.0071273404,-0.0037855045,-0.01188005,0.06483489,0.013259106,-0.020834237,-0.044141177,-0.029267618,-0.03682543,0.019205013,0.022250725,-0.038786363,0.020973021,-0.032464523,-0.026056916,-0.023402765,0.020115145,-0.002323237,0.004285527,-0.062239707,-0.04211888,0.0032194015,0.010537498,-0.033665664,-0.06266092,-0.01528691,-0.011190349,0.019433241,0.027868241,-0.03996867,0.0358441,-0.02164758,-0.014010958,-0.01856879,-0.039053883,0.00010860029,-0.030153466,0.00057909294,-0.002786903,-0.012101155,0.03345688,-0.00039106765,-0.041659534,0.016512316,0.018876018,0.0022601394,0.024775757,0.05333418,-0.015889613,0.03658272,0.034097552,0.0034578783,-0.026277946,-0.027141454,0.04167092,0.043716297,-0.0060035675,-0.029020093,0.016872153,0.024041003,0.037377197,0.0037203804,-0.016633874,-0.00024163116,-0.014683171,-0.031222776,-0.015272537,0.03048535,-0.028161228,-0.009010148,0.013258502,-0.028365463,0.00807843,0.027370565,-0.014209043,0.050727148,0.017186686,0.021972312,0.012693013,-0.03632138,0.021807611,-0.066394374,0.015011189,0.01462741,-0.0013870653,-0.020722028,0.018325647,-0.036946107,0.008895857,0.094074346,0.040696256,0.027687836,0.007145812,-0.010273589,-0.0058158087,-0.0066773347,-0.023580616,-0.013883511,-0.010122728,0.038485203,0.049168445,-0.015164818,-0.01879275,0.011095446,-0.019152036,0.0028843365,0.001874566,-0.0025495088,-0.0018731883,-0.04996605,-0.013558509,0.0025917473,-0.011983367,-0.026689641,-0.03134015,-0.029501598,0.0073326756,0.062991686,-0.02368147,-0.020299137,-0.03257311,0.049428333,-0.00033052772,-0.012691523,-0.00945884,-0.024720212,-0.009194263,0.03725257,0.031102011,-0.010402012,0.00964678,-0.04053514,0.0056794677,0.04553266,0.030585231,0.018686006,-0.01458452,-0.00265229,-0.049940825,0.005903076,0.004992592,-0.013067321,-0.009116134,0.029743642,0.014782952,-0.012697114,0.02527492,-0.032979302,0.0015789497,-0.06652403,-0.0045852615,-0.007468299,0.011787513,0.022168523,-0.0018308907,0.046542887,0.010106462,-0.006700012,0.0016007854,-0.0028042058,0.047229417,0.0063771955,-0.023767289,0.056196656,-0.010754183,0.023740884,-0.033070344,-0.03559162,0.031323332,-0.02895497,0.0031969994,0.03011016,-0.036618885,-0.033924818,0.010902346,0.042162795,0.051514126,-0.013441986,-0.013404437,-0.041468907,-0.0028744782,0.024201402,0.0007239351,-0.030056607,-0.060938008,-0.005092259,-0.0063948804,0.06307277,-0.016567163,0.013899405,0.02578728,-0.05526481,0.041128904,0.030057387,-0.011045081,0.02020934,0.025796758,0.013388189,-0.06708996,0.002522808,0.04279331,0.00075112813,-0.03395393,0.014131375,0.01032832,-0.021709442,-0.051201217,-0.018193912,0.026054697,0.0027630553,0.0037370496,0.048191037,0.0021552166,-0.002217023,0.0013141959,0.022540797,-0.016653769,0.0018470987,-0.05438261,0.031997595,-0.026812535,0.0011285077,-0.0025552674,-0.024223307,-0.0051340368,-0.020320952,-0.009804407,0.05389395,-0.01910821,-0.009478613,-0.047492802,-0.012365568,0.0018660098,-0.049145784,0.0015046734,0.018109078,-0.021713575,0.009687077,-0.005525539,-0.026919477,-0.015919399,-0.0154274395,-0.0014292985,-0.025548851,0.008289089,0.021137578,-0.008785109,-0.04075423,-0.022684371,-0.040746894,-0.048560273,-0.017292894,0.037307527,-0.00505962,-0.05678045,0.017138824,-0.047817864,0.00054613454,-0.00047295177,-0.032011442,0.025110299,-0.055061087,0.08977666,0.00082387886,0.023329394,-0.0053639384,-0.012578394,-0.07790148,0.051485587,-0.012628886,0.0074057584,-0.021541435,0.016757352,0.0084187435,-0.023857273,-0.009055146,-0.011460966,0.016964864,-0.053411074,-0.04571813,-0.0072705685,-0.04634547,-0.018823799,0.04479538,0.010256068,0.058767203,-0.03708079,0.027095214,0.010299517,-0.01010716,0.004791679,0.023007834,0.0057681794,0.011870258,0.030447682,0.018370114,0.0032426591,0.028669748,-0.028034728,0.043036494,0.044267584,0.029447205,-0.0042703305,0.016842574,0.039094992,-0.031755015,-0.018738834,-0.04022136,-0.029695835,-0.01756381,0.084768176,0.019396799,-0.0068086823,-0.030850846,0.03092185,-0.0079352325,-0.02399668,-0.03887919,-0.07629336,0.01566776,-0.11924715,-0.02129094,-0.025743863,0.0029451733,-0.0017123614,-0.030410606,-0.0066215345,0.014139986,-0.0016057768,0.016090509,-0.0051704557,-0.0146786915,0.02679002,-0.010681239,0.024162756,0.051084068,-0.023970753,0.025177198,-0.013886909,0.07341813,-0.0054943473,-0.019094966,0.019087346,0.03126661,0.010584107,0.034398954,0.0350191,0.029855076,-0.020339167,0.010433584,-0.02121062,-0.06318113,0.012879443,0.042300683,-0.013078466,0.036601476,-0.024240527,-0.0048396057,-0.0112833725,0.010918771,0.011120389,0.040104516,-0.052092846,-0.0041273995,-0.0031374134,0.086968705,-0.019038212,-0.02141291,-0.0356431,-0.02856665,-0.043579005,0.032032385,-0.040212713,0.013277539,-0.01605604,-0.050967604,-0.053571306,-0.0031466878,-0.026845407,0.035010368,-0.038760737,0.08231708,-0.026556958,0.016451687,0.039156478,0.07387266,-0.034033537,0.018238463,-0.0034709726,-0.020061517,0.0133673325,0.02625478,-0.014904251,-0.016702998,0.02889811,-0.010109943,0.042422183,0.013347641,-0.00062365056,-0.0036662125,-0.035037447,0.01419062,-0.05744119,-0.022959787,-0.012887557,0.036102206,0.0129206395,-0.014015346,-0.010571175,0.026712762,-0.03408663,-0.040115684,0.021943098,0.012090693,-0.0031522657,0.026691206,-0.016812695,0.03602093,-0.016084816,-0.0144447265,-0.0016749895,-0.0024165993,-0.047265463,0.02446244,-0.027013255,-0.0033185512,0.008136001,-0.019201495,0.02509224,-0.0050588385,-0.017982969,0.004447513,-0.006669939,0.004781187,-0.08866795,0.03959197,-0.025023587,0.0057210396,-0.0404882,0.0069844527,-0.004551064,-0.048726868,0.012568046,-0.04724888,0.031068388,0.056552995,0.028507644,0.013408106,-0.015466653,0.0401159,0.01141198,-0.020522665,-0.0017021414,0.013373176,-0.020338217,-0.039799877,-0.004095577,0.065701514,-0.06105725,-0.015821021,-0.031508166,0.02290666,-0.006402441,-0.0071061705,-0.0040896107,-0.0032107516,0.06436073,0.012969598,0.068944454,-0.053701807,0.015857091,0.0031140433,0.012620051,0.02313939,-0.018880492,0.0020562378,-0.016462635,-0.0047489824,0.025145652,0.018366717,-0.026261296,-0.002836721,0.011479913,-0.036199547,-0.018023936,0.02356551,-0.011626438,0.033812623,-0.005877654,-0.000888765,0.013718787,0.026850032,-0.0019861653,-0.0045300093,0.02865031,0.059999272,-0.019191418,0.038513944,0.0629472,0.0011175593,0.018586047,0.008615171,0.020732364,-0.006276295,-0.0054102005,0.006788138,0.0075993617,-0.00671284,-0.030150775,-0.0022951437,0.056583516,-0.03431826,0.0063354596,0.045785893,0.0058278656,0.00047302226,0.020637415,0.07873245,-0.05548994,0.019754287,0.008139922,-0.0064369487,0.011302921,-0.027697967,-0.042121198,-0.019543763,0.026614413,-0.0011866543,-0.024469316,0.034209922,0.0007154318,0.005764208,0.01824412,0.020563573,0.0069566574,0.005476081,0.046665344,-0.004436758,0.028796326,-0.06924993,-0.0025008514,0.078430876,0.038595755,-0.010918082,0.0007805502,-0.05510872,0.00070829905,0.005328515,-0.023000974,-0.04411399,0.037855964,-0.030838119,-0.041539896,0.06635762,0.03449916,-0.015096451,0.018301005,0.0011283782,0.0014817866,-0.019238936,0.05851537,-0.035272337,0.007973155,0.04641759]
520100	Office Rental	Office Rental	expense	[-0.059841752,0.034703493,-0.02452822,-0.011769996,-0.0053022117,0.025595674,-0.016523793,0.0133155435,0.055532005,-0.027913846,0.04897104,-0.020185139,-0.0029309043,0.011323458,0.021480758,-0.04516994,0.014142249,-0.019477572,0.008514815,-0.005926371,0.012307809,-0.023252027,0.024356497,0.030728584,-0.020478027,0.01556081,0.010609214,-0.0036237515,0.064757735,0.0054263016,0.03367439,-0.0014332361,0.09376786,-0.020869013,-0.010355865,-0.03002559,-0.015980797,-0.001718579,-0.08299207,0.024979709,-0.035270024,0.048988216,0.005387147,-0.014251557,-0.0067001143,-0.0068745487,-0.04375907,-0.011337866,-0.06057998,-0.016157625,-0.038119562,-0.012246489,0.06276315,-0.021835422,0.048625063,-0.0066758604,-0.02724055,-0.036070496,-0.09827046,-0.032614592,-0.041465633,0.029959206,-0.03859443,-0.03247258,0.06542724,0.03792288,-0.015280021,0.043976013,-0.009443505,-0.031036127,-0.0021215137,0.009395972,-0.03962788,-0.042519,-0.06414396,0.009265976,-0.0187468,-0.012945373,-0.007184711,0.021751469,0.024588501,-0.0077412673,-0.014507038,-0.0071797883,-0.036451895,0.03131006,-0.006509911,0.034054562,-0.0053037154,-0.017419355,-0.008948661,-0.01765811,-0.0014816206,-0.022109592,-0.023054505,-0.043342564,-0.019718777,-5.6885914e-05,0.015577186,0.0217083,0.027880749,0.010478592,0.008150156,-0.012430832,-0.027616668,-0.015560249,0.039320372,0.021719506,0.02347023,-0.02833215,-0.014284306,0.0015855699,0.030928709,-0.019870175,0.015810266,0.018831028,0.033806738,-0.021325352,0.035785623,-0.0015922997,0.021777812,-0.016246296,0.036747094,-0.031392325,0.0052882666,-0.02771953,0.016094996,0.016582876,0.0023286648,0.010485343,0.009100316,0.029010441,-0.07858495,-0.0023696013,-0.037356842,-0.028508732,0.029766744,-0.042042714,-0.008696051,-0.033769548,0.05096578,0.043645736,-0.0186621,-0.015436137,0.04041713,-0.029567821,0.0081896875,0.031789582,-0.0007591162,-0.013572558,0.021842603,0.031332064,0.0058605047,0.018869769,-0.02340776,-0.017149298,-0.021359721,0.007023484,0.0012324513,-0.0046516615,-0.00879061,0.057748526,-0.04041386,0.00022687348,-0.0077771177,-0.0031580236,0.015934447,-0.019530129,-4.841435e-05,0.019174067,0.04939111,-0.06012595,0.009656941,-0.025791386,0.023761053,0.02374894,0.041254953,0.024361568,-0.0052135843,-0.05355936,-0.017780328,0.026993334,-0.033806983,-0.012785905,-0.03651172,-0.0154979145,-0.0018559016,-0.0100020785,-0.0058074165,0.027412547,-0.010058472,-0.0055008223,0.005832586,-0.030356083,0.06563342,-0.013350336,-0.06415582,-0.016623061,-0.021693023,-0.015770696,-0.06357365,0.02016615,-0.0127899535,-0.011600684,-0.076135546,0.011926751,0.008850034,0.029416583,-0.00633492,-0.054032605,0.014326553,-0.0005150601,0.0014100111,-1.2041427e-05,-0.033208422,0.02810436,-0.0010301878,0.014007569,0.024615157,-0.033371452,-0.004911115,0.010565687,-0.037770346,0.020880874,-0.0015693948,0.003674583,0.02679469,0.02037711,-0.015665239,-0.018205155,-0.03341737,0.0036491812,0.043560244,-0.012768667,0.03235969,0.015891246,0.009990397,0.037491817,-0.013389143,0.04248985,-0.035594877,-0.019106919,-0.03153162,-0.021428104,-0.04363535,0.0283676,-0.0018951013,0.043854255,-0.046875007,-0.008731593,-0.0021977401,0.0029286193,-0.006159942,0.011383766,-0.017364116,-0.03066492,-0.020812847,-0.0030905074,0.041846827,-0.011057471,0.03294261,-0.012391196,0.00012792677,0.020339463,0.002604069,0.011726361,-0.07413534,0.0048637274,-0.00085816986,0.003804648,-0.04010986,0.0074387947,0.0393027,-0.020586522,0.023557277,0.017527863,-0.012057374,0.022353616,0.013301045,0.044532448,-0.022794895,0.013622214,-0.015788477,0.0058097094,-0.010392502,0.018146675,0.043052282,-0.002271627,0.011120502,-0.075884156,-0.027141534,-0.026523901,0.05823392,0.007036926,0.009339752,0.01261543,-0.016170688,-0.1536674,-0.018658033,0.011511552,0.029774517,-0.006193548,0.0080213975,-0.016147798,-0.0019891572,-0.058055516,-0.0046989205,-0.0023569015,-0.065492764,-0.031209638,0.02871919,0.03561791,0.018772913,-0.0032591827,-0.015210955,0.015324387,-0.019487761,-0.018335126,-0.034478616,0.047765728,0.033746507,-0.04191128,0.036505535,0.019293247,-0.012232203,0.006114963,-0.06839825,0.018900784,0.011146302,0.0036037692,0.012951525,0.045958046,0.047750786,0.048876084,-0.028823892,0.0055669956,0.018470967,0.020917062,0.05648216,-0.020046446,0.02231349,0.014555737,0.0027100393,-7.394063e-05,0.0035947752,-0.019439153,-0.03251006,0.009703118,-0.013025525,-0.00089006155,0.0029893997,-0.031068452,0.0010481892,-0.023032648,0.03800112,0.00037170463,-0.0017221726,-0.012148146,-0.0819017,-0.005935425,-0.031865392,-0.017319499,0.0029870046,0.016425852,-0.012924269,-0.0003651981,0.0096873995,0.05578264,0.018363534,-0.009033161,-0.009442795,0.04132858,0.022606699,0.0050278436,-0.021924201,0.025985274,-0.085698,0.030874493,-0.026749296,-0.01208029,-0.00027212594,-0.0481408,0.018279362,-0.003931631,-0.014713085,0.07843549,0.23599055,0.040041585,0.073208876,0.010858165,0.034434415,-0.037958704,0.0024940195,-0.008470368,0.031513575,-0.031042702,0.02262282,0.04324702,0.015029824,0.049773,-0.0015754442,0.012969939,-0.072087854,0.007021955,0.07294429,0.018709378,-0.0051384354,0.018422086,0.008596886,-0.017952092,-0.0076907612,-0.034600947,-0.027567273,0.04526,-0.033759557,0.016312895,-0.039470248,-0.0020986055,0.03484785,-0.023185749,-0.030750833,0.015480536,-0.040512092,-0.02786065,0.034464996,0.03389,-0.035642676,-0.02962095,0.011303063,0.025215948,-0.044771444,-0.05571204,0.016439512,-0.010652836,-0.013815547,0.0043879845,-0.04825819,-0.009189532,-0.048448395,0.028394757,-0.0073534967,-0.016837344,-0.037040252,-0.02687027,-0.043020073,0.060079906,-0.0033163868,0.013327404,-0.06848366,-0.002265841,0.030435823,0.00014844321,-0.045261562,0.028673865,0.011156956,0.011492634,-0.009262204,0.015630651,0.017162243,-0.0037119032,0.025435654,0.010953746,-0.0116398875,0.04005123,0.017303584,-0.00071252976,-0.02816723,-0.012289283,-0.013323054,0.00909368,0.008338478,-0.028860152,-0.05264806,0.028577859,0.007193599,-0.030952914,0.032661743,-0.012949498,0.028443353,0.025842618,-0.03355842,-0.036391117,0.027580146,-0.047809858,-0.03844821,-0.039544962,0.044818398,0.017603766,-0.017147226,-0.065292925,-0.018891172,-0.026011817,0.051146023,-0.025777098,-0.01726393,0.008829596,0.0036709972,0.018591573,0.019153142,0.011158204,0.03297482,0.015211818,0.014929084,0.040563207,0.018554367,0.017466279,0.021946583,-0.019207336,0.012031041,-0.018344712,0.020364443,0.016675659,-0.00027694754,0.007877296,0.0023084248,0.031297848,-0.024103407,0.0015317538,-0.049510177,-0.028280644,0.032990426,-0.042572163,0.025042905,-0.024378842,-0.01293255,0.0005421911,0.015262206,0.04113378,-0.016969036,-0.020069854,-0.01750596,-0.0056959833,-0.044997618,0.004403788,0.00037473213,0.067361034,0.029430818,0.0055760746,-0.0065888762,-0.016440146,0.034277692,-0.053999193,-0.01936611,0.011492597,0.03221523,-0.027284052,0.0010708151,-0.02425197,-0.0025390168,0.092245236,0.00020706988,0.026144613,-0.016378388,-0.013715842,-0.0037230018,-0.047997534,0.0022175568,-0.026088454,-0.02482552,0.07733299,0.01459487,-0.016177516,0.006957817,0.031893767,0.0077177854,-0.02853427,0.030678893,0.030863881,-0.04700975,-0.07682609,-0.01648378,0.059027,-0.0036403602,-0.021086866,0.0057206056,-0.06692531,0.0055771703,0.06371657,0.038315974,-0.025978796,0.012048853,0.026250219,0.055435535,0.03059227,0.05113633,-0.023713686,0.0005564135,0.028999189,0.055041563,-0.016815547,-0.009261643,0.0028113553,0.024412291,0.040352825,0.028997526,0.044203855,0.011696879,-0.008504648,0.0010919196,0.031920936,-0.0024618146,-0.002810305,0.017176256,0.07251284,0.028006611,-0.07233731,0.044883143,-0.021310601,0.024814466,-0.047380295,-0.016449144,-0.013076759,0.01226816,-0.014993967,0.04068365,0.011439988,0.0008067808,0.013296388,0.03175712,0.0045088544,-0.012285434,0.009176074,0.03209907,0.042070083,-0.012619968,0.022631591,-0.024564281,-0.025009926,0.060473625,0.030475175,-0.010131431,0.043098178,-0.041577917,-0.00037765628,0.038743757,0.06838206,0.023687057,-0.052877933,0.01001058,-0.023211759,0.011084918,0.02725063,0.042558014,-0.028236812,-0.043245368,-0.0036218106,-0.013862255,0.031702835,-0.003498162,0.021287305,0.011257476,-0.025664728,0.050992195,-0.0011934583,0.0152322585,-0.006003903,0.0005922897,0.005281383,-0.040545784,-0.0075399983,0.012881729,-0.025821824,-0.02864714,0.026748294,0.030465694,-0.028792024,-0.058659274,0.006767082,0.022289127,0.03068462,-0.032441806,-0.01172135,-0.015302361,-0.008310026,-0.027281327,-0.0066271657,0.018645419,-0.008667997,-0.033971224,0.043353103,-0.042302947,-0.017217077,0.029385533,-0.032411713,-0.031768527,0.008172984,-0.006963048,-0.0055910847,-0.036463592,-0.051546685,-0.014484035,0.029663512,0.0074610035,-0.037796903,-0.009691962,-0.010404681,0.005355939,-0.0035290848,0.01908136,-0.0041021034,0.07158952,0.009191107,0.025231697,0.005576869,0.027685061,0.01100968,0.025159385,-0.0029780043,-0.012443445,-0.013262581,-0.01361643,-3.80068e-05,-0.0016216978,-0.04160453,-0.06413327,0.051007114,-0.018165043,0.024870403,-0.0076476457,-0.021256108,0.03752372,-0.010809582,0.092072695,0.006568381,-0.000569421,-0.037010167,-0.03069789,-0.03314916,0.015491427,-0.033874776,0.009469613,0.014120775,-0.0073782606,0.007411341,-0.015837785,-0.04268325,-0.009148461,0.020964976,-0.011104339,-0.038187113,-0.017417869,-0.05640671,0.027748035,-0.05615785,0.0032526043,0.014431908,-0.03804922,0.03760471,0.027674848,-0.023477962,0.012646491,0.0062192637,0.0073772958,0.0005663797,0.03742327,-0.013869018,-0.009356807,0.012176798,0.0009601321,0.054512627,-0.0022754483,0.067597866,-0.032106742,-0.05901123,0.021166591,-0.037415173,-0.012683041,-0.074178055,-0.021359412,-0.031098466,0.010072503,-0.028117904,-0.018205583,-0.016169574,0.01947968,-0.0023262126,-0.02379844,-0.026498847,-0.009641679,-0.011955631,-0.14666677,0.0105200065,0.014433469,0.006131451,-0.024511972,-0.00045988703,-0.038398504,0.043608025,0.0041841324,0.0015282786,-0.009696207,0.036785793,0.018865146,0.00347664,0.032822534,0.033858865,0.011084483,0.012749693,-0.008112933,0.06426089,0.021548707,-0.008029916,0.03898975,0.03289596,0.0087582,0.023707662,0.022414146,0.006653668,-0.054221306,0.03557646,0.018414568,-0.017323399,0.0318327,0.026856178,0.02708082,0.027122408,0.008717149,-0.042701982,-0.007779143,-0.010975029,-0.050511185,0.03441316,-0.034290954,0.022401238,0.0012237851,0.019288834,0.00938472,-0.018702544,-0.032351166,-0.034453373,0.01332701,0.047790363,-0.08853267,0.047030706,0.013839642,-0.017018575,-0.04340941,-0.02529853,0.04850759,0.017188735,-0.0072829127,0.058141846,-0.019688673,-0.029511955,0.033035338,0.012046191,-0.030806338,0.04968928,0.01855702,0.032190315,-0.0596838,0.013505929,-0.023070268,-0.0231613,0.015584557,0.00013163389,-0.00037376507,-0.006602607,-0.06468989,-0.013279363,-0.021832807,-0.016268905,-0.014161086,0.022592656,-0.009850125,0.016562816,-0.024185872,-0.014094113,-0.05428916,-0.0054351655,-0.063976556,-0.04012277,-0.013160747,0.004208777,-0.0005740708,0.0032284348,-0.046354152,-0.0010220675,-0.0043852427,-0.037085593,-0.024226015,-0.027719853,-0.0074435812,-0.0678023,-0.015509113,0.011294119,0.020561656,-0.04452882,0.015064014,-0.039584972,-0.018519197,-0.031152504,0.00943517,-0.005159518,-0.01383438,0.04242539,-0.026280666,0.017922742,-0.016313745,0.02899026,0.028027035,0.010625501,-0.0072957603,-0.04000039,0.059591684,-0.021722285,-0.0015199967,-0.00922259,0.036004297,0.047828183,0.023386097,-0.018733682,-0.015383403,-0.0017924915,0.008465038,0.027435234,-0.033259925,0.057390053,-0.0475465,-0.05116432,-0.035023022,-0.009793443,-0.019595407,-0.027417965,-0.013808836,0.0072969827,0.062305465,0.010485331,0.024149887,-0.06793873,-0.013095206,-0.014687903,-0.022170262,0.023398928,0.011833888,0.0038434314,-0.024228558,-0.010508487,0.019981323,0.01620124,-0.019303245,0.010908888,-0.0012344149,-0.041481238,-0.014763446,0.015266977,-0.011913775,0.014856324,-0.0033907539,-0.058102727,-0.014380697,0.0030262216,-0.02244627,-0.021768626,0.03502906,-0.0017322685,-0.012307891,0.05019807,0.022393351,-0.014870235,0.024761375,-0.013798989,0.018216243,0.017619217,0.009217717,0.039485697,-0.016894659,-0.016408317,-0.007246506,-0.014721661,0.01686044,-0.0059078205,-0.027013613,0.052241776,0.019578984,0.0051295673,0.007995656,0.072238825,-0.016286023,0.050375625,0.013032541,0.0049893786,0.024769126,-0.036571417,-0.04956731,0.024716487,0.0120847365,0.009856077,-0.021761607,0.015009772,0.0008272912,0.024833707,-0.0068165716,0.045598544,-0.029844357,-0.008235156,0.04164205,0.00486958,0.009152112,-0.01690127,-0.0064665214,0.026403232,-0.023674529,0.038977165,-0.008385346,-0.0035034076,-0.020053266,-0.0029182709,-0.03304959,-0.0024698477,0.025962574,-0.0154895,-0.048224546,0.03766423,0.0114521505,-0.037248917,0.005205052,-0.005685824,-0.0013696634,0.00024317433,0.05370166,-0.027634999,-0.064665124,0.0004493944]
520200	Marketing & Advertising	Marketing and Advertising	expense	[-0.0702021,0.0057090754,-0.014700056,0.0046397015,0.008255622,0.02010383,0.03241033,0.0036479293,-0.009679099,-0.005151193,0.02829714,-0.010068268,-0.0059313388,0.004873415,0.008002881,0.021982087,0.04025018,-0.02752732,0.016807549,-0.029934177,-0.013759236,-0.015973194,-0.0063216537,-0.0017396723,0.03271604,-0.0016240535,-0.028167175,0.015744751,0.010985395,-0.009716025,-0.0065380963,-0.022428902,0.05520803,-0.008480707,-0.010769405,-0.04593279,-0.06366229,-0.0038652185,-0.053206354,-0.0010527064,0.028217312,5.0498817e-05,0.00741221,-0.061816584,0.06687186,-0.01181269,-0.036121503,-0.007090837,-0.026269995,0.008929249,-0.009765757,-0.014058104,0.056118224,-0.01893169,0.020725764,0.03369453,-0.020164814,0.013080015,-0.10926535,0.007289292,-0.060656592,0.008230201,-0.011486745,-0.0030230435,0.036449946,0.043367308,-0.021528142,0.018494852,-0.022090312,-0.019577466,0.03078366,0.006595956,-0.04175848,-0.0316816,-0.06245957,0.025481084,0.011929375,-0.032922216,0.009797937,0.011549223,-0.0026749242,-0.05054547,-0.030258179,-0.027619092,-0.015132521,0.0323068,0.022155797,-0.008488061,0.021553572,-0.0014073704,-0.012248036,0.006635611,0.031283874,-0.02602003,-0.0575374,-0.06786802,-0.06671575,-0.00024225692,0.0013022646,0.016396224,0.03733287,0.00808874,0.04301536,-0.008215639,-0.026336826,0.04010924,0.0007998927,-0.001943049,-0.021389676,-0.0060683317,-0.030580103,0.016558401,-0.0034749578,0.01308119,-0.014454397,0.010409647,-0.016852718,-0.007774584,0.0034525017,0.00011170968,0.018690603,0.0003853114,0.019079894,-0.038780905,0.0671142,0.020289877,0.036797635,0.025392521,-0.015394744,-0.011880165,0.04127024,0.0023050865,-0.007872548,0.039235797,-0.024912382,-0.021536965,0.049927488,-0.031384703,-0.005667841,-0.039625097,0.02882052,-0.018717047,-0.012553791,-0.01909331,0.033979863,0.007505488,0.004231835,0.038534116,0.0042361594,-0.052966222,-0.021530684,0.027936613,0.050499514,-0.057976145,-0.040556706,0.010868881,-0.0061424673,0.036336686,-0.004479155,-0.008056162,-0.04410956,0.010244929,-0.051524844,-0.017267982,0.006564161,0.0022167792,0.008533672,0.008849725,-6.207454e-05,0.017022662,0.041838784,-0.024323644,0.020710777,0.0010165637,-0.008052736,0.02996099,0.060387135,0.025196979,-0.078951165,-0.021974241,-0.08458806,-0.01806833,-0.06968781,-0.0050021545,-0.000961868,0.0396194,0.013451777,0.0023835273,0.0086357,0.02231112,0.041471053,-0.022451447,0.029818775,-0.019503018,0.028578637,-0.016252695,0.06251255,-0.041172836,-0.021711398,-0.022676384,-0.04310672,-0.017427146,0.0026904705,-0.017116545,-0.029258294,-0.014831344,0.028983893,-0.008821654,-0.01389432,-0.021684546,0.006272904,-0.012840525,0.01601933,-0.010082956,-0.03211113,0.025594844,0.05688671,-0.0078293225,0.012637678,0.010978026,-0.011140568,0.029428786,0.015161063,0.03521794,0.035018276,-0.011954756,0.0057359734,-0.0013694705,0.04681211,-0.03392493,-0.059473388,0.012306134,0.020008955,-0.022850769,-0.046141647,-0.0066643506,0.034063235,0.042394526,-0.043919995,0.02561167,0.018920405,-0.012862913,-0.0023631977,0.050180137,0.002245195,0.0079133455,-0.005328755,0.07920923,-0.03530527,-0.018062402,-0.0018780371,-0.04803274,0.010720896,-0.025959413,-0.0056802225,-0.027269194,-0.01151069,0.002357125,0.012502253,0.0092477845,0.019368002,-0.054365527,0.036534354,0.012917536,-0.009678477,-0.005205116,-0.06950191,-0.05587936,0.015933849,-0.012127647,-0.009810619,-0.018784955,0.012784195,0.011884355,-0.0051431903,0.073694214,0.02755296,-0.018506417,0.029468002,-0.034480974,-0.028961364,0.047580197,0.03949854,0.0053975377,-0.013250553,-0.027214823,-0.021550577,0.019468836,0.0021803842,-0.06292194,-0.021486184,-0.012731212,0.07271396,-0.02622594,-0.05956015,0.023587905,0.03647279,-0.14075045,-0.020990763,-0.03298494,0.040416062,-0.017777782,-0.01851927,-0.0423463,-0.0014147336,0.035476964,0.04101465,0.032350212,-0.06452222,-0.0031545039,-0.0027999904,-0.024593262,0.027230099,-0.006850391,0.031679872,-0.0045882617,-0.023770474,-0.01970222,-0.068477705,0.02684972,0.028088773,-0.029000863,0.023310913,-0.0147838425,0.006515549,-0.015485003,-0.019871734,-0.016621925,0.03872261,0.009206894,0.018653309,0.02120057,0.0059155887,0.017901318,0.021983942,0.03336509,0.0043901373,-0.0015893702,0.072890155,-0.03498285,0.034521565,0.021174068,-0.0035353985,-0.058165718,-0.008715151,-0.013998705,0.005779933,-0.026943669,-0.0037595911,0.00023663465,-0.057796784,-0.029193368,-0.02138716,0.02660364,0.004996786,0.03321788,0.037720848,-0.015971182,-0.032516923,0.038999926,0.02203487,0.012543744,-0.027539395,-0.032342438,0.010844002,0.043027353,-0.013422334,0.027121155,0.019041738,-0.018091312,-0.01140959,-0.03306865,0.04390643,-0.013691049,-0.016563619,-0.0061825924,-0.095450275,0.0008256464,0.02589904,-0.021608729,-0.01627596,-0.016309217,-0.03114415,-0.010222815,-0.050435044,0.036274903,0.19195373,0.009569007,0.07122735,0.03356642,0.04485771,-0.009971566,0.05846282,-0.0033209731,-0.021279754,-0.012357165,-0.008972032,0.03294546,-0.028554162,0.021343598,0.0119651845,-0.007165179,-0.065633684,0.059000604,0.06632319,-0.022540681,-0.028884407,0.012203784,-0.037877142,0.022941886,-0.019782139,-0.023244593,0.015671363,0.04364537,-0.0063143703,0.015036175,-0.0056984145,-0.046000153,0.011544368,0.014748843,0.02173886,-0.0066691344,-0.0058562346,-0.07119208,0.054959178,0.049328007,-0.014229781,-0.036537945,0.0208752,-0.0028655813,-0.048617743,-0.06890891,0.025976889,-0.028507177,-0.048082266,-0.043045424,0.035061568,0.053414665,-0.009873818,0.019645723,0.01673907,-0.014782762,-0.01195714,0.005674674,-0.0654166,0.020054642,0.02157896,-0.007374458,-0.020210458,0.0054999003,0.021360712,-0.009198683,-0.007430313,0.03077745,0.008461986,0.030788893,-0.001008208,0.050960824,0.029618451,0.02486035,0.010685981,0.0015393738,-0.00248435,0.023856878,0.03664002,-0.05406659,-0.030311715,0.012996171,-0.026850214,-0.0059059095,0.021286147,-0.0518607,0.019467926,0.014207318,-0.0035863083,-0.02998395,0.007554771,-0.0071924217,-0.006633135,-0.0430938,-0.030265164,-0.017264223,0.038466934,-0.03566027,-0.034020897,-0.03263376,-0.003862556,0.02247169,0.008128724,-0.06674148,0.048798747,0.05238554,-0.0129847,0.0013210346,-0.05472849,-0.02188191,-0.030018734,0.004160656,0.031441405,0.0217425,0.018146517,0.029126093,-0.041949127,-0.0064145504,0.043672517,0.01031399,0.01930719,-0.0034452698,0.016264278,-0.016586224,0.011764609,0.012304008,0.021304838,-0.011806704,-0.004191523,0.016224926,-0.011745427,-0.014796738,-0.025923202,-0.0017351458,0.06410479,-0.008698192,0.030750422,-0.002880863,0.011406864,-0.0541974,0.03911482,0.053477734,0.0038229346,-0.030527255,0.01999702,0.016281433,0.017138852,0.016123133,-0.027163744,0.10610824,0.03181708,0.013457496,0.02100053,-0.041504767,-3.0043324e-05,-0.075746715,-0.016423982,0.01629818,-0.0003229279,-0.009819013,0.009944779,0.0062824883,-0.019627726,0.089698315,0.007548477,-0.0037399856,0.07141767,-0.010859401,-0.02506564,0.0057449294,-0.022971347,-0.009651285,-0.051390186,0.07029445,-0.0065389057,-0.0012392765,-0.05205705,0.026915723,-0.0135953305,0.03403042,-0.00090579665,0.013483506,0.010481417,-0.051802084,-0.01171248,0.050493702,-0.023524733,-0.026277777,0.0011868618,-0.029383134,0.029239107,0.096258394,-0.03589933,-0.02221355,0.041805778,0.0015236597,0.0013756027,-0.008913768,0.014217782,0.007751012,-0.0054970905,0.021915304,0.0014360092,0.018308787,-0.0060649645,-0.020977283,0.029790614,0.032679092,0.02887175,-0.01991898,0.022101369,0.029528376,0.010863109,-0.01746691,0.027236924,0.006691053,-0.04213456,-0.010597999,0.0018270818,0.0073533785,-0.018679377,-0.030876022,-0.002210599,-0.05473859,-0.009290204,-0.0027191225,0.033514947,-0.000855655,0.0059339707,0.030060692,0.0019017957,0.023937108,0.036628995,0.010542215,0.00037547277,0.009603133,0.023092788,0.032997392,-0.01579831,-0.03503351,0.0047513633,-0.037996594,0.040403094,0.012863612,0.0030444758,0.04474095,-0.05107474,-0.029518677,0.02679247,0.038281295,0.010260095,-0.048566848,0.011028408,-0.01423303,0.006302162,-0.031005444,0.026550755,0.02096774,-0.07390637,0.0021249277,0.025581034,0.061779603,-0.011596646,-0.025160484,0.015871773,-0.03385136,0.04903505,-0.014326521,-0.011945316,-0.0069386857,0.026437143,-0.011419337,-0.06933588,-0.0059824022,0.03677208,-0.00035574345,0.0012529389,0.009400903,-0.025623865,0.006731041,-0.063170746,0.0008146253,0.011510703,0.019541273,0.03692742,0.019425148,0.0006866704,-0.0003076281,-0.016721522,-0.0155977225,-0.01555013,-0.007533371,-0.06353159,0.06395612,-0.011542194,-0.0018969596,-0.024421534,-0.019889416,0.012013687,-0.0004063726,-0.0029863054,0.03514277,-0.024517843,-0.0005700799,-0.02713771,0.029448034,-0.029158076,-0.03883819,0.010741917,0.02046323,-0.040263586,-0.026588934,-0.010195325,0.008941922,-0.029083602,-0.010456003,0.030825868,0.0066940463,0.027673505,0.011676377,0.028841339,-0.015520112,-0.01636737,-0.018563304,-0.027124109,-0.009637181,0.022625139,-0.029273354,-0.030753132,-0.03273596,-0.0074894107,0.0056216177,-0.035551187,-0.01654924,0.01266657,-0.035384387,0.07111901,-0.00089023705,0.0067271343,-0.002139381,-0.0013250968,-0.030999053,0.0231548,-0.023445647,0.041590974,-0.022061495,-0.015893143,0.003628116,0.00800817,0.0050339233,-0.008658526,0.010178008,-0.06230621,-0.05214403,-0.017698966,-0.05095361,-0.066565245,-0.008589491,0.020878587,0.040163297,-0.033125635,9.8854856e-05,0.012386875,0.0056208004,0.0019399353,0.03275539,-0.038616966,0.003844856,0.013052458,-0.031097151,-0.036656715,0.0073858355,-0.03993232,0.0500872,-0.012981838,0.008687365,-0.0056798034,0.010661009,0.060209278,-0.016605556,0.013444137,-0.03980028,-0.005262727,-0.009187422,0.042790122,0.0012625295,0.011737659,0.0043324744,0.023110786,0.01199849,-0.016096024,-0.045145255,-0.024053654,-0.0006517184,-0.11555607,-0.0061749695,-0.011494936,-0.0067510414,-0.030787596,0.012314393,0.00419437,-0.026221342,0.039055366,-0.0038302895,0.011979612,0.02346702,0.040012963,-0.012551,0.0030469627,0.04428065,-0.013095985,-0.00895471,0.014403205,0.045504417,0.0059189624,-0.018068744,-0.0033676343,0.026756559,0.011859609,-0.0041916403,0.04939476,0.048166588,-0.044125408,-0.023035599,-0.0039732927,-0.00018415325,0.014865188,-0.00018819676,0.024666265,0.014117646,0.0057097976,0.010978987,-0.038925093,-0.0028833356,-0.017479002,0.042025052,-0.046642307,-0.011664171,0.0052581336,0.091271564,-0.06973977,0.0024134882,-0.038446575,0.00252427,-0.027490783,-0.0013733509,-0.014136594,0.012112662,-0.032794215,-0.022367034,-0.01126828,-0.0027742996,-0.008073965,0.039390497,-0.02365447,0.024311794,-0.009145968,-0.06497168,0.033835176,0.032429226,-0.05547871,0.01259587,-0.0038054583,0.0133995125,-0.019428764,0.018670853,0.029529378,-0.0525834,0.0779991,-0.012429388,-0.018961066,-0.015173197,-0.04601536,-0.028732713,-0.007515806,0.007616967,-0.012964157,-0.043155815,-0.0043401266,0.012900553,-0.0060603907,-0.0040591303,-0.03104884,0.020504028,-0.016960701,-0.027836384,-0.01678542,0.055415414,0.037893195,0.03249605,-0.013022462,0.047169175,-0.0063647153,-0.042641032,0.027176496,-0.04331096,-0.017228542,-0.0012382175,-0.026039016,-0.01967217,-0.015973132,-0.03727677,0.06084338,0.009748469,-0.028792212,-0.018715993,-0.01551274,0.035271734,-0.04620344,-0.0066620787,0.010785723,0.04496251,-0.047627263,0.02257019,0.0023195604,-0.058135174,0.049882546,-0.029695332,0.05786663,0.028108468,0.011130729,-7.3120515e-05,0.031702403,0.0044772686,0.02657881,-0.014021126,0.032822713,-0.016424749,-0.016627392,0.004890967,0.0019961514,0.027412372,-0.056376223,-0.02333975,-0.0029163454,-0.009219257,-0.024827603,-0.03501033,0.02160829,0.02348149,0.058821052,-0.016690973,0.03365385,-0.044522665,0.003636341,-0.027983457,0.018274492,0.023231462,-0.00529575,0.019892147,-0.02401199,-0.037885495,0.02718369,0.017885942,-0.05725671,-0.022800116,-0.023128478,-0.028902976,-0.008867286,0.054254133,-0.021001216,0.029335687,0.012129466,-0.025312733,0.032442965,0.013262821,-0.011346906,-0.043638714,0.0033558712,-0.0055496166,-0.005480778,0.028509041,0.050692588,-0.016141232,-0.0013623823,0.009397143,-0.0105896415,0.021136852,0.0067337197,0.03350041,-0.056016292,0.014034663,0.020557305,0.009746345,-0.011476463,-0.0072219777,2.6200628e-06,0.048871983,0.0034672802,0.02377257,0.023498004,0.06334626,-0.044794645,0.037337713,0.011506448,0.0016956256,0.0036952593,-0.079037726,-0.019269846,-0.029678294,0.031437613,-0.02092848,-0.04609629,0.06806013,-0.03722362,-0.025563957,0.0011032809,0.013064299,-0.002911838,0.009656377,0.038451917,-0.020283833,0.03462542,-0.034377772,0.00037019883,0.03301357,-0.017007874,-0.009594776,0.025483167,-0.050986707,-0.008158987,0.02624139,0.026260564,-0.060792085,0.0035554345,-0.030050494,-0.02742434,0.050328664,0.010226077,0.008493979,0.023000114,0.020256776,-0.014236756,-0.01263894,0.08457096,-0.006970707,0.015399892,0.022413006]
520400	Bank Charges	Bank Charges	expense	[0.01270045,-0.01617966,-0.05048343,0.011215961,-0.0007171713,-0.03479218,0.052292228,0.008189634,-0.005797171,0.0135365175,0.012394313,0.0030840975,-0.021380741,0.03023308,-0.008315152,-0.0284244,0.028557152,-0.040379804,0.03082134,-0.014561358,0.002705359,-0.012071997,-0.05184909,-0.025295358,0.0076265438,0.008578433,0.005503455,-0.0071476134,0.026540503,0.0047442764,0.025600713,-0.014864693,0.033392377,-0.021595092,-0.006465443,-0.02399727,-0.036455218,-0.008135729,-0.059475586,0.026074402,0.02255798,0.013239364,0.012948878,-0.009626282,0.026546912,0.00439465,-0.04405623,-0.029544083,-0.041362353,-0.0010393604,0.021771513,-0.023399932,0.069964446,-0.058098935,0.011059702,-0.006529549,-0.024241254,0.010925535,-0.06455029,-0.009861471,0.014281254,0.0040366636,-0.0056588785,-0.054849535,0.05574878,0.053369794,-0.003905744,0.02856653,-0.011624862,-0.031733938,0.00073837215,0.0035403671,0.015618215,-0.012805499,-0.046015814,0.026736684,0.034289706,0.0020930301,0.0080437455,-0.010128576,0.012358279,-0.056253705,0.020633811,-0.009844261,-0.04244957,0.09460174,-0.009145644,-0.0029658326,-0.018467657,-0.027598917,-0.022041544,-0.017646912,0.009702626,-0.029812872,-0.039164588,-0.0031976677,-0.03859418,0.03494059,0.019117072,0.012184027,0.04048967,0.018613655,0.026086569,-0.00082702556,-0.042490352,-0.036988925,0.0022523215,-0.0031350574,0.0037979165,-0.03308242,-0.0066723367,0.008768061,0.0038516144,0.02643072,-0.0010076826,-0.014980557,-0.0094629135,-0.010086634,-0.014657287,0.008746135,0.025447471,0.006666983,0.047165878,-0.011394844,0.03804581,-0.0029709437,-0.017216453,0.020876702,-0.015686762,0.021836735,0.005296856,0.036938757,-0.0351771,0.025391746,-0.057628848,-0.032635566,0.040383242,-0.020280294,-0.011818004,-0.019280024,-0.029778821,-0.008622628,-0.01896766,-0.013922847,0.045355022,-0.018066756,0.029130628,0.009645808,0.010339332,-0.03230478,0.0063734986,0.01317882,-0.006474071,-0.020708365,-0.0055764792,-0.015818676,-0.005631848,0.027810076,-0.042486053,0.012130956,0.015314182,0.05062513,-0.009126938,-0.02535339,-0.030656297,0.033388216,-0.0013581133,0.00988575,-0.013740092,0.028037218,0.026244782,-0.046402946,0.009579654,-0.031770956,0.052046534,0.011819844,0.0489257,0.02025715,-0.017314555,-0.038738888,-0.04448484,0.011299193,-0.03580949,-0.014801647,-0.029492896,0.0065891617,-0.0027653652,-0.018583879,0.013344616,0.0012551537,-0.030027995,-0.0054918886,0.006840514,-0.045281265,-0.0074997293,-0.049807996,-0.0020174526,-0.027667306,0.011245176,0.017605716,-0.011205872,0.018517097,-0.070046045,0.028748486,0.001637847,-0.010040844,-0.004436645,-0.024357144,0.014412321,-0.08550019,0.019730791,-0.019550618,-0.0029789608,-0.01971511,0.011247621,0.027022436,-0.005277868,0.00239836,0.028163241,0.029804142,0.008207947,0.053384747,0.020818336,0.01691471,0.016101511,0.011476805,0.037119243,0.05146284,0.008932603,-0.066156276,-0.018647244,0.033235848,0.047231775,-0.0285712,-0.028621111,0.026518777,0.021862837,-0.0018387518,-0.049253687,-0.0011979317,-0.061649673,-0.034329347,-0.003744609,0.0005012087,0.0069078165,0.045898207,-0.017705107,0.019696899,-0.023153389,-0.08037035,0.014291733,-0.033691097,-0.015394284,-0.0093327835,0.031185502,-0.010433036,0.015324348,0.012077156,0.038326103,0.026139827,-0.011405086,-0.009882445,0.0025075406,0.053723115,-0.022743007,0.018573146,-0.055445537,-0.009515094,0.01696196,-0.016532935,0.0024054996,-0.03485937,0.01977949,0.00554651,-0.02353186,0.027807925,0.0046661557,-0.010232895,0.009183574,-0.034457233,0.011955508,0.080599986,-0.019219007,-0.010631753,0.003912663,0.03095664,-0.013443823,-0.036944192,0.0017903395,-0.035495657,-0.022416929,0.012499356,0.073792465,-0.008084952,-0.035239074,0.006108218,0.034231875,-0.14397715,0.02419802,0.01532252,-0.004352643,-0.011575739,0.02045709,-0.04820011,0.028800363,0.00930812,0.03463906,0.03681597,-0.05540094,0.01913567,0.018955132,-0.018527592,-0.03956088,-0.0015490167,0.017133985,0.039157867,-0.020541247,-0.040949523,-0.051270425,-0.034301843,0.026926761,-0.051338322,0.04034807,0.013714622,0.038741343,-0.03392929,-0.023774087,0.011103103,0.031715434,-0.0018572698,-0.008471789,0.0259453,0.020240743,0.04392027,0.033849075,0.033257645,-0.02675241,0.027062971,0.07643189,-0.03773429,0.047315102,-0.012914478,0.024416627,0.00069376203,0.03066088,0.013373212,-0.023897061,-0.023815341,-0.013107617,-0.019158253,0.0006397932,-0.034676652,0.01263516,-0.004418395,0.029006526,0.022253051,0.0019828042,0.00028899455,-0.060970623,-0.031742107,-0.018381352,-0.017923025,-0.0053651226,0.01779487,-0.024596056,0.036512047,-0.0080698375,0.056701224,0.0024041394,0.024296956,0.012121019,-0.011115044,0.05956524,-0.014928466,0.0012277517,-0.013234262,-0.10029952,0.013674342,0.031230982,-0.02272756,0.034353342,-0.05148091,-0.0384701,-0.032891054,-0.071181454,0.047293514,0.24057233,0.026261205,0.05026303,0.044480246,0.04430961,-0.04400106,-0.014399195,0.026385998,-0.018776732,-0.024127172,-0.04432265,-0.008240807,-0.019353967,0.019772127,-0.033551153,0.008578885,-0.04834736,-0.010035987,0.08874383,0.0023110458,-0.014549458,0.02176036,0.00921745,0.016541988,-0.07352055,-0.068463415,-0.03053326,0.011580644,-0.010046974,-0.008643333,-0.028823828,-0.027855486,0.014497258,-0.020349095,-0.008812991,-0.021968046,0.019387856,0.0012217159,0.061489653,0.04521452,0.01595351,-0.0408476,-0.00032549395,0.016692117,-0.08027904,-0.057323802,-0.0034729133,0.016953152,-0.028877437,-0.02016756,-0.02586374,-0.0014622025,-0.049974736,0.019699307,-0.02909173,-0.011569734,0.0061652954,-0.07804939,-0.042737372,0.05720663,0.0132531775,-0.028864212,-0.01776274,0.044463694,-0.014922255,-0.016425626,-0.03514121,-0.0066146962,0.022675635,0.044631444,-0.035832386,0.0083949845,0.04925109,0.024262099,0.021145502,0.007765044,0.082549006,0.030575017,0.03271716,-0.02949931,-0.056250036,0.032766778,-0.010844679,0.01712658,0.027940098,-0.044695977,-0.03137965,0.053419884,-0.011100446,-0.012762836,0.016951807,0.012875007,0.043167055,-0.02494566,-0.03435449,0.009184592,0.020807406,-0.02206684,-0.03895018,0.03009712,0.042154398,-0.03142295,0.012998416,-0.024819184,0.042468365,0.03200944,-0.0006091504,-0.012542388,-0.026502697,-0.018106896,-0.025000684,0.013877405,0.003791029,0.010743297,0.029210791,0.0019506548,0.0016780171,0.028252527,0.032698482,0.013570037,0.005461569,-0.030468378,0.034005295,-0.010835093,0.002305717,0.013629108,-0.011160845,0.00222617,-0.035302162,0.021461854,0.011240365,-0.020803167,-0.033056296,-0.0065807505,0.06189698,0.019634638,0.0016620253,0.038732633,0.0121213375,-0.02715503,0.021802634,-0.0047487435,-0.025735198,0.0074006454,0.010636803,0.042330157,-0.020467814,0.02422021,-0.0015738701,0.065545425,0.045248244,0.030723434,0.026112698,-0.056359306,0.016668318,-0.035663553,-0.01267261,-0.010964896,0.0018157524,-0.010379581,-0.018251056,0.02056291,-0.025868058,0.03685094,0.029389737,0.051626757,-0.0035354947,0.03071334,0.009348603,-0.02124411,0.0061763916,-0.0055564763,-0.04660623,0.020728355,0.0015511618,-0.04114701,-0.06115756,0.017469889,0.032939706,0.00915001,0.047988635,0.0438205,-0.008707009,-0.011239517,0.0017103837,0.038420916,-0.003833936,-0.019565178,-0.026082413,-0.054027572,-0.029179506,0.082796566,0.005907596,-0.04197908,-0.033029955,-0.0037775938,0.025626725,0.01836952,-0.0025296707,-0.010806638,0.008435604,0.0037505024,0.024557443,0.017446892,-0.005345941,0.010533743,0.04552276,0.004867887,-0.0026736103,0.02007141,0.018021619,-0.009165413,0.039812863,-0.02191284,0.016828224,-0.01740652,-0.0048371735,0.052648503,-0.015619441,-0.03356324,-0.058838975,-0.046427794,0.008253811,-0.018518355,0.011382243,-0.023197941,-0.017424189,0.012572951,0.0064158663,-0.014087256,-0.001429727,0.053097393,0.028390028,0.0047829538,0.0076353117,-0.04393623,0.028497314,0.031459372,-0.036066007,0.007528858,-0.0029060417,-0.02119217,0.08856334,0.03639955,0.020136232,0.04035022,-0.049689405,0.016555501,0.030228177,0.05566287,-0.020781599,-0.048124254,0.0502272,-0.018105293,0.022719944,0.0021552222,-0.013439541,-0.019676242,-0.015652057,-0.005222513,0.021165079,0.055370435,-0.020879254,0.008550178,0.0272566,-0.033710774,0.018041505,0.009795891,-0.009331953,-0.007573974,-0.0096017355,-0.026913106,-0.052440565,-0.033139065,-0.0018505622,-0.020501973,-0.0017116491,0.022995891,0.0068819597,-0.00832545,-0.040268537,-0.036168233,0.07435238,-0.021222066,-0.0157465,0.015216147,-0.017610945,0.012157666,-0.03373443,0.011810158,-0.03919119,-0.0015205574,-0.042309526,0.06304397,0.0040409816,0.0032069099,-0.0030401642,-0.01852847,-0.019901805,-0.010080669,-0.029932687,0.02220067,-0.031196456,-0.061557457,-0.0015993317,0.00061761774,0.0082370965,-0.012590067,0.022691496,0.043360908,0.04282697,-0.009585473,-0.0045234757,0.0042004217,0.018127093,-0.01426875,0.008612436,-0.0006588856,0.040865596,0.031797312,0.01571851,-0.042913537,-0.017499004,0.025069484,-0.018175416,-0.00893223,0.021895777,-0.020912722,-0.014473976,0.02175686,-0.037607722,-0.011348834,-0.04201962,-0.037502613,0.04628013,0.023793312,0.04972974,0.014812709,-0.0011850358,-0.0073649446,-0.04157583,-0.012286849,0.038335226,0.008250303,0.031813893,-0.043891504,0.024491861,-0.014245056,-0.059425797,0.021786671,0.0105615575,0.0236615,-0.020267682,-0.058522034,-0.0028150978,-0.053475693,-0.0019296333,-0.026242016,-0.016716748,0.031405084,-0.04938225,0.025027126,-0.0062054177,-0.020511447,-0.008489151,0.008115489,0.016650444,0.019159991,-0.0026604687,-0.0326565,0.0054359557,0.05045381,-0.006858303,0.03067156,-0.001389965,0.0260975,0.057197135,-0.004414492,0.025986068,-0.019630097,-0.043309227,-0.0104647605,-0.023772415,-0.024648996,-0.003209391,0.0077547897,-0.013194001,0.011877316,0.015708065,0.02659817,-0.028668802,-0.056982156,-0.004703691,0.02289803,-0.14124018,0.01674124,0.015824715,-0.029765004,-0.0012732856,-0.0058262725,-0.046140138,0.0017904732,-0.0072610574,0.02651765,0.005804383,0.06605475,0.0065887636,-0.0207266,-0.018054219,0.052725393,-0.008364873,0.027724305,0.008294036,0.005531962,0.021402402,-0.034194514,0.01090232,0.06740677,-0.021793732,-0.0020532676,0.029071119,0.050555386,-0.03125875,0.009290571,0.0013185845,0.0036057676,0.054661788,0.00036558212,0.022022182,-0.026620349,0.010268874,-0.012941728,-0.035622157,0.012933015,-0.076780245,0.03829728,-0.07098353,0.0015785886,-0.00700107,0.04303815,-0.0044816183,-0.027159965,-0.046747938,-0.052236415,-0.0346701,-0.03093194,-0.026211713,0.018969785,0.040630985,-0.005095319,-0.025008893,-0.053085394,0.0450873,0.026875993,0.008290092,0.005985929,-0.039520796,-0.048620455,0.023682239,0.019678902,-0.020853339,0.017260086,0.005164766,-0.02416697,-0.066133805,0.02386565,0.021517899,-0.0343013,0.01999569,-0.044468142,0.04028381,-0.013891413,-0.010666382,-0.021915657,-0.030283399,0.030274214,-0.029615318,0.0018682393,0.0060745007,-0.011020396,-0.006218845,0.037085626,-0.015450824,0.0071587344,-0.024333648,-0.038127784,0.014852539,-0.01995201,0.033898905,0.008495902,-0.0094911195,0.021146545,-0.035167523,-0.061575714,0.046572823,-0.046528455,-0.015259795,-0.0020746214,-0.053910047,0.009842332,-0.02727566,0.015871981,0.035685208,-0.019675912,-0.0049004694,0.019070055,-0.013448073,0.018713033,-0.05933209,0.009412199,-0.007764804,-0.00088692683,-0.040906724,-0.003642198,0.009332154,0.05574769,-0.008132147,-0.035410922,0.07437531,0.014484581,0.029794386,-0.029842643,0.021299291,0.020914733,0.051515855,-0.060198028,-0.007875446,-0.013368406,-0.006264467,0.04722689,-0.012820845,0.06404745,-0.052555945,-0.016829731,0.010966947,0.013128392,-0.000789562,-0.037577674,0.0055034733,0.0054590954,0.04511288,0.0093428325,0.013254443,-0.017297007,-0.0091952095,-0.036755838,0.0035804845,0.053954456,0.010331255,0.0010888261,-0.03023019,-0.008296645,0.022163663,0.01171816,-0.017150154,-0.051832464,0.016693449,-0.033121504,0.014255986,0.025698578,-0.023905,-0.0060345633,-0.0070873904,-0.0207599,-0.0032109548,-0.034307066,-0.002052605,0.03218493,0.009228822,0.015552535,-0.0007430589,-0.015634688,0.019604757,-0.021612717,0.0055521573,-0.00061905786,-0.004211586,0.012218209,-0.035463437,0.02988566,-0.025012512,0.03011866,0.016529953,-0.033467263,0.024897305,-0.004296872,-0.04608356,0.030736567,0.046299055,-0.0075374465,0.026731577,0.03512479,-0.019715048,0.03375572,0.03809249,-0.02555512,-0.016466971,-0.06740031,-0.017428823,0.0070508313,0.0021513577,-0.012137949,-0.021434886,-0.005341135,-0.0028959117,-0.012154392,-0.006703201,0.043170296,-0.018064355,0.008100303,-0.0134244785,0.010236262,0.03850378,0.040251605,0.011481135,0.06348918,-0.0065544164,0.037438363,-0.009464588,0.001701561,-0.032510877,-0.006667215,0.026057743,7.993924e-05,0.048019107,-0.0071495315,-0.034075785,0.050303493,0.010733237,-0.02501822,-0.029896269,-0.016118286,-0.048743706,-0.009824554,0.029963236,-0.016634589,-0.07713878,-0.010140508]
520300	Professional & Consulting Fees	Professional and Consulting Fees	expense	[-0.047262583,0.007634072,-0.032597378,-0.010451362,0.023307288,-0.00916168,0.032380596,-0.0017962742,-0.016267072,0.026143178,0.027512765,-0.00023264148,-0.002106811,0.020881359,0.004947237,-0.021161955,-0.016020134,-0.04321224,0.033756334,-0.010502229,0.014556976,0.012042831,-0.034224484,0.003712826,0.023128241,-0.0036109304,0.0059467577,0.0043944544,0.030066358,-0.02641472,-0.02844718,-0.053173143,0.047381207,-0.001997813,-0.016726028,-0.040998463,-0.060003493,-0.030240603,-0.065150954,0.0021971886,0.009566926,-0.033602785,0.048653707,-0.009759888,0.053111535,0.010911627,-0.04029189,-0.015838604,-0.014157249,-0.010896129,0.018571723,-0.025658878,0.08448635,-0.097160235,-0.040971063,0.03492225,-0.012817337,-0.003473438,-0.1022915,0.02298788,-0.04850808,0.022565408,0.032275327,-0.024443522,0.018976266,0.037393995,-0.022854462,0.049478076,-0.008225989,-0.023317205,0.03288856,0.010902291,-0.033076704,-0.0358478,-0.06964218,0.016063603,-0.014154175,-0.025509175,0.0108036585,0.019767161,-0.014875369,-0.047947105,-0.0031857272,-0.04824286,-0.045849215,0.03791085,0.020783728,-0.0050874944,-0.005000597,-0.045124777,-0.028248755,0.009633386,0.032545503,-0.04257834,-0.01503411,-0.034468602,-0.020147666,0.014098941,-0.003687447,0.024793614,0.063415915,0.073184416,0.032872345,-0.009792531,-0.013164071,-0.020818664,-0.02645901,-0.036786083,0.018309725,-0.027250022,-0.018233793,0.009301391,-0.028955793,-0.0005346192,0.0140532795,-0.013837371,0.019576391,0.0017936085,0.002143778,0.0028660377,0.055029336,0.04421069,0.037952174,-0.042390577,0.046693727,0.0036460094,0.015750635,0.029028958,-0.012132072,0.0077467705,0.008086763,0.02382106,-0.024755046,0.015678747,-0.03806434,-0.06237976,-0.018767385,-0.02325703,-0.02705077,-0.005617093,-0.01717252,0.026891552,-0.01976552,-0.022651535,0.029957734,-0.020278743,0.047504686,-0.0052730897,0.003842859,-0.034783103,0.027977511,-0.003717755,0.0052101756,-0.0070235096,0.0326201,0.025014592,0.009861838,3.1553736e-05,-0.0076735895,-0.029849015,-0.015512296,0.03191477,-0.021462886,-0.027218575,0.01556855,0.020007895,-0.028119594,0.0186417,0.0067770244,-0.0036085704,0.01957553,-0.04444416,0.026005387,-0.015060093,0.04277562,0.02128429,0.06881325,0.01891328,-0.0012016897,-0.041448902,-0.030941421,0.0075893546,-0.035617385,-0.05692228,-0.014709587,-0.012661934,0.0021091113,-0.010340513,0.008120836,0.032432813,0.030654835,0.013326252,-0.0031137997,-0.03630874,-0.009141736,-0.02898233,-0.009711401,-0.048988894,0.018889595,-0.0021050703,-0.045818597,0.029921258,-0.029434135,-0.011780424,-0.0011141174,-0.012143663,0.039162572,-0.031129425,0.030914107,-0.013905892,-0.008955301,-0.012949172,0.036720842,-0.013863681,0.015246302,0.06501115,0.015625285,0.020080417,0.025113216,0.014598345,-0.057785522,0.044671156,0.037280586,0.033874035,-0.005134484,0.012280452,-0.015808323,0.015960824,0.055542294,0.0096163545,-0.03232119,0.029660823,0.0671767,-0.06222653,0.014264518,0.024503423,0.025146764,0.052903567,-0.059868187,0.004473334,-0.023976725,-0.022603909,-0.012044805,0.011402453,0.0022430897,0.028101332,0.02396713,0.04060493,-0.01826936,-0.04783277,0.036758114,-0.0072373627,0.024053007,-0.016065516,0.041107167,-0.008640138,0.009234844,0.010281356,0.007085081,0.01026943,0.012431945,-0.01490921,-0.011997252,0.032417897,-0.025013983,-0.0076545146,-0.071776874,-0.03593947,0.013271512,-0.0031039293,0.012297596,0.004282141,0.04042821,0.01202953,-0.014965857,0.05306188,0.02587506,-0.016814703,0.049521755,-0.045250725,-0.0043444936,0.06602887,0.0018645733,0.008740818,-0.019445438,-0.028940164,-0.03588233,0.0005984249,-0.008971315,-0.038758136,-0.009456073,0.018735955,0.07278126,0.0025154813,-0.042715866,-0.024681196,0.05102058,-0.14708507,-0.015380425,-0.00064651505,0.014366766,-0.014653544,0.019547665,-0.027931416,0.015215001,-0.027351042,0.034921296,0.056991365,-0.049349397,-0.0068554725,0.025834661,-0.03414004,0.021740861,0.0024917582,0.008081174,0.027796544,-0.019615518,-0.04604051,-0.08265267,0.0008175384,-0.014280847,-0.049212687,0.032677986,0.012721667,0.0040766597,-0.009060479,-0.033652328,-0.017740091,0.023785025,-0.0042798086,0.022299124,0.0021699506,-0.025208933,0.023607465,-0.019924618,0.029246116,0.0023265234,0.007268314,0.07351462,-0.031447187,0.057171643,0.011137463,0.027491778,0.032486487,0.024936642,0.0034162456,-0.013496456,-0.04019858,-0.021546416,0.026239986,-0.008916511,-0.04170195,-0.011105468,-0.04449964,0.041517645,0.018449381,-0.010370312,-0.046728056,-0.06586163,0.02219215,-0.027413165,-0.0077942624,-0.00820355,-0.013732866,0.014659434,0.012255809,-0.031083245,0.028958777,-0.024857676,0.0015068948,-0.02532365,-0.009440137,0.032921813,0.0010568526,-0.011117721,-0.017255675,-0.08219269,0.008028398,0.02341689,-0.027923197,0.02244927,-0.059385743,0.01589523,-0.0075774477,-0.041464284,0.045697864,0.19702183,-0.0012288025,0.045628153,-0.0012320034,0.03140734,-0.007351618,-0.015326299,0.03490762,-0.0024599717,-0.026955072,0.0124954805,0.005597814,-0.027840385,0.0010101526,0.0027228415,0.024407625,-0.062339373,0.003120137,0.060248163,-0.030069279,-0.026643418,0.026721712,-0.010967814,0.0070865303,-0.08409484,-0.0029802376,-0.0041810665,0.040217027,-0.015692556,0.027364762,-0.020255005,-0.0045284885,0.01055836,-0.041138176,-0.0018984532,-0.055842582,-0.023604926,-0.04630035,0.08546637,0.052314315,0.008758696,-0.03817716,0.018183947,0.00755302,-0.008679287,-0.07502033,0.03174903,-0.021606827,0.0009865046,-0.042270426,-0.030715322,0.0140116215,-0.051169362,0.035682376,-0.027799832,-0.023104148,-0.022499716,-0.0743931,-0.044955812,0.06846965,-0.0066726683,-0.013808037,-0.007424708,0.04981372,0.027312154,-0.0028260176,-0.035439394,0.0062504862,0.028285198,0.014408263,-0.019495493,0.04131159,0.027189769,0.00044834157,0.00981912,-0.0057139834,0.04117878,0.04845289,0.029727485,-0.029882548,-0.05176239,0.012563473,0.02456967,0.002076146,0.01267117,-0.06389901,0.005784729,0.002229379,-0.027527906,-0.0020797565,-0.013144893,0.013460039,0.021333566,0.014460868,-0.04715408,-0.019571269,0.005210004,-0.023287188,-0.025929192,-0.020543238,0.016896905,0.013045835,0.017715909,-0.040490873,0.029294029,0.025193352,-0.0022615187,-0.03266348,-0.06045929,-0.0067104693,-0.039543625,0.0026742965,0.018779749,-0.032033592,0.016958928,0.051963404,0.00806414,-0.007205996,0.0004876096,-0.039942596,0.040267173,0.026079949,0.022301968,-0.0025126894,0.0053770584,0.020426486,-0.03582256,-0.0004541068,-0.018191427,0.010494951,-0.0066182343,-0.013444065,-0.01852033,0.026596352,0.04770475,-0.0113679655,0.04575687,0.023734847,0.014264446,-0.018220525,0.011576837,0.01532661,-0.021590354,-0.0065042153,0.015781874,0.007169792,-0.035458926,0.045612816,0.0030070161,0.061907575,0.012461145,-0.008326379,0.02351585,-0.04501083,-0.003494901,-0.067856245,-0.008941163,0.021280976,0.011974626,-0.021246742,-0.0041777734,0.0036826113,-0.0069044144,0.07086967,0.04084118,0.037993487,0.025286268,-0.02264585,-0.009701969,-0.035894033,0.00046786133,0.003860568,-0.024657171,0.06325838,0.021931462,0.018865034,-0.034760874,0.024588669,0.027572816,-0.03913934,0.005192931,0.020517603,-0.019728364,-0.017309718,0.015781343,0.018021043,-0.024826752,-0.046140693,0.007130117,-0.042234723,-0.0058809957,0.055186573,-0.016039241,-0.025305452,-0.011547563,0.061113402,0.024959624,0.020919908,0.004825568,-0.026667133,-0.06167217,0.04926903,0.03835027,0.019203942,-0.0010068803,-0.03170523,0.01942841,0.056528155,-0.024108108,0.040312763,0.00015097727,-0.03103638,-0.013684629,0.025676034,0.0014573735,0.0237817,-0.04953547,0.041664604,-0.015512821,-0.01066045,-0.030084327,-0.048373207,-0.0064966497,-0.008284816,-0.022776768,-0.0010204697,0.00023775904,0.04076239,0.0046873484,0.02716087,-0.0027131122,0.03546304,0.013321011,0.01109225,-0.014237091,-0.0061591594,0.005126075,0.03819838,-0.035122134,-0.006373436,-0.010368419,-0.045295715,0.03128855,-0.012247727,0.028793607,0.011241239,-0.08879519,-0.05053628,-0.010729182,0.047195014,0.011714857,-0.047159318,0.038226813,-0.02218342,0.052103527,-0.0068811616,0.0002969055,0.0120104505,-0.035785314,-0.012555343,0.022145879,0.06865194,0.0067503084,-0.04604875,0.012089595,-0.038522225,0.05930319,0.00656923,-0.031656235,0.00625,0.014122024,-0.013231739,-0.047222365,-0.0078106653,-0.0027814778,0.01611044,-0.05532186,0.015936792,-0.020442924,0.01349867,-0.05080069,-0.056935992,0.029752307,-0.0280182,-0.0009488183,0.02269575,0.0030324261,0.026593145,-0.016087586,0.021154458,-0.017853683,-0.0054800487,-0.079449296,-0.015950086,-0.006163172,0.007670975,-0.022905424,-0.036947194,-0.0077857454,0.0017981271,-0.023315301,0.019787045,-0.026817422,0.019144967,-0.030769916,0.011101909,0.0103282705,-0.060000665,-0.0029695185,0.026425634,0.0077547394,-0.044080183,-0.011635087,0.005783156,-0.0064458046,-0.024789486,0.022991624,0.00758505,0.025681412,-0.0012739048,0.0057381233,-0.013868746,-0.044755004,-0.04744375,-0.058579646,-0.010653739,0.039715245,-0.025465176,-0.014966989,0.015928915,-0.03591843,-0.0127114,-0.02734076,-0.014446765,0.01738911,0.021977946,0.023140961,0.015266197,0.033833012,-0.013378488,-0.024777716,-0.035985745,0.058184765,-0.017383473,0.016696876,-0.028963333,0.0040285457,0.009643265,-0.05408692,0.007577129,-0.030154727,0.0043919506,-0.014483933,-0.055336963,0.011640778,-0.019887509,0.005734245,-0.019366024,-0.018400554,0.056169324,-0.05611698,0.019131668,0.019687675,-0.001556637,-0.014202447,0.028337842,-0.031344935,0.020208668,0.0055261413,0.00046613882,-0.023931313,0.06196158,0.0048714457,0.06386622,-0.027953066,0.036533255,0.022369951,0.012804746,0.020619912,-0.036369633,-0.016580941,-0.04593372,-0.0077041234,-0.012876384,0.01000246,0.009405096,-0.0030067838,0.010099415,0.012267775,0.014974076,-0.01274497,-0.017910337,-0.0030497762,-0.012623468,-0.118847296,-0.008675555,-0.013311364,0.003980252,-0.020338817,0.0045890245,-0.02854367,0.0012059846,0.005629693,-0.003407388,-0.010332507,0.04341414,0.048542283,-0.019264236,0.009033446,0.023863444,-0.0069291443,-0.010118868,0.022282887,0.037152532,-0.008598074,0.017020889,0.0331441,0.072649,0.020887442,0.008067096,0.03652397,0.04410032,-0.042834003,0.031134235,-0.028846968,-0.05692623,-7.964959e-05,0.021603327,-0.007917157,-0.015055859,0.00057774445,-0.0033881431,-0.03262076,-0.01984971,-0.014794365,0.044887055,-0.064290665,0.05377002,-0.018234542,0.093149506,-0.015508935,-0.0090752635,0.0057578157,-0.019921146,-0.009017818,0.010069246,-0.03382047,0.0280482,0.02249741,-0.0009864164,-0.032187086,0.0036187319,0.001673314,0.023567965,-0.04260852,0.05408569,-0.030532893,-0.023417579,0.015411542,0.020521246,0.01559123,0.043934934,-0.0097391,-0.031625625,-0.031440854,0.027923357,0.007938852,-0.008442366,0.001725978,-0.057183184,0.030737842,0.015010537,-0.00050775177,-0.013708039,-0.068227276,0.006134921,-0.07920747,-0.026615085,0.0036675348,-0.0017553108,-0.015788475,0.03245191,-0.017026778,0.03633985,-0.044684667,-0.048415523,0.017626593,-0.0053256094,0.019618094,0.014558172,-0.01455068,0.033909105,0.020366466,-0.047197793,-0.00010489269,-0.04107732,-0.03101395,-0.003453377,-0.037098162,0.03859567,-0.028713873,-0.008815277,0.0052532186,-0.010881576,-0.014937563,0.022601193,-0.004225788,0.030771619,-0.047839973,0.007061581,-0.013344265,0.045991972,-0.021152234,-0.016809551,0.0031130756,0.013022335,0.017541138,-0.040574294,0.09880971,0.027715411,0.03423447,0.021653725,0.07074582,0.016005931,0.02990581,-0.011053696,-0.004282751,-0.023248082,0.002737128,0.02605987,0.026957447,0.037555628,-0.036278855,0.016831588,-0.010860877,0.014853136,-0.03509807,-0.011834081,0.011684518,0.024494711,0.03307906,0.01484136,0.04488209,-0.051249076,-0.002629239,-0.045656245,0.0030853343,0.06103694,0.01750718,0.03555262,-0.03686862,-0.015618112,-0.0045506377,0.03254628,0.003041051,-0.07011464,-0.009969003,-0.031107102,-0.030096043,0.050587736,-0.027135445,0.01941368,0.021820283,0.006984952,0.014050687,0.009083836,-0.008009788,-0.030477423,0.009855935,0.014742793,-0.028595142,-0.021940356,0.037300803,-0.008668763,0.016630601,0.00044474567,0.021792985,0.0069243624,-0.026364833,0.06322966,-0.051972076,-0.021065624,-0.0085648075,0.009432629,0.013522907,-0.008875447,-0.026207445,0.04412622,0.03549129,-0.02364472,0.0010204957,0.040577024,-0.023067795,0.012138017,-0.009946002,0.010332522,0.006392808,-0.03987465,0.012176692,-0.00283469,0.018899582,-0.036185402,-0.014664619,0.0063778637,-0.0031125292,-0.010117128,-0.008644727,0.018932337,-0.014184863,0.010877648,0.025005305,0.03238634,0.015855094,-0.017844504,0.04559861,0.06437836,-0.013493408,-0.010078188,0.028068319,-0.0061213044,0.0021467358,0.031992424,0.024818782,-0.01894773,0.03998956,-0.011402852,-0.022997698,0.00048511385,0.023733836,0.005205134,-0.0073202383,-0.009430635,-0.05725992,0.00531954,0.06520928,-0.041376937,-0.017143548,0.028864646]
520500	Insurance Expenses	Insurance Premiums	expense	[-0.05143023,0.02590079,-0.02173298,-0.021295289,-0.015408895,-0.016091049,0.036157034,0.027164267,0.031275537,0.011172996,-0.0021848695,-0.000811762,-0.016757974,0.010259845,0.013383758,-0.016895087,0.016168622,-0.012928116,-0.034555603,-0.013478953,0.023127321,-0.02321331,0.004756828,-0.0060289255,0.011764198,0.022551566,-0.009258377,0.03759666,0.014990766,-0.011312149,-0.015907908,-0.011623416,0.016948204,0.01036169,-0.032926608,-0.0077359793,-0.03460671,-0.008890904,-0.044419434,0.03182322,0.006639433,-0.0011301362,0.028531974,0.01257255,0.010411524,-0.008496227,0.010408165,0.008541889,-0.025449885,-0.043414507,-0.0055121756,-0.04549064,0.063286185,-0.077080116,0.017453356,0.018568065,-0.04601586,0.018584639,-0.056556363,-0.048934616,-0.04319049,-0.0014615214,-0.025235074,-0.022489829,0.047633167,0.06882766,-0.006290876,0.01605265,-0.030350126,-0.06371575,-0.005857583,-0.017068183,-0.03209638,-0.013285596,-0.05515296,0.019648246,0.032805182,-0.039214946,0.00046549682,0.002211338,0.0046538073,-0.02473512,-0.024904998,0.018693801,-0.032526772,0.026665628,0.0113860965,-0.015696948,-0.00742552,-0.030493801,0.0006138103,0.0021139632,0.021527788,-0.03107461,-0.03980007,-0.0036332011,-0.03344138,0.004882305,0.03383166,-0.017294273,0.029235054,-0.004912824,0.060054276,-0.026244035,0.008007855,-0.026526548,0.012110892,0.03855931,-0.012869384,-0.014224791,-0.039205108,0.055374157,0.01622426,-0.0024931151,0.018279897,-0.0015866347,0.0051212665,0.005492192,-0.020675436,-0.013571715,0.0473381,-0.010459764,0.02882833,-0.012635856,0.041998226,-0.00074213964,0.0032866658,0.0045092977,0.010079114,0.010739186,-0.011198673,0.019059498,-0.04964734,0.019606514,-0.038092893,-0.044383343,0.06974044,0.017787643,0.022123294,-0.04124292,-0.016291732,0.046817046,-0.013360347,0.005261937,-0.008371742,-0.031920094,0.06714551,0.0024797497,-0.011291843,-0.04973099,-0.042117607,-0.007516951,-0.0062356354,-0.0070018633,0.024623312,-0.0040775766,-0.029186139,0.0009725503,0.021466961,-0.0070615266,-0.01947475,0.017101634,-0.058719624,-0.04397853,-0.0027774035,-0.0051915236,-0.0020212596,-0.00050967233,-0.033816684,0.017879192,0.03495999,-0.022039585,-0.00791781,-0.041411012,0.021398291,0.022525478,0.07327714,-0.007889632,-0.008916302,-0.043738667,-0.06934142,0.0064774253,-0.009087175,-0.028228492,-0.024204224,0.005101163,0.020536214,-0.010832849,0.022487141,0.0492043,0.029506315,-0.04333196,-0.009366973,-0.082795575,0.015688183,-0.049288984,0.014811148,-0.01701889,0.06700949,0.004405992,-0.014928282,0.0026007327,-0.02549263,0.042490676,0.01679415,-0.033069327,-0.02417059,0.043038458,0.019294713,-0.046512917,0.03470527,0.012049086,0.0076725786,-0.007932221,0.000759416,0.010641617,0.034036912,0.03183491,0.030161377,0.028226456,-0.041698057,0.031068819,-0.012554019,0.024261266,0.029680071,0.013588358,0.0037903376,0.042082313,-0.012297663,-0.04107461,0.0068838997,0.052372668,0.010266473,-0.04079428,0.01664814,-0.0032653385,0.042114045,0.023450255,-0.04807257,0.010941352,0.01716689,-0.025890706,-0.02079181,0.017611125,-0.009029876,-0.007063118,0.045166697,0.027625065,-0.014381207,-0.021545859,-0.041440506,-0.04545069,-0.007974336,-0.004665077,-0.014015186,-0.0075296834,-0.037564725,-0.010913465,0.040037747,0.031211084,-0.010532266,0.020071346,0.013950091,0.020931276,-0.019171642,-0.005574367,-0.055780422,0.0028281573,-0.010070445,-0.008094023,0.03242937,-0.02370617,0.048317537,-0.034355614,-0.023288235,0.04191498,0.018204413,-0.054213025,0.001671308,-0.0077041313,0.011092529,0.03483287,-0.021014456,-0.060318545,0.005049034,-0.0081419125,-0.012871664,-0.057928752,-0.01153491,-0.037981894,-0.01171563,-0.008279741,0.068462536,-0.023735486,-0.021676317,-0.001826902,0.017316276,-0.1329637,0.01078855,0.00368114,0.020924417,-0.00086869055,0.015475016,-0.07207553,0.011937084,0.012041322,0.0063302936,0.0030514926,-0.08359654,0.014161393,0.020779578,0.026978657,0.013404887,-0.004265337,-0.006691438,0.051960558,0.012742433,-0.04050889,-0.030288544,-0.007862875,-0.0120359585,-0.03781749,0.030710861,-0.0015349711,0.032138795,-0.022918701,-0.0068823025,-0.008861154,0.04213857,0.0032271734,0.049437385,0.01468677,0.055959146,0.035752047,-0.017741667,0.049429208,0.028609406,0.011492696,0.02834576,9.930118e-05,0.029337179,0.0034749003,-0.03529726,-0.039939478,0.020690551,-0.038004763,-0.028817823,-0.043486893,-0.028270252,0.0059846067,0.015412247,-0.043390065,-0.0014138267,0.017471705,0.05356933,0.02715097,0.039569862,-0.062943,-0.034749582,0.0008777908,0.0675221,0.024007978,0.0031043123,0.027889788,-0.03445838,0.037452813,-0.0027621544,0.023969939,-0.009094866,0.036054634,-0.021340095,-0.037330937,0.040376555,-0.004986992,-0.03990052,0.042271502,-0.08536139,-0.0006598113,0.017067881,-0.0027610878,-0.02476821,-0.062784016,-0.03830715,-0.016951045,-0.030409602,0.028290046,0.23991553,0.023503473,0.05884388,0.058152616,0.020723946,-0.02135011,-0.0051173195,-0.016681708,-0.002259752,-0.030207036,-0.0549771,0.00012621569,0.011039711,0.042263575,-0.018201714,-0.016499866,-0.05884972,-0.003648989,0.0905345,-0.02069992,-0.0061091743,0.019283017,-0.004311359,-0.008498275,-0.04787773,-0.07830959,-0.008039239,0.06235437,-0.032195073,0.026736373,-0.028080447,-0.0055820933,-0.015741734,0.022372428,-0.045883544,0.006287348,0.00815757,-0.02270716,0.04383064,0.032934498,-0.0048761033,-0.022252927,0.04621255,0.008766575,0.021932865,-0.025348471,0.014570954,0.0072806864,-0.016246092,-0.009586651,-0.022996547,0.048953615,-0.041286524,0.028259734,-0.00597043,0.035233367,-0.0026454378,-0.039465167,-0.012321299,0.047967054,0.028550839,-0.008747889,-0.020866336,0.028850397,0.011088599,-0.008637932,-0.028480481,0.025351685,0.025868267,0.0541208,-0.013086459,0.026384352,0.0021744198,0.027667142,0.0018784789,0.000834316,0.020897273,0.009016351,0.010923388,-0.024518793,-0.06348609,0.006014297,-0.0059995763,-0.01937126,0.0024727983,-0.034490343,-0.043201663,0.034459982,0.034139056,-0.03874634,0.0006450406,-0.0029214497,0.041098777,-0.0039465795,-0.039712958,-0.027443014,0.08876157,-0.014081698,-0.03273841,0.015178783,0.04699851,-0.011091268,0.0083263405,-0.040112443,-0.0010450922,0.009587613,0.020363279,-0.005888644,-0.04613671,-0.046301674,0.024511818,0.03704997,0.04276697,-0.020893775,0.021045212,0.04033692,-0.010997089,0.012255821,0.0465898,0.0010655338,-0.020650163,0.0015658705,-0.0010962463,0.027102422,-0.008203381,0.016010148,-0.0031750903,-0.012816188,0.009983991,0.023945408,-0.015407778,-0.0018001252,-0.04690593,-0.026865732,0.076485984,0.008614749,0.019317294,0.036433235,0.05291814,-0.058751218,0.04688237,0.014626355,-0.018599166,-0.030803991,0.0018860105,-0.022214819,-0.013200535,-0.0016828662,-0.063589804,0.050749518,0.0365346,0.0096408455,0.01349575,-0.029395211,-0.0254344,-0.022846807,0.004075009,0.029912433,0.03520822,-0.03578342,0.020927504,-0.0048432965,-8.96882e-05,0.048644245,0.0508058,0.041002426,0.012992622,-0.006420863,0.04168337,-0.047271453,0.004409811,-0.009279406,-0.035831474,-0.0040501733,0.01103993,0.018319746,7.746303e-05,-0.0044661695,0.013096824,-0.015176836,0.01463277,0.036265526,-0.0010232329,-0.0062029744,0.0052484926,0.00077705464,-0.038035247,-0.028823432,0.034061342,-0.03522023,-0.037399366,0.086395435,-0.018911328,-0.0044514514,0.0049201204,0.0037076036,0.0031600937,-0.0056648524,0.036533415,-0.013805267,0.020872394,0.047385927,0.016163396,0.02046723,0.018223068,0.004926666,-0.014920018,0.011556781,-0.034832116,0.031817105,-0.009008603,0.0059258337,0.025435086,0.0033960948,-0.00088077324,-0.00052522344,-0.02481772,-0.006892044,-0.012455901,-0.06216124,0.029640399,-0.046165753,0.019490046,-0.038782977,0.014910694,0.018242279,-0.021650756,-0.005259605,0.035965417,0.024486573,0.003247571,-0.004952782,0.018351465,-0.036726,-0.0020461478,0.0017358243,0.011601636,0.034963217,-0.007884215,-0.006582223,-0.054761574,-0.024580618,0.00027273144,0.015654525,0.026229966,0.03311735,-0.07420325,0.01594053,0.0151897725,-0.0022405516,0.012351864,0.002486356,0.04179476,-0.03426908,-0.0067351023,-0.006881331,0.004097911,-0.026725197,-0.069618255,0.0004452858,-0.021458758,0.07718054,0.0010037513,0.003164556,0.0026084066,-0.018923797,0.0269441,-0.02631331,-0.01254047,0.018437695,0.0070635057,-0.051561736,-0.071993046,-0.04465397,0.017477872,-0.016710106,-0.044878103,0.005732748,0.04080236,-0.009640836,-0.06153385,-0.032956164,0.021481646,0.0038290655,0.0009182054,0.028897807,-0.017629152,0.03477546,-0.013771932,0.0025410268,-0.0005709089,-0.0032495891,-0.055430736,0.01036431,0.04876209,-0.0049979445,0.0016424259,0.0078042,-0.022183973,-0.014996539,-0.0107502835,-0.030615883,-0.05136922,-0.018829232,0.040872928,0.0013159909,0.011390043,-0.07232385,-0.00059373723,0.020386256,-0.0037420166,-0.020728843,0.025442922,-0.0130739715,0.005941372,0.0037186213,0.023387112,-0.03651091,0.05848994,0.029708914,0.028285269,-0.04167179,-0.01853503,0.0085558435,-0.027956648,-0.0061378344,-0.003688572,-0.023759883,-0.0096918475,0.017439287,-0.032056946,-0.0052264817,-0.041586883,0.0046165483,0.05429132,0.005795532,0.01054619,-0.008644093,0.014316672,0.021387026,-0.047480684,-0.038427852,0.09448459,-0.028645435,0.010655812,-0.040909763,0.0095285475,-0.016652687,0.0030824146,0.020575227,-0.02424002,-0.028211756,-0.010982307,-0.035475288,-0.012092531,-0.056180544,0.02097782,-0.030443514,-0.020236166,0.0045525176,-0.010482919,0.023401577,-0.014146411,0.009050342,-0.026293462,0.019949518,0.0100248195,0.006300548,0.036751784,-0.026291855,-0.011388042,0.044644542,0.015296916,0.02228091,-0.01487683,0.038773064,0.013513986,-0.017465716,0.011811812,0.01786662,-0.0073691756,-0.04256248,-0.03214264,-0.022507777,0.017950432,-0.0028374968,-0.02879256,0.009634212,0.0071646436,0.053369615,-0.007620857,-0.033182558,-0.05027073,-0.004567012,-0.14503036,0.025181267,0.008915226,0.012041603,-0.029921347,-0.014301419,-0.0026928023,0.020967118,0.01729618,0.00038196772,0.0028757255,0.008992622,0.043883175,0.0013119476,0.019939968,0.04759569,0.010670839,-0.02703823,0.011240858,0.03712138,0.038419895,0.0046867845,0.0180502,0.012503546,-0.0063578007,-0.019000154,0.024577292,0.016204745,-0.032758992,0.049135983,0.0018484714,-0.0066161347,0.02046915,0.026495164,0.045807157,-0.007838389,0.00880857,-0.07401647,0.01854663,-0.027753059,0.027315388,0.021302985,-0.03958119,0.012964186,0.039900016,0.024663886,0.0002117679,0.00068206794,-0.018210791,-0.03154928,-0.06483021,-0.038692582,-0.012951096,0.02449499,0.031430643,-0.04018559,-0.01253067,-0.002682498,0.02259247,0.053597208,-0.028184399,0.023772236,-0.013004496,-0.011146961,0.06206533,0.03885153,-0.036092587,-0.006748724,0.032622226,-0.071656145,-0.025561122,0.0012188603,-0.020099625,-0.019639712,0.025951715,-0.02144778,0.050695248,-0.0061835325,-0.007723084,-0.006376267,-0.017524628,0.010906822,-0.009046286,0.036732204,-0.015501205,0.017466733,-0.00461216,0.029410254,-0.02022063,0.019956969,-0.05747594,-0.05805161,0.025565268,-0.017413931,0.022074433,0.0181809,-0.01877516,-0.02150897,-0.041197337,-0.08481811,0.02380866,-0.028399456,0.015859216,-0.024038704,-0.0634284,0.028666982,-0.03291718,-0.015656842,0.001387333,-0.009982004,0.01150186,-0.02560076,-0.028941654,0.013365276,-0.050535716,0.00711002,-0.031255726,0.051037375,-0.02396556,0.015052621,0.016661467,0.013567956,-0.0020554673,-0.029492628,0.099986486,-0.015466015,-0.0027475269,-0.0004913478,0.00381603,0.013855272,0.04167947,-0.041168857,-0.038396504,-0.04989316,-0.0006428836,0.06657666,0.013580768,0.053981572,-0.052068274,-0.008934542,0.021171192,-0.008941419,0.009513155,-0.010220938,-0.011067752,0.002188556,0.015363692,-0.020251716,0.012309029,-0.049659465,-0.014584198,-0.016640056,-0.025825275,0.023951268,-0.015776321,-0.025286773,-0.040541604,0.005266193,-0.023709277,0.07470874,-0.03055376,-0.025548417,0.046194825,-0.0965009,-0.0017859687,0.029681215,-0.015310616,0.028434215,-0.02353473,0.0020783131,-0.0065499395,-0.011084931,0.0134163285,0.016808305,-0.010656778,0.04574088,-0.0054633557,0.028009506,0.020829927,0.0017961825,0.0036996563,0.019407198,0.032799028,0.009859764,-0.029788548,0.04772851,0.0019243577,-0.016483098,-0.00020273113,-0.046156187,0.026694223,-0.05336346,-0.033791646,-0.017694062,0.063632034,0.034619503,0.021769926,0.016800543,-0.029902278,0.032026526,-0.0059212493,-0.024726626,-0.017985376,-0.030408148,-0.019144809,0.0009050078,0.037143618,0.026507434,-0.02721709,-0.015374595,0.002221495,-0.00016542838,0.010748856,0.07042733,-0.0380954,0.013716667,0.0062142736,-0.00842654,0.027136628,0.0042634713,-0.01774895,0.053040244,0.013282435,0.017157614,-0.004196995,-0.0077546034,0.0006308483,-0.02980305,0.003935983,-0.028751215,0.044864427,0.0024064214,-0.017509691,0.027037868,0.03546043,-0.017790528,-0.0032175893,0.00587211,-0.052207723,-0.009028356,0.03883335,-0.027731838,-0.042683385,0.018439462]
520600	Depreciations	Depreciation	expense	[-0.031554047,0.0071822247,-0.03290236,0.007104911,-0.027131423,-0.006597921,0.055808924,0.024673142,-0.0054573636,0.007913126,-0.030786587,-0.025694553,0.0027367866,0.052843753,0.00023987211,-0.017991114,0.0075161834,-0.019811168,-0.015202957,0.006696576,-0.028541394,-0.040757336,0.031773698,0.008315634,-0.023441482,0.004305004,0.035859846,0.032284833,0.047942925,0.028825806,0.006026534,0.007218895,0.05141197,-0.035944846,-0.041316483,-0.047424167,0.012688781,-0.033273127,-0.043198813,0.0142574245,0.0040881345,-0.0031606029,0.0055661662,-0.022464665,0.03881914,-0.008560259,-0.034139585,-0.035410035,-0.02089646,-0.018301899,-0.01703777,-0.014119044,0.11237128,0.017904589,-0.0027962837,0.04211763,-0.05233625,-0.011696798,-0.09160381,0.029977543,-0.03016616,0.04001343,-0.0031859446,-0.026339749,0.011990138,0.07329797,0.0066906093,0.0064341244,-0.00081617024,-0.031243438,-0.012039269,0.04925637,-0.047739364,-0.015722184,-0.052861635,0.031335555,0.020463837,-0.014488213,-0.017247757,0.002045624,0.012645782,-0.020423815,0.014420663,0.00056724105,0.0066883415,0.086682,-0.010893638,-0.062920846,-0.044475507,-0.04481682,0.026179183,-0.019887734,0.007228828,-0.026480516,-0.029307112,-0.016818069,-0.071006656,0.021376861,0.03239449,0.0069658794,0.031913705,-0.011868516,0.03634715,-0.025511118,0.038094405,-0.042109117,-0.0014782256,0.038521104,0.03475871,-0.027262146,-0.011045289,0.012840932,0.0017098879,0.0024851202,0.002904923,0.011794226,0.0128749255,-0.046185046,0.02516842,-0.042970307,0.0060189096,0.01265895,0.015982175,0.0011541378,0.06927902,0.009622309,0.04053737,0.06290275,-0.013009012,-0.008726903,0.0023688553,0.017382823,-0.05953134,0.033425543,-0.039026044,-0.039241336,0.003946978,-0.008339972,-0.0012499833,-0.062776715,0.0025699902,0.013257285,-0.01567007,-0.022707405,0.04866192,-0.024727793,-0.005778716,-0.027641894,0.010911587,-0.0415476,-0.022809865,-0.016337901,0.045094226,-0.0062530013,0.008880939,0.0027137867,-0.035843864,0.06109176,0.028884012,-0.059089825,-0.06380769,0.05010003,-0.016207833,-0.037842162,0.0056431866,0.0066421367,-0.0031946627,0.008267204,0.014452515,-0.0032889242,0.027736545,-0.05176223,0.061566826,-0.039466124,0.01197567,0.03006092,0.11777457,0.002694029,0.0008312975,-0.0637659,-0.014944643,0.01837232,0.0040579364,-0.020138523,-0.020326335,0.033541646,0.014330957,-0.0036730932,-0.0024208855,-0.020631481,0.0035483784,-0.03927295,-0.030737748,-0.0028666586,0.043952726,-0.05080701,0.0039150678,0.00727317,-0.028111182,-0.0019786283,-0.0071855513,0.024726385,-0.003272683,0.007661107,-0.034227513,-0.0068537206,0.006619478,-0.017325057,0.043195277,-0.04179315,0.0013681939,-0.019255925,0.017746028,0.013714775,-0.05533257,0.00048596342,0.015123694,0.013659082,-0.0015675977,-0.015794095,-0.030625679,0.034365132,0.025368407,0.015621842,0.023991618,0.02708235,-0.030798737,0.020788303,0.025065357,0.012358588,-0.012164433,-0.014396857,0.018766183,-0.051616125,0.0321032,0.00080075243,0.023697788,0.04583369,-0.020204479,0.011265307,0.0061232117,-0.00896504,-0.054088775,-0.052690387,0.0057075145,0.026790159,0.008740377,0.0063589397,-0.032382276,-0.03457379,0.022068111,-0.006857646,0.0049057356,0.02724207,0.016329175,-0.005411163,-0.011097164,-0.02047566,-0.010743282,0.045718603,0.04572184,0.02341969,0.03136437,0.008926174,0.0020489164,-0.00933099,-0.017926589,-0.012494745,0.0014868544,0.030258682,0.008090417,-0.0058625047,0.037903026,0.020110654,0.02903172,0.014796271,-0.01722026,-0.0032831286,0.06672431,0.00077219633,0.012496422,0.034341823,-0.0031621915,-0.015266234,0.037133247,-0.0126470355,-0.05603476,-0.006336991,0.027954187,-0.06313511,-0.033999357,0.008735082,0.05001027,0.016043518,-0.07510742,-0.024637993,0.007577143,-0.149257,-0.03425451,-0.039945524,0.015043023,-0.0044075986,0.0029266085,-0.015813477,0.018801952,-0.038473003,0.0035643561,-0.0070218155,-0.06561844,0.02117364,0.047461476,0.027548779,0.031211691,0.01370017,0.02728994,-0.001999336,0.0057394006,0.010943662,0.011987542,0.007609136,-0.016856885,-0.02960443,0.014665289,0.014043761,0.04888839,-0.035553426,0.006795487,-0.016743163,0.009740531,0.015146048,-0.005110053,0.01100161,0.040674053,0.026600206,-0.0026928452,0.030933555,-0.0017243152,0.027783623,0.033415847,-0.033833068,0.026917364,-0.018363722,-0.0017889162,-0.0312935,0.018352741,0.0035213286,0.036133025,-0.03160538,-0.015249194,-0.00047967397,-0.025495723,-0.008398221,0.028997833,0.035028864,0.031574026,-0.026613371,0.04270797,-0.010658175,-0.09204792,0.022446843,0.0036451882,-0.01969326,-0.027915722,0.000816386,-0.03027405,0.043231737,-0.03690968,-0.0022172236,-0.024377855,0.023756972,-0.009592383,0.016032478,0.048678312,-0.03813638,-0.021735247,0.019079175,-0.08334689,0.0121725,0.02134027,-0.032543574,-0.0104299225,-0.042136393,-0.0007209701,-0.0026012324,-0.0046199705,0.017899012,0.22816406,-0.024878921,0.052690882,0.032132115,-0.017838363,-0.016525393,0.022629334,0.018159537,-0.008732708,-0.008538151,-0.024922734,-0.002265214,-0.0043834792,0.012499882,-0.019520447,0.0079739215,-0.040058028,0.022284437,0.075050086,-0.033120148,0.0017461714,0.024815561,0.020932779,0.015394238,-0.028058322,-0.01943689,-0.027722552,0.04701178,-0.027526563,0.020603292,-0.015329877,-0.037309457,0.058889125,-0.050726585,-0.007496843,0.021494925,-0.054339815,-0.03608844,0.030869074,0.03211599,-0.045061294,-0.009719085,-0.017426407,0.022589216,-0.001495746,-0.036902327,0.029921915,-0.041615605,0.036891934,0.0075384467,-0.0015100914,-0.008045143,0.0057781297,0.010389089,-0.03834855,-0.003497201,-0.01623704,0.0119141685,-0.010399226,0.018326223,-0.009009656,-0.020273274,-0.009717847,0.020136237,0.042180486,0.0006688185,-0.015900878,0.059988003,0.032022137,0.058851674,0.03832332,0.051594935,0.009575525,0.0025109586,0.008217772,-0.021372708,0.001200772,-0.006253229,0.04259807,-0.011990505,-0.027376026,-0.0019813762,-0.014258939,0.0051007015,0.0026545525,-0.032826416,-0.0019180258,0.01819051,-0.0010485633,-0.038575057,0.003909558,-0.0052429517,-0.016910806,0.01933352,-0.029834019,-0.031132637,0.072388746,-0.034331243,-0.03967687,0.018666726,0.002391707,-0.02525359,-0.0016978965,-0.012866352,-0.017984798,-0.023982152,0.03469822,0.015472223,-0.045873184,-0.032614637,0.046825238,0.013944792,-0.07463216,0.009394644,0.02375576,0.040606108,0.009372306,0.05887903,0.015699094,0.016047565,-0.011972912,0.002136717,0.0046106772,0.050088212,0.008412792,0.006997039,-0.044644892,0.033620607,0.008009889,0.033511885,-0.01945244,-0.021649156,-0.09178902,-0.020579709,0.06739075,0.0023454009,0.012386966,0.008588116,-0.0078394115,-0.016812038,0.02018387,0.018821213,-0.034913313,-0.043750446,0.00050422107,0.040653966,-0.005686722,0.014168821,-0.014827402,0.022693388,0.019850299,0.03134426,-0.0149786435,-0.022725891,-0.031848557,-0.04540687,-0.019126734,-0.010118013,-0.0408029,-0.02087538,0.011568752,-0.0077334708,0.028313521,0.04616471,0.027951384,-0.009268508,0.0046714717,-0.020064563,-0.020616362,0.0056659705,0.018768175,-0.04252845,-0.08244389,0.026793519,-0.010794145,-0.038568724,0.011032687,0.03777245,-0.0012448734,0.04334678,0.02712191,0.008742596,-0.009053898,-0.0009641423,-0.020140002,0.006443433,-0.043876365,-0.0031781644,0.020200124,-0.04242648,-0.033236686,0.088689506,-0.024024768,-0.033484925,0.018523695,-0.02878906,0.03677132,-0.016195701,0.05962044,-0.04913732,-0.028223315,-0.01739829,-0.016015729,-0.002606463,0.012733419,0.0060501443,0.02968203,0.023936175,-0.006141034,0.0029614142,-0.010741173,0.017084053,-0.049021523,0.034362204,-0.033770256,0.004699623,0.05041197,-0.006905264,-0.000833178,-0.061841633,0.018058194,-0.012135322,0.028936425,-0.042993974,0.027616424,0.022864584,0.009303645,0.0075066187,0.038189143,0.04072664,0.0038003614,-0.02230873,0.009786038,0.0018116464,0.020431353,0.02078617,0.003532313,0.028734276,0.0019716825,0.005794842,-0.021037512,-0.037141297,0.013595178,0.06806502,-0.028920684,0.002529795,-0.042109787,-0.020896092,0.051847,0.011444852,-0.016413456,-0.029590612,0.05090912,-0.0045471997,-0.002218096,-0.0037203587,0.0049914247,-0.007467455,-0.04865008,-0.026429214,-0.014350758,0.044073433,-0.0053243847,0.033463895,0.0061197868,-0.007041472,0.021689724,0.03140341,-0.017325247,-0.011431943,0.02246552,0.013942406,-0.015449344,-0.01122126,0.047804765,-0.02031586,-0.0024521975,0.004104637,0.002569925,0.042346805,-0.0640988,0.023571124,0.021980565,0.0003045051,-0.014765894,-0.04371303,0.034950297,0.023875304,0.0063078385,-0.024899855,0.015881501,-0.0059743915,-0.060647454,0.02310921,0.020644927,0.02521377,0.016792687,0.054465376,-0.015703976,-0.0029050028,-0.014705624,-0.035099715,-0.032397475,-0.019260095,0.0074359556,0.00949176,0.051066525,-0.023162734,-0.00597986,0.043588597,0.016135285,0.006886361,0.008889549,-0.008158362,0.033983346,0.01713826,0.05300287,0.00551832,0.03726036,-0.007735594,0.005801316,0.01570691,-0.023624416,-0.049215216,-0.066515975,0.028898485,-0.016458202,-0.015429179,-0.05784913,0.002669054,-0.012842859,-0.0037065186,-0.037673622,-0.040057678,0.044018958,-0.0001731772,0.028816523,-0.0068279537,0.029705526,-0.031880964,-0.039919592,-0.0642498,0.0507481,-0.027180454,0.037641864,-0.06075661,0.004531322,-0.0019131933,0.03655102,-0.026549159,0.012235616,0.041434545,-0.028177854,-0.050151553,0.018127976,-0.09440776,0.020401781,0.0013346195,-0.0032030405,0.020673094,-0.012510517,-0.0230263,-0.0015766991,0.03000262,-0.029771125,0.020994324,-0.012084361,0.050416477,0.016606985,-0.011028247,-0.013030453,0.018196762,-0.008034001,-0.013877408,-0.02857206,0.034014378,-0.029886626,-0.016347675,0.03686791,-0.015236013,0.011034916,-0.011628668,-0.007808614,-0.036689833,-0.03507315,-0.01103712,-0.017312437,0.01680395,0.017048964,0.06020229,0.014296123,-0.02780102,-0.043192282,-0.01050187,-0.15441324,0.03968358,0.012181021,0.005868252,-0.042713113,0.0224414,-0.030474868,-0.03335635,-0.020077012,-0.02659895,-0.011175173,0.01920613,0.005884329,0.009026085,-0.017972039,0.07364328,-0.031461213,-0.0066782106,0.027824542,-0.00093520153,0.018058715,0.006750992,0.012316921,-9.937376e-05,-0.0025027667,-1.6295066e-05,0.046505388,0.01989956,-0.010197557,0.012125439,0.009227456,0.0011360181,0.016001457,0.0063662427,0.014233028,0.0017811973,0.015335041,-0.04875626,-0.0501625,0.0026791233,0.020933399,0.018078253,-0.03898111,0.049471367,0.020710245,0.030417196,-0.028744016,-0.02243115,-0.007845146,-0.05037261,-0.039615914,0.027615951,-0.008887053,0.043838866,0.00029916046,0.033696756,-0.048164893,-0.005298508,0.049150113,-0.0018086337,-0.030789057,0.051773068,-0.0049887626,-0.052402083,0.016168188,0.023818018,-0.008920593,0.013261586,0.022840124,-0.03272945,-0.025500093,0.04104701,-0.011298874,-0.06426529,0.013765221,-0.035879415,0.04166407,-0.008931534,0.032643966,-0.019731607,-0.036009453,-0.019386495,-0.023996856,0.0087050125,0.007417056,-0.0015793585,-0.06374214,-0.017142005,-0.018293528,0.005998701,-0.064060815,-0.021956315,0.0016655994,-0.040061053,0.006318967,0.009807554,-0.06119527,-0.018789617,-0.020518538,-0.048721727,0.031320933,-0.030896157,0.007261258,-0.011944029,-0.0528692,0.013614155,-0.04382785,-0.016870981,0.035646245,0.021020371,0.005915929,-0.041052703,-0.0002018812,-0.009898453,-0.03731885,0.010119908,-0.02068683,0.0020021254,-0.0121357,0.013735303,0.009247093,-0.019449277,-0.021967715,-0.036447894,0.04792645,0.005478668,0.009545842,-0.02318613,0.006155399,0.016771503,0.041107766,-0.041641302,-0.031947006,-0.0087905405,0.016040707,0.0064968374,-0.019817289,0.05287819,0.011112446,-0.038961366,-0.007315764,-0.01605068,0.038789958,-0.021334192,0.019306054,0.019963576,0.052566443,-0.02611432,0.031261694,-0.036957797,-0.032457624,0.006843282,-0.015320998,-0.02044169,-0.008067652,0.008294776,-0.04427606,-0.025923034,0.011538763,0.029959463,0.024509609,-0.04081991,-0.00049945555,-0.0405401,-0.00947341,0.023088505,-0.0363124,0.023251006,0.025061764,-0.012776186,-0.01216732,0.03192089,-0.003360544,-0.022698464,0.03468134,-0.025323147,-0.026114434,0.0036226315,0.035842337,-0.020959472,0.035389196,0.03553367,0.04177804,-0.007912832,0.035055112,0.026406057,0.013740588,0.030925214,0.008832769,-0.007534445,-0.00924325,-0.022119077,-0.03732721,0.032139942,0.0058848625,0.00015669307,0.02477741,0.08285501,-0.024568096,0.042758282,-0.05192221,-0.026399443,-0.053954605,-0.032649565,-0.035366595,0.0140180895,-0.009527393,0.019007057,-0.02531939,0.0066517564,-0.020408444,-0.0018218637,-0.009802101,0.07620666,0.0010449417,0.0009935352,-0.019613767,-0.03621836,-0.0014585597,-0.0144564295,-0.013660274,0.0133710615,-0.018125689,0.014893949,-0.01383824,-0.043791298,-0.0056110895,-0.01054189,0.03255035,0.008275,0.014220562,0.0219325,-0.004883576,0.040476054,0.007918803,-0.00066336157,-0.02740128,0.0511027,0.022793807,0.013484377,0.05020225,-0.046510685,-0.06174806,-0.017961511]
520700	Taxes & Licenses	Taxes and License Fees	expense	[-0.046686973,-0.0026866929,-0.041761342,0.012316166,-0.005157957,-9.407703e-05,0.02339498,0.01873776,0.003273136,-0.0070412746,0.019757424,-0.021621365,0.01473108,0.009282831,0.004327918,-0.038120445,0.008135134,0.00207181,-0.02156241,-0.03375671,0.013918721,-0.061989546,-0.018687578,-0.015425287,0.026512522,0.01329857,0.014058009,0.0126779415,0.022509716,0.011148956,-0.0075985473,-0.02694599,-0.01886856,-0.030205755,-0.013131297,-0.06065319,-0.05111913,-0.01833643,-0.059555404,0.0132042365,0.0105679,-0.03233118,0.019389091,-0.018327143,0.017932197,0.02130498,-0.04610228,-0.014914186,-0.03616156,0.015814507,0.044215817,-0.002245904,0.085077696,-0.061129592,-0.008164083,0.026708456,-0.031459328,0.021785162,-0.09622326,0.0051702186,-0.042438354,0.015956493,-0.021725003,-0.025927229,-0.008448349,0.042969212,-0.05403708,0.02198274,-0.013077083,0.0015711548,0.03413312,0.00015025516,-0.012208013,-0.036630776,-0.075662225,0.0021388012,0.03189534,-0.005523578,-0.00016683579,0.0039805626,-0.005636254,-0.056280922,-0.017498802,-0.019196013,-0.0062990854,0.038947668,-0.0043565286,-0.0018430987,-0.02886694,0.0039888923,-0.012846809,-0.0066116326,0.033404607,-0.033925064,-0.039470483,-0.060872816,-0.07036323,0.030312886,0.00075599353,-0.0044722925,0.030398453,0.032142136,0.061103776,-0.025072552,-0.037956063,-0.023396451,0.010359173,-0.024351003,-0.0132731935,-0.04884647,0.0011438162,-0.0034815245,-0.011827465,0.009178054,0.011721637,0.0019310598,0.034591,0.0026850493,0.0152731985,-0.0072028795,0.052619405,0.008220875,0.060709108,-0.06158889,0.07050115,-0.011814092,0.024988795,0.006952642,0.03410946,0.005745429,0.0131652765,0.0056357025,-0.08090954,0.041430768,-0.046497423,-0.04156431,0.032951914,-0.022415616,-0.02640543,-0.014123321,-0.04581596,0.0029912794,0.030926678,-0.03287605,0.071106546,-0.025770446,0.05901414,0.0073239547,0.0008425052,-0.07568762,-0.038217947,-0.013625961,0.08177662,-0.03425595,0.0068005333,0.008268458,-0.037602626,0.017699737,0.016557502,0.0152038075,0.010170525,0.04023599,-0.010294894,-0.04514274,0.021541571,0.08357984,0.014301983,0.0020607365,0.0067867907,0.015774926,0.024336968,0.033212543,-0.0019217157,-0.014324848,-0.00042857375,0.035404693,0.04148922,0.020179445,-0.04617426,-0.03528419,-0.064438075,0.015536503,-0.036603805,-0.02364356,-0.008540726,-0.008720335,0.027637443,0.021792354,0.02622743,0.03650395,0.0036044037,-0.004678435,0.030311877,-0.013460117,0.0017336956,-0.015448389,0.0031916518,-0.015274739,-0.0033774667,-0.0030363463,-0.057055462,0.010916741,-0.009052971,-0.019090591,-0.025325464,0.01832317,0.017315535,-0.029015996,0.041454375,-0.05914347,0.014861903,0.024630465,0.009862814,-0.007864925,0.0010226732,0.043256845,0.019685293,-0.019217014,0.038391966,0.026389623,-0.018903038,0.021219978,0.033338785,0.043000624,0.0028864907,-0.00028015662,-0.020261878,0.027547985,0.02922351,-0.037982844,-0.038342334,0.02428211,0.03173757,-0.062155753,0.0009425675,-0.0010604846,0.013396758,0.050357584,-0.034662053,-0.0030083985,-0.019808462,-0.04068808,-0.04410374,0.021932553,0.04286533,0.0010756736,0.00021621984,0.057643972,-0.04530461,-0.048859403,0.023591625,-0.022894083,0.03190902,0.015739156,0.03907159,0.022916902,0.0002698295,0.0069719474,0.0007852161,0.0006288467,0.017377062,-0.030495724,0.01124773,0.03743855,-0.023355616,0.006856369,-0.046595503,-0.041456882,0.011382682,-0.011684108,0.013111779,-0.011363442,0.033556186,-0.0010385619,-0.0056233266,0.058222536,0.007180259,-0.015688809,0.059681617,-0.025055457,-0.0042343508,0.05310624,0.027396316,-0.02354586,-0.0054587903,0.012378103,-0.0054615196,0.041878514,0.01593439,-0.09021161,-0.04886065,-0.01615967,0.0712986,-0.0038390441,-0.02758241,-0.012466553,0.026878376,-0.15200756,-0.012127298,0.022950942,-0.012711792,-0.021346103,0.0034790705,-0.012547971,-0.026016822,0.00024654905,0.022707405,0.045990035,-0.051642697,-0.024211328,0.0059540775,-0.0039717294,-0.0056540403,-0.0011507712,0.028633123,-0.0039640698,-0.030775094,-0.039888088,-0.080333464,-0.0023142672,-0.010503418,-0.022735903,0.04362301,0.021633597,0.01071851,-0.03858962,-0.02605847,0.0055051465,0.037112705,0.01347468,0.0062736934,0.022433948,0.010518565,0.013858829,-0.017454458,0.039269056,0.027965313,0.024701437,0.0560136,-0.05933044,0.04511664,0.0010076249,-0.017693507,0.02069015,-0.032957874,0.023746055,-0.00076776935,-0.03472894,-0.03112647,-0.0073904116,-0.04893807,-0.02768255,0.00816133,-0.010900199,0.032422114,0.03460632,0.0025316307,-0.029362014,-0.070148185,0.027181504,-0.002405054,-0.00019832549,-0.00814204,-0.0067310967,0.0013529061,0.0060280142,0.0049026697,0.023222659,-0.034236796,0.0188264,0.0057218354,-0.012017236,0.033545744,-0.017980123,-0.019658191,0.0004616499,-0.09979718,-0.030616997,0.020503508,-0.02834573,-0.026635498,-0.04107121,-0.006523909,0.004938311,-0.021896908,0.031364474,0.20180924,0.012238256,0.040754873,0.0069739283,0.046118915,-0.038931493,-0.01573766,0.0023208822,-0.025476709,-0.030520042,0.0034950147,0.019603845,-0.0012039489,-0.01592943,0.009111194,0.03805801,-0.040008396,0.019606577,0.058894094,0.010358354,-0.012873993,0.0063145123,-0.02147086,0.0031339808,-0.04475506,0.014444366,-0.043868843,0.025643876,-0.00037817805,-0.006128893,-0.0137155475,-0.0068336944,0.009917075,0.004534825,0.0012728224,-0.032725457,0.024907032,-0.035454795,0.090629645,0.07245928,-0.02810267,-0.017443372,0.0047898316,0.02456405,-0.019575598,-0.055381,0.052559983,0.0071133124,-0.008380702,-0.027592432,0.005603257,-0.034041893,-0.06278952,0.020039087,-0.046720896,-0.00983199,-0.023501713,-0.055014793,-0.04197501,0.08297102,-1.9840767e-05,-0.011464422,-0.009083645,0.01493091,0.019800225,0.007773565,-0.016986312,-0.020949056,0.037477307,0.06404764,-0.005773571,0.015069769,0.011356143,0.019816533,-0.0068582166,0.015995651,0.032431923,0.00037174768,-0.013943163,-0.029096775,-0.048105504,-0.0020929163,-0.0087624015,0.020568736,0.0067059603,-0.030316677,0.047637742,0.0029313923,0.015333956,-0.040347055,0.01554581,-0.0063067516,0.015958086,-0.00420863,-0.06557832,0.0004447396,0.043898538,-0.007192562,-0.04844351,-0.0021572988,-0.009946909,0.015339802,0.020497829,-0.045666177,0.050002404,-0.016744273,0.02431823,-0.011904578,-0.06346872,0.0003905589,-0.00064116117,0.015804231,-0.02416876,0.034904186,0.011858637,0.026953815,0.009200497,0.030403053,0.047693256,0.011974109,-0.015651863,0.065243036,0.016155627,0.007584923,-0.0010443728,-0.024240103,-0.02506903,-0.009529277,-0.013521302,0.014069662,-0.029073369,-0.01671079,-0.05933318,0.028670946,0.02763872,-0.023912549,0.016897319,0.014039481,0.008928364,-0.049694102,-0.0012225115,0.05760084,-0.028816806,-0.048893917,0.010067768,-0.02609929,-0.009110268,0.029883878,-0.020185387,0.043345477,0.0534744,0.019762695,0.041770592,-0.042350385,-0.005109867,-0.0647596,-0.003191289,-0.012444691,-0.004190708,0.0010648934,-0.00698297,0.003502317,-0.013064383,0.093104415,0.018694822,0.012996941,0.05295693,-0.008808505,-0.021821957,-0.007507366,-0.030464208,-0.03073304,-0.02099694,0.028383764,-0.011609778,0.035032734,-0.026719356,0.00844714,-0.022331268,-0.008787589,0.034045666,0.0323782,-0.0034158367,-0.036871683,-0.0013821532,0.04709737,-0.007187444,-0.041559827,-0.03734941,-0.012393298,-0.011794936,0.07925642,-0.011829922,-0.025366018,0.0035741418,0.06921178,0.040491153,0.019112049,-0.0027734973,-0.01976312,-0.007568634,0.01271985,0.02776261,0.00050105504,0.023623329,-0.020553602,-0.012474845,0.05256908,0.00026308722,0.015483361,-0.0010595102,-0.015540462,-0.012537902,-0.011394042,0.0143167935,0.016964601,-0.010203439,0.05616236,0.023428196,-0.054173812,-0.031876184,-0.030775446,0.014947353,-0.027245944,0.001759711,0.0071731475,-0.026703063,0.016892321,0.03090211,0.014724217,0.003455835,-0.013642356,0.029569978,0.031132117,0.025916878,-0.019717967,0.038059633,0.03131011,-0.0056656557,-0.0170248,0.0070334286,-0.0071274056,0.05215977,-0.0018797438,0.013619882,0.018911337,-0.035464913,-0.03229642,0.0026740374,0.06465097,-0.003688187,-0.024562113,0.0013513815,-0.018065926,0.031230165,0.027486265,-0.0010334525,-0.007830063,-0.037793174,-0.01038932,0.005554355,0.04587764,0.009125816,-0.034673,0.06540663,-0.041049,0.024797164,-0.006321949,-0.016120678,0.02526626,0.018529342,-0.004855916,-0.05432606,0.005809374,0.059554055,-0.0051720627,-0.02147321,0.062598996,0.0061651766,0.0075696646,-0.022286344,-0.015991315,0.012944748,0.006962241,0.023924362,0.019957008,-0.018881029,-0.013367554,-0.009519932,-0.0019316996,-0.046086285,-0.026458653,-0.047281727,0.020120405,-0.032054663,-0.005953411,-0.032936588,-0.026285337,-0.03745182,-0.022585422,-0.013219106,0.040017243,-0.061124124,-0.019125175,-0.016061183,0.012182426,-0.004709202,-0.06939736,0.030440971,-0.004459035,0.03118041,0.01603665,0.010401727,-0.02267246,-0.010980824,1.8380422e-05,0.054342262,-0.005199723,0.024847189,-0.02506404,0.017664446,-0.008007307,-0.022641806,-0.0142138675,-0.018149992,0.020729035,0.02581644,-0.0013976382,-0.02994137,0.011869849,-0.04125781,0.0071213045,-0.03171322,-0.007278247,0.026608733,-0.00071767217,0.05801177,0.0005788267,0.03364595,-0.04849537,0.0027826857,-0.0337427,0.068676874,0.0038298962,0.04177368,-0.06247932,0.014915813,-0.005025468,-0.028383993,0.010300726,-0.039893605,0.013494032,-0.027346145,-0.049349807,0.002529833,-0.054233227,0.03636359,-0.048514184,-0.006951428,0.034238838,-0.024438836,0.016328575,0.015206932,-0.015703468,0.007525062,0.0167057,-0.0049656914,0.008709183,0.012514647,-0.01368708,0.0072277877,0.03435704,0.0093463715,0.041108064,-0.0069615007,0.030924983,-0.018900013,-0.0037292356,-0.0018777673,-0.040244225,0.010780989,-0.032577407,-0.058372013,-0.010940331,0.03655196,0.016074935,-0.0048213783,0.021567177,0.00061613123,0.008631528,-0.007685898,-0.016947065,-0.03524653,0.02496951,-0.12315524,-0.008651811,-0.032172676,-0.017334178,-0.022023039,0.0052175736,-0.00034664493,-0.0063330415,0.0027988816,0.011336432,-0.00503049,0.0151529275,0.013423782,-0.013215655,0.019569479,0.033254903,-0.01164038,-0.0020968944,0.038848728,0.029688679,-0.005606244,-0.02005136,-0.029161707,0.031205976,-0.015548661,0.009015801,0.014086119,0.027804162,-0.03520699,0.038601488,-0.0027738803,-0.00399896,0.015072925,0.05540395,0.02102827,0.016480286,-0.006767407,0.002327052,-0.032912876,-0.014631246,-0.019660607,0.033552833,-0.07005994,0.021783039,0.0028394454,0.07803654,-0.0155688645,-0.02655923,-0.023381747,-0.027389182,-0.0028562183,-0.025375599,-0.023334367,0.01619551,-0.0022533985,-0.011740449,-0.037023693,-0.023103535,0.005713401,0.05448636,-0.037043136,0.050566066,-0.009999127,-0.037339397,0.02730184,0.030450411,-0.029645002,0.037017398,0.03182005,-0.022212358,-0.0155632235,0.015071678,0.0025760895,-0.024709178,0.03746807,-0.02718059,0.044101987,0.011185231,0.0071648182,0.005430051,-0.008475281,0.027841967,-0.053447813,-0.04810089,0.027820256,0.02836036,-0.0130557185,0.011074384,0.006650325,0.0023415196,-0.04673948,-0.06351883,-0.024089195,0.031598747,0.0046971287,0.017713394,-0.021252586,-0.005018916,0.006561823,-0.03943473,0.0263126,-0.03898657,-0.017792223,-0.020089315,-0.026971817,0.011268414,0.00771566,-0.026712267,0.03529456,-0.010582255,0.012361444,0.025083262,-0.013388808,0.0057514347,-0.055882942,0.0010689464,-0.013123504,-0.02067363,-0.0069564465,0.0032609291,0.016847022,-0.03006152,0.03657454,-0.04483554,0.061094135,0.029861387,0.03680333,-0.00028007757,0.02087852,0.0016967871,0.04132204,0.021922972,-0.006309961,-0.030453607,-0.016909203,-0.017659565,0.019624414,0.07512814,-0.06483691,-0.024503756,0.011779375,0.021676218,-0.030579519,-0.029610945,-0.008445416,-0.003562978,0.0688236,0.0029763533,0.023478141,-0.063866094,-0.01126064,-0.02374808,0.010938612,0.04500112,-0.008645204,0.009547368,-0.035458706,-0.035501003,0.017738909,0.0054629836,-0.03168991,-0.008774778,-0.005666989,-0.0204559,-0.017307086,0.05786512,-0.055070374,0.013537827,0.00816078,-0.00925552,-0.00381413,0.015075329,-0.0032131416,0.006357784,0.015142888,0.008491159,-0.026191719,0.04888558,0.014291393,-0.009912021,0.004792159,0.010340739,0.049862124,0.046160843,0.005118702,0.06211862,-0.038604293,-0.0028389,0.0064175352,-0.0064531844,0.005067929,0.026134988,-0.043606807,0.021161636,0.0091372365,0.010223067,0.014557994,0.077354126,-0.049092222,0.023655582,0.03167348,-0.007180739,-0.011437645,-0.07654281,-0.015981562,-0.036357142,0.06508953,-0.019698024,-0.024265302,0.016901122,-0.025999468,-0.014215187,0.0059100334,0.07468018,-0.018194962,-0.008581786,0.004455695,0.0077458313,0.029880714,-0.027483694,0.011896689,0.06680574,-0.0048630447,0.016383639,-0.010625928,-0.060446564,-0.022102831,0.00685137,0.005394846,-0.005216941,0.032000262,-0.032221675,-0.04432205,0.009811292,-0.001816588,-0.012125139,-0.009411147,0.00424835,-0.018538876,0.0077824565,0.0631718,-0.0047853994,-0.051440388,-0.018623436]
\.


--
-- Data for Name: customer_contacts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer_contacts (id, customer_id, fullname, role, email, phone, notes, created_at) FROM stdin;
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customers (id, code, name, name_th, tax_id, billing_address, shipping_address, contact_name, contact_email, contact_phone, credit_limit_thb, payment_terms, blacklist, is_active, created_at, updated_at, name_de) FROM stdin;
\.


--
-- Data for Name: domain_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.domain_events (id, type, actor_id, ref_type, ref_id, payload, severity, created_at) FROM stdin;
\.


--
-- Data for Name: exec_snapshots; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exec_snapshots (id, snapshot_date, kpis, dept_budgets, stuck_count, created_at) FROM stdin;
1	2026-07-10	{"cash": {"totalCash": -67410}, "kpis": {"netIncome": -9000, "mtdExpenses": 33000, "outstandingLiabilities": 0}}	[{"dept_id": "dept-development", "pct_used": 0.5, "dept_name": "Development", "mtd_spend": 9630, "monthly_budget": 2000000, "is_over_threshold": false}, {"dept_id": "dept-executive", "pct_used": 0, "dept_name": "Executive", "mtd_spend": 0, "monthly_budget": 1000000, "is_over_threshold": false}, {"dept_id": "dept-finance-2", "pct_used": 0.5, "dept_name": "Finance & Account", "mtd_spend": 9630, "monthly_budget": 2000000, "is_over_threshold": false}, {"dept_id": "dept-hr-2", "pct_used": 1.9, "dept_name": "HR", "mtd_spend": 9630, "monthly_budget": 500000, "is_over_threshold": false}, {"dept_id": "dept-it", "pct_used": 19.3, "dept_name": "IT", "mtd_spend": 57780, "monthly_budget": 300000, "is_over_threshold": false}, {"dept_id": "dept-marketing", "pct_used": 0, "dept_name": "Marketing", "mtd_spend": 0, "monthly_budget": 2000000, "is_over_threshold": false}]	0	2026-07-10 13:08:43.724878+07
2	2026-07-03	{"cash": {"netIncome": 0, "totalCash": 20000, "mtdExpenses": 5000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 5000}, "mtdTrend": [5000], "cashTrend": [20000]}	[]	0	2026-07-10 13:28:18.98554+07
3	2026-07-04	{"cash": {"netIncome": 0, "totalCash": 12000, "mtdExpenses": 11000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 11000}, "mtdTrend": [11000], "cashTrend": [12000]}	[]	0	2026-07-10 13:28:18.989111+07
4	2026-07-05	{"cash": {"netIncome": 0, "totalCash": 5000, "mtdExpenses": 18000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 18000}, "mtdTrend": [18000], "cashTrend": [5000]}	[]	0	2026-07-10 13:28:18.989783+07
5	2026-07-06	{"cash": {"netIncome": 0, "totalCash": -8000, "mtdExpenses": 22000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 22000}, "mtdTrend": [22000], "cashTrend": [-8000]}	[]	0	2026-07-10 13:28:18.99029+07
6	2026-07-07	{"cash": {"netIncome": 0, "totalCash": -28000, "mtdExpenses": 26000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 26000}, "mtdTrend": [26000], "cashTrend": [-28000]}	[]	0	2026-07-10 13:28:18.990783+07
7	2026-07-08	{"cash": {"netIncome": 0, "totalCash": -45000, "mtdExpenses": 29000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 29000}, "mtdTrend": [29000], "cashTrend": [-45000]}	[]	0	2026-07-10 13:28:18.991267+07
8	2026-07-09	{"cash": {"netIncome": 0, "totalCash": -58000, "mtdExpenses": 31000, "outstandingLiabilities": 0}, "kpis": {"mtdExpenses": 31000}, "mtdTrend": [31000], "cashTrend": [-58000]}	[]	0	2026-07-10 13:28:18.991743+07
\.


--
-- Data for Name: expense_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.expense_items (id, expense_id, description, amount, mapped_account_code, confidence_score, created_at, qty, unit_price) FROM stdin;
1077	135	ค่าคอมมิชชัน	5000.00	520400	0.580762061255188	2026-07-08 16:22:32.651905	1.00	0.00
1078	135	ค่าแพนฟิเล	4000.00	110600	0.42294176964156416	2026-07-08 16:22:32.651905	1.00	0.00
1079	136	ค่าอาหารกลางวัน	5000.00	510400	0.6169733354528837	2026-07-08 19:16:52.303354	1.00	0.00
1080	136	ค่าบริการอื่น	4000.00	410300	0.6610424907568855	2026-07-08 19:16:52.303354	1.00	0.00
1081	137	ค่าตอบแทนลางเสือ	5000.00	410300	0.47270673188051704	2026-07-08 19:25:47.780055	1.00	0.00
1082	137	ค่าพัฒนาที่	4000.00	520600	0.4688981668803599	2026-07-08 19:25:47.780055	1.00	0.00
1083	145	ค่าออกแบบลายเสื้อ	5000.00	520200	0.5161020967413777	2026-07-09 12:42:11.902188	1.00	0.00
1084	145	ค่าพิมพ์เสื้อ	4000.00	520100	0.4994711879067635	2026-07-09 12:42:11.902188	1.00	0.00
1085	147	คำออลมาแลยเอือ	5000.00	510100	0.34936265809740186	2026-07-09 17:49:14.654858	1.00	0.00
1086	147	คำพมพทเลือ	4000.00	520600	0.3646146981074827	2026-07-09 17:49:14.654858	1.00	0.00
1087	148	ค่าออกแบบลายเสื้อ	5000.00	520200	0.5161020967413777	2026-07-09 19:29:30.595067	1.00	0.00
1088	148	ค่าพิมพ์เสื้อ	4000.00	520100	0.4994711879067635	2026-07-09 19:29:30.595067	1.00	0.00
1089	149	ค่าออกแบบลายเสื้อ	5000.00	520200	0.5161020967413777	2026-07-10 11:39:19.15769	1.00	0.00
1090	149	ค่าพิมพ์เสื้อ	4000.00	520100	0.4994711879067635	2026-07-10 11:39:19.15769	1.00	0.00
1091	150	ค่าออกแบบลายเสื้อ	5000.00	520200	0.5161020967413777	2026-07-10 11:40:32.085598	1.00	0.00
1092	150	ค่าพิมพ์เสื้อ	4000.00	520100	0.4994711879067635	2026-07-10 11:40:32.085598	1.00	0.00
1093	151	ค่าตอบแทนงานที่ได้	5000.00	410200	0.595298985589414	2026-07-10 12:30:51.864669	1.00	0.00
1094	151	ค่าพัฒนาสื่อ	4000.00	520200	0.5244006572724993	2026-07-10 12:30:51.864669	1.00	0.00
\.


--
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.expenses (id, submitter_id, vendor_name, transaction_date, subtotal, vat_amount, total_amount, payment_method, status, ocr_raw_json, is_corrupted, correction_notes, document_url, created_at, updated_at, rejection_reason, rejection_actor_id, rejected_at, disbursed_at, disbursed_by, gl_confirmed_at, gl_confirmed_by, pr_id, po_id, journal_entry_id, created_to, vendor_address, created_to_address) FROM stdin;
151	959	บริษัท เนสซ์ เล่ห์ จำกัด	2025-08-04	9000.00	630.00	9630.00	cash	dept_verification	{"items": [{"amount": 5000, "description": "ค่าตอบแทนงานที่ได้"}, {"amount": 4000, "description": "ค่าพัฒนาสื่อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เนสซ์ เล่ห์ จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2F8515fa79-40cd-44af-8672-099abaf47c15.webp	2026-07-10 12:30:47.027341	2026-07-10 12:30:51.864669	\N	\N	\N	\N	\N	\N	\N	17	\N	\N	\N	\N	\N
153	952	\N	\N	0.00	0.00	0.00	cash	draft	\N	f	\N	\N	2026-07-13 11:02:42.128966	2026-07-13 11:02:42.128966	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
135	964	บริษัท บีมแอนด์ ดีโกลล์ จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	disbursed	{"items": [{"amount": 5000, "description": "ค่าคอมมิชชัน"}, {"amount": 4000, "description": "ค่าแพนฟิเล"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมแอนด์ ดีโกลล์ จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2F1ac9f709-a347-4161-b3cd-3263a33a5cd1.webp	2026-07-08 16:22:32.651905	2026-07-08 18:34:44.067968	\N	\N	\N	2026-07-08 18:10:52.796114	952	2026-07-08 18:34:44.067968	966	9	9	\N	\N	\N	\N
137	968	บริษัท ไปร์สแลนด์ ดีโกล จํากัด	2025-08-04	9000.00	630.00	9630.00	transfer	disbursed	{"items": [{"amount": 5000, "description": "ค่าตอบแทนลางเสือ"}, {"amount": 4000, "description": "ค่าพัฒนาที่"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ไปร์สแลนด์ ดีโกล จํากัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2F32bd7f7a-0253-45f3-890c-ef5f70505170.webp	2026-07-08 19:25:47.780055	2026-07-08 19:28:11.729281	\N	\N	\N	2026-07-08 19:28:05.920233	955	2026-07-08 19:28:11.729281	955	11	11	\N	\N	\N	\N
145	968	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	rejected	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2F7ef31c45-a887-4d5f-b156-0b91eede34de.webp	2026-07-09 12:41:31.004266	2026-07-09 14:54:11.18883	I don't like you	946	2026-07-09 14:54:11.18883	\N	\N	\N	\N	12	\N	\N	\N	\N	\N
136	968	บริษัท บิ๊กแมด จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	disbursed	{"items": [{"amount": 5000, "description": "ค่าอาหารกลางวัน"}, {"amount": 4000, "description": "ค่าบริการอื่น"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บิ๊กแมด จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2Ff1026e11-0bb3-4b3a-81b9-be94b0ab12c3.webp	2026-07-08 19:16:52.303354	2026-07-09 17:36:18.683273	\N	\N	\N	2026-07-09 17:36:18.683273	952	2026-07-09 17:33:24.467097	952	10	10	2037	\N	\N	\N
147	962	บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	dept_verification	{"items": [{"amount": 5000, "description": "คำออลมาแลยเอือ"}, {"amount": 4000, "description": "คำพมพทเลือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2Fc60ee9b6-c228-432d-9e98-3af7bf2f7007.webp	2026-07-09 17:44:52.491442	2026-07-09 17:49:14.654858	\N	\N	\N	\N	\N	\N	\N	13	\N	\N	\N	\N	\N
150	964	บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	dept_verification	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	f		/api/slips/file?key=2026%2F07%2F21849439-29dd-42e8-a140-cdd3703f5ddc.webp	2026-07-10 11:40:08.285969	2026-07-10 11:40:32.085598	\N	\N	\N	\N	\N	\N	\N	16	\N	\N	\N	\N	\N
148	964	บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	disbursed	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "Payment method radio buttons all appear unchecked; paymentMethod left empty per rules.", "transactionDate": "2025-08-04"}	f	Payment method radio buttons all appear unchecked; paymentMethod left empty per rules.	/api/slips/file?key=2026%2F07%2Fb7bd89b0-c15f-48d4-870d-0cfc73486aff.webp	2026-07-09 19:29:16.632477	2026-07-09 22:37:49.373617	\N	\N	\N	2026-07-09 22:37:37.620574	946	2026-07-09 22:37:49.373617	946	14	\N	\N	\N	\N	\N
152	957	\N	\N	0.00	0.00	0.00	cash	draft	\N	f	\N	\N	2026-07-12 17:32:33.28978	2026-07-12 17:32:33.28978	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
130	946	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	disbursed	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสือ"}, {"amount": 4000, "description": "ค่าพิมพ์เสือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "waybillId": "WB-2026-000002", "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04", "reconstructedFrom": "waybill"}	f	\N	\N	2026-07-09 23:23:35.81764	2026-07-09 23:23:45.006761	\N	\N	\N	2026-07-09 23:23:35.819059	946	2026-07-09 23:23:45.006761	946	\N	\N	\N	\N	\N	\N
149	951	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	2025-08-04	9000.00	630.00	9630.00	transfer	dept_verification	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "Payment method radio buttons are not visibly selected on receipt.", "transactionDate": "2025-08-04"}	f	Payment method radio buttons are not visibly selected on receipt.	/api/slips/file?key=2026%2F07%2Fed263627-c94d-4a09-b956-1a411b4feea1.webp	2026-07-10 11:38:50.664609	2026-07-10 11:39:19.15769	\N	\N	\N	\N	\N	\N	\N	15	\N	\N	\N	\N	\N
\.


--
-- Data for Name: hook_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.hook_events (id, provider_id, external_id, event_type, received_at, payload, headers, signature_ok, status, processed_at, processed_by, error, replay_count) FROM stdin;
1	generic	\N	generic	2026-07-02 00:38:08.037968+07	{"_raw": ""}	{"host": "localhost:3003", "accept": "*/*", "user-agent": "curl/8.7.1", "x-forwarded-for": "127.0.0.1", "x-forwarded-host": "localhost:3003", "x-forwarded-port": "3003", "x-forwarded-proto": "http"}	f	received	\N	\N	\N	0
2	generic	smoke-1	generic	2026-07-02 00:38:12.851502+07	{"hello": "world"}	{"host": "localhost:3003", "accept": "*/*", "user-agent": "curl/8.7.1", "content-type": "application/json", "content-length": "17", "x-forwarded-for": "127.0.0.1", "x-hook-event-id": "smoke-1", "x-forwarded-host": "localhost:3003", "x-forwarded-port": "3003", "x-forwarded-proto": "http"}	t	received	\N	\N	\N	0
3	generic	smoke-2	generic	2026-07-02 00:38:12.867914+07	{"hello": "world"}	{"host": "localhost:3003", "accept": "*/*", "user-agent": "curl/8.7.1", "content-type": "application/json", "content-length": "17", "x-forwarded-for": "127.0.0.1", "x-hook-event-id": "smoke-2", "x-forwarded-host": "localhost:3003", "x-forwarded-port": "3003", "x-forwarded-proto": "http"}	f	received	\N	\N	\N	0
5	line	msg-1	message:text	2026-07-02 00:38:22.36296+07	{"events": [{"type": "message", "message": {"id": "msg-1", "text": "hello", "type": "text"}, "timestamp": 1700000000, "webhookEventId": "evt-1"}], "destination": "U123"}	{"host": "localhost:3003", "accept": "*/*", "user-agent": "curl/8.7.1", "content-type": "application/json", "content-length": "154", "x-forwarded-for": "127.0.0.1", "x-forwarded-host": "localhost:3003", "x-forwarded-port": "3003", "x-forwarded-proto": "http"}	t	received	\N	\N	\N	0
6	line	evt-2	follow	2026-07-02 00:38:22.38603+07	{"events": [{"type": "follow", "source": {"type": "user", "userId": "U456"}, "webhookEventId": "evt-2"}]}	{"host": "localhost:3003", "accept": "*/*", "user-agent": "curl/8.7.1", "content-type": "application/json", "content-length": "96", "x-forwarded-for": "127.0.0.1", "x-forwarded-host": "localhost:3003", "x-forwarded-port": "3003", "x-forwarded-proto": "http"}	t	received	\N	\N	\N	0
\.


--
-- Data for Name: hook_providers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.hook_providers (id, display_name, kind, secret_env, enabled, created_at) FROM stdin;
line	LINE Official Account	line	LINE_CHANNEL_SECRET	t	2026-07-02 00:33:02.907587+07
generic	Generic Webhook	generic	HOOK_GENERIC_SECRET	t	2026-07-02 00:33:02.907587+07
\.


--
-- Data for Name: journal_entries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.journal_entries (id, expense_id, entry_date, description, created_at, is_draft, finalized_at, finalized_by, draft_source, pr_id, po_id, step, so_id) FROM stdin;
2033	135	2026-07-08	Disbursed employee reimbursement for บริษัท บีมแอนด์ ดีโกลล์ จำกัด (EXP-135)	2026-07-08 18:10:52.821176	f	\N	\N	expense	\N	\N	reimbursement	\N
2034	137	2026-07-08	Disbursed employee reimbursement for บริษัท ไปร์สแลนด์ ดีโกล จํากัด (EXP-137)	2026-07-08 19:28:05.928647	f	\N	\N	expense	\N	\N	reimbursement	\N
2036	136	2026-07-09	DRAFT: Disbursed reimbursement for บริษัท บิ๊กแมด จำกัด (EXP-136)	2026-07-09 17:33:24.477127	f	2026-07-09 17:33:24.485279	952	expense	\N	\N	reimbursement	\N
2037	136	2026-07-09	DRAFT: Disbursed reimbursement for บริษัท บิ๊กแมด จำกัด (EXP-136)	2026-07-09 17:35:01.365168	f	2026-07-09 17:35:01.368023	952	expense	\N	\N	reimbursement	\N
2038	136	2026-07-09	DRAFT: Disbursed reimbursement for บริษัท บิ๊กแมด จำกัด (EXP-136)	2026-07-09 17:36:18.691189	f	2026-07-09 17:36:18.69377	952	expense	\N	\N	reimbursement	\N
2039	148	2026-07-09	DRAFT: Disbursed reimbursement for บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด (EXP-148)	2026-07-09 22:37:37.629707	f	2026-07-09 22:37:37.634012	946	expense	\N	\N	reimbursement	\N
2040	130	2026-07-09	DRAFT: Disbursed reimbursement for บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด (EXP-130)	2026-07-09 23:23:35.827769	f	2026-07-09 23:23:35.829772	946	expense	\N	\N	reimbursement	\N
\.


--
-- Data for Name: ledger_lines; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ledger_lines (id, journal_entry_id, account_code, debit, credit, description) FROM stdin;
52	2033	520400	5000.00	0.00	ค่าคอมมิชชัน
53	2033	110600	4000.00	0.00	ค่าแพนฟิเล
54	2033	110500	630.00	0.00	Input VAT 7% for EXP-135
55	2033	110200	0.00	9630.00	Disbursed cash at bank for EXP-135
56	2034	410300	5000.00	0.00	ค่าตอบแทนลางเสือ
57	2034	520600	4000.00	0.00	ค่าพัฒนาที่
58	2034	110500	630.00	0.00	Input VAT 7% for EXP-137
59	2034	110200	0.00	9630.00	Disbursed cash at bank for EXP-137
60	2036	510400	5000.00	0.00	ค่าอาหารกลางวัน
61	2036	410300	4000.00	0.00	ค่าบริการอื่น
62	2036	110500	630.00	0.00	Input VAT 7% for EXP-136
63	2036	110200	0.00	9630.00	Disbursed cash at bank for EXP-136
64	2037	510400	5000.00	0.00	ค่าอาหารกลางวัน
65	2037	410300	4000.00	0.00	ค่าบริการอื่น
66	2037	110500	630.00	0.00	Input VAT 7% for EXP-136
67	2037	110200	0.00	9630.00	Disbursed cash at bank for EXP-136
68	2038	510400	5000.00	0.00	ค่าอาหารกลางวัน
69	2038	410300	4000.00	0.00	ค่าบริการอื่น
70	2038	110500	630.00	0.00	Input VAT 7% for EXP-136
71	2038	110200	0.00	9630.00	Disbursed cash at bank for EXP-136
72	2039	520200	5000.00	0.00	ค่าออกแบบลายเสื้อ
73	2039	520100	4000.00	0.00	ค่าพิมพ์เสื้อ
74	2039	110500	630.00	0.00	Input VAT 7% for EXP-148
75	2039	110200	0.00	9630.00	Disbursed cash at bank for EXP-148
76	2040	110500	630.00	0.00	Input VAT 7% for EXP-130
77	2040	110200	0.00	9630.00	Disbursed cash at bank for EXP-130
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (id, user_id, type, target_type, target_id, payload_json, read_at, created_at, cleared_at) FROM stdin;
\.


--
-- Data for Name: po_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.po_items (id, po_id, description, qty, unit_price, mapped_account_code, created_at) FROM stdin;
\.


--
-- Data for Name: policy_audit; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.policy_audit (id, policy_id, actor_id, before_json, after_json, changed_at) FROM stdin;
\.


--
-- Data for Name: pr_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pr_items (id, pr_id, description, qty, unit_price, mapped_account_code, confidence_score, created_at) FROM stdin;
\.


--
-- Data for Name: purchase_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purchase_orders (id, pr_id, po_number, vendor_name, total_amount, currency, status, issued_at, issued_by, settled_at, settled_by, settled_slip_id, rejection_reason, rejection_actor_id, rejected_at, created_at, updated_at, vendor_country) FROM stdin;
9	9	PO-2026-000001	บริษัท บีมแอนด์ ดีโกลล์ จำกัด	9630.00	THB	submission	2026-07-09 11:09:24.298576	964	\N	\N	\N	\N	\N	\N	2026-07-09 11:09:24.298576	2026-07-09 11:09:24.298576	\N
10	10	PO-2026-000002	บริษัท บิ๊กแมด จำกัด	9630.00	THB	submission	2026-07-09 11:09:24.309442	968	\N	\N	\N	\N	\N	\N	2026-07-09 11:09:24.309442	2026-07-09 11:09:24.309442	\N
11	11	PO-2026-000003	บริษัท ไปร์สแลนด์ ดีโกล จํากัด	9630.00	THB	submission	2026-07-09 11:09:24.311425	968	\N	\N	\N	\N	\N	\N	2026-07-09 11:09:24.311425	2026-07-09 11:09:24.311425	\N
\.


--
-- Data for Name: purchase_requisitions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purchase_requisitions (id, requester_id, vendor_name, need_by_date, status, total_estimate, currency, justification, document_url, is_recurring, created_at, updated_at, rejection_reason, rejection_actor_id, rejected_at, dept_group_id, vendor_country) FROM stdin;
9	964	บริษัท บีมแอนด์ ดีโกลล์ จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-09 11:09:24.298576	2026-07-09 11:09:24.298576	\N	\N	\N	dept-it	\N
10	968	บริษัท บิ๊กแมด จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-09 11:09:24.309442	2026-07-09 11:09:24.309442	\N	\N	\N	dept-it	\N
11	968	บริษัท ไปร์สแลนด์ ดีโกล จํากัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-09 11:09:24.311425	2026-07-09 11:09:24.311425	\N	\N	\N	dept-it	\N
12	968	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-09 12:42:11.902188	2026-07-09 12:42:11.902188	\N	\N	\N	dept-it	\N
13	962	บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-09 17:49:14.654858	2026-07-09 17:49:14.654858	\N	\N	\N	dept-hr-2	\N
14	964	บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-09 19:29:30.595067	2026-07-09 19:29:30.595067	\N	\N	\N	dept-it	\N
15	951	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-10 11:39:19.15769	2026-07-10 11:39:19.15769	\N	\N	\N	dept-it	\N
16	964	บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-10 11:40:32.085598	2026-07-10 11:40:32.085598	\N	\N	\N	dept-it	\N
17	959	บริษัท เนสซ์ เล่ห์ จำกัด	\N	submission	9630.00	THB	\N	\N	f	2026-07-10 12:30:51.864669	2026-07-10 12:30:51.864669	\N	\N	\N	dept-development	\N
\.


--
-- Data for Name: sales_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sales_orders (id, so_number, customer_id, sales_rep_id, status, payment_terms, due_date, invoice_number, invoice_issued_at, ar_slip_id, vat_account_code, ar_account_code, cash_account_code, revenue_account_code, subtotal, vat_total, total_amount, currency, rejection_reason, rejection_actor_id, rejected_at, invoice_issuer_id, paid_by_id, paid_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: slips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.slips (id, expense_id, pr_id, file_path, mime_type, file_size, ocr_raw_json, ocr_confidence, ai_reasoning, uploaded_by, uploaded_at, po_id, status, confirmed_at, discarded_at, discarded_by, kind, bank_name, account_number, account_name, bank_branch) FROM stdin;
101	\N	\N	2026/07/ee59519d-0c51-4af8-abe0-99315f23632e.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าอุปกรณ์/สินค้า"}, {"amount": 4000, "description": "ค่าคอมมิชชัน"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมดิกัล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	964	2026-07-08 14:56:32.302415	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
102	\N	\N	2026/07/9777881b-8bbd-4665-946e-e714e151d0db.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าอีกแบบ"}, {"amount": 4000, "description": "ค่าเพิ่ม"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เบิมดิจิทัล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "credit_card", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	964	2026-07-08 15:33:13.483323	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
104	\N	\N	2026/07/e1ffa886-cd89-4b3b-bd66-927cf7b01a98.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนลาสซี"}, {"amount": 4000, "description": "ค่าพัฒนาแล้ว"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท วิบูลย์มาร์เก็ติ้ง จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	964	2026-07-08 15:45:46.635963	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
105	\N	\N	2026/07/9a8c8a7a-cf39-4875-bf6a-be63ea55b0de.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "บริษัท ไออูเปฟเทคโนโลยี จํากัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	964	2026-07-08 15:46:51.067416	\N	pending	\N	\N	\N	book_bank	SCB	0123456789	บริษัท ไออูเปฟเทคโนโลยี จํากัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
107	\N	\N	2026/07/137a6611-33d3-4e0e-9217-fe68957a42b0.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สายาพิว เจอ้พา รัต รังสิต", "accountName": "อุมาพิมพ์ จึงภูพิน", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	964	2026-07-08 15:56:38.675315	\N	pending	\N	\N	\N	book_bank	SCB	0123456789	อุมาพิมพ์ จึงภูพิน	0080 สายาพิว เจอ้พา รัต รังสิต
106	135	\N	2026/07/1ac9f709-a347-4161-b3cd-3263a33a5cd1.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าคอมมิชชัน"}, {"amount": 4000, "description": "ค่าแพนฟิเล"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมแอนด์ ดีโกลล์ จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	964	2026-07-08 15:55:21.632839	\N	confirmed	2026-07-08 16:22:32.651905+07	\N	\N	receipt	\N	\N	\N	\N
108	\N	\N	2026/07/f7d7e289-149a-4549-a2bf-ca5e9a387e02.png	image/png	113216	{"items": [], "currency": "THB", "subtotal": 8094436, "vatAmount": 0, "vendorName": "SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED", "isCorrupted": false, "totalAmount": 8094436, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-02-27"}	0.7	\N	952	2026-07-08 17:53:45.255766	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
109	135	\N	2026/07/1ea3aeae-e012-4801-92e5-e0308e8626b3.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "เกษท์แบบลายเลือด"}, {"amount": 4000, "description": "ต่ำที่ป่าเลือด"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมดิจิตัล ได้โกว์ จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "credit_card", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	952	2026-07-08 18:05:43.607377	\N	confirmed	2026-07-08 18:10:52.796114+07	\N	\N	receipt	\N	\N	\N	\N
110	\N	\N	2026/07/b65e9073-583d-4125-9f75-bc155f0cc360.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนรายเดือน"}, {"amount": 4000, "description": "ค่าทําพลาฟี"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เดอะมอลล์ จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	945	2026-07-08 19:07:37.007527	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
111	\N	\N	2026/07/dd7d4d30-1d40-410d-8306-bbc78f116ab3.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาพีวิจาระจว่าทั้งตี", "accountName": "บริษัท ไอวอล์พีเทคโนโลยี่ จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	945	2026-07-08 19:10:49.813039	\N	pending	\N	\N	\N	book_bank	SCB	0123456789	บริษัท ไอวอล์พีเทคโนโลยี่ จำกัด	0080 สาขาพีวิจาระจว่าทั้งตี
112	136	\N	2026/07/f1026e11-0bb3-4b3a-81b9-be94b0ab12c3.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าอาหารกลางวัน"}, {"amount": 4000, "description": "ค่าบริการอื่น"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บิ๊กแมด จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-08 19:14:18.554979	\N	confirmed	2026-07-08 19:16:52.303354+07	\N	\N	receipt	\N	\N	\N	\N
113	136	\N	2026/07/89cc2f54-c723-4c93-98a9-83a7cdefd651.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาสาทิวเจอทรัค รังสิต", "accountName": "บุญชัย เดิมคามนท์", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	968	2026-07-08 19:16:13.935394	\N	confirmed	2026-07-08 19:16:52.303354+07	\N	\N	book_bank	SCB	0123456789	บุญชัย เดิมคามนท์	0080 สาขาสาทิวเจอทรัค รังสิต
114	137	\N	2026/07/32bd7f7a-0253-45f3-890c-ef5f70505170.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนลางเสือ"}, {"amount": 4000, "description": "ค่าพัฒนาที่"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ไปร์สแลนด์ ดีโกล จํากัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-08 19:24:54.544407	\N	confirmed	2026-07-08 19:25:47.780055+07	\N	\N	receipt	\N	\N	\N	\N
115	137	\N	2026/07/8352dc15-5b59-4a24-845d-a3885221125e.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "ไอแองพลอคโนโลยี จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	968	2026-07-08 19:25:42.02302	\N	confirmed	2026-07-08 19:25:47.780055+07	\N	\N	book_bank	SCB	0123456789	ไอแองพลอคโนโลยี จำกัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
116	137	\N	2026/07/f7ef31d8-750f-4efc-a438-996eb0c4bf22.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนเลือด"}, {"amount": 4000, "description": "ค่าแพนเพลิโอ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมอเลนต์ ดีโกล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	955	2026-07-08 19:27:34.313903	\N	confirmed	2026-07-08 19:28:05.920233+07	\N	\N	receipt	\N	\N	\N	\N
117	\N	\N	2026/07/69620773-f187-4b71-89be-e963f2595c96.png	image/png	68	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No text detected on receipt", "transactionDate": ""}	0.4	\N	952	2026-07-09 11:40:15.414644	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
118	\N	\N	2026/07/12bb5ea1-e3b6-4d57-b598-9944a11675e3.png	image/png	68	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Receipt image is completely blank; no data found.", "transactionDate": ""}	0.4	\N	964	2026-07-09 11:46:09.134679	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
119	\N	\N	2026/07/9fbc643a-7705-4e98-8bcd-75ccda4badd6.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "test receipt sample", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No actual receipt content provided; only placeholder text 'test receipt sample' found", "transactionDate": ""}	0.55	\N	968	2026-07-09 11:58:13.999486	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
120	\N	\N	2026/07/7ed986a5-f970-49d8-b2c2-7017a16f8d64.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": false, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:05:35.466075	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
121	\N	\N	2026/07/5e0bcd2b-f0f9-4751-939f-f3f60b8e14e9.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No valid transaction data found; document contains only placeholder text.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:06:12.635219	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
122	\N	\N	2026/07/aa981b9a-d298-461c-a3d5-cb6ef098a2ed.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No vendor name, transaction date, or itemized details found. Receipt text only contains 'test receipt sample' with no numerical data.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:07:04.413976	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
123	\N	\N	2026/07/ef6d6047-18e5-41a9-8f2e-6e28eb9b9d93.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No valid receipt content provided.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:11:35.59086	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
124	\N	\N	2026/07/9dc4682e-9ef8-4e71-bf07-e7ffdfb789ea.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No valid transaction details found; data is empty.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:12:16.401572	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
125	\N	\N	2026/07/24d8b449-1015-43e7-ab8c-ca01086f1472.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Document contains only the placeholder text 'test receipt sample' — no vendor, date, amounts, or line items present.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:12:51.87523	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
126	\N	\N	2026/07/4e0cfda8-02ad-48e1-bff7-c604676ce752.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Input contains only the placeholder text 'test receipt sample' — no vendor, date, line items, or totals are present.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:13:28.251069	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
127	\N	\N	2026/07/e7c0e0ee-deb6-4e0b-977d-a5873c637291.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Input is only 'test receipt sample' — no actual receipt content provided (no vendor, date, items, or amounts).", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:13:31.686939	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
128	\N	\N	2026/07/3b8c8c2d-78b1-4b2d-8dd9-fb6fa48e8b10.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No valid receipt data extracted; only 'test receipt sample' provided.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:14:56.967244	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
129	\N	\N	2026/07/1b7bbda0-eb42-4805-ada2-a98993aa6ad7.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Document contains only placeholder text 'test receipt sample'. No vendor name, date, line items, amounts, or payment information are present. The input is not a real receipt and cannot be parsed.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:18:50.120887	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
130	\N	\N	2026/07/a313a9bc-1414-4052-af23-758fdfa45d29.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Input text is only 'test receipt sample'. No vendor name, date, line items, or amounts are present; receipt content is missing/illegible.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:21:28.167737	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
131	\N	\N	2026/07/4242afbf-116d-425e-97c6-459e5470da5e.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Input is a placeholder/test string ('test receipt sample') with no actual receipt data — no vendor name, date, line items, totals, or payment information present.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:21:30.933496	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
132	\N	\N	2026/07/be5ea44b-18d3-4b89-8e1d-4f3bd588f71f.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No receipt data provided. Input contains only placeholder text 'test receipt sample' with no actual receipt content to parse.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:21:36.626098	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
133	\N	\N	2026/07/486579c6-525e-44b3-be1d-471f04ce7b45.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ไบรท์มิลล์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-09 12:22:58.075372	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
134	\N	\N	2026/07/8879f2ba-92bd-4de6-99d1-0315edc64ee3.webp	application/octet-stream	20	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "No receipt content provided. Input text is only 'test receipt sample' with no vendor name, date, line items, or totals to extract.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:29:18.544721	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
135	\N	\N	2026/07/6ca42a0e-6e1d-46ea-a43f-9ec8230ebdbb.webp	application/octet-stream	64386	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Input is raw binary WEBP image data (RIFF/WEBP header detected). No readable receipt text fields (vendor name, date, items, totals) are present in the provided content, so no fields can be extracted. Please provide the receipt as text (OCR output) or a viewable image.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:31:07.180826	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
136	\N	\N	2026/07/8cb3e525-fefe-48a1-980c-da2e0b7cceed.webp	application/octet-stream	64386	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Document is binary WEBP image data, not OCR text. Cannot parse as receipt.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:31:14.235893	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
137	\N	\N	2026/07/9a9ea454-0c5a-4919-9481-27b81c4825ab.webp	application/octet-stream	64386	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Document content is binary WebP image data (RIFF/WEBP container), not extractable receipt text. No vendor name, date, line items, or totals could be read. Please provide the receipt as extracted OCR text or as a viewable image.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:32:12.218628	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
138	\N	\N	2026/07/d611436a-c8b7-4a98-8889-8b052950d79c.webp	application/octet-stream	64386	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Input is raw WebP image binary data (RIFF/WEBP header) rather than extracted receipt text. No vendor, date, items, or totals can be parsed. Please provide the receipt as image with OCR-extracted text, or as a clear text/structured representation.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:32:51.696825	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
139	\N	\N	2026/07/56c511eb-9de6-402a-b6b8-b49587ee2734.webp	application/octet-stream	64386	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Document text is raw binary WebP image data (RIFF/WEBP container with VP8X, ICCP, VP8 chunks); no readable Thai receipt text, vendor name, date, line items, or totals could be extracted. The input does not contain OCR-able receipt content.", "transactionDate": ""}	0.4	\N	968	2026-07-09 12:33:19.030973	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
140	\N	\N	2026/07/b6baac2b-021c-4fc5-a67d-e7b2892da0ff.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสือ"}, {"amount": 4000, "description": "ค่าพิมพ์เสือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ไนน์ทิลลส์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "No payment method selected; defaulting to cash", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-09 12:34:02.793383	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
141	\N	\N	2026/07/2cb77e0c-8671-4415-89a6-8f0c3e466d7b.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออมแผนล่าเลือด"}, {"amount": 4000, "description": "ค่าเพิ่มพันเลือด"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท นีวิน แอนด์ วัน เจ้าสิ้น", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-09 12:37:40.536855	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
142	\N	\N	2026/07/e53daf29-a7f5-404c-bc35-e5e14a1d3579.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-09 12:40:06.728415	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
143	145	\N	2026/07/7ef31c45-a887-4d5f-b156-0b91eede34de.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-09 12:41:30.802663	\N	confirmed	2026-07-09 12:42:11.902188+07	\N	\N	receipt	\N	\N	\N	\N
144	145	\N	2026/07/74aeef05-f5c1-4b72-8977-12128e1002b1.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "บริษัท ไอแอพพ์เทคโนโลยี จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	968	2026-07-09 12:42:00.714308	\N	confirmed	2026-07-09 12:42:11.902188+07	\N	\N	book_bank	SCB	0123456789	บริษัท ไอแอพพ์เทคโนโลยี จำกัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
145	\N	\N	2026/07/be4c4191-a409-4180-a67c-0607707df8a0.png	image/png	113216	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "SIAM COMMERCIAL BANK PUBLIC COMPANY LIMITED", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "Document is a Siam Commercial Bank passbook/account identification slip (account 012-345678-9, branch 0080 สาขาฟิวเจอร์พาร์ค รังสิต), not a sales receipt. No transaction date, transaction amount, VAT, or itemized purchases are printed on the slip.", "transactionDate": ""}	0.55	\N	952	2026-07-09 13:53:56.817758	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
146	\N	\N	2026/07/1f93d988-3290-4e66-9f06-3241b5b438f1.png	image/png	113216	{"items": [], "currency": "THB", "subtotal": 0, "vatAmount": 0, "vendorName": "ธนาคารไทยพาณิชย์ จำกัด (มหาชน)", "isCorrupted": true, "totalAmount": 0, "paymentMethod": "cash", "correctionNotes": "This is a Siam Commercial Bank savings account passbook identification page, not a receipt. Contains account holder name, branch (0080 สาขาฟิวเจอร์พาร์ค รังสิต), account number (012-345678-9), and account type (บัญชีเงินฝากออมทรัพย์). No transaction date, amounts, VAT, line items, or payment details are shown.", "transactionDate": ""}	0.55	\N	946	2026-07-09 16:37:28.695746	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
147	\N	\N	2026/07/e9970ef7-3493-4971-9ffc-c8a11d5cdcf5.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	946	2026-07-09 16:37:34.948262	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
148	\N	\N	2026/07/fe6b549e-e9f3-46e7-a293-4dfba92a3f85.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออนไลน์"}, {"amount": 4000, "description": "ค่าพนักงาน"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท นวัตกรรม สื่อสาร จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	968	2026-07-09 17:02:16.691747	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
149	136	\N	2026/07/ee0112da-91a6-4874-bc7e-ffdb56927c1d.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนลาวที่"}, {"amount": 4000, "description": "ค่าเพิ่มพัสดุ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บันทึกอีสาน ติดข้อบุญ จังหวัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	952	2026-07-09 17:36:10.74655	\N	confirmed	2026-07-09 17:36:18.683273+07	\N	\N	receipt	\N	\N	\N	\N
150	\N	\N	2026/07/760bbaa8-dfe8-4dfa-8731-05f3339c4c33.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออมบุญมาเลือ"}, {"amount": 4000, "description": "ค่ามีที่"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เน็ตวอร์ค ดีจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	952	2026-07-09 17:40:15.610658	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
151	\N	\N	2026/07/15576065-7c51-421c-b3c1-ad9339e782e3.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออลามูลม้าเลือ"}, {"amount": 4000, "description": "ค่าพัฒน์เลือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท นิรันดร์ แล้ว ดีจูอล่า จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	952	2026-07-09 17:43:22.657312	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
152	\N	\N	2026/07/3406e226-ae02-4a8f-9e9b-7d5411b6e135.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนลายสือ"}, {"amount": 4000, "description": "ค่าเพิ่มทั้งสิ้น"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เบมดิจิตอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	962	2026-07-09 17:44:13.407807	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
156	148	\N	2026/07/b7bd89b0-c15f-48d4-870d-0cfc73486aff.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "Payment method radio buttons all appear unchecked; paymentMethod left empty per rules.", "transactionDate": "2025-08-04"}	1	\N	964	2026-07-09 19:29:16.291781	\N	confirmed	2026-07-09 19:29:30.595067+07	\N	\N	receipt	\N	\N	\N	\N
153	147	\N	2026/07/c60ee9b6-c228-432d-9e98-3af7bf2f7007.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "คำออลมาแลยเอือ"}, {"amount": 4000, "description": "คำพมพทเลือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	962	2026-07-09 17:44:52.305093	\N	confirmed	2026-07-09 17:49:14.654858+07	\N	\N	receipt	\N	\N	\N	\N
154	147	\N	2026/07/64e50107-99c7-49c6-b47e-00d16d4b47d7.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "บริษัท ไอแอพพ์เทคโนโลยี จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	962	2026-07-09 17:49:02.205539	\N	confirmed	2026-07-09 17:49:14.654858+07	\N	\N	book_bank	SCB	0123456789	บริษัท ไอแอพพ์เทคโนโลยี จำกัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
155	\N	\N	2026/07/2366bda7-64b4-44d2-90c4-c9342a0f529e.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สายพิวเจอราล รังสิต", "accountName": "บิ๊นท์ ไอแอดพัทธ์ จ้างดู (มหัส)", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	962	2026-07-09 17:50:03.061136	\N	pending	\N	\N	\N	book_bank	SCB	0123456789	บิ๊นท์ ไอแอดพัทธ์ จ้างดู (มหัส)	0080 สายพิวเจอราล รังสิต
157	148	\N	2026/07/61834851-b4b0-4f06-8c6f-dd657f9f3b97.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซ์ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "Payment method radio buttons (เงินสด/บัตรเครดิต/โอนผ่านบัญชี) are all unchecked; cannot determine payment method.", "transactionDate": "2025-08-04"}	1	\N	946	2026-07-09 22:37:21.596465	\N	confirmed	2026-07-09 22:37:37.620574+07	\N	\N	receipt	\N	\N	\N	\N
158	\N	\N	2026/07/1f0d9f17-5179-460e-b571-b0932c7d90b8.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอจเจ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	946	2026-07-09 23:06:31.563492	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
159	130	\N	2026/07/84fef4ed-2f3c-4993-85ca-1fe9bb3e825f.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสือ"}, {"amount": 4000, "description": "ค่าพิมพ์เสือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	946	2026-07-09 23:07:47.934366	\N	confirmed	2026-07-09 23:23:35.819059+07	\N	\N	receipt	\N	\N	\N	\N
160	149	\N	2026/07/ed263627-c94d-4a09-b956-1a411b4feea1.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "Payment method radio buttons are not visibly selected on receipt.", "transactionDate": "2025-08-04"}	1	\N	951	2026-07-10 11:38:50.258804	\N	confirmed	2026-07-10 11:39:19.15769+07	\N	\N	receipt	\N	\N	\N	\N
161	149	\N	2026/07/e9864862-4565-4c84-a1a0-e382216ea9bd.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "บริษัท ไอแอพพ์เทคโนโลยี จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	951	2026-07-10 11:39:13.891553	\N	confirmed	2026-07-10 11:39:19.15769+07	\N	\N	book_bank	SCB	0123456789	บริษัท ไอแอพพ์เทคโนโลยี จำกัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
162	150	\N	2026/07/21849439-29dd-42e8-a140-cdd3703f5ddc.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	964	2026-07-10 11:40:08.074886	\N	confirmed	2026-07-10 11:40:32.085598+07	\N	\N	receipt	\N	\N	\N	\N
163	150	\N	2026/07/867080c3-6d50-4979-81e6-fd5c34f54ed6.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "บริษัท ไอแอพพ์เทคโนโลยี จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	964	2026-07-10 11:40:29.682812	\N	confirmed	2026-07-10 11:40:32.085598+07	\N	\N	book_bank	SCB	0123456789	บริษัท ไอแอพพ์เทคโนโลยี จำกัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
164	\N	\N	2026/07/2f481c72-4b9d-4c6b-a097-f2fd02fda5e0.png	image/png	113216	{"bankName": "SCB", "bankBranch": "0080 สาขาฟิวเจอร์พาร์ค รังสิต", "accountName": "บริษัท ไอแอพพ์เทคโนโลยี จำกัด", "isCorrupted": false, "accountNumber": "0123456789", "correctionNotes": ""}	1	\N	959	2026-07-10 12:29:35.286024	\N	pending	\N	\N	\N	book_bank	SCB	0123456789	บริษัท ไอแอพพ์เทคโนโลยี จำกัด	0080 สาขาฟิวเจอร์พาร์ค รังสิต
165	151	\N	2026/07/8515fa79-40cd-44af-8672-099abaf47c15.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าตอบแทนงานที่ได้"}, {"amount": 4000, "description": "ค่าพัฒนาสื่อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เนสซ์ เล่ห์ จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	959	2026-07-10 12:30:46.829268	\N	confirmed	2026-07-10 12:30:51.864669+07	\N	\N	receipt	\N	\N	\N	\N
166	\N	\N	2026/07/fe9b6838-2e06-44df-80fa-384ae4cffa0d.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออมทุนมาลาเอลี"}, {"amount": 4000, "description": "ค่าพิมพ์เลือ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท นันเช่นซ์ แอนด์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	957	2026-07-12 17:26:40.408749	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
167	\N	\N	2026/07/26dd7bed-bd42-41bf-9285-517158c3882f.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าของใบสั่ง"}, {"amount": 4000, "description": "ค่าของใบสั่ง"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บุ๊ค เด็กน้อย จังหวัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	0.85	\N	957	2026-07-12 17:32:33.16645	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
168	\N	\N	2026/07/134feeb2-ea85-4d4d-992a-75e9d564b326.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าอื่นๆ"}, {"amount": 4000, "description": "คำพิมพ์เลือด"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท เดว์ลิส จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "cash", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	952	2026-07-13 11:02:41.845202	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
169	\N	\N	2026/07/532ddce6-b04c-4eac-a241-b179a6f01f4b.webp	image/webp	64386	{"items": [{"amount": 5000, "description": "ค่าออกแบบลายเสื้อ"}, {"amount": 4000, "description": "ค่าพิมพ์เสื้อ"}], "currency": "THB", "subtotal": 9000, "vatAmount": 630, "vendorName": "บริษัท ไบร์ทมิลล์ ดิจิทอล จำกัด", "isCorrupted": false, "totalAmount": 9630, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2025-08-04"}	1	\N	952	2026-07-13 11:26:00.01454	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
170	\N	\N	2026/07/49861b85-9c3d-423b-aa13-9feef49d46d4.png	image/png	22697	{"items": [{"amount": 100, "description": "Front and rear brake cables"}, {"amount": 30, "description": "New set of pedal arms"}, {"amount": 15, "description": "Labor 3hrs"}], "currency": "USD", "subtotal": 145, "vatAmount": 9.06, "vendorName": "East Repair Inc.", "isCorrupted": false, "totalAmount": 154.06, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2019-11-02"}	0.85	\N	952	2026-07-13 12:16:04.288332	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
171	\N	\N	2026/07/d08795a3-de1d-490e-acad-504a1c5828b7.png	image/png	22697	{"items": [{"qty": 1, "amount": 100, "unitPrice": 100, "description": "Front and rear brake cables"}, {"qty": 2, "amount": 30, "unitPrice": 15, "description": "New set of pedal arms"}, {"qty": 3, "amount": 15, "unitPrice": 5, "description": "Labor 3hrs"}], "currency": "USD", "subtotal": 145, "createdTo": "John Smith", "vatAmount": 9.06, "vendorName": "East Repair Inc.", "isCorrupted": false, "totalAmount": 154.06, "paymentMethod": "", "correctionNotes": "", "transactionDate": "2019-11-02"}	0.85	\N	952	2026-07-13 12:33:35.479238	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
172	\N	\N	2026/07/f3cf1b8e-b955-4787-8b09-974bd98afe94.png	image/png	22697	{"items": [{"qty": 1, "amount": 100, "unitPrice": 100, "description": "Front and rear brake cables"}, {"qty": 2, "amount": 30, "unitPrice": 15, "description": "New set of pedal arms"}, {"qty": 3, "amount": 15, "unitPrice": 5, "description": "Labor 3hrs"}], "currency": "USD", "subtotal": 145, "createdTo": "John Smith", "vatAmount": 9.06, "vendorName": "East Repair Inc.", "isCorrupted": false, "totalAmount": 154.06, "paymentMethod": "", "vendorAddress": "1912 Harvest Lane New York, NY 12210", "correctionNotes": "", "transactionDate": "2019-11-02", "createdToAddress": "2 Court Square New York, NY 12210"}	0.85	\N	952	2026-07-13 12:50:08.355165	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
173	\N	\N	2026/07/fdc9ef58-1956-46c6-8af2-69d06365f599.png	image/png	22697	{"items": [{"qty": 1, "amount": 100, "unitPrice": 100, "description": "Front and rear brake cables"}, {"qty": 2, "amount": 30, "unitPrice": 15, "description": "New set of pedal arms"}, {"qty": 3, "amount": 15, "unitPrice": 5, "description": "Labor 3hrs"}], "currency": "USD", "subtotal": 145, "createdTo": "John Smith", "vatAmount": 9.06, "vendorName": "East Repair Inc.", "isCorrupted": false, "totalAmount": 154.06, "paymentMethod": "", "vendorAddress": "1912 Harvest Lane New York, NY 12210", "correctionNotes": "", "transactionDate": "2019-11-02", "createdToAddress": "2 Court Square New York, NY 12210"}	0.85	\N	952	2026-07-13 13:16:30.648456	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
174	\N	\N	2026/07/08246567-5081-4f14-bf81-951cd82b8025.png	image/png	2756758	{"bankName": "Summit City Bank", "bankBranch": "Sukhumvit Branch", "accountName": "MR. JAMES ANDERSON", "isCorrupted": false, "accountNumber": "1234567890", "correctionNotes": ""}	1	\N	952	2026-07-13 13:19:33.92164	\N	pending	\N	\N	\N	book_bank	Summit City Bank	1234567890	MR. JAMES ANDERSON	Sukhumvit Branch
175	\N	\N	2026/07/fb652f77-b250-41f7-a7d9-30c27a83a37c.png	image/png	22697	{"items": [{"qty": 1, "amount": 100, "unitPrice": 100, "description": "Front and rear brake cables"}, {"qty": 2, "amount": 30, "unitPrice": 15, "description": "New set of pedal arms"}, {"qty": 3, "amount": 15, "unitPrice": 5, "description": "Labor 3hrs"}], "currency": "USD", "subtotal": 145, "createdTo": "John Smith", "vatAmount": 9.06, "vendorName": "East Repair Inc.", "isCorrupted": false, "totalAmount": 154.06, "paymentMethod": "", "vendorAddress": "1912 Harvest Lane\\nNew York, NY 12210", "correctionNotes": "", "transactionDate": "2019-02-11", "createdToAddress": "2 Court Square\\nNew York, NY 12210"}	0.85	\N	965	2026-07-13 23:42:32.537401	\N	pending	\N	\N	\N	receipt	\N	\N	\N	\N
\.


--
-- Data for Name: so_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.so_items (id, sales_order_id, description, qty, unit_price, vat_amount, line_total, mapped_revenue_account_code, confidence_score, created_at) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, employee_code, fullname, line_user_id, created_at, is_active, hired_at, secondary_locale) FROM stdin;
959	EMP001	John Staff	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
960	EMP007	Lisa Staff	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
961	EMP010	Karen Staff	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
963	EMP025	Frank Finance	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
957	EMP022	Iris IT-Supervisor	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
954	EMP017	Steven Supervisor	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
944	EMP006	Charles Executive	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
945	EMP005	Olivia Director	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
946	EMP019	Tina Treasurer	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
947	EMP002	Sarah Approver	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
948	EMP008	David Approver	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
949	EMP015	Patricia Manager	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
950	EMP021	Nadia Marketing	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
951	EMP023	Oliver IT-Manager	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
952	EMP004	Emily Manager	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
953	EMP013	Michael Manager	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
955	EMP018	Andrew Supervisor	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
956	EMP020	Marcus Marketing	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
958	EMP024	Rita HR-Supervisor	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
962	EMP016	Jennifer Staff	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
964	IT001	Alex Admin	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
965	EMP003	Mark Reviewer	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
966	EMP009	Robert Reviewer	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
967	EMP012	Daniel Accountant	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
968	EMP029	Brian Admin	\N	2026-07-08 10:56:47.585918	t	2026-07-08	th
\.


--
-- Data for Name: waybill_attachments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.waybill_attachments (id, waybill_id, stage_key, kind, storage_backend, storage_key, filename, content_type, byte_size, uploaded_by, uploaded_role, caption, occurred_at, created_at) FROM stdin;
2	WB-2026-000001	awaiting_disbursement	payment_receipt	minio	waybill-attachments/WB-2026-000001/awaiting_disbursement/2026/07/591da1f2-a57d-4e71-8378-c9d3adb33118.webp	Sample-receipt.webp	image/webp	64386	918	finance	\N	2026-07-08 10:10:36.195368+07	2026-07-08 10:10:36.195368+07
3	WB-2026-000003	submission	slip	minio	waybill-attachments/WB-2026-000003/submission/2026/07/3f88bb93-042a-4fcc-a246-b0fb427c6ae4.png	Screenshot 2569-07-08 at 11.50.41.png	image/png	14009	957	supervisor	\N	2026-07-08 17:10:38.959924+07	2026-07-08 17:10:38.959924+07
4	WB-2026-000005	submission	payment_receipt	minio	2026/07/8352dc15-5b59-4a24-845d-a3885221125e.png	8352dc15-5b59-4a24-845d-a3885221125e.png	image/png	113216	968	staff	Book bank · SCB · 0123456789	2026-07-08 19:25:48.958467+07	2026-07-08 19:25:48.958467+07
5	WB-2026-000009	submission	payment_receipt	minio	2026/07/74aeef05-f5c1-4b72-8977-12128e1002b1.png	74aeef05-f5c1-4b72-8977-12128e1002b1.png	image/png	113216	968	staff	Book bank · SCB · 0123456789	2026-07-09 12:42:13.794507+07	2026-07-09 12:42:13.794507+07
6	WB-2026-000011	submission	payment_receipt	minio	2026/07/64e50107-99c7-49c6-b47e-00d16d4b47d7.png	64e50107-99c7-49c6-b47e-00d16d4b47d7.png	image/png	113216	962	staff	Book bank · SCB · 0123456789	2026-07-09 17:49:16.161932+07	2026-07-09 17:49:16.161932+07
7	WB-2026-000013	submission	payment_receipt	minio	2026/07/e9864862-4565-4c84-a1a0-e382216ea9bd.png	e9864862-4565-4c84-a1a0-e382216ea9bd.png	image/png	113216	951	staff	Book bank · SCB · 0123456789	2026-07-10 11:39:20.901495+07	2026-07-10 11:39:20.901495+07
8	WB-2026-000014	submission	payment_receipt	minio	2026/07/867080c3-6d50-4979-81e6-fd5c34f54ed6.png	867080c3-6d50-4979-81e6-fd5c34f54ed6.png	image/png	113216	964	staff	Book bank · SCB · 0123456789	2026-07-10 11:40:32.422389+07	2026-07-10 11:40:32.422389+07
\.


--
-- Data for Name: waybill_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.waybill_events (id, waybill_id, sequence, previous_event_id, kind, stage_from, stage_to, actor_id, actor_role, actor_signature, occurred_at, payload) FROM stdin;
4c16991e-0b4e-49eb-b8b4-22304ad9670e	WB-2026-000001	1	\N	created	\N	awaiting_disbursement	\N	\N	\N	2026-07-07 18:44:10.961899+07	{"origin": "expense", "backfill": true, "origin_id": 131}
a8490398-505a-4d7f-8ce1-c809d5db78b1	WB-2026-000002	1	\N	created	\N	dept_authorization	\N	\N	\N	2026-07-06 16:29:43.694048+07	{"origin": "expense", "backfill": true, "origin_id": 130}
1dd293a6-4ebc-4572-8e4d-5417cd77999e	WB-2026-000001	2	4c16991e-0b4e-49eb-b8b4-22304ad9670e	attached	\N	awaiting_disbursement	918	finance	\\xc37cb2fb2e6db089192d655f306062b4e3a1c38e0c10406dfa0cc14cb0644ce8	2026-07-08 10:10:36.197781+07	{"kind": "payment_receipt", "filename": "Sample-receipt.webp", "byte_size": 64386, "attachment_id": "2"}
b7a54a08-cfa1-4f8c-930c-8463721ad343	WB-2026-000001	3	1dd293a6-4ebc-4572-8e4d-5417cd77999e	advanced	awaiting_disbursement	awaiting_disbursement	917	staff	\\x5e59e6790b7a4e8df614ec1093cdbd0254ff237f886b8a5ee2aac0394f977658	2026-07-08 10:13:18.601168+07	{"decision": "approve"}
db917c0e-59fb-46ea-84c1-cd7fcef30d1b	WB-2026-000001	4	b7a54a08-cfa1-4f8c-930c-8463721ad343	advanced	awaiting_disbursement	awaiting_disbursement	917	staff	\\xfe633d868e18a252e8e1525ff6f78fdfabbcb1c8851fa4d567db2f664ac848eb	2026-07-08 10:13:29.864596+07	{"decision": "approve"}
ffae40d7-05cb-4392-ab05-523c869f829a	WB-2026-000001	5	db917c0e-59fb-46ea-84c1-cd7fcef30d1b	advanced	awaiting_disbursement	awaiting_disbursement	915	staff	\\x7d68a92215b7adce4e00709fc9b9cc92951fe4de45e7f787a3f0e2c9194ab83d	2026-07-08 10:13:57.040916+07	{"decision": "approve"}
e0a45561-4f27-49db-babb-5fd3fcc334ef	WB-2026-000001	6	ffae40d7-05cb-4392-ab05-523c869f829a	advanced	awaiting_disbursement	awaiting_disbursement	917	staff	\\x8bcda23716f137d62a8e34676d1b242b5994fda639d0a6266874e8acae127cd6	2026-07-08 10:14:20.359027+07	{"decision": "approve"}
c74cd40a-0a1f-41ab-8dfa-04bae582d41d	WB-2026-000003	1	\N	submitted	\N	dept_verification	964	\N	\\x57e686590039aafd15bde355ac0f26cadb8eab26d5f410974f8bba4f51a2de6c	2026-07-08 16:22:34.379502+07	{"vendor": "บริษัท บีมแอนด์ ดีโกลล์ จำกัด", "vatAmount": 630, "totalAmount": 9630}
6a108ac6-f6c5-4bdf-9d87-6f7efc116abf	WB-2026-000003	2	c74cd40a-0a1f-41ab-8dfa-04bae582d41d	attached	\N	submission	957	supervisor	\\xe89aa86ea78d0ae4c5c249d92356ccbf39d17ef382a128dc5afb664452fdd4c9	2026-07-08 17:10:38.961675+07	{"kind": "slip", "filename": "Screenshot 2569-07-08 at 11.50.41.png", "byte_size": 14009, "attachment_id": "3"}
2fd3dd55-ef24-416d-958c-fa9192ad4044	WB-2026-000003	3	6a108ac6-f6c5-4bdf-9d87-6f7efc116abf	advanced	submission	dept_verification	965	account_officer	\\xb313db9dc0331594a1e6448602ca3ebf7e0d46d8dba3ee1e8911b14356751b36	2026-07-08 17:32:18.047258+07	{"decision": "approve"}
5e3d02b8-5d05-4178-9066-812cded97a3e	WB-2026-000003	4	2fd3dd55-ef24-416d-958c-fa9192ad4044	advanced	submission	dept_verification	965	account_officer	\\xeaccabe9cb77d2d12a049164e476ca737332b7af9afab5e6df150de7af788a9a	2026-07-08 17:41:00.971587+07	{"decision": "approve"}
8eece017-4de4-4b93-a78b-ccf747893630	WB-2026-000003	5	5e3d02b8-5d05-4178-9066-812cded97a3e	advanced	dept_verification	accounting_authorization	955	account_supervisor	\\x095c66495e0a49ad6bd946c2b22cd9eedfb5d5a2ccc0b5806a1bc3f98a2097be	2026-07-08 17:41:32.264045+07	{"decision": "approve"}
c18eb4ec-952e-4076-922f-d7f23823285c	WB-2026-000003	6	8eece017-4de4-4b93-a78b-ccf747893630	advanced	accounting_authorization	awaiting_disbursement	952	accounting_manager	\\xe6fe99bbedc1b6e699184642fc6e27317b8f0a2c16f8ed6e2d96dd16e7445f73	2026-07-08 17:42:06.249586+07	{"decision": "approve"}
4f4a180f-c44a-4c69-9e9d-443039e7100d	WB-2026-000003	7	c18eb4ec-952e-4076-922f-d7f23823285c	settled	awaiting_disbursement	disbursed	952	accounting_manager	\\xfc1d6b6a4c6e7eb8b2c681c9bf340e1bc2910fe7461962fcf04328c87872d6c7	2026-07-08 18:10:52.796114+07	{"slipId": 109, "paymentMethod": "transfer"}
76b66427-2049-4311-9194-0e054bacc59c	WB-2026-000003	8	4f4a180f-c44a-4c69-9e9d-443039e7100d	posted-to-gl	awaiting_disbursement	disbursed	952	accounting_manager	\\xde53ff1de9ae5c7128bc004a3dc10966d4f689564be552fdab501ffe213af1d0	2026-07-08 18:10:52.796+07	{"slipId": 109, "journalId": 2033}
879a355b-cf0e-41c9-b05e-05130582ea62	WB-2026-000003	9	76b66427-2049-4311-9194-0e054bacc59c	gl-confirmed	disbursed	disbursed	966	account_officer	\\xf7b522405a4f7b4a980254b203964b35a4d5a3f4483ce986660d5a6e76b12d01	2026-07-08 18:34:44.067968+07	{"expenseId": 135}
d35339c4-bc45-4d91-b2cc-4e62e0776d98	WB-2026-000004	1	\N	submitted	\N	dept_verification	968	\N	\\x83f4e7f9fca3b39553a6357265d4618b40e9067d77092e09e30db5f3ad8ea744	2026-07-08 19:16:54.0299+07	{"vendor": "บริษัท บิ๊กแมด จำกัด", "vatAmount": 630, "totalAmount": 9630}
502f5c64-8e4d-4bcf-9db3-fe3662421a7a	WB-2026-000005	1	\N	submitted	\N	dept_verification	968	\N	\\x798c5d5179c216bfac7ec6a75e8c81778b07103d2034643a111e5b4c04d00858	2026-07-08 19:25:48.955992+07	{"vendor": "บริษัท ไปร์สแลนด์ ดีโกล จํากัด", "vatAmount": 630, "totalAmount": 9630}
dc451c18-e90f-4ec4-baa4-7b3d3758229e	WB-2026-000005	2	502f5c64-8e4d-4bcf-9db3-fe3662421a7a	attached	\N	submission	968	staff	\\x44b1d035ce602182c8780eafc8965c087c84e985121500813a1765c3a7f7c61c	2026-07-08 19:25:48.959435+07	{"kind": "payment_receipt", "filename": "8352dc15-5b59-4a24-845d-a3885221125e.png", "byte_size": 113216, "attachment_id": "4"}
eb3a1389-9139-41f2-a177-df0577ae46b8	WB-2026-000005	3	dc451c18-e90f-4ec4-baa4-7b3d3758229e	advanced	submission	dept_verification	955	account_supervisor	\\x1c06b8c139ce1e76874119e7438d53d2ff5fb35a3ec21ecae4e347d56bd7a57d	2026-07-08 19:26:29.694654+07	{"decision": "approve"}
384836f2-a2ac-4fe2-9146-84360e3743a5	WB-2026-000005	4	eb3a1389-9139-41f2-a177-df0577ae46b8	advanced	dept_verification	accounting_authorization	955	account_supervisor	\\x020595006071f0d409e14ccd3741e77987a60e6c7c1da02564ce3c44ab70ff76	2026-07-08 19:26:32.488928+07	{"decision": "approve"}
68d18bea-8a6b-4b1c-918a-ff181e7bee60	WB-2026-000005	5	384836f2-a2ac-4fe2-9146-84360e3743a5	advanced	accounting_authorization	awaiting_disbursement	955	account_supervisor	\\x3212f0d77da36f23e85a308f8e46a12a605964069be0217ae8b781c4eb38c332	2026-07-08 19:26:38.310961+07	{"decision": "approve"}
c74050c6-11c6-400f-a336-a737992232a8	WB-2026-000005	6	68d18bea-8a6b-4b1c-918a-ff181e7bee60	settled	awaiting_disbursement	disbursed	955	account_supervisor	\\x9459c842ecb2f4c2aa42d0b2f9741e345f5bf41fec299397ea1d78c242520e86	2026-07-08 19:28:05.920233+07	{"slipId": 116, "paymentMethod": "transfer"}
014e9f27-3f00-43d0-8f62-5f371e437735	WB-2026-000005	7	c74050c6-11c6-400f-a336-a737992232a8	posted-to-gl	awaiting_disbursement	disbursed	955	account_supervisor	\\xe9cac5044bf6e8ebc06d1ef9bfcbfc5058cdfab0a24b987debefc5a1392e3659	2026-07-08 19:28:05.932291+07	{"slipId": 116, "journalId": 2034}
6fcb70ee-3326-4ddb-bad1-77f605d8aaf5	WB-2026-000005	8	014e9f27-3f00-43d0-8f62-5f371e437735	gl-confirmed	disbursed	disbursed	955	account_supervisor	\\x2a9bd05e2bae9bf12e696391c87aff019cda6ac6b599dda5a46ef98917655548	2026-07-08 19:28:11.729281+07	{"expenseId": 137}
87afb282-a8e2-4237-8182-c0f37033d40a	WB-2026-000009	1	\N	created	\N	draft	968	\N	\\x	2026-07-09 12:41:31.007474+07	{"reason": "draft-created"}
39ef5b83-8d09-4d1a-b27e-1930352f41cb	WB-2026-000009	2	87afb282-a8e2-4237-8182-c0f37033d40a	submitted	draft	dept_verification	968	\N	\\x0325d1f0d78999e31c99520c3cb57c912a1b79aa92a6bc5fc56054e84945d093	2026-07-09 12:42:13.788349+07	{"vendor": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "vatAmount": 630, "totalAmount": 9630}
adcf2770-d74c-49a7-b072-d76b71879a10	WB-2026-000009	3	39ef5b83-8d09-4d1a-b27e-1930352f41cb	attached	\N	submission	968	staff	\\x71103d3ddf491d912377a040e20100eda8f4fcc1796abed47aafa2446f4fcdba	2026-07-09 12:42:13.796545+07	{"kind": "payment_receipt", "filename": "74aeef05-f5c1-4b72-8977-12128e1002b1.png", "byte_size": 113216, "attachment_id": "5"}
b9ec4630-9701-4fa7-828e-53885fd8d538	WB-2026-000009	4	adcf2770-d74c-49a7-b072-d76b71879a10	rejected	submission	rejected	946	staff	\\x1e2c129d1227a29831801fdd9a6e7df09c76914782206694ce4a5cf15e6cfe70	2026-07-09 14:54:11.18883+07	{"reason": "I don't like you"}
dd14defd-cbde-4db7-8bb3-0f8bfb3094bc	WB-2026-000004	2	d35339c4-bc45-4d91-b2cc-4e62e0776d98	advanced	submission	dept_verification	952	accounting_manager	\\xba744b0ef014cc5467c579622238fd6a17c870c5e98e22c8ba7290601bea9bbd	2026-07-09 17:33:13.568236+07	{"decision": "approve"}
db25d38b-d2e0-4954-9421-d0bb05282989	WB-2026-000004	3	dd14defd-cbde-4db7-8bb3-0f8bfb3094bc	advanced	dept_verification	accounting_authorization	952	accounting_manager	\\x801def77c167485fe8782cc993e12150fcd427a8945b069de8fbb5555b05eb56	2026-07-09 17:33:20.178832+07	{"decision": "approve"}
ef07fbb3-ed04-461f-a362-d2ee5f7cce65	WB-2026-000004	4	db25d38b-d2e0-4954-9421-d0bb05282989	advanced	accounting_authorization	final_authorization	952	accounting_manager	\\xf09ac6a37ec4da897a388ef90fc3a288920e0bbcb6881e5c0cbc859b831d79ee	2026-07-09 17:33:24.467097+07	{"decision": "approve"}
13ba187c-bf78-4024-96c2-e05d454f7d3a	WB-2026-000004	5	ef07fbb3-ed04-461f-a362-d2ee5f7cce65	advanced	final_authorization	awaiting_disbursement	952	accounting_manager	\\x81d2fa33ab24e416f1455916762699c490cd7bbef1bd235ba45d5d2180939e42	2026-07-09 17:35:01.355286+07	{"decision": "final-approve", "gl_will_post": true}
26197875-5c50-42ca-80a0-0e69898c9c66	WB-2026-000004	6	13ba187c-bf78-4024-96c2-e05d454f7d3a	posted-to-gl	final_authorization	awaiting_disbursement	952	accounting_manager	\\xd7f0cdf3a7a484ad3220b7df8acff2c40087622ce448b4d0616132378ce62fc4	2026-07-09 17:35:01.369536+07	{"expenseId": 136, "journalId": 2037}
eb453f88-9dc9-41c2-ac86-ae15c16bf38f	WB-2026-000004	7	26197875-5c50-42ca-80a0-0e69898c9c66	settled	awaiting_disbursement	disbursed	952	accounting_manager	\\xea503b713aa914b8f169239281a9e268a71921757d0b829f87533fbb2f921c3e	2026-07-09 17:36:18.683273+07	{"slipId": 149, "paymentMethod": "transfer"}
0203593e-afa3-48b1-a9b2-cf6405b286b5	WB-2026-000004	8	eb453f88-9dc9-41c2-ac86-ae15c16bf38f	posted-to-gl	awaiting_disbursement	disbursed	952	accounting_manager	\\x17332f9a46d756fb56c54fd2bc5797ef9615249696109854b7513eab140be7f1	2026-07-09 17:36:18.694832+07	{"slipId": 149, "journalId": 2038, "posted_by": "attachPaymentSlipAction"}
4f2feb8c-b278-404a-a431-223831135bf1	WB-2026-000011	1	\N	created	\N	draft	962	\N	\\x	2026-07-09 17:44:52.4981+07	{"reason": "draft-created"}
b958b709-545f-439b-b7f0-57dab2c8c5ee	WB-2026-000011	2	4f2feb8c-b278-404a-a431-223831135bf1	submitted	draft	dept_verification	962	\N	\\x226a9cee12e38a67d99aab7283a0159dd2fd9fb6118eeb6adcce8747757fee31	2026-07-09 17:49:16.157689+07	{"vendor": "บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด", "vatAmount": 630, "totalAmount": 9630}
49ac069c-2869-4f8a-aae2-56afd7bb13c6	WB-2026-000011	3	b958b709-545f-439b-b7f0-57dab2c8c5ee	attached	\N	submission	962	staff	\\x424cf3354c19cf0e83ab7d45482987922f71dea73f4f8fb3d4e035ea4a48ae00	2026-07-09 17:49:16.163358+07	{"kind": "payment_receipt", "filename": "64e50107-99c7-49c6-b47e-00d16d4b47d7.png", "byte_size": 113216, "attachment_id": "6"}
ffa62744-20c4-4991-b0cf-5a86b3085a4f	WB-2026-000012	1	\N	created	\N	draft	964	\N	\\x	2026-07-09 19:29:16.63622+07	{"reason": "draft-created"}
f6b36b3e-7bfb-453f-964c-3280a355b2ff	WB-2026-000012	2	ffa62744-20c4-4991-b0cf-5a86b3085a4f	submitted	draft	dept_verification	964	\N	\\x7f189af1696d2f622eb99b8dd04376243e0c18cc332f6691244afc80fbefbeb5	2026-07-09 19:29:32.292645+07	{"vendor": "บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด", "vatAmount": 630, "totalAmount": 9630}
04804098-4942-40d4-bfe2-7d99cb7d1d4b	WB-2026-000012	3	f6b36b3e-7bfb-453f-964c-3280a355b2ff	advanced	dept_verification	dept_authorization	951	manager	\\xc34a055c3c7f84084edbb63478681e2f25e8a85633ab49cd1108ad50f2d2c476	2026-07-09 22:21:31.480053+07	{"decision": "approve"}
d5c53771-e834-4ee3-ace3-ef690ad1b48a	WB-2026-000012	4	04804098-4942-40d4-bfe2-7d99cb7d1d4b	advanced	accounting_authorization	awaiting_disbursement	952	accounting_manager	\\x85e217b6bd124d516da9e64c7aa765cd5d30024ad44d423218cf24cbe29a2c59	2026-07-09 22:36:01.653558+07	{"decision": "approve"}
bf2a02f5-1f6e-4d5b-b640-dbe3009132c9	WB-2026-000012	5	d5c53771-e834-4ee3-ace3-ef690ad1b48a	settled	awaiting_disbursement	disbursed	946	finance	\\xe2551ea9752f79d2a8fc2e7233eaf2734b8d9ca303325e4c9a40dcd7f676b95a	2026-07-09 22:37:37.620574+07	{"slipId": 157, "paymentMethod": "transfer"}
2272941d-19a4-4d70-b745-1c3fd41323be	WB-2026-000012	6	bf2a02f5-1f6e-4d5b-b640-dbe3009132c9	posted-to-gl	awaiting_disbursement	disbursed	946	finance	\\xb4e7492326e12869a80d2a49e338472ffb4c1b6b09c22781738ad4911c982f2d	2026-07-09 22:37:37.634966+07	{"slipId": 157, "journalId": 2039, "posted_by": "attachPaymentSlipAction"}
01483caa-ddb4-4b98-9d83-7b718d20b408	WB-2026-000012	7	2272941d-19a4-4d70-b745-1c3fd41323be	gl-confirmed	disbursed	disbursed	946	finance	\\x7a2c7c549570ce5afc48a8ea214bb2f4028c8285c260b32fd2fac00629fa31eb	2026-07-09 22:37:49.373617+07	{"expenseId": 148}
cdd0a3cd-9502-42ed-891a-185ff56f3b56	WB-2026-000002	2	a8490398-505a-4d7f-8ce1-c809d5db78b1	advanced	accounting_authorization	awaiting_disbursement	952	accounting_manager	\\xd2c764b24e98fe931fc5dad38b7cb00e005e01499ac08862fa0a65fd961c2973	2026-07-09 23:07:09.80797+07	{"decision": "approve"}
ae0b5717-828e-4765-9db6-f79046ede28b	WB-2026-000002	3	cdd0a3cd-9502-42ed-891a-185ff56f3b56	settled	awaiting_disbursement	disbursed	946	finance	\\xad826f17dfb16dfdbbceadf72be2a3d39bdda727c60c60dab1355d8f61747000	2026-07-09 23:23:35.819059+07	{"slipId": 159, "paymentMethod": "transfer"}
cce604d5-0c8e-42b4-ba03-837519fd366e	WB-2026-000002	4	ae0b5717-828e-4765-9db6-f79046ede28b	posted-to-gl	awaiting_disbursement	disbursed	946	finance	\\x35b73f1855d5d236f4bde59f72af5d8a4c3f49d5f58d45ca20971d419cdd77a5	2026-07-09 23:23:35.830522+07	{"slipId": 159, "journalId": 2040, "posted_by": "attachPaymentSlipAction"}
e167b803-c7d1-4ffb-8f95-33174b0b5c50	WB-2026-000002	5	cce604d5-0c8e-42b4-ba03-837519fd366e	gl-confirmed	disbursed	disbursed	946	finance	\\x4c54589f8b798cbb0d5a5ae12097ac2c66bf1248e5f8b960b38dbd12bac26a8f	2026-07-09 23:23:45.006761+07	{"expenseId": 130}
7b2bcc5f-0413-4a84-b86e-3cc8f91bbaf4	WB-2026-000013	1	\N	created	\N	draft	951	\N	\\x	2026-07-10 11:38:50.665911+07	{"reason": "draft-created"}
764a7547-61f1-43ed-9540-af05b2eed407	WB-2026-000013	2	7b2bcc5f-0413-4a84-b86e-3cc8f91bbaf4	submitted	draft	dept_verification	951	\N	\\xdb5d374b9c572db3a9f525cfdd78889a94a2440478f8fdb08382c7f64218b8e9	2026-07-10 11:39:20.898712+07	{"vendor": "บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด", "vatAmount": 630, "totalAmount": 9630}
ec6e983b-286c-4be5-a117-5f690d472135	WB-2026-000013	3	764a7547-61f1-43ed-9540-af05b2eed407	attached	\N	submission	951	staff	\\x781618cad4efcc59ff9b9b05dd2f34065ce3a987a233a94a3d1aa9d07f93a8cd	2026-07-10 11:39:20.902775+07	{"kind": "payment_receipt", "filename": "e9864862-4565-4c84-a1a0-e382216ea9bd.png", "byte_size": 113216, "attachment_id": "7"}
0070158d-75d5-49f6-9bf6-c461a2d35498	WB-2026-000014	1	\N	created	\N	draft	964	\N	\\x	2026-07-10 11:40:08.304331+07	{"reason": "draft-created"}
7ed7e24b-e42c-49ed-a7b6-cef0dcfa0895	WB-2026-000014	2	0070158d-75d5-49f6-9bf6-c461a2d35498	submitted	draft	dept_verification	964	\N	\\x206e6d8bb629413b859fe94cbe370d2295234f21db23332c2792393ced63638a	2026-07-10 11:40:32.418517+07	{"vendor": "บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด", "vatAmount": 630, "totalAmount": 9630}
b475f2b6-ac59-4ca0-919f-ca8d7ecde7c8	WB-2026-000014	3	7ed7e24b-e42c-49ed-a7b6-cef0dcfa0895	attached	\N	submission	964	staff	\\xdf854a7685ed93f514e1682e91ecf905bc89b2c30d13e9f1e9671d4e17e7c8f2	2026-07-10 11:40:32.423741+07	{"kind": "payment_receipt", "filename": "867080c3-6d50-4979-81e6-fd5c34f54ed6.png", "byte_size": 113216, "attachment_id": "8"}
3aa5a750-18ef-4b1e-86a0-ed7296a58d8f	WB-2026-000015	1	\N	created	\N	draft	959	\N	\\x	2026-07-10 12:30:47.031472+07	{"reason": "draft-created"}
e233e3fd-4d0b-489c-a4cd-31e90626e198	WB-2026-000015	2	3aa5a750-18ef-4b1e-86a0-ed7296a58d8f	submitted	draft	dept_verification	959	\N	\\xd3ebd4057c9e2e00b5428dfdd8d95b8b0c4db2faf03f48e7f48e00b2f919f926	2026-07-10 12:30:53.042849+07	{"vendor": "บริษัท เนสซ์ เล่ห์ จำกัด", "vatAmount": 630, "totalAmount": 9630}
e8200d43-f8f1-4010-8565-705671206b56	WB-2026-000016	1	\N	created	\N	draft	957	\N	\\x	2026-07-12 17:32:33.297557+07	{"reason": "draft-created"}
1534a577-5ad3-4ed3-9d74-d3000f2cdb34	WB-2026-000017	1	\N	created	\N	draft	952	\N	\\x	2026-07-13 11:02:42.136154+07	{"reason": "draft-created"}
\.


--
-- Data for Name: waybill_watchers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.waybill_watchers (id, waybill_id, stage_key, user_id, notified_at, created_at) FROM stdin;
1	WB-2026-000001	dept_verification	946	\N	2026-07-09 16:57:50.808314
\.


--
-- Data for Name: waybills; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.waybills (id, origin, origin_id, fiscal_year, waybill_kind, submitter_id, vendor_name, total_amount, currency, current_stage, current_owner_role, current_owner_user_id, status, created_at, updated_at, created_to, vendor_address, created_to_address) FROM stdin;
WB-2026-000012	expense	148	2026	reimbursement	964	บริษัท ใบรักมิลลี่ ดิจิทอล จำกัด	9630.00	THB	disbursed	awaiting_disbursement	\N	completed	2026-07-09 19:29:16.635318+07	2026-07-09 22:37:37.620574+07	\N	\N	\N
WB-2026-000002	expense	130	2026	reimbursement	934	ESDES	12500.00	cash	disbursed	awaiting_disbursement	\N	completed	2026-07-06 16:29:43.694048+07	2026-07-09 23:23:35.819059+07	\N	\N	\N
WB-2026-000001	expense	131	2026	reimbursement	933	บริษัท นิติบุญ ตีนจง จำกัด	9630.00	cash	awaiting_disbursement	finance	\N	open	2026-07-07 18:44:10.961899+07	2026-07-08 10:14:20.359027+07	\N	\N	\N
WB-2026-000003	expense	135	2026	reimbursement	\N	\N	\N	THB	disbursed	finance	\N	completed	2026-07-08 16:22:34.374974+07	2026-07-08 18:10:52.796114+07	\N	\N	\N
WB-2026-000005	expense	137	2026	reimbursement	\N	\N	\N	THB	disbursed	finance	\N	completed	2026-07-08 19:25:48.954234+07	2026-07-08 19:28:05.920233+07	\N	\N	\N
WB-2026-000009	expense	145	2026	reimbursement	968	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	9630.00	THB	rejected	\N	\N	rejected	2026-07-09 12:41:31.006253+07	2026-07-09 14:54:11.18883+07	\N	\N	\N
WB-2026-000004	expense	136	2026	reimbursement	\N	\N	\N	THB	disbursed	finance	\N	completed	2026-07-08 19:16:54.026504+07	2026-07-09 17:36:18.683273+07	\N	\N	\N
WB-2026-000011	expense	147	2026	reimbursement	962	บริษัท บีเอムดีวิท แอนด์ ดีจีล่า จำกัด	9630.00	THB	dept_verification	\N	\N	open	2026-07-09 17:44:52.496744+07	2026-07-09 18:12:44.233903+07	\N	\N	\N
WB-2026-000013	expense	149	2026	reimbursement	951	บริษัท บีมเอเจนซี่ แอนด์ ดิจิทอล จำกัด	9630.00	THB	dept_verification	\N	\N	open	2026-07-10 11:38:50.665469+07	2026-07-10 11:39:19.15769+07	\N	\N	\N
WB-2026-000014	expense	150	2026	reimbursement	964	บริษัท บีมเออเบนซ์ แอนด์ ดิจิทอล จำกัด	9630.00	THB	dept_verification	\N	\N	open	2026-07-10 11:40:08.288654+07	2026-07-10 11:40:32.085598+07	\N	\N	\N
WB-2026-000015	expense	151	2026	reimbursement	959	บริษัท เนสซ์ เล่ห์ จำกัด	9630.00	THB	dept_verification	\N	\N	open	2026-07-10 12:30:47.030658+07	2026-07-10 12:30:51.864669+07	\N	\N	\N
WB-2026-000016	expense	152	2026	reimbursement	957	\N	\N	THB	draft	\N	\N	open	2026-07-12 17:32:33.29585+07	2026-07-12 17:32:33.29585+07	\N	\N	\N
WB-2026-000017	expense	153	2026	reimbursement	952	\N	\N	THB	draft	\N	\N	open	2026-07-13 11:02:42.134373+07	2026-07-13 11:02:42.134373+07	\N	\N	\N
\.


--
-- Name: audit_id_seq; Type: SEQUENCE SET; Schema: perm; Owner: -
--

SELECT pg_catalog.setval('perm.audit_id_seq', 1, false);


--
-- Name: policy_decisions_id_seq; Type: SEQUENCE SET; Schema: perm; Owner: -
--

SELECT pg_catalog.setval('perm.policy_decisions_id_seq', 1, false);


--
-- Name: user_permissions_id_seq; Type: SEQUENCE SET; Schema: perm; Owner: -
--

SELECT pg_catalog.setval('perm.user_permissions_id_seq', 26, true);


--
-- Name: access_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.access_requests_id_seq', 2, true);


--
-- Name: ai_assignments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ai_assignments_id_seq', 150, true);


--
-- Name: ai_invocations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ai_invocations_id_seq', 319, true);


--
-- Name: ai_models_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ai_models_id_seq', 1451, true);


--
-- Name: ai_providers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ai_providers_id_seq', 29, true);


--
-- Name: ai_staff_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ai_staff_id_seq', 28, true);


--
-- Name: approval_override_audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.approval_override_audit_id_seq', 9, true);


--
-- Name: approval_transitions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.approval_transitions_id_seq', 108, true);


--
-- Name: customer_contacts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customer_contacts_id_seq', 1, false);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customers_id_seq', 2, true);


--
-- Name: domain_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.domain_events_id_seq', 53, true);


--
-- Name: exec_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exec_snapshots_id_seq', 9, true);


--
-- Name: expense_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.expense_items_id_seq', 1094, true);


--
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.expenses_id_seq', 155, true);


--
-- Name: hook_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.hook_events_id_seq', 7, true);


--
-- Name: journal_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.journal_entries_id_seq', 2046, true);


--
-- Name: ledger_lines_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ledger_lines_id_seq', 88, true);


--
-- Name: notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notifications_id_seq', 70, true);


--
-- Name: po_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.po_items_id_seq', 1, true);


--
-- Name: policy_audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.policy_audit_id_seq', 1, false);


--
-- Name: pr_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pr_items_id_seq', 1, false);


--
-- Name: purchase_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purchase_orders_id_seq', 12, true);


--
-- Name: purchase_requisitions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purchase_requisitions_id_seq', 18, true);


--
-- Name: sales_orders_fy_2026_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sales_orders_fy_2026_seq', 1, true);


--
-- Name: sales_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sales_orders_id_seq', 1, true);


--
-- Name: slips_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.slips_id_seq', 177, true);


--
-- Name: so_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.so_items_id_seq', 2, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_id_seq', 968, true);


--
-- Name: waybill_attachments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.waybill_attachments_id_seq', 8, true);


--
-- Name: waybill_watchers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.waybill_watchers_id_seq', 1, true);


--
-- Name: waybills_fy_2026_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.waybills_fy_2026_seq', 18, true);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: audit audit_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.audit
    ADD CONSTRAINT audit_pkey PRIMARY KEY (id);


--
-- Name: user_permissions perm_user_permissions_one_alive; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_permissions
    ADD CONSTRAINT perm_user_permissions_one_alive EXCLUDE USING btree (user_id WITH =, permission_id WITH =) WHERE ((revoked_at IS NULL)) DEFERRABLE;


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: policies policies_name_key; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.policies
    ADD CONSTRAINT policies_name_key UNIQUE (name);


--
-- Name: policies policies_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.policies
    ADD CONSTRAINT policies_pkey PRIMARY KEY (id);


--
-- Name: policy_decisions policy_decisions_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.policy_decisions
    ADD CONSTRAINT policy_decisions_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: tiles tiles_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.tiles
    ADD CONSTRAINT tiles_pkey PRIMARY KEY (id);


--
-- Name: user_permissions user_permissions_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_permissions
    ADD CONSTRAINT user_permissions_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


--
-- Name: access_requests access_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_requests
    ADD CONSTRAINT access_requests_pkey PRIMARY KEY (id);


--
-- Name: ai_assignments ai_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_assignments
    ADD CONSTRAINT ai_assignments_pkey PRIMARY KEY (id);


--
-- Name: ai_assignments ai_assignments_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_assignments
    ADD CONSTRAINT ai_assignments_unique UNIQUE (section_key, task_type, priority);


--
-- Name: ai_invocations ai_invocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_invocations
    ADD CONSTRAINT ai_invocations_pkey PRIMARY KEY (id);


--
-- Name: ai_models ai_models_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_models
    ADD CONSTRAINT ai_models_pkey PRIMARY KEY (id);


--
-- Name: ai_models ai_models_provider_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_models
    ADD CONSTRAINT ai_models_provider_id_name_key UNIQUE (provider_id, name);


--
-- Name: ai_providers ai_providers_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_providers
    ADD CONSTRAINT ai_providers_name_key UNIQUE (name);


--
-- Name: ai_providers ai_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_providers
    ADD CONSTRAINT ai_providers_pkey PRIMARY KEY (id);


--
-- Name: ai_staff ai_staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_staff
    ADD CONSTRAINT ai_staff_pkey PRIMARY KEY (id);


--
-- Name: approval_override_audit approval_override_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_override_audit
    ADD CONSTRAINT approval_override_audit_pkey PRIMARY KEY (id);


--
-- Name: approval_transitions approval_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_transitions
    ADD CONSTRAINT approval_transitions_pkey PRIMARY KEY (id);


--
-- Name: chart_of_accounts chart_of_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_of_accounts
    ADD CONSTRAINT chart_of_accounts_pkey PRIMARY KEY (code);


--
-- Name: customer_contacts customer_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT customer_contacts_pkey PRIMARY KEY (id);


--
-- Name: customers customers_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_code_key UNIQUE (code);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: domain_events domain_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_events
    ADD CONSTRAINT domain_events_pkey PRIMARY KEY (id);


--
-- Name: exec_snapshots exec_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exec_snapshots
    ADD CONSTRAINT exec_snapshots_pkey PRIMARY KEY (id);


--
-- Name: exec_snapshots exec_snapshots_snapshot_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exec_snapshots
    ADD CONSTRAINT exec_snapshots_snapshot_date_key UNIQUE (snapshot_date);


--
-- Name: expense_items expense_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_items
    ADD CONSTRAINT expense_items_pkey PRIMARY KEY (id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: hook_events hook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hook_events
    ADD CONSTRAINT hook_events_pkey PRIMARY KEY (id);


--
-- Name: hook_events hook_events_provider_id_external_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hook_events
    ADD CONSTRAINT hook_events_provider_id_external_id_key UNIQUE (provider_id, external_id);


--
-- Name: hook_providers hook_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hook_providers
    ADD CONSTRAINT hook_providers_pkey PRIMARY KEY (id);


--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);


--
-- Name: ledger_lines ledger_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT ledger_lines_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: po_items po_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.po_items
    ADD CONSTRAINT po_items_pkey PRIMARY KEY (id);


--
-- Name: policy_audit policy_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_audit
    ADD CONSTRAINT policy_audit_pkey PRIMARY KEY (id);


--
-- Name: pr_items pr_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pr_items
    ADD CONSTRAINT pr_items_pkey PRIMARY KEY (id);


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- Name: purchase_orders purchase_orders_po_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_po_number_key UNIQUE (po_number);


--
-- Name: purchase_requisitions purchase_requisitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_requisitions
    ADD CONSTRAINT purchase_requisitions_pkey PRIMARY KEY (id);


--
-- Name: sales_orders sales_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_pkey PRIMARY KEY (id);


--
-- Name: sales_orders sales_orders_so_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_so_number_key UNIQUE (so_number);


--
-- Name: slips slips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips
    ADD CONSTRAINT slips_pkey PRIMARY KEY (id);


--
-- Name: so_items so_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.so_items
    ADD CONSTRAINT so_items_pkey PRIMARY KEY (id);


--
-- Name: users users_employee_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_employee_code_key UNIQUE (employee_code);


--
-- Name: users users_line_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_line_user_id_key UNIQUE (line_user_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: waybill_attachments waybill_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_attachments
    ADD CONSTRAINT waybill_attachments_pkey PRIMARY KEY (id);


--
-- Name: waybill_events waybill_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_events
    ADD CONSTRAINT waybill_events_pkey PRIMARY KEY (id);


--
-- Name: waybill_watchers waybill_watchers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_watchers
    ADD CONSTRAINT waybill_watchers_pkey PRIMARY KEY (id);


--
-- Name: waybill_watchers waybill_watchers_waybill_id_stage_key_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_watchers
    ADD CONSTRAINT waybill_watchers_waybill_id_stage_key_user_id_key UNIQUE (waybill_id, stage_key, user_id);


--
-- Name: waybills waybills_origin_origin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybills
    ADD CONSTRAINT waybills_origin_origin_id_key UNIQUE (origin, origin_id);


--
-- Name: waybills waybills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybills
    ADD CONSTRAINT waybills_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions_active_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX auth_sessions_active_idx ON auth.sessions USING btree (expires_at) WHERE (revoked_at IS NULL);


--
-- Name: auth_sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX auth_sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: perm_perm_domain_idx; Type: INDEX; Schema: perm; Owner: -
--

CREATE INDEX perm_perm_domain_idx ON perm.permissions USING btree (split_part(id, ':'::text, 1));


--
-- Name: perm_roles_parent_idx; Type: INDEX; Schema: perm; Owner: -
--

CREATE INDEX perm_roles_parent_idx ON perm.roles USING btree (parent_role_id) WHERE (parent_role_id IS NOT NULL);


--
-- Name: perm_tiles_group_idx; Type: INDEX; Schema: perm; Owner: -
--

CREATE INDEX perm_tiles_group_idx ON perm.tiles USING btree (group_name, sort_order);


--
-- Name: perm_up_active_idx; Type: INDEX; Schema: perm; Owner: -
--

CREATE INDEX perm_up_active_idx ON perm.user_permissions USING btree (user_id) WHERE (revoked_at IS NULL);


--
-- Name: perm_up_perm_idx; Type: INDEX; Schema: perm; Owner: -
--

CREATE INDEX perm_up_perm_idx ON perm.user_permissions USING btree (permission_id) WHERE (revoked_at IS NULL);


--
-- Name: access_requests_pending_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX access_requests_pending_uniq ON public.access_requests USING btree (actor_id, tile_id) WHERE (status = 'pending'::text);


--
-- Name: access_requests_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX access_requests_status_idx ON public.access_requests USING btree (status, created_at DESC);


--
-- Name: access_requests_target_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX access_requests_target_idx ON public.access_requests USING btree (target_user_id) WHERE (status = 'pending'::text);


--
-- Name: customer_contacts_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_contacts_customer_idx ON public.customer_contacts USING btree (customer_id);


--
-- Name: customers_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customers_active_idx ON public.customers USING btree (is_active) WHERE is_active;


--
-- Name: customers_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customers_name_idx ON public.customers USING btree (name);


--
-- Name: exec_snapshots_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX exec_snapshots_date_idx ON public.exec_snapshots USING btree (snapshot_date DESC);


--
-- Name: hook_events_provider_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hook_events_provider_idx ON public.hook_events USING btree (provider_id);


--
-- Name: hook_events_received_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hook_events_received_idx ON public.hook_events USING btree (received_at DESC);


--
-- Name: hook_events_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hook_events_status_idx ON public.hook_events USING btree (status);


--
-- Name: idx_ai_assignments_section; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_assignments_section ON public.ai_assignments USING btree (section_key, task_type, priority);


--
-- Name: idx_ai_invocations_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_invocations_created ON public.ai_invocations USING btree (created_at DESC);


--
-- Name: idx_ai_invocations_section; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_invocations_section ON public.ai_invocations USING btree (section_key, created_at DESC);


--
-- Name: idx_ai_invocations_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_invocations_staff ON public.ai_invocations USING btree (staff_id, created_at DESC);


--
-- Name: idx_ai_models_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_models_provider ON public.ai_models USING btree (provider_id);


--
-- Name: idx_aov_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aov_actor ON public.approval_override_audit USING btree (actor_id);


--
-- Name: idx_aov_kind_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aov_kind_stage ON public.approval_override_audit USING btree (kind, attempted_stage);


--
-- Name: idx_aov_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aov_target ON public.approval_override_audit USING btree (target_type, target_id);


--
-- Name: idx_atx_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atx_actor ON public.approval_transitions USING btree (actor_id);


--
-- Name: idx_atx_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atx_stage ON public.approval_transitions USING btree (stage) WHERE (stage IS NOT NULL);


--
-- Name: idx_atx_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atx_target ON public.approval_transitions USING btree (target_type, target_id, created_at DESC);


--
-- Name: idx_domain_events_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domain_events_actor ON public.domain_events USING btree (actor_id);


--
-- Name: idx_domain_events_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domain_events_created_at ON public.domain_events USING btree (created_at DESC);


--
-- Name: idx_domain_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domain_events_type ON public.domain_events USING btree (type);


--
-- Name: idx_expenses_jv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expenses_jv ON public.expenses USING btree (journal_entry_id);


--
-- Name: idx_expenses_po; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expenses_po ON public.expenses USING btree (po_id);


--
-- Name: idx_expenses_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expenses_pr ON public.expenses USING btree (pr_id);


--
-- Name: idx_expenses_rejected; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expenses_rejected ON public.expenses USING btree (rejected_at) WHERE ((status)::text = 'rejected'::text);


--
-- Name: idx_journal_entries_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_active ON public.journal_entries USING btree (expense_id) WHERE (is_draft = false);


--
-- Name: idx_journal_entries_expense_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_expense_id ON public.journal_entries USING btree (expense_id);


--
-- Name: idx_journal_entries_one_draft_per_expense; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_journal_entries_one_draft_per_expense ON public.journal_entries USING btree (expense_id, step) WHERE ((is_draft = true) AND (expense_id IS NOT NULL));


--
-- Name: idx_journal_entries_one_draft_per_po; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_journal_entries_one_draft_per_po ON public.journal_entries USING btree (po_id, step) WHERE ((is_draft = true) AND (po_id IS NOT NULL));


--
-- Name: idx_journal_entries_one_draft_per_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_journal_entries_one_draft_per_pr ON public.journal_entries USING btree (pr_id, step) WHERE ((is_draft = true) AND (pr_id IS NOT NULL));


--
-- Name: idx_journal_entries_one_draft_per_so; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_one_draft_per_so ON public.journal_entries USING btree (so_id, step) WHERE ((is_draft = true) AND (so_id IS NOT NULL));


--
-- Name: idx_journal_entries_po; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_po ON public.journal_entries USING btree (po_id);


--
-- Name: idx_journal_entries_po_step; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_po_step ON public.journal_entries USING btree (po_id, step);


--
-- Name: idx_journal_entries_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_pr ON public.journal_entries USING btree (pr_id);


--
-- Name: idx_journal_entries_pr_step; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_pr_step ON public.journal_entries USING btree (pr_id, step);


--
-- Name: idx_journal_entries_so_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_so_id ON public.journal_entries USING btree (so_id);


--
-- Name: idx_ledger_lines_account_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_lines_account_code ON public.ledger_lines USING btree (account_code);


--
-- Name: idx_ledger_lines_journal_entry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_lines_journal_entry ON public.ledger_lines USING btree (journal_entry_id);


--
-- Name: idx_notif_user_cleared; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notif_user_cleared ON public.notifications USING btree (user_id, cleared_at) WHERE (cleared_at IS NULL);


--
-- Name: idx_notif_user_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notif_user_unread ON public.notifications USING btree (user_id, read_at);


--
-- Name: idx_po_items_po; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_po_items_po ON public.po_items USING btree (po_id);


--
-- Name: idx_po_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_po_pr ON public.purchase_orders USING btree (pr_id);


--
-- Name: idx_po_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_po_status ON public.purchase_orders USING btree (status);


--
-- Name: idx_pr_dept_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pr_dept_group ON public.purchase_requisitions USING btree (dept_group_id);


--
-- Name: idx_pr_pr_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pr_pr_number ON public.purchase_requisitions USING btree (pr_number);


--
-- Name: idx_pr_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pr_status ON public.purchase_requisitions USING btree (status);


--
-- Name: idx_prs_rejected; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prs_rejected ON public.purchase_requisitions USING btree (rejected_at) WHERE ((status)::text = 'rejected'::text);


--
-- Name: idx_slips_expense; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slips_expense ON public.slips USING btree (expense_id);


--
-- Name: idx_slips_kind_expense; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slips_kind_expense ON public.slips USING btree (kind, expense_id) WHERE (expense_id IS NOT NULL);


--
-- Name: idx_slips_po; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slips_po ON public.slips USING btree (po_id);


--
-- Name: idx_slips_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slips_pr ON public.slips USING btree (pr_id);


--
-- Name: idx_slips_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slips_status ON public.slips USING btree (status);


--
-- Name: idx_slips_uploader_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_slips_uploader_status ON public.slips USING btree (uploaded_by, status);


--
-- Name: idx_users_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_active ON public.users USING btree (is_active) WHERE is_active;


--
-- Name: idx_users_hired_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_hired_at ON public.users USING btree (hired_at);


--
-- Name: idx_watchers_user_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_watchers_user_unread ON public.waybill_watchers USING btree (user_id) WHERE (notified_at IS NULL);


--
-- Name: idx_watchers_waybill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_watchers_waybill ON public.waybill_watchers USING btree (waybill_id);


--
-- Name: idx_waybill_attachments_wb_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybill_attachments_wb_created ON public.waybill_attachments USING btree (waybill_id, occurred_at DESC);


--
-- Name: idx_waybill_attachments_wb_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybill_attachments_wb_kind ON public.waybill_attachments USING btree (waybill_id, kind);


--
-- Name: idx_waybill_attachments_wb_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybill_attachments_wb_stage ON public.waybill_attachments USING btree (waybill_id, stage_key);


--
-- Name: idx_waybills_fy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybills_fy ON public.waybills USING btree (fiscal_year);


--
-- Name: idx_waybills_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybills_origin ON public.waybills USING btree (origin, origin_id);


--
-- Name: idx_waybills_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybills_owner ON public.waybills USING btree (current_owner_user_id);


--
-- Name: idx_waybills_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybills_stage ON public.waybills USING btree (current_stage);


--
-- Name: idx_waybills_submitter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_waybills_submitter ON public.waybills USING btree (submitter_id);


--
-- Name: idx_wbx_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wbx_actor ON public.waybill_events USING btree (actor_id);


--
-- Name: idx_wbx_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wbx_kind ON public.waybill_events USING btree (kind);


--
-- Name: idx_wbx_previous; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wbx_previous ON public.waybill_events USING btree (previous_event_id);


--
-- Name: idx_wbx_waybill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wbx_waybill ON public.waybill_events USING btree (waybill_id, sequence);


--
-- Name: sales_orders_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_orders_customer_idx ON public.sales_orders USING btree (customer_id);


--
-- Name: sales_orders_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_orders_due_idx ON public.sales_orders USING btree (due_date) WHERE (status <> ALL (ARRAY['so_paid'::text, 'rejected'::text]));


--
-- Name: sales_orders_rep_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_orders_rep_idx ON public.sales_orders USING btree (sales_rep_id);


--
-- Name: sales_orders_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_orders_status_idx ON public.sales_orders USING btree (status);


--
-- Name: so_items_so_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX so_items_so_idx ON public.so_items USING btree (sales_order_id);


--
-- Name: tiles perm_tiles_touch; Type: TRIGGER; Schema: perm; Owner: -
--

CREATE TRIGGER perm_tiles_touch BEFORE UPDATE ON perm.tiles FOR EACH ROW EXECUTE FUNCTION perm.touch_updated_at();


--
-- Name: slips slips_exactly_one_parent_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER slips_exactly_one_parent_trg AFTER INSERT OR UPDATE ON public.slips DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.slips_check_exactly_one_parent();


--
-- Name: TRIGGER slips_exactly_one_parent_trg ON slips; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER slips_exactly_one_parent_trg ON public.slips IS 'Enforces exactly-one of (expense_id, pr_id, po_id). DEFERRABLE so orphan-then-link patterns within a single transaction still commit successfully; permanent orphans (slips committed with zero parents, or with multiple parents) are rejected.';


--
-- Name: domain_events trg_domain_events_fanout; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_domain_events_fanout AFTER INSERT ON public.domain_events FOR EACH ROW EXECUTE FUNCTION public.domain_events_fanout_notifications();


--
-- Name: sessions sessions_impersonator_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_impersonator_user_id_fkey FOREIGN KEY (impersonator_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES perm.permissions(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES perm.roles(id) ON DELETE CASCADE;


--
-- Name: roles roles_head_user_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.roles
    ADD CONSTRAINT roles_head_user_id_fkey FOREIGN KEY (head_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: roles roles_parent_role_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.roles
    ADD CONSTRAINT roles_parent_role_id_fkey FOREIGN KEY (parent_role_id) REFERENCES perm.roles(id) ON DELETE RESTRICT;


--
-- Name: user_permissions user_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_permissions
    ADD CONSTRAINT user_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES perm.permissions(id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_user_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_permissions
    ADD CONSTRAINT user_permissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES perm.roles(id) ON DELETE RESTRICT;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: perm; Owner: -
--

ALTER TABLE ONLY perm.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: access_requests access_requests_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_requests
    ADD CONSTRAINT access_requests_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: access_requests access_requests_resolved_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_requests
    ADD CONSTRAINT access_requests_resolved_by_user_id_fkey FOREIGN KEY (resolved_by_user_id) REFERENCES public.users(id);


--
-- Name: access_requests access_requests_target_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_requests
    ADD CONSTRAINT access_requests_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES public.users(id);


--
-- Name: ai_assignments ai_assignments_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_assignments
    ADD CONSTRAINT ai_assignments_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.ai_models(id) ON DELETE SET NULL;


--
-- Name: ai_assignments ai_assignments_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_assignments
    ADD CONSTRAINT ai_assignments_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.ai_providers(id) ON DELETE SET NULL;


--
-- Name: ai_assignments ai_assignments_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_assignments
    ADD CONSTRAINT ai_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.ai_staff(id) ON DELETE SET NULL;


--
-- Name: ai_invocations ai_invocations_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_invocations
    ADD CONSTRAINT ai_invocations_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ai_invocations ai_invocations_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_invocations
    ADD CONSTRAINT ai_invocations_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.ai_models(id) ON DELETE SET NULL;


--
-- Name: ai_invocations ai_invocations_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_invocations
    ADD CONSTRAINT ai_invocations_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.ai_providers(id) ON DELETE SET NULL;


--
-- Name: ai_invocations ai_invocations_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_invocations
    ADD CONSTRAINT ai_invocations_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.ai_staff(id) ON DELETE SET NULL;


--
-- Name: ai_models ai_models_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_models
    ADD CONSTRAINT ai_models_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.ai_providers(id) ON DELETE CASCADE;


--
-- Name: ai_staff ai_staff_default_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_staff
    ADD CONSTRAINT ai_staff_default_model_id_fkey FOREIGN KEY (default_model_id) REFERENCES public.ai_models(id) ON DELETE SET NULL;


--
-- Name: ai_staff ai_staff_default_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_staff
    ADD CONSTRAINT ai_staff_default_provider_id_fkey FOREIGN KEY (default_provider_id) REFERENCES public.ai_providers(id) ON DELETE SET NULL;


--
-- Name: approval_override_audit approval_override_audit_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_override_audit
    ADD CONSTRAINT approval_override_audit_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: approval_transitions approval_transitions_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_transitions
    ADD CONSTRAINT approval_transitions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: customer_contacts customer_contacts_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT customer_contacts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: domain_events domain_events_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_events
    ADD CONSTRAINT domain_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: expense_items expense_items_expense_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_items
    ADD CONSTRAINT expense_items_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE CASCADE;


--
-- Name: expense_items expense_items_mapped_account_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_items
    ADD CONSTRAINT expense_items_mapped_account_code_fkey FOREIGN KEY (mapped_account_code) REFERENCES public.chart_of_accounts(code);


--
-- Name: expenses expenses_disbursed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_disbursed_by_fkey FOREIGN KEY (disbursed_by) REFERENCES public.users(id);


--
-- Name: expenses expenses_gl_confirmed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_gl_confirmed_by_fkey FOREIGN KEY (gl_confirmed_by) REFERENCES public.users(id);


--
-- Name: expenses expenses_journal_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id) ON DELETE SET NULL;


--
-- Name: expenses expenses_po_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE SET NULL;


--
-- Name: expenses expenses_pr_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pr_id_fkey FOREIGN KEY (pr_id) REFERENCES public.purchase_requisitions(id) ON DELETE SET NULL;


--
-- Name: expenses expenses_rejection_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_rejection_actor_id_fkey FOREIGN KEY (rejection_actor_id) REFERENCES public.users(id);


--
-- Name: expenses expenses_submitter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_submitter_id_fkey FOREIGN KEY (submitter_id) REFERENCES public.users(id);


--
-- Name: slips fk_slips_po; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips
    ADD CONSTRAINT fk_slips_po FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE SET NULL;


--
-- Name: slips fk_slips_pr; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips
    ADD CONSTRAINT fk_slips_pr FOREIGN KEY (pr_id) REFERENCES public.purchase_requisitions(id) ON DELETE SET NULL;


--
-- Name: hook_events hook_events_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hook_events
    ADD CONSTRAINT hook_events_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.hook_providers(id);


--
-- Name: journal_entries journal_entries_expense_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE SET NULL;


--
-- Name: journal_entries journal_entries_finalized_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_finalized_by_fkey FOREIGN KEY (finalized_by) REFERENCES public.users(id);


--
-- Name: journal_entries journal_entries_po_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE SET NULL;


--
-- Name: journal_entries journal_entries_pr_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pr_id_fkey FOREIGN KEY (pr_id) REFERENCES public.purchase_requisitions(id) ON DELETE SET NULL;


--
-- Name: journal_entries journal_entries_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_so_id_fkey FOREIGN KEY (so_id) REFERENCES public.sales_orders(id) ON DELETE RESTRICT;


--
-- Name: ledger_lines ledger_lines_account_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT ledger_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES public.chart_of_accounts(code);


--
-- Name: ledger_lines ledger_lines_journal_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT ledger_lines_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: po_items po_items_mapped_account_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.po_items
    ADD CONSTRAINT po_items_mapped_account_code_fkey FOREIGN KEY (mapped_account_code) REFERENCES public.chart_of_accounts(code);


--
-- Name: po_items po_items_po_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.po_items
    ADD CONSTRAINT po_items_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;


--
-- Name: policy_audit policy_audit_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_audit
    ADD CONSTRAINT policy_audit_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: pr_items pr_items_mapped_account_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pr_items
    ADD CONSTRAINT pr_items_mapped_account_code_fkey FOREIGN KEY (mapped_account_code) REFERENCES public.chart_of_accounts(code);


--
-- Name: pr_items pr_items_pr_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pr_items
    ADD CONSTRAINT pr_items_pr_id_fkey FOREIGN KEY (pr_id) REFERENCES public.purchase_requisitions(id) ON DELETE CASCADE;


--
-- Name: purchase_orders purchase_orders_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.users(id);


--
-- Name: purchase_orders purchase_orders_pr_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pr_id_fkey FOREIGN KEY (pr_id) REFERENCES public.purchase_requisitions(id) ON DELETE RESTRICT;


--
-- Name: purchase_orders purchase_orders_rejection_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_rejection_actor_id_fkey FOREIGN KEY (rejection_actor_id) REFERENCES public.users(id);


--
-- Name: purchase_orders purchase_orders_settled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_settled_by_fkey FOREIGN KEY (settled_by) REFERENCES public.users(id);


--
-- Name: purchase_orders purchase_orders_settled_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_settled_slip_id_fkey FOREIGN KEY (settled_slip_id) REFERENCES public.slips(id) ON DELETE SET NULL;


--
-- Name: purchase_requisitions purchase_requisitions_rejection_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_requisitions
    ADD CONSTRAINT purchase_requisitions_rejection_actor_id_fkey FOREIGN KEY (rejection_actor_id) REFERENCES public.users(id);


--
-- Name: purchase_requisitions purchase_requisitions_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_requisitions
    ADD CONSTRAINT purchase_requisitions_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.users(id);


--
-- Name: sales_orders sales_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE RESTRICT;


--
-- Name: sales_orders sales_orders_invoice_issuer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_invoice_issuer_id_fkey FOREIGN KEY (invoice_issuer_id) REFERENCES public.users(id);


--
-- Name: sales_orders sales_orders_paid_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_paid_by_id_fkey FOREIGN KEY (paid_by_id) REFERENCES public.users(id);


--
-- Name: sales_orders sales_orders_rejection_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_rejection_actor_id_fkey FOREIGN KEY (rejection_actor_id) REFERENCES public.users(id);


--
-- Name: sales_orders sales_orders_sales_rep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: slips slips_discarded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips
    ADD CONSTRAINT slips_discarded_by_fkey FOREIGN KEY (discarded_by) REFERENCES public.users(id);


--
-- Name: slips slips_expense_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips
    ADD CONSTRAINT slips_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE SET NULL;


--
-- Name: slips slips_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slips
    ADD CONSTRAINT slips_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id);


--
-- Name: so_items so_items_mapped_revenue_account_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.so_items
    ADD CONSTRAINT so_items_mapped_revenue_account_code_fkey FOREIGN KEY (mapped_revenue_account_code) REFERENCES public.chart_of_accounts(code);


--
-- Name: so_items so_items_sales_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.so_items
    ADD CONSTRAINT so_items_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES public.sales_orders(id) ON DELETE CASCADE;


--
-- Name: waybill_attachments waybill_attachments_waybill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_attachments
    ADD CONSTRAINT waybill_attachments_waybill_id_fkey FOREIGN KEY (waybill_id) REFERENCES public.waybills(id) ON DELETE RESTRICT;


--
-- Name: waybill_events waybill_events_previous_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_events
    ADD CONSTRAINT waybill_events_previous_event_id_fkey FOREIGN KEY (previous_event_id) REFERENCES public.waybill_events(id);


--
-- Name: waybill_events waybill_events_waybill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_events
    ADD CONSTRAINT waybill_events_waybill_id_fkey FOREIGN KEY (waybill_id) REFERENCES public.waybills(id) ON DELETE RESTRICT;


--
-- Name: waybill_watchers waybill_watchers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_watchers
    ADD CONSTRAINT waybill_watchers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: waybill_watchers waybill_watchers_waybill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waybill_watchers
    ADD CONSTRAINT waybill_watchers_waybill_id_fkey FOREIGN KEY (waybill_id) REFERENCES public.waybills(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict aBeKTxuxrgm3rmjmAREirHnm6L5hh84eCSHGiUcSEj3PfLsjOPbWDJeDTuUvuLA

