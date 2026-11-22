import { isServiceRoleRequest } from "../../functions/_shared/guardian/service-auth.ts";

function assertEquals(actual: unknown, expected: unknown, label: string): void {
  if (actual !== expected) {
    throw new Error(
      `${label}: expected ${String(expected)}, got ${String(actual)}`,
    );
  }
}

Deno.test("service auth rejects a missing Authorization header", () => {
  assertEquals(
    isServiceRoleRequest(new Request("https://example.test"), "service-secret"),
    false,
    "missing header",
  );
});

Deno.test("service auth rejects an anon or malformed bearer token", () => {
  for (
    const authorization of [
      "Bearer anon-key",
      "bearer service-secret",
      "Bearer service-secret extra",
    ]
  ) {
    const req = new Request("https://example.test", {
      headers: { Authorization: authorization },
    });
    assertEquals(
      isServiceRoleRequest(req, "service-secret"),
      false,
      authorization,
    );
  }
});

Deno.test("service auth rejects requests when the server key is missing", () => {
  const req = new Request("https://example.test", {
    headers: { Authorization: "Bearer service-secret" },
  });
  assertEquals(isServiceRoleRequest(req, ""), false, "missing server key");
});

Deno.test("service auth accepts the exact service-role bearer token", () => {
  const req = new Request("https://example.test", {
    headers: { Authorization: "Bearer service-secret" },
  });
  assertEquals(
    isServiceRoleRequest(req, "service-secret"),
    true,
    "valid service token",
  );
});
