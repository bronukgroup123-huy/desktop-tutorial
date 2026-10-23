-- SQL Query to generate GeoJSON FeatureCollection from forest_zones table
-- Run this in Supabase SQL Editor, or use as RPC function
-- Correct column names: polygon (not geom), forest_type, region_id, stand_age_years

SELECT jsonb_build_object(
  'type', 'FeatureCollection',
  'features', COALESCE(jsonb_agg(
    jsonb_build_object(
      'type', 'Feature',
      'id', id,
      'geometry', ST_AsGeoJSON(polygon)::jsonb,
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