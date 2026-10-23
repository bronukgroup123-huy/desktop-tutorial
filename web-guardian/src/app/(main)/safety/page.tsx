import { SafetyContent } from "./SafetyContent";

export default async function SafetyPage({
  searchParams,
}: {
  searchParams: Promise<{ destLat?: string; destLng?: string }>;
}) {
  const { destLat, destLng } = await searchParams;
  return <SafetyContent destLat={destLat ?? null} destLng={destLng ?? null} />;
}