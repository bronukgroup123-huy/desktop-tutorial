-- SQL Query to generate simplified GeoJSON FeatureCollection from forest_zones table
-- Run this in Supabase SQL Editor
-- Uses ST_SimplifyPreserveTopology with 0.001 tolerance (~110m) to reduce vertex count
-- ST_AsGeoJSON with 3 decimal places (~110m precision) instead of default 8-9

SELECT jsonb_build_object(
  'type', 'FeatureCollection',
  'features', COALESCE(jsonb_agg(
    jsonb_build_object(
      'type', 'Feature',
      'id', id,
      'geometry', ST_AsGeoJSON(ST_SimplifyPreserveTopology(polygon, 0.001), 3)::jsonb,
      'properties', jsonb_build_object(
        'id', id,
        'forest_type', forest_type,
        'region_id', region_id,
        'stand_age_years', stand_age_years
      )
    )
  ), '[]'::jsonb)
) AS geojson
FROM forest_zones;