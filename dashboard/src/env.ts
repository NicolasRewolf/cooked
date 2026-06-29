import "server-only";
import { z } from "zod";

// Validation fail-fast des variables serveur. La clé service ne doit JAMAIS
// porter le préfixe NEXT_PUBLIC_ (sinon Next l'inlinerait dans le bundle navigateur).
const schema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().min(1, "NEXT_PUBLIC_SUPABASE_URL manquante"),
  SUPABASE_SECRET_KEY: z
    .string()
    .regex(/^sb_secret_/, "SUPABASE_SECRET_KEY doit commencer par sb_secret_ (clé service)"),
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
