// ============================================================================
// Forecast Engine — Types (plan v6.0 §11.1)
// ============================================================================

import type { FeatureFlags } from "./flags.ts";

export type { FeatureFlags };

export type Wave = "spring" | "summer1" | "summer2" | "autumn" | "late";

export type ForestType =
  | "pine"
  | "spruce"
  | "oak"
  | "birch"
  | "aspen"
  | "alder"
  | "beech"
  | "hornbeam"
  | "deciduous"
  | "coniferous"
  | "mixed"
  | "any";

export type HabitatType =
  | "forest_floor"
  | "moss"
  | "decaying_wood"
  | "grassland"
  | "meadow"
  | "pasture"
  | "forest_edge"
  | "floodplain"
  | "swamp"
  | "disturbed_ground";

export type ReliefType =
  | "plain"
  | "hill"
  | "slope"
  | "plateau"
  | "valley"
  | "swale"
  | "microrefugium";

export type SoilState =
  | "sandy"
  | "loam"
  | "clay"
  | "peat"
  | "chalky"
  | "podzol";

export type LightRecord = "full_sun" | "partial_shade" | "deep_shade";

export type ProbabilityLevel = "none" | "low" | "medium" | "high" | "peak";

// ============================================================================
// Weather (§11.1)
// ============================================================================

export type PressureTrend =
  | "rising"
  | "falling"
  | "stable"
  | "smooth_decline_before_rain";

/** Стан ґрунту за вологістю (§13) — не плутати з SoilState (текстура) */
export type SoilMoistureState = "dry" | "normal" | "wet" | "waterlogged";

export interface WeatherData {
  // Температура
  tempAvg7d: number;
  tempAvg14d: number;
  tempAvg20d: number;
  tempMin: number;
  tempMax: number;

  // Вологість і опади
  humidity: number;       // середня за 7 днів, %
  rain1d: number;         // мм за 1 день
  rain2d: number;         // мм за 2 дні
  rain3d: number;         // мм за 3 дні
  rain7d: number;         // мм за 7 днів
  rain14d: number;        // мм за 14 днів
  rain30d: number;        // мм за 30 днів
  droughtDays: number;    // днів з опадами <1 мм/24 год (§11.1)
  daysAfterRain: number;  // днів після останнього дощу ≥10 мм/24 год

  // Тиск
  pressure: number;       // гПа
  pressureTrend: PressureTrend;

  // Стан ґрунту (§13)
  soilState: SoilMoistureState;

  // Додаткові (для GDD)
  gdd: number | null;     // Growing Degree Days, або null якщо недоступно

  // Метадані
  fetchedAt: string;      // ISO timestamp
  source: "open-meteo" | "openweather" | "cached" | "unavailable";
}

// ============================================================================
// Crowd
// ============================================================================

export interface CrowdData {
  verifiedPicks7d: number;
  negativeReports7d: number;
  indicatorSpecies: string[];
}

// ============================================================================
// Forecast input / context
// ============================================================================

export interface ForecastInput {
  lat: number;
  lng: number;
  date: Date;
  forestType: ForestType | null;
  forestConfirmed: boolean;
  homeRegionId: number | null;
  userId?: string;
  mushroomTypes?: string[];    // filter (optional)
}

export interface ForestZoneRef {
  id: string;
  forest_type: ForestType | null;
  stand_age_years: number | null;
  stand_age_confidence: number | null;
  relief_type: ReliefType | null;
  light_type: LightRecord | null;
}

export interface ForestZoneData {
  standAgeYears: number | null;
  standAgeSource: "inventory" | "ndvi" | "user" | null;
  standAgeConfidence: number;
  reliefType: ReliefType | null;
  lightType: string | null;
}

export interface ForecastContext {
  input: ForecastInput;
  weather: WeatherData;
  crowd: CrowdData;
  wave: Wave;

  // FIX 2.6 — окремі прапорці
  forestTypeUnknown: boolean;
  standAgeUnknown: boolean;

  // Значення
  standAge: number | null;
  standAgeConfidence: number;
  reliefType: ReliefType | null;
  lightType: string | null;

  config: FeatureFlags;
  regionName: string | null;  // null у 8.2 (seed regions у 9.1)

  // Метадані
  computedAt: string;
}

// ============================================================================
// SpeciesRule — camelCase конвертація рядка expert_rules
// ============================================================================

export interface SpeciesRule {
  id: string;
  legacyId: number | null;
  mushroomType: string;
  nameUa: string;
  nameLat: string;

