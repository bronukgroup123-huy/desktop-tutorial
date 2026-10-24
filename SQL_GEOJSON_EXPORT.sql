-- SQL Query to generate simplified GeoJSON FeatureCollection from forest_zones table
-- Run this in Supabase SQL Editor
-- Uses ST_SimplifyPreserveTopology with 0.0001 tolerance (~11m) to reduce vertex count while keeping small forests
-- ST_AsGeoJSON with 3 decimal places (~110m precision) instead of default 8-9

create or replace function export_all_forests_geojson()
returns json
language plpgsql
as $$
declare
  geojson json;
begin
  set local statement_timeout = '300s';

  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(jsonb_agg(
      jsonb_build_object(
        'type', 'Feature',
        'id', id,
        'geometry', ST_AsGeoJSON(ST_SimplifyPreserveTopology(polygon, 0.0001), 3)::jsonb,
        'properties', jsonb_build_object(
          'id', id,
          'forest_type', forest_type,
          'region_id', region_id,
          'stand_age_years', stand_age_years
        )
      )
    ), '[]'::jsonb)
  ) into geojson
  from forest_zones
  where polygon is not null;

  return geojson;
end;
$$;
