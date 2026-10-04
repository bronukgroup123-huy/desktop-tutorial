import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";
import { Errors } from "./errors.ts";

export const CoordinateSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

export const GuardianInputSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().min(5).max(20),
  is_emergency: z.boolean().optional().default(false),
});

export const OverdueThresholdsSchema = z.object({
  soft: z.number().int().min(0).max(1440),
  medium: z.number().int().min(0).max(1440),
  hard: z.number().int().min(0).max(1440),
}).refine(
  (t) => t.soft <= t.medium && t.medium <= t.hard,
  { message: "Thresholds must be soft <= medium <= hard" }
);

export const SessionSettingsSchema = z.object({
  overdue_thresholds: OverdueThresholdsSchema.optional(),
  stationary_threshold_min: z.number().int().min(5).max(240).optional(),
  offline_threshold_min: z.number().int().min(10).max(480).optional(),
  grace_period_min: z.number().int().min(1).max(60).optional(),
  recovery_window_min: z.number().int().min(5).max(1440).optional(),
}).optional();

export const CreateSessionSchema = z.object({
  expected_return: z.string().datetime({ offset: true }),
  guardians: z.array(GuardianInputSchema).min(1).max(3),
  settings: SessionSettingsSchema,
});

export const PingSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  recorded_at: z.string().datetime({ offset: true }).optional(),
  battery_pct: z.number().int().min(0).max(100).optional(),
  signal_strength: z.number().int().min(0).max(5).optional(),
  speed_kmh: z.number().min(0).max(200).optional(),
  was_offline: z.boolean().optional().default(false),
});

export const ExtendSchema = z.object({
  minutes: z.number().int().min(5).max(480),
});

export const RevokeGuardianSchema = z.object({
  guardian_id: z.string().uuid(),
});

export const GuardianExtendRequestSchema = z.object({
  minutes: z.number().int().min(5).max(480).optional(),
  message: z.string().max(200).optional(),
});

export async function parseBody<T>(
  req: Request,
  schema: z.ZodSchema<T>
): Promise<T> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw Errors.validation("Invalid JSON body");
  }

  const result = schema.safeParse(body);
  if (!result.success) {
    throw Errors.validation(
      "Validation failed",
      { issues: result.error.issues }
    );
  }
  return result.data;
}
