import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function expect(errors, condition, message) {
  if (!condition) errors.push(message);
}

export function scheduleHours(workflow) {
  const cron = /cron:\s*['"]17\s+([0-9,]+)\s+\*\s+\*\s+\*['"]/.exec(workflow)?.[1];
  if (!cron) return null;
  return cron.split(",").map(Number).sort((a, b) => a - b);
}

export function maximumScheduleGap(hours) {
  if (!hours?.length) return Infinity;
  const gaps = hours.slice(1).map((hour, index) => hour - hours[index]);
  gaps.push(24 - hours.at(-1) + hours[0]);
  return Math.max(...gaps);
}

export function validateAutonomy({ workflow, prompt, ownership }) {
  const errors = [];
  const hours = scheduleHours(workflow);
  expect(errors, maximumScheduleGap(hours) <= 5, "scheduled retry gap exceeds five hours");
  expect(errors, /workflow_dispatch:/.test(workflow), "manual recovery trigger is missing");
  expect(errors, !workflow.includes("CODEX_AUTONOMY_ENABLED"), "obsolete manual enable gate is still present");
  expect(errors, /permissions:\s*\n\s+contents: write\s*\n\s+pull-requests: write/.test(workflow), "review-branch permissions are incomplete");
  expect(errors, /cancel-in-progress: false/.test(workflow), "concurrent runs must queue instead of cancelling work");
  expect(errors, /timeout-minutes: 55/.test(workflow), "bounded job timeout is missing");
  expect(errors, /Check autonomous maintenance window/.test(workflow) && /2026-12-23/.test(workflow), "30-day execution window guard is missing");
  expect(errors, /name: Execute one bounded task\s*\n\s+if: steps\.window\.outputs\.active == 'true'/.test(workflow), "Codex execution can bypass the date window");
  expect(errors, /OPENAI_API_KEY: \$\{\{ secrets\.OPENAI_API_KEY \}\}/.test(workflow), "OpenAI key must come from repository secrets");
  const secretNames = [...workflow.matchAll(/secrets\.([A-Z0-9_]+)/g)].map((match) => match[1]);
  expect(errors, secretNames.every((name) => name === "OPENAI_API_KEY"), "autonomous job receives a production secret");
  expect(errors, /@openai\/codex@\d+\.\d+\.\d+/.test(workflow), "Codex CLI version is not exact");
  expect(errors, /gh pr create/.test(workflow) && !/gh pr (?:merge|close)/.test(workflow), "workflow must open review-only PRs and never merge them");
  expect(errors, prompt.includes("WORK_OWNERSHIP.md") && prompt.includes("overlap Claude"), "agent prompt lacks file-collision handling");
  expect(errors, prompt.includes("blocked_rate_limit") && prompt.includes("within five hours"), "agent prompt lacks bounded rate-limit recovery");
  expect(errors, /Do not deploy, merge, auto-merge/.test(prompt), "agent prompt lacks production and merge prohibition");
  expect(errors, ownership.includes("## Codex") && ownership.includes("## Claude") && ownership.includes("Collision rule"), "ownership contract is incomplete");
  if (errors.length) throw new Error(errors.join("\n"));
  return { scheduledHours: hours, maximumGapHours: maximumScheduleGap(hours) };
}

export function checkRepository(root) {
  return validateAutonomy({
    workflow: readFileSync(resolve(root, ".github/workflows/codex-autonomy.yml"), "utf8"),
    prompt: readFileSync(resolve(root, ".github/codex/autonomy.md"), "utf8"),
    ownership: readFileSync(resolve(root, "docs/agent/WORK_OWNERSHIP.md"), "utf8"),
  });
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === currentFile) {
  const result = checkRepository(resolve(dirname(currentFile), "../.."));
  console.log(`Codex autonomy safety valid: max schedule gap ${result.maximumGapHours}h`);
}
