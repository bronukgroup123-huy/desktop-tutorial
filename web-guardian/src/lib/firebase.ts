import { initializeApp, getApps, FirebaseApp } from "firebase/app";
import {
  getMessaging,
  getToken,
  onMessage,
  Messaging,
  MessagePayload,
} from "firebase/messaging";

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY!,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID!,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID!,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID!,
};

let app: FirebaseApp | null = null;

function getApp(): FirebaseApp {
  if (app) return app;
  if (getApps().length > 0) {
    app = getApps()[0];
  } else {
    app = initializeApp(firebaseConfig);
  }
  return app;
}

export function isMessagingSupported(): boolean {
  if (typeof window === "undefined") return false;
  return "serviceWorker" in navigator && "PushManager" in window;
}

export async function getMessagingInstance(): Promise<Messaging | null> {
  if (!isMessagingSupported()) return null;
  try {
    return getMessaging(getApp());
  } catch (err) {
    console.error("[firebase] messaging init failed:", err);
    return null;
  }
}

async function registerServiceWorker(): Promise<ServiceWorkerRegistration> {
  const params = new URLSearchParams({
    apiKey: firebaseConfig.apiKey,
    projectId: firebaseConfig.projectId,
    messagingSenderId: firebaseConfig.messagingSenderId,
    appId: firebaseConfig.appId,
  });

  return navigator.serviceWorker.register(
    `/firebase-messaging-sw.js?${params.toString()}`,
    { scope: "/" }
  );
}

export interface PushRegistrationResult {
  success: boolean;
  token?: string;
  error?: string;
  permission: NotificationPermission;
}

export async function requestPushToken(): Promise<PushRegistrationResult> {
  if (!isMessagingSupported()) {
    return {
      success: false,
      error: "Push не підтримується цим браузером",
      permission: "denied",
    };
  }

  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    return {
      success: false,
      error: "Користувач відмовив у дозволі",
      permission,
    };
  }

  try {
    await registerServiceWorker();

    const messaging = await getMessagingInstance();
    if (!messaging) {
      return {
        success: false,
        error: "Messaging не ініціалізовано",
        permission,
      };
    }

    const vapidKey = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY;
    if (!vapidKey) {
      return {
        success: false,
        error: "VAPID key не виставлено",
        permission,
      };
    }

    const token = await getToken(messaging, { vapidKey });

    if (!token) {
      return {
        success: false,
        error: "FCM не видав токен",
        permission,
      };
    }

    return { success: true, token, permission };
  } catch (err) {
    return {
      success: false,
      error: err instanceof Error ? err.message : "Невідома помилка",
      permission,
    };
  }
}

export async function onForegroundMessage(
  callback: (payload: MessagePayload) => void
): Promise<() => void> {
  const messaging = await getMessagingInstance();
  if (!messaging) return () => {};

  const unsubscribe = onMessage(messaging, callback);
  return unsubscribe;
}
