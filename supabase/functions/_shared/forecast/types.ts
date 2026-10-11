// ============================================================================
// Forecast Engine — Types (plan v6.0 §11.1)
// ============================================================================

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
  | "mixed";

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
// Weather / Crowd
// ============================================================================

export interface WeatherData {
  date: string;                 // ISO
  temp_min: number;             // °C
  temp_max: number;
  temp_avg: number;
  humidity: number;             // %
  rain_1d: number;              // mm
  rain_2d: number;              // mm
  rain_3d: number;              // mm
  rain_7d?: number;             // mm
  pressure?: number;            // hPa
  pressure_trend?: "rising" | "falling" | "stable";
  wind_kmh?: number;
  cloudiness?: number;          // %
  drought_days?: number;        // днів без дощу
  days_after_rain?: number;
}

export interface CrowdData {
  date: string;
  crowd_level: "low" | "medium" | "high" | "extreme";
  is_weekend: boolean;
  is_holiday?: boolean;
}

// ============================================================================
// Forecast input / context
// ============================================================================

export interface ForecastInput {
  user_id: string;
  coords: { lat: number; lng: number };
  region_id?: number | null;
  date_range: string[];         // ISO dates
  mushroom_types?: string[];    // filter (optional)
}

export interface ForestZoneRef {
  id: string;
  forest_type: ForestType | null;
  stand_age_years: number | null;
  stand_age_confidence: number | null;
  relief_type: ReliefType | null;
  light_type: LightRecord | null;
}

export interface ForecastContext {
  region_id: number | null;
  region_name: string | null;
  forest_zone: ForestZoneRef | null;
  weather: WeatherData[];
  crowd: CrowdData[];
  gdd_accumulated?: number;     // growing degree days
  day_of_year: number;
  in_forest: boolean;
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
  top1: ScoredSpecies | null;
  alternative: ScoredSpecies | null;
  warnings: string[];
  noDataReason: "no_forest_zone" | "no_weather" | "no_region" | "no_rules" | null;
}
