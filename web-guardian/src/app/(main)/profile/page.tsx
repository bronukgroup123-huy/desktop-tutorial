"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuthStore } from "@/store/auth-store";
import { useMe } from "@/hooks/useMe";

export default function ProfilePage() {
  const router = useRouter();
  const { user, loading: authLoading } = useAuthStore();
  const { profile, regions, loading, saving, error, update } = useMe();
  const [name, setName] = useState("");
  const [regionSlug, setRegionSlug] = useState("");
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (!authLoading && !user) router.replace("/login");
  }, [authLoading, user, router]);

  useEffect(() => {
    if (profile) {
      setName(profile.name ?? "");
      setRegionSlug(profile.home_region?.slug ?? "");
    }
  }, [profile]);

  if (authLoading || loading) {
    return (
      <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-cream-200 border-t-forest" />
        <p className="mt-3 text-sm text-ink-muted">Завантаження…</p>
      </div>
    );
  }
  if (!user) return null;

  const onSave = async () => {
    setSaved(false);
    const patch: { name?: string; home_region_slug?: string } = {};
    if (name !== (profile?.name ?? "")) patch.name = name;
    if (regionSlug && regionSlug !== profile?.home_region?.slug) {
      patch.home_region_slug = regionSlug;
    }
    if (Object.keys(patch).length === 0) return;
    try {
      await update(patch);
      setSaved(true);
    } catch {
      // error відображено через useMe
    }
  };

  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 overflow-y-auto p-4 pb-[calc(var(--nav-h)+1rem)]">
      <header className="mb-6">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">Профіль</h1>
        <p className="text-ink-muted text-sm mt-1">{user.email}</p>
      </header>

      <section className="rounded-2xl bg-white p-5 shadow-soft border border-cream-300 mb-6">
        <label className="mb-1 block text-sm font-medium text-forest-dark">Ім'я</label>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={50}
          className="w-full rounded-xl border border-cream-300 bg-cream-50 px-3 py-2.5 text-base text-ink outline-none focus:border-forest"
        />

        <label className="mb-1 mt-4 block text-sm font-medium text-forest-dark">Домашній регіон</label>
        <select
          value={regionSlug}
          onChange={(e) => setRegionSlug(e.target.value)}
          className="w-full rounded-xl border border-cream-300 bg-cream-50 px-3 py-2.5 text-base text-ink outline-none focus:border-forest"
        >
          <option value="">— не обрано —</option>
          {regions.map((r) => (
            <option key={r.slug} value={r.slug}>
              {r.name}
            </option>
          ))}
        </select>

        <button
          onClick={onSave}
          disabled={saving}
          className="mt-5 w-full rounded-xl bg-forest-dark py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60"
        >
          {saving ? "Зберігаємо…" : "Зберегти"}
        </button>

        {saved && <p className="mt-3 text-sm text-forest">✓ Збережено</p>}
        {error && <p className="mt-3 text-sm text-sos">Помилка: {error}</p>}
      </section>

      <section className="rounded-2xl bg-white p-5 shadow-soft border border-cream-300">
        <h2 className="font-serif text-lg font-semibold text-forest-dark mb-4">Ваша статистика</h2>
        <div className="mt-3 flex gap-6 text-sm text-ink-muted">
          <p>
            Рейтинг:{" "}
            <strong className="text-forest-dark">{profile?.rating ?? 0}</strong>
          </p>
          <p>
            Верифікованих знахідок:{" "}
            <strong className="text-forest-dark">
              {profile?.total_verified_picks ?? 0}
            </strong>
          </p>
        </div>
      </section>
    </div>
  );
}