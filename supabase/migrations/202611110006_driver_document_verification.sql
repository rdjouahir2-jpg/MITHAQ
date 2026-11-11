-- Private driver document intake, review, and approval gate.
-- Required document types: identity_card, driving_license, vehicle_registration, insurance.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'driver-documents',
  'driver-documents',
  false,
  10485760,
  array['application/pdf','image/jpeg','image/png']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table public.driver_documents (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null check (document_type in (
    'identity_card','driving_license','vehicle_registration','insurance'
  )),
  object_path text not null unique,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  expires_on date,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_reason text,
  uploaded_at timestamptz not null default now(),
  check (document_type <> 'insurance' or expires_on is not null),
  check (expires_on is null or expires_on >= uploaded_at::date)
);

create index driver_documents_driver_type_uploaded_idx
  on public.driver_documents(driver_id, document_type, uploaded_at desc);
create index driver_documents_status_uploaded_idx
  on public.driver_documents(status, uploaded_at desc);

alter table public.driver_documents enable row level security;
revoke all on public.driver_documents from public, anon, authenticated;

-- Private files: owners can upload/read only inside their own driver folder;
-- administrators can read files for manual review. No client can delete/replace.
drop policy if exists driver_documents_owner_upload on storage.objects;
create policy driver_documents_owner_upload
on storage.objects for insert to authenticated
with check (
  bucket_id = 'driver-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (storage.foldername(name))[3] in ('identity_card','driving_license','vehicle_registration','insurance')
  and exists (
    select 1 from public.driver_profiles d
    where d.id::text = (storage.foldername(name))[2]
      and d.user_id = (select auth.uid())
  )
);

drop policy if exists driver_documents_owner_read on storage.objects;
create policy driver_documents_owner_read
on storage.objects for select to authenticated
using (
  bucket_id = 'driver-documents'
  and (
    (
      (storage.foldername(name))[1] = (select auth.uid())::text
      and exists (
        select 1 from public.driver_profiles d
        where d.id::text = (storage.foldername(name))[2]
          and d.user_id = (select auth.uid())
      )
    )
    or exists (
      select 1 from public.user_roles ur
      where ur.user_id = (select auth.uid()) and ur.role = 'admin'
    )
  )
);

