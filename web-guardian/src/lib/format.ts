import type { SessionStatus } from "./types";

export function formatTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleTimeString("uk-UA", {
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function formatDateTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString("uk-UA", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function formatRelativeSeconds(seconds: number | null): string {
  if (seconds === null) return "—";
  if (seconds < 60) return `${seconds} сек тому`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} хв тому`;
  const hours = Math.floor(minutes / 60);
  return `${hours} год тому`;
}

export function formatDuration(minutes: number): string {
  if (minutes < 0) {
    const absMin = Math.abs(minutes);
    if (absMin < 60) return `прострочено ${absMin} хв`;
    const hours = Math.floor(absMin / 60);
    const rest = absMin % 60;
    return `прострочено ${hours} год ${rest} хв`;
  }
  if (minutes < 60) return `через ${minutes} хв`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `через ${hours} год` : `через ${hours} год ${rest} хв`;
}

export interface StatusStyle {
  label: string;
  color: string;
  bgColor: string;
  emoji: string;
  isUrgent: boolean;
}

export function getStatusStyle(status: SessionStatus): StatusStyle {
  const map: Record<SessionStatus, StatusStyle> = {
    pending: {
      label: "Очікуємо сигнал",
      color: "text-gray-600",
      bgColor: "bg-gray-100",
      emoji: "⏳",
      isUrgent: false,
    },
    active: {
      label: "У лісі",
      color: "text-green-700",
      bgColor: "bg-green-100",
      emoji: "🟢",
      isUrgent: false,
    },
    stale: {
      label: "Немає свіжого сигналу",
      color: "text-yellow-700",
      bgColor: "bg-yellow-100",
      emoji: "🟡",
      isUrgent: false,
    },
    offline: {
      label: "Не на зв'язку",
      color: "text-gray-700",
      bgColor: "bg-gray-200",
      emoji: "⚪",
      isUrgent: false,
    },
    exiting: {
      label: "Виходить з лісу",
      color: "text-blue-700",
      bgColor: "bg-blue-100",
      emoji: "🔵",
      isUrgent: false,
    },
    overdue_soft: {
      label: "Затримується",
      color: "text-orange-700",
      bgColor: "bg-orange-100",
      emoji: "🟠",
      isUrgent: false,
    },
    overdue_medium: {
      label: "Немає зв'язку після часу",
      color: "text-orange-800",
      bgColor: "bg-orange-200",
      emoji: "🟠",
      isUrgent: true,
    },
    overdue_hard: {
      label: "Терміново! Час минув",
      color: "text-red-800",
      bgColor: "bg-red-200",
      emoji: "🔴",
      isUrgent: true,
    },
    sos: {
      label: "SOS!",
      color: "text-white",
      bgColor: "bg-red-600",
      emoji: "🔴",
      isUrgent: true,
    },
    closing: {
      label: "Завершує сесію",
      color: "text-gray-700",
      bgColor: "bg-gray-100",
      emoji: "⏹",
      isUrgent: false,
    },
    closed: {
      label: "Сесія закрита",
      color: "text-gray-600",
      bgColor: "bg-gray-100",
      emoji: "✅",
      isUrgent: false,
    },
  };
  return map[status];
}

export function formatCoords(coords: { lat: number; lng: number } | null): string {
  if (!coords) return "—";
  return `${coords.lat.toFixed(5)}, ${coords.lng.toFixed(5)}`;
}

export function distanceKm(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number }
): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;

  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export function formatBattery(pct: number | null): string {
  if (pct === null) return "—";
  return `${pct}%`;
}

export function getBatteryColor(pct: number | null): string {
  if (pct === null) return "text-gray-400";
  if (pct <= 10) return "text-red-600";
  if (pct <= 25) return "text-orange-500";
  return "text-gray-700";
}

export function formatSignal(strength: number | null): string {
  if (strength === null) return "—";
  const bars = ["▁", "▂", "▃", "▄", "▅"];
  return bars.slice(0, strength).join("") || "—";
}
