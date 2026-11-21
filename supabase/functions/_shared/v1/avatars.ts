// ============================================================================
// Аватар — готові картинки (рішення PO 2026-11-21, ADR-021 §21.7): конструктор прибрано.
//
// 40 аватарів у шести рівнях (ADR-013), рамка показує рівень: береза → дуб → живий вінок →
// камінь із рогами → бронза → золото з короною. Картинки — у застосунку
// (`assets/avatars/<id>.webp`), тут — список і хто що відкрив. Новий аватар = картинка в
// застосунку + рядок тут, без змін БД. За замовчуванням (і для старих наліпок/грибів) —
// перший «Мандрівник».
// ============================================================================

import { HttpError } from "../http.ts";
import { type Level, levelOf } from "./profile-rules.ts";

export type Avatar = { kind: "preset"; id: string };

export interface PresetAvatar {
  id: string;
  /** Гриб і роль — підпис у виборі аватара. */
  title: string;
  role: string;
  /** З якого рівня відкривається (ADR-013). */
  level: Level["id"];
}

const LEVEL_ORDER: Level["id"][] = ["traveler", "tracker", "expert", "forester", "keeper", "master"];

export const LEVEL_TITLES: Record<Level["id"], string> = {
  traveler: "Мандрівник",
  tracker: "Слідопит",
  expert: "Грибознавець",
  forester: "Лісовик",
  keeper: "Хранитель лісу",
  master: "Грибний Майстер",
};

const p = (level: Level["id"], n: number, title: string, role: string): PresetAvatar => ({
  id: `${level}_${String(n).padStart(2, "0")}`,
  title,
  role,
  level,
});

/** Готові аватари — у порядку показу (рівень, номер). */
export const PRESET_AVATARS: PresetAvatar[] = [
  p("traveler", 1, "Білий гриб", "Мандрівник"),
  p("traveler", 2, "Лисичка", "Збирачка"),
  p("traveler", 3, "Підберезник", "Картограф"),
  p("traveler", 4, "Підосиковик", "Вартовий"),
  p("traveler", 5, "Маслюк", "Під дощем"),
  p("traveler", 6, "Рижик", "Шукач"),
  p("traveler", 7, "Сироїжка", "Травниця"),
  p("traveler", 8, "Печериця", "На світанку"),
  p("traveler", 9, "Дощовик", "Спостерігач"),
  p("traveler", 10, "Моховик", "Провідник"),
  p("tracker", 1, "Парасолька", "Читач слідів"),
  p("tracker", 2, "Сморж", "Весняний слідопит"),
  p("tracker", 3, "Опеньок", "Верхолаз"),
  p("tracker", 4, "Рядовка фіолетова", "Дозорець"),
  p("tracker", 5, "Грузд", "Сигнальник"),
  p("tracker", 6, "Глива", "Нічний слідопит"),
  p("tracker", 7, "Їжовик жовтий", "Мітить шлях"),
  p("tracker", 8, "Підмолочник", "Знахідка"),
  p("expert", 1, "Дубовик крапчастий", "Знавець синяви"),
  p("expert", 2, "Ковпак кільчастий", "Відбиток спор"),
  p("expert", 3, "Гнойовик білий", "Літописець"),
  p("expert", 4, "Трутовик сірчано-жовтий", "Збирач зразків"),
  p("expert", 5, "Їжовик гребінчастий", "Охоронець рідкісного"),
  p("expert", 6, "Опеньок лучний", "Знавець атласів"),
  p("expert", 7, "Трюфель літній", "Шукач прихованого"),
  p("forester", 1, "Гриб-баран", "Старійшина лісу"),
  p("forester", 2, "Трутовик лакований", "Хранитель світла"),
  p("forester", 3, "Спарасис кучерявий", "Садівник лісу"),
  p("forester", 4, "Трутовик справжній", "Вогнищанин"),
  p("forester", 5, "Мухомор червоний", "Кличе ліс"),
  p("forester", 6, "Опеньок зимовий", "Зимовий лісовик"),
  p("keeper", 1, "Боровик королівський", "Вартовий галявини"),
  p("keeper", 2, "Земляна зірка", "Світить дорогу додому"),
  p("keeper", 3, "Гомфус", "Хранитель джерел"),
  p("keeper", 4, "Лійочник", "Нічний вартовий"),
  p("keeper", 5, "Трутовик зонтичний", "Хранитель старих дерев"),
  p("master", 1, "Цезарів мухомор", "Володар лісу"),
  p("master", 2, "Великий боровик", "Легендарний мандрівник"),
  p("master", 3, "Трюфель троїцький", "Хранитель віків"),
  p("master", 4, "Їжовик коралоподібний", "Майстер грибниці"),
];

export const DEFAULT_AVATAR: Avatar = { kind: "preset", id: "traveler_01" };

/** Що показувати: відомий готовий аватар або перший «Мандрівник». */
export function publicAvatar(stored: Record<string, unknown> | null | undefined): Avatar {
  const id = stored?.kind === "preset" && typeof stored.id === "string" ? stored.id : null;
  return id && PRESET_AVATARS.some((a) => a.id === id) ? { kind: "preset", id } : DEFAULT_AVATAR;
}

/**
 * Чи відкритий аватар. Рівні йдуть по порядку; «Грибознавець» (сертифікат знань, ADR-012) —
 * між «Слідопитом» і «Лісовиком», тож його аватари відкриває й «Лісовик».
 */
function isOpen(avatar: PresetAvatar, rating: number): boolean {
  return LEVEL_ORDER.indexOf(avatar.level) <= LEVEL_ORDER.indexOf(levelOf(rating).id);
}

function lockLabel(level: Level["id"]): string {
  if (level === "expert") return "Відкриється на рівні «Грибознавець» або «Лісовик»";
  return `Відкриється на рівні «${LEVEL_TITLES[level]}»`;
}

/** Вибір аватара: лише готовий зі списку й відкритий рівнем користувача. */
export function validatePresetAvatar(raw: unknown, rating: number): Avatar {
  const a = raw as Record<string, unknown> | null;
  const preset = a && typeof a === "object" && a.kind === "preset" ? PRESET_AVATARS.find((x) => x.id === a.id) : undefined;
  if (!preset) throw new HttpError(400, "invalid_avatar", "Оберіть один із готових аватарів");
  if (!isOpen(preset, rating)) throw new HttpError(403, "avatar_locked", lockLabel(preset.level));
  return { kind: "preset", id: preset.id };
}

/** Вибір аватара (`GET v1-me?avatars=1`): групи за рівнями, замки з причиною — вирішує сервер. */
export function avatarChoices(stored: Record<string, unknown> | null | undefined, rating: number, isGuest: boolean) {
  return {
    current: publicAvatar(stored),
    can_change: !isGuest,
    reason_label: isGuest ? "Змінити аватар можна після входу через Google або Apple" : null,
    groups: LEVEL_ORDER.map((level) => {
      const open = PRESET_AVATARS.some((a) => a.level === level && isOpen(a, rating));
      return {
        level,
        label: LEVEL_TITLES[level],
        open,
        lock_label: open ? null : lockLabel(level),
        avatars: PRESET_AVATARS.filter((a) => a.level === level).map((a) => ({
          id: a.id,
          title: a.title,
          role: a.role,
          open: isOpen(a, rating),
        })),
      };
    }),
  };
}
