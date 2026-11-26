// BACKEND_PLAN B2.4 «Отруйні — ніколи»: прогноз бере лише правила їстівних і умовно їстівних видів
// за довідником. Вид без запису в довіднику чи з невідомою їстівністю теж не потрапляє в прогноз.
import { assertEquals } from "jsr:@std/assert";
import { findAllRules, findRulesByType, forecastableRows, ruleEdibility } from "../../functions/_shared/forecast/db.ts";
import type { DbClient } from "../../functions/_shared/forecast/db.ts";

function row(type: string, edibility: unknown, embed: "object" | "array" | "none" = "object"): Record<string, unknown> {
  const r: Record<string, unknown> = { id: type, legacy_id: 1, mushroom_type: type, name_ua: type, name_lat: type };
  if (embed === "object") r.mushroom_catalog = { edibility };
  if (embed === "array") r.mushroom_catalog = [{ edibility }];
  return r;
}

/** Мок: що повертає expert_rules, і чи просили вкласти їстівність. */
function dbWith(rows: Record<string, unknown>[]) {
  const selects: string[] = [];
  const db = {
    from(_table: string) {
      const chain: Record<string, unknown> = {
        select(cols: string) { selects.push(cols); return chain; },
        eq(col: string, val: unknown) {
          if (col === "mushroom_type") rows = rows.filter((r) => r.mushroom_type === val);
          return chain;
        },
        order() { return chain; },
        maybeSingle() { return Promise.resolve({ data: rows[0] ?? null, error: null }); },
        then(resolve: (v: unknown) => unknown) { return Promise.resolve({ data: rows, error: null }).then(resolve); },
      };
      return chain;
    },
    rpc() { return Promise.resolve({ data: null, error: null }); },
  };
  return { db: db as unknown as DbClient, selects };
}

const silent = () => {
  const warn = console.warn;
  console.warn = () => {};
  return () => (console.warn = warn);
};

Deno.test("отруйні, смертельно отруйні, неїстівні й без довідника — не потрапляють у прогноз", async () => {
  const restore = silent();
  try {
    const { db, selects } = dbWith([
      row("boletus_edulis", "edible"),
      row("lactarius_resimus", "conditionally_edible", "array"),
      row("amanita_phalloides", "deadly_poisonous"),
      row("amanita_muscaria", "poisonous"),
      row("tylopilus_felleus", "inedible"),
      row("mystery_species", null, "none"),
    ]);
    const rules = await findAllRules(db);
    assertEquals(rules.map((r) => r.mushroomType), ["boletus_edulis", "lactarius_resimus"]);
    assertEquals(selects[0], "*, mushroom_catalog(edibility)"); // їстівність береться тим самим запитом
  } finally {
    restore();
  }
});

Deno.test("правило одного виду: отруйний — null, їстівний — правило", async () => {
  const restore = silent();
  try {
    const rows = [row("amanita_phalloides", "deadly_poisonous"), row("cantharellus_cibarius", "edible")];
    assertEquals(await findRulesByType(dbWith(rows).db, "amanita_phalloides"), null);
    assertEquals((await findRulesByType(dbWith(rows).db, "cantharellus_cibarius"))?.mushroomType, "cantharellus_cibarius");
  } finally {
    restore();
  }
});

Deno.test("їстівність з вкладення: об'єкт, масив, відсутня", () => {
  assertEquals(ruleEdibility(row("a", "edible")), "edible");
  assertEquals(ruleEdibility(row("a", "poisonous", "array")), "poisonous");
  assertEquals(ruleEdibility(row("a", null, "none")), null);
  const restore = silent();
  try {
    assertEquals(forecastableRows([row("a", "edible"), row("b", 42)]).length, 1);
  } finally {
    restore();
  }
});
