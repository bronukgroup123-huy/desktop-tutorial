import { createClient, SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | null = null;

export function getSupabaseBrowser(): SupabaseClient {
  if (client) return client;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    throw new Error("Supabase env variables missing");
  }

  client = createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      // Унікальний storage key — щоб анонімний клієнт НІКОЛИ не бачив JWT,
      // збережений auth-клієнтом (getSupabaseAuth) у default-key storage.
      // Інакше supabase-js додає Authorization: Bearer <jwt> у realtime-
      // підписки Guardian-таблиць → 401 на /s/[token] (X-Guardian-Token flow).
      storageKey: "sb-anon-noauth-storage",
    },
    realtime: {
      params: { eventsPerSecond: 5 },
    },
  });

  return client;
}
