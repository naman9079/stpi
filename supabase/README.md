# Supabase migrations

The marketplace schema is defined in `migrations/20261021000000_marketplace_schema.sql`.
It creates the marketplace tables, enums, timestamps, role helpers, RLS policies, storage buckets, and storage policies. Storage object paths are expected to begin with the related project UUID (for example, `<project-id>/cover.png`).

These migrations have **not** been applied from this workspace. Apply them only after verifying access to the intended Supabase project and reviewing the migration in that environment. The migration is additive and avoids destructive drops.
