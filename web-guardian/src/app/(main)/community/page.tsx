"use client";

import { useEffect, useState } from "react";
import { Users } from "lucide-react";
import { FUNCTIONS_URL } from "@/lib/constants";

interface PickItem {
  id: string;
  name_ua: string | null;
  mushroom_type: string;
  user_name: string | null;
  region_name: string | null;
  photo_url: string | null;
  verification_status: string;
  created_at: string;
}

export default function CommunityPage() {
  const [picks, setPicks] = useState<PickItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const res = await fetch(
          `${FUNCTIONS_URL}/picks?scope=public&period=week&limit=20`
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = await res.json();
        if (cancelled) return;
        setPicks(Array.isArray(json?.data) ? json.data : []);
      } catch (err) {
        console.error("Community feed load failed:", err);
        if (!cancelled) setFailed(true);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="mx-auto max-w-2xl px-4 pb-10 pt-6">
      <header className="mb-5">
        <h1 className="font-serif text-3xl font-semibold text-forest-dark">
          Спільнота
        </h1>
        <p className="mt-1 text-sm text-ink-muted">
          Знахідки грибників, відкриті для всіх
        </p>
      </header>

      {loading ? (
        <p className="text-sm text-ink-muted">Завантаження стрічки…</p>
      ) : failed ? (
        <div className="rounded-2xl bg-white p-5 text-sm text-ink-muted shadow-soft">
          Стрічка зараз недоступна. Спробуйте оновити сторінку.
        </div>
      ) : picks.length === 0 ? (
        <div className="rounded-2xl bg-white p-6 text-center shadow-soft">
          <Users size={26} className="mx-auto mb-3 text-forest" />
          <p className="text-sm text-ink-muted">
            Поки що немає відкритих знахідок. Станьте першим — надсилайте фото
            грибів через застосунок.
          </p>
        </div>
      ) : (
        <ul className="space-y-3">
          {picks.map((pick) => (
            <li key={pick.id} className="rounded-2xl bg-white p-4 shadow-soft">
              <div className="flex items-baseline justify-between gap-3">
                <span className="font-semibold text-forest-dark">
                  {pick.name_ua ?? pick.mushroom_type}
                </span>
                <span className="shrink-0 text-xs text-ink-muted">
                  {new Date(pick.created_at).toLocaleDateString("uk-UA")}
                </span>
              </div>
              <p className="mt-1 text-xs text-ink-muted">
                {pick.user_name ?? "Анонім"}
                {pick.region_name ? ` · ${pick.region_name}` : ""}
              </p>
              {pick.photo_url && (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={pick.photo_url}
                  alt={pick.name_ua ?? pick.mushroom_type}
                  className="mt-3 max-h-56 w-full rounded-xl object-cover"
                />
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
