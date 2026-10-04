import { assertEquals, assert, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://localhost:54321";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;

async function createTestUser(): Promise<{ userId: string; token: string }> {
  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const email = `sos-${crypto.randomUUID()}@example.com`;
  const { data, error } = await db.auth.admin.createUser({
    email, password: "test-password-123", email_confirm: true,
  });
  if (error || !data.user) throw new Error(error?.message);

  const { data: session } = await db.auth.signInWithPassword({
    email, password: "test-password-123",
  });
  return { userId: data.user.id, token: session!.session!.access_token };
}

async function createSession(token: string) {
  const res = await fetch(`${FUNCTIONS_URL}/guardian-session-create`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      expected_return: new Date(Date.now() + 3600_000).toISOString(),
      guardians: [
        { name: "Мама", phone: "+380501234567" },
        { name: "101", phone: "+380501119991", is_emergency: true },
      ],
    }),
  });
  return (await res.json()).data;
}

async function callFn(path: string, init: RequestInit = {}) {
  return fetch(`${FUNCTIONS_URL}${path}`, init);
}

Deno.test("SOS → переводить сесію в статус sos", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  const res = await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  assertEquals(res.status, 200);

  const body = await res.json();
  assertEquals(body.data.status, "sos");
  assertEquals(body.data.previous_status, "pending");
  assertExists(body.data.sos_activated_at);
  assertExists(body.data.alert_id);
});

Deno.test("SOS → створює alert типу sos", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: alerts } = await db
    .from("guardian_alerts")
    .select("alert_type")
    .eq("session_id", session.session.id)
    .eq("alert_type", "sos");

  assertEquals(alerts?.length, 1);
});

Deno.test("SOS → ідемпотентно (повторний виклик не дублює alert)", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: alerts } = await db
    .from("guardian_alerts")
    .select("id")
    .eq("session_id", session.session.id)
    .eq("alert_type", "sos");

  assertEquals(alerts?.length, 1);
});

Deno.test("cancel SOS → повертає сесію в active", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  await callFn("/guardian-ping", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ lat: 50.45, lng: 30.52 }),
  });

  await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

  const res = await callFn("/guardian-sos-cancel", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.status, "active");
});

Deno.test("cancel SOS → створює alert recovered", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  await callFn("/guardian-sos-cancel", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: alerts } = await db
    .from("guardian_alerts")
    .select("alert_type, payload")
    .eq("session_id", session.session.id)
    .eq("alert_type", "recovered");

  assertEquals(alerts?.length, 1);
  assertEquals((alerts![0].payload as any).action, "sos_cancelled");
});

Deno.test("GPX для Наглядача → повертає XML", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  await callFn("/guardian-ping", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ lat: 50.45, lng: 30.52, speed_kmh: 3.5 }),
  });
  await callFn("/guardian-ping", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ lat: 50.451, lng: 30.521, speed_kmh: 2.1 }),
  });

  const guardianToken = session.guardians[0].token;
  const res = await callFn(`/guardian-session-gpx/${guardianToken}`);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type")?.includes("gpx"), true);

  const xml = await res.text();
  assert(xml.includes("<gpx"));
  assertEquals((xml.match(/<trkpt/g) ?? []).length, 2);
});

Deno.test("rescue-request → повертає URL і токен", async () => {
  const { token } = await createTestUser();
  await createSession(token);

  const res = await callFn("/guardian-rescue-request", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ target: "101", notes: "Загубився" }),
  });
  assertEquals(res.status, 201);
  const body = await res.json();
  assertExists(body.data.token);
  assertExists(body.data.url);
  assert(body.data.url.includes("/rescue/"));
});

Deno.test("rescue-request → заборона дублювання", async () => {
  const { token } = await createTestUser();
  await createSession(token);

  await callFn("/guardian-rescue-request", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ target: "101" }),
  });

  const res = await callFn("/guardian-rescue-request", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ target: "101" }),
  });

  assertEquals(res.status, 409);
});

Deno.test("rescue-get → публічний доступ за токеном", async () => {
  const { token } = await createTestUser();
  await createSession(token);

  const createRes = await callFn("/guardian-rescue-request", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ target: "101", notes: "Test" }),
  });
  const { data } = await createRes.json();

  const res = await callFn(`/guardian-rescue-get/${data.token}`);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.target, "101");
  assertEquals(body.data.notes, "Test");
  assertExists(body.data.picker.name);
});

Deno.test("rescue-get /gpx → повертає GPX", async () => {
  const { token } = await createTestUser();
  await createSession(token);

  const createRes = await callFn("/guardian-rescue-request", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ target: "101" }),
  });
  const { data } = await createRes.json();

  const res = await callFn(`/guardian-rescue-get/${data.token}/gpx`);
  assertEquals(res.status, 200);
  const xml = await res.text();
  assert(xml.includes("<gpx"));
  assert(xml.includes('creator="MushroomRadar"'));
});

Deno.test("dispatcher → екстрений контакт НЕ отримує offline alert", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data: alert } = await db
    .from("guardian_alerts")
    .insert({
      session_id: session.session.id,
      alert_type: "offline",
      payload: { level: "stale" },
    })
    .select("id")
    .single();

  await callFn("/guardian-notify", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify({ alert_id: alert.id }),
  });

  const { data: notifs } = await db
    .from("guardian_notifications")
    .select(`
      guardian_id,
      guardian:guardians!inner(name, is_emergency)
    `)
    .eq("alert_id", alert.id);

  assert(notifs && notifs.length > 0);
  for (const n of notifs!) {
    assertEquals((n.guardian as any).is_emergency, false);
  }
});

Deno.test("dispatcher → екстрений контакт ОТРИМУЄ sos alert", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  await callFn("/guardian-sos", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data: alert } = await db
    .from("guardian_alerts")
    .select("id")
    .eq("session_id", session.session.id)
    .eq("alert_type", "sos")
    .single();

  await callFn("/guardian-notify", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify({ alert_id: alert!.id }),
  });

  const { data: notifs } = await db
    .from("guardian_notifications")
    .select(`
      guardian_id,
      guardian:guardians!inner(name, is_emergency)
    `)
    .eq("alert_id", alert!.id);

  const emergencies = notifs!.filter((n) => (n.guardian as any).is_emergency);
  assertEquals(emergencies.length, 1);
});
