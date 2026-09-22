-- 003_views.sql
CREATE VIEW v_catalog_stats AS
SELECT
  (SELECT COUNT(*) FROM species) AS total_species,
  (SELECT COUNT(*) FROM species WHERE has_photos) AS with_photos,
  (SELECT COUNT(*) FROM species WHERE NOT has_photos) AS without_photos,
  (SELECT COUNT(*) FROM species WHERE in_forecast) AS top20,
  (SELECT COUNT(*) FROM species WHERE is_popular) AS popular,
  (SELECT COUNT(*) FROM species WHERE is_poisonous) AS poisonous,
  (SELECT COUNT(*) FROM species WHERE is_deadly) AS deadly,
  (SELECT COUNT(*) FROM species WHERE is_red_listed) AS red_listed,
  (SELECT COUNT(*) FROM species WHERE in_ai_recognition) AS ai,
  (SELECT COUNT(*) FROM species WHERE has_ai_prompt) AS ai_prompt,

  -- Перевірки (має бути 0)
  (SELECT COUNT(*) FROM species WHERE in_forecast AND NOT has_photos) AS bad_top20,
  (SELECT COUNT(*) FROM species WHERE is_popular AND NOT has_photos) AS bad_popular,
  (SELECT COUNT(*) FROM species WHERE is_poisonous AND NOT has_photos) AS bad_poisonous,
  (SELECT COUNT(*) FROM species WHERE in_ai_recognition AND NOT has_photos) AS bad_ai,
  (SELECT COUNT(*) FROM species WHERE is_red_listed AND has_photos = FALSE) AS bad_red;

CREATE VIEW v_data_integrity_check AS
SELECT 'top20_not_in_ai' AS issue, ARRAY_AGG(scientific_name) AS affected
  FROM species WHERE in_forecast AND NOT in_ai_recognition
UNION ALL
SELECT 'poisonous_not_in_ai', ARRAY_AGG(scientific_name)
  FROM species WHERE is_poisonous AND NOT in_ai_recognition
UNION ALL
SELECT 'deadly_without_emergency', ARRAY_AGG(s.scientific_name)
  FROM species s LEFT JOIN species_emergency e ON e.species_id = s.id
  WHERE s.is_deadly AND e.species_id IS NULL
UNION ALL
SELECT 'red_listed_with_regions', ARRAY_AGG(s.scientific_name)
  FROM species s WHERE s.is_red_listed
    AND EXISTS (SELECT 1 FROM species_regions WHERE species_id = s.id)
UNION ALL
SELECT 'top20_missing_species', ARRAY_AGG(er.mushroom_type)
  FROM expert_rules er LEFT JOIN species s ON s.legacy_id = er.legacy_id
  WHERE er.mushroom_type IS NOT NULL AND s.id IS NULL;
