"use client";

import { useCallback, useState, useEffect } from "react";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { Filter, X } from "lucide-react";
import { FUNCTIONS_URL } from "@/lib/constants";
import type { ForecastResponse } from "@/lib/types/forecast";

const MapCanvas = dynamic(() => import("@/components/map/MapCanvas").then((mod) => ({ default: mod.MapCanvas })), { ssr: false });

const FOREST_TYPES = [
  { value: "all", label: "All", icon: null },
  { value: "pine", label: "Pine", icon: null },
  { value: "oak", label: "Oak", icon: null },
  { value: "birch", label: "Birch", icon: null },
  { value: "mixed", label: "Mixed", icon: null },
] as const;

export default function MapPage() {
  const router = useRouter();
  const [forecast, setForecast] = useState<any | null>(null);
  const [loading, setLoading] = useState(false);
  const [bottomSheetOpen, setBottomSheetOpen] = useState(false);
  const [activeLayer, setActiveLayer] = useState<"forest" | "heat" | "my">("forest");
  const [userLocation, setUserLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [selectedForest, setSelectedForest] = useState<any | null>(null);
  const [showForestTypeMenu, setShowForestTypeMenu] = useState(false);
  const [forestTypeFilter, setForestTypeFilter] = useState<string | null>(null);
  const [longPressMenu, setLongPressMenu] = useState<{ feature: any; lngLat: { lat: number; lng: number } } | null>(null);

  const formatCoords = (lat: number, lng: number) => {
    const latDir = lat >= 0 ? "N" : "S";
    const lngDir = lng >= 0 ? "E" : "W";
    return Math.abs(lat).toFixed(2) + latDir + " · " + Math.abs(lng).toFixed(2) + lngDir;
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
    setSelectedForest(null);
  };

  const handleForestClick = useCallback((feature: any) => {
    setSelectedForest(feature);
    setBottomSheetOpen(true);
  }, []);

  const handleLongPress = useCallback((feature: any, lngLat: { lat: number; lng: number }) => {
    setLongPressMenu({ feature, lngLat });
  }, []);

  const handleAddRoute = () => {
    if (longPressMenu) {
      const { lngLat } = longPressMenu;
      router.push("/safety?destLat=" + lngLat.lat + "&destLng=" + lngLat.lng);
      setLongPressMenu(null);
    }
  };

  const closeLongPressMenu = () => setLongPressMenu(null);

  const handleForestTypeChange = (type: string | null) => {
    setForestTypeFilter(type === "all" ? null : type);
    setShowForestTypeMenu(false);
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
              50.45N · 30.52E
            </div>
            <h1 className="font-serif font-semibold text-forest-dark text-[26px] leading-tight">Map</h1>
          </div>
          <button className="p-2 rounded-xl bg-cream-200 text-ink-muted hover:bg-cream-300 transition-colors" aria-label="Refresh">
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
            Forest
          </button>
          <button
            onClick={() => setActiveLayer("heat")}
            className="layer-toggle flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-full border border-cream-300 bg-white text-ink-muted transition-all"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
              <path d="M13 2 3 14h9l-1 8 10-12h-9z" />
            </svg>
            Heat
          </button>
          <button
            onClick={() => setActiveLayer("my")}
            className="layer-toggle flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-full border border-cream-300 bg-white text-ink-muted transition-all"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
              <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z" />
              <circle cx="12" cy="10" r="3" />
            </svg>
            My Points
          </button>
          <div className="relative">
            <button
              onClick={() => setShowForestTypeMenu(!showForestTypeMenu)}
              className="layer-toggle flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-full border border-cream-300 bg-white text-ink-muted transition-all"
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 3h18v18H3z" />
                <path d="M9 3v18" />
                <path d="M15 3v18" />
              </svg>
              Filter
            </button>
            {showForestTypeMenu && (
              <div className="absolute right-0 top-full mt-1 z-20 rounded-xl bg-white shadow-lg border border-cream-300 py-1 min-w-[140px]">
                {FOREST_TYPES.map((type) => (
                  <button
                    key={type.value}
                    onClick={() => handleForestTypeChange(type.value)}
                    className="w-full px-3 py-2 text-sm text-left transition-colors"
                  >
                    {type.label}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </header>

      <div className="flex-1 relative min-h-0 mx-4 mb-4 rounded-3xl overflow-hidden border border-cream-300 shadow-lg">
        <MapCanvas
          onPick={handlePick}
          activeLayer={activeLayer}
          onForestClick={handleForestClick}
          onLongPress={handleLongPress}
          forestTypeFilter={forestTypeFilter}
        />
      </div>

      {longPressMenu && (
        <div
          className="fixed left-0 right-0 z-50 bg-white rounded-t-3xl shadow-xl p-4 transition-transform duration-300 ease-out translate-y-0"
          style={{ bottom: "var(--nav-h)" }}
        >
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-xl font-semibold text-forest-dark">Action</h2>
            <button onClick={closeLongPressMenu} className="text-2xl text-ink-muted hover:text-ink">×</button>
          </div>
          <p className="text-sm text-ink-muted mb-4">
            Forest: {longPressMenu.feature.properties?.name || "Unknown"} ({longPressMenu.feature.properties?.forest_type || "unknown"})
          </p>
          <button
            onClick={handleAddRoute}
            className="w-full rounded-xl bg-amberbrand py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90"
          >
            Add Route
          </button>
          <button
            onClick={closeLongPressMenu}
            className="w-full mt-2 rounded-xl border border-cream-300 bg-white py-3 text-sm font-medium text-ink-muted transition-colors hover:bg-cream-100"
          >
            Cancel
          </button>
        </div>
      )}

      <div
        className="fixed left-0 right-0 z-40 bg-white rounded-t-3xl shadow-xl p-4 transition-transform duration-300 ease-out translate-y-full"
        style={{ bottom: "var(--nav-h)" }}
      >
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-xl font-semibold text-forest-dark">
            Forest
          </h2>
          <button className="text-2xl text-ink-muted hover:text-ink" aria-label="Close">×</button>
        </div>

        <div className="text-center py-12 text-ink-muted">
          <p className="text-sm">Click on map for mushroom forecast</p>
        </div>

        <div className="mt-4 flex items-center gap-4 text-[10px] text-ink-muted">
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#4A6B54" }} />
            <span>Verified</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#C97A2B" }} />
            <span>Conditional</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#8B7F6E" }} />
            <span>Pending</span>
          </div>
        </div>
      </div>
    </div>
  );
}
