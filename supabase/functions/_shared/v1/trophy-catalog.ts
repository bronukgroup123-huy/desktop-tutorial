// ============================================================================
// Трофеї-медальйони (ADR-021 §21.2.2, §21.10; рішення PO 2026-11-21)
//
// 24 трофеї: за що й скільки — тут (сервер вирішує, клієнт лише малює). Показники рахує SQL
// `trophy_stats` (знахідки, види, походи з Наглядачем, друзі). Отриманий трофей зберігається в
// `user_trophies` і не забирається. Картинки — у застосунку: `assets/trophies/{large,small}/<id>.webp`.
//
// «Підтверджена знахідка» — тук-тук із фото, що пройшло перевірку місця й часу зйомки (EXIF),
// не відхилений і не видалений. Походи — лише з Наглядачем (похід без нього живе тільки на
// телефоні, сервер його не бачить). Три трофеї чекають своїх функцій: запрошення (B9.5) і тести
// знань (B3.10) — до того показуються закритими з «скоро».
// ============================================================================

export type TrophyTier = "bronze" | "silver" | "gold";

export type TrophyMetric =
  | "finds"
  | "species_season"
  | "porcini"
  | "chanterelle"
  | "red_book_private"
  | "ai_match"
  | "morels_spring"
  | "winter_honey"
  | "hikes_safe"
  | "hikes_on_time"
  | "hikes_checklist"
  | "hikes_home_nav"
  | "has_guardian"
  | "guarded_hikes"
  | "friends";

export type TrophyGroup = "finds" | "species" | "hikes" | "friends" | "knowledge" | "seasons";

export interface Trophy {
  id: string;
  title: string;
  tier: TrophyTier;
  group: TrophyGroup;
  /** За що — коротко, для картки трофея. */
  how: string;
  /** Що рахуємо і скільки треба; `null` — функції ще немає (трофей «скоро»). */
  metric: TrophyMetric | null;
  target: number;
}

export const TROPHIES: Trophy[] = [
  // Знахідки
  { id: "first_find", title: "Перша знахідка", tier: "bronze", group: "finds", metric: "finds", target: 1,
    how: "Перша підтверджена знахідка — тук-тук із фото, знятим на місці" },
  { id: "basket", title: "Грибний кошик", tier: "silver", group: "finds", metric: "finds", target: 10,
    how: "10 підтверджених знахідок" },
  { id: "full_basket", title: "Повний кошик", tier: "gold", group: "finds", metric: "finds", target: 50,
    how: "50 підтверджених знахідок" },
  // Колекція видів за сезон (календарний рік)
  { id: "collection_5", title: "Колекція: 5 видів", tier: "bronze", group: "species", metric: "species_season", target: 5,
    how: "5 різних видів у підтверджених знахідках за сезон" },
  { id: "collection_10", title: "Колекція: 10 видів", tier: "silver", group: "species", metric: "species_season", target: 10,
    how: "10 різних видів у підтверджених знахідках за сезон" },
  { id: "season_forager", title: "Грибник сезону", tier: "gold", group: "species", metric: "species_season", target: 20,
    how: "20 різних видів у підтверджених знахідках за сезон" },
  // Окремі види
  { id: "king_of_forest", title: "Король лісу", tier: "gold", group: "species", metric: "porcini", target: 10,
    how: "10 підтверджених знахідок білого гриба" },
  { id: "chanterelle_trail", title: "Лисичкова стежка", tier: "silver", group: "species", metric: "chanterelle", target: 10,
    how: "10 підтверджених знахідок лисичок" },
  { id: "rare_guardian", title: "Охоронець рідкісних", tier: "gold", group: "species", metric: "red_book_private", target: 1,
    how: "Сфотографувати вид із Червоної книги України й лишити точку приватною — не зривати й не виказувати місце" },
  // Походи з Наглядачем
  { id: "first_hike", title: "Перший похід", tier: "bronze", group: "hikes", metric: "hikes_safe", target: 1,
    how: "Перший похід із Наглядачем, завершений «Я вдома»" },
  { id: "wanderer", title: "Мандрівник", tier: "silver", group: "hikes", metric: "hikes_safe", target: 10,
    how: "10 походів із Наглядачем, завершених «Я вдома»" },
  { id: "forest_veteran", title: "Лісовий ветеран", tier: "gold", group: "hikes", metric: "hikes_safe", target: 50,
    how: "50 походів із Наглядачем, завершених «Я вдома»" },
  { id: "ready_for_forest", title: "Готовий до лісу", tier: "bronze", group: "hikes", metric: "hikes_checklist", target: 10,
    how: "10 походів із Наглядачем, перед якими пройдено чек-лист" },
  { id: "home_on_time", title: "Вчасно вдома", tier: "silver", group: "hikes", metric: "hikes_on_time", target: 10,
    how: "10 походів, завершених «Я вдома» до запланованого часу повернення, без тривог" },
  { id: "own_footsteps", title: "Своїм слідом", tier: "silver", group: "hikes", metric: "hikes_home_nav", target: 5,
    how: "5 походів, з яких ви повернулися за допомогою «Додому»" },
  // Наглядач і друзі
  { id: "under_watch", title: "Під наглядом", tier: "bronze", group: "friends", metric: "has_guardian", target: 1,
    how: "Друг погодився бути вашим Наглядачем" },
  { id: "loyal_guardian", title: "Вірний Наглядач", tier: "silver", group: "friends", metric: "guarded_hikes", target: 5,
    how: "Бути Наглядачем у 5 походах друзів" },
  { id: "mushroom_company", title: "Грибна компанія", tier: "bronze", group: "friends", metric: "friends", target: 5,
    how: "5 друзів у застосунку" },
  { id: "invited_friend", title: "Запросив друга", tier: "silver", group: "friends", metric: null, target: 1,
    how: "Запрошений вами друг зареєструвався й пройшов перший похід" },
  // Знання
  { id: "twin_expert", title: "Знавець двійників", tier: "silver", group: "knowledge", metric: null, target: 1,
    how: "Скласти тест «Двійники» — як відрізнити їстівні гриби від отруйних" },
  { id: "mycologist", title: "Грибознавець", tier: "gold", group: "knowledge", metric: null, target: 1,
    how: "Отримати сертифікат знань — скласти всі тести" },
  { id: "recognizer", title: "Розпізнавач", tier: "bronze", group: "knowledge", metric: "ai_match", target: 10,
    how: "10 підтверджених знахідок, де розпізнавання на телефоні підказало той самий вид" },
  // Сезони
  { id: "spring_morels", title: "Весняні зморшки", tier: "bronze", group: "seasons", metric: "morels_spring", target: 1,
    how: "Підтверджена знахідка зморшка (сморчка) у березні–травні" },
  { id: "winter_honey", title: "Зимові опеньки", tier: "silver", group: "seasons", metric: "winter_honey", target: 1,
    how: "Підтверджена знахідка зимового опенька у грудні–лютому" },
];

