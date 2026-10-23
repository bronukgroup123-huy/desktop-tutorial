"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  CloudSun,
  Map as MapIcon,
  ScanLine,
  ShieldAlert,
  Users,
  UserRound,
  type LucideIcon,
} from "lucide-react";

interface Tab {
  href: string;
  label: string;
  icon: LucideIcon;
}

const TABS: Tab[] = [
  { href: "/forecast", label: "Прогноз", icon: CloudSun },
  { href: "/map", label: "Карта", icon: MapIcon },
  { href: "/recognize", label: "Розпізнати", icon: ScanLine },
  { href: "/safety", label: "Безпека", icon: ShieldAlert },
  { href: "/community", label: "Спільнота", icon: Users },
  { href: "/profile", label: "Профіль", icon: UserRound },
];

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Основна навігація"
      className="fixed bottom-0 left-0 right-0 z-50 border-t border-cream-300 bg-white"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
    >
      <div className="flex h-[var(--nav-h)] items-stretch">
        {TABS.map((tab) => {
          const Icon = tab.icon;
          const active = pathname === tab.href || pathname.startsWith(`${tab.href}/`);

          return (
            <Link
              key={tab.href}
              href={tab.href}
              aria-current={active ? "page" : undefined}
              className={`relative flex flex-1 flex-col items-center gap-[3px] px-1 pb-2 pt-2.5 text-[10px] font-medium transition-colors duration-200 ${
                active ? "text-amberbrand" : "text-ink-muted"
              }`}
            >
              {active && (
                <span
                  aria-hidden
                  className="absolute left-1/2 top-0 h-[3px] w-6 -translate-x-1/2 rounded-b bg-amberbrand"
                />
              )}
              <Icon
                size={20}
                strokeWidth={2.4}
                className={active ? "-translate-y-px" : undefined}
              />
              <span>{tab.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
