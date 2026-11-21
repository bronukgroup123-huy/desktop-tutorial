// ============================================================================
// Трофеї-медальйони (ADR-021 §21.2.2, §21.10; рішення PO 2026-11-21)
//
// 24 трофеї: за що й скільки — тут (сервер вирішує, клієнт лише малює). Отриманий трофей
// зберігається в `user_trophies` і не забирається. Картинки — `assets/trophies/<id>.webp`.
//
// ЯК ПЕРЕВІРЯЄМО (щоб трофей означав справжнє досягнення, а не натискання кнопок):
//  • Знахідка зараховується, лише якщо фото пройшло перевірку місця й часу зйомки (EXIF ≤ 1 км
//    і ≤ 24 год від точки), точка не відхилена й не видалена.
//  • Одне місце за день — одна знахідка: точки того самого дня ближче 50 м одна від одної
//    рахуються раз (10 фото одного гриба чи сімейка білих під одним дубом — це одна знахідка).
//    Для видових трофеїв — те саме, але окремо для кожного виду.
//  • У залік — не більше 5 знахідок на день (проти «накрутки» за один вихід).
//  • Вид підтверджено — якщо розпізнавання на телефоні першою підказкою назвало той самий вид
//    із рівнем «найімовірніше» або «можливо» (ai_check.top[0]), або фото перевірив модератор
//    (verification_status = verified). Вид, який просто вибрали зі списку, для видових трофеїв
//    не рахується. Види, яких розпізнавання не знає (усі з Червоної книги), — лише модератор.
//  • Похід — з Наглядачем, завершений «Я вдома», не коротший за 30 хв, пройдено ≥ 1 км
//    (≥ 10 точок треку з добрим GPS); у залік — один похід на день. SQL `trophy_stats`.
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
    how: "Перша знахідка — тук-тук із фото, знятим на місці (перевіряємо місце й час зйомки)" },
  { id: "basket", title: "Грибний кошик", tier: "silver", group: "finds", metric: "finds", target: 10,
    how: "10 знахідок у різних місцях — тук-туки з фото, знятим на місці" },
  { id: "full_basket", title: "Повний кошик", tier: "gold", group: "finds", metric: "finds", target: 50,
    how: "50 знахідок у різних місцях — тук-туки з фото, знятим на місці" },
  // Колекція видів за сезон (календарний рік)
  { id: "collection_5", title: "Колекція: 5 видів", tier: "bronze", group: "species", metric: "species_season", target: 5,
    how: "5 різних видів за сезон — вид підтверджує розпізнавання на телефоні або модератор" },
  { id: "collection_10", title: "Колекція: 10 видів", tier: "silver", group: "species", metric: "species_season", target: 10,
    how: "10 різних видів за сезон — вид підтверджує розпізнавання на телефоні або модератор" },
  { id: "season_forager", title: "Грибник сезону", tier: "gold", group: "species", metric: "species_season", target: 20,
    how: "20 різних видів за сезон — вид підтверджує розпізнавання на телефоні або модератор" },
  // Окремі види
  { id: "king_of_forest", title: "Король лісу", tier: "gold", group: "species", metric: "porcini", target: 10,
    how: "Білий гриб у 10 різних місцях — вид підтверджує розпізнавання на телефоні або модератор" },
  { id: "chanterelle_trail", title: "Лисичкова стежка", tier: "silver", group: "species", metric: "chanterelle", target: 10,
    how: "Лисички в 10 різних місцях — вид підтверджує розпізнавання на телефоні або модератор" },
  { id: "rare_guardian", title: "Охоронець рідкісних", tier: "gold", group: "species", metric: "red_book_private", target: 1,
    how: "Сфотографувати вид із Червоної книги України, не зривати й лишити точку приватною — фото перевіряє модератор" },
  // Походи з Наглядачем
  { id: "first_hike", title: "Перший похід", tier: "bronze", group: "hikes", metric: "hikes_safe", target: 1,
    how: "Перший похід із Наглядачем: від 30 хв і 1 км, завершений «Я вдома»" },
  { id: "wanderer", title: "Мандрівник", tier: "silver", group: "hikes", metric: "hikes_safe", target: 10,
    how: "10 походів із Наглядачем (від 30 хв і 1 км, «Я вдома»; один на день)" },
  { id: "forest_veteran", title: "Лісовий ветеран", tier: "gold", group: "hikes", metric: "hikes_safe", target: 50,
    how: "50 походів із Наглядачем (від 30 хв і 1 км, «Я вдома»; один на день)" },
  { id: "ready_for_forest", title: "Готовий до лісу", tier: "bronze", group: "hikes", metric: "hikes_checklist", target: 10,
    how: "10 походів із Наглядачем, перед якими пройдено весь чек-лист" },
  { id: "home_on_time", title: "Вчасно вдома", tier: "silver", group: "hikes", metric: "hikes_on_time", target: 10,
    how: "10 походів, з яких ви повернулися вчасно: не пізніше запланованого й не раніше ніж за 1,5 год, без тривог" },
  { id: "own_footsteps", title: "Своїм слідом", tier: "silver", group: "hikes", metric: "hikes_home_nav", target: 5,
    how: "5 походів, з яких ви повернулися за допомогою «Додому»" },
  // Наглядач і друзі
  { id: "under_watch", title: "Під наглядом", tier: "bronze", group: "friends", metric: "has_guardian", target: 1,
    how: "Друг погодився бути вашим Наглядачем" },
  { id: "loyal_guardian", title: "Вірний Наглядач", tier: "silver", group: "friends", metric: "guarded_hikes", target: 5,
    how: "Бути Наглядачем у 5 завершених походах друзів" },
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
    how: "10 знахідок у різних місцях, де розпізнавання на телефоні першим назвало вибраний вид" },
  // Сезони
  { id: "spring_morels", title: "Весняні зморшки", tier: "bronze", group: "seasons", metric: "morels_spring", target: 1,
    how: "Зморшок (сморчок) у березні–травні — вид підтверджує розпізнавання або модератор" },
  { id: "winter_honey", title: "Зимові опеньки", tier: "silver", group: "seasons", metric: "winter_honey", target: 1,
    how: "Зимовий опеньок у грудні–лютому — вид підтверджує розпізнавання або модератор" },
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

