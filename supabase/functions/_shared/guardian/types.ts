// ============================================================================
// Guardian Module — Types
// ============================================================================

export type SessionStatus =
  | 'pending'
  | 'active'
  | 'stale'
  | 'offline'
  | 'exiting'
  | 'overdue_soft'
  | 'overdue_medium'
  | 'overdue_hard'
  | 'sos'
  | 'closing'
  | 'closed';

export type AlertType =
  | 'sos'
  | 'overdue_soft'
  | 'overdue_medium'
  | 'overdue_hard'
  | 'offline'
  | 'stationary'
  | 'exit'
  | 'battery_low'
  | 'closing'
  | 'closed'
  | 'recovered';

export type NotificationChannel = 'push' | 'sms';
export type NotificationStatus =
  | 'queued'
  | 'sent'
  | 'delivered'
  | 'failed'
  | 'skipped';

export interface OverdueThresholds {
  soft: number;
  medium: number;
  hard: number;
}

export interface SessionSettings {
  overdue_thresholds: OverdueThresholds;
  stationary_threshold_min: number;
  offline_threshold_min: number;
  grace_period_min: number;
  recovery_window_min: number;
}

export interface GuardianSession {
  id: string;
  user_id: string;
  status: SessionStatus;
  expected_return: string;
  original_return: string;
  started_at: string;
  closing_started_at: string | null;
  closed_at: string | null;
  recoverable_until: string | null;
  last_known_coords: { lat: number; lng: number } | null;
  last_known_at: string | null;
  last_battery_pct: number | null;
  last_signal_strength: number | null;
  exit_detected_at: string | null;
  sos_activated_at: string | null;
  overdue_level: 'soft' | 'medium' | 'hard' | null;
  settings: SessionSettings;
  created_at: string;
  updated_at: string;
}

export interface Guardian {
  id: string;
  session_id: string;
  name: string | null;
  phone: string | null;
  token_prefix: string;
  is_emergency: boolean;
  notified_at: string | null;
  last_seen_at: string | null;
  revoked_at: string | null;
  created_at: string;
}

export interface GuardianTrackPoint {
  id: number;
  session_id: string;
  coords: { lat: number; lng: number };
  recorded_at: string;
  battery_pct: number | null;
  signal_strength: number | null;
  speed_kmh: number | null;
  was_offline: boolean;
  created_at: string;
}

export interface GuardianAlert {
  id: number;
  session_id: string;
  alert_type: AlertType;
  payload: Record<string, unknown>;
  delivered_at: string | null;
  created_at: string;
}

export interface GuardianNotification {
  id: number;
  guardian_id: string;
  alert_id: number | null;
  channel: NotificationChannel;
  status: NotificationStatus;
  provider_message_id: string | null;
  error_message: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  created_at: string;
}

export interface GuardianTokenPayload {
  session_id: string;
  guardian_id: string;
  role: 'guardian';
  exp: number;
  iat: number;
  jti: string;
}

export interface CreateSessionRequest {
  expected_return: string;
  guardians: Array<{
    name: string;
    phone: string;
    is_emergency?: boolean;
  }>;
  settings?: Partial<SessionSettings>;
}

export interface CreateSessionResponse {
  session: GuardianSession;
  guardians: Array<{
    id: string;
    name: string | null;
    token: string;
    url: string;
  }>;
}
