-- ============================================
-- Batch import RPC for forest_zones
-- ============================================

CREATE OR REPLACE FUNCTION import_forest_zones_batch(p_features JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  feature_record JSONB;
  geom GEOMETRY;
  v_inserted INT := 0;
  v_skipped INT := 0;
BEGIN
  FOR feature_record IN SELECT * FROM jsonb_array_elements(p_features)
  LOOP
    BEGIN
      geom := ST_MakeValid(
        ST_Multi(
          ST_SetSRID(
            ST_GeomFromGeoJSON(feature_record->>'polygon'),
            4326
          )
        )
      );

      IF geom IS NULL OR ST_IsEmpty(geom) THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

      INSERT INTO forest_zones (
        osm_id,
        polygon,
        forest_type,
        stand_age_years,
        stand_age_source,
        stand_age_confidence,
        relief_type,
        light_type,
        region_id
      ) VALUES (
        (feature_record->>'osm_id')::BIGINT,
        geom,
        (feature_record->>'forest_type')::TEXT,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        (feature_record->>'region_id')::INT
      )
      ON CONFLICT (osm_id) WHERE osm_id IS NOT NULL DO NOTHING;

      IF FOUND THEN
        v_inserted := v_inserted + 1;
      ELSE
        v_skipped := v_skipped + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object('inserted', v_inserted, 'skipped', v_skipped);
END;
$$;