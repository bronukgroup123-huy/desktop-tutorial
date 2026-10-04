import { assertEquals, assert, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://localhost:54321";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;

async function createTestUser(): Promise<{ userId: string; token: string }> {
  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const email = `notif-${crypto.randomUUID()}@example.com`;
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
      guardians: [{ name: "Test", phone: "+380501234567" }],
    }),
  });
  return (await res.json()).data;
}

Deno.test("notify → обробляє alert і створює notification", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data: alert } = await db
    .from("guardian_alerts")
    .insert({
      session_id: session.session.id,
      alert_type: "overdue_soft",
      payload: { minutes_over: 5 },
    })
    .select("id")
    .single();

  const res = await fetch(`${FUNCTIONS_URL}/guardian-notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify({ alert_id: alert.id }),
  });
  assertEquals(res.status, 200);

  const { data: notifs } = await db
    .from("guardian_notifications")
    .select("id, channel, status")
    .eq("alert_id", alert.id);

  assert(notifs && notifs.length > 0);

  const { data: alertCheck } = await db
    .from("guardian_alerts")
    .select("delivered_at")
    .eq("id", alert.id)
    .single();
  assertExists(alertCheck?.delivered_at);
});

Deno.test("notify → skip якщо alert вже delivered", async () => {
  const { token } = await createTestUser();
  const session = await createSession(token);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: alert } = await db
    .from("guardian_alerts")
    .insert({
      session_id: session.session.id,
      alert_type: "offline",
      payload: {},
      delivered_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  const res = await fetch(`${FUNCTIONS_URL}/guardian-notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify({ alert_id: alert.id }),
  });
  const body = await res.json();
  assertEquals(body.data.skipped, true);
});

Deno.test("register-device → зберігає FCM токен", async () => {
  const { token } = await createTestUser();

  const res = await fetch(`${FUNCTIONS_URL}/guardian-register-device`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      fcm_token: "test-fcm-token-" + crypto.randomUUID(),
      platform: "android",
    }),
  });
  assertEquals(res.status, 200);
});
