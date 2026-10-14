import { create } from "zustand";
import { getSupabaseBrowser } from "@/lib/supabase-browser";
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

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  accessToken: null,
  loading: true,
  error: null,

  init: async () => {
    const supabase = getSupabaseBrowser();
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
  },

  signInWithGoogle: async () => {
    const supabase = getSupabaseBrowser();
    const redirectTo = `${window.location.origin}/auth/callback`;
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo },
    });
    if (error) set({ error: error.message });
  },

  signInWithEmail: async (email: string) => {
    const supabase = getSupabaseBrowser();
    const emailRedirectTo = `${window.location.origin}/auth/callback`;
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo },
    });
    if (error) set({ error: error.message });
    else set({ error: null });
  },

  signOut: async () => {
    const supabase = getSupabaseBrowser();
    await supabase.auth.signOut();
    set({ user: null, accessToken: null });
  },
}));
