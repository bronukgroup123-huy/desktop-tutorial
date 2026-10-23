import { getSupabaseBrowser } from "@/lib/supabase-browser";
import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET() {
  // Supabase не налаштовано (немає env у Vercel) → повертаємо порожній
  // FeatureCollection, щоб debug-роут не падав з 500.
  let supabase: ReturnType<typeof getSupabaseBrowser>;
  try {
    supabase = getSupabaseBrowser();
  } catch {
    return NextResponse.json({ type: "FeatureCollection", features: [] });
  }

  // TEMPORARY DEBUG ENDPOINT - REMOVE BEFORE RELEASE
  // This requires a Postgres function to be created in Supabase:
  // CREATE OR REPLACE FUNCTION get_forest_zones_geojson(bbox double precision[], limit_count int)
  // RETURNS jsonb LANGUAGE plpgsql AS $$
  // DECLARE
  //   result jsonb;
  // BEGIN
  //   SELECT jsonb_build_object(
  //     'type', 'FeatureCollection',
  //     'features', jsonb_agg(jsonb_build_object(
  //       'type', 'Feature',
  //       'geometry', ST_AsGeoJSON(polygon)::jsonb,
  //       'properties', jsonb_build_object('forest_type', forest_type)
  //     ))
  //   ) INTO result
  //   FROM forest_zones
  //   WHERE ST_Intersects(polygon, ST_MakeEnvelope(bbox[1], bbox[2], bbox[3], bbox[4], 4326))
  //   LIMIT limit_count;
  //   RETURN result;
  // END;
  // $$;

  const { data, error } = await supabase.rpc("get_forest_zones_geojson", {
    bbox: [29.5, 50.1, 32.2, 51.2],
    limit_count: 5000,
  });

  if (error) {
    console.error("Supabase error:", error);
    // Fallback: return empty FeatureCollection if function doesn't exist
    return NextResponse.json({
      type: "FeatureCollection",
      features: [],
    });
  }

  return NextResponse.json(data);
}