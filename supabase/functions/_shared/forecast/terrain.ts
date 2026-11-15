// ============================================================================
// Рельєф і ґрунт ділянки (рішення PO 2026-11-15, ADR-015 §15.8 п.15)
//
//  * Рельєф — висоти 9 точок квадрата (Open-Meteo Elevation API, DEM 90 м): центр нижче за
//    кільце на 15+ м — низина (вологіше, холодніше, заморозки), вище — пагорб (сухіше).
//  * Ґрунт — частка піску й глини шару 0–5 см (ISRIC SoilGrids): піщаний ґрунт після дощу
//    пересихає швидше, глинистий тримає вологу довше.
// Визначається один раз на ділянку (зберігається з ділянкою) і змінює параметри рушія
// плодоношення — без нових таблиць правил.
// ============================================================================

import type { FruitingParams } from "./fruiting.ts";

export type Relief = "valley" | "hill" | "flat";
export type SoilTexture = "sandy" | "loam" | "clay";

export interface Terrain {
  /** Висота центру ділянки, м. */
  elevation: number | null;
  relief: Relief | null;
  /** Перепад висот у квадраті, м. */
  reliefRange: number | null;
  /** Частка піску / глини у верхньому шарі ґрунту, %. */
  sand: number | null;
  clay: number | null;
  soil: SoilTexture | null;
  fetchedAt: string;
}

/** Перепад центру до кільця, за якого центр — низина / пагорб, м. */
export const RELIEF_STEP_M = 15;

export function reliefOf(center: number, ring: number[]): { relief: Relief; range: number } {
  const all = [center, ...ring];
  const range = Math.round(Math.max(...all) - Math.min(...all));
  const mean = ring.reduce((s, x) => s + x, 0) / ring.length;
  const relief: Relief = center <= mean - RELIEF_STEP_M ? "valley" : center >= mean + RELIEF_STEP_M ? "hill" : "flat";
  return { relief, range };
}

/** Текстура за часткою піску й глини (спрощено за трикутником USDA). */
export function soilOf(sand: number | null, clay: number | null): SoilTexture | null {
  if (sand === null || clay === null) return null;
  if (sand >= 65 && clay < 15) return "sandy";
  if (clay >= 35) return "clay";
  return "loam";
}

/** Точки квадрата: центр, 4 кути і 4 середини сторін (на півдорозі до краю). */
export function samplePoints(lat: number, lng: number, sizeKm: number): Array<[number, number]> {
  const dLat = (sizeKm / 2) / 111.32;
  const dLng = (sizeKm / 2) / (111.32 * Math.cos((lat * Math.PI) / 180));
  const pts: Array<[number, number]> = [[lat, lng]];
  for (const [a, b] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) pts.push([lat + a * dLat * 0.9, lng + b * dLng * 0.9]);
  for (const [a, b] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) pts.push([lat + a * dLat * 0.5, lng + b * dLng * 0.5]);
  return pts;
}

type Fetch = (url: string) => Promise<Response>;

