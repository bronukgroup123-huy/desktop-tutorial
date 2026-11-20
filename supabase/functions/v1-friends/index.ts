// ============================================================================
// Edge Function: v1-friends — друзі (ADR-021 §21.1; BACKEND_PLAN B9.2)
// GET / POST / PUT /functions/v1/v1-friends — логіка в `_shared/v1/friends.ts`.
// ============================================================================

import { sendPush } from "../_shared/guardian/notifications/firebase.ts";
import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleFriends } from "../_shared/v1/friends.ts";

Deno.serve(handle((req) =>
  handleFriends(req, {
    db: serviceClient(),
    verify: supabaseTokenVerifier,
    send: async (token, msg) => {
      const r = await sendPush({ token, title: msg.title, body: msg.body, data: msg.data, priority: "normal" });
      return { ok: r.success, unregistered: /registration-token-not-registered|not.?registered|invalid-registration/i.test(r.errorMessage ?? "") };
    },
  })
));
