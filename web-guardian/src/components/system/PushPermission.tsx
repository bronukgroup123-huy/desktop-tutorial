"use client";

import { Bell, BellOff } from "lucide-react";
import { useWebPush } from "@/hooks/useWebPush";

export function PushPermission({ token }: { token: string }) {
  const { state, error, register } = useWebPush(token);

  if (state === "unsupported") {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-3 text-sm text-gray-600">
        <BellOff className="w-4 h-4 inline mr-1" />
        Ваш браузер не підтримує push-повідомлення
      </div>
    );
  }

  if (state === "registered") {
    return (
      <div className="bg-green-50 border border-green-200 rounded-lg p-3 text-sm text-green-700 flex items-center gap-2">
        <Bell className="w-4 h-4" />
        Сповіщення увімкнено
      </div>
    );
  }

  if (state === "denied") {
    return (
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3 text-sm text-yellow-800">
        <BellOff className="w-4 h-4 inline mr-1" />
        Сповіщення заблоковано. Увімкніть у налаштуваннях браузера.
      </div>
    );
  }

  return (
    <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
      <div className="flex items-center gap-2 mb-2">
        <Bell className="w-4 h-4 text-blue-600" />
        <span className="text-sm font-medium text-blue-900">
          Увімкніть сповіщення
        </span>
      </div>
      <p className="text-xs text-blue-800 mb-2">
        Отримуйте миттєві тривоги, коли грибник потребує допомоги.
      </p>
      <button
        onClick={register}
        disabled={state === "registering"}
        className="w-full bg-blue-600 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
      >
        {state === "registering" ? "Реєстрація..." : "Увімкнути"}
      </button>
      {error && <p className="text-xs text-red-600 mt-2">{error}</p>}
    </div>
  );
}
