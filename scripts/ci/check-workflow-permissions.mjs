import { readFileSync, readdirSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REVIEWED_TOP_LEVEL_WRITE = new Map([
  ["ai-model.yml", new Set(["contents"])],
  ["catalog.yml", new Set(["contents"])],
  ["codex-autonomy.yml", new Set(["contents", "pull-requests"])],
  ["twin-photos.yml", new Set(["contents"])],
]);

const DATA_WORKFLOWS = new Set([
  "basemap.yml",
  "forest-type-pilot.yml",
  "forests.yml",
  "trails.yml",
]);

function expect(errors, condition, message) {
  if (!condition) errors.push(message);
}

export function parseTopLevelPermissions(source) {
  const lines = source.split(/\r?\n/);
  const start = lines.findIndex((line) => /^permissions:\s*$/.test(line));
  if (start < 0) return null;
  const permissions = new Map();
  for (let index = start + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.trim() || /^\s+#/.test(line)) continue;
    if (!/^\s/.test(line)) break;
    const match = /^ {2}([a-z-]+):\s*(read|write|none)\s*$/.exec(line);
    if (match) permissions.set(match[1], match[2]);
  }
  return permissions;
}

export function validateWorkflowPermissions(name, source) {
  const errors = [];
  const permissions = parseTopLevelPermissions(source);
  expect(errors, permissions != null, `${name}: top-level permissions are missing`);
  if (!permissions) throw new Error(errors.join("\n"));
  expect(errors, permissions.size > 0, `${name}: top-level permissions must be an explicit mapping`);

  const writes = new Set([...permissions].filter(([, value]) => value === "write").map(([key]) => key));
  const reviewedWrites = REVIEWED_TOP_LEVEL_WRITE.get(name) ?? new Set();
  for (const permission of writes) {
    expect(errors, reviewedWrites.has(permission), `${name}: unreviewed top-level write permission: ${permission}`);
  }

  if (name === "deploy.yml" || name === "smoke-test.yml") {
    expect(
      errors,
      permissions.size === 1 && permissions.get("contents") === "read",
      `${name}: production workflow token must be contents: read only`,
    );
  }

  if (errors.length) throw new Error(errors.join("\n"));
  return { writes: [...writes].sort() };
}

export function validateSmokeSecretMasking(source) {
  const errors = [];
  expect(errors, source.includes('echo "::add-mask::$ANON_KEY"'), "smoke-test.yml: anonymous key is not masked");
  expect(errors, source.includes('echo "::add-mask::$SERVICE_KEY"'), "smoke-test.yml: service-role key is not masked");
  expect(errors, source.includes('echo "::add-mask::$JWT"'), "smoke-test.yml: user JWT is not masked");
  expect(errors, /jq -er[^\n]+name=="service_role"/.test(source), "smoke-test.yml: service-role key extraction is not fail-closed");
  if (errors.length) throw new Error(errors.join("\n"));
}

export function validateProductionSecretScope(name, source) {
  const lines = source.split(/\r?\n/);
  const errors = [];
  for (let index = 0; index < lines.length; index += 1) {
    if (/^env:\s*$/.test(lines[index])) {
      const block = [];
      for (let offset = index + 1; offset < lines.length; offset += 1) {
        if (lines[offset].trim() && !/^\s/.test(lines[offset])) break;
        block.push(lines[offset]);
      }
      expect(errors, !block.some((line) => line.includes("secrets.")), `${name}: secrets are exposed at workflow scope`);
    }
    if (!/^ {4}env:\s*$/.test(lines[index])) continue;
    const block = [];
    for (let offset = index + 1; offset < lines.length; offset += 1) {
      if (lines[offset].trim() && lines[offset].search(/\S/) <= 4) break;
      block.push(lines[offset]);
    }
    expect(errors, !block.some((line) => line.includes("secrets.")), `${name}: production secrets are exposed at job scope`);
  }
  if (errors.length) throw new Error(errors.join("\n"));
}

function jobBlock(source, jobName) {
  const lines = source.split(/\r?\n/);
  const start = lines.findIndex((line) => line === `  ${jobName}:`);
  if (start < 0) return "";
  const end = lines.findIndex((line, index) => index > start && /^ {2}[a-zA-Z0-9_-]+:\s*$/.test(line));
  return lines.slice(start, end < 0 ? undefined : end).join("\n");
}

export function validateDataWorkflowSafety(name, source) {
  const errors = [];
  const artifactChecks = new Map([
    ["forests.yml", "name: forests-generator-check"],
    ["trails.yml", "name: trails-generator-check"],
    ["forest-type-pilot.yml", "name: ci-forest-type-validation"],
  ]);
  const artifactCheck = artifactChecks.get(name);
  if (artifactCheck) {
    expect(errors, source.includes(artifactCheck), `${name}: fast PR artifact smoke test is missing`);
  }

  if (name === "forest-type-pilot.yml") {
    expect(
      errors,
      source.includes("python -m py_compile scripts/forest_type/s2_leaf_type.py scripts/forest_type/zonal.py"),
      `${name}: fast Python validation is missing`,
    );
  }

  const heavyJobs = new Map([
    ["forests.yml", "build"],
    ["forest-type-pilot.yml", "map"],
  ]);
  const heavyJob = heavyJobs.get(name);
  if (heavyJob) {
    const block = jobBlock(source, heavyJob);
    expect(errors, block.length > 0, `${name}: ${heavyJob} job is missing`);
    expect(errors, block.includes("github.actor != 'dependabot[bot]'"), `${name}: heavy PR job must skip Dependabot`);
    expect(
      errors,
      block.includes("github.event.pull_request.head.repo.full_name == github.repository"),
      `${name}: heavy PR job must skip fork pull requests`,
    );
    expect(errors, block.includes("contents: read"), `${name}: heavy data job must be read-only`);
    expect(errors, !block.includes("contents: write"), `${name}: heavy data job cannot publish directly`);
  }

  if (errors.length) throw new Error(errors.join("\n"));
}

export function checkRepository(root) {
  const workflowsRoot = resolve(root, ".github/workflows");
  const files = readdirSync(workflowsRoot)
    .filter((file) => /\.ya?ml$/.test(file))
    .sort();
  const writeScoped = [];
  for (const file of files) {
    const source = readFileSync(resolve(workflowsRoot, file), "utf8");
    const result = validateWorkflowPermissions(basename(file), source);
    if (result.writes.length) writeScoped.push(file);
    if (file === "smoke-test.yml") validateSmokeSecretMasking(source);
    if (file === "deploy.yml" || file === "smoke-test.yml" || DATA_WORKFLOWS.has(file)) {
      validateProductionSecretScope(file, source);
    }
    if (DATA_WORKFLOWS.has(file)) validateDataWorkflowSafety(file, source);
  }
  return { workflows: files.length, writeScoped };
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === currentFile) {
  const result = checkRepository(resolve(dirname(currentFile), "../.."));
  console.log(`Workflow permissions valid: ${result.workflows} explicit, ${result.writeScoped.length} reviewed write-scoped`);
}
