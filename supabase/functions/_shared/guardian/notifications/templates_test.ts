import { assertEquals, assert } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { renderNotification, getTemplate, _internal } from "./templates.ts";

Deno.test("renderNotification — sos містить координати", () => {
  const result = renderNotification("sos", {}, {
    picker_name: "Олег",
    session_url: "https://x/session/1",
    guardian_url: "https://x/s/",
    coords: { lat: 50.45, lng: 30.52 },
  });
  assert(result.title.includes("SOS"));
  assert(result.body.includes("50.45000"));
  assert(result.body.includes("30.52000"));
});

Deno.test("renderNotification — overdue_hard містить minutes_over", () => {
  const result = renderNotification("overdue_hard", { minutes_over: 95 }, {
    picker_name: "Олег",
    session_url: "",
    guardian_url: "",
    coords: null,
  });
  assert(result.body.includes("95"));
});

Deno.test("getTemplate — sos requiresSms=true, priority=1", () => {
  const t = getTemplate("sos");
  assertEquals(t.requiresSms, true);
  assertEquals(t.priority, 1);
});

Deno.test("getTemplate — exit requiresSms=false, priority=5", () => {
  const t = getTemplate("exit");
  assertEquals(t.requiresSms, false);
  assertEquals(t.priority, 5);
});

Deno.test("_internal.interpolate — підставляє змінні", () => {
  assertEquals(
    _internal.interpolate("Hello {name}!", { name: "Олег" }),
    "Hello Олег!"
  );
});

Deno.test("_internal.interpolate — залишає невідомі змінні", () => {
  assertEquals(
    _internal.interpolate("Hello {unknown}!", {}),
    "Hello {unknown}!"
  );
});
