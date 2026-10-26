// ============================================================================
// Tier 3 API Contracts — Forecast (Flutter-ready)
// ============================================================================

import { z } from "npm:zod@3";

// ---------------------------------------------------------------------------
// Request: POST /v1/forecast
// ---------------------------------------------------------------------------

export const ForecastRequestSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  forestType: z.string().optional(),
});

export type ForecastRequest = z.infer<typeof ForecastRequestSchema>;

// ---------------------------------------------------------------------------
// Response shapes (Flutter-ready — Thin Client manifest)
// All fields the Flutter client needs to render UI without any logic.
// ---------------------------------------------------------------------------

export type ProbabilityLevel = "no_data" | "low" | "medium" | "high" | "peak";

export const SpeciesResponseSchema = z.object({
  mushroom_type: z.string(),
  name_ua: z.string(),
  score: z.number().min(0).max(1),
  probability: z.enum(["no_data", "low", "medium", "high", "peak"]),
  // Thin Client fields — готове для UI:
  level: z.enum(["no_data", "low", "medium", "high", "peak"]),
  level_label: z.string(),
  level_color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  when_label: z.string(),
  where_label: z.string(),
  why_labels: z.array(z.string()),
  // Debug fields (опціонально, для дебагу):
  matched: z.array(z.string()).optional(),
  missed: z.array(z.string()).optional(),
  wave: z.enum(["spring", "summer1", "summer2", "autumn", "late"]).nullable().optional(),
});

export type SpeciesResponse = z.infer<typeof SpeciesResponseSchema>;

export const ForecastResponseSchema = z.object({
  regionName: z.string().nullable(),
  date: z.string(), // YYYY-MM-DD
  forest: z.string(),
  top1: SpeciesResponseSchema.nullable(),
  alternative: SpeciesResponseSchema.nullable(),
  warnings: z.array(z.string()),
  noDataReason: z.string().optional(),
});

export type ForecastResponse = z.infer<typeof ForecastResponseSchema>;