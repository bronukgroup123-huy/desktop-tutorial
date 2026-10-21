-- ============================================================================
-- Validate forest_zones import from kyiv_forests.geojson
-- Run in Supabase SQL Editor after import
-- Returns a single result set with check_name, actual, expected, status (PASS/FAIL)
-- ============================================================================

WITH params AS (
  SELECT
    20700 AS min_total,
    20808 AS max_total,
    20700 AS min_osm_id,
    20808 AS min_region_id,
    0 AS max_duplicates,
    0 AS max_invalid_geom,
    0 AS max_empty_geom,
    0 AS max_non_multipolygon,
    0 AS max_outside_kyiv,
    4000.0 AS min_area_km2,
    8000.0 AS max_area_km2,
    29.0 AS min_lng,
    32.5 AS max_lng,
    49.0 AS min_lat,
    52.0 AS max_lat,
    30.52 AS kyiv_lng,
    50.45 AS kyiv_lat,
    3 AS min_sample_hits
),
kyiv_region AS (
  SELECT polygon AS kyiv_polygon
  FROM regions
  WHERE slug = 'kyiv'
  LIMIT 1
),
city_points AS (
  SELECT 'Kyiv' AS city, 30.52 AS lng, 50.45 AS lat
  UNION ALL SELECT 'Brovary', 30.79, 50.51
  UNION ALL SELECT 'Bila_Tserkva', 30.11, 49.80
  UNION ALL SELECT 'Boryspil', 30.80, 50.35
  UNION ALL SELECT 'Fastiv', 29.92, 50.07
),
city_checks AS (
  SELECT
    cp.city,
    COUNT(fz.id) AS polygon_count
  FROM city_points cp
  CROSS JOIN LATERAL (
    SELECT 1
    FROM forest_zones fz
    WHERE ST_DWithin(
      fz.polygon::geography,
      ST_SetSRID(ST_MakePoint(cp.lng, cp.lat), 4326)::geography,
      5000
    )
    LIMIT 1
  ) fz
  GROUP BY cp.city
),
base_stats AS (
  SELECT
    COUNT(*) AS total_count,
    COUNT(osm_id) AS count_with_osm_id,
    COUNT(region_id) AS count_with_region_id,
    COUNT(forest_type) AS count_with_forest_type,
    SUM(CASE WHEN NOT ST_IsValid(polygon) THEN 1 ELSE 0 END) AS invalid_geometry,
    SUM(CASE WHEN ST_IsEmpty(polygon) THEN 1 ELSE 0 END) AS empty_geometry,
    SUM(CASE WHEN ST_GeometryType(polygon) != 'ST_MultiPolygon' THEN 1 ELSE 0 END) AS non_multipolygon,
    SUM(ST_Area(polygon::geography)) / 1e6 AS total_area_km2,
    ST_XMin(ST_Extent(polygon)) AS min_lng,
    ST_XMax(ST_Extent(polygon)) AS max_lng,
    ST_YMin(ST_Extent(polygon)) AS min_lat,
    ST_YMax(ST_Extent(polygon)) AS max_lat
  FROM forest_zones
),
duplicate_check AS (
  SELECT COUNT(*) AS duplicate_osm_id
  FROM (
    SELECT osm_id
    FROM forest_zones
    WHERE osm_id IS NOT NULL
    GROUP BY osm_id
    HAVING COUNT(*) > 1
  ) d
),
outside_kyiv_check AS (
  SELECT COUNT(*) AS outside_kyiv_region
  FROM forest_zones fz, kyiv_region kr
  WHERE NOT ST_Intersects(fz.polygon, kr.kyiv_polygon)
),
sample_point_check AS (
  SELECT COUNT(*) AS sample_point_kyiv
  FROM forest_zones fz
  WHERE ST_Contains(
    fz.polygon,
    ST_SetSRID(ST_MakePoint((SELECT kyiv_lng FROM params), (SELECT kyiv_lat FROM params)), 4326)
  )
),
top5_largest AS (
  SELECT
    name,
    ROUND(ST_Area(polygon::geography) / 10000.0, 2) AS area_ha
  FROM forest_zones
  WHERE name IS NOT NULL
  ORDER BY ST_Area(polygon::geography) DESC
  LIMIT 5
),
point_buckets AS (
  SELECT
    CASE
      WHEN npoints <= 10 THEN '4-10'
      WHEN npoints <= 50 THEN '11-50'
      WHEN npoints <= 200 THEN '51-200'
      ELSE '200+'
    END AS bucket,
    COUNT(*) AS polygon_count
  FROM (
    SELECT ST_NPoints(polygon) AS npoints
    FROM forest_zones
  ) p
  GROUP BY bucket
  ORDER BY
    CASE bucket
      WHEN '4-10' THEN 1
      WHEN '11-50' THEN 2
      WHEN '51-200' THEN 3
      WHEN '200+' THEN 4
    END
)
SELECT check_name, actual, expected, status FROM (
  -- 1. total_count
  SELECT
    'total_count'::text AS check_name,
    bs.total_count::text AS actual,
    p.min_total || '-' || p.max_total AS expected,
    CASE WHEN bs.total_count BETWEEN p.min_total AND p.max_total THEN 'PASS' ELSE 'FAIL' END AS status
  FROM base_stats bs, params p

  UNION ALL

  -- 2. count_with_osm_id
  SELECT
    'count_with_osm_id',
    bs.count_with_osm_id::text,
    '>=' || p.min_osm_id,
    CASE WHEN bs.count_with_osm_id >= p.min_osm_id THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 3. count_with_region_id
  SELECT
    'count_with_region_id',
    bs.count_with_region_id::text,
    '>=' || p.min_region_id,
    CASE WHEN bs.count_with_region_id >= p.min_region_id THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 4. count_with_forest_type
  SELECT
    'count_with_forest_type',
    bs.count_with_forest_type::text,
    '>=0 (informational)',
    CASE WHEN bs.count_with_forest_type >= 0 THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs

  UNION ALL

  -- 5. duplicate_osm_id
  SELECT
    'duplicate_osm_id',
    dc.duplicate_osm_id::text,
    '0',
    CASE WHEN dc.duplicate_osm_id = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM duplicate_check dc, params p

  UNION ALL

  -- 6. invalid_geometry
  SELECT
    'invalid_geometry',
    bs.invalid_geometry::text,
    '0',
    CASE WHEN bs.invalid_geometry = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 7. empty_geometry
  SELECT
    'empty_geometry',
    bs.empty_geometry::text,
    '0',
    CASE WHEN bs.empty_geometry = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 8. non_multipolygon
  SELECT
    'non_multipolygon',
    bs.non_multipolygon::text,
    '0',
    CASE WHEN bs.non_multipolygon = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 9. outside_kyiv_region
  SELECT
    'outside_kyiv_region',
    oc.outside_kyiv_region::text,
    '0',
    CASE WHEN oc.outside_kyiv_region = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM outside_kyiv_check oc, params p

  UNION ALL

  -- 10. total_area_km2
  SELECT
    'total_area_km2',
    ROUND(bs.total_area_km2, 2)::text,
    p.min_area_km2 || '-' || p.max_area_km2,
    CASE WHEN bs.total_area_km2 BETWEEN p.min_area_km2 AND p.max_area_km2 THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 11. bbox
  SELECT
    'bbox',
    'lng:' || ROUND(bs.min_lng,4) || '-' || ROUND(bs.max_lng,4) || ' lat:' || ROUND(bs.min_lat,4) || '-' || ROUND(bs.max_lat,4),
    'lng:' || p.min_lng || '-' || p.max_lng || ' lat:' || p.min_lat || '-' || p.max_lat,
    CASE
      WHEN bs.min_lng >= p.min_lng AND bs.max_lng <= p.max_lng
       AND bs.min_lat >= p.min_lat AND bs.max_lat <= p.max_lat
      THEN 'PASS' ELSE 'FAIL' END
  FROM base_stats bs, params p

  UNION ALL

  -- 12. sample_point_kyiv
  SELECT
    'sample_point_kyiv',
    spc.sample_point_kyiv::text,
    '>=' || p.min_sample_hits,
    CASE WHEN spc.sample_point_kyiv >= p.min_sample_hits THEN 'PASS' ELSE 'FAIL' END
  FROM sample_point_check spc, params p

  UNION ALL

  -- Additional: city proximity checks
  SELECT
    'city_proximity_' || cc.city,
    cc.polygon_count::text,
    '>=1',
    CASE WHEN cc.polygon_count >= 1 THEN 'PASS' ELSE 'FAIL' END
  FROM city_checks cc

  UNION ALL

  -- Additional: top-5 largest polygons (informational)
  SELECT
    'top5_largest_' || t5.name,
    t5.area_ha::text || ' ha',
    'informational',
    'INFO'
  FROM top5_largest t5

  UNION ALL

  -- Additional: point distribution buckets (informational)
  SELECT
    'point_bucket_' || pb.bucket,
    pb.polygon_count::text,
    'informational',
    'INFO'
  FROM point_buckets pb
) checks
ORDER BY
  CASE
    WHEN check_name LIKE 'total_count' THEN 1
    WHEN check_name LIKE 'count_with_osm_id' THEN 2
    WHEN check_name LIKE 'count_with_region_id' THEN 3
    WHEN check_name LIKE 'count_with_forest_type' THEN 4
    WHEN check_name LIKE 'duplicate_osm_id' THEN 5
    WHEN check_name LIKE 'invalid_geometry' THEN 6
    WHEN check_name LIKE 'empty_geometry' THEN 7
    WHEN check_name LIKE 'non_multipolygon' THEN 8
    WHEN check_name LIKE 'outside_kyiv_region' THEN 9
    WHEN check_name LIKE 'total_area_km2' THEN 10
    WHEN check_name LIKE 'bbox' THEN 11
    WHEN check_name LIKE 'sample_point_kyiv' THEN 12
    WHEN check_name LIKE 'city_proximity_%' THEN 13
    WHEN check_name LIKE 'top5_largest_%' THEN 20
    WHEN check_name LIKE 'point_bucket_%' THEN 30
    ELSE 99
  END,
  check_name;