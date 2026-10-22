"use client";

import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { ForecastResponse, ForestZonesResponse } from "@/lib/types/forecast";
import { FUNCTIONS_URL } from "@/lib/constants";

const KYIV_CENTER: [number, number] = [30.52, 50.45];
const INITIAL_ZOOM = 10;
const DEBOUNCE_MS = 400;

function debounce<Args extends unknown[]>(
  fn: (...args: Args) => void,
  ms: number
): (...args: Args) => void {
  let timer: ReturnType<typeof setTimeout> | null = null;
  return (...args: Args) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

export default function MapPage() {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const [forecast, setForecast] = useState<ForecastResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [bottomSheetOpen, setBottomSheetOpen] = useState(false);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const map = new maplibregl.Map({
      container: containerRef.current,
      style: {
        version: 8,
        sources: {
          osm: {
            type: "raster",
            tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
            tileSize: 256,
            attribution: "© OpenStreetMap",
          },
        },
        layers: [
          {
            id: "osm",
            type: "raster",
            source: "osm",
            minzoom: 0,
            maxzoom: 19,
          },
        ],
      },
      center: KYIV_CENTER,
      zoom: INITIAL_ZOOM,
    });

    map.addControl(new maplibregl.NavigationControl(), "top-right");
    mapRef.current = map;

    map.on("load", () => {
      map.addSource("forest-zones", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });

      map.addLayer({
        id: "forest-zones-fill",
        type: "fill",
        source: "forest-zones",
        paint: { "fill-color": "#22c55e", "fill-opacity": 0.3 },
      });

      map.addLayer({
        id: "forest-zones-outline",
        type: "line",
        source: "forest-zones",
        paint: {
          "line-color": "#22c55e",
          "line-width": 0.6,
          "line-opacity": 0.6,
        },
      });
    });

    const handleMoveEnd = debounce(async () => {
      const m = mapRef.current;
      if (!m || !m.isStyleLoaded()) return;
      const bounds = m.getBounds();
      const bbox = [
        bounds.getWest(),
        bounds.getSouth(),
        bounds.getEast(),
        bounds.getNorth(),
      ];
      try {
        const res = await fetch(
          `${FUNCTIONS_URL}/v1-forest-zones?bbox=${bbox.join(",")}&limit=5000`
        );
        if (!res.ok) return;
        const data: ForestZonesResponse = await res.json();
        const source = m.getSource(
          "forest-zones"
        ) as maplibregl.GeoJSONSource | undefined;
        if (source) source.setData(data as unknown as GeoJSON.FeatureCollection);
      } catch (err) {
        console.error("Forest zones load failed:", err);
      }
    }, DEBOUNCE_MS);

    map.on("moveend", handleMoveEnd);

    const handleClick = async (e: maplibregl.MapMouseEvent) => {
      const { lat, lng } = e.lngLat;
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
    };

    map.on("click", handleClick);

    return () => {
      map.off("moveend", handleMoveEnd);
      map.off("click", handleClick);
      map.remove();
      mapRef.current = null;
    };
  }, []);

  const closeSheet = () => {
    setBottomSheetOpen(false);
    setForecast(null);
  };

  return (
    <div className="relative h-screen w-full overflow-hidden">
      <div ref={containerRef} className="absolute inset-0 z-0" />

      <div
        className={`fixed bottom-0 left-0 right-0 z-50 bg-white rounded-t-2xl shadow-2xl transition-transform duration-300 ease-out ${
          bottomSheetOpen ? "translate-y-0" : "translate-y-full"
        }`}
      >
        <div className="p-4 border-b border-gray-200 flex items-center justify-between">
          <button
            onClick={closeSheet}
            className="text-2xl text-gray-400 hover:text-gray-600 leading-none"
            aria-label="Закрити"
          >
            ×
          </button>
          <h2 className="text-lg font-semibold text-gray-900 flex-1 text-center">
            Аналіз району 5×5 км
          </h2>
          <div className="w-8" />
        </div>

        <div className="p-6">
          {loading ? (
            <div className="flex flex-col items-center justify-center py-8">
              <div
                className="w-8 h-8 border-4 border-gray-200 border-t-blue-500 rounded-full animate-spin"
              />
              <p className="mt-3 text-sm text-gray-600">
                Завантаження прогнозу…
              </p>
            </div>
          ) : forecast ? (
            <div className="space-y-4">
              {forecast.top1 && (
                <div className="bg-blue-50 rounded-xl p-4 border border-blue-100">
                  <div className="flex items-center gap-2 mb-2">
                    <span
                      className="px-2.5 py-0.5 rounded-full text-xs font-semibold uppercase tracking-wider"
                      style={{
                        backgroundColor: forecast.top1.level_color,
                        color: "#ffffff",
                      }}
                    >
                      {forecast.top1.level_label}
                    </span>
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">
                    {forecast.top1.name_ua}
                  </h3>
                  <p className="text-sm text-gray-600">
                    <span className="font-medium">Коли:</span>{" "}
                    {forecast.top1.when_label}
                  </p>
                  <p className="text-sm text-gray-600">
                    <span className="font-medium">Де шукати:</span>{" "}
                    {forecast.top1.where_label}
                  </p>
                  {forecast.top1.why_labels.length > 0 && (
                    <div className="mt-3 pt-3 border-t border-gray-200">
                      <p className="text-xs font-medium text-gray-500 mb-1">
                        Чому саме цей гриб:
                      </p>
                      <div className="flex flex-wrap gap-1.5">
                        {forecast.top1.why_labels.map((label, i) => (
                          <span
                            key={i}
                            className="px-2 py-1 rounded bg-gray-100 text-xs text-gray-700"
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
                <div className="bg-gray-50 rounded-xl p-4 border border-gray-100">
                  <h4 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">
                    Альтернатива
                  </h4>
                  <div className="flex items-center gap-2 mb-2">
                    <span
                      className="px-2.5 py-0.5 rounded-full text-xs font-semibold uppercase tracking-wider"
                      style={{
                        backgroundColor: forecast.alternative.level_color,
                        color: "#ffffff",
                      }}
                    >
                      {forecast.alternative.level_label}
                    </span>
                  </div>
                  <h3 className="text-lg font-bold text-gray-800">
                    {forecast.alternative.name_ua}
                  </h3>
                  <p className="text-sm text-gray-600">
                    <span className="font-medium">Коли:</span>{" "}
                    {forecast.alternative.when_label}
                  </p>
                  <p className="text-sm text-gray-600">
                    <span className="font-medium">Де шукати:</span>{" "}
                    {forecast.alternative.where_label}
                  </p>
                </div>
              )}

              {forecast.warnings.length > 0 && (
                <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4">
                  <h4 className="text-xs font-semibold text-yellow-800 uppercase tracking-wider mb-2">
                    Увага
                  </h4>
                  <ul className="text-sm text-yellow-700 space-y-1">
                    {forecast.warnings.map((w, i) => (
                      <li key={i} className="flex items-start gap-2">
                        <span className="text-yellow-500 shrink-0">⚠</span>
                        {w}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          ) : (
            <div className="text-center py-12 text-gray-400">
              <p className="text-sm">Клацніть на карту для прогнозу грибів</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
