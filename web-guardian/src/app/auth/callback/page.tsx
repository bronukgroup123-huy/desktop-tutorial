"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseAuth } from "@/lib/supabase-auth";

export default function AuthCallbackPage() {
  const router = useRouter();

  useEffect(() => {
    (async () => {
      const supabase = getSupabaseAuth();
      const { error } = await supabase.auth.getSession();
      router.replace(
        error ? `/login?error=${encodeURIComponent(error.message)}` : "/login"
      );
    })();
  }, [router]);

  return (
    <div style={{ padding: 40, textAlign: "center" }}>Завершуємо вхід…</div>
  );
}
