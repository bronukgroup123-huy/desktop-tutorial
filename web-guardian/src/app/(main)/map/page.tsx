"use client";

import { useCallback, useState } from "react";
import { MapCanvas, type PickedPoint } from "@/components/map/MapCanvas";
import { FUNCTIONS_URL } from "@/lib/constants";
import type { ForecastResponse } from "@/lib/types/forecast";

export default function MapPage() {
  const [forecast, setForecast] = useState<ForecastResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [bottomSheetOpen, setBottomSheetOpen] = useState(false);

  const handlePick = useCallback(async ({ lat, lng }: PickedPoint) => {
    const date = new Date().toISOString().slice(0, 10);
    setLoading(true);
    setBottomSheetOpen(true);
    try {
      const res = await fetch(`${FUNCTIONS_URL}/v1-forecast`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ lat, lng, date }),
      });
      if (!res.ok) throw new Error(`Forecast error: ${res.status}`);
      const data: ForecastResponse = await res.json();
      setForecast(data);
    } catch (err) {
      console.error("Forecast load failed:", err);
      setForecast(null);
    } finally {
      setLoading(false);
    }
  }, []);

  const closeSheet = () => {
    setBottomSheetOpen(false);
    setForecast(null);
  };

  return (
    <div
      className="relative w-full overflow-hidden"
      style={{ height: "calc(var(--app-vh) - var(--nav-h))" }}
    >
      <MapCanvas onPick={handlePick} />

      <div
        className={`fixed left-0 right-0 z-40 rounded-t-2xl bg-white shadow-lift transition-transform duration-300 ease-out ${
          bottomSheetOpen ? "translate-y-0" : "translate-y-full"
        }`}
        style={{
          bottom: "calc(var(--nav-h) + env(safe-area-inset-bottom))",
        }}
      >
        <div className="flex items-center border-b border-cream-200 p-4">
          <button
            onClick={closeSheet}
            className="text-2xl text-ink-muted transition-colors hover:text-ink"
            aria-label="Закрити"
          >
            ×
          </button>
          <h2 className="flex-1 text-center font-serif text-lg font-semibold text-forest-dark">
            Аналіз району 5×5 км
          </h2>
          <div className="w-8" />
        </div>

        <div className="max-h-[55vh] overflow-y-auto p-5">
          {loading ? (
            <div className="flex flex-col items-center justify-center py-8">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-cream-200 border-t-amberbrand" />
              <p className="mt-3 text-sm text-ink-muted">
                Завантаження прогнозу…
              </p>
            </div>
          ) : forecast ? (
            <div className="space-y-4">
              {forecast.top1 && (
                <div className="rounded-xl bg-forest-light/60 p-4">
                  <div className="mb-2 flex items-center gap-2">
                    <span
                      className="rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider text-white"
                      style={{ backgroundColor: forecast.top1.level_color }}
                    >
                      {forecast.top1.level_label}
                    </span>
                  </div>
                  <h3 className="text-xl font-bold text-forest-dark">
                    {forecast.top1.name_ua}
                  </h3>
                  <p className="text-sm text-ink-muted">
                    <span className="font-medium">Коли:</span>{" "}
                    {forecast.top1.when_label}
                  </p>
                  <p className="text-sm text-ink-muted">
                    <span className="font-medium">Де шукати:</span>{" "}
                    {forecast.top1.where_label}
                  </p>
                  {forecast.top1.why_labels.length > 0 && (
                    <div className="mt-3 border-t border-cream-200 pt-3">
                      <p className="mb-1 text-xs font-medium text-ink-muted">
                        Чому саме цей гриб:
                      </p>
                      <div className="flex flex-wrap gap-1.5">
                        {forecast.top1.why_labels.map((label, i) => (
                          <span
                            key={i}
                            className="rounded bg-cream-100 px-2 py-1 text-xs text-forest-dark"
                          >
                            {label}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}

              {forecast.alternative && (
                <div className="rounded-xl bg-cream-100 p-4">
                  <h4 className="mb-2 text-xs font-semibold uppercase tracking-wider text-ink-muted">
                    Альтернатива
                  </h4>
                  <div className="mb-2 flex items-center gap-2">
                    <span
                      className="rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider text-white"
                      style={{ backgroundColor: forecast.alternative.level_color }}
                    >
                      {forecast.alternative.level_label}
                    </span>
                  </div>
                  <h3 className="text-lg font-bold text-forest-dark">
                    {forecast.alternative.name_ua}
                  </h3>
                  <p className="text-sm text-ink-muted">
                    <span className="font-medium">Коли:</span>{" "}
                    {forecast.alternative.when_label}
                  </p>
                  <p className="text-sm text-ink-muted">
                    <span className="font-medium">Де шукати:</span>{" "}
                    {forecast.alternative.where_label}
                  </p>
                </div>
              )}

              {forecast.warnings.length > 0 && (
                <div className="rounded-xl border border-amberbrand/30 bg-amberbrand/5 p-4">
                  <h4 className="mb-2 text-xs font-semibold uppercase tracking-wider text-amberbrand">
                    Увага
                  </h4>
                  <ul className="space-y-1 text-sm text-ink-muted">
                    {forecast.warnings.map((w, i) => (
                      <li key={i} className="flex items-start gap-2">
                        <span className="shrink-0 text-amberbrand">⚠</span>
                        {w}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          ) : (
            <div className="py-12 text-center text-ink-muted">
              <p className="text-sm">Клацніть на карту для прогнозу грибів</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
