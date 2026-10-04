import {
  requireMushroomPicker,
  parseBody,
  successResponse,
  withErrorHandling,
  Errors,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";
import { createRescueRequest } from "../_shared/guardian/rescue.ts";
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

const Schema = z.object({
  target: z.enum(["101", "police", "family", "other"]).default("101"),
  notes: z.string().max(500).optional(),
});

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  const input = await parseBody(req, Schema);

  const result = await createRescueRequest(
    db,
    session,
    userId,
    input.target,
    input.notes
  );

  return successResponse(result, 201);
}));
