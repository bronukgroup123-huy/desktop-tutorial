import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse, Errors } from "../_shared/guardian/errors.ts";
import { processQueue } from "../_shared/guardian/notifications/queue.ts";
import { isServiceRoleRequest } from "../_shared/guardian/service-auth.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");
  if (!isServiceRoleRequest(req)) {
    throw Errors.unauthorized("Service-role authorization required");
  }
  const db = createServiceClient();
  const stats = await processQueue(db);
  return successResponse(stats);
}));
