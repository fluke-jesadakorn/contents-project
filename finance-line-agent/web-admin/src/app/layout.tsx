import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "FinAgent - AI Accounting & Finance Portal",
  description: "Manage receipts, semantic category mappings, and expense approvals with AI assistance.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="th">
      <body className="antialiased bg-slate-950 text-slate-50 min-h-screen font-sans">
        {children}
      </body>
    </html>
  );
}
