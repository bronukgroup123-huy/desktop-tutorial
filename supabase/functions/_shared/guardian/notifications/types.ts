import type { AlertType, NotificationChannel } from "../types.ts";

export interface NotificationTemplate {
  title: string;
  body: string;
  requiresSms: boolean;
  priority: 1 | 2 | 3 | 4 | 5;
}

export interface RenderedNotification {
  title: string;
  body: string;
  url?: string;
  data?: Record<string, string>;
}

export interface DispatchTarget {
  guardian_id: string;
  phone: string | null;
  fcm_tokens: string[];
  is_emergency: boolean;
}

export interface DispatchResult {
  alert_id: number;
  notifications_created: number;
  push_attempted: number;
  sms_attempted: number;
  skipped: number;
}

export interface PushPayload {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  priority: "high" | "normal";
}

export interface SmsPayload {
  phone: string;
  text: string;
}

export interface SendResult {
  success: boolean;
  providerMessageId?: string;
  errorMessage?: string;
}
