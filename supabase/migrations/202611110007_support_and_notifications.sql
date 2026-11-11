-- Durable support workflow and in-app notifications for passengers and drivers.
alter table public.support_tickets
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists assigned_to uuid references public.profiles(id),
  add column if not exists resolution text;

create index if not exists support_tickets_status_created_idx
  on public.support_tickets(status, created_at desc);
create index if not exists support_tickets_user_created_idx
  on public.support_tickets(user_id, created_at desc);

create table if not exists public.support_ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  author_user_id uuid not null references public.profiles(id),
  body text not null check (length(trim(body)) between 1 and 4000),
  is_staff boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists support_ticket_messages_ticket_created_idx
  on public.support_ticket_messages(ticket_id, created_at);

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null,
  title text not null check (length(title) between 1 and 120),
  body text not null check (length(body) between 1 and 500),
  related_ride_id uuid references public.rides(id) on delete set null,
  related_ticket_id uuid references public.support_tickets(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists user_notifications_unread_idx
  on public.user_notifications(user_id, created_at desc) where read_at is null;
create index if not exists user_notifications_user_created_idx
  on public.user_notifications(user_id, created_at desc);

alter table public.support_ticket_messages enable row level security;
alter table public.user_notifications enable row level security;

drop policy if exists support_ticket_insert_self on public.support_tickets;
drop policy if exists support_ticket_select_self on public.support_tickets;
revoke all on public.support_tickets from public, anon, authenticated;
grant select on public.support_tickets to authenticated;
create policy support_ticket_select_self on public.support_tickets
  for select to authenticated using (user_id = (select auth.uid()));
create policy support_messages_participant_read on public.support_ticket_messages
  for select to authenticated using (
    exists(select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = (select auth.uid()))
    or exists(select 1 from public.user_roles r where r.user_id = (select auth.uid()) and r.role = 'admin')
  );
create policy notifications_read_own on public.user_notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_update_own on public.user_notifications
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.create_support_ticket(
  p_category text, p_message text, p_ride_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ticket uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if length(trim(coalesce(p_category,''))) not between 2 and 60
     or length(trim(coalesce(p_message,''))) not between 5 and 4000 then
    raise exception 'invalid_support_ticket' using errcode = '22023';
  end if;
  if p_ride_id is not null and not exists (
    select 1 from public.rides r
    where r.id = p_ride_id and (
      r.passenger_id = v_user or exists (
        select 1 from public.driver_profiles d where d.id = r.driver_id and d.user_id = v_user
      )
    )
  ) then
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;
  insert into public.support_tickets(user_id, ride_id, category, message)
  values(v_user, p_ride_id, trim(p_category), trim(p_message))
  returning id into v_ticket;
  insert into public.support_ticket_messages(ticket_id, author_user_id, body, is_staff)
  values(v_ticket, v_user, trim(p_message), false);
  return v_ticket;
end;
$$;

create or replace function public.admin_list_support_tickets()
returns table (
  ticket_id uuid, user_id uuid, requester_name text, ride_id uuid,
  category text, initial_message text, ticket_status text,
  assigned_to uuid, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles r where r.user_id = auth.uid() and r.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return query
  select t.id, t.user_id, p.display_name, t.ride_id, t.category, t.message,
    t.status, t.assigned_to, t.created_at, t.updated_at
  from public.support_tickets t join public.profiles p on p.id = t.user_id
  order by case t.status when 'open' then 1 when 'assigned' then 2 when 'resolved' then 3 else 4 end,
    t.updated_at desc limit 200;
end;
$$;

create or replace function public.admin_reply_support_ticket(
  p_ticket_id uuid, p_body text, p_status text default 'assigned'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_user uuid;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles r where r.user_id = v_actor and r.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_body,''))) not between 2 and 4000
     or p_status not in ('assigned','resolved','closed') then
    raise exception 'invalid_support_reply' using errcode = '22023';
  end if;
  select user_id into v_user from public.support_tickets where id = p_ticket_id for update;
  if not found then raise exception 'support_ticket_not_found' using errcode = 'P0002'; end if;
  insert into public.support_ticket_messages(ticket_id, author_user_id, body, is_staff)
  values(p_ticket_id, v_actor, trim(p_body), true);
  update public.support_tickets
    set status = p_status, assigned_to = v_actor, updated_at = now(),
        resolution = case when p_status = 'resolved' then trim(p_body) else resolution end
  where id = p_ticket_id;
  insert into public.user_notifications(user_id, notification_type, title, body, related_ticket_id)
  values(v_user, 'support_reply', 'تحديث من فريق دعم ميثاق', trim(p_body), p_ticket_id);
end;
$$;

create or replace function public.notify_ride_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver_user uuid;
  v_title text;
  v_body text;
begin
  if new.status is not distinct from old.status then return new; end if;
  select d.user_id into v_driver_user from public.driver_profiles d where d.id = new.driver_id;
  v_title := 'تحديث الرحلة';
  v_body := case new.status
    when 'accepted' then 'تم قبول الرحلة من السائق.'
    when 'driver_arriving' then 'السائق في طريقه إلى نقطة الانطلاق.'
    when 'arrived' then 'وصل السائق إلى نقطة الانطلاق.'
    when 'boarded' then 'تم تأكيد الصعود.'
    when 'in_progress' then 'بدأت الرحلة.'
    when 'completed' then 'اكتملت الرحلة.'
    when 'cancelled' then 'تم إلغاء الرحلة.'
    when 'expired' then 'انتهت صلاحية طلب الرحلة.'
    when 'no_driver_found' then 'لم يتم العثور على سائق.'
    else 'تم تحديث حالة الرحلة.'
  end;
  insert into public.user_notifications(user_id, notification_type, title, body, related_ride_id)
  values(new.passenger_id, 'ride_status', v_title, v_body, new.id);
  if v_driver_user is not null then
    insert into public.user_notifications(user_id, notification_type, title, body, related_ride_id)
    values(v_driver_user, 'ride_status', v_title, v_body, new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists rides_notify_status_change on public.rides;
create trigger rides_notify_status_change
after update of status on public.rides
for each row execute function public.notify_ride_status_change();

create or replace function public.notify_driver_offer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid;
begin
  select user_id into v_user from public.driver_profiles where id = new.driver_id;
  if v_user is not null then
    insert into public.user_notifications(user_id, notification_type, title, body, related_ride_id)
    select v_user, 'ride_offer', 'طلب رحلة جديد', 'لديك عرض رحلة جديد. افتح التطبيق لمراجعته.', new.ride_id;
  end if;
  return new;
end;
$$;
drop trigger if exists ride_offers_notify_driver on public.ride_offers;
create trigger ride_offers_notify_driver after insert on public.ride_offers
for each row execute function public.notify_driver_offer();

revoke all on function public.create_support_ticket(text,text,uuid) from public, anon;
revoke all on function public.admin_list_support_tickets() from public, anon, authenticated;
revoke all on function public.admin_reply_support_ticket(uuid,text,text) from public, anon, authenticated;
revoke all on function public.notify_ride_status_change() from public, anon, authenticated;
revoke all on function public.notify_driver_offer() from public, anon, authenticated;
grant execute on function public.create_support_ticket(text,text,uuid) to authenticated;
grant execute on function public.admin_list_support_tickets() to authenticated;
grant execute on function public.admin_reply_support_ticket(uuid,text,text) to authenticated;

revoke all on public.support_ticket_messages, public.user_notifications from public, anon, authenticated;
grant select on public.support_ticket_messages, public.user_notifications to authenticated;
grant update (read_at) on public.user_notifications to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='user_notifications') then
      alter publication supabase_realtime add table public.user_notifications;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='support_tickets') then
      alter publication supabase_realtime add table public.support_tickets;
    end if;
  end if;
end;
$$;
