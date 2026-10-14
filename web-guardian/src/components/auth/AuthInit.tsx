"use client";

import { useEffect } from "react";
import { useAuthStore } from "@/store/auth-store";

export function AuthInit() {
  const init = useAuthStore((s) => s.init);

  useEffect(() => {
    init();
  }, [init]);

  return null;
}
