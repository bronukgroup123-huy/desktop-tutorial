-- ============================================================================
-- Public Storage bucket для каталогових фото довідника (PC-TASK #8)
-- ============================================================================
-- Bucket: публічний, 10 MiB, image only.
-- Розміщаємо тут каталогові фото (не user-upload, а довідник).
-- Шлях: зберігаємо як є з кореня репозиторію:
--   "фото Топ-20 грибів (webp)/Білий гриб Boletus edulis/large.webp"
-- Клієнт віддає через CDN:
--   https://wrukmuxdbkbmkygfasai.supabase.co/storage/v1/object/public/
--     mushroom-catalog-photos/фото Топ-20 грибів (webp)/...
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'mushroom-catalog-photos',
  'mushroom-catalog-photos',
  true,
  10485760,
  ARRAY['image/webp','image/jpeg','image/png']
)
ON CONFLICT (id) DO NOTHING;

-- Публічне читання для всіх (анонимно)
DROP POLICY IF EXISTS "catalog_photos_public_read" ON storage.objects;
CREATE POLICY "catalog_photos_public_read"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'mushroom-catalog-photos');

-- Запис тільки через service_role (скрипт upload на ПК)
-- Storage RLS увімкнено за дефолтом Supabase, тому service_role обходить.

COMMENT ON TABLE storage.buckets IS
  'mushroom-photos: private (user picks). mushroom-catalog-photos: public (довідник, PC-TASK #8).';
