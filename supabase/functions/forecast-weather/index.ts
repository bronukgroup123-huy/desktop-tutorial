// ============================================================================
// Edge Function: forecast-weather (group 8.2)
// GET / POST — погода + хвиля для точки. graceful degradation → 200.
// ============================================================================

import { corsHeaders } from "../_shared/cors.ts";
import { fetchWeather } from "../_shared/forecast/weather.ts";
import { detectWave } from "../_shared/forecast/wave.ts";

const JSON_HEADERS = { ...corsHeaders, "Content-Type": "application/json" };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const lat = Number(body.lat);
    const lng = Number(body.lng);
    const dateRaw = body.date;

    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return new Response(
        JSON.stringify({ error: "lat and lng required (numbers)" }),
        { status: 400, headers: JSON_HEADERS }
      );
    }

    const weather = await fetchWeather(lat, lng);
    const targetDate = typeof dateRaw === "string" && dateRaw
      ? new Date(dateRaw)
      : new Date();
    const wave = detectWave(targetDate, lat, weather.gdd);

    return new Response(
      JSON.stringify({
        data: {
          weather,
          wave,
          date: targetDate.toISOString().slice(0, 10),
        },
      }),
      { status: 200, headers: JSON_HEADERS }
    );
  } catch (e) {
    console.error("forecast-weather error:", e);
    return new Response(
      JSON.stringify({ error: "internal_error", message: (e as Error).message }),
      { status: 500, headers: JSON_HEADERS }
    );
  }
});
