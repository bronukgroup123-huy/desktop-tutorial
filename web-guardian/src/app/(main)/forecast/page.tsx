"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { MapPin, Sprout } from "lucide-react";
import { FUNCTIONS_URL } from "@/lib/constants";

interface RegionItem {
  id: number;
  name: string;
  slug: string;
}

export default function ForecastPage() {
  const [regions, setRegions] = useState<RegionItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const res = await fetch(`${FUNCTIONS_URL}/regions`);
        if (!res.ok) return;
        const json = await res.json();
        if (cancelled) return;
        setRegions(Array.isArray(json?.data) ? json.data : []);
      } catch (err) {
        console.error("Regions load failed:", err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="mx-auto max-w-2xl px-4 pb-10 pt-6">
      <header className="mb-5">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">
          Прогноз
        </h1>
        <p className="mt-1 text-sm text-ink-muted">
          Плодоношення грибів у вашому районі
        </p>
      </header>

      <section className="mb-6 rounded-2xl bg-white p-5 shadow-soft">
        <div className="mb-3 flex items-center gap-2">
          <Sprout size={18} className="text-forest" />
          <h2 className="font-serif text-lg font-semibold text-forest-dark">
            Як працює прогноз
          </h2>
        </div>
        <ol className="space-y-2 text-sm text-ink-muted">
          <li>1. Відкрийте карту та натисніть на ділянку, де збираєте гриби.</li>
          <li>
            2. Система враховує тип лісу, вологість, опади, температуру та
            накопичене тепла (GDD).
          </li>
          <li>
            3. Отримаєте головний вид, альтернативу та попередження — наприклад,
            «занадто мокро» або «поза сезоном».
          </li>
        </ol>
        <Link
          href="/map"
          className="mt-5 flex items-center justify-center gap-2 rounded-xl bg-forest-dark py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          <MapPin size={16} />
          Відкрити карту
        </Link>
      </section>

      <section>
        <h2 className="mb-3 font-serif text-lg font-semibold text-forest-dark">
          Регіони України
        </h2>
        {loading ? (
          <p className="text-sm text-ink-muted">Завантаження…</p>
        ) : regions.length === 0 ? (
          <p className="text-sm text-ink-muted">
            Список регіонів тимчасово недоступний.
          </p>
        ) : (
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {regions.map((region) => (
              <li key={region.slug}>
                <Link
                  href="/map"
                  className="flex items-center gap-2 rounded-xl bg-white px-3 py-2.5 text-sm text-forest-dark shadow-soft transition-colors hover:bg-forest-light/60"
                >
                  <MapPin size={14} className="shrink-0 text-forest" />
                  <span className="truncate">{region.name}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
