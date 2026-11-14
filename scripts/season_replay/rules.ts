// Правила видів і прапорці рушія для повтору: з файлу (вивантаження з БД) або тестовий набір.
import { rowToRule } from "../../supabase/functions/_shared/forecast/db.ts";
import { DEFAULT_FEATURE_FLAGS, type FeatureFlags, loadFeatureFlags } from "../../supabase/functions/_shared/forecast/flags.ts";
import type { SpeciesRule } from "../../supabase/functions/_shared/forecast/types.ts";

const FIXTURE = new URL("../../supabase/tests/fixtures/rules-subset.json", import.meta.url);

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
  const rules = rows.filter((r) => (r.mvp_stage ?? "mvp") === "mvp").map(rowToRule);
  return { rules, flags, source: path ? `база (${rules.length} видів)` : `тестовий набір (${rules.length} видів)` };
}