export const TIER_LABEL: Record<TrophyTier, string> = { bronze: "Бронза", silver: "Срібло", gold: "Золото" };
export const SOON_LABEL = "Скоро — з'явиться разом із новою функцією";

export type TrophyStats = Partial<Record<TrophyMetric, number>>;

export interface TrophyView {
  id: string;
  title: string;
  tier: TrophyTier;
  tier_label: string;
  how_label: string;
  earned: boolean;
  earned_at: string | null;
  /** «3 з 10» — поки не отримано; `null` для «так / ні» (ціль 1) і для «скоро». */
  progress_label: string | null;
  /** 0…1 — смужка прогресу. */
  progress: number;
  soon: boolean;
}

/** Які трофеї вже виконано за показниками (для запису в `user_trophies`). */
export function newlyEarned(stats: TrophyStats, earned: Set<string>): string[] {
  return TROPHIES.filter((t) => t.metric !== null && !earned.has(t.id) && (stats[t.metric] ?? 0) >= t.target).map((t) => t.id);
}

/** Каталог для екрана: отримані — згори за датою, далі — найближчі до отримання. */
export function trophyViews(stats: TrophyStats, earned: Map<string, string>): TrophyView[] {
  const views = TROPHIES.map((t): TrophyView => {
    const at = earned.get(t.id) ?? null;
    const value = t.metric === null ? 0 : Math.min(stats[t.metric] ?? 0, t.target);
    const soon = t.metric === null && at === null;
    return {
      id: t.id,
      title: t.title,
      tier: t.tier,
      tier_label: TIER_LABEL[t.tier],
      how_label: t.how,
      earned: at !== null,
      earned_at: at,
      progress_label: at !== null || soon || t.target === 1 ? null : `${value} з ${t.target}`,
      progress: at !== null ? 1 : t.target > 0 ? value / t.target : 0,
      soon,
    };
  });
  const order = new Map(TROPHIES.map((t, i) => [t.id, i]));
  return views.sort((a, b) =>
    Number(b.earned) - Number(a.earned) ||
    (a.earned && b.earned ? (b.earned_at ?? "").localeCompare(a.earned_at ?? "") : 0) ||
    Number(a.soon) - Number(b.soon) ||
    (a.earned ? 0 : b.progress - a.progress) ||
    order.get(a.id)! - order.get(b.id)!
  );
}

/** Для публічного профілю — лише отримані (id, назва, метал, коли). */
export function earnedPublic(earned: Map<string, string>) {
  return TROPHIES.filter((t) => earned.has(t.id))
    .map((t) => ({ id: t.id, title: t.title, tier: t.tier, earned_at: earned.get(t.id)! }))
    .sort((a, b) => b.earned_at.localeCompare(a.earned_at));
}

export interface TrophyDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

/** Отримані трофеї користувача: id → коли. */
export async function loadEarned(db: TrophyDb, userId: string): Promise<Map<string, string>> {
  const { data, error } = await db.from("user_trophies").select("trophy_id, earned_at").eq("user_id", userId);
  if (error) throw error;
  return new Map(((data ?? []) as Array<{ trophy_id: string; earned_at: string }>).map((r) => [r.trophy_id, r.earned_at]));
}

/** Перерахувати показники, записати нові трофеї, повернути каталог і показники. */
export async function refreshTrophies(db: TrophyDb, userId: string, now: Date) {
  const { data, error } = await db.rpc("trophy_stats", { p_user: userId, p_now: now.toISOString() });
  if (error) throw error;
  const stats = (data ?? {}) as TrophyStats;
  const earned = await loadEarned(db, userId);
  const fresh = newlyEarned(stats, new Set(earned.keys()));
  if (fresh.length > 0) {
    const at = now.toISOString();
    const { error: e2 } = await db.from("user_trophies")
      .upsert(fresh.map((id) => ({ user_id: userId, trophy_id: id, earned_at: at })), { onConflict: "user_id,trophy_id", ignoreDuplicates: true });
    if (e2) throw e2;
    for (const id of fresh) earned.set(id, at);
  }
  return { stats, earned, fresh, views: trophyViews(stats, earned) };
}
