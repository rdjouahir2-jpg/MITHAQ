-- Mutual post-trip ratings. A participant can rate the other participant once,
-- and only after the ride is completed.
create table public.ride_ratings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  rater_user_id uuid not null references public.profiles(id) on delete cascade,
  rated_user_id uuid not null references public.profiles(id) on delete cascade,
  score smallint not null check (score between 1 and 5),
  comment text not null default '' check (length(comment) <= 500),
  created_at timestamptz not null default now(),
  unique(ride_id, rater_user_id),
  check (rater_user_id <> rated_user_id)
);

alter table public.ride_ratings enable row level security;
revoke all on table public.ride_ratings from public, anon, authenticated;
grant select on table public.ride_ratings to authenticated;
create policy "ride_ratings_select_participants" on public.ride_ratings
for select to authenticated using (
  rater_user_id = auth.uid() or rated_user_id = auth.uid()
);

create or replace function public.submit_ride_rating(
  p_ride_id uuid,
  p_score integer,
  p_comment text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ride public.rides%rowtype;
  v_rated_user uuid;
  v_rating_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_score not between 1 and 5 or length(coalesce(p_comment,'')) > 500 then
    raise exception 'invalid_rating' using errcode = '22023';
  end if;

  select * into v_ride from public.rides r where r.id = p_ride_id;
  if not found then
    raise exception 'ride_not_found' using errcode = 'P0002';
  end if;
  if v_ride.status <> 'completed' then
    raise exception 'ride_must_be_completed' using errcode = 'P0001';
  end if;

  if v_user = v_ride.passenger_id then
    select d.user_id into v_rated_user
    from public.driver_profiles d where d.id = v_ride.driver_id;
  else
    select v_ride.passenger_id into v_rated_user
    where exists (
      select 1 from public.driver_profiles d
      where d.id = v_ride.driver_id and d.user_id = v_user
    );
  end if;

  if v_rated_user is null then
    raise exception 'ride_participant_required' using errcode = '42501';
  end if;

  insert into public.ride_ratings(ride_id, rater_user_id, rated_user_id, score, comment)
  values(p_ride_id, v_user, v_rated_user, p_score, trim(coalesce(p_comment,'')))
  returning id into v_rating_id;

  return v_rating_id;
exception
  when unique_violation then
    raise exception 'rating_already_submitted' using errcode = '23505';
end;
$$;

create or replace function public.get_my_ride_rating_status(p_ride_id uuid)
returns table (has_rated boolean, score smallint, comment text)
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.ride_ratings rr
    where rr.ride_id = p_ride_id and rr.rater_user_id = auth.uid()
  ),
  (select rr.score from public.ride_ratings rr
    where rr.ride_id = p_ride_id and rr.rater_user_id = auth.uid()),
  (select rr.comment from public.ride_ratings rr
    where rr.ride_id = p_ride_id and rr.rater_user_id = auth.uid());
$$;

revoke all on function public.submit_ride_rating(uuid,integer,text) from public, anon;
revoke all on function public.get_my_ride_rating_status(uuid) from public, anon;
grant execute on function public.submit_ride_rating(uuid,integer,text) to authenticated;
grant execute on function public.get_my_ride_rating_status(uuid) to authenticated;
