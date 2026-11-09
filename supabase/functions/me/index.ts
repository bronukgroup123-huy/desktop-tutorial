// Legacy /me — тільки GET (GDPR-експорт власних даних). DELETE вимкнено → 405.
// Профіль і онбординг для Flutter — v1-me. Логіка — у handler.ts (тестується окремо).
import { createMeHandler, getUserId, handleGet } from "./handler.ts";

Deno.serve(createMeHandler({ getUserId, handleGet }));
