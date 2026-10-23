import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AuthInit } from "@/components/auth/AuthInit";

export const metadata: Metadata = {
  title: "Mushroom Radar",
  description:
    "Грибний Радар — прогноз плодоношення грибів, карта лісів і безпека в поході",
  manifest: "/manifest.json",
  // Запобігає витоку токена з URL (/s/<token>) через Referer header
  // до сторонніх CDN (maptiler, Google Fonts, analytics).
  referrer: "no-referrer",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Mushroom Radar",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  // viewport-fit=cover потрібен для safe-area-inset на iPhone (нижня навігація).
  viewportFit: "cover",
  themeColor: "#2F4A3A",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="uk">
      <head>
        <link rel="apple-touch-icon" href="/icons/icon-192.png" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,500;0,9..144,600;0,9..144,700;1,9..144,500;1,9..144,600;1,9..144,700&family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="antialiased bg-cream-50 text-ink">
        <AuthInit />
        {children}
      </body>
    </html>
  );
}
