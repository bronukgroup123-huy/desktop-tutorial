"use client";

import { useEffect, useRef } from "react";
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
