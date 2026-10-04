"use client";

import { useEffect, useState } from "react";
import { fetchGuardianSession, GuardianApiError } from "@/lib/api";
import { getSupabaseBrowser } from "@/lib/supabase-browser";
import { useGuardianStore } from "@/store/guardian-store";
import { useVisibility } from "./useVisibility";

export function useGuardianSession(token: string) {
  const { setSession, setLoading, setError, reset } = useGuardianStore();
  const [notFound, setNotFound] = useState(false);
  const [unauthorized, setUnauthorized] = useState(false);
  const isVisible = useVisibility();

  useEffect(() => {
    if (!token) return;

    let cancelled = false;
    setLoading(true);

    fetchGuardianSession(token)
      .then((data) => {
        if (cancelled) return;
        setSession(data);
      })
      .catch((err) => {
        if (cancelled) return;
        if (err instanceof GuardianApiError) {
          if (err.isNotFound) setNotFound(true);
          else if (err.isExpiredToken) setUnauthorized(true);
          setError(err.message);
        } else {
          setError(err instanceof Error ? err.message : "Помилка завантаження");
        }
      });

    return () => {
      cancelled = true;
    };
  }, [token, setLoading, setSession, setError]);

  useEffect(() => {
    if (!token || !isVisible) return;

    const supabase = getSupabaseBrowser();
    const channel = supabase
      .channel(`guardian-session-${token}`)
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "guardian_sessions",
        },
        async () => {
          try {
            const data = await fetchGuardianSession(token);
            setSession(data);
          } catch {
            // ignore
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [token, isVisible, setSession]);

  useEffect(() => {
    if (!token || !isVisible) return;

    const interval = setInterval(async () => {
      try {
        const data = await fetchGuardianSession(token);
        setSession(data);
      } catch {
        // ignore
      }
    }, 30_000);

    return () => clearInterval(interval);
  }, [token, isVisible, setSession]);

  useEffect(() => {
    return () => reset();
  }, [reset]);

  return { notFound, unauthorized };
}
