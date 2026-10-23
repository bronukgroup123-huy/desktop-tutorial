-- SQL Query to generate GeoJSON FeatureCollection from forest_zones table
-- Run this in Supabase SQL Editor, then copy the result to public/data/forests.geojson

SELECT jsonb_build_object(
  'type', 'FeatureCollection',
  'features', jsonb_agg(feature)
) AS geojson
FROM (
  SELECT jsonb_build_object(
    'type', 'Feature',
    'id', id,
    'geometry', ST_AsGeoJSON(geom)::jsonb,
    'properties', jsonb_build_object(
      'id', id,
      'name', name,
      'forest_type', forest_type,
      'area_ha', area_ha,
      'status', status,
      'status_color', status_color,
      'created_at', created_at,
      'updated_at', updated_at
    )
  ) AS feature
  FROM forest_zones
  WHERE geom IS NOT NULL
) features;

-- Alternative: If you need to transform geometry to WGS84 (EPSG:4326) first:
-- SELECT jsonb_build_object(
--   'type', 'FeatureCollection',
--   'features', jsonb_agg(feature)
-- ) AS geojson
-- FROM (
--   SELECT jsonb_build_object(
--     'type', 'Feature',
--     'id', id,
--     'geometry', ST_AsGeoJSON(ST_Transform(geom, 4326))::jsonb,
--     'properties', jsonb_build_object(
--       'id', id,
--       'name', name,
--       'forest_type', forest_type,
--       'area_ha', area_ha,
--       'status', status,
--       'status_color', status_color,
--       'created_at', created_at,
--       'updated_at', updated_at
--     )
--   ) AS feature
--   FROM forest_zones
--   WHERE geom IS NOT NULL
-- ) features;