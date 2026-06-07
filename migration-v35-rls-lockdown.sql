-- ============================================================
-- v35: RLS-Lockdown — anon-Lesezugriff auf personenbezogene Daten entfernen
-- Projekt: krs-projektwahl-2026  (Supabase: uzynvvtsyjfmtywsfxtz)
-- Erstellt: 2026-06-07
--
-- HINTERGRUND
-- Das Basis-Schema (schema-v2-fixed.sql) legt offene Policies an:
--   CREATE POLICY "open_read_schueler" ON schueler FOR SELECT TO anon, authenticated USING (true);
-- Damit kann der oeffentliche anon-Key (steht im Frontend) die KOMPLETTE
-- Schuelertabelle ueber die REST-API lesen. Gleiches gilt fuer users/zuteilungen.
-- Diese Migration schliesst das.
--
-- WICHTIG: Vor dem Anwenden in Supabase ein Backup / einen Branch anlegen.
-- Reihenfolge beachten: erst RPC anlegen, dann Policy droppen.
-- Danach die E2E-Suite (Playwright) laufen lassen und ERST DANN promoten.
-- ============================================================

-- ------------------------------------------------------------
-- TEIL 1 — SCHUELER (kritisch, 493 Minderjaehrige). Sicher anwendbar.
-- ------------------------------------------------------------

-- 1a) Admin/Staff-RPC fuer die vollstaendige Schuelerliste
--     (ersetzt das frontseitige .from('schueler').select('*'))
CREATE OR REPLACE FUNCTION public.admin_list_schueler()
RETURNS SETOF public.schueler
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_app_user() THEN
    RAISE EXCEPTION 'nicht berechtigt';
  END IF;
  RETURN QUERY SELECT * FROM public.schueler ORDER BY klasse, nachname;
END;
$$;
REVOKE ALL  ON FUNCTION public.admin_list_schueler() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_schueler() TO authenticated;

-- 1b) Offene anon-Leseregel entfernen.
--     Schueler:innen greifen weiterhin NUR ueber get_schueler_status(code) zu
--     (SECURITY DEFINER, gibt nur die eigene Zeile zurueck) — bleibt unveraendert.
DROP POLICY IF EXISTS "open_read_schueler" ON public.schueler;

-- 1c) RLS sicher aktiv
ALTER TABLE public.schueler ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- TEIL 2 — USERS & ZUTEILUNGEN
-- ERST NACH ERFOLGREICHEM E2E-TEST AKTIVIEREN (auskommentiert).
-- Begruendung: users-Schreibflows (Anlegen/Bearbeiten von Lehrkraeften)
-- und die Anzeige der Projektleitung im Schuelerblick muessen geprueft werden.
-- Die hier gewaehlten Policies sind bewusst rekursionsfrei
-- (kein Funktionsaufruf, der selbst users liest, in einer Policy ON users).
-- ------------------------------------------------------------

-- -- USERS: anon raus, eingeloggtes Personal darf die Liste sehen
-- DROP POLICY IF EXISTS "open_read_users" ON public.users;
-- CREATE POLICY "users_authenticated_read" ON public.users
--   FOR SELECT TO authenticated USING (true);
-- ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
-- -- Hinweis: Schreib-Policies (insert/update/delete) bestehender Migrationen
-- -- nicht entfernen. Falls Admin-User-Verwaltung danach scheitert, fehlt eine
-- -- Schreib-Policy fuer Leitung/super_admin -> gezielt ergaenzen.

-- -- ZUTEILUNGEN: anon raus (Schueler bekommen ihre Zuteilung via get_schueler_status)
-- DROP POLICY IF EXISTS "open_read_zuteilungen" ON public.zuteilungen;
-- CREATE POLICY "zuteilungen_authenticated_read" ON public.zuteilungen
--   FOR SELECT TO authenticated USING (true);
-- ALTER TABLE public.zuteilungen ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- PROJEKTE bleiben oeffentlich lesbar (kein Klartextname, nur lehrer_id-UUID),
-- damit Schueler:innen die Projektliste sehen koennen.
-- VORHER PRUEFEN: Falls der Schuelerblick Lehrernamen direkt aus users laedt,
-- muss die Namensanzeige ueber eine View/RPC laufen, bevor Teil 2 aktiviert wird.
-- ------------------------------------------------------------

-- ============================================================
-- VERIFIKATION (nach dem Anwenden, ohne Login):
--   curl "https://uzynvvtsyjfmtywsfxtz.supabase.co/rest/v1/schueler?select=*" \
--        -H "apikey: <ANON_KEY>"
--   -> muss [] (leer) zurueckgeben.
-- ============================================================
