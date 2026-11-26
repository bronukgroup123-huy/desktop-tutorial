// ============================================================================
// Edge Function: v1-me (BACKEND_PLAN B1.3, B1.6, B1.9)
// GET   /functions/v1/v1-me
// PATCH /functions/v1/v1-me   { name?, home_region_slug?, accept_terms_version? }
//
// Профіль + is_guest + onboarding.next_step + region_change.allowed (ADR-001, ADR-016).
// GET ?export=1 — усі свої дані (GDPR, B6.1); DELETE — видалити акаунт (B6.2).
// Старий `me` (лише GET-експорт) застосунок не викликає.
// ============================================================================

import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleMe } from "../_shared/v1/me.ts";

Deno.serve(handle((req) => handleMe(req, { db: serviceClient(), verify: supabaseTokenVerifier })));
