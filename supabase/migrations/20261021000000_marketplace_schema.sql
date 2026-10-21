-- Marketplace foundation schema.
-- This migration is intentionally additive: it uses IF NOT EXISTS and does not drop
-- tables, columns, policies, functions, or storage objects.

create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('buyer', 'seller', 'verifier', 'support', 'moderator', 'admin');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.project_status as enum ('draft', 'in_review', 'published', 'paused', 'sold', 'archived');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.verification_status as enum ('unverified', 'requested', 'in_progress', 'verified', 'rejected', 'expired');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.buyer_request_status as enum ('draft', 'open', 'paused', 'matched', 'closed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.match_status as enum ('suggested', 'shortlisted', 'contacted', 'accepted', 'dismissed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.asset_visibility as enum ('public', 'private', 'evidence');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.inquiry_status as enum ('open', 'awaiting_buyer', 'awaiting_seller', 'resolved', 'closed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.verification_request_type as enum ('financial', 'technical', 'legal', 'market', 'full');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.verification_test_status as enum ('pending', 'passed', 'failed', 'not_applicable');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.handover_status as enum ('planned', 'in_progress', 'completed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.handover_task_status as enum ('todo', 'in_progress', 'blocked', 'done', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.listing_report_status as enum ('open', 'investigating', 'resolved', 'dismissed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.moderation_action_type as enum ('hide', 'unhide', 'warn', 'remove', 'restore', 'suspend');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null default 'buyer',
  display_name text,
  avatar_url text,
  bio text,
  location text,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.buyer_preferences (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null unique references public.profiles(id) on delete cascade,
  budget_min numeric(14, 2),
  budget_max numeric(14, 2),
  preferred_industries text[] not null default '{}',
  preferred_locations text[] not null default '{}',
  preferred_technologies text[] not null default '{}',
  investment_stage text,
  risk_tolerance text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint buyer_preferences_budget_range check (budget_min is null or budget_max is null or budget_min <= budget_max),
  constraint buyer_preferences_nonnegative_budget check ((budget_min is null or budget_min >= 0) and (budget_max is null or budget_max >= 0))
);

create table if not exists public.seller_profiles (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null unique references public.profiles(id) on delete cascade,
  company_name text not null,
  legal_name text,
  website text,
  description text,
  founded_year integer check (founded_year between 1800 and 3000),
  contact_email text,
  verification_status public.verification_status not null default 'unverified',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete restrict,
  title text not null,
  slug text not null unique,
  summary text,
  description text,
  status public.project_status not null default 'draft',
  asking_price numeric(14, 2) check (asking_price is null or asking_price >= 0),
  currency char(3) not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  revenue numeric(14, 2) check (revenue is null or revenue >= 0),
  annual_growth numeric(8, 3),
  location text,
  industry text,
  is_featured boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_assets (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  storage_path text not null,
  asset_type text not null,
  file_name text,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  visibility public.asset_visibility not null default 'public',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, storage_path)
);

create table if not exists public.project_technologies (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  technology text not null check (length(trim(technology)) > 0),
  proficiency text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, technology)
);

create table if not exists public.project_metrics (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.projects(id) on delete cascade,
  metric_period_start date,
  metric_period_end date,
  monthly_revenue numeric(14, 2) check (monthly_revenue is null or monthly_revenue >= 0),
  monthly_profit numeric(14, 2),
  monthly_active_users bigint check (monthly_active_users is null or monthly_active_users >= 0),
  total_customers bigint check (total_customers is null or total_customers >= 0),
  retention_rate numeric(5, 2) check (retention_rate is null or retention_rate between 0 and 100),
  churn_rate numeric(5, 2) check (churn_rate is null or churn_rate between 0 and 100),
  extra_metrics jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_metrics_period check (metric_period_start is null or metric_period_end is null or metric_period_start <= metric_period_end)
);

create table if not exists public.project_costs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  cost_type text not null,
  amount numeric(14, 2) not null check (amount >= 0),
  currency char(3) not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  frequency text not null default 'one_time',
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.buyer_requests (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  budget_min numeric(14, 2),
  budget_max numeric(14, 2),
  target_industries text[] not null default '{}',
  target_locations text[] not null default '{}',
  target_technologies text[] not null default '{}',
  status public.buyer_request_status not null default 'draft',
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint buyer_requests_budget_range check (budget_min is null or budget_max is null or budget_min <= budget_max),
  constraint buyer_requests_nonnegative_budget check ((budget_min is null or budget_min >= 0) and (budget_max is null or budget_max >= 0))
);

create table if not exists public.buyer_request_matches (
  id uuid primary key default gen_random_uuid(),
  buyer_request_id uuid not null references public.buyer_requests(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  match_score numeric(5, 2) not null check (match_score between 0 and 100),
  status public.match_status not null default 'suggested',
  rationale text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (buyer_request_id, project_id)
);

create table if not exists public.saved_projects (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (buyer_id, project_id)
);

create table if not exists public.saved_searches (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  criteria jsonb not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  project_id uuid references public.projects(id) on delete set null,
  subject text not null,
  status public.inquiry_status not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inquiries_distinct_participants check (buyer_id <> seller_id)
);

create table if not exists public.inquiry_messages (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete restrict,
  body text not null check (length(trim(body)) > 0),
  attachments jsonb not null default '[]',
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  assigned_to uuid references public.profiles(id) on delete set null,
  request_type public.verification_request_type not null default 'full',
  status public.verification_status not null default 'requested',
  notes text,
  submitted_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.verification_reports (
  id uuid primary key default gen_random_uuid(),
  verification_request_id uuid not null unique references public.verification_requests(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  verifier_id uuid not null references public.profiles(id) on delete restrict,
  status public.verification_status not null default 'in_progress',
  summary text,
  findings jsonb not null default '{}',
  score numeric(5, 2) check (score is null or score between 0 and 100),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.verification_tests (
  id uuid primary key default gen_random_uuid(),
  verification_report_id uuid not null references public.verification_reports(id) on delete cascade,
  test_name text not null,
  status public.verification_test_status not null default 'pending',
  result text,
  evidence_asset_id uuid references public.project_assets(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.demand_evidence (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  evidence_type text not null,
  source_url text,
  storage_path text,
  description text,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint demand_evidence_source check (source_url is not null or storage_path is not null)
);

create table if not exists public.handover_records (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  status public.handover_status not null default 'planned',
  agreed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint handover_distinct_participants check (buyer_id <> seller_id)
);

create table if not exists public.handover_tasks (
  id uuid primary key default gen_random_uuid(),
  handover_record_id uuid not null references public.handover_records(id) on delete cascade,
  title text not null,
  description text,
  assigned_to uuid references public.profiles(id) on delete set null,
  status public.handover_task_status not null default 'todo',
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_terms (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.projects(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  support_period_days integer check (support_period_days is null or support_period_days >= 0),
  response_sla_hours numeric(8, 2) check (response_sla_hours is null or response_sla_hours >= 0),
  channels text[] not null default '{}',
  included_items text[] not null default '{}',
  exclusions text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.listing_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  reported_by uuid not null references public.profiles(id) on delete restrict,
  reason text not null,
  description text,
  status public.listing_report_status not null default 'open',
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  moderator_id uuid not null references public.profiles(id) on delete restrict,
  action_type public.moderation_action_type not null,
  target_type text not null,
  target_id uuid not null,
  notes text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null,
  title text not null,
  body text,
  data jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists projects_seller_id_idx on public.projects(seller_id);
create index if not exists projects_status_idx on public.projects(status);
create index if not exists project_assets_project_id_idx on public.project_assets(project_id);
create index if not exists project_technologies_project_id_idx on public.project_technologies(project_id);
create index if not exists buyer_requests_buyer_id_idx on public.buyer_requests(buyer_id);
create index if not exists buyer_request_matches_project_id_idx on public.buyer_request_matches(project_id);
create index if not exists inquiries_participants_idx on public.inquiries(buyer_id, seller_id);
create index if not exists inquiry_messages_inquiry_id_idx on public.inquiry_messages(inquiry_id, created_at);
create index if not exists verification_requests_project_id_idx on public.verification_requests(project_id);
create index if not exists notifications_recipient_idx on public.notifications(recipient_id, read_at);
create index if not exists audit_logs_entity_idx on public.audit_logs(entity_type, entity_id, created_at);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.role from public.profiles p where p.id = auth.uid()), 'buyer'::public.app_role);
$$;

create or replace function public.has_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_app_role()::text = required_role;
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_app_role() in ('verifier'::public.app_role, 'support'::public.app_role, 'moderator'::public.app_role, 'admin'::public.app_role);
$$;

create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_app_role() in ('moderator'::public.app_role, 'admin'::public.app_role);
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.current_app_role() = 'admin'::public.app_role;
$$;

create or replace function public.protect_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
     and new.role is distinct from 'buyer'::public.app_role
     and coalesce(auth.role(), '') <> 'service_role'
     and not public.is_admin() then
    raise exception 'profile role assignment requires admin authorization';
  end if;

   if tg_op = 'UPDATE'
      and old.role is distinct from new.role
      and old.role in ('buyer'::public.app_role, 'seller'::public.app_role)
      and new.role in ('buyer'::public.app_role, 'seller'::public.app_role)
      then
     -- Buyer/seller mode changes are self-service. Elevated roles remain
     -- provisioned by an administrator or the trusted service role only.
     null;
   elsif tg_op = 'UPDATE'
      and old.role is distinct from new.role
      and coalesce(auth.role(), '') <> 'service_role'
      and not public.is_admin() then
     raise exception 'profile role changes require admin authorization';
   end if;
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'name'))
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.current_app_role() from public;
revoke all on function public.has_role(text) from public;
revoke all on function public.is_staff() from public;
revoke all on function public.is_moderator() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.set_updated_at() from public;
revoke all on function public.protect_profile_role() from public;
revoke all on function public.handle_new_user() from public;
grant execute on function public.current_app_role() to anon, authenticated;
grant execute on function public.has_role(text) to anon, authenticated;
grant execute on function public.is_staff() to anon, authenticated;

create or replace function public.protect_project_moderation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  privileged boolean := coalesce(auth.role(), '') = 'service_role' or public.is_moderator();
begin
  if not privileged then
    if tg_op = 'INSERT' then
      if new.status is distinct from 'draft'::public.project_status
         or new.published_at is not null
         or new.is_featured then
        raise exception 'project moderation fields require moderator authorization';
      end if;
    else
      if old.status is distinct from new.status
         and old.seller_id = auth.uid()
         and not (
           (old.status = 'draft'::public.project_status and new.status = 'in_review'::public.project_status)
           or (old.status = 'in_review'::public.project_status and new.status = 'draft'::public.project_status)
           or (old.status = 'published'::public.project_status and new.status = 'paused'::public.project_status)
         ) then
        raise exception 'invalid seller project status transition';
      end if;
      if old.status is distinct from new.status
         and old.seller_id <> auth.uid() then
        raise exception 'project status changes require moderator authorization';
      end if;
      if old.published_at is distinct from new.published_at
         or old.is_featured is distinct from new.is_featured then
        raise exception 'project moderation fields require moderator authorization';
      end if;
    end if;
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status and not (
    (old.status = 'draft'::public.project_status and new.status in ('in_review'::public.project_status, 'archived'::public.project_status))
    or (old.status = 'in_review'::public.project_status and new.status in ('draft'::public.project_status, 'published'::public.project_status, 'archived'::public.project_status))
    or (old.status = 'published'::public.project_status and new.status in ('paused'::public.project_status, 'sold'::public.project_status, 'archived'::public.project_status))
    or (old.status = 'paused'::public.project_status and new.status in ('in_review'::public.project_status, 'published'::public.project_status, 'sold'::public.project_status, 'archived'::public.project_status))
    or (old.status = 'sold'::public.project_status and new.status = 'archived'::public.project_status)
    or (old.status = 'archived'::public.project_status and new.status = 'draft'::public.project_status)
  ) then
    raise exception 'invalid project status transition';
  end if;

  if new.status = 'published'::public.project_status and new.published_at is null then
    new.published_at := coalesce(old.published_at, now());
  end if;
  return new;
end;
$$;

create or replace function public.protect_listing_report_moderation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and not public.is_moderator() then
    if tg_op = 'INSERT'
       and (new.status is distinct from 'open'::public.listing_report_status
            or new.resolved_by is not null
            or new.resolved_at is not null) then
      raise exception 'listing report moderation requires moderator authorization';
    end if;
    if tg_op = 'UPDATE'
       and (old.status is distinct from new.status
            or old.resolved_by is distinct from new.resolved_by
            or old.resolved_at is distinct from new.resolved_at) then
      raise exception 'listing report moderation requires moderator authorization';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.protect_moderation_action()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and not public.is_moderator() then
    raise exception 'moderation actions require moderator authorization';
  end if;
  if coalesce(auth.role(), '') <> 'service_role' and new.moderator_id <> auth.uid() then
    raise exception 'moderation action actor must match the authenticated user';
  end if;
  return new;
end;
$$;

revoke all on function public.protect_project_moderation() from public;
revoke all on function public.protect_listing_report_moderation() from public;
revoke all on function public.protect_moderation_action() from public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.projects'::regclass and tgname = 'projects_protect_moderation') then
    create trigger projects_protect_moderation before insert or update on public.projects for each row execute function public.protect_project_moderation();
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.listing_reports'::regclass and tgname = 'listing_reports_protect_moderation') then
    create trigger listing_reports_protect_moderation before insert or update on public.listing_reports for each row execute function public.protect_listing_report_moderation();
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.moderation_actions'::regclass and tgname = 'moderation_actions_protect_actor') then
    create trigger moderation_actions_protect_actor before insert on public.moderation_actions for each row execute function public.protect_moderation_action();
  end if;
end $$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'buyer_preferences', 'seller_profiles', 'projects', 'project_assets',
    'project_technologies', 'project_metrics', 'project_costs', 'buyer_requests',
    'buyer_request_matches', 'saved_projects', 'saved_searches', 'inquiries',
    'inquiry_messages', 'verification_requests', 'verification_reports',
    'verification_tests', 'demand_evidence', 'handover_records', 'handover_tasks',
    'support_terms', 'listing_reports', 'moderation_actions', 'notifications', 'audit_logs'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    if table_name <> 'saved_projects' and table_name <> 'moderation_actions' and table_name <> 'audit_logs' then
      execute format('alter table public.%I add column if not exists updated_at timestamptz not null default now()', table_name);
    end if;
    if not exists (
      select 1 from pg_trigger
      where tgrelid = to_regclass(format('public.%I', table_name))
        and tgname = table_name || '_set_updated_at'
    ) and table_name <> 'saved_projects' and table_name <> 'moderation_actions' and table_name <> 'audit_logs' then
      execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()', table_name || '_set_updated_at', table_name);
    end if;
  end loop;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_protect_role') then
    create trigger profiles_protect_role before update on public.profiles for each row execute function public.protect_profile_role();
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_created') then
    create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
  end if;
end $$;

create or replace function public.ensure_policy(
  p_schema text,
  p_table text,
  p_name text,
  p_command text,
  p_roles text,
  p_using text default null,
  p_check text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  statement text;
begin
  if not exists (
    select 1
     from pg_catalog.pg_policies existing_policy
    where existing_policy.schemaname = p_schema
      and existing_policy.tablename = p_table
      and existing_policy.policyname = p_name
  ) then
    statement := pg_catalog.format('create policy %I on %I.%I as permissive for %s to %s', p_name, p_schema, p_table, p_command, p_roles);
    if p_using is not null then
      statement := statement || pg_catalog.format(' using (%s)', p_using);
    end if;
    if p_check is not null then
      statement := statement || pg_catalog.format(' with check (%s)', p_check);
    end if;
    execute statement;
  end if;
end;
$$;

revoke all on function public.ensure_policy(text, text, text, text, text, text, text) from public;

-- Public marketplace records are readable by signed-in users; writes are owner- or staff-controlled.
select public.ensure_policy('public', 'profiles', 'profiles_select_authenticated', 'select', 'authenticated', 'true');
select public.ensure_policy('public', 'profiles', 'profiles_insert_self_buyer', 'insert', 'authenticated', null, 'id = auth.uid() and role = ''buyer''::public.app_role');
select public.ensure_policy('public', 'profiles', 'profiles_update_self_or_staff', 'update', 'authenticated', 'id = auth.uid() or public.is_staff()', 'id = auth.uid() or public.is_staff()');

select public.ensure_policy('public', 'buyer_preferences', 'buyer_preferences_owner_select', 'select', 'authenticated', 'buyer_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'buyer_preferences', 'buyer_preferences_owner_insert', 'insert', 'authenticated', null, 'buyer_id = auth.uid()');
select public.ensure_policy('public', 'buyer_preferences', 'buyer_preferences_owner_update', 'update', 'authenticated', 'buyer_id = auth.uid() or public.is_staff()', 'buyer_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'buyer_preferences', 'buyer_preferences_owner_delete', 'delete', 'authenticated', 'buyer_id = auth.uid() or public.is_staff()');

select public.ensure_policy('public', 'seller_profiles', 'seller_profiles_select_authenticated', 'select', 'authenticated', 'true');
select public.ensure_policy('public', 'seller_profiles', 'seller_profiles_owner_insert', 'insert', 'authenticated', null, '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');
select public.ensure_policy('public', 'seller_profiles', 'seller_profiles_owner_update', 'update', 'authenticated', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');

select public.ensure_policy('public', 'projects', 'projects_select_published_or_owner', 'select', 'authenticated', 'status = ''published''::public.project_status or seller_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'projects', 'projects_select_published_anon', 'select', 'anon', 'status = ''published''::public.project_status');
select public.ensure_policy('public', 'projects', 'projects_owner_insert', 'insert', 'authenticated', null, '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');
select public.ensure_policy('public', 'projects', 'projects_owner_update', 'update', 'authenticated', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');
select public.ensure_policy('public', 'projects', 'projects_owner_delete', 'delete', 'authenticated', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');

select public.ensure_policy('public', 'project_assets', 'project_assets_select_allowed', 'select', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and ((p.status = ''published''::public.project_status and visibility = ''public''::public.asset_visibility) or p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_assets', 'project_assets_select_published_anon', 'select', 'anon', 'visibility = ''public''::public.asset_visibility and exists (select 1 from public.projects p where p.id = project_id and p.status = ''published''::public.project_status)');
select public.ensure_policy('public', 'project_assets', 'project_assets_owner_insert', 'insert', 'authenticated', null, 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_assets', 'project_assets_owner_update', 'update', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_assets', 'project_assets_owner_delete', 'delete', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');

select public.ensure_policy('public', 'project_technologies', 'project_technologies_select_allowed', 'select', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.status = ''published''::public.project_status or p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_technologies', 'project_technologies_select_published_anon', 'select', 'anon', 'exists (select 1 from public.projects p where p.id = project_id and p.status = ''published''::public.project_status)');
select public.ensure_policy('public', 'project_technologies', 'project_technologies_owner_write', 'insert', 'authenticated', null, 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_technologies', 'project_technologies_owner_update', 'update', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_technologies', 'project_technologies_owner_delete', 'delete', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');

select public.ensure_policy('public', 'project_metrics', 'project_metrics_select_allowed', 'select', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.status = ''published''::public.project_status or p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_metrics', 'project_metrics_select_published_anon', 'select', 'anon', 'exists (select 1 from public.projects p where p.id = project_id and p.status = ''published''::public.project_status)');
select public.ensure_policy('public', 'project_metrics', 'project_metrics_owner_write', 'insert', 'authenticated', null, 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_metrics', 'project_metrics_owner_update', 'update', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');

select public.ensure_policy('public', 'project_costs', 'project_costs_owner_select', 'select', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_costs', 'project_costs_owner_insert', 'insert', 'authenticated', null, 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_costs', 'project_costs_owner_update', 'update', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'project_costs', 'project_costs_owner_delete', 'delete', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.seller_id = auth.uid() or public.is_staff()))');

select public.ensure_policy('public', 'buyer_requests', 'buyer_requests_select_owner_open_or_staff', 'select', 'authenticated', 'buyer_id = auth.uid() or status = ''open''::public.buyer_request_status or public.is_staff()');
select public.ensure_policy('public', 'buyer_requests', 'buyer_requests_owner_insert', 'insert', 'authenticated', null, 'buyer_id = auth.uid()');
select public.ensure_policy('public', 'buyer_requests', 'buyer_requests_owner_update', 'update', 'authenticated', 'buyer_id = auth.uid() or public.is_staff()', 'buyer_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'buyer_requests', 'buyer_requests_owner_delete', 'delete', 'authenticated', 'buyer_id = auth.uid() or public.is_staff()');

select public.ensure_policy('public', 'buyer_request_matches', 'matches_participant_select', 'select', 'authenticated', 'exists (select 1 from public.buyer_requests br where br.id = buyer_request_id and br.buyer_id = auth.uid()) or exists (select 1 from public.projects p where p.id = project_id and p.seller_id = auth.uid()) or public.is_staff()');
select public.ensure_policy('public', 'buyer_request_matches', 'matches_staff_insert', 'insert', 'authenticated', null, 'public.is_staff()');
select public.ensure_policy('public', 'buyer_request_matches', 'matches_staff_update', 'update', 'authenticated', 'public.is_staff()', 'public.is_staff()');

select public.ensure_policy('public', 'saved_projects', 'saved_projects_owner_select', 'select', 'authenticated', 'buyer_id = auth.uid()');
select public.ensure_policy('public', 'saved_projects', 'saved_projects_owner_insert', 'insert', 'authenticated', null, 'buyer_id = auth.uid()');
select public.ensure_policy('public', 'saved_projects', 'saved_projects_owner_delete', 'delete', 'authenticated', 'buyer_id = auth.uid()');
select public.ensure_policy('public', 'saved_searches', 'saved_searches_owner_all', 'all', 'authenticated', 'buyer_id = auth.uid()', 'buyer_id = auth.uid()');

select public.ensure_policy('public', 'inquiries', 'inquiries_participant_select', 'select', 'authenticated', 'buyer_id = auth.uid() or seller_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'inquiries', 'inquiries_buyer_insert', 'insert', 'authenticated', null, 'buyer_id = auth.uid() and buyer_id <> seller_id');
select public.ensure_policy('public', 'inquiries', 'inquiries_participant_update', 'update', 'authenticated', 'buyer_id = auth.uid() or seller_id = auth.uid() or public.is_staff()', 'buyer_id = auth.uid() or seller_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'inquiry_messages', 'inquiry_messages_participant_select', 'select', 'authenticated', 'exists (select 1 from public.inquiries i where i.id = inquiry_id and (i.buyer_id = auth.uid() or i.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'inquiry_messages', 'inquiry_messages_participant_insert', 'insert', 'authenticated', null, 'sender_id = auth.uid() and exists (select 1 from public.inquiries i where i.id = inquiry_id and (i.buyer_id = auth.uid() or i.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'inquiry_messages', 'inquiry_messages_sender_update', 'update', 'authenticated', 'sender_id = auth.uid() or public.is_staff()', 'sender_id = auth.uid() or public.is_staff()');

select public.ensure_policy('public', 'verification_requests', 'verification_requests_participant_select', 'select', 'authenticated', 'requested_by = auth.uid() or assigned_to = auth.uid() or exists (select 1 from public.projects p where p.id = project_id and p.seller_id = auth.uid()) or public.is_staff()');
select public.ensure_policy('public', 'verification_requests', 'verification_requests_owner_insert', 'insert', 'authenticated', null, 'requested_by = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'verification_requests', 'verification_requests_staff_update', 'update', 'authenticated', 'requested_by = auth.uid() or assigned_to = auth.uid() or public.is_staff()', 'public.is_staff() or requested_by = auth.uid()');
select public.ensure_policy('public', 'verification_reports', 'verification_reports_participant_select', 'select', 'authenticated', 'verifier_id = auth.uid() or exists (select 1 from public.projects p where p.id = project_id and p.seller_id = auth.uid()) or public.is_staff()');
select public.ensure_policy('public', 'verification_reports', 'verification_reports_staff_insert', 'insert', 'authenticated', null, 'verifier_id = auth.uid() and (public.has_role(''verifier'') or public.is_staff())');
select public.ensure_policy('public', 'verification_reports', 'verification_reports_staff_update', 'update', 'authenticated', 'verifier_id = auth.uid() or public.is_staff()', 'verifier_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'verification_tests', 'verification_tests_participant_select', 'select', 'authenticated', 'exists (select 1 from public.verification_reports vr where vr.id = verification_report_id and (vr.verifier_id = auth.uid() or exists (select 1 from public.projects p where p.id = vr.project_id and p.seller_id = auth.uid()) or public.is_staff()))');
select public.ensure_policy('public', 'verification_tests', 'verification_tests_staff_write', 'all', 'authenticated', 'exists (select 1 from public.verification_reports vr where vr.id = verification_report_id and (vr.verifier_id = auth.uid() or public.is_staff()))', 'exists (select 1 from public.verification_reports vr where vr.id = verification_report_id and (vr.verifier_id = auth.uid() or public.is_staff()))');

select public.ensure_policy('public', 'demand_evidence', 'demand_evidence_participant_select', 'select', 'authenticated', 'submitted_by = auth.uid() or exists (select 1 from public.projects p where p.id = project_id and p.seller_id = auth.uid()) or public.is_staff()');
select public.ensure_policy('public', 'demand_evidence', 'demand_evidence_owner_insert', 'insert', 'authenticated', null, 'submitted_by = auth.uid()');
select public.ensure_policy('public', 'demand_evidence', 'demand_evidence_owner_update', 'update', 'authenticated', 'submitted_by = auth.uid() or public.is_staff()', 'submitted_by = auth.uid() or public.is_staff()');

select public.ensure_policy('public', 'handover_records', 'handover_records_participant_select', 'select', 'authenticated', 'buyer_id = auth.uid() or seller_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'handover_records', 'handover_records_participant_insert', 'insert', 'authenticated', null, '(buyer_id = auth.uid() or seller_id = auth.uid()) and buyer_id <> seller_id');
select public.ensure_policy('public', 'handover_records', 'handover_records_participant_update', 'update', 'authenticated', 'buyer_id = auth.uid() or seller_id = auth.uid() or public.is_staff()', 'buyer_id = auth.uid() or seller_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'handover_tasks', 'handover_tasks_participant_select', 'select', 'authenticated', 'exists (select 1 from public.handover_records h where h.id = handover_record_id and (h.buyer_id = auth.uid() or h.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'handover_tasks', 'handover_tasks_participant_write', 'all', 'authenticated', 'exists (select 1 from public.handover_records h where h.id = handover_record_id and (h.buyer_id = auth.uid() or h.seller_id = auth.uid() or public.is_staff()))', 'exists (select 1 from public.handover_records h where h.id = handover_record_id and (h.buyer_id = auth.uid() or h.seller_id = auth.uid() or public.is_staff()))');

select public.ensure_policy('public', 'support_terms', 'support_terms_select_published', 'select', 'authenticated', 'exists (select 1 from public.projects p where p.id = project_id and (p.status = ''published''::public.project_status or p.seller_id = auth.uid() or public.is_staff()))');
select public.ensure_policy('public', 'support_terms', 'support_terms_select_published_anon', 'select', 'anon', 'exists (select 1 from public.projects p where p.id = project_id and p.status = ''published''::public.project_status)');
select public.ensure_policy('public', 'support_terms', 'support_terms_owner_insert', 'insert', 'authenticated', null, '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');
select public.ensure_policy('public', 'support_terms', 'support_terms_owner_update', 'update', 'authenticated', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()', '(seller_id = auth.uid() and public.has_role(''seller'')) or public.is_staff()');
select public.ensure_policy('public', 'listing_reports', 'listing_reports_reporter_or_staff_select', 'select', 'authenticated', 'reported_by = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'listing_reports', 'listing_reports_authenticated_insert', 'insert', 'authenticated', null, 'reported_by = auth.uid()');
select public.ensure_policy('public', 'listing_reports', 'listing_reports_staff_update', 'update', 'authenticated', 'public.is_staff()', 'public.is_staff()');
select public.ensure_policy('public', 'moderation_actions', 'moderation_actions_staff_select', 'select', 'authenticated', 'public.is_staff()');
select public.ensure_policy('public', 'moderation_actions', 'moderation_actions_staff_insert', 'insert', 'authenticated', null, 'moderator_id = auth.uid() and public.is_staff()');
select public.ensure_policy('public', 'notifications', 'notifications_recipient_select', 'select', 'authenticated', 'recipient_id = auth.uid() or public.is_staff()');
select public.ensure_policy('public', 'notifications', 'notifications_recipient_update', 'update', 'authenticated', 'recipient_id = auth.uid()', 'recipient_id = auth.uid()');
select public.ensure_policy('public', 'audit_logs', 'audit_logs_staff_select', 'select', 'authenticated', 'public.is_staff()');
select public.ensure_policy('public', 'audit_logs', 'audit_logs_staff_insert', 'insert', 'authenticated', null, 'public.is_staff() or actor_id = auth.uid()');

insert into storage.buckets (id, name, public)
values
  ('project-public-assets', 'project-public-assets', false),
  ('project-private-evidence', 'project-private-evidence', false),
  ('verification-evidence', 'verification-evidence', false),
  ('private-project-files', 'private-project-files', false)
on conflict (id) do nothing;

select public.ensure_policy('storage', 'objects', 'project_public_assets_read', 'select', 'anon', 'bucket_id = ''project-public-assets'' and exists (select 1 from public.project_assets a join public.projects p on p.id = a.project_id where a.storage_path = name and a.visibility = ''public''::public.asset_visibility and p.status = ''published''::public.project_status)');
select public.ensure_policy('storage', 'objects', 'project_public_assets_read_authenticated', 'select', 'authenticated', 'bucket_id = ''project-public-assets'' and (exists (select 1 from public.project_assets a join public.projects p on p.id = a.project_id where a.storage_path = name and a.visibility = ''public''::public.asset_visibility and p.status = ''published''::public.project_status) or exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1]) or public.is_staff())');
select public.ensure_policy('storage', 'objects', 'project_public_assets_insert', 'insert', 'authenticated', null, 'bucket_id = ''project-public-assets'' and (public.is_staff() or (public.has_role(''seller'') and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'project_public_assets_update', 'update', 'authenticated', 'bucket_id = ''project-public-assets'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))', 'bucket_id = ''project-public-assets'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'project_public_assets_delete', 'delete', 'authenticated', 'bucket_id = ''project-public-assets'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');

select public.ensure_policy('storage', 'objects', 'project_private_evidence_read', 'select', 'authenticated', 'bucket_id = ''project-private-evidence'' and (public.is_staff() or exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1]) or exists (select 1 from public.handover_records h where h.buyer_id = auth.uid() and h.project_id::text = (storage.foldername(name))[1]))');
select public.ensure_policy('storage', 'objects', 'project_private_evidence_insert', 'insert', 'authenticated', null, 'bucket_id = ''project-private-evidence'' and (public.is_staff() or (public.has_role(''seller'') and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'project_private_evidence_update', 'update', 'authenticated', 'bucket_id = ''project-private-evidence'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))', 'bucket_id = ''project-private-evidence'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'project_private_evidence_delete', 'delete', 'authenticated', 'bucket_id = ''project-private-evidence'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');

select public.ensure_policy('storage', 'objects', 'verification_evidence_read', 'select', 'authenticated', 'bucket_id = ''verification-evidence'' and (public.is_staff() or public.has_role(''verifier'') or exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1]))');
select public.ensure_policy('storage', 'objects', 'verification_evidence_insert', 'insert', 'authenticated', null, 'bucket_id = ''verification-evidence'' and (public.is_staff() or public.has_role(''verifier'')) and exists (select 1 from public.projects p where p.id::text = (storage.foldername(name))[1])');
select public.ensure_policy('storage', 'objects', 'verification_evidence_update', 'update', 'authenticated', 'bucket_id = ''verification-evidence'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and public.has_role(''verifier'') and exists (select 1 from public.projects p where p.id::text = (storage.foldername(name))[1])))', 'bucket_id = ''verification-evidence'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and public.has_role(''verifier'') and exists (select 1 from public.projects p where p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'verification_evidence_delete', 'delete', 'authenticated', 'bucket_id = ''verification-evidence'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and public.has_role(''verifier'') and exists (select 1 from public.projects p where p.id::text = (storage.foldername(name))[1])))');

select public.ensure_policy('storage', 'objects', 'private_project_files_read', 'select', 'authenticated', 'bucket_id = ''private-project-files'' and (public.is_staff() or exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1]) or exists (select 1 from public.handover_records h where h.buyer_id = auth.uid() and h.project_id::text = (storage.foldername(name))[1]))');
select public.ensure_policy('storage', 'objects', 'private_project_files_insert', 'insert', 'authenticated', null, 'bucket_id = ''private-project-files'' and (public.is_staff() or (public.has_role(''seller'') and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'private_project_files_update', 'update', 'authenticated', 'bucket_id = ''private-project-files'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))', 'bucket_id = ''private-project-files'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
select public.ensure_policy('storage', 'objects', 'private_project_files_delete', 'delete', 'authenticated', 'bucket_id = ''private-project-files'' and (public.is_staff() or (owner_id = (select auth.uid()::text) and exists (select 1 from public.projects p where p.seller_id = auth.uid() and p.id::text = (storage.foldername(name))[1])))');
