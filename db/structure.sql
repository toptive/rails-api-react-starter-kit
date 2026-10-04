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
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: reject_audit_event_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_audit_event_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_events are append-only';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    action character varying NOT NULL,
    actor_id uuid,
    impersonator_id uuid,
    organization_id uuid,
    subject_type character varying,
    subject_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip_address character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: billing_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    livemode boolean NOT NULL,
    stripe_event_id character varying NOT NULL,
    type character varying NOT NULL,
    stripe_subscription_id character varying,
    organization_id uuid,
    processed_at timestamp(6) without time zone,
    outcome character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: billing_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    livemode boolean DEFAULT false NOT NULL,
    status character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stripe_customer_id character varying NOT NULL,
    stripe_subscription_id character varying NOT NULL,
    offer_id character varying,
    plan character varying DEFAULT 'free'::character varying NOT NULL,
    current_period_end timestamp(6) without time zone,
    cancel_at_period_end boolean DEFAULT false NOT NULL,
    paused boolean DEFAULT false NOT NULL,
    renewal_notice_sent_for timestamp(6) without time zone
);


--
-- Name: impersonations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.impersonations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    admin_id uuid,
    target_user_id uuid,
    reason character varying NOT NULL,
    ended_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    invited_by_id uuid,
    email public.citext NOT NULL,
    role character varying DEFAULT 'member'::character varying NOT NULL,
    access character varying DEFAULT 'full'::character varying NOT NULL,
    token_hash bytea NOT NULL,
    accepted_at timestamp(6) without time zone,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT invitations_access CHECK (((access)::text = ANY (ARRAY[('full'::character varying)::text, ('viewer'::character varying)::text]))),
    CONSTRAINT invitations_role CHECK (((role)::text = ANY (ARRAY[('admin'::character varying)::text, ('member'::character varying)::text]))),
    CONSTRAINT invitations_token_hash_length CHECK ((octet_length(token_hash) = 32))
);


--
-- Name: jobs_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jobs_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id uuid NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    consumed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: legal_acceptances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legal_acceptances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    email_hash character varying NOT NULL,
    versions jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip_address character varying,
    accepted_at timestamp(6) without time zone NOT NULL,
    legal_document_version_id uuid
);


--
-- Name: legal_document_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legal_document_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    legal_document_id uuid NOT NULL,
    number integer NOT NULL,
    titles jsonb DEFAULT '{}'::jsonb NOT NULL,
    bodies jsonb DEFAULT '{}'::jsonb NOT NULL,
    note character varying(255),
    published_at timestamp(6) without time zone,
    created_by_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: legal_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legal_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug character varying NOT NULL,
    published_version_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'member'::character varying NOT NULL,
    access character varying DEFAULT 'full'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT memberships_access CHECK (((access)::text = ANY (ARRAY[('full'::character varying)::text, ('viewer'::character varying)::text]))),
    CONSTRAINT memberships_role CHECK (((role)::text = ANY (ARRAY[('owner'::character varying)::text, ('admin'::character varying)::text, ('member'::character varying)::text])))
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug public.citext NOT NULL,
    personal boolean DEFAULT false NOT NULL,
    onboarded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_hash bytea NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    authenticated_at timestamp(6) without time zone NOT NULL,
    sudo_until timestamp(6) without time zone,
    impersonator_user_id uuid,
    impersonator_session_id uuid,
    revoked_at timestamp(6) without time zone,
    ip_address character varying,
    user_agent character varying(255),
    last_used_at timestamp(6) without time zone,
    renewed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    impersonation_id uuid,
    organization_id uuid,
    CONSTRAINT sessions_impersonation_no_sudo CHECK (((impersonator_user_id IS NULL) OR (sudo_until IS NULL))),
    CONSTRAINT sessions_token_hash_length CHECK ((octet_length(token_hash) = 32))
);


--
-- Name: solid_queue_batch_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batch_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batch_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batch_executions_id_seq OWNED BY public.solid_queue_batch_executions.id;


