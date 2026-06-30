import type { Metadata } from "next";
import { IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";
import { Header } from "@/components/Header";

// Typo « instrument » : IBM Plex Sans pour le texte, IBM Plex Mono pour tous les
// chiffres / données (alignement tabulaire, lecture d'instrument).
const sans = IBM_Plex_Sans({
  variable: "--font-ibm-plex-sans",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});
const mono = IBM_Plex_Mono({
  variable: "--font-ibm-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  title: "Cooked — Articles ressources",
  description: "Tableau de bord SEO & comportement des articles ressources (jplouton-avocat.fr)",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr" className={`${sans.variable} ${mono.variable} h-full antialiased`}>
      <body className="min-h-full bg-paper text-ink">
        <Header />
        {children}
      </body>
    </html>
  );
}
