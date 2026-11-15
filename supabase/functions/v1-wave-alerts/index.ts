// ============================================================================
// Edge Function: v1-wave-alerts — щоденні сповіщення «Почалась хвиля» (ADR-015 §15.8 п.19)
// POST /functions/v1/v1-wave-alerts  (Authorization: Bearer <service_role>) — з розкладу
// GitHub Actions (.github/workflows/wave-alerts.yml). Логіка — `_shared/v1/wave-alerts.ts`.
// ============================================================================

import { ForecastEngine } from "../_shared/forecast/engine.ts";
import { type FeatureFlags, loadFeatureFlags } from "../_shared/forecast/flags.ts";
import { fetchTerrain } from "../_shared/forecast/terrain.ts";
import type { ForecastInput } from "../_shared/forecast/types.ts";
import { sendPush } from "../_shared/guardian/notifications/firebase.ts";
import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleWaveAlerts } from "../_shared/v1/wave-alerts.ts";

Deno.serve(handle((req) => {
  const db = serviceClient();
  let flags: Promise<FeatureFlags> | null = null;

  return handleWaveAlerts(req, {
    db,
    verify: supabaseTokenVerifier,
    serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    allowAll: Deno.env.get("WAVE_ALERTS_FOR_ALL") === "true",
    terrain: (lat, lng, sizeKm) => fetchTerrain(lat, lng, sizeKm),
    forecast: async (input) => {
      flags ??= loadFeatureFlags(db as unknown as Parameters<typeof loadFeatureFlags>[0]);
      const engineInput: ForecastInput = {
        lat: input.lat,
        lng: input.lng,
        date: new Date(`${input.dates[0]}T00:00:00Z`),
        forestType: input.forestType as ForecastInput["forestType"],
        forestConfirmed: input.forestType !== null,
        homeRegionId: input.homeRegionId,
        terrain: input.terrain ?? null,
      };
      return ForecastEngine.forecastDays(
        engineInput,
        input.dates,
        db as unknown as Parameters<typeof ForecastEngine.forecastDays>[2],
        await flags,
      );
    },
    send: async (token, msg) => {
      const r = await sendPush({ token, title: msg.title, body: msg.body, data: msg.data, priority: "normal" });
      return { ok: r.success, unregistered: /registration-token-not-registered|not.?registered|invalid-registration/i.test(r.errorMessage ?? "") };
    },
  });
}));
