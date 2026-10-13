// ============================================================================
// Edge Function: catalog (group 9.3)
// GET / — довідник 326 видів грибів для Flutter.
//   204 OPTIONS | 405 non-GET | 400 invalid_* | 200 {data,total,limit,offset} | 500 db_error
// Логіка — у _shared/forecast/catalog-endpoint.ts (pure, тестована).
// service_role-клієнт обходить RLS (catalog_read — тільки authenticated).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleCatalogRequest } from "../_shared/forecast/catalog-endpoint.ts";

Deno.serve(async (req: Request) => {
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } }
  );

  return handleCatalogRequest(db, req);
});
