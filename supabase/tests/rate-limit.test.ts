import {
  checkAndIncrementIpRateLimit,
  RateLimitUnavailableError,
  rateLimitUnavailableResponse,
} from "../functions/_shared/rate-limit.ts";
import { enforceRateLimit, HttpError } from "../functions/_shared/http.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}

async function assertRejects(
  action: () => Promise<unknown>,
  errorClass: new (...args: never[]) => Error,
): Promise<Error> {
  let caught: unknown;
  try {
    await action();
  } catch (error) {
    caught = error;
  }
  if (!(caught instanceof errorClass)) {
    throw new Error(`Expected ${errorClass.name}, received ${String(caught)}`);
  }
  return caught;
}

function rateLimitDb(result: unknown) {
  let fromCalled = false;
  return {
    get fromCalled() {
      return fromCalled;
    },
    rpc: () => Promise.resolve(result),
    from: () => {
      fromCalled = true;
      throw new Error("non-atomic fallback must not run");
    },
  };
}

const asRateLimitDb = (db: unknown) =>
  db as Parameters<typeof checkAndIncrementIpRateLimit>[0];

Deno.test("rate limit: PostgREST table result uses the returned count", async () => {
  const db = rateLimitDb({ data: [{ count: 11 }], error: null });
  const result = await checkAndIncrementIpRateLimit(
    asRateLimitDb(db),
    "192.0.2.1",
    "picks",
    10,
  );
  assertEquals(result.allowed, false);
  assertEquals(result.count, 11);
  assertEquals(result.remaining, 0);
  assertEquals(result.retryAfter, 60);
});

Deno.test("rate limit: object result remains compatible", async () => {
  const db = rateLimitDb({ data: { count: 2 }, error: null });
  const result = await checkAndIncrementIpRateLimit(
    asRateLimitDb(db),
    "192.0.2.1",
    "regions",
    60,
  );
  assertEquals(result.allowed, true);
  assertEquals(result.count, 2);
  assertEquals(result.remaining, 58);
});

Deno.test("rate limit: RPC error fails closed without non-atomic fallback", async () => {
  const db = rateLimitDb({
    data: null,
    error: { message: "connection refused" },
  });
  await assertRejects(
    () =>
      checkAndIncrementIpRateLimit(
        asRateLimitDb(db),
        "192.0.2.1",
        "catalog",
        60,
      ),
    RateLimitUnavailableError,
  );
  assertEquals(db.fromCalled, false);
});

Deno.test("rate limit: rejected RPC request fails closed", async () => {
  const db = {
    rpc: () => Promise.reject(new Error("network unavailable")),
  };
  await assertRejects(
    () =>
      checkAndIncrementIpRateLimit(
        asRateLimitDb(db),
        "192.0.2.1",
        "catalog",
        60,
      ),
    RateLimitUnavailableError,
  );
});

Deno.test("rate limit: malformed RPC data fails closed", async () => {
  const db = rateLimitDb({ data: [], error: null });
  await assertRejects(
    () =>
      checkAndIncrementIpRateLimit(
        asRateLimitDb(db),
        "192.0.2.1",
        "regions",
        60,
      ),
    RateLimitUnavailableError,
  );
});

Deno.test("rate limit: v1 HTTP layer maps counter failure to retryable 503", async () => {
  const db = rateLimitDb({
    data: null,
    error: { message: "database unavailable" },
  });
  const error = await assertRejects(
    () =>
      enforceRateLimit(
        asRateLimitDb(db),
        new Request("http://x/v1"),
        "v1-picks",
      ),
    HttpError,
  ) as HttpError;
  assertEquals(error.status, 503);
  assertEquals(error.code, "rate_limit_unavailable");
  assertEquals(error.headers["Retry-After"], "5");
  assertEquals(db.fromCalled, false);
});

Deno.test("rate limit: unavailable response is retryable 503", async () => {
  const response = rateLimitUnavailableResponse(new Request("http://x"));
  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "5");
  assertEquals((await response.json()).error, "rate_limit_unavailable");
});
