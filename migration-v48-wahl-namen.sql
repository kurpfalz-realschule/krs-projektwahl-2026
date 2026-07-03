-- ============================================================
-- Migration v48 — admin_projekt_wahl_namen()
--   Namentliche Wunsch-Liste pro Projekt (wer hat es als 1./2./3.
--   Wunsch gewählt). Ergänzt die aggregierte v47-Statistik um die
--   Einzelnamen — für die manuelle Nachbearbeitung (z. B. passende
--   Umbuchungs-Kandidaten für ein überfülltes/unpassendes Projekt).
--
-- DATENSCHUTZ (DSGVO / Minderjährige) — WICHTIG
--   Diese Funktion gibt personenbezogene Einzelwahlen zurück (Name +
--   Klasse pro Wunsch). Sie ist deshalb serverseitig strikt auf die
--   Rollen 'projektleitung' und 'super_admin' beschränkt. Andere
--   App-User (projektlehrer, klassenlehrer) erhalten eine Exception.
--   Im Frontend liegt der Aufruf zusätzlich in der Statistik-Section,
--   die nur diese beiden Rollen sehen (ALLOWED_SECTIONS).
--
-- SICHERHEIT
--   SECURITY DEFINER + eigenes Rollen-Gate (unabhängig von is_admin()).
--
-- RISIKO
--   KEINS für die Daten. Reine CREATE OR REPLACE FUNCTION, read-only
--   (nur SELECT), kein Schema-Eingriff an Tabellen, kein INSERT/UPDATE/
--   DELETE, idempotent — mehrfach ausführbar. Verändert KEINE Zuteilungen.
-- ============================================================

-- ------------------------------------------------------------
-- CHECK (optional vorher ausführen — nur Anzeige, ändert nichts):
--   Roh-Gegenprobe für EIN Projekt (Titel anpassen).
-- ------------------------------------------------------------
-- WITH ziel AS (SELECT id FROM projekte WHERE titel ILIKE '%tanz%')
-- SELECT CASE WHEN w.erstwahl_id=z.id THEN 1 WHEN w.zweitwahl_id=z.id THEN 2 ELSE 3 END AS prio,
--        s.klasse, s.vorname, s.nachname
-- FROM ziel z JOIN wahlen w ON z.id IN (w.erstwahl_id,w.zweitwahl_id,w.drittwahl_id)
-- JOIN schueler s ON s.code=w.schueler_code WHERE s.aktiv ORDER BY prio, s.klasse, s.nachname;

-- ------------------------------------------------------------
-- RPC: admin_projekt_wahl_namen(p_projekt_id UUID DEFAULT NULL)
--   NULL = alle Projekte, sonst nur das angegebene.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_projekt_wahl_namen(p_projekt_id UUID DEFAULT NULL)
RETURNS TABLE (
  projekt_id    UUID,
  prioritaet    SMALLINT,
  schueler_code TEXT,
  vorname       TEXT,
  nachname      TEXT,
  klasse        TEXT,
  klassenstufe  INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- DSGVO-Gate: nur Projektleitung + Superadmin dürfen personenbezogene
  -- Einzelwahlen sehen. Bewusst NICHT is_app_user() (das ließe auch
  -- projektlehrer/klassenlehrer durch).
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.auth_user_id = auth.uid()
      AND u.rolle::text IN ('projektleitung', 'super_admin')
  ) THEN
    RAISE EXCEPTION 'nicht berechtigt';
  END IF;

  RETURN QUERY
  SELECT t.projekt_id, t.prio AS prioritaet,
         s.code, s.vorname, s.nachname, s.klasse, s.klassenstufe
  FROM (
    SELECT w.schueler_code, w.erstwahl_id  AS projekt_id, 1::smallint AS prio FROM public.wahlen w
    UNION ALL
    SELECT w.schueler_code, w.zweitwahl_id, 2::smallint FROM public.wahlen w
    UNION ALL
    SELECT w.schueler_code, w.drittwahl_id, 3::smallint FROM public.wahlen w
  ) t
  JOIN public.schueler s ON s.code = t.schueler_code
  WHERE s.aktiv
    AND (p_projekt_id IS NULL OR t.projekt_id = p_projekt_id)
  ORDER BY t.prio, s.klasse, s.nachname;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_projekt_wahl_namen(UUID) TO authenticated;

-- ------------------------------------------------------------
-- UNDO (falls je nötig — entfernt nur die Funktion, keine Daten):
--   DROP FUNCTION IF EXISTS public.admin_projekt_wahl_namen(UUID);
-- ------------------------------------------------------------
