"use client";

import { useEffect, useState } from "react";
import type { CSSProperties } from "react";
import { useAuthStore } from "@/store/auth-store";

export default function LoginPage() {
  const { user, loading, error, init, signInWithGoogle, signInWithEmail, signOut } =
    useAuthStore();
  const [email, setEmail] = useState("");
  const [emailSent, setEmailSent] = useState(false);

  useEffect(() => {
    init();
  }, [init]);

  if (loading) return <div style={pageStyle}>Завантаження…</div>;

  if (user) {
    return (
      <div style={pageStyle}>
        <h1>Ви увійшли</h1>
        <p>{user.email}</p>
        <p style={{ fontSize: 12, color: "#666" }}>ID: {user.id}</p>
        <button onClick={signOut} style={btnStyle}>
          Вийти
        </button>
        <p style={{ marginTop: 24 }}>
          <a href="/map">← На головну</a>
        </p>
      </div>
    );
  }

  return (
    <div style={pageStyle}>
      <h1>Увійти у Грибний Радар</h1>

      <button onClick={signInWithGoogle} style={googleBtnStyle}>
        Увійти з Google
      </button>

      <div style={{ margin: "24px 0", color: "#999" }}>або</div>

      <input
        type="email"
        placeholder="email@example.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        style={inputStyle}
      />
      <button
        onClick={async () => {
          await signInWithEmail(email);
          setEmailSent(true);
        }}
        style={btnStyle}
      >
        Надіслати Magic Link
      </button>

      {emailSent && (
        <p style={{ color: "green" }}>
          Перевірте пошту — ми надіслали посилання.
        </p>
      )}
      {error && <p style={{ color: "red" }}>Помилка: {error}</p>}

      <p style={{ marginTop: 24 }}>
        <a href="/map">← На головну</a>
      </p>
    </div>
  );
}

const pageStyle: CSSProperties = {
  padding: 40,
  maxWidth: 400,
  margin: "0 auto",
  fontFamily: "system-ui",
};
const btnStyle: CSSProperties = {
  display: "block",
  width: "100%",
  padding: 12,
  marginTop: 8,
  cursor: "pointer",
  borderRadius: 8,
  border: "1px solid #ccc",
  background: "#fff",
  fontSize: 16,
};
const googleBtnStyle: CSSProperties = {
  ...btnStyle,
  background: "#4285f4",
  color: "#fff",
  border: "none",
};
const inputStyle: CSSProperties = {
  display: "block",
  width: "100%",
  padding: 12,
  marginTop: 8,
  borderRadius: 8,
  border: "1px solid #ccc",
  fontSize: 16,
  boxSizing: "border-box",
};
