// ============================================================================
// Аватар — готові картинки (рішення PO 2026-11-21, ADR-021 §21.7): конструктор прибрано.
//
// Набір готових аватарів більший і відкривається рівнем (ADR-013). Поки картинок немає —
// у всіх аватар-заглушка `default` (застосунок малює силует грибника). Картинки додаватимуться
// в застосунок (`assets/avatars/<id>.webp`) разом із записом тут — без змін схеми БД.
// Старі збережені значення (стандартні гриби, наліпки конструктора) показуються як `default`.
// ============================================================================

import { HttpError } from "../http.ts";
import { type Level, levelOf } from "./profile-rules.ts";

export type Avatar = { kind: "preset"; id: string };

export interface PresetAvatar {
  id: string;
  title: string;
  /** З якого рівня відкривається (ADR-013). */
  level: Level["id"];
}

/** Готові аватари. Порожньо, доки не готові картинки; перший — для 1-го рівня («Мандрівник»). */
export const PRESET_AVATARS: PresetAvatar[] = [];

export const DEFAULT_AVATAR: Avatar = { kind: "preset", id: "default" };

const LEVEL_ORDER: Level["id"][] = ["traveler", "tracker", "expert", "forester", "keeper", "master"];

/** Що показувати іншим: відомий готовий аватар або заглушка. */
export function publicAvatar(stored: Record<string, unknown> | null | undefined): Avatar {
  const id = stored?.kind === "preset" && typeof stored.id === "string" ? stored.id : null;
  return id && PRESET_AVATARS.some((p) => p.id === id) ? { kind: "preset", id } : DEFAULT_AVATAR;
}

/** Вибір аватара: лише готовий зі списку й відкритий рівнем користувача. */
export function validatePresetAvatar(raw: unknown, rating: number): Avatar {
  const a = raw as Record<string, unknown> | null;
  const preset = a && typeof a === "object" && a.kind === "preset" ? PRESET_AVATARS.find((p) => p.id === a.id) : undefined;
  if (!preset) throw new HttpError(400, "invalid_avatar", "Оберіть один із готових аватарів");
  const mine = LEVEL_ORDER.indexOf(levelOf(rating).id);
  if (LEVEL_ORDER.indexOf(preset.level) > mine) {
    throw new HttpError(403, "avatar_locked", "Цей аватар відкривається на вищому рівні");
  }
  return { kind: "preset", id: preset.id };
}
