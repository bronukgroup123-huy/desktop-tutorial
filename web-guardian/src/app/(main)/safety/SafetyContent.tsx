"use client";

import { useEffect, useState } from "react";
import { ShieldAlert, AlertTriangle, Skull, MapPin, Navigation, X } from "lucide-react";

const DEADLY = [
  {
    name: "Бліда поганка",
    latin: "Amanita phalloides",
    note: "Смертельно отруйна. Сплутати з сироїжками або сирoїжками.",
    icon: Skull,
  },
  {
    name: "Мухомор червоний",
    latin: "Amanita muscaria",
    note: "Отруйний, у високих дозах — смертельно.",
    icon: Skull,
  },
  {
    name: "Мухомор пантерний",
    latin: "Amanita pantherina",
    note: "Смертельно отруйний, містить ібетенніну.",
    icon: Skull,
  },
  {
    name: "Мухомор вірменський",
    latin: "Amanita verna",
    note: "Смертельно отруйний, схожий на білий сироїжковий гриб.",
    icon: Skull,
  },
  {
    name: "Мухомор білий",
    latin: "Amanita virosa",
    note: "Смертельно отруйний, схожий на сироїжку.",
    icon: Skull,
  },
  {
    name: "Смердючий гриб",
    latin: "Phallus impudicus",
    note: "Сильно отруйний, викликає важкі розлади шлунка.",
    icon: AlertTriangle,
  },
  {
    name: "Зелена пантерка",
    latin: "Chlorophyllum molybdites",
    note: "Отруйний, спричиняє важкі розлади шлунка.",
    icon: AlertTriangle,
  },
];

export function SafetyContent({ destLat, destLng }: { destLat: string | null; destLng: string | null }) {
  const [showRoute, setShowRoute] = useState(false);

  useEffect(() => {
    // Check URL params on client side
    const params = new URLSearchParams(window.location.search);
    const lat = params.get("destLat");
    const lng = params.get("destLng");
    if (lat && lng) {
      setShowRoute(true);
    }
  }, []);

  const clearRoute = () => {
    window.history.replaceState({}, "", "/safety");
  };

  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 overflow-y-auto p-4 pb-[calc(var(--nav-h)+1rem)]">
      {showRoute && (
        <div className="mb-4 rounded-2xl bg-amberbrand/10 border border-amberbrand/30 p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Navigation size={20} className="text-amberbrand" />
              <h2 className="font-serif text-lg font-semibold text-amberbrand">Маршрут до лісу</h2>
            </div>
            <button
              type="button"
              onClick={() => window.history.replaceState({}, "", "/safety")}
              className="p-1 rounded-lg text-ink-muted hover:bg-cream-200 transition-colors"
              aria-label="Закрити маршрут"
            >
              <X size={18} />
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3 mb-3">
            <div className="rounded-xl bg-white p-3 shadow-soft border border-cream-300">
              <p className="text-xs text-ink-muted uppercase tracking-wider">Цільова точка</p>
              <p className="font-semibold text-forest-dark font-mono text-sm">
                {parseFloat(destLat!).toFixed(4)}N, {parseFloat(destLng!).toFixed(4)}E
              </p>
            </div>
            <div className="rounded-xl bg-white p-3 shadow-soft border border-cream-300">
              <p className="text-xs text-ink-muted uppercase tracking-wider">Статус</p>
              <p className="font-semibold text-forest">Маршрут готовий</p>
            </div>
          </div>
          <div className="rounded-xl bg-white p-3 shadow-soft border border-cream-300 mb-3">
            <p className="text-xs text-ink-muted uppercase tracking-wider mb-2">Дії</p>
            <div className="flex gap-2">
              <button type="button" className="flex-1 rounded-xl bg-forest-dark py-2.5 text-sm font-semibold text-white transition-opacity hover:opacity-90">
                <Navigation className="inline w-4 h-4 mr-1" /> Навігація
              </button>
              <button type="button" className="flex-1 rounded-xl border border-cream-300 bg-white py-2.5 text-sm font-medium text-ink-muted transition-colors hover:bg-cream-100">
                Зберегти
              </button>
            </div>
          </div>
          <p className="text-xs text-ink-muted text-center">
            Додайте моє місцезнаходження для побудови маршруту (функція в розробці)
          </p>
        </div>
      )}

      <header className="mb-6">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">Безпека</h1>
        <p className="text-ink-muted text-sm mt-1">Отруйні та смертельно отруйні гриби України</p>
      </header>

      <section className="mb-6 rounded-2xl border border-sos/30 bg-sos/5 p-4">
        <div className="mb-1 flex items-center gap-2">
          <ShieldAlert size={18} className="text-sos" />
          <h2 className="font-serif text-lg font-semibold text-sos">Головне правило</h2>
        </div>
        <p className="text-sm text-ink-muted">
          Їжте тільки ті гриби, які ви впевнено визначили. Сумнівний гриб —
          не бери. При отруєнні зверніться по телефону <strong>103</strong> або
          <strong>112</strong>.
        </p>
      </section>

      <section className="rounded-2xl bg-white p-5 shadow-soft border border-cream-300">
        <h2 className="font-serif text-lg font-semibold text-forest-dark mb-4">Не бери ці гриби</h2>
        <ul className="space-y-3">
          {DEADLY.map((mushroom) => {
            const Icon = mushroom.icon;
            return (
              <li key={mushroom.latin} className="rounded-xl border border-cream-200 p-3">
                <div className="flex items-baseline justify-between gap-3">
                  <span className="font-semibold text-forest-dark">{mushroom.name}</span>
                  <span className="shrink-0 text-xs italic text-ink-muted">{mushroom.latin}</span>
                </div>
                <p className="mt-1 text-sm text-ink-muted">{mushroom.note}</p>
              </li>
            );
          })}
        </ul>
      </section>
    </div>
  );
}