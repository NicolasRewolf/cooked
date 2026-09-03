// Magic-link : charge utile passée à supabase.auth.signInWithOtp (T-13, constat g-06 — 25/07 puis 02/09/2026).
// shouldCreateUser: false = un e-mail hors allowlist ne crée jamais de compte auth.users et ne consomme
// pas le quota d'e-mails du projet ; défense en profondeur, indépendante du réglage console Supabase.

export type OtpPayload = {
  email: string;
  options: { emailRedirectTo: string; shouldCreateUser: false };
};

export function otpSignInPayload(email: string, redirectTo: string): OtpPayload {
  return {
    email: email.trim(),
    options: { emailRedirectTo: redirectTo, shouldCreateUser: false },
  };
}