--
-- Name: solid_queue_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batches (
    id bigint NOT NULL,
    active_job_batch_id character varying,
    description character varying,
    on_finish text,
    on_success text,
    on_failure text,
    metadata text,
    total_jobs integer DEFAULT 0 NOT NULL,
    completed_jobs integer DEFAULT 0 NOT NULL,
    failed_jobs integer DEFAULT 0 NOT NULL,
    enqueued_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batches_id_seq OWNED BY public.solid_queue_batches.id;


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    batch_id bigint
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: translation_fills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.translation_fills (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id uuid,
    locale character varying NOT NULL,
    ip_address character varying,
    count integer,
    error_code character varying,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: translations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.translations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying(255) NOT NULL,
    locale character varying NOT NULL,
    value text DEFAULT ''::text NOT NULL,
    edited boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_hash bytea NOT NULL,
    context character varying NOT NULL,
    sent_to public.citext NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT user_tokens_hash_length CHECK ((octet_length(token_hash) = 32))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying DEFAULT ''::character varying NOT NULL,
    email public.citext NOT NULL,
    hashed_password character varying,
    confirmed_at timestamp(6) without time zone,
    locale character varying DEFAULT 'en'::character varying NOT NULL,
    role character varying DEFAULT 'user'::character varying NOT NULL,
    optional_emails boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    last_organization_id uuid,
    legal_accepted_at timestamp(6) without time zone,
    legal_accepted_versions jsonb DEFAULT '{}'::jsonb NOT NULL,
    legal_accepted_ip_address character varying,
    google_uid character varying,
    CONSTRAINT users_role CHECK (((role)::text = ANY (ARRAY[('user'::character varying)::text, ('superadmin'::character varying)::text])))
);


--
-- Name: solid_queue_batch_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batch_executions_id_seq'::regclass);


--
-- Name: solid_queue_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batches_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: billing_events billing_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_events
    ADD CONSTRAINT billing_events_pkey PRIMARY KEY (id);


--
-- Name: billing_subscriptions billing_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_subscriptions
    ADD CONSTRAINT billing_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: impersonations impersonations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonations
    ADD CONSTRAINT impersonations_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: jobs_tickets jobs_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs_tickets
    ADD CONSTRAINT jobs_tickets_pkey PRIMARY KEY (id);


--
-- Name: legal_acceptances legal_acceptances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_acceptances
    ADD CONSTRAINT legal_acceptances_pkey PRIMARY KEY (id);


--
-- Name: legal_document_versions legal_document_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_document_versions
    ADD CONSTRAINT legal_document_versions_pkey PRIMARY KEY (id);


--
-- Name: legal_documents legal_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_documents
    ADD CONSTRAINT legal_documents_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batch_executions solid_queue_batch_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT solid_queue_batch_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batches solid_queue_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches
    ADD CONSTRAINT solid_queue_batches_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: translation_fills translation_fills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translation_fills
    ADD CONSTRAINT translation_fills_pkey PRIMARY KEY (id);


--
-- Name: translations translations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translations
    ADD CONSTRAINT translations_pkey PRIMARY KEY (id);


--
-- Name: user_tokens user_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_tokens
    ADD CONSTRAINT user_tokens_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_livemode_stripe_subscription_id_733efec0bd; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_livemode_stripe_subscription_id_733efec0bd ON public.billing_subscriptions USING btree (livemode, stripe_subscription_id);


--
-- Name: idx_on_user_id_legal_document_version_id_8b5841d436; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_user_id_legal_document_version_id_8b5841d436 ON public.legal_acceptances USING btree (user_id, legal_document_version_id);


--
-- Name: index_audit_events_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_actor_id ON public.audit_events USING btree (actor_id);


--
-- Name: index_audit_events_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_created_at ON public.audit_events USING btree (created_at);


--
-- Name: index_audit_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_organization_id ON public.audit_events USING btree (organization_id);


--
-- Name: index_audit_events_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_subject_id ON public.audit_events USING btree (subject_id);


--
-- Name: index_audit_events_on_subject_type_and_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_subject_type_and_subject_id ON public.audit_events USING btree (subject_type, subject_id);


--
-- Name: index_billing_events_on_livemode_and_stripe_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_billing_events_on_livemode_and_stripe_event_id ON public.billing_events USING btree (livemode, stripe_event_id);


--
-- Name: index_billing_subscriptions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billing_subscriptions_on_organization_id ON public.billing_subscriptions USING btree (organization_id);


--
-- Name: index_billing_subscriptions_on_organization_id_and_livemode; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_billing_subscriptions_on_organization_id_and_livemode ON public.billing_subscriptions USING btree (organization_id, livemode);


--
-- Name: index_impersonations_on_admin_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_impersonations_on_admin_id ON public.impersonations USING btree (admin_id);


--
-- Name: index_impersonations_on_target_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_impersonations_on_target_user_id ON public.impersonations USING btree (target_user_id);


--
-- Name: index_invitations_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_expires_at ON public.invitations USING btree (expires_at);


--
-- Name: index_invitations_on_invited_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_invited_by_id ON public.invitations USING btree (invited_by_id);


--
-- Name: index_invitations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_organization_id ON public.invitations USING btree (organization_id);


--
-- Name: index_invitations_on_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token_hash ON public.invitations USING btree (token_hash);


--
-- Name: index_jobs_tickets_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jobs_tickets_on_expires_at ON public.jobs_tickets USING btree (expires_at);


--
-- Name: index_jobs_tickets_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jobs_tickets_on_session_id ON public.jobs_tickets USING btree (session_id);


--
-- Name: index_legal_acceptances_on_legal_document_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_legal_acceptances_on_legal_document_version_id ON public.legal_acceptances USING btree (legal_document_version_id);


--
-- Name: index_legal_acceptances_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_legal_acceptances_on_user_id ON public.legal_acceptances USING btree (user_id);


--
-- Name: index_legal_document_versions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_legal_document_versions_on_created_by_id ON public.legal_document_versions USING btree (created_by_id);


--
-- Name: index_legal_document_versions_on_legal_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_legal_document_versions_on_legal_document_id ON public.legal_document_versions USING btree (legal_document_id);


--
-- Name: index_legal_document_versions_on_legal_document_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_legal_document_versions_on_legal_document_id_and_number ON public.legal_document_versions USING btree (legal_document_id, number);


--
-- Name: index_legal_documents_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_legal_documents_on_slug ON public.legal_documents USING btree (slug);


--
-- Name: index_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_organization_id ON public.memberships USING btree (organization_id);


--
-- Name: index_memberships_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_organization_id_and_user_id ON public.memberships USING btree (organization_id, user_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_organizations_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_slug ON public.organizations USING btree (slug);


--
-- Name: index_sessions_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_expires_at ON public.sessions USING btree (expires_at);


--
-- Name: index_sessions_on_impersonation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_impersonation_id ON public.sessions USING btree (impersonation_id);


--
-- Name: index_sessions_on_impersonator_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_impersonator_session_id ON public.sessions USING btree (impersonator_session_id);


--
-- Name: index_sessions_on_impersonator_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_impersonator_user_id ON public.sessions USING btree (impersonator_user_id);


--
-- Name: index_sessions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_organization_id ON public.sessions USING btree (organization_id);


--
-- Name: index_sessions_on_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_token_hash ON public.sessions USING btree (token_hash);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_solid_queue_batch_executions_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batch_executions_on_batch_id ON public.solid_queue_batch_executions USING btree (batch_id);


--
-- Name: index_solid_queue_batch_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batch_executions_on_job_id ON public.solid_queue_batch_executions USING btree (job_id);


--
-- Name: index_solid_queue_batches_on_active_job_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batches_on_active_job_batch_id ON public.solid_queue_batches USING btree (active_job_batch_id);


--
-- Name: index_solid_queue_batches_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batches_on_finished_at ON public.solid_queue_batches USING btree (finished_at);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_batch_id ON public.solid_queue_jobs USING btree (batch_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: index_translation_fills_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_translation_fills_on_session_id ON public.translation_fills USING btree (session_id);


--
-- Name: index_translations_on_key_and_locale; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_translations_on_key_and_locale ON public.translations USING btree (key, locale);


--
-- Name: index_user_tokens_on_token_hash_and_context; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_tokens_on_token_hash_and_context ON public.user_tokens USING btree (token_hash, context);


--
-- Name: index_user_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_tokens_on_user_id ON public.user_tokens USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_google_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_google_uid ON public.users USING btree (google_uid);


--
-- Name: index_users_on_last_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_organization_id ON public.users USING btree (last_organization_id);


--
-- Name: invitations_pending_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX invitations_pending_email_index ON public.invitations USING btree (organization_id, email) WHERE (accepted_at IS NULL);


--
-- Name: audit_events audit_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_events_append_only BEFORE DELETE OR UPDATE ON public.audit_events FOR EACH ROW EXECUTE FUNCTION public.reject_audit_event_mutation();


--
-- Name: impersonations fk_rails_06800193f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonations
    ADD CONSTRAINT fk_rails_06800193f7 FOREIGN KEY (admin_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: invitations fk_rails_0fe4c14f0e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_0fe4c14f0e FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_13b6b70e63; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_13b6b70e63 FOREIGN KEY (impersonator_user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_154fcbdf62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_154fcbdf62 FOREIGN KEY (impersonation_id) REFERENCES public.impersonations(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: billing_subscriptions fk_rails_364213cc3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_subscriptions
    ADD CONSTRAINT fk_rails_364213cc3e FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: legal_acceptances fk_rails_3b2c4ebc36; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_acceptances
    ADD CONSTRAINT fk_rails_3b2c4ebc36 FOREIGN KEY (legal_document_version_id) REFERENCES public.legal_document_versions(id);


--
-- Name: legal_document_versions fk_rails_49e0e9421c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_document_versions
    ADD CONSTRAINT fk_rails_49e0e9421c FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: legal_document_versions fk_rails_5fe2791bee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_document_versions
    ADD CONSTRAINT fk_rails_5fe2791bee FOREIGN KEY (legal_document_id) REFERENCES public.legal_documents(id);


--
-- Name: memberships fk_rails_64267aab58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_64267aab58 FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: jobs_tickets fk_rails_643d5a202b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs_tickets
    ADD CONSTRAINT fk_rails_643d5a202b FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_717a4cd6ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_717a4cd6ef FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: solid_queue_batch_executions fk_rails_7c5e073422; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_7c5e073422 FOREIGN KEY (batch_id) REFERENCES public.solid_queue_batches(id) ON DELETE CASCADE;


--
-- Name: legal_acceptances fk_rails_7e26cdb304; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_acceptances
    ADD CONSTRAINT fk_rails_7e26cdb304 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: users fk_rails_bb5362b0e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_bb5362b0e2 FOREIGN KEY (last_organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: solid_queue_batch_executions fk_rails_bc9f981155; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_bc9f981155 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: legal_documents fk_rails_befd55bf99; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_documents
    ADD CONSTRAINT fk_rails_befd55bf99 FOREIGN KEY (published_version_id) REFERENCES public.legal_document_versions(id);


--
-- Name: translation_fills fk_rails_c20cdbb44c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translation_fills
    ADD CONSTRAINT fk_rails_c20cdbb44c FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: invitations fk_rails_d799c974a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_d799c974a1 FOREIGN KEY (invited_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: user_tokens fk_rails_e0a9c15abb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_tokens
    ADD CONSTRAINT fk_rails_e0a9c15abb FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_e5929df22f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_e5929df22f FOREIGN KEY (impersonator_session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;


--
-- Name: impersonations fk_rails_e6447cd602; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonations
    ADD CONSTRAINT fk_rails_e6447cd602 FOREIGN KEY (target_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261004170100'),
('20261004170000'),
('20261004160000'),
('20261004150000'),
('20261004140000'),
('20261004110000'),
('20261004100000'),
('20261004090200'),
('20261004090100'),
('20261004090000');
