export type SessionStatus =
  | "pending"
  | "active"
  | "stale"
  | "offline"
  | "exiting"
  | "overdue_soft"
  | "overdue_medium"
  | "overdue_hard"
  | "sos"
  | "closing"
  | "closed";

export type AlertType =
  | "sos"
  | "overdue_soft"
  | "overdue_medium"
  | "overdue_hard"
  | "offline"
  | "stationary"
  | "exit"
  | "battery_low"
  | "closing"
  | "closed"
  | "recovered";

export interface Coords {
  lat: number;
  lng: number;
}

export interface GuardianSession {
  id: string;
  status: SessionStatus;
  expected_return: string;
  original_return: string;
  started_at: string;
  closed_at: string | null;
  recoverable_until: string | null;
  last_known_coords: Coords | null;
  last_known_at: string | null;
  last_battery_pct: number | null;
  last_signal_strength: number | null;
  exit_detected_at: string | null;
  sos_activated_at: string | null;
  overdue_level: "soft" | "medium" | "hard" | null;
  previous_status: SessionStatus | null;
  settings: {
    overdue_thresholds: { soft: number; medium: number; hard: number };
    stationary_threshold_min: number;
    offline_threshold_min: number;
    grace_period_min: number;
    recovery_window_min: number;
  };
}

export interface GuardianSessionResponse {
  session: GuardianSession;
  derived: {
    seconds_since_last_known: number | null;
    minutes_to_return: number;
  };
  guardians: Array<{
    id: string;
    name: string | null;
    is_emergency: boolean;
    last_seen_at: string | null;
    revoked_at: string | null;
  }>;
  current_guardian_id: string;
}

export interface TrackPoint {
  coords: { coordinates: [number, number] } | Coords;
  recorded_at: string;
  battery_pct: number | null;
  signal_strength: number | null;
  speed_kmh: number | null;
}

export interface TrackResponse {
  session_id: string;
  points: TrackPoint[];
}

export interface RescueView {
  rescue_id: string;
  session: {
    id: string;
    status: SessionStatus;
    started_at: string;
    expected_return: string;
    last_known_coords: Coords | null;
    last_known_at: string | null;
    sos_activated_at: string | null;
  };
  picker: { name: string };
  target: string;
  notes: string | null;
  payload: Record<string, unknown>;
  created_at: string;
  expires_at: string;
  resolved_at: string | null;
  gpx_url: string;
}
