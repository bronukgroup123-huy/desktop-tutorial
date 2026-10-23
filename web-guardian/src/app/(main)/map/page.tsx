"use client";

import { useState } from "react";
import dynamic from "next/dynamic";

const MapCanvas = dynamic(() => import("@/components/map/MapCanvas").then((mod) => ({ default: mod.MapCanvas })), { ssr: false });

export default function MapPage() {
  const [activeLayer, setActiveLayer] = useState<"forest" | "heat" | "my">("forest");

  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50">
      <header className="p-4 flex justify-between items-center border-b border-cream-300 bg-white">
        <h1 className="text-3xl font-serif text-forest-dark">Map</h1>
        <button className="bg-forest-dark text-white px-4 py-2 rounded-full text-sm font-medium">
          Profile
        </button>
      </header>
      <div className="flex-1 relative mx-4 mb-4 rounded-3xl overflow-hidden border border-cream-300 shadow-soft">
        <MapCanvas onPick={() => {}} activeLayer="forest" />
      </div>
    </div>
  );
}
