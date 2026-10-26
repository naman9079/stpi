-- Sponsor metrics fallback for providers without a public API (currently Matiks).
-- TrustMRR syncs can also write here through the sponsor-metrics Edge Function.

create table if not exists public.sponsor_metrics (
  slug text primary key,
  revenue jsonb not null default '{}',
  raised_cents bigint,
  customers bigint,
  active_subscriptions bigint,
  currency char(3) not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  source text not null default 'manual',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

insert into public.sponsor_metrics (slug, source)
values ('matiks', 'manual'), ('trustmrr', 'manual')
on conflict (slug) do nothing;

create table if not exists public.sponsor_metric_snapshots (
  id uuid primary key default gen_random_uuid(),
  slug text not null references public.sponsor_metrics(slug) on delete cascade,
  total_revenue_cents bigint,
  mrr_cents bigint,
  customers bigint,
  active_subscriptions bigint,
  captured_at timestamptz not null default now()
);

create index if not exists sponsor_metric_snapshots_slug_captured_idx
  on public.sponsor_metric_snapshots (slug, captured_at desc);

alter table public.sponsor_metrics enable row level security;
alter table public.sponsor_metric_snapshots enable row level security;

drop policy if exists sponsor_metrics_authenticated_read on public.sponsor_metrics;
create policy sponsor_metrics_authenticated_read on public.sponsor_metrics
  for select to authenticated using (true);

drop policy if exists sponsor_metrics_staff_write on public.sponsor_metrics;
create policy sponsor_metrics_staff_write on public.sponsor_metrics
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Snapshot history is written by the service-role Edge Function only.
revoke all on public.sponsor_metric_snapshots from anon, authenticated;
