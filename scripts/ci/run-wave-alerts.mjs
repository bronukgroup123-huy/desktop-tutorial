import { appendFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const KEY_API_TIMEOUT_MS = 60_000;
const WAVE_ALERT_TIMEOUT_MS = 280_000;
const SAFE_ERROR_CODE = /^[a-z][a-z0-9_]{0,63}$/;
const SAFE_PROJECT_REF = /^[a-z0-9]{10,40}$/;
const SAFE_API_KEY = /^[A-Za-z0-9._-]+$/;

function required(env, name) {
  const value = env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

async function request(fetchImpl, stage, url, init, timeoutMs) {
  try {
    return await fetchImpl(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  } catch (error) {
    const kind = error instanceof Error ? error.name : "unknown_error";
    throw new Error(`${stage} request failed (${kind})`);
  }
}

async function readJson(response, stage) {
  try {
    return await response.json();
  } catch {
    throw new Error(`${stage} returned invalid JSON`);
  }
}

function safeRemoteError(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
  const code = payload.error;
  return typeof code === "string" && SAFE_ERROR_CODE.test(code) ? code : null;
}

function validateResult(payload) {
  const data = payload?.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("v1-wave-alerts returned an invalid success payload");
  }
  for (const field of ["users", "areas", "sent", "skipped"]) {
    if (!Number.isSafeInteger(data[field]) || data[field] < 0) {
      throw new Error(`v1-wave-alerts returned an invalid data.${field}`);
    }
  }
  return data;
}

export async function runWaveAlerts({
  env = process.env,
  fetchImpl = globalThis.fetch,
  write = (line) => process.stdout.write(`${line}\n`),
  appendSummary = (path, content) => appendFileSync(path, content, "utf8"),
} = {}) {
  const accessToken = required(env, "SUPABASE_ACCESS_TOKEN");
  const projectId = required(env, "SUPABASE_PROJECT_ID");
  if (!SAFE_PROJECT_REF.test(projectId)) throw new Error("SUPABASE_PROJECT_ID has an invalid format");

  const keysResponse = await request(
    fetchImpl,
    "Supabase Management API",
    `https://api.supabase.com/v1/projects/${projectId}/api-keys?reveal=true`,
    { headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" } },
    KEY_API_TIMEOUT_MS,
  );
  if (!keysResponse.ok) {
    throw new Error(`Supabase Management API returned HTTP ${keysResponse.status}`);
  }
  const keys = await readJson(keysResponse, "Supabase Management API");
  if (!Array.isArray(keys)) throw new Error("Supabase Management API returned an invalid key list");
  const serviceKeys = keys
    .filter((item) => item?.name === "service_role" && typeof item.api_key === "string" && SAFE_API_KEY.test(item.api_key))
    .map((item) => item.api_key);
  if (serviceKeys.length !== 1) {
    throw new Error(`Supabase Management API returned ${serviceKeys.length} service_role keys; expected exactly one`);
  }
  const serviceKey = serviceKeys[0];
  write(`::add-mask::${serviceKey}`);

  const alertResponse = await request(
    fetchImpl,
    "v1-wave-alerts",
    `https://${projectId}.supabase.co/functions/v1/v1-wave-alerts`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
        "Content-Type": "application/json",
      },
      body: "{}",
    },
    WAVE_ALERT_TIMEOUT_MS,
  );
  let payload;
  try {
    payload = await alertResponse.json();
  } catch {
    if (!alertResponse.ok) throw new Error(`v1-wave-alerts returned HTTP ${alertResponse.status}`);
    throw new Error("v1-wave-alerts returned invalid JSON");
  }
  if (!alertResponse.ok) {
    const remoteCode = safeRemoteError(payload);
    throw new Error(`v1-wave-alerts returned HTTP ${alertResponse.status}${remoteCode ? ` (${remoteCode})` : ""}`);
  }

  const data = validateResult(payload);
  const compact = JSON.stringify(data);
  write(`Wave alerts completed: ${compact}`);
  if (env.GITHUB_STEP_SUMMARY) appendSummary(env.GITHUB_STEP_SUMMARY, `### Сповіщення про хвилі: ${compact}\n`);
  return data;
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  runWaveAlerts().catch((error) => {
    const message = error instanceof Error ? error.message : "unknown error";
    process.stderr.write(`::error::${message}\n`);
    process.exitCode = 1;
  });
}
