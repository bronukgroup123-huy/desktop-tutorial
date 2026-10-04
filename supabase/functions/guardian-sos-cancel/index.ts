import {
  requireMushroomPicker,
  successResponse,
  withErrorHandling,
  Errors,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";
import { cancelSos } from "../_shared/guardian/sos.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  const result = await cancelSos(db, session);

  return successResponse({
    session_id: result.session.id,
    status: result.session.status,
    alert_id: result.alert_id,
  });
}));
