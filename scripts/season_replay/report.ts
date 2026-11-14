// Звіт повтору сезону: HTML (теплова карта «вид × день» + погода) і текстова сітка для логів.

import type { ProbabilityLevel } from "../../supabase/functions/_shared/forecast/types.ts";
import type { ReplayRun } from "./core.ts";

const LEVEL_UA: Record<ProbabilityLevel, string> = {
  peak: "Пік", high: "Висока", medium: "Середня", low: "Низька", no_data: "Недостатньо даних",
};
const LEVEL_CHAR: Record<ProbabilityLevel, string> = { no_data: ".", low: "l", medium: "M", high: "H", peak: "P" };
const RANK: Record<ProbabilityLevel, number> = { no_data: 0, low: 1, medium: 2, high: 3, peak: 4 };
const FOREST_UA: Record<string, string> = {
  pine: "сосновий", spruce: "ялиновий", oak: "дубовий", birch: "березовий", deciduous: "листяний",
  coniferous: "хвойний", mixed: "мішаний",
};

export const forestUa = (t: string | null) => (t ? FOREST_UA[t] ?? t : "тип невідомий");

/** Види, що хоч раз піднялися вище «Недостатньо даних», — за найкращим рівнем. */
function activeSpecies(run: ReplayRun): string[] {
  const best = new Map<string, number>();
  for (const d of run.days) {
    for (const [k, v] of Object.entries(d.species)) best.set(k, Math.max(best.get(k) ?? 0, RANK[v.level]));
  }
  return [...best.entries()].filter(([, r]) => r > 0).sort((a, b) => b[1] - a[1]).map(([k]) => k);
}

/** Сітка для логів: рядок на вид, символ на день (. l M H P). */
export function textGrid(run: ReplayRun): string {
  const lines = [`== ${run.title} (${forestUa(run.forestType)} ліс, ${run.days[0]?.date}…${run.days.at(-1)?.date})`];
  lines.push("дощ    " + run.days.map((d) => (d.weather.rain >= 10 ? "R" : d.weather.rain >= 3 ? "r" : d.weather.rain > 0.5 ? "," : " ")).join(""));
  for (const k of Object.keys(run.names)) {
    lines.push(k.slice(0, 6).padEnd(7) + run.days.map((d) => LEVEL_CHAR[d.species[k]?.level ?? "no_data"]).join(""));
  }
  return lines.join("\n");
}

interface SpeciesSummary {
  key: string;
  name: string;
  firstMedium: string | null;
  highDays: number;
  longestHigh: number;
  peakFrom: string | null;
  peakTo: string | null;
}

function summarize(run: ReplayRun): SpeciesSummary[] {
  return activeSpecies(run).map((key) => {
    let firstMedium: string | null = null, highDays = 0, streak = 0, longest = 0, from: string | null = null;
    let bestFrom: string | null = null, bestTo: string | null = null;
    for (const d of run.days) {
      const r = RANK[d.species[key].level];
      if (r >= RANK.medium && !firstMedium) firstMedium = d.date;
      if (r >= RANK.high) {
        highDays++;
        streak++;
        if (streak === 1) from = d.date;
        if (streak > longest) [longest, bestFrom, bestTo] = [streak, from, d.date];
      } else streak = 0;
    }
    return { key, name: run.names[key] ?? key, firstMedium, highDays, longestHigh: longest, peakFrom: bestFrom, peakTo: bestTo };
  });
}

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const fmtDate = (d: string | null) => (d ? `${d.slice(8, 10)}.${d.slice(5, 7)}` : "—");

function weatherSvg(run: ReplayRun, cell: number): string {
  const n = run.days.length, h = 70, w = n * cell;
  const maxRain = Math.max(20, ...run.days.map((d) => d.weather.rain));
  const temps = run.days.map((d) => d.weather.tmean);
  const tMin = Math.min(-5, ...temps), tMax = Math.max(30, ...temps);
  const y = (t: number) => h - ((t - tMin) / (tMax - tMin)) * h;
  const bars = run.days.map((d, i) => {
    const bh = (d.weather.rain / maxRain) * h;
    return bh > 0 ? `<rect x="${i * cell}" y="${h - bh}" width="${Math.max(1, cell - 1)}" height="${bh}" class="rain"><title>${fmtDate(d.date)}: ${d.weather.rain} мм</title></rect>` : "";
  }).join("");
  const line = temps.map((t, i) => `${i === 0 ? "M" : "L"}${i * cell + cell / 2},${y(t).toFixed(1)}`).join("");
  return `<svg class="wx" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="Опади й температура">
    <line x1="0" x2="${w}" y1="${y(0)}" y2="${y(0)}" class="zero"/>${bars}<path d="${line}" class="temp"/></svg>`;
}

function monthAxis(run: ReplayRun, cell: number): string {
  return run.days.map((d, i) =>
    d.date.endsWith("-01") || i === 0 ? `<span style="left:${i * cell}px">${fmtDate(d.date)}</span>` : ""
  ).join("");
}

