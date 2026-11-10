// ============================================================================
// Підписи й кольори типів лісу (Response Shaping).
// Єдине джерело для API (v1-forest-zones) і генератора файлів лісів областей
// (scripts/forests) — клієнт ніколи не вигадує ці тексти сам.
// Без залежностей, щоб імпортуватися де завгодно.
// ============================================================================

/** Підписи й кольори типів лісу — сервер віддає готові (Response Shaping). */
export const FOREST_TYPE_STYLE: Record<string, { label: string; color: string }> = {
  pine: { label: "Сосновий ліс", color: "#81c784" },
  spruce: { label: "Ялиновий ліс", color: "#2e7d32" },
  oak: { label: "Дубовий ліс", color: "#4caf50" },
  birch: { label: "Березовий ліс", color: "#aed581" },
  aspen: { label: "Осиковий ліс", color: "#c5e1a5" },
  alder: { label: "Вільшаний ліс", color: "#8bc34a" },
  beech: { label: "Буковий ліс", color: "#689f38" },
  hornbeam: { label: "Грабовий ліс", color: "#7cb342" },
  deciduous: { label: "Листяний ліс", color: "#a5d6a7" },
  coniferous: { label: "Хвойний ліс", color: "#66bb6a" },
  mixed: { label: "Мішаний ліс", color: "#9e9e9e" },
};
export const UNKNOWN_FOREST_STYLE = { label: "Ліс (тип невідомий)", color: "#b0bec5" };

export function forestTypeStyle(type: unknown): { label: string; color: string } {
  return (typeof type === "string" && FOREST_TYPE_STYLE[type]) || UNKNOWN_FOREST_STYLE;
}
