// WEB-001: вебклієнта немає — жоден сайт (зокрема колишній на Vercel) не отримує CORS-доступу;
// мобільний застосунок Origin не надсилає і CORS не потребує.
import { assertEquals } from "jsr:@std/assert";
import { buildCorsHeaders } from "../functions/_shared/cors.ts";

Deno.test("CORS: без Origin і з будь-якого сайту — без Access-Control-Allow-Origin", () => {
  for (const origin of [null, "https://desktop-tutorial-eta-tan.vercel.app", "http://localhost:3000", "https://evil.example"]) {
    const headers = buildCorsHeaders(new Request("http://localhost/v1-me", origin ? { headers: { origin } } : {}));
    assertEquals(headers["Access-Control-Allow-Origin"], undefined, String(origin));
    assertEquals(headers["Vary"], "Origin");
  }
});
