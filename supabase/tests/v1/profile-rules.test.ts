import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handleKey, levelOf, points } from "../../functions/_shared/v1/profile-rules.ts";

Deno.test("Рівень за балами (ADR-013): межі, наступний рівень, бали українською", () => {
  assertEquals([levelOf(0).label, levelOf(0).progress_label], ["Мандрівник", "0 балів · ще 51 бал до рівня «Слідопит»"]);
  assertEquals(levelOf(51).label, "Слідопит");
  assertEquals(levelOf(198).progress_label, "198 балів · ще 3 бали до рівня «Лісовик»");
  assertEquals(levelOf(201).label, "Лісовик");
  assertEquals(levelOf(750).next_label, "Грибний Майстер");
  assertEquals(levelOf(1500).label, "Хранитель лісу"); // без тестів знань Майстром не стати
  assertEquals(levelOf(1500, true).label, "Грибний Майстер");
  assertEquals(levelOf(120, true).label, "Грибознавець");
  assertEquals([points(1), points(2), points(5), points(11), points(21), points(22), points(112)], ["1 бал", "2 бали", "5 балів", "11 балів", "21 бал", "22 бали", "112 балів"]);
});

Deno.test("Ключ ніка: без урахування великих літер і виду апострофа", () => {
  assertEquals(handleKey("Мар'яна_Ліс"), handleKey("МАР’ЯНА_ліс"));
});
