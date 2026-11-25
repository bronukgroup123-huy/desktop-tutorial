import assert from "node:assert/strict";
import test from "node:test";
import { runWaveAlerts } from "./run-wave-alerts.mjs";

const env = {
  SUPABASE_ACCESS_TOKEN: "management-token",
  SUPABASE_PROJECT_ID: "abcdefghijklmnopqrst",
  GITHUB_STEP_SUMMARY: "/tmp/summary",
};

function jsonResponse(status, payload) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(payload),
  };
}

test("uses both Authorization and apikey for the service-role invocation", async () => {
  const requests = [];
  const lines = [];
  const summaries = [];
  const result = await runWaveAlerts({
    env,
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      return requests.length === 1
        ? jsonResponse(200, [{ name: "service_role", api_key: "service-secret" }])
        : jsonResponse(200, { data: { users: 2, areas: 3, sent: 1, skipped: 1 } });
    },
    write: (line) => lines.push(line),
    appendSummary: (path, content) => summaries.push({ path, content }),
  });

  assert.deepEqual(result, { users: 2, areas: 3, sent: 1, skipped: 1 });
  assert.equal(requests[1].init.headers.Authorization, "Bearer service-secret");
  assert.equal(requests[1].init.headers.apikey, "service-secret");
  assert(lines.includes("::add-mask::service-secret"));
  assert(!lines.join("\n").includes("management-token"));
  assert.deepEqual(summaries, [{
    path: "/tmp/summary",
    content: '### Сповіщення про хвилі: {"users":2,"areas":3,"sent":1,"skipped":1}\n',
  }]);
});

test("missing configuration fails instead of silently skipping the schedule", async () => {
  await assert.rejects(() => runWaveAlerts({ env: {}, fetchImpl: () => assert.fail("must not fetch") }), /SUPABASE_ACCESS_TOKEN is required/);
});

test("Management API HTTP failures identify the failed stage", async () => {
  await assert.rejects(
    () => runWaveAlerts({ env, fetchImpl: async () => jsonResponse(401, { message: "token management-token rejected" }) }),
    /Supabase Management API returned HTTP 401/,
  );
});

test("missing service-role key fails before invoking the Edge Function", async () => {
  let calls = 0;
  await assert.rejects(
    () => runWaveAlerts({
      env,
      fetchImpl: async () => {
        calls += 1;
        return jsonResponse(200, [{ name: "anon", api_key: "public" }]);
      },
    }),
    /returned 0 service_role keys/,
  );
  assert.equal(calls, 1);
});

test("unsafe service-role key text cannot inject a GitHub workflow command", async () => {
  const lines = [];
  await assert.rejects(
    () => runWaveAlerts({
      env,
      fetchImpl: async () => jsonResponse(200, [{ name: "service_role", api_key: "safe\n::warning::injected" }]),
      write: (line) => lines.push(line),
    }),
    /returned 0 service_role keys/,
  );
  assert.deepEqual(lines, []);
});

test("Edge Function failures expose only HTTP status and a safe error code", async () => {
  let calls = 0;
  await assert.rejects(
    () => runWaveAlerts({
      env,
      fetchImpl: async () => {
        calls += 1;
        return calls === 1
          ? jsonResponse(200, [{ name: "service_role", api_key: "service-secret" }])
          : jsonResponse(401, { error: "invalid_api_key", message: "secret service-secret" });
      },
      write: () => {},
    }),
    (error) => {
      assert.equal(error.message, "v1-wave-alerts returned HTTP 401 (invalid_api_key)");
      assert(!error.message.includes("service-secret"));
      return true;
    },
  );
});

test("non-JSON Edge Function failures still identify the HTTP stage", async () => {
  let calls = 0;
  await assert.rejects(
    () => runWaveAlerts({
      env,
      fetchImpl: async () => {
        calls += 1;
        return calls === 1
          ? jsonResponse(200, [{ name: "service_role", api_key: "service-secret" }])
          : { ok: false, status: 502, json: () => Promise.reject(new SyntaxError("HTML response")) };
      },
      write: () => {},
    }),
    /v1-wave-alerts returned HTTP 502/,
  );
});

test("invalid success payloads fail closed", async () => {
  let calls = 0;
  await assert.rejects(
    () => runWaveAlerts({
      env,
      fetchImpl: async () => {
        calls += 1;
        return calls === 1
          ? jsonResponse(200, [{ name: "service_role", api_key: "service-secret" }])
          : jsonResponse(200, { data: { users: "two", areas: 3, sent: 1, skipped: 1 } });
      },
      write: () => {},
    }),
    /invalid data.users/,
  );
});
