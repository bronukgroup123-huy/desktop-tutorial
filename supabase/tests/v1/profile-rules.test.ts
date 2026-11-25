import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handleKey, hasBlockedWord, isReserved, levelOf, points, skeleton } from "../../functions/_shared/v1/profile-rules.ts";

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

Deno.test("Нецензурне ловиться й в обхід: розділювачі, цифри замість літер, повтори, і/ї/и", () => {
  for (const bad of ["хуйло", "х_у_й_ня", "хууууй", "Хуї_мої", "п1зда", "пи3да", "піііздець", "бл9дь", "су4ка", "е6ать", "за.їб.ав", "Гітлер_88", "підар", "ПІДОР"]) {
    assertEquals(hasBlockedWord(bad), true, bad);
  }
  // Звичайні слова з «підозрілими» частинами — дозволені.
  for (const ok of ["Рибак", "небагато", "Мандарин", "Олена_лісова", "грибник_88", "Хустка", "Сусідка", "Дебора"]) {
    assertEquals(hasBlockedWord(ok), false, ok);
  }
});

Deno.test("Зарезервовані ніки — і з обходами (Адмін, а_д_м_і_н, адмiн з латинською i — латиниця й так заборонена)", () => {
  assertEquals(isReserved("Адмін"), true);
  assertEquals(isReserved("а_д_м_і_н"), true);
  assertEquals(isReserved("ПІДТРИМКА"), true);
  assertEquals(isReserved("адмінка_ліс"), false);
  assertEquals(skeleton("Хууу_ЙЙ.ло"), "хуило");
});

// Ті самі межі перевіряє SQL public.level_of (supabase/tests/rls_rating.sql): ліміти публічних точок у БД
// і рівень у профілі мають збігатися (PROD-001a).
Deno.test("levelOf: межі рівнів збігаються з SQL level_of", () => {
  const cases: Array<[number, boolean, string]> = [
    [0, false, "traveler"], [50, false, "traveler"], [51, false, "tracker"], [51, true, "expert"],
    [200, false, "tracker"], [200, true, "expert"], [201, false, "forester"], [201, true, "forester"],
    [500, false, "forester"], [501, false, "keeper"], [1000, false, "keeper"], [1001, false, "keeper"],
    [1001, true, "master"],
  ];
  for (const [rating, certified, id] of cases) assertEquals(levelOf(rating, certified).id, id, `${rating}/${certified}`);
});

