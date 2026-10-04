import {
  requireGuardian,
  parseBody,
  successResponse,
  withErrorHandling,
  Errors,
} from "../_shared/guardian/index.ts";
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

const Schema = z.object({
  fcm_token: z.string().min(20).max(500),
  user_agent: z.string().max(500).optional(),
});

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { guardian, db } = await requireGuardian(req);
  const input = await parseBody(req, Schema);

  const { error } = await db
    .from("guardian_push_tokens")
    .upsert(
      {
        guardian_id: guardian.id,
        fcm_token: input.fcm_token,
        user_agent: input.user_agent ?? req.headers.get("user-agent") ?? null,
        last_seen_at: new Date().toISOString(),
        revoked_at: null,
      },
      { onConflict: "fcm_token" }
    );

  if (error) throw Errors.internal(error.message);

  return successResponse({ registered: true });
}));
