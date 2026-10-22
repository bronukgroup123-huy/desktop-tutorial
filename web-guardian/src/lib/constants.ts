export const GUARDIAN_BASE_URL =
  process.env.NEXT_PUBLIC_GUARDIAN_BASE_URL ?? "https://guardian.mushroomradar.com.ua";

// Базовий URL Edge Functions. Значення з env має пріоритет; fallback —
// публічний anon-рівень Supabase Functions URL (не секрет).
export const FUNCTIONS_URL =
  process.env.NEXT_PUBLIC_FUNCTIONS_URL ||
  "https://wrukmuxdbkbmkygfasai.supabase.co/functions/v1";
