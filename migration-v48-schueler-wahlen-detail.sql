-- ============================================================
-- KRS Projektwahl 2026 — Migration v48
-- Read-only Detail-RPC: Wünsche EINES Schülers (für Zuteilungen-View)
-- ============================================================
--
-- ZWECK
--   In der Zuteilungen-Tabelle soll die Projektleitung per Klick sehen,
--   was ein Schüler als 1./2./3. Wunsch gewählt hat — als Grundlage für
--   manuelle Umbuchungen ("bekommt er wenigstens irgendeinen Wunsch?").
--   admin_list_schueler() liefert nur hat_gewaehlt (Boolean); die
--   v47-Statistik liefert bewusst nur Aggregate. Deshalb neue RPC.
--
-- DATENSCHUTZ (DSGVO / Minderjährige)
--   Anders als v47 liefert diese Funktion personenbezogene Einzelwahlen —
--   das ist hier der legitime Zweck (Einzelfallentscheidung bei Umbuchung
--   durch Admin/Projektleitung). Minimierung:
--   - nur EIN Schüler pro Aufruf (kein Massen-Export der Wahlen),
--   - Abruf nur on-demand per Klick, kein Vorab-Laden aller Wünsche,
--   - nur für eingeloggte App-User (is_app_user-Gate), anon revoked.
--
-- SICHERHEIT
--   SECURITY DEFINER + is_app_user()-Gate (wie admin_list_schueler).
--
-- RISIKO
--   KEINS. Reine CREATE OR REPLACE FUNCTION, read-only (nur SELECT),
--   kein Schema-Eingriff, idempotent, mehrfach ausführbar.
-- ============================================================

-- ------------------------------------------------------------
-- CHECK (vorher ausführen — nur Anzeige, ändert nichts):
--   Beispiel-Schüler mit Wahlen ansehen, um das RPC-Ergebnis gegenzuprüfen.
-- ------------------------------------------------------------
-- SELECT w.schueler_code, p1.titel AS erstwahl, p2.titel AS zweitwahl, p3.titel AS drittwahl
-- FROM wahlen w
-- LEFT JOIN projekte p1 ON p1.id = w.erstwahl_id
-- LEFT JOIN projekte p2 ON p2.id = w.zweitwahl_id
-- LEFT JOIN projekte p3 ON p3.id = w.drittwahl_id
-- LIMIT 5;

-- ------------------------------------------------------------
-- RPC: admin_schueler_wahlen
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_schueler_wahlen(p_code TEXT)
RETURNS TABLE (
  wahl_nr       INT,
  projekt_id    UUID,
  projekt_titel TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT := UPPER(TRIM(COALESCE(p_code, '')));
BEGIN
  IF NOT public.is_app_user() THEN
    RAISE EXCEPTION 'nicht berechtigt';
  END IF;

  IF v_code = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT x.wahl_nr, x.projekt_id, p.titel AS projekt_titel
  FROM public.wahlen w
  CROSS JOIN LATERAL (VALUES
    (1, w.erstwahl_id),
    (2, w.zweitwahl_id),
    (3, w.drittwahl_id)
  ) AS x(wahl_nr, projekt_id)
  LEFT JOIN public.projekte p ON p.id = x.projekt_id
  WHERE w.schueler_code = v_code
    AND x.projekt_id IS NOT NULL
  ORDER BY x.wahl_nr;
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_schueler_wahlen(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_schueler_wahlen(TEXT) TO authenticated;

-- ------------------------------------------------------------
-- VERIFIKATION (nach dem Anlegen — als eingeloggter App-User):
-- ------------------------------------------------------------
-- 1) Ein Schüler-Code mit Wahlen (aus dem CHECK oben) einsetzen:
--    SELECT * FROM admin_schueler_wahlen('7B-A7K2');
--    → genau die 3 Zeilen (bzw. weniger, falls Wahl leer) in Wunsch-Reihenfolge.
-- 2) Rechte prüfen:
--    SELECT has_function_privilege('anon', 'public.admin_schueler_wahlen(text)', 'EXECUTE') AS anon_darf,  -- false!
--           has_function_privilege('authenticated', 'public.admin_schueler_wahlen(text)', 'EXECUTE') AS auth_darf;  -- true
