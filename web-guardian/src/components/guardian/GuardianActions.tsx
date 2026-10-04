"use client";

import { Phone, Download, Route, MessageSquare } from "lucide-react";
import { useGuardianStore } from "@/store/guardian-store";
import { getGpxUrl } from "@/lib/api";

export function GuardianActions({ token }: { token: string }) {
  const session = useGuardianStore((s) => s.session);

  if (!session) return null;

  const handleRoute = () => {
    if (!session.last_known_coords) return;
    const { lat, lng } = session.last_known_coords;
    window.open(
      `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`,
      "_blank"
    );
  };

  const handleGpx = () => {
    window.location.href = getGpxUrl(token);
  };

  const handleCall = () => {
    const phone = window.prompt("Номер телефону грибника:");
    if (phone) window.location.href = `tel:${phone}`;
  };

  const handleSms = () => {
    const phone = window.prompt("Номер телефону грибника:");
    if (phone) {
      window.location.href = `sms:${phone}?body=${encodeURIComponent(
        "Ти як? Я слідкую за тобою через MushroomRadar."
      )}`;
    }
  };

  return (
    <div className="grid grid-cols-4 gap-2 bg-white border-t border-gray-200 px-4 py-3">
      <button
        onClick={handleRoute}
        className="flex flex-col items-center gap-1 p-2 rounded-lg hover:bg-gray-50"
        aria-label="Прокласти маршрут"
      >
        <Route className="w-5 h-5 text-blue-600" />
        <span className="text-xs">Маршрут</span>
      </button>

      <button
        onClick={handleGpx}
        className="flex flex-col items-center gap-1 p-2 rounded-lg hover:bg-gray-50"
        aria-label="Завантажити GPX"
      >
        <Download className="w-5 h-5 text-gray-700" />
        <span className="text-xs">GPX</span>
      </button>

      <button
        onClick={handleCall}
        className="flex flex-col items-center gap-1 p-2 rounded-lg hover:bg-gray-50"
        aria-label="Подзвонити"
      >
        <Phone className="w-5 h-5 text-green-600" />
        <span className="text-xs">Дзвінок</span>
      </button>

      <button
        onClick={handleSms}
        className="flex flex-col items-center gap-1 p-2 rounded-lg hover:bg-gray-50"
        aria-label="Написати SMS"
      >
        <MessageSquare className="w-5 h-5 text-blue-600" />
        <span className="text-xs">SMS</span>
      </button>
    </div>
  );
}
