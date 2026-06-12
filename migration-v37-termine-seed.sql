-- ============================================================
-- Migration v37: Termin-Keys in system_settings seeden
-- ============================================================
-- Hintergrund: Die Einstellungen-View im Admin war bisher eine
-- Attrappe. Ab v37 werden 4 Termin-Keys aus system_settings
-- geladen/gespeichert und im Schüler-Frontend angezeigt.
-- Die Termine sind reine Anzeige-/Hinweis-Werte — die Phase
-- bleibt der manuelle Master-Schalter.
--
-- Werte sind JSONB-Strings im ISO-Format:
--   anmelde_deadline    "2026-07-10T23:59"
--   tausch_deadline     "2026-07-17T23:59"
--   projekttage_beginn  "2026-07-21"
--   projekttage_ende    "2026-07-23"
--
-- Ausführen mit:
--   ~/.local/bin/supabase db query --linked --file migration-v37-termine-seed.sql
-- ============================================================

-- 1. Seed — bestehende Werte werden NICHT überschrieben
INSERT INTO public.system_settings (key, value)
VALUES
  ('anmelde_deadline',   to_jsonb('2026-07-10T23:59'::text)),
  ('tausch_deadline',    to_jsonb('2026-07-17T23:59'::text)),
  ('projekttage_beginn', to_jsonb('2026-07-21'::text)),
  ('projekttage_ende',   to_jsonb('2026-07-23'::text))
ON CONFLICT (key) DO NOTHING;

-- Kontrolle 1: Alle Termin-Keys + phase anzeigen
SELECT key, value
FROM public.system_settings
WHERE key IN ('phase', 'anmelde_deadline', 'tausch_deadline',
              'projekttage_beginn', 'projekttage_ende')
ORDER BY key;

-- Kontrolle 2: RLS-Policies auf system_settings anzeigen
-- (Lesen muss für anon möglich sein — Schüler-App liest phase + Termine;
--  Schreiben nur für eingeloggte Admins, wie bisher bei phase)
SELECT polname, polcmd, pg_get_expr(polqual, polrelid) AS using_expr
FROM pg_policy
WHERE polrelid = 'public.system_settings'::regclass;
