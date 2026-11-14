// Штучні сценарії сезону → звіт (без мережі).
//   deno run -A scripts/season_replay/scenarios.ts [--rules rules.json] [--out out/scenarios.html]
import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { compactRun, renderReport, textGrid } from "./report.ts";
import { loadRules } from "./rules.ts";
import { runScenario, SCENARIOS } from "./core.ts";

const args = parseArgs(Deno.args, { string: ["rules", "out"], default: { out: "out/scenarios.html" } });
const { rules, flags, source } = await loadRules(args.rules);
const runs = SCENARIOS.map((s) => runScenario(s, rules, flags));
for (const r of runs) console.log(textGrid(r) + "\n");
for (const r of runs) console.log(`REPLAY_COMPACT ${compactRun(r)}`);
await Deno.mkdir(args.out.replace(/\/[^/]+$/, ""), { recursive: true });
await Deno.writeTextFile(
  args.out,
  renderReport("Сценарії сезону", `Штучна погода, справжній рушій прогнозу. Правила видів: ${source}.`, runs),
);
console.log(`→ ${args.out}`);
