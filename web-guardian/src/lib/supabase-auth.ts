import { createClient, SupabaseClient } from "@supabase/supabase-js";

// ============================================================================
// Auth-only Supabase client (persistSession: true)
// ============================================================================
// Використовується ВИКЛЮЧНО для auth-flow (auth-store.ts, /auth/callback):
// Google OAuth, Email Magic Link, збереження JWT у localStorage.
//
// НЕ використовувати для realtime-підписок Guardian-контуру — для цього є
// анонімний singleton getSupabaseBrowser() (supabase-browser.ts) без
// persistSession, щоб JWT не потрапляв у заголовки Guardian-realtime.
// ============================================================================

let authClient: SupabaseClient | null = null;

export function getSupabaseAuth(): SupabaseClient {
  if (authClient) return authClient;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    throw new Error("Supabase auth env missing");
  }

  authClient = createClient(url, key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });

  return authClient;
}
