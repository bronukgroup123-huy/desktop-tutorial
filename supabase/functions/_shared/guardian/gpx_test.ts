import { assertEquals, assert } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { buildGpx } from "./gpx.ts";
import type { GuardianSession, GuardianTrackPoint } from "./types.ts";

const mockSession: GuardianSession = {
  id: "sess-123",
  user_id: "user-1",
  status: "active",
  expected_return: "2026-09-11T18:00:00Z",
  original_return: "2026-09-11T18:00:00Z",
  started_at: "2026-09-11T14:00:00Z",
  closing_started_at: null,
  closed_at: null,
  recoverable_until: null,
  last_known_coords: null,
  last_known_at: null,
  last_battery_pct: null,
  last_signal_strength: null,
  exit_detected_at: null,
  sos_activated_at: null,
  overdue_level: null,
  settings: {
    overdue_thresholds: { soft: 0, medium: 30, hard: 90 },
    stationary_threshold_min: 30,
    offline_threshold_min: 60,
    grace_period_min: 5,
    recovery_window_min: 30,
  },
  created_at: "2026-09-11T14:00:00Z",
  updated_at: "2026-09-11T14:00:00Z",
};

const mockPoints: GuardianTrackPoint[] = [
  {
    id: 1,
    session_id: "sess-123",
    coords: { lat: 50.45, lng: 30.52 },
    recorded_at: "2026-09-11T14:05:00Z",
    battery_pct: 85,
    signal_strength: 4,
    speed_kmh: 3.2,
    was_offline: false,
    created_at: "2026-09-11T14:05:00Z",
  },
  {
    id: 2,
    session_id: "sess-123",
    coords: { lat: 50.451, lng: 30.521 },
    recorded_at: "2026-09-11T:10:00Z",
    battery_pct: 84,
    signal_strength: 4,
    speed_kmh: 2.8,
    was_offline: false,
    created_at: "2026-09-11T14:10:00Z",
  },
];

Deno.test("buildGpx — валідний XML з прологом", () => {
  const gpx = buildGpx(mockSession, mockPoints);
  assert(gpx.startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
  assert(gpx.includes('<gpx version="1.1"'));
  assert(gpx.includes("</gpx>"));
});

Deno.test("buildGpx — містить усі точки треку", () => {
  const gpx = buildGpx(mockSession, mockPoints);
  const trkptCount = (gpx.match(/<trkpt/g) ?? []).length;
  assertEquals(trkptCount, 2);
});

Deno.test("buildGpx — координати у правильному форматі", () => {
  const gpx = buildGpx(mockSession, mockPoints);
  assert(gpx.includes('lat="50.450000"'));
  assert(gpx.includes('lon="30.520000"'));
});

Deno.test("buildGpx — speed у м/с (з км/год)", () => {
  const gpx = buildGpx(mockSession, mockPoints);
  assert(gpx.includes("<speed>0.889</speed>"));
});

Deno.test("buildGpx — SOS waypoint додається", () => {
  const gpx = buildGpx(mockSession, mockPoints, {
    sosWaypoint: { lat: 50.45, lng: 30.52, time: "2026-09-11T15:00:00Z" },
  });
  assert(gpx.includes("<name>SOS</name>"));
  assert(gpx.includes("<type>SOS</type>"));
});

Deno.test("buildGpx — exit waypoint додається", () => {
  const gpx = buildGpx(mockSession, mockPoints, {
    exitWaypoint: { lat: 50.46, lng: 30.53, time: "2026-09-11T17:00:00Z" },
  });
  assert(gpx.includes("<name>Вихід з лісу</name>"));
});

Deno.test("buildGpx — escape XML у name", () => {
  const session = { ...mockSession, started_at: "2026-09-11T14:00:00Z" };
  const gpx = buildGpx(session, mockPoints, {
    name: 'Test <script> "X" & Y',
  });
  assert(gpx.includes("&lt;script&gt;"));
  assert(gpx.includes("&quot;X&quot;"));
  assert(gpx.includes("&amp;"));
});

Deno.test("buildGpx — порожній трек не ламається", () => {
  const gpx = buildGpx(mockSession, []);
  assert(gpx.includes("<trkseg>"));
  assert(gpx.includes("</trkseg>"));
  assertEquals((gpx.match(/<trkpt/g) ?? []).length, 0);
});
