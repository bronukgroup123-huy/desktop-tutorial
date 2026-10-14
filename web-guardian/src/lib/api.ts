import type {
  GuardianSessionResponse,
  TrackResponse,
  RescueView,
} from "./types";
import { useAuthStore } from "@/store/auth-store";

const FUNCTIONS_URL = process.env.NEXT_PUBLIC_FUNCTIONS_URL!;

if (!FUNCTIONS_URL) {
  throw new Error("NEXT_PUBLIC_FUNCTIONS_URL is not set");
}

interface ApiSuccess<T> {
  data: T;
}

interface ApiError {
  error: string;
  message: string;
  details?: Record<string, unknown>;
}

export class GuardianApiError extends Error {
  constructor(
    public code: string,
    message: string,
    public status: number,
    public details?: Record<string, unknown>
  ) {
    super(message);
    this.name = "GuardianApiError";
  }

  get isExpiredToken(): boolean {
    return this.code === "invalid_token" || this.status === 401;
  }

  get isNotFound(): boolean {
    return this.status === 404;
  }
}

async function apiCall<T>(
  path: string,
  init: RequestInit = {},
  auth = false
): Promise<T> {
  // JWT — ЛИШЕ для явно позначених auth-викликів (/me).
  // Guardian-виклики за замовчуванням auth=false → ніколи не додаємо
  // Authorization у X-Guardian-Token flow (урок фіксу 27539f1).
  const token = auth ? useAuthStore.getState().accessToken : null;

  const res = await fetch(`${FUNCTIONS_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(auth && token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init.headers ?? {}),
    },
  });

  let json: ApiSuccess<T> | ApiError;
  try {
    json = await res.json();
  } catch {
    throw new GuardianApiError(
      "parse_error",
      "Не вдалось розібрати відповідь сервера",
      res.status
    );
  }

  if (!res.ok) {
    const err = json as ApiError;
    throw new GuardianApiError(
      err.error ?? "unknown_error",
      err.message ?? "Невідома помилка",
      res.status,
      err.details
    );
  }

  return (json as ApiSuccess<T>).data;
}

export async function fetchGuardianSession(
  token: string
): Promise<GuardianSessionResponse> {
  return apiCall<GuardianSessionResponse>(`/guardian-session-get/${token}`);
}

export async function fetchGuardianTrack(
  token: string,
  since?: string,
  limit = 5000
): Promise<TrackResponse> {
  const params = new URLSearchParams();
  if (since) params.set("since", since);
  params.set("limit", String(limit));
  return apiCall<TrackResponse>(
    `/guardian-session-track/${token}?${params.toString()}`
  );
}

export async function registerGuardianDevice(
  token: string,
  fcmToken: string,
  userAgent?: string
): Promise<{ registered: boolean }> {
  return apiCall<{ registered: boolean }>(
    `/guardian-register-guardian-device`,
    {
      method: "POST",
      headers: { "X-Guardian-Token": token },
      body: JSON.stringify({ fcm_token: fcmToken, user_agent: userAgent }),
    }
  );
}

export async function fetchRescue(token: string): Promise<RescueView> {
  return apiCall<RescueView>(`/guardian-rescue-get/${token}`);
}

export function getGpxUrl(token: string): string {
  return `${FUNCTIONS_URL}/guardian-session-gpx/${token}`;
}

export function getRescueGpxUrl(token: string): string {
  return `${FUNCTIONS_URL}/guardian-rescue-get/${token}/gpx`;
}

// ============================================================================
// Auth-scope API (JWT через apiCall auth=true) — Phase 2
// ============================================================================
// Формат відповідей = MeProfile (snake_case) із _shared/forecast/me-endpoint.ts.
// apiCall<T> повертає РОЗГОРНУТЕ data (ApiSuccess<T>.data), тому без .data.

export interface MeProfile {
  id: string;
  name: string | null;
  rating: number;
  total_verified_picks: number;
  home_region: { id: number; slug: string; name: string } | null;
  created_at: string;
}

export interface RegionItem {
  id: number;
  name: string;
  slug: string;
  koatuu: string | null;
  katottg: string | null;
}

export async function fetchMe(): Promise<MeProfile> {
  return apiCall<MeProfile>("/me", { method: "GET" }, true);
}

export async function patchMe(input: {
  name?: string;
  home_region_slug?: string;
}): Promise<MeProfile> {
  return apiCall<MeProfile>(
    "/me",
    { method: "PATCH", body: JSON.stringify(input) },
    true
  );
}

// Публічний довідник областей (без JWT).
export async function fetchRegions(): Promise<RegionItem[]> {
  return apiCall<RegionItem[]>("/regions", { method: "GET" });
}
