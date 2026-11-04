import "server-only";
import { z } from "zod";

// Configuration Auth. La clé de lecture métier est vérifiée uniquement à l’appel serveur.
const schema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().min(1, "NEXT_PUBLIC_SUPABASE_URL manquante"),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, "NEXT_PUBLIC_SUPABASE_ANON_KEY manquante"),
  // OBLIGATOIRE : une allowlist vide bloquerait tout le monde (fail-closed côté proxy).
  // On exige au moins une adresse pour éviter un déploiement avec un gate inopérant.
  DASHBOARD_ALLOWED_EMAILS: z
    .string()
    .min(3, "DASHBOARD_ALLOWED_EMAILS est obligatoire (au moins un email autorisé)"),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  throw new Error(
    "Configuration env invalide:\n" +
      parsed.error.issues.map((i) => `  - ${i.path.join(".")}: ${i.message}`).join("\n"),
  );
}

export const env = parsed.data;

export const allowedEmails = env.DASHBOARD_ALLOWED_EMAILS.split(",")
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);
