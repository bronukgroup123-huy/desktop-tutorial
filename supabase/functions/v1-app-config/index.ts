// ============================================================================
// Edge Function: v1-app-config (BACKEND_PLAN B4.3, B4.10)
// GET /functions/v1/v1-app-config
//
// Тексти вкладки «Безпека» (банер ДСНС, «Заблукали?», «Отруєння», «Інші небезпеки», чек-лист,
// поради на час повітряної тривоги) — змінюються без релізу застосунку. Публічний.
// ============================================================================

import { handle, serviceClient } from "../_shared/http.ts";
import { handleAppConfig } from "../_shared/v1/app-config.ts";

// deno-lint-ignore no-explicit-any
Deno.serve(handle((req) => handleAppConfig(req, { db: serviceClient() as any })));
