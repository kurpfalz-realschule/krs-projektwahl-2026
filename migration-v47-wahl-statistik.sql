-- ============================================================
-- KRS Projektwahl 2026 — Migration v47
-- Read-only Aggregat-RPC für die Wahl-Statistik
-- ============================================================
--
-- ZWECK
--   Die Admin-/Projektleitungs-Statistik soll zeigen, *wie oft jedes
--   Projekt gewählt* wurde (Erst-/Zweit-/Drittwahl), auch VOR der Verlosung.
--   admin_list_schueler() liefert nur `hat_gewaehlt` (Boolean), nicht die
--   einzelnen Wahlen — deshalb war diese Auswertung im Dashboard bisher
--   nur als Belegung (nach Zuteilung) sichtbar.
--
-- DATENSCHUTZ (DSGVO / Minderjährige)
--   Diese Funktion gibt NUR aggregierte Zahlen pro Projekt zurück — keine
--   Schüler-Codes, keine personenbezogenen Wahl-Datensätze. Damit ist die
--   Beliebtheits-Auswertung möglich, ohne individuelle Wahlen ans Frontend
--   zu geben.
--
-- SICHERHEIT
--   SECURITY DEFINER + is_app_user()-Gate (wie admin_list_schueler).
--   Nur eingeloggte App-User (authenticated) dürfen ausführen.
--
-- RISIKO
--   KEINS. Reine CREATE OR REPLACE FUNCTION, read-only (nur SELECT),
--   kein Schema-Eingriff, kein INSERT/UPDATE/DELETE, idempotent.
--   Mehrfach ausführbar.
-- ============================================================

-- ------------------------------------------------------------
-- CHECK (vorher ausführen — nur Anzeige, ändert nichts):
--   Zeigt die Wahl-Verteilung roh, damit man das RPC-Ergebnis gegenprüfen kann.
-- ------------------------------------------------------------
-- SELECT
--   p.id, p.titel,
--   (SELECT count(*) FROM wahlen w WHERE w.erstwahl_id  = p.id) AS erstwahl,
--   (SELECT count(*) FROM wahlen w WHERE w.zweitwahl_id = p.id) AS zweitwahl,
--   (SELECT count(*) FROM wahlen w WHERE w.drittwahl_id = p.id) AS drittwahl
-- FROM projekte p
-- ORDER BY erstwahl DESC;

-- ------------------------------------------------------------
-- RPC: admin_projekt_wahl_statistik
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_projekt_wahl_statistik()
RETURNS TABLE (
  projekt_id  UUID,
  erstwahl    BIGINT,
  zweitwahl   BIGINT,
  drittwahl   BIGINT,
  gesamt      BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_app_user() THEN
    RAISE EXCEPTION 'nicht berechtigt';
  END IF;

  -- Skalar-Subqueries pro Projekt: keine Mehrfach-Joins auf wahlen
  -- (drei LEFT JOINs würden ein kartesisches Produkt erzeugen und überzählen).
  RETURN QUERY
  SELECT
    p.id AS projekt_id,
    (SELECT COUNT(*) FROM public.wahlen w WHERE w.erstwahl_id  = p.id) AS erstwahl,
    (SELECT COUNT(*) FROM public.wahlen w WHERE w.zweitwahl_id = p.id) AS zweitwahl,
    (SELECT COUNT(*) FROM public.wahlen w WHERE w.drittwahl_id = p.id) AS drittwahl,
    (  (SELECT COUNT(*) FROM public.wahlen w WHERE w.erstwahl_id  = p.id)
     + (SELECT COUNT(*) FROM public.wahlen w WHERE w.zweitwahl_id = p.id)
     + (SELECT COUNT(*) FROM public.wahlen w WHERE w.drittwahl_id = p.id) ) AS gesamt
  FROM public.projekte p;
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_projekt_wahl_statistik() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_projekt_wahl_statistik() TO authenticated;

-- ------------------------------------------------------------
-- VERIFIKATION (nach dem Anlegen — als eingeloggter App-User):
--   SELECT * FROM admin_projekt_wahl_statistik() ORDER BY erstwahl DESC;
-- ------------------------------------------------------------
