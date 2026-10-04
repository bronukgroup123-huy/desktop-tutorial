import {
  requireMushroomPicker,
  successResponse,
  withErrorHandling,
  Errors,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";
import { activateSos } from "../_shared/guardian/sos.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  const result = await activateSos(db, session);

  return successResponse({
    session_id: result.session.id,
    status: result.session.status,
    previous_status: result.previous_status,
    sos_activated_at: result.session.sos_activated_at,
    alert_id: result.alert_id,
  });
}));
