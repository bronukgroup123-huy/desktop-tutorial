"use client";

import { useEffect, useRef } from "react";
import type { Map as MapLibreMap, MapMouseEvent } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { FUNCTIONS_URL } from "@/lib/constants";

const KYIV_CENTER: [number, number] = [30.52, 50.45];
const INITIAL_ZOOM = 10;
const DEBOUNCE_MS = 400;

interface MapCanvasProps {
  onPick: (point: { lat: number; lng: number }) => void;
  activeLayer: "forest" | "heat" | "my";
}

export function MapCanvas({ onPick, activeLayer }: MapCanvasProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const onPickRef = useRef(onPick);

  useEffect(() => {
    onPickRef.current = onPick;
  }, [onPick]);

  useEffect(() => {
    let cancelled = false;
    let map: MapLibreMap | null = null;

    async function init() {
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
      });

      mapRef.current = map;
      map.addControl(new maplibregl.NavigationControl(), "top-right");

      const loadForestZones = async () => {
        const current = mapRef.current;
        if (!current || !current.isStyleLoaded()) return;
        const bounds = current.getBounds();
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
          const data = await res.json();
          const source = current.getSource(
            "forest-zones"
          ) as import("maplibre-gl").GeoJSONSource | undefined;
          if (source) {
            source.setData(data as unknown as GeoJSON.FeatureCollection);
          }
        } catch (err) {
          console.error("Forest zones load failed:", err);
        }
      };

      const debouncedLoad = debounce(loadForestZones, DEBOUNCE_MS);

      map.on("load", () => {
        map?.addSource("forest-zones", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });

        map?.addLayer({
          id: "forest-zones-fill",
          type: "fill",
          source: "forest-zones",
          paint: { "fill-color": "#4A6B54", "fill-opacity": 0.3 },
        });

        map?.addLayer({
          id: "forest-zones-outline",
          type: "line",
          source: "forest-zones",
          paint: {
            "line-color": "#2F4A3A",
            "line-width": 0.6,
            "line-opacity": 0.6,
          },
        });

        void loadForestZones();
      });

      map.on("moveend", debouncedLoad);

      map.on("click", (e: MapMouseEvent) => {
        onPickRef.current({ lat: e.lngLat.lat, lng: e.lngLat.lng });
      });
    }

    void init();

    return () => {
      cancelled = true;
      if (map) {
        map.remove();
      }
      mapRef.current = null;
    };
  }, [activeLayer]);

  return <div ref={containerRef} className="absolute inset-0 z-0" />;
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