-- ============================================================================
-- Рушій плодоношення (ADR-015 §15.8): параметри виду — поштовх, дозрівання, хвиля.
--   fruiting_trigger — що запускає хвилю: rain (дощ), rain_cool (дощ + осіннє похолодання),
--                      spring_warm (весняний прогрів ґрунту), thaw (відлига після заморозків);
--   trigger_rain_mm  — сума опадів за 3 дні, що промочує ґрунт;
--   maturation_dd    — градусо-днів ґрунту від поштовху до грибів (з неготовою грибницею;
--                      з вологим ґрунтом — 40%, тобто 2–4 дні, як у книгах);
--   dd_base          — база градусо-днів, °C;
--   flush_days       — тривалість хвилі, днів;
--   soil_temp_min/max — температура ґрунту, за якої гриби ростуть.
-- Значення — стартові оцінки (мікологічні джерела й практика), калібруються повтором сезону
-- (docs/SEASON_REPLAY.md) і перевіреними тук-туками. Змінюються тут, без зміни коду.
-- ============================================================================

ALTER TABLE public.expert_rules
  ADD COLUMN IF NOT EXISTS fruiting_trigger TEXT NOT NULL DEFAULT 'rain'
    CHECK (fruiting_trigger IN ('rain', 'rain_cool', 'spring_warm', 'thaw')),
  ADD COLUMN IF NOT EXISTS trigger_rain_mm NUMERIC NOT NULL DEFAULT 15 CHECK (trigger_rain_mm >= 0),
  ADD COLUMN IF NOT EXISTS maturation_dd NUMERIC NOT NULL DEFAULT 70 CHECK (maturation_dd > 0),
  ADD COLUMN IF NOT EXISTS dd_base NUMERIC NOT NULL DEFAULT 4,
  ADD COLUMN IF NOT EXISTS flush_days INT NOT NULL DEFAULT 9 CHECK (flush_days BETWEEN 1 AND 60),
  ADD COLUMN IF NOT EXISTS soil_temp_min NUMERIC,
  ADD COLUMN IF NOT EXISTS soil_temp_max NUMERIC;

UPDATE public.expert_rules AS er SET
  fruiting_trigger = v.trig, trigger_rain_mm = v.rain, maturation_dd = v.dd, dd_base = v.base,
  flush_days = v.flush, soil_temp_min = v.smin, soil_temp_max = v.smax
FROM (VALUES
  ('boletus_edulis',          'rain',        15, 80,  4, 10, 10, 20),
  ('imleria_badia',           'rain',        15, 80,  4, 10, 10, 20),
  ('boletus_luridus',         'rain',        15, 70,  4,  8, 12, 22),
  ('leccinum_scabrum',        'rain',        10, 55,  4,  8,  8, 20),
  ('leccinum_aurantiacum',    'rain',        10, 60,  4,  8,  8, 20),
  ('suillus_luteus',          'rain',        10, 50,  4,  7, 10, 22),
  ('suillus_bovinus',         'rain',        10, 55,  4,  7, 10, 22),
  ('xerocomus_subtomentosus', 'rain',        10, 55,  4,  7, 10, 22),
  ('russula_vesca',           'rain',        10, 50,  4,  7, 10, 22),
  ('cantharellus_cibarius',   'rain',        20, 110, 4, 18, 12, 22),
  ('hydnum_repandum',         'rain',        15, 100, 4, 14, 10, 18),
  ('lactarius_deliciosus',    'rain',        20, 100, 4, 12, 10, 20),
  ('lactarius_resimus',       'rain',        20, 100, 4, 12, 10, 20),
  ('lactarius_torminosus',    'rain',        15, 90,  4, 12, 10, 18),
  ('armillaria_mellea',       'rain_cool',   15, 70,  4, 12,  8, 16),
  ('pleurotus_ostreatus',     'rain',        10, 60,  4, 10,  8, 18),
  ('flammulina_velutipes',    'thaw',        10, 25,  0, 20,  0, 10),
  ('lycoperdon_perlatum',     'rain',        10, 40,  4,  7, 12, 25),
  ('agaricus_campestris',     'rain',        10, 40,  4,  6, 12, 25),
  ('morchella_esculenta',     'spring_warm',  0, 60,  4, 18,  6, 14)
) AS v(mt, trig, rain, dd, base, flush, smin, smax)
WHERE er.mushroom_type = v.mt;

-- Печериця за книгою — «на луках, полях, у цілинних степах, на пасовиськах»: не лісовий вид.
-- Порожній список лісів означав «будь-який ліс», і печериця вигравала в сосняках.
UPDATE public.expert_rules SET forest_type = ARRAY['meadow']::TEXT[] WHERE mushroom_type = 'agaricus_campestris';

DO $$
DECLARE missing INT;
BEGIN
  SELECT COUNT(*) INTO missing FROM public.expert_rules WHERE mvp_stage = 'mvp' AND soil_temp_min IS NULL;
  IF missing > 0 THEN
    RAISE EXCEPTION 'Без параметрів плодоношення: % видів', missing;
  END IF;
END $$;
