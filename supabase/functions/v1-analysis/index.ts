// ============================================================================
// Edge Function: v1-analysis — машинний прогноз, аналіз ділянки (B2.9, ADR-015)
// GET  /functions/v1/v1-analysis    доступні розміри, збережена ділянка, ліміт на сьогодні
// POST /functions/v1/v1-analysis    { lat, lng, size_km: 5 | 10, date? }
//
// JWT обов'язковий (гість теж має JWT — ADR-001). Ділянка — тільки у своїй області.
// Відповідь — рівні з готовими підписами, без числових ймовірностей.
// Логіка — `_shared/v1/analysis.ts`.
// ============================================================================

import { ForecastEngine } from "../_shared/forecast/engine.ts";
import { type FeatureFlags, loadFeatureFlags } from "../_shared/forecast/flags.ts";
import type { ForecastInput } from "../_shared/forecast/types.ts";
import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleAnalysis } from "../_shared/v1/analysis.ts";

Deno.serve(handle((req) => {
  const db = serviceClient();
  let flags: Promise<FeatureFlags> | null = null;

  return handleAnalysis(req, {
    db,
    verify: supabaseTokenVerifier,
    forecast: async (input) => {
      flags ??= loadFeatureFlags(db as unknown as Parameters<typeof loadFeatureFlags>[0]);
      const engineInput: ForecastInput = {
        lat: input.lat,
        lng: input.lng,
        date: input.date,
        forestType: input.forestType as ForecastInput["forestType"],
        forestConfirmed: input.forestType !== null,
        homeRegionId: input.homeRegionId,
      };
      return ForecastEngine.forecast(
        engineInput,
        db as unknown as Parameters<typeof ForecastEngine.forecast>[1],
        await flags,
      );
    },
  });
}));
