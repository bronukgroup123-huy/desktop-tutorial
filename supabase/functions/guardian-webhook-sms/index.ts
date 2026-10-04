import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse, Errors } from "../_shared/guardian/errors.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const secret = req.headers.get("X-Webhook-Secret");
  const expected = Deno.env.get("SMS_WEBHOOK_SECRET");
  if (!expected || secret !== expected) {
    throw Errors.unauthorized("Invalid webhook secret");
  }

  const body = await req.json().catch(() => ({}));
  const messageId = body?.message_id;
  const status = body?.status;

  if (!messageId || !status) {
    throw Errors.validation("Missing message_id or status");
  }

  const db = createServiceClient();

  const updates: Record<string, unknown> = {};
  if (status === "delivered") {
    updates.status = "delivered";
    updates.delivered_at = new Date().toISOString();
  } else if (status === "failed") {
    updates.status = "failed";
    updates.error_message = body?.error ?? "Delivery failed";
  }

  const { error } = await db
    .from("guardian_notifications")
    .update(updates)
    .eq("provider_message_id", messageId);

  if (error) throw Errors.internal(error.message);

  return successResponse({ updated: true });
}));
