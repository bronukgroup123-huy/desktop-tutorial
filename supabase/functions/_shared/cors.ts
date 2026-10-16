// ============================================================================
// Edge Functions — CORS headers (audit G7-hardening)
// ============================================================================
// Whitelist origins (frontend + preview + dev)
const ALLOWED_ORIGINS = [
  "https://desktop-tutorial-eta-tan.vercel.app",
  "https://desktop-tutorial-m072sxnc6-bronykhub.vercel.app",
  "http://localhost:3000",
];

// Preview URLs Vercel — патерн
const ALLOWED_ORIGIN_PATTERNS = [
  /^https:\/\/desktop-tutorial-[a-z0-9]+-bronykhub\.vercel\.app$/,
];

function isOriginAllowed(origin: string): boolean {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.includes(origin)) return true;
  return ALLOWED_ORIGIN_PATTERNS.some((p) => p.test(origin));
}

export function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";

  // Серверні запити (cron, webhooks) — без Origin → віддаємо default
  const allowOrigin = isOriginAllowed(origin)
    ? origin
    : "https://desktop-tutorial-eta-tan.vercel.app";

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Vary": "Origin",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-guardian-token",
    "Access-Control-Allow-Methods": "POST, GET, PATCH, OPTIONS",
  };
}

// Legacy fallback (для файлів, які ще не мігровані — TODO V2)
// НЕ використовувати у новому коді
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-guardian-token",
  "Access-Control-Allow-Methods": "POST, GET, PATCH, OPTIONS",
};
