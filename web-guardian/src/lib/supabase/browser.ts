import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase не налаштовано, якщо в оточенні немає
 * NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY.
 *
 * Такий стан можливий, коли Vercel-проєкт не має доступу до Environment
 * Variables. Замість падіння всієї сторінки клієнт має зрозуміти, що
 * авторизація недоступна, але решта застосунку (карта, прогноз, спільнота)
 * продовжує працювати.
 */
export class SupabaseNotConfiguredError extends Error {
  constructor() {
    super(
      "Авторизація недоступна: не задано NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY"
    );
    this.name = "SupabaseNotConfiguredError";
  }
}

export function isSupabaseConfigured(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  );
}

export function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    throw new SupabaseNotConfiguredError();
  }

  return createBrowserClient(url, key);
}
