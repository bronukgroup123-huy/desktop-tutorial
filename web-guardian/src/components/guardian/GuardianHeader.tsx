"use client";

import { useGuardianStore } from "@/store/guardian-store";
import { StatusBadge } from "./StatusBadge";
import { formatRelativeSeconds } from "@/lib/format";
import { useEffect, useState } from "react";

export function GuardianHeader() {
  const session = useGuardianStore((s) => s.session);
  const derived = useGuardianStore((s) => s.derived);
  const [seconds, setSeconds] = useState(derived?.seconds_since_last_known ?? 0);

  useEffect(() => {
    if (!derived?.seconds_since_last_known) return;
    setSeconds(derived.seconds_since_last_known);

    const interval = setInterval(() => {
      setSeconds((s) => s + 1);
    }, 1000);

    return () => clearInterval(interval);
  }, [derived?.seconds_since_last_known]);

  if (!session) return null;

  return (
    <header className="sticky top-0 z-20 bg-white border-b border-gray-200 px-4 py-3">
      <div className="flex items-center justify-between">
        <div className="flex-1 min-w-0">
          <StatusBadge status={session.status} />
          <p className="mt-1 text-xs text-gray-500">
            {seconds !== null
              ? `Останній сигнал: ${formatRelativeSeconds(seconds)}`
              : "Очікуємо перший сигнал"}
          </p>
        </div>
      </div>
    </header>
  );
}
