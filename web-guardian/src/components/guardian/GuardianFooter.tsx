"use client";

import { useGuardianStore } from "@/store/guardian-store";
import {
  formatBattery,
  formatDuration,
  formatSignal,
  getBatteryColor,
} from "@/lib/format";

export function GuardianFooter() {
  const session = useGuardianStore((s) => s.session);
  const derived = useGuardianStore((s) => s.derived);

  if (!session || !derived) return null;

  return (
    <div className="grid grid-cols-3 gap-2 bg-white border-t border-gray-200 px-4 py-3 text-sm">
      <div>
        <p className="text-xs text-gray-500">Повернення</p>
        <p className="font-medium">{formatDuration(derived.minutes_to_return)}</p>
      </div>
      <div>
        <p className="text-xs text-gray-500">Батарея</p>
        <p className={`font-medium ${getBatteryColor(session.last_battery_pct)}`}>
          {formatBattery(session.last_battery_pct)}
        </p>
      </div>
      <div>
        <p className="text-xs text-gray-500">Сигнал</p>
        <p className="font-medium">{formatSignal(session.last_signal_strength)}</p>
      </div>
    </div>
  );
}
