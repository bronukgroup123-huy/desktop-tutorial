// ============================================================================
// POST v1-forecast — прогноз для точки з готовими підписами (Response Shaping)
// (BACKEND_PLAN B2.1)
//
// Body: { lat, lng, date: YYYY-MM-DD, forestType? }
// 200 { data: { regionName, date, forest, top1, alternative, warnings, noDataReason? } }
// 400 invalid_body · 401 · 403 outside_home_region · 404 me_not_found ·
// 409 home_region_required · 429 · 500
//
// Заборона №1 (маніфест): жодних чисел-ймовірностей у відповіді — тільки рівні з
// готовими підписами й кольорами. RegionGuard — завжди, за Home Region з профілю.
// ============================================================================

import { z } from "npm:zod@3";
import type { ScoredSpecies, WeatherData } from "../forecast/types.ts";
import { whenLabel, whyLabels } from "./forecast-labels.ts";
import { HttpError } from "../http.ts";

export const ForecastInputSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  forestType: z.string().max(32).optional(),
});
export type ForecastBody = z.infer<typeof ForecastInputSchema>;

export type ProbabilityLevel = "no_data" | "low" | "medium" | "high" | "peak";

export const LEVEL_LABEL: Record<ProbabilityLevel, string> = {
  peak: "Пікова ймовірність",
  high: "Висока ймовірність",
  medium: "Середня ймовірність",
  low: "Низька ймовірність",
  no_data: "Недостатньо даних",
};

export const LEVEL_COLOR: Record<ProbabilityLevel, string> = {
  peak: "#10b981",
  high: "#22c55e",
  medium: "#eab308",
  low: "#f97316",
  no_data: "#94a3b8",
};

export function normalizeLevel(p: string): ProbabilityLevel {
  return (["peak", "high", "medium", "low", "no_data"] as const).includes(p as ProbabilityLevel)
    ? p as ProbabilityLevel
    : "no_data";
}

/** Вид у відповіді: тільки рівень і готові підписи — без score / probability. */
export function shapeSpecies(
  s: ScoredSpecies | null,
  weather: WeatherData | null | undefined = null,
): Record<string, unknown> | null {
  if (!s) return null;
  const level = normalizeLevel(s.probability);
  return {
    mushroom_type: s.mushroom_type,
    name_ua: s.name_ua,
    level,
    level_label: LEVEL_LABEL[level],
    level_color: LEVEL_COLOR[level],
    when_label: whenLabel(s.wave, weather),
    where_label: s.where ?? "У лісі, де ростуть дерева-симбіонти цього виду",
    why_labels: whyLabels(s.matched, weather),
  };
}

export function parseForecastBody(body: unknown): ForecastBody {
  const r = ForecastInputSchema.safeParse(body);
  if (!r.success) {
    const issue = r.error.issues[0];
    throw new HttpError(
      400,
      "invalid_body",
      issue ? `${issue.path.join(".") || "body"}: ${issue.message}` : "Некоректне тіло запиту",
    );
  }
  return r.data;
}

/** Точка має бути в Home Region (ADR-015 §15.2). Не залежить від feature flag. */
export async function assertPointInHomeRegion(
  db: { rpc(fn: string, p: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }> },
  lat: number,
  lng: number,
  regionId: number,
): Promise<void> {
  const { data, error } = await db.rpc("point_in_region", {
    lat,
    lng,
    region_id: regionId,
  });
  if (error) {
    console.error("[v1-forecast] point_in_region failed:", error);
    throw new HttpError(500, "db_error", "Не вдалося перевірити область");
  }
  if (data !== true) {
    throw new HttpError(403, "outside_home_region", "Точка поза вашою областю. Прогноз доступний лише у своїй області.");
  }
}

