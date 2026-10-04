import type { AlertType } from "../types.ts";
import type { NotificationTemplate, RenderedNotification } from "./types.ts";

const TEMPLATES: Record<AlertType, NotificationTemplate> = {
  sos: {
    title: "🔴 SOS!",
    body: "{name} потребує допомоги! Координати: {lat}, {lng}",
    requiresSms: true,
    priority: 1,
  },

  overdue_hard: {
    title: "🔴 {name} не виходить на зв'язок",
    body: "Час повернення минув {minutes_over} хв тому. Рекомендуємо зв'язатися з 101.",
    requiresSms: true,
    priority: 1,
  },

  overdue_medium: {
    title: "🟠 {name} затримується",
    body: "Час повернення минув {minutes_over} хв тому. Зв'язку немає.",
    requiresSms: true,
    priority: 2,
  },

  overdue_soft: {
    title: "🟠 {name} затримується",
    body: "Мав вийти о {expected_return}. Ймовірно, затримується.",
    requiresSms: false,
    priority: 3,
  },

  offline: {
    title: "⚪ {name} не на зв'язку",
    body: "Останній сигнал {minutes_since_ping} хв тому.",
    requiresSms: false,
    priority: 3,
  },

  stationary: {
    title: "🟡 {name} стоїть на місці",
    body: "Не рухається {minutes_stationary} хв.",
    requiresSms: false,
    priority: 4,
  },

  exit: {
    title: "✅ {name} виходить з лісу",
    body: "Автоматично визначено о {time}.",
    requiresSms: false,
    priority: 5,
  },

  battery_low: {
    title: "🔋 Батарея {name} садиться",
    body: "Заряд: {battery_pct}%. Можливий втрата зв'язку найближчим часом.",
    requiresSms: false,
    priority: 4,
  },

  closing: {
    title: "{name} завершує сесію",
    body: "Grace period: {grace_period_min} хв. Можете продовжити, якщо це помилка.",
    requiresSms: false,
    priority: 4,
  },

  closed: {
    title: "Сесія {name} закрита",
    body: "Причина: {reason}.",
    requiresSms: false,
    priority: 5,
  },

  recovered: {
    title: "Сесія {name} відновлена",
    body: "{name} продовжив сесію.",
    requiresSms: false,
    priority: 4,
  },
};

export function renderNotification(
  alertType: AlertType,
  payload: Record<string, unknown>,
  context: {
    picker_name: string;
    session_url: string;
    guardian_url: string;
    coords?: { lat: number; lng: number } | null;
    expected_return?: string;
  }
): RenderedNotification {
  if (alertType === "recovered" && payload.action === "sos_cancelled") {
    return {
      title: "✅ SOS скасовано",
      body: `${context.picker_name} скасував сигнал SOS. Ситуація під контролем.`,
      url: context.guardian_url,
      data: {
        alert_type: "recovered",
        subtype: "sos_cancelled",
        session_id: String(payload.session_id ?? ""),
      },
    };
  }

  if (alertType === "recovered" && payload.action === "user_recovered") {
    return {
      title: "Сесія відновлена",
      body: `${context.picker_name} продовжив сесію.`,
      url: context.guardian_url,
      data: {
        alert_type: "recovered",
        subtype: "user_recovered",
        session_id: String(payload.session_id ?? ""),
      },
    };
  }

  const template = TEMPLATES[alertType];

  const vars: Record<string, string> = {
    name: context.picker_name,
    ...Object.fromEntries(
      Object.entries(payload).map(([k, v]) => [k, String(v)])
    ),
  };

  if (context.coords) {
    vars.lat = String(context.coords.lat);
    vars.lng = String(context.coords.lng);
  }

  if (context.expected_return) {
    try {
      const d = new Date(context.expected_return);
      vars.expected_return = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
    } catch {
      vars.expected_return = context.expected_return;
    }
  }

  const now = new Date();
  vars.time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;

  return {
    title: interpolate(template.title, vars),
    body: interpolate(template.body, vars),
    url: context.guardian_url,
    data: {
      alert_type: alertType,
      session_id: String(payload.session_id ?? ""),
      click_action: "OPEN_GUARDIAN_PAGE",
    },
  };
}

export function getTemplate(alertType: AlertType): NotificationTemplate {
  return TEMPLATES[alertType];
}

function interpolate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_, key) => vars[key] ?? `{${key}}`);
}

export const _internal = {
  TEMPLATES,
  interpolate,
};
