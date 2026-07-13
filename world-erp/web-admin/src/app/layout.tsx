import type { Metadata } from "next";
import "./globals.css";
import { UIProvider, GlobalLoading } from "@/components/ui";
import { AppShell } from "@/components/AppShell";
import { LangGate } from "@/components/lang/LangGate";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "World ERP - AI Accounting & Finance Portal",
  description: "Manage receipts, semantic category mappings, and expense approvals with AI.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="th" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: [
              "document.documentElement.classList.add('gl-loading');",
              "try { var l = localStorage.getItem('worderp.lang'); document.documentElement.lang = (l === 'de' || l === 'th') ? l : 'th'; } catch (e) {}",
            ].join(' '),
          }}
        />
      </head>
      <body className="antialiased bg-slate-950 text-slate-50 min-h-screen font-sans">
        <UIProvider>
          <AppShell>{children}</AppShell>
          <GlobalLoading />
          <LangGate />
        </UIProvider>
      </body>
    </html>
  );
}