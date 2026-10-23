"use client";

import { MapPin, Sprout } from "lucide-react";

export default function ForecastPage() {
  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 overflow-y-auto p-4 pb-[calc(var(--nav-h)+1rem)]">
      <header className="mb-6">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">Прогноз</h1>
        <p className="text-ink-muted text-sm mt-1">Плодоношення грибів у вашому регіоні</p>
      </header>

      <div className="rounded-2xl bg-white p-5 shadow-soft border border-cream-300 mb-6">
        <div className="flex items-center gap-2 mb-3">
          <Sprout size={18} className="text-forest" />
          <h2 className="font-serif text-lg font-semibold text-forest-dark">Як працює прогноз</h2>
        </div>
        <ol className="space-y-2 text-sm text-ink-muted">
          <li>1. Відкрийте карту та натисніть на ділянку, де збираєте гриби.</li>
          <li>2. Система враховує тип лісу, вологість, опади, температуру та накопичене тепла (GDD).</li>
          <li>3. Отримаєте головний вид, альтернативу та попередження — наприклад, «занадто мокро» або «поза сезоном».</li>
        </ol>
        <a
          href="/map"
          className="mt-5 flex items-center justify-center gap-2 rounded-xl bg-forest-dark py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          <MapPin size={16} />
          Відкрити карту
        </a>
      </div>

      <section>
        <h2 className="font-serif text-lg font-semibold text-forest-dark mb-3">Популярні регіони</h2>
        <ul className="grid grid-cols-2 sm:grid-cols-3 gap-2">
          {[
            { name: "Київська", slug: "kyivska" },
            { name: "Львівська", slug: "lvivska" },
            { name: "Закарпатська", slug: "zakarpatska" },
            { name: "Івано-Франківська", slug: "ivano-frankivska" },
            { name: "Чернівецька", slug: "chernivetska" },
            { name: "Хмельницька", slug: "khmelnytska" },
          ].map((region) => (
            <li key={region.slug}>
              <a
                href="/map"
                className="flex items-center gap-2 rounded-xl bg-white px-3 py-2.5 text-sm text-forest-dark shadow-soft border border-cream-300 transition-colors hover:bg-forest-light/60"
              >
                <MapPin size={14} className="shrink-0 text-forest" />
                <span className="truncate">{region.name}</span>
              </a>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}