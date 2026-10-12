-- ============================================================================
-- Storage bucket для фото знахідок (group 8.6d) + RLS-політики
-- ============================================================================
-- Bucket: приватний, 5MiB, image only.
-- RLS on storage.objects — увімкнено Supabase за дефолтом.
-- Шлях: {user_id}/{pick_id}.jpg. Клієнт генерує signed URL для read.
-- ============================================================================

-- Приватний bucket: тільки власник папки {user_id}/... має доступ
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'mushroom-photos',
  'mushroom-photos',
  false,
  5242880,   -- 5 MiB
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- INSERT у свою папку
DROP POLICY IF EXISTS "mushroom_photos_insert_own" ON storage.objects;
CREATE POLICY "mushroom_photos_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'mushroom-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- SELECT свої
DROP POLICY IF EXISTS "mushroom_photos_select_own" ON storage.objects;
CREATE POLICY "mushroom_photos_select_own"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'mushroom-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- UPDATE свої
DROP POLICY IF EXISTS "mushroom_photos_update_own" ON storage.objects;
CREATE POLICY "mushroom_photos_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'mushroom-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'mushroom-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- DELETE свої
DROP POLICY IF EXISTS "mushroom_photos_delete_own" ON storage.objects;
CREATE POLICY "mushroom_photos_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'mushroom-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