function runSection(run: ReplayRun, idx: number): string {
  const cell = run.days.length > 90 ? 6 : 14;
  const species = activeSpecies(run);
  const quiet = Object.keys(run.names).length - species.length;
  const rows = species.map((k) => {
    const cells = run.days.map((d) => {
      const s = d.species[k];
      const tip = `${run.names[k]} · ${fmtDate(d.date)}: ${LEVEL_UA[s.level]}`;
      return `<i class="l-${s.level}" title="${esc(tip)}"></i>`;
    }).join("");
    return `<div class="row"><b>${esc(run.names[k] ?? k)}</b><div class="cells" style="grid-template-columns:repeat(${run.days.length},${cell}px)">${cells}</div></div>`;
  }).join("");
  const top = run.days.map((d) => `<i class="l-${d.top1Level ?? "no_data"}" title="${esc(`${fmtDate(d.date)}: ${d.top1 ? run.names[d.top1] : "—"}`)}"></i>`).join("");
  const sum = summarize(run).map((s) =>
    `<tr><td>${esc(s.name)}</td><td>${fmtDate(s.firstMedium)}</td><td>${s.highDays}</td><td>${s.longestHigh ? `${s.longestHigh} (${fmtDate(s.peakFrom)}–${fmtDate(s.peakTo)})` : "—"}</td></tr>`
  ).join("");
  return `<section id="run-${idx}">
  <h2>${esc(run.title)}</h2>
  <p class="meta">${esc(forestUa(run.forestType))} ліс · ${run.lat.toFixed(2)}, ${run.lng.toFixed(2)} · ${fmtDate(run.days[0].date)}–${fmtDate(run.days.at(-1)!.date)}</p>
  ${run.note ? `<p class="note"><b>Очікування:</b> ${esc(run.note)}</p>` : ""}
  <div class="scroll"><div class="plot" style="width:${run.days.length * cell + 150}px">
    <div class="row"><b>Опади / t°</b>${weatherSvg(run, cell)}</div>
    <div class="row axis"><b></b><div class="months">${monthAxis(run, cell)}</div></div>
    ${rows}
    <div class="row top"><b>Найкращий вид</b><div class="cells" style="grid-template-columns:repeat(${run.days.length},${cell}px)">${top}</div></div>
  </div></div>
  ${quiet ? `<p class="meta">Ще ${quiet} видів увесь період — «Недостатньо даних».</p>` : ""}
  ${sum ? `<table><thead><tr><th>Вид</th><th>Перший день ≥ Середня</th><th>Днів ≥ Висока</th><th>Найдовше ≥ Висока</th></tr></thead><tbody>${sum}</tbody></table>` : ""}
</section>`;
}

export function renderReport(title: string, intro: string, runs: ReplayRun[], findings: string[] = []): string {
  return `<!doctype html>
<html lang="uk"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<style>
:root{--bg:#f6f4ea;--card:#fff;--ink:#1c2b22;--muted:#5f6f64;--line:#d9d6c8;--rain:#5b8fd6;--temp:#d97706;
--l-no_data:#e7e5dc;--l-low:#f3b27a;--l-medium:#eccb4a;--l-high:#5fbf6a;--l-peak:#1f8a4c}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#141a16;--card:#1d2520;--ink:#e6ece7;--muted:#9aa89e;--line:#2f3a33;
--l-no_data:#2a322d;--l-low:#a8683a;--l-medium:#b39a2c;--l-high:#3f9a4b;--l-peak:#5fd08a}}
:root[data-theme="dark"]{--bg:#141a16;--card:#1d2520;--ink:#e6ece7;--muted:#9aa89e;--line:#2f3a33;
--l-no_data:#2a322d;--l-low:#a8683a;--l-medium:#b39a2c;--l-high:#3f9a4b;--l-peak:#5fd08a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:20px 16px 48px}h1{font-size:22px;margin:0 0 6px}h2{font-size:17px;margin:0 0 4px}
.meta{color:var(--muted);font-size:13px;margin:2px 0 8px}.note{font-size:14px;margin:6px 0 10px}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin:14px 0}
.legend{display:flex;flex-wrap:wrap;gap:10px;font-size:13px;color:var(--muted);margin:10px 0}
.legend i{display:inline-block;width:12px;height:12px;border-radius:3px;vertical-align:-2px;margin-right:4px}
.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch;padding-bottom:6px}
.row{display:flex;align-items:center;gap:8px;min-height:16px;margin:1px 0}.row>b{flex:0 0 142px;font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cells{display:grid;gap:0;height:14px}.cells i{display:block;height:14px;border-right:1px solid var(--card)}
.top .cells i{height:8px;margin-top:3px}
.l-no_data{background:var(--l-no_data)}.l-low{background:var(--l-low)}.l-medium{background:var(--l-medium)}.l-high{background:var(--l-high)}.l-peak{background:var(--l-peak)}
.wx .rain{fill:var(--rain);opacity:.75}.wx .temp{fill:none;stroke:var(--temp);stroke-width:1.6}.wx .zero{stroke:var(--line);stroke-dasharray:3 3}
.axis .months{position:relative;height:16px;flex:1}.months span{position:absolute;font-size:11px;color:var(--muted);white-space:nowrap}
table{border-collapse:collapse;width:100%;font-size:13px;margin-top:10px}th,td{text-align:left;padding:5px 8px;border-bottom:1px solid var(--line)}th{color:var(--muted);font-weight:600}
ul.find{padding-left:20px}ul.find li{margin:4px 0}
</style></head><body><main>
<h1>${esc(title)}</h1>
<p class="meta">${esc(intro)}</p>
<div class="legend"><span><i class="l-no_data"></i>Недостатньо даних</span><span><i class="l-low"></i>Низька</span><span><i class="l-medium"></i>Середня</span><span><i class="l-high"></i>Висока</span><span><i class="l-peak"></i>Пік</span><span><i style="background:var(--rain)"></i>опади, мм</span><span><i style="background:var(--temp)"></i>середня t°</span></div>
${findings.length ? `<section><h2>Що видно</h2><ul class="find">${findings.map((f) => `<li>${esc(f)}</li>`).join("")}</ul></section>` : ""}
${runs.map(runSection).join("\n")}
</main></body></html>`;
}
