import { BottomNav } from "@/components/navigation/BottomNav";

export default function MainLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col h-[var(--app-vh)] w-full bg-cream-50 overflow-hidden">
      <main className="flex-1 relative overflow-y-auto min-h-0">
        {children}
      </main>
      <BottomNav />
    </div>
  );
}