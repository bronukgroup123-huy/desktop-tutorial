"use client";

import { use } from "react";
import { MapView } from "@/components/map/MapView";
import { GuardianHeader } from "@/components/guardian/GuardianHeader";
import { GuardianFooter } from "@/components/guardian/GuardianFooter";
import { GuardianActions } from "@/components/guardian/GuardianActions";
import { EmergencyActions } from "@/components/guardian/EmergencyActions";
import { PushPermission } from "@/components/system/PushPermission";
import { LoadingScreen } from "@/components/system/LoadingScreen";
import { useGuardianSession } from "@/hooks/useGuardianSession";
import { useRealtimeTrack } from "@/hooks/useRealtimeTrack";
import { useGuardianStore } from "@/store/guardian-store";

export default function GuardianPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
  const { notFound, unauthorized } = useGuardianSession(token);

  const session = useGuardianStore((s) => s.session);
  const error = useGuardianStore((s) => s.error);

  useRealtimeTrack(token, session?.id ?? null);

  if (notFound) {
    return (
      <ErrorScreen
        title="Посилання недійсне"
        message="Можливо, сесія вже завершена, або посилання відкликано."
      />
    );
  }

  if (unauthorized) {
    return (
      <ErrorScreen
        title="Доступ заборонено"
        message="Це посилання вже не працює."
      />
    );
  }

  if (error && !session) {
    return <ErrorScreen title="Помилка" message={error} />;
  }

  if (!session) {
    return <LoadingScreen />;
  }

  return (
    <div className="flex flex-col h-screen">
      <GuardianHeader />

      <div className="flex-1 relative">
        <MapView token={token} />
      </div>

      <GuardianFooter />
      <GuardianActions token={token} />
      <EmergencyActions />

      <div className="absolute top-20 left-4 right-4 z-10">
        <PushPermission token={token} />
      </div>
    </div>
  );
}

function ErrorScreen({ title, message }: { title: string; message: string }) {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen px-6 text-center">
      <div className="text-6xl mb-4">⚠️</div>
      <h1 className="text-xl font-bold mb-2">{title}</h1>
      <p className="text-gray-600">{message}</p>
    </div>
  );
}
