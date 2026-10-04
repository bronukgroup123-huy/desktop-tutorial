"use client";

import { useEffect, useState } from "react";

export function useVisibility(): boolean {
  const [visible, setVisible] = useState(
    typeof document !== "undefined" ? !document.hidden : true
  );

  useEffect(() => {
    const handler = () => setVisible(!document.hidden);
    document.addEventListener("visibilitychange", handler);
    return () => document.removeEventListener("visibilitychange", handler);
  }, []);

  return visible;
}