create or replace function public.driver_documents_complete(p_driver_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with required(document_type) as (
    values ('identity_card'), ('driving_license'),
           ('vehicle_registration'), ('insurance')
  ),
  latest as (
    select distinct on (dd.document_type)
      dd.document_type, dd.status, dd.expires_on
    from public.driver_documents dd
    where dd.driver_id = p_driver_id
    order by dd.document_type, dd.uploaded_at desc, dd.id desc
  )
  select not exists (
    select 1 from required r
    left join latest l using (document_type)
    where l.status is distinct from 'approved'
       or (l.expires_on is not null and l.expires_on < current_date)
  );
$$;
revoke all on function public.driver_documents_complete(uuid) from public, anon, authenticated;

create or replace function public.enforce_driver_documents_before_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.onboarding_status = 'approved'
     and old.onboarding_status is distinct from new.onboarding_status
     and not public.driver_documents_complete(new.id) then
    raise exception 'required_driver_documents_not_approved' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_driver_documents_before_approval() from public, anon, authenticated;

drop trigger if exists driver_documents_required_for_approval on public.driver_profiles;
create trigger driver_documents_required_for_approval
before update of onboarding_status on public.driver_profiles
for each row execute function public.enforce_driver_documents_before_approval();

create or replace function public.register_my_driver_document(
  p_document_type text,
  p_object_path text,
  p_expires_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver uuid;
  v_availability text;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_document_type not in ('identity_card','driving_license','vehicle_registration','insurance')
     or p_object_path is null or length(p_object_path) > 500
     or p_expires_on is not null and p_expires_on < current_date
     or p_document_type = 'insurance' and p_expires_on is null then
    raise exception 'invalid_driver_document' using errcode = '22023';
  end if;

  select d.id, d.availability_status into v_driver, v_availability
  from public.driver_profiles d
  where d.user_id = v_user and d.onboarding_status <> 'suspended'
  for update;
  if v_driver is null then
    raise exception 'driver_application_required' using errcode = '42501';
  end if;
  if v_availability = 'busy' then
    raise exception 'active_trip_prevents_document_replacement' using errcode = 'P0001';
  end if;

  if p_object_path !~ (
    '^' || v_user::text || '/' || v_driver::text || '/' || p_document_type ||
    '/[A-Za-z0-9._-]+$'
  ) then
    raise exception 'invalid_driver_document_path' using errcode = '42501';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'driver-documents' and o.name = p_object_path
  ) then
    raise exception 'uploaded_document_not_found' using errcode = 'P0002';
  end if;

  insert into public.driver_documents(
    driver_id,user_id,document_type,object_path,expires_on
  ) values (v_driver,v_user,p_document_type,p_object_path,p_expires_on)
  returning id into v_id;

  update public.driver_profiles
    set onboarding_status = 'under_review', availability_status = 'offline', updated_at = now()
  where id = v_driver;

  insert into public.audit_logs(actor_user_id,action,target_type,target_id,reason,metadata)
  values(v_user,'driver_document_submitted','driver_document',v_id::text,
    'Submitted driver document for review',
    jsonb_build_object('driver_id',v_driver,'document_type',p_document_type));
  return v_id;
end;
$$;

create or replace function public.get_my_driver_documents()
returns table (
  document_id uuid,
  document_type text,
  status text,
  expires_on date,
  uploaded_at timestamptz,
  reviewed_at timestamptz,
  review_reason text
)
language sql
stable
security definer
set search_path = ''
as $$
  select dd.id, dd.document_type, dd.status, dd.expires_on,
         dd.uploaded_at, dd.reviewed_at, dd.review_reason
  from public.driver_documents dd
  join public.driver_profiles d on d.id = dd.driver_id
  where d.user_id = auth.uid()
  order by dd.uploaded_at desc;
$$;

create or replace function public.admin_list_driver_documents()
returns table (
  document_id uuid,
  driver_id uuid,
  user_id uuid,
  display_name text,
  document_type text,
  object_path text,
  status text,
  expires_on date,
  uploaded_at timestamptz,
  reviewed_at timestamptz,
  review_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select dd.id, dd.driver_id, dd.user_id, p.display_name,
         dd.document_type, dd.object_path, dd.status, dd.expires_on,
         dd.uploaded_at, dd.reviewed_at, dd.review_reason
  from public.driver_documents dd
  join public.profiles p on p.id = dd.user_id
  where not exists (
    select 1 from public.driver_documents newer
    where newer.driver_id = dd.driver_id
      and newer.document_type = dd.document_type
      and (newer.uploaded_at,newer.id) > (dd.uploaded_at,dd.id)
  )
  order by dd.uploaded_at asc;
end;
$$;

create or replace function public.admin_review_driver_document(
  p_document_id uuid,
  p_decision text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_driver_id uuid;
  v_old_status text;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_decision not in ('approved','rejected')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_document_review' using errcode = '22023';
  end if;

  select driver_id,status into v_driver_id,v_old_status
  from public.driver_documents where id = p_document_id for update;
  if not found then
    raise exception 'driver_document_not_found' using errcode = 'P0002';
  end if;
  if v_old_status <> 'pending' then
    raise exception 'document_already_reviewed' using errcode = 'P0001';
  end if;
  if p_decision = 'approved' and exists (
    select 1 from public.driver_documents d where d.id = p_document_id
      and d.expires_on is not null and d.expires_on < current_date
  ) then
    raise exception 'document_expired' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.driver_documents newer
    where newer.driver_id = v_driver_id
      and newer.document_type = (
        select current_doc.document_type from public.driver_documents current_doc
        where current_doc.id = p_document_id
      )
      and (newer.uploaded_at,newer.id) > (
        select current_doc.uploaded_at,current_doc.id from public.driver_documents current_doc
        where current_doc.id = p_document_id
      )
  ) then
    raise exception 'document_superseded_by_new_upload' using errcode = 'P0001';
  end if;

  update public.driver_documents
  set status = p_decision, reviewed_by = v_actor, reviewed_at = now(),
      review_reason = trim(p_reason)
  where id = p_document_id;

  insert into public.audit_logs(actor_user_id,action,target_type,target_id,reason,metadata)
  values(v_actor,'driver_document_reviewed','driver_document',p_document_id::text,trim(p_reason),
    jsonb_build_object('driver_id',v_driver_id,'from',v_old_status,'to',p_decision));
end;
$$;

revoke all on function public.register_my_driver_document(text,text,date) from public, anon;
revoke all on function public.get_my_driver_documents() from public, anon;
revoke all on function public.admin_list_driver_documents() from public, anon;
revoke all on function public.admin_review_driver_document(uuid,text,text) from public, anon;
grant execute on function public.register_my_driver_document(text,text,date) to authenticated;
grant execute on function public.get_my_driver_documents() to authenticated;
grant execute on function public.admin_list_driver_documents() to authenticated;
grant execute on function public.admin_review_driver_document(uuid,text,text) to authenticated;


-- Expired or replaced documents immediately remove online eligibility.
-- This gate is checked again at the critical write boundaries, not only in the UI.
create or replace function public.enforce_current_driver_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $mithaq$
declare
  v_driver_id uuid;
begin
  if tg_table_name = 'driver_profiles' then
    v_driver_id := new.id;
    if new.availability_status = 'online'
       and not public.driver_documents_complete(v_driver_id) then
      raise exception 'required_driver_documents_not_approved' using errcode = '23514';
    end if;
  elsif tg_table_name = 'driver_locations' then
    v_driver_id := new.driver_id;
    if not public.driver_documents_complete(v_driver_id) then
      raise exception 'required_driver_documents_not_approved' using errcode = '23514';
    end if;
  elsif tg_table_name = 'ride_offers' then
    v_driver_id := new.driver_id;
    if new.status = 'accepted'
       and not public.driver_documents_complete(v_driver_id) then
      raise exception 'required_driver_documents_not_approved' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$mithaq$;
revoke all on function public.enforce_current_driver_documents() from public, anon, authenticated;

drop trigger if exists driver_profile_documents_before_online on public.driver_profiles;
create trigger driver_profile_documents_before_online
before update of availability_status on public.driver_profiles
for each row execute function public.enforce_current_driver_documents();

drop trigger if exists driver_location_documents_gate on public.driver_locations;
create trigger driver_location_documents_gate
before insert or update on public.driver_locations
for each row execute function public.enforce_current_driver_documents();

drop trigger if exists ride_offer_documents_gate on public.ride_offers;
create trigger ride_offer_documents_gate
before update of status on public.ride_offers
for each row execute function public.enforce_current_driver_documents();

-- Existing approved drivers must not retain access without the new evidence gate.
update public.driver_profiles d
set onboarding_status = 'under_review',
    availability_status = 'offline',
    updated_at = now()
where d.onboarding_status = 'approved'
  and not public.driver_documents_complete(d.id);
