import { ShieldAlert } from "lucide-react";

const DEADLY = [
  {
    name: "Бліда поганка",
    latin: "Amanita phalloides",
    note: "Смертельно отруйна. Сплутати з сироїжками або сирinemilk.",
  },
  {
    name: "Мухомор червоний",
    latin: "Amanita muscaria",
    note: "Отруйний, у високих дозах — смертельно.",
  },
  {
    name: "Мухомор пантерний",
    latin: "Amanita pantherina",
    note: "Смертельно отруйний, містить ібетенніну.",
  },
  {
    name: "Мухомор вірменський",
    latin: "Amanita verna",
    note: "Смертельно отруйний, схожий на білий сироїжковий гриб.",
  },
  {
    name: "Мухомор білий",
    latin: "Amanita virosa",
    note: "Смертельно отруйний, схожий на сироїжку.",
  },
  {
    name: "Смердючий гриб",
    latin: "Phallus impudicus",
    note: "Сильно отруйний, викликає отруєння зі шлунково-кишковими симптомами.",
  },
  {
    name: "Зелена пантерка",
    latin: "Chlorophyllum molybdites",
    note: "Отруйний, спричиняє важкі розлади шлунка.",
  },
];

export default function SafetyPage() {
  return (
    <div className="mx-auto max-w-2xl px-4 pb-10 pt-6">
      <header className="mb-5">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">
          Безпека
        </h1>
        <p className="mt-1 text-sm text-ink-muted">
          Отруйні та смертельно отруйні гриби України
        </p>
      </header>

      <section className="mb-6 rounded-2xl border border-sos/30 bg-sos/5 p-4">
        <div className="mb-1 flex items-center gap-2">
          <ShieldAlert size={18} className="text-sos" />
          <h2 className="font-serif text-lg font-semibold text-sos">
            Головне правило
          </h2>
        </div>
        <p className="text-sm text-ink-muted">
          Їжте тільки ті гриби, які ви впевнено визначили. Сумнівний гриб —
          не беріть. При отруєнні зверніться по телефону <strong>103</strong> або
          <strong> 112</strong>.
        </p>
      </section>

      <section className="rounded-2xl bg-white p-5 shadow-soft">
        <h2 className="mb-4 font-serif text-lg font-semibold text-forest-dark">
          Не беріть ці гриби
        </h2>
        <ul className="space-y-3">
          {DEADLY.map((mushroom) => (
            <li
              key={mushroom.latin}
              className="rounded-xl border border-cream-200 p-3"
            >
              <div className="flex items-baseline justify-between gap-3">
                <span className="font-semibold text-forest-dark">
                  {mushroom.name}
                </span>
                <span className="shrink-0 text-xs italic text-ink-muted">
                  {mushroom.latin}
                </span>
              </div>
              <p className="mt-1 text-sm text-ink-muted">{mushroom.note}</p>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
