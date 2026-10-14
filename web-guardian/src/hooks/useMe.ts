"use client";

import { useState, useEffect, useCallback } from "react";
import {
  fetchMe,
  patchMe,
  fetchRegions,
  type MeProfile,
  type RegionItem,
} from "@/lib/api";
import { useAuthStore } from "@/store/auth-store";

export function useMe() {
  const user = useAuthStore((s) => s.user);
  const [profile, setProfile] = useState<MeProfile | null>(null);
  const [regions, setRegions] = useState<RegionItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) {
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [me, regs] = await Promise.all([fetchMe(), fetchRegions()]);
      setProfile(me);
      setRegions(regs);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Помилка завантаження");
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    load();
  }, [load]);

  const update = useCallback(
    async (input: { name?: string; home_region_slug?: string }) => {
      setSaving(true);
      setError(null);
      try {
        const updated = await patchMe(input);
        setProfile(updated);
        return updated;
      } catch (e) {
        setError(e instanceof Error ? e.message : "Помилка збереження");
        throw e;
      } finally {
        setSaving(false);
      }
    },
    []
  );

  return { profile, regions, loading, saving, error, update, reload: load };
}
