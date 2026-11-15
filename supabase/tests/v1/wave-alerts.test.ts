// Сповіщення «Почалась хвиля» (ADR-015 §15.8 п.19).
import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handleWaveAlerts, waveStartAlert } from "../../functions/_shared/v1/wave-alerts.ts";
import { mockDb, RL_OK } from "./mock-db.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const AREA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const EWKB = "0101000020E61000000000000000803E403333333333334940";
const NOW = new Date("2026-11-15T06:00:00Z"); // 08:00 у Києві

const dayWith = (wave: unknown, level = "high") => ({
  date: "2026-11-15",
  top1: { mushroom_type: "flammulina_velutipes", name_ua: "Зимовий опеньок", level, wave },
  alternative: null,
});
const saved = (wave: unknown, level = "high") => ({
  result_version: 3,
  days: [dayWith(wave, level)],
  best_day: { date: "2026-11-17", label: "Найкращий день: неділя" },
});

Deno.test("waveStartAlert: 1–2-й день хвилі, рівень від середнього — сповіщення; інакше — ні", () => {
  const a = waveStartAlert(saved({ phase: "flush", day: 2, days: 20 }), "Броники", "2026-11-15")!;
  assertEquals(a.species, "flammulina_velutipes");
  assertEquals(a.waveStart, "2026-11-14");
  assertEquals(a.title, "Броники: зимовий опеньок — хвиля почалась");
  assertEquals(a.body, "2-й день хвилі з 20. Найкращий день: неділя. Подивіться прогноз ділянки.");
  assertEquals(waveStartAlert(saved({ phase: "flush", day: 5, days: 20 }), "Б", "2026-11-15"), null);
  assertEquals(waveStartAlert(saved({ phase: "flush", day: 1, days: 20 }, "low"), "Б", "2026-11-15"), null);
  assertEquals(waveStartAlert(saved({ phase: "maturing" }), "Б", "2026-11-15"), null);
});

function deps(o: { claim?: boolean; rating?: number; lastAt?: string; wave?: unknown; sendOk?: boolean } = {}) {
  const sent: Array<{ token: string; title: string }> = [];
  const db = mockDb({
    ...RL_OK,
    "rpc.wave_alert_targets": { data: [{ user_id: USER, tokens: ["tok-aaaaaaaaaaaaaaaaaaaaaaaa"] }], error: null },
    "analysis_areas.select": {
      data: [{
        id: AREA, slot: 1, size_km: 5, center: EWKB, label: "Броники",
        last_analyzed_at: o.lastAt ?? "2026-11-15T05:00:00Z",
        last_result: saved(o.wave ?? { phase: "flush", day: 1, days: 20 }),
      }],
      error: null,
    },
    "users.select": { data: { home_region_id: 10, rating: o.rating ?? 60 }, error: null },
    "rpc.claim_wave_alert": { data: o.claim ?? true, error: null },
  });
  return {
    db,
    sent,
    deps: {
      db,
      verify: () => Promise.resolve(null),
      now: () => NOW,
      serviceKey: "svc",
      forecast: () => Promise.reject(new Error("not expected")),
      send: (token: string, msg: { title: string }) => {
        sent.push({ token, title: msg.title });
        return Promise.resolve(o.sendOk === false ? { ok: false, unregistered: true } : { ok: true });
      },
    },
  };
}

const post = (key = "svc") => new Request("http://localhost/v1-wave-alerts", { method: "POST", headers: { Authorization: `Bearer ${key}` } });

Deno.test("v1-wave-alerts: «Слідопит» — одне сповіщення на хвилю; вдруге — без дубля", async () => {
  const d = deps();
  const res = await handle((r) => handleWaveAlerts(r, d.deps as never))(post());
  const json = await res.json();
  assertEquals(res.status, 200);
  assertEquals(json.data, { users: 1, areas: 1, sent: 1, skipped: 0 });
  assertEquals(d.sent[0].title, "Броники: зимовий опеньок — хвиля почалась");
  const claim = d.db.calls.find((c) => c.key === "rpc.claim_wave_alert")!.args[0] as Record<string, unknown>;
  assertEquals([claim.p_species, claim.p_wave_start], ["flammulina_velutipes", "2026-11-15"]);

  const again = deps({ claim: false });
  const r2 = await (await handle((r) => handleWaveAlerts(r, again.deps as never))(post())).json();
  assertEquals(r2.data.sent, 0);
  assertEquals(again.sent.length, 0);
});

Deno.test("v1-wave-alerts: без доступу (не Pro, рейтинг < 51) — пропуск; недійсний токен — прибрати", async () => {
  const low = deps({ rating: 10 });
  const r = await (await handle((x) => handleWaveAlerts(x, low.deps as never))(post())).json();
  assertEquals([r.data.sent, r.data.skipped], [0, 1]);

  const bad = deps({ sendOk: false });
  await handle((x) => handleWaveAlerts(x, bad.deps as never))(post());
  assert(bad.db.calls.some((c) => c.key === "rpc.drop_push_device"));
});

Deno.test("v1-wave-alerts: лише з ключем service_role", async () => {
  const d = deps();
  const res = await handle((r) => handleWaveAlerts(r, d.deps as never))(post("wrong"));
  assertEquals(res.status, 401);
});
