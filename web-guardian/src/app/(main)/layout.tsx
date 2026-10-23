import { BottomNav } from "@/components/navigation/BottomNav";

export default function MainLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-cream-50 text-ink">
      {children}
      <BottomNav />
    </div>
  );
}
