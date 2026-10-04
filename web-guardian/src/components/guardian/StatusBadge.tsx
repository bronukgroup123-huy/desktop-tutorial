"use client";

import { getStatusStyle } from "@/lib/format";
import type { SessionStatus } from "@/lib/types";
import { clsx } from "clsx";

export function StatusBadge({ status }: { status: SessionStatus }) {
  const style = getStatusStyle(status);

  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium",
        style.bgColor,
        style.color,
        style.isUrgent && "animate-pulse"
      )}
    >
      <span aria-hidden>{style.emoji}</span>
      {style.label}
    </span>
  );
}
