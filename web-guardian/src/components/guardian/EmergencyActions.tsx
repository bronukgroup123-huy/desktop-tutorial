"use client";

import { AlertTriangle, Phone } from "lucide-react";
import { useGuardianStore } from "@/store/guardian-store";
import { formatCoords } from "@/lib/format";

export function EmergencyActions() {
  const session = useGuardianStore((s) => s.session);

  if (!session) return null;

  const isEmergency =
    session.status === "sos" ||
    session.status === "overdue_hard";

  if (!isEmergency) return null;

  const coords = session.last_known_coords;
  const coordsText = coords
    ? `${coords.lat.toFixed(5)}, ${coords.lng.toFixed(5)}`
    : "невідомо";

  const handleCall101 = () => {
    window.location.href = "tel:101";
  };

  return (
    <div className="fixed bottom-20 left-4 right-4 z-30 bg-red-600 text-white rounded-lg shadow-xl p-4">
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-6 h-6 flex-shrink-0 animate-pulse" />
        <div className="flex-1">
          <p className="font-bold text-lg">
            {session.status === "sos" ? "SOS!" : "Терміново!"}
          </p>
          <p className="text-sm mt-1">
            Координати: {coordsText}
          </p>
          {session.sos_activated_at && (
            <p className="text-xs mt-1 opacity-90">
              Активовано: {new Date(session.sos_activated_at).toLocaleTimeString("uk-UA")}
            </p>
          )}
        </div>
      </div>

      <button
        onClick={handleCall101}
        className="mt-3 w-full bg-white text-red-700 font-bold py-3 rounded-lg flex items-center justify-center gap-2"
      >
        <Phone className="w-5 h-5" />
        Подзвонити 101
      </button>
    </div>
  );
}
