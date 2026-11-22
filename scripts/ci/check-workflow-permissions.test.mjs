import assert from "node:assert/strict";
import test from "node:test";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  checkRepository,
  validateSmokeSecretMasking,
  validateWorkflowPermissions,
} from "./check-workflow-permissions.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

test("all repository workflows declare reviewed top-level permissions", () => {
  assert.deepEqual(checkRepository(root), {
    workflows: 17,
    writeScoped: ["ai-model.yml", "catalog.yml", "codex-autonomy.yml", "twin-photos.yml"],
  });
});

test("missing top-level permissions fail closed", () => {
  assert.throws(
    () => validateWorkflowPermissions("new.yml", "name: New\njobs: {}\n"),
    /top-level permissions are missing/,
  );
});

test("unreviewed workflow write permission is rejected", () => {
  const source = "name: New\npermissions:\n  contents: write\njobs: {}\n";
  assert.throws(() => validateWorkflowPermissions("new.yml", source), /unreviewed top-level write/);
});

test("production deploy cannot gain repository write access", () => {
  const source = "name: Deploy\npermissions:\n  contents: write\njobs: {}\n";
  assert.throws(
    () => validateWorkflowPermissions("deploy.yml", source),
    /production workflow token must be contents: read only/,
  );
});

test("dynamically fetched service-role key must be masked", () => {
  const source = [
    'SERVICE_KEY=$(echo "$RESULT" | jq -er \'.[] | select(.name=="service_role") | .api_key\')',
    'echo "service_key=$SERVICE_KEY" >> "$GITHUB_OUTPUT"',
  ].join("\n");
  assert.throws(() => validateSmokeSecretMasking(source), /service-role key is not masked/);
});
