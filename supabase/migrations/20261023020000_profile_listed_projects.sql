-- Show every project a user has listed on their public profile.

create or replace function public.get_public_profile(p_profile_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'bio', p.bio,
    'location', p.location,
    'role', p.role,
    'company_name', sp.company_name,
    'website', sp.website,
    'contact_email', sp.contact_email,
    'projects_posted', (select count(*) from public.projects posted where posted.seller_id = p.id),
    'projects_sold', (select count(*) from public.projects sold where sold.seller_id = p.id and sold.status = 'sold'::public.project_status),
    'projects_bought', (select count(*) from public.handover_records bought where bought.buyer_id = p.id and bought.status = 'completed'::public.handover_status),
    'posted_projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', listed.id,
        'title', listed.title,
        'summary', listed.summary,
        'status', listed.status,
        'created_at', listed.created_at
      ) order by listed.created_at desc)
      from public.projects listed
      where listed.seller_id = p.id
    ), '[]'::jsonb),
    'sold_projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sold.id,
        'title', sold.title,
        'summary', sold.summary,
        'status', sold.status,
        'created_at', sold.created_at
      ) order by sold.created_at desc)
      from public.projects sold
      where sold.seller_id = p.id and sold.status = 'sold'::public.project_status
    ), '[]'::jsonb),
    'bought_projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', bought_project.id,
        'title', bought_project.title,
        'summary', bought_project.summary,
        'status', bought_project.status,
        'created_at', bought_project.created_at
      ) order by bought_project.created_at desc)
      from public.handover_records bought_record
      join public.projects bought_project on bought_project.id = bought_record.project_id
      where bought_record.buyer_id = p.id and bought_record.status = 'completed'::public.handover_status
    ), '[]'::jsonb)
  )
  from public.profiles p
  left join public.seller_profiles sp on sp.seller_id = p.id
  where p.id = p_profile_id;
$$;

revoke all on function public.get_public_profile(uuid) from public;
grant execute on function public.get_public_profile(uuid) to authenticated;
