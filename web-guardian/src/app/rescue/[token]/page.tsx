"use client";

import { use, useEffect, useState } from "react";
import { fetchRescue, getRescueGpxUrl, GuardianApiError } from "@/lib/api";
import { formatCoords, formatDateTime } from "@/lib/format";
import type { RescueView } from "@/lib/types";

export default function RescuePage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
  const [rescue, setRescue] = useState<RescueView | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchRescue(token)
      .then(setRescue)
      .catch((err) => {
        if (err instanceof GuardianApiError) setError(err.message);
        else setError("Помилка завантаження");
      });
  }, [token]);

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen p-6 text-center">
        <h1 className="text-xl font-bold mb-2">Запит недоступний</h1>
        <p className="text-gray-600">{error}</p>
      </div>
    );
  }

  if (!rescue) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-red-600" />
      </div>
    );
  }

  const coords = rescue.session.last_known_coords;

  return (
    <div className="max-w-2xl mx-auto p-4">
      <div className="bg-red-50 border-2 border-red-500 rounded-lg p-4 mb-4">
        <h1 className="text-2xl font-bold text-red-700 mb-1">
          Запит на допомогу
        </h1>
        <p className="text-sm text-red-600">
          Створено: {formatDateTime(rescue.created_at)}
        </p>
      </div>

      <div className="bg-white rounded-lg shadow p-4 mb-4">
        <h2 className="font-semibold text-lg mb-3">Грибник</h2>
        <p><span className="text-gray-500">Ім'я:</span> {rescue.picker.name}</p>
        <p><span className="text-gray-500">Статус:</span> {rescue.session.status}</p>
        <p><span className="text-gray-500">Початок:</span> {formatDateTime(rescue.session.started_at)}</p>
        <p><span className="text-gray-500">Планове повернення:</span> {formatDateTime(rescue.session.expected_return)}</p>
      </div>

      <div className="bg-white rounded-lg shadow p-4 mb-4">
        <h2 className="font-semibold text-lg mb-3">Остання позиція</h2>
        <p className="text-2xl font-mono">{formatCoords(coords)}</p>
        <p className="text-sm text-gray-500 mt-1">
          Оновлено: {formatDateTime(rescue.session.last_known_at)}
        </p>
        {rescue.session.sos_activated_at && (
          <p className="text-red-600 font-medium mt-2">
            🔴 SOS активовано: {formatDateTime(rescue.session.sos_activated_at)}
          </p>
        )}
      </div>

      {rescue.notes && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-4">
          <h2 className="font-semibold mb-2">Примітка грибника</h2>
          <p>{rescue.notes}</p>
        </div>
      )}

      <div className="grid grid-cols-2 gap-3">
        <a
          href={getRescueGpxUrl(token)}
          className="bg-green-600 text-white text-center py-4 rounded-lg font-medium"
        >
          Завантажити GPX
        </a>
        <a
          href={`https://www.google.com/maps/dir/?api=1&destination=${coords?.lat},${coords?.lng}`}
          target="_blank"
          rel="noopener"
          className="bg-blue-600 text-white text-center py-4 rounded-lg font-medium"
        >
          Маршрут у Google Maps
        </a>
      </div>

      <p className="text-xs text-gray-500 mt-6 text-center">
        Запит дійсний до: {formatDateTime(rescue.expires_at)}
      </p>
    </div>
  );
}
