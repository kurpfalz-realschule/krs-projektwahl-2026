// =====================================================================
// KRS Projektwahl 2026 — Supabase Configuration
// =====================================================================
// Wird von admin-dashboard-v2.html und schueler-frontend-v3.html geladen.
// Öffentlicher Schlüssel — darf im Frontend liegen (ist für den Browser gedacht).
// Schutz passiert über Row Level Security (RLS) in der Datenbank.
// =====================================================================

window.KRS_SUPABASE = {
  url: 'https://uzynvvtsyjfmtywsfxtz.supabase.co',
  publishableKey: 'sb_publishable_kdZSmagc_sbq9qwynebcxw_hKdhyDt1',
  // Hinweis: Der alte "anon key" heißt im neuen Supabase-Keystore "publishable key".
  // Funktional identisch — gleiche Rolle, gleicher Einsatzzweck.
};
