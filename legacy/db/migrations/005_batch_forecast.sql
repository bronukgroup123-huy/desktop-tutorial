-- ============================================
-- Multi-Point Forecast — batch API & feature flags
-- ============================================

-- ---------- Batch forecast function ----------
-- Можна викликати через supabase.rpc('forecast_batch', {...})
CREATE OR REPLACE FUNCTION forecast_batch(
  p_points JSONB,
  p_date DATE DEFAULT CURRENT_DATE,
  p_user_id UUID DEFAULT NULL,
  p_home_region_id INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_results JSONB := '[]'::JSONB;
  v_pt JSONB;
  v_pt_id TEXT;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
  v_forest_type TEXT;
  v_region_id INT;
  v_inside BOOLEAN;
  v_level TEXT;
  v_species_id UUID;
  v_warnings JSONB := '[]'::JSONB;
  v_ranking INT[] := '{}'::INT[];
  v_score NUMERIC;
  v_best_idx INT := 1;
  v_best_score NUMERIC := -999;
BEGIN
  IF jsonb_array_length(p_points) > 3 THEN
    RAISE EXCEPTION 'Max 3 points allowed';
  END IF;

  FOR i IN 0..jsonb_array_length(p_points) - 1 LOOP
    v_pt := p_points->i;
    v_pt_id := v_pt->>'pointId';
    v_lat := (v_pt->>'lat')::DOUBLE PRECISION;
    v_lng := (v_pt->>'lng')::DOUBLE PRECISION;
    v_forest_type := v_pt->>'forestType';

    -- Перевірка Home Region
    IF p_home_region_id IS NOT NULL THEN
      SELECT INTO v_inside
        ST_Contains(r.polygon, ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326))
      FROM regions r
      WHERE r.id = p_home_region_id;

      IF NOT v_inside THEN
        v_results := v_results || jsonb_build_object(
          'pointId', v_pt_id,
          'error', 'outside_home_region'
        );
        CONTINUE;
      END IF;
    END IF;

    -- Демо-логіка рівня (в реальному додатку тут буде виклик рушія прогнозування)
    v_level := CASE
      WHEN random() < 0.35 THEN 'high'
      WHEN random() < 0.75 THEN 'medium'
      WHEN random() < 0.92 THEN 'low'
      ELSE 'no_data'
    END;

    -- Випадковий вид з топ-20 прогнозу
    SELECT id INTO v_species_id
    FROM species
    WHERE in_forecast = TRUE
    ORDER BY random()
    LIMIT 1;

    v_results := v_results || jsonb_build_object(
      'pointId', v_pt_id,
      'level', v_level,
      'top1', jsonb_build_object(
        'id', v_species_id,
        'name', (SELECT common_name_uk FROM species WHERE id = v_species_id),
        'latin', (SELECT scientific_name FROM species WHERE id = v_species_id)
      ),
      'alternative', jsonb_build_object(
        'name', (SELECT common_name_uk FROM species WHERE in_forecast = TRUE AND id != v_species_id ORDER BY random() LIMIT 1),
        'latin', (SELECT scientific_name FROM species WHERE in_forecast = TRUE AND id != v_species_id ORDER BY random() LIMIT 1)
      ),
      'warnings', v_warnings,
      'daysAfterRain', floor(random() * 10 + 1)::INT,
      'habitat', 'Низини, струмки, мох-сфагнум',
      'verifiedPicks7d', floor(random() * 8)::INT
    );
  END LOOP;

  -- Рейтинг точок
  FOR i IN 0..jsonb_array_length(p_points) - 1 LOOP
    v_pt := p_points->i;
    v_pt_id := v_pt->>'pointId';
    SELECT (v_results->i->>'level') INTO v_level;

    v_score := CASE v_level
      WHEN 'high' THEN 3
      WHEN 'medium' THEN 2
      WHEN 'low' THEN 1
      ELSE 0
    END;

    IF v_level != 'low' AND v_level != 'no_data' THEN
      v_score := v_score + 0.5; -- alternative bonus
    END IF;
    IF (v_results->i->>'verifiedPicks7d')::INT >= 3 THEN
      v_score := v_score + 0.5; -- crowd bonus
    END IF;
    IF jsonb_array_length(v_results->i->'warnings') > 0 THEN
      v_score := v_score - 0.3; -- penalty
    END IF;

    IF v_score > v_best_score THEN
      v_best_score := v_score;
      v_best_idx := i + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'results', v_results,
    'ranking', (
      SELECT array_agg(idx ORDER BY score DESC)
      FROM (
        SELECT i + 1 AS idx, (
          CASE (v_results->i->>'level')
            WHEN 'high' THEN 3 WHEN 'medium' THEN 2 WHEN 'low' THEN 1 ELSE 0
          END +
          CASE WHEN (v_results->i->>'level') NOT IN ('low','no_data') THEN 0.5 ELSE 0 END +
          CASE WHEN (v_results->i->>'verifiedPicks7d')::INT >= 3 THEN 0.5 ELSE 0 END -
          CASE WHEN jsonb_array_length(v_results->i->'warnings') > 0 THEN 0.3 ELSE 0 END
        ) AS score
        FROM generate_series(0, jsonb_array_length(p_points) - 1) AS i
      ) s
    )
  );
END;
$$;

-- ---------- Feature flags seed ----------
INSERT INTO feature_flags (key, enabled, value) VALUES
  ('multi_point_enabled', TRUE, '{"description": "Режим 3 точок"}'::JSONB),
  ('multi_point_max', TRUE, '{"value": 3, "description": "Максимум точок"}'::JSONB),
  ('top10_forecast_enabled', TRUE, '{"description": "Список 10 грибів"}'::JSONB)
ON CONFLICT (key) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  value = EXCLUDED.value,
  updated_at = now();
