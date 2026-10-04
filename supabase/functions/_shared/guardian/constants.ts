export const GUARDIAN_SESSION_STATUSES = [
  "pending", "active", "stale", "offline",
  "exiting", "overdue_soft", "overdue_medium", "overdue_hard",
  "sos", "closing", "closed",
] as const;

export const ALERT_TYPES = [
  "sos",
  "overdue_soft", "overdue_medium", "overdue_hard",
  "offline", "stationary", "exit", "battery_low",
  "closing", "closed", "recovered",
] as const;

export const TOKEN_TTL_HOURS = 24;
export const TOKEN_PREFIX_LENGTH = 8;
export const MAX_GUARDIANS_PER_SESSION = 3;
