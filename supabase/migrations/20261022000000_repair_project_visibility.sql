-- Repair the authenticated project read policy for databases that already
-- contain a stale policy with the same name. The original additive migration
-- intentionally preserved same-named policies, which can leave seller-owned
-- drafts invisible after they are created.
drop policy if exists projects_select_published_or_owner on public.projects;

create policy projects_select_published_or_owner
  on public.projects
  as permissive
  for select
  to authenticated
  using (
    status = 'published'::public.project_status
    or seller_id = auth.uid()
    or public.is_staff()
  );
