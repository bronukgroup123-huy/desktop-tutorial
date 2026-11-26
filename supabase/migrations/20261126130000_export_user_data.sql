-- ============================================================================
-- B6.1: копія всіх даних користувача — на запит через підтримку (GDPR / Закон України «Про захист
-- персональних даних», право на доступ)
-- ============================================================================
-- Один SQL-виклик збирає JSON з усіма даними користувача: профіль, згоди, зміни області, точки
-- (і видалені — вони ще зберігаються), рейтинг, трофеї, ділянки аналізу, друзі, Наглядачі,
-- походи з треком, скарги, які він подав. Координати — числами lat/lng.
--
-- Не віддаємо:
--   • токени push і коди прив'язки Telegram — це ключі доставки, не дані про людину
--     (віддаємо лише платформу й дату);
--   • чужі дані, крім публічних імені та ніку друзів / Наглядачів (видно в застосунку й так);
--   • факт, що ІНШИЙ користувач заблокував цього (як і в застосунку — такий рядок не показується);
--   • службові лічильники лімітів.
-- Рішення PO 2026-11-26: кнопки «Завантажити мої дані» в застосунку НЕМАЄ — масове вивантаження точних
-- координат одним натиском шкідливе, якщо телефон чи сесію вкрали. Копію готує адміністратор на запит
-- людини (підтвердженої з пошти акаунта): `SELECT public.export_user_data('<uuid>');` у SQL Editor.
-- Функція лише читає; викликати може тільки service_role — з застосунку недоступна (тест).

