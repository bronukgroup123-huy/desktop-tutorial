import {
  assertEquals,
  assert,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://localhost:54321";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;

async function createTestUser(): Promise<{ userId: string; token: string }> {
  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const email = `test-${crypto.randomUUID()}@example.com`;
  const { data, error } = await db.auth.admin.createUser({
    email,
    password: "test-password-123",
    email_confirm: true,
  });
  if (error || !data.user) throw new Error(`Failed: ${error?.message}`);

  const { data: session, error: signInError } = await db.auth.signInWithPassword({
    email,
    password: "test-password-123",
  });
  if (signInError || !session.session) throw new Error("Sign-in failed");

  return { userId: data.user.id, token: session.session.access_token };
}

async function callFunction(
  path: string,
  options: RequestInit = {}
): Promise<Response> {
  return fetch(`${FUNCTIONS_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(options.headers ?? {}),
    },
  });
}

Deno.test("create session → returns tokens for guardians", async () => {
  const { token } = await createTestUser();
  const futureReturn = new Date(Date.now() + 5 * 60 * 60 * 1000).toISOString();

  const res = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: futureReturn,
      guardians: [
        { name: "Мама", phone: "+380501234567" },
        { name: "Тарас", phone: "+380507654321", is_emergency: true },
      ],
    }),
  });

  assertEquals(res.status, 201);
  const body = await res.json();
  assertExists(body.data.session.id);
  assertEquals(body.data.guardians.length, 2);
  assert(body.data.guardians[0].token.length > 100);
  assert(body.data.guardians[0].url.includes("/s/"));
});

Deno.test("create session → conflict if active session exists", async () => {
  const { token } = await createTestUser();
  const body = {
    expected_return: new Date(Date.now() + 3600000).toISOString(),
    guardians: [{ name: "A", phone: "+380501111111" }],
  };

  await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });

  const res = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });

  assertEquals(res.status, 409);
});

Deno.test("create session → rejects past expected_return", async () => {
  const { token } = await createTestUser();
  const res = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() - 1000).toISOString(),
      guardians: [{ name: "A", phone: "+380501111111" }],
    }),
  });
  assertEquals(res.status, 422);
});

Deno.test("guardian get session → returns state", async () => {
  const { token } = await createTestUser();
  const createRes = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [{ name: "Мама", phone: "+380501234567" }],
    }),
  });
  const { data } = await createRes.json();
  const guardianToken = data.guardians[0].token;

  const res = await callFunction(`/guardian-session-get/${guardianToken}`);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.session.status, "pending");
  assertEquals(body.data.guardians.length, 1);
});

Deno.test("guardian get session → invalid token rejected", async () => {
  const res = await callFunction("/guardian-session-get/invalid.token.here");
  assertEquals(res.status, 401);
});

Deno.test("ping → creates track point and activates session", async () => {
  const { token } = await createTestUser();
  const createRes = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [{ name: "A", phone: "+380501111111" }],
    }),
  });
  await createRes.json();

  const pingRes = await callFunction("/guardian-ping", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      lat: 50.45,
      lng: 30.52,
      battery_pct: 85,
      signal_strength: 4,
    }),
  });
  assertEquals(pingRes.status, 201);
  const body = await pingRes.json();
  assertEquals(body.data.status, "active");
});

Deno.test("extend → moves expected_return forward", async () => {
  const { token } = await createTestUser();
  const originalReturn = new Date(Date.now() + 3600000);
  const createRes = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: originalReturn.toISOString(),
      guardians: [{ name: "A", phone: "+380501111111" }],
    }),
  });
  await createRes.json();

  const extendRes = await callFunction("/guardian-extend", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ minutes: 30 }),
  });
  assertEquals(extendRes.status, 200);
  const body = await extendRes.json();
  const newReturn = new Date(body.data.session.expected_return);
  assertEquals(
    Math.round((newReturn.getTime() - originalReturn.getTime()) / 60000),
    30
  );
});

Deno.test("exiting → transitions to exiting state", async () => {
  const { token } = await createTestUser();
  await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [{ name: "A", phone: "+380501111111" }],
    }),
  });

  const res = await callFunction("/guardian-exiting", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.session.status, "exiting");
});

Deno.test("close → moves to closing, cancel-close → back to previous", async () => {
  const { token } = await createTestUser();
  await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [{ name: "A", phone: "+380501111111" }],
    }),
  });

  const closeRes = await callFunction("/guardian-close", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  assertEquals(closeRes.status, 200);
  const closeBody = await closeRes.json();
  assertEquals(closeBody.data.session.status, "closing");
  assertEquals(closeBody.data.session.previous_status, "pending");

  const cancelRes = await callFunction("/guardian-cancel-close", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  assertEquals(cancelRes.status, 200);
  const cancelBody = await cancelRes.json();
  assertEquals(cancelBody.data.session.status, "pending");
  assertEquals(cancelBody.data.session.previous_status, null);
});

Deno.test("revoke → guardian token no longer works", async () => {
  const { token } = await createTestUser();
  const createRes = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [
        { name: "A", phone: "+380501111111" },
        { name: "B", phone: "+380502222222" },
      ],
    }),
  });
  const { data } = await createRes.json();
  const guardianAId = data.guardians[0].id;
  const guardianAToken = data.guardians[0].token;

  const revokeRes = await callFunction(
    `/guardian-revoke/${guardianAId}`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    }
  );
  assertEquals(revokeRes.status, 200);

  const getRes = await callFunction(`/guardian-session-get/${guardianAToken}`);
  assertEquals(getRes.status, 401);
});

Deno.test("revoke → cannot revoke guardian from another session", async () => {
  const { token: tokenA } = await createTestUser();
  const { token: tokenB } = await createTestUser();

  const createA = await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${tokenA}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [{ name: "A", phone: "+380501111111" }],
    }),
  });
  const { data: dataA } = await createA.json();

  await callFunction("/guardian-session-create", {
    method: "POST",
    headers: { Authorization: `Bearer ${tokenB}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600000).toISOString(),
      guardians: [{ name: "B", phone: "+380502222222" }],
    }),
  });

  const res = await callFunction(
    `/guardian-revoke/${dataA.guardians[0].id}`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${tokenB}` },
    }
  );
  assertEquals(res.status, 404);
});
