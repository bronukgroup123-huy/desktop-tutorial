import { readdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const AUTH_CLASSES = new Set([
  "public",
  "mixed_handler_auth",
  "user_jwt",
  "service_role",
  "webhook_secret",
]);

export const JWT_BYPASS_CLASSES = new Set([
  "public",
  "mixed_handler_auth",
  "webhook_secret",
]);

function sorted(values) {
  return [...values].sort((a, b) => a.localeCompare(b));
}

function sameValues(left, right) {
  return JSON.stringify(sorted(left)) === JSON.stringify(sorted(right));
}

export function parseFunctionJwtConfig(toml) {
  const result = new Map();
  let currentFunction = null;

  for (const rawLine of toml.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    const section = /^\[functions\.([A-Za-z0-9_-]+)\]$/.exec(line);
    if (section) {
      currentFunction = section[1];
      continue;
    }
    if (/^\[.*\]$/.test(line)) {
      currentFunction = null;
      continue;
    }
    const setting = /^verify_jwt\s*=\s*(true|false)$/.exec(line);
    if (currentFunction && setting) {
      result.set(currentFunction, setting[1] === "true");
    }
  }

  return result;
}

export function validateEdgeAuthMatrix({ deployedFunctions, matrix, jwtConfig }) {
  const errors = [];
  const matrixFunctions = Object.keys(matrix);

  if (!sameValues(deployedFunctions, matrixFunctions)) {
    const deployed = new Set(deployedFunctions);
    const classified = new Set(matrixFunctions);
    const missing = sorted(deployedFunctions.filter((name) => !classified.has(name)));
    const stale = sorted(matrixFunctions.filter((name) => !deployed.has(name)));
    if (missing.length) errors.push(`unclassified deployed functions: ${missing.join(", ")}`);
    if (stale.length) errors.push(`matrix entries without a function directory: ${stale.join(", ")}`);
  }

  for (const [name, authClass] of Object.entries(matrix)) {
    if (!AUTH_CLASSES.has(authClass)) {
      errors.push(`${name} has unsupported auth class: ${authClass}`);
    }
  }

  const expectedBypass = sorted(
    Object.entries(matrix)
      .filter(([, authClass]) => JWT_BYPASS_CLASSES.has(authClass))
      .map(([name]) => name),
  );
  const configuredBypass = sorted(
    [...jwtConfig.entries()]
      .filter(([, verifyJwt]) => verifyJwt === false)
      .map(([name]) => name),
  );
  if (!sameValues(expectedBypass, configuredBypass)) {
    errors.push(
      `verify_jwt=false must exactly match the bypass allowlist; expected [${expectedBypass.join(", ")}], configured [${configuredBypass.join(", ")}]`,
    );
  }

  for (const [name, verifyJwt] of jwtConfig.entries()) {
    if (!(name in matrix)) errors.push(`config references unclassified function: ${name}`);
    if (verifyJwt === false && !JWT_BYPASS_CLASSES.has(matrix[name])) {
      errors.push(`${name} disables platform JWT verification despite auth class ${matrix[name]}`);
    }
  }

  if (errors.length) throw new Error(errors.join("\n"));
  return { deployed: deployedFunctions.length, bypass: expectedBypass.length };
}

export function checkRepository(root) {
  const functionsDir = resolve(root, "supabase/functions");
  const deployedFunctions = readdirSync(functionsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== "_shared")
    .map((entry) => entry.name);
  const matrix = JSON.parse(
    readFileSync(resolve(functionsDir, "auth-matrix.json"), "utf8"),
  ).functions;
  const jwtConfig = parseFunctionJwtConfig(
    readFileSync(resolve(root, "supabase/config.toml"), "utf8"),
  );
  const workflow = readFileSync(resolve(root, ".github/workflows/deploy.yml"), "utf8");

  if (!workflow.includes("supabase/functions/auth-matrix.json")) {
    throw new Error("deploy workflow must read supabase/functions/auth-matrix.json");
  }
  if (!workflow.includes('AUTH_CLASS=$(jq -er --arg fn "$fn"')) {
    throw new Error("deploy workflow must fail when a function is absent from the auth matrix");
  }
  if (/supabase functions deploy[^\n]*--no-verify-jwt/.test(workflow)) {
    throw new Error("deploy workflow must not disable JWT verification directly for every function");
  }
  if (!workflow.includes("JWT_ARGS=(--no-verify-jwt)") || !workflow.includes("JWT_ARGS=()")) {
    throw new Error("deploy workflow must choose JWT flags from the classified auth mode");
  }

  return validateEdgeAuthMatrix({ deployedFunctions, matrix, jwtConfig });
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === currentFile) {
  const root = resolve(dirname(currentFile), "../..");
  const result = checkRepository(root);
  console.log(
    `Edge auth matrix valid: ${result.deployed} functions, ${result.bypass} explicit JWT bypasses`,
  );
}
