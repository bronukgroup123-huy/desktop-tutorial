// ============================================================================
// Тук-тук: підписи й кольори статусів (Thin Client — клієнт лише показує).
// ADR-018 §18.2: сірі — «Перевіряється», зелені — «Підтверджено».
// ============================================================================

export interface PickPresentation {
  status_label: string;
  marker_color: string;
}

const PRIVATE_STYLE: PickPresentation = { status_label: "Приватна точка", marker_color: "#1e88e5" };
const PUBLIC_STYLE: Record<string, PickPresentation> = {
  pending: { status_label: "Перевіряється", marker_color: "#9e9e9e" },
  conditional: { status_label: "Перевіряється", marker_color: "#9e9e9e" },
  verified: { status_label: "Підтверджено", marker_color: "#43a047" },
  rejected: { status_label: "Відхилено", marker_color: "#e53935" },
};

export function pickPresentation(visibility: string, verificationStatus: string): PickPresentation {
  if (visibility !== "public") return PRIVATE_STYLE;
  return PUBLIC_STYLE[verificationStatus] ?? PUBLIC_STYLE.pending;
}

/** Назва виду для показу; «Не знаю, що це» — коли вид не вибрано. */
export const UNKNOWN_SPECIES_LABEL = "Не знаю, що це";

export function speciesLabel(nameUa: unknown): string {
  return typeof nameUa === "string" && nameUa.length > 0 ? nameUa : UNKNOWN_SPECIES_LABEL;
}
