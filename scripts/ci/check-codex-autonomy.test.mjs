import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { checkRepository, validateAutonomy } from "./check-codex-autonomy.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const valid = {
  workflow: readFileSync(resolve(root, ".github/workflows/codex-autonomy.yml"), "utf8"),
  prompt: readFileSync(resolve(root, ".github/codex/autonomy.md"), "utf8"),
  ownership: readFileSync(resolve(root, "docs/agent/WORK_OWNERSHIP.md"), "utf8"),
  claudeRunbook: readFileSync(resolve(root, "docs/agent/AUTONOMY.md"), "utf8"),
};

test("repository autonomy configuration is bounded and review-only", () => {
  assert.deepEqual(checkRepository(root), {
    scheduledHours: [0, 5, 10, 15, 20],
    maximumGapHours: 5,
  });
});

test("schedule gaps longer than five hours fail", () => {
  const workflow = valid.workflow.replace("0,5,10,15,20", "0,6,12,18");
  assert.throws(() => validateAutonomy({ ...valid, workflow }), /scheduled retry gap exceeds five hours/);
});

test("production secrets fail the autonomous workflow guard", () => {
  const workflow = `${valid.workflow}\n# secrets.SUPABASE_ACCESS_TOKEN`;
  assert.throws(() => validateAutonomy({ ...valid, workflow }), /receives a production secret/);
});

test("merge commands fail the review-only guard", () => {
  const workflow = `${valid.workflow}\n# gh pr merge --auto`;
  assert.throws(() => validateAutonomy({ ...valid, workflow }), /never merge/);
});

test("missing collision handling fails", () => {
  const prompt = valid.prompt.replace("overlap Claude", "conflict with other work");
  assert.throws(() => validateAutonomy({ ...valid, prompt }), /file-collision handling/);
});

test("Claude state writes fail the ownership guard", () => {
  const claudeRunbook = valid.claudeRunbook.replace(
    "Treat `docs/agent/*` as read-only",
    "Update `docs/agent/*` after every run",
  );
  assert.throws(() => validateAutonomy({ ...valid, claudeRunbook }), /collide with Codex state files/);
});
