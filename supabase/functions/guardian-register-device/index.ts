import {
  requireMushroomPicker,
  parseBody,
  successResponse,
  withErrorHandling,
  Errors,
} from "../_shared/guardian/index.ts";
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

const Schema = z.object({
  fcm_token: z.string().min(20).max(500),
  platform: z.enum(["android", "ios", "web"]),
  device_info: z.record(z.unknown()).optional(),
});

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const input = await parseBody(req, Schema);

  const { error } = await db
    .from("user_push_tokens")
    .upsert(
      {
        user_id: userId,
        fcm_token: input.fcm_token,
        platform: input.platform,
        device_info: input.device_info ?? {},
        last_seen_at: new Date().toISOString(),
        revoked_at: null,
      },
      { onConflict: "fcm_token" }
    );

  if (error) throw Errors.internal(error.message);

  return successResponse({ registered: true });
}));
