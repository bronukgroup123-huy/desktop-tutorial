// ============================================================================
// Edge Function: v1-quiz — тести знань (ADR-023; BACKEND_PLAN B3.10)
// GET / POST /functions/v1/v1-quiz — логіка в `_shared/v1/quiz.ts`.
// ============================================================================

import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleQuiz } from "../_shared/v1/quiz.ts";

Deno.serve(handle((req) => handleQuiz(req, { db: serviceClient(), verify: supabaseTokenVerifier })));
