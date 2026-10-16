import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse, Errors } from "../_shared/guardian/errors.ts";
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

const WebhookSmsSchema = z.object({
  message_id: z.string().min(1),
  status: z.string().min(1),
  error: z.string().optional(),
});

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const secret = req.headers.get("X-Webhook-Secret");
  const expected = Deno.env.get("SMS_WEBHOOK_SECRET");
  if (!expected || secret !== expected) {
    throw Errors.unauthorized("Invalid webhook secret");
  }

  const body = await req.json().catch(() => ({}));
  const bodyParse = WebhookSmsSchema.safeParse(body);
  if (!bodyParse.success) {
    throw Errors.validation("Validation failed", { issues: bodyParse.error.issues });
  }
  const { message_id: messageId, status } = bodyParse.data;

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