  fruitingTempMin: number | null;
  fruitingTempMax: number | null;
  fruitingTempPeakMin: number | null;
  fruitingTempPeakMax: number | null;
  myceliumTempMin: number | null;
  myceliumTempMax: number | null;

  humidityMin: number | null;
  rain3dMin: number | null;
  rain1dMin: number | null;
  rain2dMin: number | null;
  droughtDaysMin: number | null;
  daysAfterRainMin: number | null;
  daysAfterRainMax: number | null;
  waterloggedPenalty: number | null;
  droughtThenRain: boolean;

  forestType: string[];
  habitatType: string[];
  reliefType: ReliefType[];
  altitudeMin: number | null;
  altitudeMax: number | null;
  soilPhMin: number | null;
  soilPhMax: number | null;
  lightPreference: LightRecord | null;
  standAgeMin: number | null;
  standAgeMax: number | null;
  prefersLowland: boolean;
  prefersHilltop: boolean;

  seasonStart: string;          // MM-DD
  seasonEnd: string;            // MM-DD
  waveSpring: boolean;
  waveSummer1: boolean;
  waveSummer2: boolean;
  waveAutumn: boolean;
  waveLate: boolean;
  peakWaves: Wave[];
  peakMonths: number[];

  indicatorSpecies: string[];
  shockRequired: boolean;
  microrefugiumDry: string | null;
  microrefugiumWet: string | null;

  regionIds: number[];
  weight: number;
  mvpStage: "mvp" | "v2" | "future";
  lastCalibratedAt: string | null;
}

// ============================================================================
// Scoring / Result
// ============================================================================

export interface ScoredSpecies {
  mushroom_type: string;
  name_ua: string;
  score: number;                // 0..1
  probability: ProbabilityLevel;
  matched: string[];            // які умови спрацювали
  missed: string[];             // які ні
  wave: Wave | null;
}

export interface ForecastResult {
  regionName: string | null;
  date: string;
  forest: string;
  top1: ScoredSpecies | null;
  alternative: ScoredSpecies | null;
  warnings: string[];
  noDataReason?: string;
}

// ============================================================================
// CatalogEntry — рядок mushroom_catalog (канонічний довідник 326 видів)
// ============================================================================

export type Edibility =
  | "edible"
  | "conditionally_edible"
  | "inedible"
  | "poisonous"
  | "deadly_poisonous";

export interface CatalogAttrs {
  color: string[];
  stem: string[];
  tree: string[];
  season: string[];
}

export interface CatalogEntry {
  id: string;
  nameUa: string;
  nameLat: string;
  edibility: Edibility;
  edibilityLabel: string;
  redListed: boolean;
  rarity: string;
  hasPhoto: boolean;
  top20: boolean;
  popular: boolean;
  aiRecognition: boolean;
  features: string;
  months: number[];
  attrs: CatalogAttrs;
  photos: Array<{ url: string }>;
  peakMonths: number[];
  zones: string[];
  license?: Record<string, unknown>;
  redBookSource?: Record<string, unknown>;
}

/** snake_case → camelCase рядок mushroom_catalog */
export function catalogRowToEntry(row: Record<string, unknown>): CatalogEntry {
  const attrs = (row.attrs ?? {}) as Record<string, unknown>;
  const photos = Array.isArray(row.photos)
    ? (row.photos as Array<Record<string, unknown>>).map((p) => ({ url: String(p.url ?? "") }))
    : [];
  return {
    id: String(row.id),
    nameUa: String(row.name_ua),
    nameLat: String(row.name_lat),
    edibility: (row.edibility as Edibility) ?? "inedible",
    edibilityLabel: String(row.edibility_label ?? ""),
    redListed: Boolean(row.red_listed),
    rarity: String(row.rarity ?? ""),
    hasPhoto: Boolean(row.has_photo),
    top20: Boolean(row.top20),
    popular: Boolean(row.popular),
    aiRecognition: Boolean(row.ai_recognition),
    features: String(row.features ?? ""),
    months: intArray(row.months),
    attrs: {
      color: strArray(attrs.color),
      stem: strArray(attrs.stem),
      tree: strArray(attrs.tree),
      season: strArray(attrs.season),
    },
    photos,
    peakMonths: intArray(row.peak_months),
    zones: strArray(row.zones),
    license: (row.license as Record<string, unknown>) ?? undefined,
    redBookSource: (row.red_book_source as Record<string, unknown>) ?? undefined,
  };
}

function intArray(v: unknown): number[] {
  return Array.isArray(v) ? v.map(Number).filter((n) => !Number.isNaN(n)) : [];
}

function strArray(v: unknown): string[] {
  return Array.isArray(v) ? v.map(String) : [];
}
