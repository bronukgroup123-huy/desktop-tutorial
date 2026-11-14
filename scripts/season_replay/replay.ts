// Повтор фактичного сезону: архів погоди Open-Meteo (ERA5) → рушій прогнозу день за днем.
//   deno run -A scripts/season_replay/replay.ts --from 2025-04-01 --to 2025-11-15 \
//     --point "Житомир:50.30:28.60" --point "Овруч:51.32:28.80" --forest pine,deciduous,mixed \
//     [--rules rules.json] [--out out]
import { parseArgs } from "jsr:@std/cli@1/parse-args";
import type { ForestType } from "../../supabase/functions/_shared/forecast/types.ts";
import { buildSeries, type OpenMeteoResponse } from "../../supabase/functions/_shared/forecast/weather.ts";
import { dateRange, replay, type ReplayRun } from "./core.ts";
import { forestUa, renderReport, textGrid } from "./report.ts";
import { loadRules } from "./rules.ts";

const args = parseArgs(Deno.args, {
  string: ["from", "to", "forest", "rules", "out", "title"],
  collect: ["point"],
  default: { from: "2025-04-01", to: "2025-11-15", forest: "pine,deciduous,mixed", out: "out", title: "Сезон 2025" },
});
const points = (args.point as string[]).map((p) => {
  const [name, lat, lng] = p.split(":");
  if (!name || Number.isNaN(Number(lat)) || Number.isNaN(Number(lng))) throw new Error(`--point "Назва:lat:lng", отримано ${p}`);
  return { name, lat: Number(lat), lng: Number(lng) };
});
if (points.length === 0) throw new Error("Потрібна хоча б одна --point");
const forests = args.forest.split(",").map((s) => s.trim()) as ForestType[];

const PAST = 30; // передісторія для вікон погоди (опади за 30 днів)
const start = new Date(Date.parse(`${args.from}T00:00:00Z`) - PAST * 86_400_000).toISOString().slice(0, 10);

async function archive(lat: number, lng: number): Promise<OpenMeteoResponse> {
  const q = new URLSearchParams({
    latitude: lat.toFixed(4),
    longitude: lng.toFixed(4),
    start_date: start,
    end_date: args.to,
    hourly: "temperature_2m,relative_humidity_2m,precipitation,pressure_msl,soil_moisture_0_to_7cm",
    daily: "temperature_2m_max,temperature_2m_min,precipitation_sum",
    timezone: "Europe/Kyiv",
  });
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(`https://archive-api.open-meteo.com/v1/archive?${q}`);
    if (res.ok) return await res.json();
    console.warn(`archive HTTP ${res.status}, спроба ${attempt + 1}`);
    await new Promise((r) => setTimeout(r, 2000 * 2 ** attempt));
  }
  throw new Error("Архів Open-Meteo недоступний");
}

const { rules, flags, source } = await loadRules(args.rules);
const dates = dateRange(args.from, args.to);
const runs: ReplayRun[] = [];
for (const p of points) {
  const series = buildSeries(await archive(p.lat, p.lng), 0, new Date());
  if (!series) throw new Error(`Порожній архів для ${p.name}`);
  for (const f of forests) {
    runs.push(replay(`${p.name}: ${forestUa(f)} ліс`, series, dates, p.lat, p.lng, f, rules, flags));
  }
}
for (const r of runs) console.log(textGrid(r) + "\n");

await Deno.mkdir(args.out, { recursive: true });
await Deno.writeTextFile(`${args.out}/replay.json`, JSON.stringify({ from: args.from, to: args.to, source, runs }));
await Deno.writeTextFile(
  `${args.out}/replay.html`,
  renderReport(args.title, `Фактична погода (архів Open-Meteo, ERA5), справжній рушій прогнозу день за днем. Правила видів: ${source}.`, runs),
);
console.log(`→ ${args.out}/replay.html, ${args.out}/replay.json`);
