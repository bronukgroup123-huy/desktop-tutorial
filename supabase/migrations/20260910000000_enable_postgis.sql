-- ============================================================================
-- Enable PostGIS
-- ============================================================================
-- Розширення встановлюється у схему extensions, як це робить Supabase
-- за замовчуванням. Сама схема public має extensions у search_path.

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

-- Гарантуємо, що типи geography/geometry видно у public
-- (Supabase зазвичай уже має extensions у search_path, але дублюємо для CI)
ALTER DATABASE postgres SET search_path TO public, extensions;
