"use client";

import { Users, MapPin } from "lucide-react";

const mockPicks = [
  {
    id: "1",
    name_ua: "Білий гриб",
    latin: "Boletus edulis",
    user_name: "Олексій",
    region_name: "Київська",
    verification_status: "verified",
    created_at: "2024-10-20",
  },
  {
    id: "2",
    name_ua: "Маслюк звичайний",
    latin: "Suillus luteus",
    user_name: "Марія",
    region_name: "Львівська",
    verification_status: "conditional",
    created_at: "2024-10-19",
  },
  {
    id: "3",
    name_ua: "Підберезник",
    latin: "Leccinum scabrum",
    user_name: "Іван",
    region_name: "Закарпатська",
    verification_status: "pending",
    created_at: "2024-10-18",
  },
];

const getStatusBadge = (status: string) => {
  switch (status) {
    case "verified":
      return (
        <span className="badge badge-green">Верифіковано</span>
      );
    case "conditional":
      return (
        <span className="badge badge-amber">Умовно</span>
      );
    default:
      return (
        <span className="badge badge-neutral">Очікує</span>
      );
  }
};

export default function CommunityPage() {
  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 overflow-y-auto p-4 pb-[calc(var(--nav-h)+1rem)]">
      <header className="mb-6">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">Спільнота</h1>
        <p className="text-ink-muted text-sm mt-1">Знахідки грибників, відкриті для всіх</p>
      </header>

      <div className="rounded-2xl bg-white p-5 shadow-soft border border-cream-300 mb-6">
        <div className="flex items-center gap-2 mb-3">
          <Users size={18} className="text-forest" />
          <h2 className="font-serif text-lg font-semibold text-forest-dark">Як це працює</h2>
        </div>
        <ul className="space-y-2 text-sm text-ink-muted">
          <li>1. Додавайте знахідки на вкладці «Карта» — вони потраплять у спільноту.</li>
          <li>2. Всі публічні знахідки модерується командою.</li>
          <li>3. Верифіковані знахідки отримують зелену мітку.</li>
        </ul>
        <a
          href="/map"
          className="mt-5 flex items-center justify-center gap-2 rounded-xl bg-forest-dark py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          <MapPin size={16} />
          Додати знахідку
        </a>
      </div>

      <section>
        <h2 className="font-serif text-lg font-semibold text-forest-dark mb-3">Останні знахідки</h2>
        <ul className="space-y-3">
          {mockPicks.map((pick) => (
            <li key={pick.id} className="rounded-2xl bg-white p-4 shadow-soft border border-cream-300">
              <div className="flex items-baseline justify-between gap-3">
                <span className="font-semibold text-forest-dark">{pick.name_ua}</span>
                <span className="shrink-0 text-xs text-ink-muted">
                  {new Date(pick.created_at).toLocaleDateString("uk-UA")}
                </span>
              </div>
              <p className="mt-1 text-xs text-ink-muted">
                {pick.user_name} · {pick.region_name}
              </p>
              <div className="mt-2">{getStatusBadge(pick.verification_status)}</div>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}