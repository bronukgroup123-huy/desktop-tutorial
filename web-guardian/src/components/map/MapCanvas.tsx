"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import type { Map as MapLibreMap, LngLatLike } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";

const KYIV_CENTER: [number, number] = [30.52, 50.45];
const INITIAL_ZOOM = 10;
const LONG_PRESS_MS = 500;
const UKRAINE_BOUNDS: [number, number, number, number] = [28.0, 49.0, 33.0, 52.0];

interface MapCanvasProps {
  onPick: (point: { lat: number; lng: number }) => void;
  activeLayer: "forest" | "heat" | "my";
  onForestClick?: (feature: any) => void;
  onLongPress?: (feature: any, lngLat: { lat: number; lng: number }) => void;
  forestTypeFilter?: string | null;
}

export function MapCanvas({
  onPick,
  activeLayer,
  onForestClick,
  onLongPress,
  forestTypeFilter,
}: MapCanvasProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const onPickRef = useRef(onPick);
  const onForestClickRef = useRef(onForestClick);
  const onLongPressRef = useRef(onLongPress);
  const forestTypeFilterRef = useRef(forestTypeFilter);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    onPickRef.current = onPick;
  }, [onPick]);

  useEffect(() => {
    onForestClickRef.current = onForestClick;
  }, [onForestClick]);

  useEffect(() => {
    onLongPressRef.current = onLongPress;
  }, [onLongPress]);

  useEffect(() => {
    forestTypeFilterRef.current = forestTypeFilter;
    if (mapRef.current && mapRef.current.isStyleLoaded()) {
      applyForestTypeFilter(mapRef.current);
    }
  }, [forestTypeFilter]);

  const applyForestTypeFilter = useCallback((map: MapLibreMap) => {
    const filter = forestTypeFilterRef.current;
    if (map.getLayer("forest-fill-layer")) {
      if (filter && filter !== "all") {
        map.setFilter("forest-fill-layer", ["==", ["get", "forest_type"], filter]);
        map.setFilter("forest-outline-layer", ["==", ["get", "forest_type"], filter]);
      } else {
        map.setFilter("forest-fill-layer", null);
        map.setFilter("forest-outline-layer", null);
      }
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    let map: MapLibreMap | null = null;
    let longPressTimer: ReturnType<typeof setTimeout> | null = null;
    let touchStartTime = 0;
    let touchStartPoint: { x: number; y: number } | null = null;

    let handleTouchStart: ((e: any) => void) | null = null;
    let handleTouchEnd: (() => void) | null = null;

    async function loadForests(currentMap: MapLibreMap) {
      try {
        const geojsonUrl = process.env.NEXT_PUBLIC_FORESTS_GEOJSON_URL;
        console.log("MapCanvas: geojsonUrl set?", !!geojsonUrl);

        if (!geojsonUrl) {
          console.warn("MapCanvas: NEXT_PUBLIC_FORESTS_GEOJSON_URL is not set");
          setIsLoading(false);
          return;
        }

        const response = await fetch(geojsonUrl);
        if (!response.ok) {
          throw new Error("Помилка завантаження лісів: " + response.status);
        }

        const geojson = await response.json();
        const featureCount = geojson?.features?.length ?? 0;
        console.log("MapCanvas: forests GeoJSON loaded, features:", featureCount);

        if (cancelled) return;

        const source = currentMap.getSource("forests") as
          | import("maplibre-gl").GeoJSONSource
          | undefined;
        if (source) {
          source.setData(geojson);
        }

        setIsLoading(false);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        setError(msg);
        setIsLoading(false);
        console.error("MapCanvas: load forests error:", err);
      }
    }

    async function init() {
      try {
        const maplibregl = (await import("maplibre-gl")).default;
        if (cancelled || !containerRef.current) return;

        map = new maplibregl.Map({
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
          maxBounds: UKRAINE_BOUNDS,
        });

        mapRef.current = map;
        map.addControl(new (await import("maplibre-gl")).default.NavigationControl(), "top-right");

        map.on("load", () => {
          if (cancelled) return;
          const currentMap = map;
          if (!currentMap) return;

          currentMap.addSource("forests", {
            type: "geojson",
            data: { type: "FeatureCollection", features: [] },
          });

          currentMap.addLayer({
            id: "forest-fill-layer",
            type: "fill",
            source: "forests",
            paint: { "fill-color": "#4A6B54", "fill-opacity": 0.3 },
          });

          currentMap.addLayer({
            id: "forest-outline-layer",
            type: "line",
            source: "forests",
            paint: {
              "line-color": "#2F4A3A",
              "line-width": 0.6,
              "line-opacity": 0.6,
            },
          });

          applyForestTypeFilter(currentMap);

          // OSM тайли вже ініціалізовані, тепер завантажуємо полігони лісів.
          void loadForests(currentMap);
        });

        map.on("click", "forest-fill-layer", (e: any) => {
          const feature = e.features?.[0];
          if (feature && onForestClickRef.current) {
            onForestClickRef.current(feature);
          }
        });

        map.on("click", (e: any) => {
          if (!e.features?.find((f: any) => f.layer?.id === "forest-fill-layer")) {
            onPickRef.current({ lat: e.lngLat.lat, lng: e.lngLat.lng });
          }
        });

        map.on("mousemove", (e) => {
          const currentMap = map;
          if (!currentMap) return;
          const features = currentMap.queryRenderedFeatures(e.point, {
            layers: ["forest-fill-layer"],
          });
          currentMap.getCanvas().style.cursor = features && features.length > 0 ? "pointer" : "";
        });

        const handleTouchStart = (e: any) => {
          const currentMap = map;
          if (!currentMap) return;
          const point = e.point || e.lngLat;
          touchStartTime = Date.now();
          touchStartPoint = { x: point.x, y: point.y };
          longPressTimer = setTimeout(() => {
            if (!touchStartPoint) return;
            const features = currentMap.queryRenderedFeatures(
              [touchStartPoint.x, touchStartPoint.y],
              { layers: ["forest-fill-layer"] }
            );
            const feature = features?.[0];
            if (feature && onLongPressRef.current) {
              const lngLat = currentMap.unproject([touchStartPoint.x, touchStartPoint.y]);
              if (lngLat) {
                onLongPressRef.current(feature, { lng: lngLat.lng, lat: lngLat.lat });
              }
            }
          }, LONG_PRESS_MS);
        };

        const handleTouchEnd = () => {
          if (longPressTimer) {
            clearTimeout(longPressTimer);
            longPressTimer = null;
          }
          touchStartPoint = null;
        };

        map.getCanvas().addEventListener("mousedown", handleTouchStart);
        map.getCanvas().addEventListener("touchstart", handleTouchStart);
        map.getCanvas().addEventListener("mouseup", handleTouchEnd);
        map.getCanvas().addEventListener("touchend", handleTouchEnd);
        map.getCanvas().addEventListener("mouseleave", handleTouchEnd);
        map.getCanvas().addEventListener("touchcancel", handleTouchEnd);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        setError(msg);
        setIsLoading(false);
        console.error("MapCanvas: init error:", err);
      }
    }

    void init();

    return () => {
      cancelled = true;
      if (longPressTimer) clearTimeout(longPressTimer);
      if (map) {
        map.getCanvas().removeEventListener("mousedown", handleTouchStart as any);
        map.getCanvas().removeEventListener("touchstart", handleTouchStart as any);
        map.getCanvas().removeEventListener("mouseup", handleTouchEnd as any);
        map.getCanvas().removeEventListener("touchend", handleTouchEnd as any);
        map.getCanvas().removeEventListener("mouseleave", handleTouchEnd as any);
        map.getCanvas().removeEventListener("touchcancel", handleTouchEnd as any);
        map.remove();
      }
      mapRef.current = null;
    };
  }, [activeLayer]);

  return (
    <div
      ref={containerRef}
      style={{ width: "100%", height: "100%", minHeight: "400px", position: "absolute", top: 0, left: 0 }}
      className="z-0 relative"
    >
      {error && (
        <div
          className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-red-50 border border-red-200 p-4 text-red-700 text-sm"
          role="alert"
        >
          <p className="font-bold mb-1">Помилка карти</p>
          <p className="break-words">{error}</p>
        </div>
      )}
      {!error && isLoading && (
        <div className="absolute inset-0 z-10 flex flex-col items-center justify-center bg-white/80 backdrop-blur-sm">
          <div className="w-8 h-8 border-4 border-current border-t-transparent rounded-full animate-spin" />
          <p className="mt-2 text-sm font-medium text-gray-700">Завантаження лісів...</p>
        </div>
      )}
    </div>
  );
}

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