async function getJson(fetchFn: Fetch, url: string): Promise<unknown | null> {
  try {
    const res = await fetchFn(url);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

/** Відповідь Elevation API → рельєф (null — немає даних). */
export function parseElevation(json: unknown): { elevation: number; relief: Relief; range: number } | null {
  const e = (json as { elevation?: unknown })?.elevation;
  if (!Array.isArray(e) || e.length < 5 || !e.every((x) => typeof x === "number" && Number.isFinite(x))) return null;
  const [center, ...ring] = e as number[];
  return { elevation: Math.round(center), ...reliefOf(center, ring) };
}

/** Відповідь SoilGrids → частки піску й глини, % (mean у г/кг × d_factor). */
export function parseSoilGrids(json: unknown): { sand: number | null; clay: number | null } {
  const layers = (json as { properties?: { layers?: unknown[] } })?.properties?.layers ?? [];
  const pick = (name: string): number | null => {
    const l = layers.find((x) => (x as { name?: string })?.name === name) as
      | { unit_measure?: { d_factor?: number }; depths?: Array<{ values?: { mean?: number | null } }> }
      | undefined;
    const mean = l?.depths?.[0]?.values?.mean;
    if (typeof mean !== "number") return null;
    const factor = l?.unit_measure?.d_factor ?? 10;
    return Math.round(mean / factor / 10); // г/кг → %
  };
  return { sand: pick("sand"), clay: pick("clay") };
}

/** Рельєф і ґрунт ділянки; частина недоступна — відповідні поля null. */
export async function fetchTerrain(lat: number, lng: number, sizeKm: number, fetchFn: Fetch = fetch): Promise<Terrain> {
  const pts = samplePoints(lat, lng, sizeKm);
  const elevUrl = "https://api.open-meteo.com/v1/elevation?" + new URLSearchParams({
    latitude: pts.map((p) => p[0].toFixed(4)).join(","),
    longitude: pts.map((p) => p[1].toFixed(4)).join(","),
  });
  const soilUrl = "https://rest.isric.org/soilgrids/v2.0/properties/query?" + new URLSearchParams([
    ["lon", lng.toFixed(4)], ["lat", lat.toFixed(4)],
    ["property", "sand"], ["property", "clay"], ["depth", "0-5cm"], ["value", "mean"],
  ]);
  const [elev, soil] = await Promise.all([getJson(fetchFn, elevUrl), getJson(fetchFn, soilUrl)]);
  const r = parseElevation(elev);
  const s = parseSoilGrids(soil);
  return {
    elevation: r?.elevation ?? null,
    relief: r?.relief ?? null,
    reliefRange: r?.range ?? null,
    sand: s.sand,
    clay: s.clay,
    soil: soilOf(s.sand, s.clay),
    fetchedAt: new Date().toISOString(),
  };
}

/**
 * Параметри плодоношення з поправкою на місце: пісок пересихає швидше (посуха зриває
 * дозрівання за 7 днів, «вологий ґрунт» — від 14 мм), глина тримає вологу довше; низина —
 * прохолодніший ґрунт і волога затримується, пагорб — сухіше.
 */
export function terrainAdjust(p: FruitingParams, t: Pick<Terrain, "relief" | "soil"> | null | undefined): FruitingParams {
  if (!t || (!t.relief && !t.soil)) return p;
  const out: FruitingParams = { ...p };
  if (t.soil === "sandy") {
    out.abortDryDays = 7;
    out.primedRainMm = 14;
  } else if (t.soil === "clay") {
    out.abortDryDays = 13;
  }
  if (t.relief === "valley") {
    out.soilTOffset = -0.7;
    out.primedRainMm = (out.primedRainMm ?? 10) - 2;
  } else if (t.relief === "hill") {
    out.soilTOffset = 0.3;
    out.abortDryDays = (out.abortDryDays ?? 10) - 1;
  }
  return out;
}

/** Ключ для кешу станів рушія: той самий вид на іншому рельєфі — інший розрахунок. */
export const terrainKey = (t: Pick<Terrain, "relief" | "soil"> | null | undefined) => (t ? `${t.relief ?? "-"}/${t.soil ?? "-"}` : "");

const RELIEF_LABEL: Record<Relief, string> = {
  valley: "низина — вологіше й прохолодніше, вранці заморозки",
  hill: "підвищення — сухіше, ґрунт прогрівається краще",
  flat: "рівнина",
};
const SOIL_LABEL: Record<SoilTexture, string> = {
  sandy: "піщаний — після дощу пересихає швидше",
  loam: "суглинок — вологу тримає помірно",
  clay: "глинистий — вологу тримає довго",
};

/** «Рельєф: низина — вологіше… · Ґрунт: піщаний — …» для блоку лісу; нічого не відомо — null. */
export function terrainLabel(t: Pick<Terrain, "relief" | "soil"> | null | undefined): string | null {
  if (!t) return null;
  const parts = [
    t.relief ? `Рельєф: ${RELIEF_LABEL[t.relief]}` : null,
    t.soil ? `Ґрунт: ${SOIL_LABEL[t.soil]}` : null,
  ].filter((x): x is string => !!x);
  return parts.length ? parts.join(" · ") : null;
}