CREATE OR REPLACE FUNCTION public.export_user_data(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH me AS (SELECT * FROM public.users WHERE id = p_user_id)
  SELECT jsonb_build_object(
    'format_version', 1,
    'exported_at', now(),

    'profile', (
      SELECT jsonb_build_object(
        'id', u.id,
        'name', u.name,
        'handle', u.handle,
        'email', u.email,
        'avatar', u.avatar,
        'rating', u.rating,
        'verified_picks', u.total_verified_picks,
        'home_region', r.slug,
        'knowledge_certified_at', u.knowledge_certified_at,
        'curriculum_version', u.curriculum_version,
        'created_at', u.created_at,
        'updated_at', u.updated_at
      )
      FROM me u LEFT JOIN public.regions r ON r.id = u.home_region_id
    ),

    'consents', coalesce((
      SELECT jsonb_agg(jsonb_build_object('doc', c.doc, 'version', c.version, 'accepted_at', c.accepted_at)
        ORDER BY c.accepted_at)
      FROM public.user_consents c WHERE c.user_id = p_user_id
    ), '[]'::jsonb),

    'region_changes', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'from', ro.slug, 'to', rn.slug, 'source', l.source, 'changed_at', l.changed_at,
          'device_fingerprint', l.device_fingerprint)
        ORDER BY l.changed_at)
      FROM public.region_change_log l
      LEFT JOIN public.regions ro ON ro.id = l.old_region_id
      LEFT JOIN public.regions rn ON rn.id = l.new_region_id
      WHERE l.user_id = p_user_id
    ), '[]'::jsonb),

    'picks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'id', p.id,
          'visibility', p.pick_type,
          'species_id', p.species_id,
          'mushroom_type', p.mushroom_type,
          'description', p.description,
          'lat', extensions.ST_Y(p.geom::extensions.geometry),
          'lng', extensions.ST_X(p.geom::extensions.geometry),
          'shown_lat', CASE WHEN p.display_geom IS NULL THEN NULL ELSE extensions.ST_Y(p.display_geom::extensions.geometry) END,
          'shown_lng', CASE WHEN p.display_geom IS NULL THEN NULL ELSE extensions.ST_X(p.display_geom::extensions.geometry) END,
          'forest_type', p.forest_type,
          'verification_status', p.verification_status,
          'photo_path', p.photo_url,
          'captured_at', p.captured_at,
          'created_at', p.created_at,
          'deleted_at', p.deleted_at)
        ORDER BY p.created_at)
      FROM public.mushroom_picks p WHERE p.user_id = p_user_id
    ), '[]'::jsonb),

    'rating_events', coalesce((
      SELECT jsonb_agg(jsonb_build_object('delta', e.delta, 'reason', e.reason, 'pick_id', e.pick_id,
          'created_at', e.created_at) ORDER BY e.created_at)
      FROM public.rating_events e WHERE e.user_id = p_user_id
    ), '[]'::jsonb),

    'trophies', coalesce((
      SELECT jsonb_agg(jsonb_build_object('trophy_id', t.trophy_id, 'earned_at', t.earned_at) ORDER BY t.earned_at)
      FROM public.user_trophies t WHERE t.user_id = p_user_id
    ), '[]'::jsonb),

    'analysis_areas', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'id', a.id,
          'slot', a.slot,
          'label', a.label,
          'lat', extensions.ST_Y(a.center::extensions.geometry),
          'lng', extensions.ST_X(a.center::extensions.geometry),
          'size_km', a.size_km,
          'region', r.slug,
          'forest_override', a.forest_override,
          'created_at', a.created_at,
          'last_analyzed_at', a.last_analyzed_at,
          'history', coalesce((
            SELECT jsonb_agg(jsonb_build_object('day', h.day, 'species', to_jsonb(h.species)) ORDER BY h.day)
            FROM public.analysis_history h WHERE h.area_id = a.id AND h.user_id = p_user_id
          ), '[]'::jsonb))
        ORDER BY a.slot)
      FROM public.analysis_areas a LEFT JOIN public.regions r ON r.id = a.region_id
      WHERE a.user_id = p_user_id
    ), '[]'::jsonb),

    'friends', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'handle', o.handle,
          'name', o.name,
          'status', f.status,
          'requested_by_me', f.requested_by = p_user_id,
          'created_at', f.created_at,
          'responded_at', f.responded_at)
        ORDER BY f.created_at)
      FROM public.friendships f
      JOIN public.users o ON o.id = CASE WHEN f.user_a = p_user_id THEN f.user_b ELSE f.user_a END
      WHERE (f.user_a = p_user_id OR f.user_b = p_user_id)
        AND (f.blocked_by IS NULL OR f.blocked_by = p_user_id)
    ), '[]'::jsonb),

    'guardian_links', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'role', CASE WHEN g.owner_id = p_user_id THEN 'my_guardian' ELSE 'i_guard' END,
          'handle', o.handle,
          'name', o.name,
          'status', g.status,
          'created_at', g.created_at,
          'responded_at', g.responded_at)
        ORDER BY g.created_at)
      FROM public.guardian_links g
      JOIN public.users o ON o.id = CASE WHEN g.owner_id = p_user_id THEN g.guardian_id ELSE g.owner_id END
      WHERE g.owner_id = p_user_id OR g.guardian_id = p_user_id
    ), '[]'::jsonb),

    'hikes', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'id', h.id,
          'status', h.status,
          'route', h.route,
          'started_at', h.started_at,
          'expected_return', h.expected_return,
          'closed_at', h.closed_at,
          'closed_reason', h.closed_reason,
          'sos_at', h.sos_at,
          'walked_m', h.walked_m,
          'guardians', coalesce((
            SELECT jsonb_agg(o.handle ORDER BY o.handle)
            FROM public.hike_guardians hg JOIN public.users o ON o.id = hg.guardian_id
            WHERE hg.hike_id = h.id
          ), '[]'::jsonb),
          'track', coalesce((
            SELECT jsonb_agg(jsonb_build_object('lat', pt.lat, 'lng', pt.lng, 'accuracy', pt.accuracy,
                'recorded_at', pt.recorded_at) ORDER BY pt.recorded_at)
            FROM public.hike_points pt WHERE pt.hike_id = h.id
          ), '[]'::jsonb))
        ORDER BY h.started_at)
      FROM public.hikes h WHERE h.owner_id = p_user_id
    ), '[]'::jsonb),

    -- Наглядач v0 (до ADR-022): сесії ще можуть зберігатися
    'legacy_guardian_sessions', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
          'id', s.id,
          'status', s.status,
          'started_at', s.started_at,
          'expected_return', s.expected_return,
          'closed_at', s.closed_at,
          'sos_activated_at', s.sos_activated_at,
          'track', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                'lat', extensions.ST_Y(t.coords::extensions.geometry),
                'lng', extensions.ST_X(t.coords::extensions.geometry),
                'recorded_at', t.recorded_at) ORDER BY t.recorded_at)
            FROM public.guardian_track t WHERE t.session_id = s.id
          ), '[]'::jsonb))
        ORDER BY s.created_at)
      FROM public.guardian_sessions s WHERE s.user_id = p_user_id
    ), '[]'::jsonb),

    'devices', coalesce((
      SELECT jsonb_agg(d ORDER BY d->>'updated_at')
      FROM (
        SELECT jsonb_build_object('kind', 'push', 'platform', pd.platform, 'wave_alerts', pd.wave_alerts,
          'updated_at', pd.updated_at) AS d
        FROM public.push_devices pd WHERE pd.user_id = p_user_id
        UNION ALL
        SELECT jsonb_build_object('kind', 'friends_push', 'platform', ut.platform, 'updated_at', ut.last_seen_at,
          'revoked_at', ut.revoked_at)
        FROM public.user_push_tokens ut WHERE ut.user_id = p_user_id
      ) x
    ), '[]'::jsonb),

    'telegram_linked_at', (SELECT gt.linked_at FROM public.guardian_telegram gt WHERE gt.user_id = p_user_id),

    'reports_sent', coalesce((
      SELECT jsonb_agg(jsonb_build_object('about', o.handle, 'reason', ur.reason, 'comment', ur.comment,
          'created_at', ur.created_at) ORDER BY ur.created_at)
      FROM public.user_reports ur LEFT JOIN public.users o ON o.id = ur.target_id
      WHERE ur.reporter_id = p_user_id
    ), '[]'::jsonb)
  )
  WHERE EXISTS (SELECT 1 FROM me);
$$;

REVOKE ALL ON FUNCTION public.export_user_data(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_user_data(UUID) TO service_role;
