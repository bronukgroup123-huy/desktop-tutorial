import {
  requireMushroomPicker,
  Errors,
  successResponse,
  withErrorHandling,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const url = new URL(req.url);
  const guardianId = url.pathname.split("/").pop();
  if (!guardianId) throw Errors.validation("Missing guardian_id in path");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  const { data: guardian, error: fetchError } = await db
    .from("guardians")
    .select("id, session_id, revoked_at")
    .eq("id", guardianId)
    .eq("session_id", session.id)
    .maybeSingle();

  if (fetchError) throw Errors.internal(fetchError.message);
  if (!guardian) throw Errors.notFound("Guardian not found in this session");
  if (guardian.revoked_at) {
    return successResponse({ already_revoked: true });
  }

  const { error: updateError } = await db
    .from("guardians")
    .update({ revoked_at: new Date().toISOString() })
    .eq("id", guardianId);

  if (updateError) throw Errors.internal(updateError.message);

  return successResponse({ revoked: true, guardian_id: guardianId });
}));