// ─── Знахідки: що зараховувати ──────────────────────────────────────────────

/** Рядок `trophy_finds`: підтверджена фото знахідка (координати — лише для «одне місце»). */
export interface FindRow {
  species_id: string | null;
  pick_type: string;
  lat: number;
  lng: number;
  /** Місцевий час (Київ) без поясу: «2026-09-10T10:00:00». */
  local_at: string;
  ai_species: string | null;
  ai_level: string | null;
  moderated: boolean;
  red_listed: boolean;
}

export const SAME_PLACE_M = 50;
export const MAX_FINDS_PER_DAY = 5;

function distanceM(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const r = (x: number) => (x * Math.PI) / 180;
  const h = Math.sin(r(b.lat - a.lat) / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(r(b.lng - a.lng) / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

/** Вид підтверджено: розпізнавання на телефоні першим назвало цей вид (найімовірніше / можливо) або модератор. */
export function speciesConfirmed(f: FindRow): boolean {
  if (!f.species_id || f.species_id === "unknown") return false;
  return f.moderated || aiAgrees(f);
}

function aiAgrees(f: FindRow): boolean {
  return !!f.species_id && f.ai_species === f.species_id && (f.ai_level === "high" || f.ai_level === "medium");
}

/**
 * Залік знахідок: одне місце за день (ближче [SAME_PLACE_M] — те саме місце), не більше
 * [MAX_FINDS_PER_DAY] на день. [key] групує окремо (наприклад, за видом); `null` — усі разом.
 */
export function countPlaces(rows: FindRow[], key: (f: FindRow) => string | null = () => "all"): number {
  const byDay = new Map<string, Array<{ lat: number; lng: number }>>();
  let n = 0;
  for (const f of rows) {
    const k = key(f);
    if (k === null) continue;
    const day = `${f.local_at.slice(0, 10)}|${k}`;
    const places = byDay.get(day) ?? [];
    if (places.length >= MAX_FINDS_PER_DAY) continue;
    if (places.some((p) => distanceM(p, f) < SAME_PLACE_M)) continue;
    places.push({ lat: f.lat, lng: f.lng });
    byDay.set(day, places);
    n++;
  }
  return n;
}

const month = (f: FindRow) => Number(f.local_at.slice(5, 7));
const year = (f: FindRow) => Number(f.local_at.slice(0, 4));

/** Показники знахідок для трофеїв (сезон — календарний рік за Києвом). */
export function findMetrics(rows: FindRow[], now: Date): TrophyStats {
  const sorted = [...rows].sort((a, b) => a.local_at.localeCompare(b.local_at));
  const kyivYear = Number(new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Kyiv", year: "numeric" }).format(now));
  const confirmed = sorted.filter(speciesConfirmed);
  const bySpecies = (f: FindRow) => f.species_id;
  const only = (pred: (f: FindRow) => boolean) => (f: FindRow) => (pred(f) ? f.species_id : null);
  return {
    finds: countPlaces(sorted),
    species_season: new Set(confirmed.filter((f) => year(f) === kyivYear).map((f) => f.species_id)).size,
    porcini: countPlaces(confirmed, only((f) => f.species_id === "boletus_edulis")),
    chanterelle: countPlaces(confirmed, only((f) => (f.species_id ?? "").startsWith("cantharellus_"))),
    red_book_private: countPlaces(confirmed, only((f) => f.red_listed && f.pick_type === "private")),
    ai_match: countPlaces(sorted.filter(aiAgrees), bySpecies),
    morels_spring: countPlaces(confirmed, only((f) => (f.species_id ?? "").startsWith("morchella_") && month(f) >= 3 && month(f) <= 5)),
    winter_honey: countPlaces(confirmed, only((f) => f.species_id === "flammulina_velutipes" && [12, 1, 2].includes(month(f)))),
  };
}

/** Скільки знахідок у заліку (для профілю «N знахідок»). */
export async function countFinds(db: TrophyDb, userId: string): Promise<number | null> {
  const { data, error } = await db.rpc("trophy_finds", { p_user: userId });
  if (error || !Array.isArray(data)) return null;
  return countPlaces([...(data as FindRow[])].sort((a, b) => a.local_at.localeCompare(b.local_at)));
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
  const [{ data, error }, { data: finds, error: e1 }] = await Promise.all([
    db.rpc("trophy_stats", { p_user: userId, p_now: now.toISOString() }),
    db.rpc("trophy_finds", { p_user: userId }),
  ]);
  if (error) throw error;
  if (e1) throw e1;
  const stats: TrophyStats = { ...((data ?? {}) as TrophyStats), ...findMetrics((finds ?? []) as FindRow[], now) };
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
