"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/supabase-browser";

export default function AuthCallbackPage() {
  const router = useRouter();

  useEffect(() => {
    (async () => {
      const supabase = getSupabaseBrowser();
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
