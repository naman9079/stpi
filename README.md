# Launchpad Marketplace MVP

This repository contains a compact Vite + React + TypeScript marketplace MVP backed by Supabase.

## Run locally

```bash
npm install
copy .env.example .env.local
# edit .env.local with the Supabase URL and anon key
npm run dev
```

The browser client reads only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. The local env file is ignored by git. Never put a service-role key, database password, or other privileged credential in Vite environment variables.

## Database setup

The marketplace schema migration is:

```text
supabase/migrations/20261021000000_marketplace_schema.sql
```

If the schema migration was already applied before the seller visibility policy
was corrected, also apply:

```text
supabase/migrations/20261022000000_repair_project_visibility.sql
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
names; the follow-up repair migration intentionally replaces the stale
authenticated project read policy so sellers can see their own drafts and
review submissions.

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
- sellers can read their own projects, including drafts, in-review listings,
  and paused listings;
- private Storage objects are not readable by unrelated users.

## Checks run

```bash
npm run build
```

The production TypeScript/Vite build passes. There is no automated browser test suite yet. Live Supabase reads/writes and RLS tests remain blocked until the migration is applied and a valid project anon key is configured.
