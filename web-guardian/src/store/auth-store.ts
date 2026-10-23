import { create } from "zustand";
import { createClient } from "@/lib/supabase/browser";
import type { User } from "@supabase/supabase-js";

interface AuthState {
  user: User | null;
  accessToken: string | null;
  loading: boolean;
  error: string | null;
  init: () => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signInWithEmail: (email: string) => Promise<void>;
  signOut: () => Promise<void>;
}

function messageOf(err: unknown): string {
  return err instanceof Error ? err.message : "Помилка авторизації";
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  accessToken: null,
  loading: true,
  error: null,

  // Не кидаємо помилку назовні: інакше unhandled rejection в useEffect
  // обриває рендер усієї сторінки (краш на мобільному).
  init: async () => {
    try {
      const supabase = createClient();
      const { data: { session } } = await supabase.auth.getSession();
      set({
        user: session?.user ?? null,
        accessToken: session?.access_token ?? null,
        loading: false,
      });
      supabase.auth.onAuthStateChange((_event, session) => {
        set({
          user: session?.user ?? null,
          accessToken: session?.access_token ?? null,
        });
      });
    } catch (err) {
      set({
        user: null,
        accessToken: null,
        loading: false,
        error: messageOf(err),
      });
    }
  },

  signInWithGoogle: async () => {
    try {
      const supabase = createClient();
      const redirectTo = `${window.location.origin}/auth/callback`;
      const { error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo },
      });
      if (error) set({ error: error.message });
    } catch (err) {
      set({ error: messageOf(err) });
    }
  },

  signInWithEmail: async (email: string) => {
    try {
      const supabase = createClient();
      const emailRedirectTo = `${window.location.origin}/auth/callback`;
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: { emailRedirectTo },
      });
      if (error) set({ error: error.message });
      else set({ error: null });
    } catch (err) {
      set({ error: messageOf(err) });
    }
  },

  signOut: async () => {
    try {
      const supabase = createClient();
      await supabase.auth.signOut();
    } catch (err) {
      set({ error: messageOf(err) });
    }
    set({ user: null, accessToken: null });
  },
}));
