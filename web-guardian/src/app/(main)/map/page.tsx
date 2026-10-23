"use client";

import { useCallback, useState, useEffect } from "react";
import dynamic from "next/dynamic";
import { FUNCTIONS_URL } from "@/lib/constants";
import type { ForecastResponse } from "@/lib/types/forecast";

const MapCanvas = dynamic(() => import("@/components/map/MapCanvas").then(mod => ({ default: mod.MapCanvas })), { ssr: false });

export default function MapPage() {
  const [forecast, setForecast] = useState<any | null>(null);
  const [loading, setLoading] = useState(false);
  const [bottomSheetOpen, setBottomSheetOpen] = useState(false);
  const [activeLayer, setActiveLayer] = useState<"forest" | "heat" | "my">("forest");
  const [userLocation, setUserLocation] = useState<{ lat: number; lng: number } | null>(null);

  const formatCoords = (lat: number, lng: number) => {
    const latDir = lat >= 0 ? "N" : "S";
    const lngDir = lng >= 0 ? "E" : "W";
    return Math.abs(lat).toFixed(2) + latDir + " \u00b7 " + Math.abs(lng).toFixed(2) + lngDir;
  };

  const handleLayerChange = (layer: "forest" | "heat" | "my") => {
    setActiveLayer(layer);
  };

  const handlePick = useCallback(async ({ lat, lng }: { lat: number; lng: number }) => {
    const date = new Date().toISOString().slice(0, 10);
    setLoading(true);
    setBottomSheetOpen(true);
    try {
      const res = await fetch(FUNCTIONS_URL + "/v1-forecast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ lat, lng, date }),
      });
      if (!res.ok) throw new Error("Forecast error: " + res.status);
      const data = await res.json();
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

  useEffect(() => {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => setUserLocation({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
        () => setUserLocation({ lat: 50.45, lng: 30.52 })
      );
    } else {
      setUserLocation({ lat: 50.45, lng: 30.52 });
    }
  }, []);

  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50">
      <header className="p-4 flex flex-col gap-2 border-b border-cream-300 bg-white">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[11px] text-ink-muted font-medium">
              {userLocation ? (userLocation.lat.toFixed(2) + (userLocation.lat >= 0 ? "N" : "S") + " \u00b7 " + userLocation.lng.toFixed(2) + (userLocation.lng >= 0 ? "E" : "W")) : "50.45N \u00b7 30.52E"}
            </div>
            <h1 className="font-serif font-semibold text-forest-dark text-[26px] leading-tight">Карта</h1>
          </div>
          <button className="p-2 rounded-xl bg-cream-200 text-ink-muted hover:bg-cream-300 transition-colors" aria-label="Оновити">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 12a9 9 0 1 1-3-6.7L21 8" />
              <path d="M21 3v5h-5" />
            </svg>
          </button>
        </div>

        <div className="flex gap-2 overflow-x-auto scroll-hide px-4 pb-2">
          <button
            onClick={() => setActiveLayer("forest")}
            className="layer-toggle flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-full border border-cream-300 bg-white text-ink-muted transition-all"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 2 4 7v10l8 5 8-5V7z" />
            </svg>
            Тип лісу
          </button>
          <button
            onClick={() => setActiveLayer("heat")}
            className="layer-toggle flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-full border border-cream-300 bg-white text-ink-muted transition-all"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
              <path d="M13 2 3 14h9l-1 8 10-12h-9z" />
            </svg>
            Теплова
          </button>
          <button
            onClick={() => setActiveLayer("my")}
            className="layer-toggle flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-full border border-cream-300 bg-white text-ink-muted transition-all"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
              <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z" />
              <circle cx="12" cy="10" r="3" />
            </svg>
            Мої точки
          </button>
        </div>
      </header>

      <div className="flex-1 relative min-h-0 mx-4 mb-4 rounded-3xl overflow-hidden border border-cream-300 shadow-lg">
        <MapCanvas onPick={handlePick} activeLayer={activeLayer} />
      </div>

      <div className="fixed left-0 right-0 z-40 bg-white rounded-t-3xl shadow-xl p-4 transition-transform duration-300 ease-out translate-y-full" style={{ bottom: "var(--nav-h)" }}>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-xl font-semibold text-forest-dark">Білий гриб</h2>
          <button className="text-2xl text-ink-muted hover:text-ink" aria-label="Закрити">×</button>
        </div>

        <div className="text-center py-12 text-ink-muted">
          <p className="text-sm">Клацніть на карту для прогнозу грибів</p>
        </div>

        <div className="mt-4 flex items-center gap-4 text-[10px] text-ink-muted">
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#4A6B54" }} />
            <span>Вериф.</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#C97A2B" }} />
            <span>Умовна</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#8B7F6E" }} />
            <span>Очікує</span>
          </div>
        </div>
      </div>
    </div>
  );
}
