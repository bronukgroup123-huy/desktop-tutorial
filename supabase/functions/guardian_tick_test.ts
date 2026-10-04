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
  const email = `tick-${crypto.randomUUID()}@example.com`;
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

async function createSession(token: string, expectedReturnOffsetMs: number) {
  const res = await fetch(`${FUNCTIONS_URL}/guardian-session-create`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + expectedReturnOffsetMs).toISOString(),
      guardians: [{ name: "Test", phone: "+380501111111" }],
    }),
  });
  const body = await res.json();
  return body.data;
}

async function callTick(): Promise<Response> {
  return fetch(`${FUNCTIONS_URL}/guardian-tick`, { method: "POST" });
}

Deno.test("tick → skips pending sessions", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, 3600_000);

  const res = await callTick();
  assertEquals(res.status, 200);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data } = await db
    .from("guardian_sessions")
    .select("status")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "pending");
});

Deno.test("tick → active → stale after STALE_MIN", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, 3600_000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  await db
    .from("guardian_sessions")
    .update({
      status: "active",
      last_known_at: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
    })
    .eq("id", session.session.id);

  const res = await callTick();
  assertEquals(res.status, 200);

  const { data } = await db
    .from("guardian_sessions")
    .select("status")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "stale");
});

Deno.test("tick → stale → offline after OFFLINE_MIN", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, 3600_000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  await db
    .from("guardian_sessions")
    .update({
      status: "stale",
      last_known_at: new Date(Date.now() - 70 * 60 * 1000).toISOString(),
    })
    .eq("id", session.session.id);

  await callTick();

  const { data } = await db
    .from("guardian_sessions")
    .select("status")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "offline");
});

Deno.test("tick → active → overdue_soft when time passed and not moving", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, -5 * 60 * 1000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  await db
    .from("guardian_sessions")
    .update({
      status: "active",
      last_known_at: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
    })
    .eq("id", session.session.id);

  await db.from("guardian_track").insert({
    session_id: session.session.id,
    coords: "POINT(30.52 50.45)",
    recorded_at: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
    speed_kmh: 0,
  });

  await callTick();

  const { data } = await db
    .from("guardian_sessions")
    .select("status, overdue_level")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "overdue_soft");
  assertEquals(data?.overdue_level, "soft");
});

Deno.test("tick → overdue_soft → overdue_medium after 30 min", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, -35 * 60 * 1000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  await db
    .from("guardian_sessions")
    .update({
      status: "overdue_soft",
      overdue_level: "soft",
      last_known_at: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
    })
    .eq("id", session.session.id);

  await db.from("guardian_track").insert({
    session_id: session.session.id,
    coords: "POINT(30.52 50.45)",
    recorded_at: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
    speed_kmh: 0,
  });

  await callTick();

  const { data } = await db
    .from("guardian_sessions")
    .select("status, overdue_level")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "overdue_medium");
  assertEquals(data?.overdue_level, "medium");
});

Deno.test("tick → closing → closed after grace period", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, 3600_000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  await db
    .from("guardian_sessions")
    .update({
      status: "closing",
      closing_started_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
      previous_status: "active",
    })
    .eq("id", session.session.id);

  await callTick();

  const { data } = await db
    .from("guardian_sessions")
    .select("status, recoverable_until")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "closed");
  assertExists(data?.recoverable_until);
});

Deno.test("tick → idempotent: повторний виклик не змінює стан", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, 3600_000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  await db
    .from("guardian_sessions")
    .update({
      status: "active",
      last_known_at: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
    })
    .eq("id", session.session.id);

  await callTick();
  await callTick();
  await callTick();

  const { data } = await db
    .from("guardian_sessions")
    .select("status")
    .eq("id", session.session.id)
    .single();

  assertEquals(data?.status, "stale");
});

Deno.test("tick → alert дублікати не створюються", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token, 3600_000);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  await db
    .from("guardian_sessions")
    .update({
      status: "active",
      last_known_at: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
    })
    .eq("id", session.session.id);

  await callTick();
  await callTick();
  await callTick();

  const { data: alerts } = await db
    .from("guardian_alerts")
    .select("id")
    .eq("session_id", session.session.id)
    .eq("alert_type", "offline");

  assertEquals(alerts?.length, 1);
});

Deno.test("tick → tick_log записується", async () => {
  await callTick();

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data } = await db
    .from("guardian_tick_log")
    .select("*")
    .order("started_at", { ascending: false })
    .limit(1)
    .single();

  assertExists(data);
  assertExists(data?.finished_at);
  assert(data!.sessions_scanned >= 0);
});
