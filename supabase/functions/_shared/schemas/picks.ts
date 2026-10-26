// ============================================================================
// Tier 3 API Contracts — Picks (Flutter-ready)
// ============================================================================

import { z } from "npm:zod@3";

// ---------------------------------------------------------------------------
// Request: POST /picks
// ---------------------------------------------------------------------------

export const PickRequestSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  gpsAccuracy: z.number().positive().optional(),
  photoBase64: z.string().min(1),
  mushroomType: z.string().min(1),
  forestType: z.string().optional(),
  isIndicator: z.boolean(),
  isNegativeReport: z.boolean(),
});

export type PickRequest = z.infer<typeof PickRequestSchema>;

// ---------------------------------------------------------------------------
// Response: 201 Created
// ---------------------------------------------------------------------------

export const PickResponseSchema = z.object({
  id: z.string().uuid(),
  verificationStatus: z.enum(["pending", "verified", "conditional"]),
});

export type PickResponse = z.infer<typeof PickResponseSchema>;

// ---------------------------------------------------------------------------
// Wrapper response (matching current jsonResponse shape: { data: ... })
// ---------------------------------------------------------------------------

export const PickSuccessResponseSchema = z.object({
  data: PickResponseSchema,
});

export type PickSuccessResponse = z.infer<typeof PickSuccessResponseSchema>;