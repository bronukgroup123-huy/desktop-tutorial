// ============================================================================
// Edge Functions — CORS
// ============================================================================
// Клієнт — лише мобільний застосунок (Flutter): він не надсилає Origin і CORS не потребує.
// Вебклієнта немає (web-guardian і Vercel прибрано, WEB-001), тож жодному сайту браузер не дозволить
// читати відповіді: заголовок Access-Control-Allow-Origin віддається лише origin зі списку нижче.
// З'явиться вебверсія — додайте її адресу сюди.
const ALLOWED_ORIGINS: string[] = [];

function isOriginAllowed(origin: string): boolean {
  return origin !== "" && ALLOWED_ORIGINS.includes(origin);
}

export function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  return {
    ...(isOriginAllowed(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, PUT, PATCH, DELETE, OPTIONS",
  };
}

// Legacy fallback (для файлів, які ще не мігровані — TODO V2)
// НЕ використовувати у новому коді
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, PUT, PATCH, DELETE, OPTIONS",
};
