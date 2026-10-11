// ============================================================================
// Forecast Engine — Feature Flags (§11.2)
// ============================================================================



/**
 * Мінімальний структурний тип Supabase-клієнта (без esm.sh імпорту —
 * щоб unit-тести не падали на typecheck @types/node).
 */
interface FlagRow {
  key: string;
  enabled: boolean;
  value: unknown;
}

interface DbClient {
  from(table: string): {
    select(cols?: string): Promise<{
      data: FlagRow[] | null;
      error: { message: string } | null;
    }>;
  };
}

export interface FeatureFlags {
  /** Buffer °C навколо температурних порогів (default 3) */
  fruiting_temp_buffer: number;
  region_filter_enabled: boolean;
  auto_calibration_enabled: boolean;
  rule5_anti_double_counting_enabled: boolean;
  indicator_pidvyshen_enabled: boolean;
  pressure_enabled: boolean;
  light_enabled: boolean;
  relief_enabled: boolean;
  gdd_enabled: boolean;
  peak_wave_bonus_enabled: boolean;
}

export const DEFAULT_FEATURE_FLAGS: FeatureFlags = {
  fruiting_temp_buffer: 3,
  region_filter_enabled: true,
  auto_calibration_enabled: false,
  rule5_anti_double_counting_enabled: true,
  indicator_pidvyshen_enabled: false,
  pressure_enabled: false,
  light_enabled: false,
  relief_enabled: false,
  gdd_enabled: true,
  peak_wave_bonus_enabled: true,
};

export async function loadFeatureFlags(
  db: DbClient
): Promise<FeatureFlags> {
  const { data, error } = await db
    .from("feature_flags")
    .select("key, enabled, value");

  if (error || !data || data.length === 0) {
    return { ...DEFAULT_FEATURE_FLAGS };
  }

  const flags: FeatureFlags = { ...DEFAULT_FEATURE_FLAGS };

  for (const row of data) {
    const key = row.key as keyof FeatureFlags;
    if (!(key in DEFAULT_FEATURE_FLAGS)) continue;

    if (key === "fruiting_temp_buffer") {
      // value — число (JSONB може бути числом або рядком)
      const num = typeof row.value === "number"
        ? row.value
        : Number(row.value);
      if (!Number.isNaN(num)) {
        flags.fruiting_temp_buffer = num;
      }
      continue;
    }

    (flags as unknown as Record<string, boolean | number>)[key] =
      typeof row.value === "boolean" ? row.value : row.enabled !== false;
  }

  return flags;
}
