// ============================================================================
// Forecast API types (Thin Client — всі розрахунки на сервері)
// ============================================================================

export type ProbabilityLevel = "no_data" | "low" | "medium" | "high" | "peak";

export interface ScoredSpeciesShape {
  mushroom_type: string;
  name_ua: string;
  score: number;
  probability: ProbabilityLevel;
  level_label: string;
  level_color: string;
  when_label: string;
  where_label: string;
  why_labels: string[];
  matched: string[];
  missed: string[];
}

export interface ForecastResponse {
  regionName: string | null;
  date: string;
  forest: string;
  top1: ScoredSpeciesShape | null;
  alternative: ScoredSpeciesShape | null;
  warnings: string[];
  noDataReason?: string;
}

export interface ForestZoneProperties {
  forest_type: string | null;
  stand_age_years: number | null;
  [key: string]: unknown;
}

export interface ForestZoneFeature {
  type: "Feature";
  properties: ForestZoneProperties;
  geometry: {
    type: "Polygon" | "MultiPolygon";
    coordinates: unknown;
  };
}

export interface ForestZonesResponse {
  type: "FeatureCollection";
  features: ForestZoneFeature[];
}
