"use client";

import { useEffect, useState } from "react";
import type { CSSProperties } from "react";
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

  if (authLoading || loading) return <div style={pageStyle}>Завантаження…</div>;
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
    <div style={pageStyle}>
      <h1>Профіль</h1>
      <p style={{ color: "#666" }}>{user.email}</p>

      <label style={labelStyle}>Ім&apos;я</label>
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={inputStyle}
        maxLength={50}
      />

      <label style={labelStyle}>Домашній регіон</label>
      <select
        value={regionSlug}
        onChange={(e) => setRegionSlug(e.target.value)}
        style={inputStyle}
      >
        <option value="">— не обрано —</option>
        {regions.map((r) => (
          <option key={r.slug} value={r.slug}>
            {r.name}
          </option>
        ))}
      </select>

      <button onClick={onSave} disabled={saving} style={btnStyle}>
        {saving ? "Зберігаємо…" : "Зберегти"}
      </button>

      {saved && <p style={{ color: "green" }}>✓ Збережено</p>}
      {error && <p style={{ color: "red" }}>Помилка: {error}</p>}

      <div style={{ marginTop: 32, color: "#666" }}>
        <p>Рейтинг: {profile?.rating ?? 0}</p>
        <p>Верифікованих знахідок: {profile?.total_verified_picks ?? 0}</p>
      </div>

      <p style={{ marginTop: 32 }}>
        <a href="/">← На головну</a>
      </p>
    </div>
  );
}

const pageStyle: CSSProperties = {
  padding: 40,
  maxWidth: 480,
  margin: "0 auto",
  fontFamily: "system-ui",
};
const labelStyle: CSSProperties = {
  display: "block",
  marginTop: 16,
  marginBottom: 4,
  fontWeight: 500,
};
const inputStyle: CSSProperties = {
  display: "block",
  width: "100%",
  padding: 12,
  borderRadius: 8,
  border: "1px solid #ccc",
  fontSize: 16,
  boxSizing: "border-box",
};
const btnStyle: CSSProperties = {
  display: "block",
  width: "100%",
  padding: 12,
  marginTop: 24,
  cursor: "pointer",
  borderRadius: 8,
  border: "none",
  background: "#d97706",
  color: "#fff",
  fontSize: 16,
};
