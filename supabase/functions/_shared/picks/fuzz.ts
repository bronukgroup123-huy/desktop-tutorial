// ============================================================================
// Тук-тук: зсунуте місце публічної точки (ADR-018 §18.5, BACKEND_PLAN B3.1)
//
// Чужі очі бачать публічну точку з похибкою 300–500 м. Зсув стабільний для
// кожної точки: кут і відстань виводяться з id точки, тому повторні запити
// не дають «усереднити» справжнє місце.
//
// Чому HMAC, а не просто SHA-256(id): id точки публічний (він є у відповідях
// API), а алгоритм відкритий. Із самого лише id будь-хто обчислив би зсув і
// «відмотав» його назад до точних координат. Тому зсув залежить ще й від
// серверного секрету, якого клієнт не знає.
//
// Чисті функції (Web Crypto), тестуються без мережі.
// ============================================================================

/** Межі зсуву на сфері. Запас 3 м — щоб і на еліпсоїді WGS84 (PostGIS) лишатись у 300–500 м. */
export const FUZZ_MIN_M = 303;
export const FUZZ_MAX_M = 497;

const EARTH_RADIUS_M = 6_371_008.8;
const DOMAIN = "pick-display:v1:";
const toRad = (deg: number) => (deg * Math.PI) / 180;
const toDeg = (rad: number) => (rad * 180) / Math.PI;

export interface FuzzOffset {
  /** Азимут зсуву, градуси [0, 360). */
  bearingDeg: number;
  /** Відстань зсуву, метри [FUZZ_MIN_M, FUZZ_MAX_M). */
  distanceM: number;
}

/** Детермінований зсув для точки: HMAC-SHA-256(secret, id) → кут і відстань. */
export async function fuzzOffset(pickId: string, secret: string): Promise<FuzzOffset> {
  if (!secret) throw new Error("fuzz secret is required");
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, enc.encode(DOMAIN + pickId.toLowerCase()));
  const view = new DataView(mac);
  const angle = view.getUint32(0) / 2 ** 32; // [0, 1)
  const dist = view.getUint32(4) / 2 ** 32; // [0, 1)
  return {
    bearingDeg: angle * 360,
    distanceM: FUZZ_MIN_M + dist * (FUZZ_MAX_M - FUZZ_MIN_M),
  };
}

/** Точка на відстані `distanceM` за азимутом `bearingDeg` (сферична модель Землі). */
export function destinationPoint(
  lat: number,
  lng: number,
  bearingDeg: number,
  distanceM: number,
): { lat: number; lng: number } {
  const delta = distanceM / EARTH_RADIUS_M;
  const theta = toRad(bearingDeg);
  const phi1 = toRad(lat);
  const lambda1 = toRad(lng);

  const sinPhi2 = Math.sin(phi1) * Math.cos(delta) + Math.cos(phi1) * Math.sin(delta) * Math.cos(theta);
  const phi2 = Math.asin(Math.min(1, Math.max(-1, sinPhi2)));
  const lambda2 = lambda1 + Math.atan2(
    Math.sin(theta) * Math.sin(delta) * Math.cos(phi1),
    Math.cos(delta) - Math.sin(phi1) * sinPhi2,
  );
  const lngOut = ((toDeg(lambda2) + 540) % 360) - 180; // нормалізація до [-180, 180)
  return { lat: toDeg(phi2), lng: lngOut };
}

/** Відстань між двома точками на тій самій сфері, метри. */
export function distanceM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/**
 * Зсунуте місце публічної точки (`display_geom`).
 * Той самий (id, secret) завжди дає той самий зсув; координати — 6 знаків (~0.1 м).
 */
export async function fuzzPoint(
  pickId: string,
  lat: number,
  lng: number,
  secret: string,
): Promise<{ lat: number; lng: number }> {
  const { bearingDeg, distanceM: d } = await fuzzOffset(pickId, secret);
  const p = destinationPoint(lat, lng, bearingDeg, d);
  return { lat: Number(p.lat.toFixed(6)), lng: Number(p.lng.toFixed(6)) };
}
