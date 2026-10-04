import type {
  GuardianSessionResponse,
  TrackResponse,
  RescueView,
} from "./types";

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
  init: RequestInit = {}
): Promise<T> {
  const res = await fetch(`${FUNCTIONS_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
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
