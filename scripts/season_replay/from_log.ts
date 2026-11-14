// Звіт із логу запуску (рядки REPLAY_COMPACT) — коли артефакт недоступний.
//   deno run -A scripts/season_replay/from_log.ts log.txt out.html "Сезон 2025"
import { expandRun, renderReport } from "./report.ts";

const [log, out, title = "Повтор сезону"] = Deno.args;
const runs = (await Deno.readTextFile(log)).split("\n")
  .map((l) => l.replace(/^\S+Z /, ""))
  .filter((l) => l.startsWith("REPLAY_COMPACT "))
  .map((l) => expandRun(l.slice("REPLAY_COMPACT ".length)));
await Deno.writeTextFile(out, renderReport(title, "Відновлено з логу запуску (рівні, найкращий вид, погода дня).", runs));
console.log(`${runs.length} прогонів → ${out}`);
