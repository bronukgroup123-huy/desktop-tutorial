// Правила видів і прапорці рушія для повтору: з файлу (вивантаження з БД) або тестовий набір.
import { rowToRule } from "../../supabase/functions/_shared/forecast/db.ts";
import { DEFAULT_FEATURE_FLAGS, type FeatureFlags, loadFeatureFlags } from "../../supabase/functions/_shared/forecast/flags.ts";
import type { SpeciesRule } from "../../supabase/functions/_shared/forecast/types.ts";

const FIXTURE = new URL("../../supabase/tests/fixtures/rules-subset.json", import.meta.url);
const FRUITING_MIGRATION = new URL("../../supabase/migrations/20261114120000_expert_rules_fruiting.sql", import.meta.url);

/**
 * Параметри плодоношення з міграції — для рядків БД, де колонок ще немає (PR до злиття:
 * повтор сезону має рахувати вже з новими параметрами, а не зі значень за замовчуванням).
 */
async function fruitingOverlay(): Promise<Map<string, Record<string, unknown>>> {
  const sql = await Deno.readTextFile(FRUITING_MIGRATION);
  const out = new Map<string, Record<string, unknown>>();
  for (const m of sql.matchAll(/\('([a-z_]+)',\s*'([a-z_]+)',\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\)/g)) {
    out.set(m[1], {
      fruiting_trigger: m[2], trigger_rain_mm: Number(m[3]), maturation_dd: Number(m[4]), dd_base: Number(m[5]),
      flush_days: Number(m[6]), soil_temp_min: Number(m[7]), soil_temp_max: Number(m[8]),
    });
  }
  const meadow = sql.match(/forest_type = ARRAY\['meadow'\]::TEXT\[\] WHERE mushroom_type = '([a-z_]+)'/);
  if (meadow) out.set(meadow[1], { ...out.get(meadow[1]), forest_type: ["meadow"] });
  return out;
}

/**
 * [path] — JSON `{ rules: [...рядки expert_rules], flags?: [...рядки feature_flags] }` або
 * просто масив рядків. Без файлу — 9 видів із тестового набору (`rules-subset.json`).
 */
export async function loadRules(path?: string): Promise<{ rules: SpeciesRule[]; flags: FeatureFlags; source: string }> {
  const raw = JSON.parse(await Deno.readTextFile(path ?? FIXTURE));
  const rows: Record<string, unknown>[] = Array.isArray(raw) ? raw : raw.rules ?? [];
  const flagRows = Array.isArray(raw) ? null : raw.flags ?? null;
  const flags = flagRows
    ? await loadFeatureFlags({ from: () => ({ select: () => Promise.resolve({ data: flagRows, error: null }) }) })
    : { ...DEFAULT_FEATURE_FLAGS };
  const overlay = await fruitingOverlay();
  const withFruiting = rows.map((r) => {
    const o = overlay.get(String(r.mushroom_type));
    if (!o || r.soil_temp_min !== undefined) return r; // колонки вже є — беремо з БД
    return { ...r, ...o };
  });
  const rules = withFruiting.filter((r) => (r.mvp_stage ?? "mvp") === "mvp").map(rowToRule);
  return { rules, flags, source: path ? `база (${rules.length} видів)` : `тестовий набір (${rules.length} видів)` };
}
