"use client";

import { useEffect } from "react";
import { fetchGuardianTrack } from "@/lib/api";
import { getSupabaseBrowser } from "@/lib/supabase-browser";
import { useGuardianStore } from "@/store/guardian-store";
import { useVisibility } from "./useVisibility";
import type { Coords, TrackPoint } from "@/lib/types";

export function useRealtimeTrack(token: string, sessionId: string | null) {
  const { setTrack, appendTrackPoint } = useGuardianStore();
  const isVisible = useVisibility();

  useEffect(() => {
    if (!token || !sessionId) return;

    let cancelled = false;

    fetchGuardianTrack(token, undefined, 5000)
      .then((data) => {
        if (cancelled) return;
        setTrack(data.points);
      })
      .catch(() => {
        // ignore
      });

    return () => {
      cancelled = true;
    };
  }, [token, sessionId, setTrack]);

  useEffect(() => {
    if (!token || !sessionId || !isVisible) return;

    const supabase = getSupabaseBrowser();
    const channel = supabase
      .channel(`guardian-track-${sessionId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "guardian_track",
          filter: `session_id=eq.${sessionId}`,
        },
        (payload) => {
          const row = payload.new as {
            coords: unknown;
            recorded_at: string;
            battery_pct: number | null;
            signal_strength: number | null;
            speed_kmh: number | null;
          };

          const coords = normalizeCoords(row.coords);
          if (!coords) return;

          const point: TrackPoint = {
            coords,
            recorded_at: row.recorded_at,
            battery_pct: row.battery_pct,
            signal_strength: row.signal_strength,
            speed_kmh: row.speed_kmh,
          };

          appendTrackPoint(point);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [token, sessionId, isVisible, appendTrackPoint]);
}

function normalizeCoords(raw: unknown): Coords | { coordinates: [number, number] } | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (Array.isArray(r.coordinates) && r.coordinates.length === 2) {
    return { coordinates: [r.coordinates[0] as number, r.coordinates[1] as number] };
  }
  if (typeof r.lat === "number" && typeof r.lng === "number") {
    return { lat: r.lat, lng: r.lng };
  }
  return null;
}
