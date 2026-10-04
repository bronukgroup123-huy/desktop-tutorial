import {
  requireMushroomPicker,
  successResponse,
  withErrorHandling,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "GET") throw new Error("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);

  if (!session) {
    return successResponse({ session: null, guardians: [] });
  }

  const { data: guardians } = await db
    .from("guardians")
    .select("id, name, is_emergency, last_seen_at, revoked_at")
    .eq("session_id", session.id)
    .is("revoked_at", null)
    .order("created_at", { ascending: true });

  return successResponse({ session, guardians: guardians ?? [] });
}));
