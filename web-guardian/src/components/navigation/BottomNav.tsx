"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  MapPin,
  CloudSun,
  ScanLine,
  ShieldAlert,
  Users,
  UserRound,
} from "lucide-react";

const tabs = [
  { href: "/map", label: "Карта", icon: MapPin, activeIcon: MapPin },
  { href: "/forecast", label: "Прогноз", icon: CloudSun, activeIcon: CloudSun },
  { href: "/recognize", label: "Розпізнати", icon: ScanLine, activeIcon: ScanLine },
  { href: "/safety", label: "Безпека", icon: ShieldAlert, activeIcon: ShieldAlert },
  { href: "/community", label: "Спільнота", icon: Users, activeIcon: Users },
  { href: "/profile", label: "Профіль", icon: UserRound, activeIcon: UserRound },
] as const;

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-50 h-[var(--nav-h)] bg-white border-t border-cream-300"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
      aria-label="Основна навігація"
    >
      <div className="flex h-full items-stretch">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = pathname === tab.href || pathname.startsWith(tab.href + "/");

          return (
            <Link
              key={tab.href}
              href={tab.href}
              className={`flex flex-1 flex-col items-center justify-center gap-1 px-2 py-1.5 text-[10px] font-medium transition-colors ${
                isActive ? "text-amberbrand" : "text-ink-muted"
              }`}
              aria-current={isActive ? "page" : undefined}
            >
              <Icon size={20} strokeWidth={2.4} />
              <span>{tab.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}