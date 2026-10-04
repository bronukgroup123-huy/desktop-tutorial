import type { GuardianSession, GuardianTrackPoint } from "./types.ts";

export interface GpxOptions {
  name?: string;
  sosWaypoint?: { lat: number; lng: number; time: string } | null;
  exitWaypoint?: { lat: number; lng: number; time: string } | null;
}

export function buildGpx(
  session: GuardianSession,
  points: GuardianTrackPoint[],
  options: GpxOptions = {}
): string {
  const name = options.name ?? buildDefaultName(session);
  const now = new Date().toISOString();

  const lines: string[] = [];

  lines.push(`<?xml version="1.0" encoding="UTF-8"?>`);
  lines.push(
    `<gpx version="1.1" creator="MushroomRadar" ` +
    `xmlns="http://www.topografix.com/GPX/1/1" ` +
    `xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ` +
    `xsi:schemaLocation="http://www.topografix.com/GPX/1/1 ` +
    `http://www.topografix.com/GPX/1/1/gpx.xsd">`
  );

  lines.push(`  <metadata>`);
  lines.push(`    <name>${escapeXml(name)}</name>`);
  lines.push(`    <time>${now}</time>`);
  lines.push(`    <desc>${escapeXml(buildDescription(session))}</desc>`);
  lines.push(`  </metadata>`);

  if (options.sosWaypoint) {
    lines.push(
      `  <wpt lat="${options.sosWaypoint.lat.toFixed(6)}" ` +
      `lon="${options.sosWaypoint.lng.toFixed(6)}">`
    );
    lines.push(`    <time>${options.sosWaypoint.time}</time>`);
    lines.push(`    <name>SOS</name>`);
    lines.push(`    <sym>Danger</sym>`);
    lines.push(`    <type>SOS</type>`);
    lines.push(`  </wpt>`);
  }

  if (options.exitWaypoint) {
    lines.push(
      `  <wpt lat="${options.exitWaypoint.lat.toFixed(6)}" ` +
      `lon="${options.exitWaypoint.lng.toFixed(6)}">`
    );
    lines.push(`    <time>${options.exitWaypoint.time}</time>`);
    lines.push(`    <name>Вихід з лісу</name>`);
    lines.push(`    <sym>Flag</sym>`);
    lines.push(`  </wpt>`);
  }

  lines.push(`  <trk>`);
  lines.push(`    <name>${escapeXml(name)}</name>`);
  lines.push(`    <type>hiking</type>`);
  lines.push(`    <trkseg>`);

  for (const p of points) {
    const lat = coordsToLat(p.coords);
    const lng = coordsToLng(p.coords);
    if (lat === null || lng === null) continue;

    lines.push(`      <trkpt lat="${lat.toFixed(6)}" lon="${lng.toFixed(6)}">`);
    lines.push(`        <time>${p.recorded_at}</time>`);
    if (p.speed_kmh !== null) {
      lines.push(`        <speed>${(p.speed_kmh / 3.6).toFixed(3)}</speed>`);
    }
    lines.push(`      </trkpt>`);
  }

  lines.push(`    </trkseg>`);
  lines.push(`  </trk>`);
  lines.push(`</gpx>`);

  return lines.join("\n");
}

function buildDefaultName(session: GuardianSession): string {
  const date = new Date(session.started_at).toISOString().slice(0, 10);
  return `Похід — ${date}`;
}

function buildDescription(session: GuardianSession): string {
  const parts: string[] = [];
  parts.push(`Session: ${session.id}`);
  parts.push(`Started: ${session.started_at}`);
  if (session.expected_return) {
    parts.push(`Expected return: ${session.expected_return}`);
  }
  parts.push(`Status: ${session.status}`);
  return parts.join(" | ");
}

function escapeXml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function coordsToLat(coords: unknown): number | null {
  if (!coords || typeof coords !== "object") return null;
  const c = coords as Record<string, unknown>;
  if (typeof c.lat === "number") return c.lat;
  if (Array.isArray(c.coordinates) && typeof c.coordinates[1] === "number") {
    return c.coordinates[1] as number;
  }
  return null;
}

function coordsToLng(coords: unknown): number | null {
  if (!coords || typeof coords !== "object") return null;
  const c = coords as Record<string, unknown>;
  if (typeof c.lng === "number") return c.lng;
  if (Array.isArray(c.coordinates) && typeof c.coordinates[0] === "number") {
    return c.coordinates[0] as number;
  }
  return null;
}
