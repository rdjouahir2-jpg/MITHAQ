-- Ensure the full routed line, not only its endpoints, remains inside
-- the selected service area before a quote is issued.
create or replace function public.validate_route_geometry_in_area(
  p_service_area_id uuid,
  p_route_geometry jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_boundary extensions.geometry;
  v_route extensions.geometry;
begin
  if p_service_area_id is null or p_route_geometry is null
     or p_route_geometry->>'type' <> 'LineString'
     or jsonb_typeof(p_route_geometry->'coordinates') <> 'array' then
    return false;
  end if;

  select sa.boundary::extensions.geometry into v_boundary
  from public.service_areas sa
  where sa.id = p_service_area_id and sa.is_active and sa.boundary is not null;

  if v_boundary is null then
    return false;
  end if;

  v_route := extensions.st_setsrid(
    extensions.st_geomfromgeojson(p_route_geometry::text), 4326
  );

  return extensions.st_isvalid(v_route)
    and extensions.st_geometrytype(v_route) = 'ST_LineString'
    and extensions.st_coveredby(v_route, v_boundary);
exception
  when others then
    return false;
end;
$$;

revoke all on function public.validate_route_geometry_in_area(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.validate_route_geometry_in_area(uuid,jsonb) to service_role;
