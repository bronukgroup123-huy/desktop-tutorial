"use client";

import { useEffect, useState } from "react";
import {
  requestPushToken,
  isMessagingSupported,
  onForegroundMessage,
} from "@/lib/firebase";
import { registerGuardianDevice } from "@/lib/api";

export type PushState =
  | "unsupported"
  | "default"
  | "granted"
  | "denied"
  | "registering"
  | "registered"
  | "error";

export function useWebPush(token: string) {
  const [state, setState] = useState<PushState>("default");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isMessagingSupported()) {
      setState("unsupported");
      return;
    }
    if (typeof Notification !== "undefined") {
      setState(Notification.permission as PushState);
    }
  }, []);

  const register = async () => {
    setState("registering");
    setError(null);

    const result = await requestPushToken();
    if (!result.success || !result.token) {
      setState(result.permission === "denied" ? "denied" : "error");
      setError(result.error ?? "Невідома помилка");
      return;
    }

    try {
      await registerGuardianDevice(token, result.token, navigator.userAgent);
      setState("registered");
    } catch (err) {
      setState("error");
      setError(err instanceof Error ? err.message : "Помилка реєстрації");
    }
  };

  useEffect(() => {
    if (state !== "registered") return;

    let unsubscribe: (() => void) | null = null;

    onForegroundMessage((payload) => {
      const title = payload.notification?.title ?? "MushroomRadar";
      const body = payload.notification?.body ?? "";

      if (Notification.permission === "granted") {
        new Notification(title, {
          body,
          icon: "/icons/icon-192.png",
          tag: payload.data?.alert_type ?? "guardian",
        });
      }
    }).then((unsub) => {
      unsubscribe = unsub;
    });

    return () => {
      unsubscribe?.();
    };
  }, [state]);

  return { state, error, register };
}
