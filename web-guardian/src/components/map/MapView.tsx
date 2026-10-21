"use client";

import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { useGuardianStore } from "@/store/guardian-store";
import type { TrackPoint } from "@/lib/types";

function coordsToLngLat(c: TrackPoint["coords"]): [number, number] | null {
  if ("coordinates" in c) return c.coordinates;
  if ("lat" in c && "lng" in c) return [c.lng, c.lat];
  return null;
}

export function MapView({ token }: { token: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markerRef = useRef<maplibregl.Marker | null>(null);

  const session = useGuardianStore((s) => s.session);
  const track = useGuardianStore((s) => s.track);

  // TEMPORARY DEBUG: Forest zones loading state
  // REMOVE BEFORE RELEASE
  const [forestsLoaded, setForestsLoaded] = useState(false);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const initialCenter: [number, number] =
      session?.last_known_coords
        ? [session.last_known_coords.lng, session.last_known_coords.lat]
        : [31.1656, 48.3794];

    const map = new maplibregl.Map({
      container: containerRef.current,
      style: {
        version: 8,
        sources: {
          osm: {
            type: "raster",
            tiles: [
              "https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
              "https://b.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
              "https://c.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png"
            ],
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
      center: initialCenter,
      zoom: 13,
    });

    map.addControl(new maplibregl.NavigationControl(), "top-right");
    map.addControl(
      new maplibregl.GeolocateControl({
        positionOptions: { enableHighAccuracy: true },
        trackUserLocation: true,
      }),
      "top-right"
    );

    mapRef.current = map;

    map.on("load", () => {
      map.addSource("track", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });

      map.addLayer({
        id: "track-line",
        type: "line",
        source: "track",
        paint: {
          "line-color": "#16a34a",
          "line-width": 4,
          "line-opacity": 0.8,
        },
      });

      // TEMPORARY: Load forest zones for visual verification (Kyiv region)
      // REMOVE BEFORE RELEASE
      if (!forestsLoaded) {
        fetch("/api/debug/forests")
          .then((res) => res.json())
          .then((data) => {
            if (data.error) {
              console.error("Forest data error:", data.error);
              return;
            }
            const features = data?.features ?? data;
            if (features && Array.isArray(features) && features.length > 0) {
              map.addSource("forests", {
                type: "geojson",
                data: { type: "FeatureCollection", features },
              });

              map.addLayer({
                id: "forests-fill",
                type: "fill",
                source: "forests",
                paint: {
                  "fill-color": "rgba(34, 139, 34, 0.4)",
                  "fill-outline-color": "#006400",
                },
              });

              map.addLayer({
                id: "forests-outline",
                type: "line",
                source: "forests",
                paint: {
                  "line-color": "#006400",
                  "line-width": 1,
                },
              });

              map.on("click", "forests-fill", (e) => {
                const feature = e.features?.[0];
                const forestType = feature?.properties?.forest_type ?? "unknown";
                new maplibregl.Popup()
                  .setLngLat(e.lngLat)
                  .setHTML(`<strong>Forest type:</strong> ${forestType}`)
                  .addTo(map);
              });

              map.on("mouseenter", "forests-fill", () => {
                map.getCanvas().style.cursor = "pointer";
              });

              map.on("mouseleave", "forests-fill", () => {
                map.getCanvas().style.cursor = "";
              });

              setForestsLoaded(true);
            }
          })
          .catch((err) => console.error("Failed to load forests:", err));
      }
    });

    return () => {
      map.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !session?.last_known_coords) return;

    const { lat, lng } = session.last_known_coords;

    if (markerRef.current) {
      markerRef.current.setLngLat([lng, lat]);
    } else {
      const el = document.createElement("div");
      el.className =
        "w-6 h-6 rounded-full bg-green-500 border-4 border-white shadow-lg animate-pulse";
      el.setAttribute("aria-label", "Позиція грибника");

      markerRef.current = new maplibregl.Marker({ element: el })
        .setLngLat([lng, lat])
        .addTo(map);
    }
  }, [session?.last_known_coords]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !map.isStyleLoaded()) return;

    const source = map.getSource("track") as maplibregl.GeoJSONSource | undefined;
    if (!source) return;

    const coords: [number, number][] = [];
    for (const p of track) {
      const c = coordsToLngLat(p.coords);
      if (c) coords.push(c);
    }

    source.setData({
      type: "FeatureCollection",
      features:
        coords.length > 1
          ? [
              {
                type: "Feature",
                properties: {},
                geometry: { type: "LineString", coordinates: coords },
              },
            ]
          : [],
    });
  }, [track]);

  return (
    <div
      ref={containerRef}
      className="w-full h-full"
      aria-label="Карта позиції грибника"
    />
  );
}
