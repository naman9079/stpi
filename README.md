# BuildExist Marketplace

This repository contains a compact Vite + React + TypeScript marketplace MVP backed by Supabase.

## Run locally

```bash
npm install
copy .env.example .env.local
# edit .env.local with the Supabase URL and anon key
npm run dev
```

The browser client reads only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. The local env file is ignored by git. Never put a service-role key, database password, or other privileged credential in Vite environment variables.

## Startup metrics

**Matiks** and **TrustMRR** are tracked startup profiles in the marketplace, not
sponsors. The sponsor rails remain reserved for sponsor placements. The startup
profiles poll `VITE_STARTUP_METRICS_URL` every 60 seconds and show today, 7-day,
30-day, 3-month, 6-month, 1-year, lifetime revenue, raised funding, customers,
and active subscriptions.

The endpoint must keep provider API keys server-side and return JSON in this shape:

```json
{
  "startups": {
    "matiks": {
      "revenue": { "day": 10000, "week": 70000, "month": 300000, "threeMonths": 900000, "sixMonths": 1800000, "year": 3600000, "lifetime": 5000000 },
      "raised": 314000000,
      "customers": 1200,
      "activeSubscriptions": 300,
      "updatedAt": "2026-10-23T12:00:00.000Z",
      "currency": "USD",
      "source": "provider-name"
    },
    "trustmrr": { "revenue": {}, "raised": null, "updatedAt": "2026-10-23T12:00:00.000Z" }
  }
}
```

Amounts are integer cents. The endpoint should aggregate the historical periods
and return a fresh `updatedAt` value on every successful sync. Do not place a
TrustMRR API key or a Matiks provider key in `.env.local` under a `VITE_` name;
proxy both integrations through a server-side function.

### Matiks fallback plan

Matiks does not currently have a verified public metrics API in this project.
The implemented fallback is:

1. TrustMRR data is synced by `supabase/functions/sponsor-metrics` when a
   TrustMRR key and startup slug are configured.
2. Matiks metrics are stored in `public.sponsor_metrics` and can be edited by
   an admin in the app under **Moderate → Manual startup metrics**.
3. The app subscribes to Supabase Realtime changes and still polls the metrics
   endpoint every 60 seconds.
4. TrustMRR snapshots are stored in `public.sponsor_metric_snapshots` so the
   server can calculate longer periods as history accumulates.

Deploy the fallback function after applying the sponsor migration:

```bash
npx supabase functions deploy sponsor-metrics
npx supabase secrets set TRUSTMRR_API_KEY=tmrr_your_private_key
npx supabase secrets set TRUSTMRR_STARTUP_SLUGS=actual-matiks-slug,actual-trustmrr-slug
```

The deployed function must be reachable at:

```text
https://jyvavcqpnxhlneaigpgv.supabase.co/functions/v1/sponsor-metrics
```

If that URL returns 404, deploy the function before testing the frontend. The
startup slugs must be the exact `slug` values returned by TrustMRR's list
endpoint; startup names are not always valid slugs.

Then point the frontend at the deployed function:

```env
VITE_STARTUP_METRICS_URL=https://your-project.supabase.co/functions/v1/sponsor-metrics
```

If Matiks later provides an official API, add its server-side credentials to
the Edge Function and replace the manual row with a Matiks adapter. Until then,
Matiks values are labeled `manual` and are not presented as verified live data.

## Database setup

The marketplace schema migration is:

```text
supabase/migrations/20261021000000_marketplace_schema.sql
```

If the schema migration was already applied, also apply these visibility
repairs:

```text
supabase/migrations/20261022000000_repair_project_visibility.sql
supabase/migrations/20261023000000_make_projects_visible_to_authenticated_users.sql
supabase/migrations/20261026030000_sponsor_metrics_fallback.sql
```

It defines the marketplace tables, relationships, enums, timestamp triggers, auth profile trigger, RLS policies, moderation protections, and Storage buckets/policies. It has **not** been applied from this workspace because the supplied anon key is not sufficient for schema administration and the Supabase CLI is not linked here.

### Apply with the Supabase CLI

From the project root, after installing the Supabase CLI and authenticating with an account that can administer the project:

```bash
npx supabase login
npx supabase link --project-ref jyvavcqpnxhlneaigpgv
npx supabase db push
```

Review the migrations and existing schema before applying them. The original
schema migration is additive and preserves existing policies with the same
names; the follow-up migrations replace stale project read policies. Signed-in
users can discover projects created by other signed-in users, including drafts
and review submissions. Anonymous users still see only published projects.

### Apply with the Supabase SQL Editor

Open the SQL Editor for project `jyvavcqpnxhlneaigpgv`, paste the contents of
`supabase/migrations/20261021000000_marketplace_schema.sql` and, if the schema
was already installed, `supabase/migrations/20261022000000_repair_project_visibility.sql`.
Review the statements and run them as a privileged database administrator. Do
not run these migrations with the browser anon key.

After applying it, verify:

- all requested tables exist;
- the `on_auth_user_created` trigger creates a buyer profile;
- RLS is enabled on every marketplace table;
- the four Storage buckets exist;
- buyer/seller users cannot set elevated roles or publish their own listing;
- signed-in users can read projects created by other signed-in users;
- private Storage objects are not readable by unrelated users.

## Checks run

```bash
npm run build
```

The production TypeScript/Vite build passes. There is no automated browser test suite yet. Live Supabase reads/writes and RLS tests remain blocked until the migration is applied and a valid project anon key is configured.
