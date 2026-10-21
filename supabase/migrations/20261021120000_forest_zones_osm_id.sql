-- 1. Додати колонку osm_id BIGINT
ALTER TABLE forest_zones
ADD COLUMN IF NOT EXISTS osm_id BIGINT;

-- 2. Унікальний парційальний індекс на osm_id (тільки для непорожніх значень)
CREATE UNIQUE INDEX IF NOT EXISTS forest_zones_osm_id_unique
ON forest_zones (osm_id)
WHERE osm_id IS NOT NULL;

-- 3. Видалити дублікат GIST-індексу idx_forest_zones_polygon
DROP INDEX IF EXISTS idx_forest_zones_polygon;

-- 4. Коментар до колонки osm_id
COMMENT ON COLUMN forest_zones.osm_id IS 'OSM id (way/relation number), витягнутий з ''way/123'' або ''relation/456''';