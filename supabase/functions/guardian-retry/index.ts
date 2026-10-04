import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse } from "../_shared/guardian/errors.ts";
import { processQueue } from "../_shared/guardian/notifications/queue.ts";

Deno.serve(withErrorHandling(async (_req) => {
  const db = createServiceClient();
  const stats = await processQueue(db);
  return successResponse(stats);
}));
