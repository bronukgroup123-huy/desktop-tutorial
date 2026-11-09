-- ============================================================================
-- Виправлення приватності тук-туків (знайдено під час аудиту блоку 1)
--
-- Політика mushroom_picks_read (20260912000001) дозволяла бачити ВСІ точки
-- авторів зі своєї області — включно з private і friends. Це порушує модель
-- приватності (план v8.2 §4, ADR-010/011): private бачить тільки автор,
-- friends — автор і ті, з ким поділились.
--
-- Нова політика: автор | з ким поділились (shared_with) | public.
-- Стрічка scope=region тепер показує лише public-точки авторів області.
-- ============================================================================

DROP POLICY IF EXISTS mushroom_picks_read ON public.mushroom_picks;
CREATE POLICY mushroom_picks_read ON public.mushroom_picks
  FOR SELECT USING (
    auth.uid() = user_id
    OR auth.uid() = ANY (shared_with)
    OR pick_type = 'public'
  );
