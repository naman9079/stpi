# Supabase migrations

The marketplace schema is defined in `migrations/20261021000000_marketplace_schema.sql`.
If that migration has already been applied, also apply
`migrations/20261022000000_repair_project_visibility.sql` to replace a stale
authenticated project read policy, followed by
`migrations/20261023000000_make_projects_visible_to_authenticated_users.sql`
to make all projects visible inside the authenticated marketplace workspace.
For chat delivery/read ticks, public profile activity, and WebP project logos,
also apply `migrations/20261023010000_profile_chat_logo_features.sql`.
It creates the marketplace tables, enums, timestamps, role helpers, RLS policies, storage buckets, and storage policies. Storage object paths are expected to begin with the related project UUID (for example, `<project-id>/cover.png`).

These migrations have **not** been applied from this workspace. Apply them only
after verifying access to the intended Supabase project and reviewing the
migrations in that environment. The schema migration is additive; the repair
migrations intentionally drop and recreate only the named project read policy.
