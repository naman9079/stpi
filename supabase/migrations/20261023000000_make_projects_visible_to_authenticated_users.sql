-- The app is an authenticated marketplace workspace: users should be able to
-- discover projects created by other signed-in users, including newly-created
-- drafts. Anonymous users still see only published projects through the
-- separate anonymous policy.
drop policy if exists projects_select_published_or_owner on public.projects;

create policy projects_select_authenticated
  on public.projects
  as permissive
  for select
  to authenticated
  using (true);
