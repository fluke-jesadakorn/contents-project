import type { Metadata } from "next";
import "./globals.css";
import { UIProvider } from "@/components/ui";
import { AppShell } from "@/components/AppShell";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "World ERP - AI Accounting & Finance Portal",
  description: "Manage receipts, semantic category mappings, and expense approvals with AI assistance.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased bg-slate-950 text-slate-50 min-h-screen font-sans">
        <UIProvider>
          <AppShell>{children}</AppShell>
        </UIProvider>
      </body>
    </html>
  );
}