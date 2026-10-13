// ============================================================================
// Edge Function: regions (group 9.2)
// GET / — публічний список областей для Flutter Home Region dropdown.
//   204 OPTIONS | 405 non-GET | 200 {data: [...]} | 500 db_error
// Логіка — у _shared/forecast/regions-endpoint.ts (pure, тестована).
// service_role-клієнт обходить RLS (regions_read — тільки authenticated).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleRegionsRequest } from "../_shared/forecast/regions-endpoint.ts";

Deno.serve(async (req: Request) => {
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } }
  );

  return handleRegionsRequest(db, req);
});
