-- Resolve a fare policy only when both route endpoints fall inside
-- the same explicitly active service area. No global fallback in live quoting.
alter table public.fare_quotes
  add column if not exists service_area_id uuid references public.service_areas(id);

create or replace function public.resolve_fare_policy_for_route(
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_destination_latitude double precision,
  p_destination_longitude double precision
)
returns table (
  service_area_id uuid,
  service_area_name text,
  version integer,
  currency_code char(3),
  base_amount_minor bigint,
  distance_rate_minor bigint,
  time_rate_minor bigint,
  minimum_amount_minor bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pickup extensions.geometry;
  v_destination extensions.geometry;
  v_area public.service_areas%rowtype;
begin
  if p_pickup_latitude is null or p_pickup_latitude not between -90 and 90
     or p_destination_latitude is null or p_destination_latitude not between -90 and 90
     or p_pickup_longitude is null or p_pickup_longitude not between -180 and 180
     or p_destination_longitude is null or p_destination_longitude not between -180 and 180 then
    raise exception 'invalid_route_coordinates' using errcode = '22023';
  end if;

  v_pickup := extensions.st_setsrid(extensions.st_makepoint(p_pickup_longitude,p_pickup_latitude),4326);
  v_destination := extensions.st_setsrid(extensions.st_makepoint(p_destination_longitude,p_destination_latitude),4326);

  select sa.* into v_area
  from public.service_areas sa
  where sa.is_active
    and sa.boundary is not null
    and extensions.st_covers(sa.boundary::extensions.geometry, v_pickup)
    and extensions.st_covers(sa.boundary::extensions.geometry, v_destination)
  order by sa.created_at asc
  limit 1;

  if not found then
    raise exception 'route_outside_active_service_area' using errcode = '22023';
  end if;

  return query
  select v_area.id, v_area.name, fp.version, fp.currency_code,
    fp.base_amount_minor, fp.distance_rate_minor,
    fp.time_rate_minor, fp.minimum_amount_minor
  from public.fare_policies fp
  where fp.service_area_id = v_area.id
    and fp.is_active
  order by fp.version desc
  limit 1;

  if not found then
    raise exception 'active_service_area_fare_policy_required' using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.resolve_fare_policy_for_route(double precision,double precision,double precision,double precision) from public, anon, authenticated;
grant execute on function public.resolve_fare_policy_for_route(double precision,double precision,double precision,double precision) to service_role;
