/**
 * Усі часові пороги для автоматичних переходів.
 * Можуть перевизначатись через session.settings, але це — defaults.
 */

export const THRESHOLDS = {
  /** Час без ping, після якого active → stale */
  STALE_MIN: 15,

  /** Час без ping, після якого stale → offline */
  OFFLINE_MIN: 60,

  /** Час нерухомості, після якого тривога stationary */
  STATIONARY_MIN: 30,

  /** Мінімальна швидкість (км/год), щоб вважати, що грибник рухається */
  MOVEMENT_SPEED_KMH: 1,

  /** Вікно для обчислення руху (хв) */
  MOVEMENT_WINDOW_MIN: 30,

  /** Час після exiting, коли сесія автоматично закривається */
  EXITING_AUTO_CLOSE_MIN: 60,

  /** Час без ping, після якого pending сесія закривається */
  PENDING_AUTO_CLOSE_HOURS: 24,

  /** Час після last_known_at, коли сесія остаточно закривається (24 год) */
  AUTO_CLOSE_HOURS: 24,
} as const;

/** Дефолтні пороги Overdue (в хвилинах після expected_return) */
export const DEFAULT_OVERDUE_THRESHOLDS = {
  soft: 0,
  medium: 30,
  hard: 90,
} as const;
