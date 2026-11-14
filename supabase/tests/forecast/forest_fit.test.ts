// Тип лісу ділянки ↔ список типів виду: зв'язки між типами (мішаний, хвойний, листяний).
import { assert, assertEquals } from "jsr:@std/assert";
import { forestFit, GROUP_FIT, MIXED_FIT } from "../../functions/_shared/forecast/matchers.ts";
import { isLimitingReason } from "../../functions/_shared/forecast/scorer.ts";
import { limitLabels } from "../../functions/_shared/v1/forecast-labels.ts";

const PORCINI = ["pine", "spruce", "oak", "birch"];
const SUILLUS = ["pine"]; // маслюк — лише сосна
const BIRCH_BOLETE = ["birch"]; // підберезник

Deno.test("forestFit: точний збіг і «any» — повністю", () => {
  assertEquals(forestFit(PORCINI, "pine").score, 1);
  assertEquals(forestFit(["any"], "mixed").score, 1);
  assertEquals(forestFit(["mixed", "oak"], "mixed").score, 1);
});

Deno.test("forestFit: порода ділянки і загальний тип виду — лише коли порід у списку немає", () => {
  assertEquals(forestFit(["coniferous"], "pine").score, 1);
  assertEquals(forestFit(["deciduous"], "birch").score, 1);
  assertEquals(forestFit(["mixed"], "spruce").score, 1);
  // білий: породи перелічені (сосна, ялина, дуб) — березняк не підходить, хоч є «листяний»
  assertEquals(forestFit(["pine", "spruce", "oak", "deciduous", "coniferous"], "birch").score, 0);
  assertEquals(forestFit(["pine", "mixed"], "birch").score, 0);
});

Deno.test("forestFit: мішаний ліс — види і хвойних, і листяних, трохи нижче", () => {
  assertEquals(forestFit(PORCINI, "mixed"), { score: MIXED_FIT, reason: "forest group: mixed" });
  assertEquals(forestFit(SUILLUS, "mixed").score, MIXED_FIT);
  assertEquals(forestFit(BIRCH_BOLETE, "mixed").score, MIXED_FIT);
  assertEquals(forestFit(["coniferous"], "mixed").score, MIXED_FIT);
});

Deno.test("forestFit: хвойний / листяний без породи (супутник) — види відповідних порід", () => {
  assertEquals(forestFit(SUILLUS, "coniferous"), { score: GROUP_FIT, reason: "forest group: coniferous" });
  assertEquals(forestFit(BIRCH_BOLETE, "deciduous").score, GROUP_FIT);
  assertEquals(forestFit(["mixed"], "deciduous").score, GROUP_FIT);
});

Deno.test("forestFit: справді чужий ліс — вид не росте", () => {
  assertEquals(forestFit(SUILLUS, "deciduous").score, 0);
  assertEquals(forestFit(BIRCH_BOLETE, "coniferous").score, 0);
  assertEquals(forestFit(SUILLUS, "birch").score, 0);
  assertEquals(forestFit(["grassland_only"], "mixed").score, 0);
});

Deno.test("forestFit: неповний збіг — обмежувальний фактор з підказкою «Уточніть ліс»", () => {
  assert(isLimitingReason("forest group: mixed"));
  assert(isLimitingReason("forest group: coniferous"));
  assertEquals(limitLabels(["forest group: mixed"], [], "high", null), [
    "Ліс мішаний — невідомо, чи є тут потрібні дерева. Уточніть ліс",
  ]);
  assertEquals(limitLabels(["forest group: coniferous"], [], "high", null), [
    "Хвойний ліс без відомої породи — уточніть ліс, щоб прогноз був точнішим",
  ]);
});
