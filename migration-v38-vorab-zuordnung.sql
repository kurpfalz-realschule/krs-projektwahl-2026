-- ============================================================
-- KRS Projektwahl 2026 — v38 Migration „Vorab-Zuordnung"
-- Zweck: Ganze Klassen / einzelne Schüler können VOR der Verlosung
--        fest einem Projekt zugeordnet werden (z.B. Klassenprojekte
--        7a+7d, Französisch-Gruppe). Diese Zuordnungen sind „fixiert":
--        die Verlosung überspringt die Schüler, rechnet ihre Plätze
--        an und löscht sie beim Commit NICHT.
-- Datum: 2026-06-11
--
-- WICHTIG: In Supabase SQL-Editor als Ganzes ausführen.
-- Alle Statements sind idempotent (IF NOT EXISTS / CREATE OR REPLACE
-- / DROP IF EXISTS). Kontroll-SELECTs am Ende.
--
-- Enthält:
--   1. Spalte zuteilungen.fixiert (BOOLEAN, Default FALSE) + Backfill
--   2. View zuteilungen_detail um fixiert erweitert
--   3. admin_list_schueler() liefert jetzt hat_gewaehlt, zuteilung,
--      fixiert mit (Fix: Live-Modus zeigte Status/Zuteilung nie an)
--   4. NEU: admin_bulk_assign(codes[], projekt_id, …) — Bulk-Zuordnung
--      und Bulk-Aufhebung (projekt_id = NULL) in einem Aufruf
--   5. update_zuteilung(): setzt fixiert = TRUE (manuelle Umbuchungen
--      überleben eine erneute Verlosung)
--   6. klassenlehrer_assign_schueler(): setzt fixiert = TRUE
--   7. run_verteilung(): überspringt fixierte Schüler, zählt deren
--      Plätze in die Belegung, Commit löscht nur nicht-fixierte Zeilen
-- ============================================================

-- ------------------------------------------------------------
-- 1) Spalte fixiert + Backfill
-- ------------------------------------------------------------
ALTER TABLE public.zuteilungen
  ADD COLUMN IF NOT EXISTS fixiert BOOLEAN NOT NULL DEFAULT FALSE;

-- Bestehende manuelle Zuordnungen (wahl_nr IS NULL = manuell/Klassen-
-- lehrer/Umbuchung) als fixiert markieren, damit sie ab sofort eine
-- Verlosung überleben.
UPDATE public.zuteilungen
   SET fixiert = TRUE
 WHERE wahl_nr IS NULL
   AND projekt_id IS NOT NULL
   AND fixiert = FALSE;

CREATE INDEX IF NOT EXISTS idx_zuteilungen_fixiert
  ON public.zuteilungen (fixiert) WHERE fixiert;

-- ------------------------------------------------------------
-- 2) View zuteilungen_detail um fixiert erweitern
--    WICHTIG: CREATE OR REPLACE VIEW erlaubt neue Spalten NUR am Ende
--    (Lehre aus erstem Migrationslauf: 42P16) — fixiert steht deshalb
--    als letzte Spalte.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW public.zuteilungen_detail AS
SELECT
  z.id,
  z.schueler_code,
  s.vorname, s.nachname, s.klasse, s.klassenstufe,
  z.projekt_id, p.titel AS projekt_titel,
  NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name,
  z.wahl_nr,
  z.updated_at,
  u1.name AS lehrer1_name,
  u2.name AS lehrer2_name,
  z.fixiert
FROM public.zuteilungen z
JOIN public.schueler s ON z.schueler_code = s.code
LEFT JOIN public.projekte p ON z.projekt_id = p.id
LEFT JOIN public.users u1 ON p.lehrer_id = u1.id
LEFT JOIN public.users u2 ON p.lehrer2_id = u2.id;

-- ------------------------------------------------------------
-- 3) admin_list_schueler — liefert Status + Zuteilung mit
--    (Returntyp ändert sich → DROP nötig, CREATE OR REPLACE reicht nicht)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_list_schueler();

CREATE FUNCTION public.admin_list_schueler()
RETURNS TABLE (
  code          TEXT,
  vorname       TEXT,
  nachname      TEXT,
  klasse        TEXT,
  klassenstufe  INT,
  created_at    TIMESTAMPTZ,
  hat_gewaehlt  BOOLEAN,
  zuteilung     UUID,
  wahl_nr       INT,
  fixiert       BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_app_user() THEN
    RAISE EXCEPTION 'nicht berechtigt';
  END IF;
  RETURN QUERY
  SELECT
    s.code, s.vorname, s.nachname, s.klasse, s.klassenstufe, s.created_at,
    EXISTS(SELECT 1 FROM public.wahlen w WHERE w.schueler_code = s.code) AS hat_gewaehlt,
    z.projekt_id AS zuteilung,
    z.wahl_nr,
    COALESCE(z.fixiert, FALSE) AS fixiert
  FROM public.schueler s
  LEFT JOIN public.zuteilungen z ON z.schueler_code = s.code
  ORDER BY s.klasse, s.nachname;
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_list_schueler() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_schueler() TO authenticated;

-- ------------------------------------------------------------
-- 4) NEU: admin_bulk_assign — Bulk-Zuordnung / Bulk-Aufhebung
--    p_projekt_id = NULL  → Zuordnung der übergebenen Codes aufheben
--    p_projekt_id gesetzt → alle Codes fixiert diesem Projekt zuordnen
--    Projekt darf 'entwurf' ODER 'veroeffentlicht' sein (Vorab-Phase!),
--    bei 'entwurf' kommt ein Hinweis zurück.
--    Klassenstufen-Konflikte blockieren nicht, werden aber gemeldet.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_bulk_assign(
  p_schueler_codes TEXT[],
  p_projekt_id     UUID DEFAULT NULL,
  p_bearbeiter_id  UUID DEFAULT NULL,
  p_kommentar      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code        TEXT;
  v_codes       TEXT[];
  v_projekt     RECORD;
  v_schueler    RECORD;
  v_zugeordnet  INT := 0;
  v_aufgehoben  INT := 0;
  v_unbekannt   JSONB := '[]'::jsonb;
  v_stufen_hinweise JSONB := '[]'::jsonb;
  v_belegt      INT;
  v_kommentar   TEXT;
BEGIN
  -- 0) Caller-Rollencheck (wie update_zuteilung)
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;

  -- 1) Codes normalisieren + deduplizieren
  SELECT ARRAY(
    SELECT DISTINCT UPPER(TRIM(c))
      FROM unnest(COALESCE(p_schueler_codes, '{}')) AS c
     WHERE TRIM(COALESCE(c, '')) <> ''
  ) INTO v_codes;

  IF COALESCE(array_length(v_codes, 1), 0) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'keine_codes');
  END IF;

  -- 2a) Aufheben-Modus
  IF p_projekt_id IS NULL THEN
    DELETE FROM public.zuteilungen
     WHERE schueler_code = ANY(v_codes);
    GET DIAGNOSTICS v_aufgehoben = ROW_COUNT;
    RETURN jsonb_build_object(
      'success', true,
      'modus', 'aufheben',
      'aufgehoben', v_aufgehoben,
      'codes_uebergeben', array_length(v_codes, 1)
    );
  END IF;

  -- 2b) Zuordnen-Modus: Projekt prüfen
  SELECT * INTO v_projekt
    FROM public.projekte
   WHERE id = p_projekt_id
     AND status IN ('entwurf', 'veroeffentlicht');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_unbekannt');
  END IF;

  v_kommentar := COALESCE(NULLIF(TRIM(p_kommentar), ''), 'Vorab zugeordnet')
                 || ' (' || to_char(now(), 'YYYY-MM-DD') || ')';

  -- 3) Schleife: upsert mit fixiert = TRUE
  FOREACH v_code IN ARRAY v_codes LOOP
    SELECT * INTO v_schueler FROM public.schueler WHERE public.schueler.code = v_code;
    IF NOT FOUND THEN
      v_unbekannt := v_unbekannt || to_jsonb(v_code);
      CONTINUE;
    END IF;

    IF v_schueler.klassenstufe < v_projekt.min_klasse
       OR v_schueler.klassenstufe > v_projekt.max_klasse THEN
      v_stufen_hinweise := v_stufen_hinweise || jsonb_build_object(
        'code', v_code,
        'klassenstufe', v_schueler.klassenstufe,
        'projekt_min', v_projekt.min_klasse,
        'projekt_max', v_projekt.max_klasse
      );
    END IF;

    INSERT INTO public.zuteilungen
      (schueler_code, projekt_id, wahl_nr, zugewiesen_von, kommentar, fixiert)
    VALUES
      (v_code, p_projekt_id, NULL, p_bearbeiter_id, v_kommentar, TRUE)
    ON CONFLICT (schueler_code) DO UPDATE
       SET projekt_id     = EXCLUDED.projekt_id,
           wahl_nr        = NULL,
           zugewiesen_von = EXCLUDED.zugewiesen_von,
           kommentar      = TRIM(BOTH ' |' FROM COALESCE(public.zuteilungen.kommentar, '')
                              || ' | ' || EXCLUDED.kommentar),
           fixiert        = TRUE,
           updated_at     = now();
    v_zugeordnet := v_zugeordnet + 1;
  END LOOP;

  -- 4) Neue Belegung
  SELECT COUNT(*) INTO v_belegt
    FROM public.zuteilungen
   WHERE projekt_id = p_projekt_id;

  RETURN jsonb_build_object(
    'success', true,
    'modus', 'zuordnen',
    'projekt_id', p_projekt_id,
    'projekt_titel', v_projekt.titel,
    'projekt_status', v_projekt.status,
    'zugeordnet', v_zugeordnet,
    'unbekannte_codes', v_unbekannt,
    'klassenstufen_hinweise', v_stufen_hinweise,
    'neue_belegung', v_belegt,
    'max_plaetze', v_projekt.max_plaetze,
    'ueberbucht', v_belegt > v_projekt.max_plaetze,
    'hinweis_entwurf', v_projekt.status = 'entwurf'
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_bulk_assign(TEXT[], UUID, UUID, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_assign(TEXT[], UUID, UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_bulk_assign(TEXT[], UUID, UUID, TEXT) TO authenticated;

-- ------------------------------------------------------------
-- 5) update_zuteilung — Body wie v29, setzt zusätzlich fixiert = TRUE
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_zuteilung(
  p_schueler_code TEXT,
  p_neues_projekt_id UUID,
  p_bearbeiter_id UUID DEFAULT NULL,
  p_kommentar TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schueler RECORD;
  v_projekt RECORD;
  v_alte_zuteilung RECORD;
  v_belegt INT;
  v_ueberbucht BOOLEAN;
  v_hinweis TEXT;
  v_normalized TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;

  v_normalized := UPPER(TRIM(COALESCE(p_schueler_code, '')));
  IF v_normalized = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_code_leer');
  END IF;

  SELECT * INTO v_schueler FROM schueler WHERE code = v_normalized;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_unbekannt', 'code', v_normalized);
  END IF;

  SELECT * INTO v_projekt
    FROM projekte
   WHERE id = p_neues_projekt_id AND status = 'veroeffentlicht';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_unbekannt_oder_unveroeffentlicht');
  END IF;

  IF v_schueler.klassenstufe < v_projekt.min_klasse
     OR v_schueler.klassenstufe > v_projekt.max_klasse THEN
    v_hinweis := 'klassenstufe_ausserhalb_' || v_projekt.min_klasse || '_' || v_projekt.max_klasse;
  END IF;

  SELECT COUNT(*) INTO v_belegt
    FROM zuteilungen
   WHERE projekt_id = p_neues_projekt_id
     AND schueler_code <> v_normalized;

  v_ueberbucht := v_belegt >= v_projekt.max_plaetze;

  SELECT * INTO v_alte_zuteilung FROM zuteilungen WHERE schueler_code = v_normalized;

  IF FOUND THEN
    UPDATE zuteilungen
       SET projekt_id = p_neues_projekt_id,
           wahl_nr = NULL,
           fixiert = TRUE,
           zugewiesen_von = p_bearbeiter_id,
           kommentar = TRIM(BOTH ' |' FROM COALESCE(kommentar, '') || ' | ' ||
                             COALESCE(NULLIF(TRIM(p_kommentar), ''), 'Manuell umgebucht') ||
                             ' (' || to_char(now(), 'YYYY-MM-DD') || ')'),
           updated_at = now()
     WHERE schueler_code = v_normalized;
  ELSE
    INSERT INTO zuteilungen (schueler_code, projekt_id, wahl_nr, zugewiesen_von, kommentar, fixiert)
    VALUES (
      v_normalized, p_neues_projekt_id, NULL, p_bearbeiter_id,
      COALESCE(NULLIF(TRIM(p_kommentar), ''), 'Manuell zugeteilt') ||
        ' (' || to_char(now(), 'YYYY-MM-DD') || ')',
      TRUE
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'schueler_code', v_normalized,
    'projekt_id', p_neues_projekt_id,
    'projekt_titel', v_projekt.titel,
    'neue_belegung', v_belegt + 1,
    'max_plaetze', v_projekt.max_plaetze,
    'ueberbucht', v_ueberbucht,
    'hinweis', v_hinweis
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

-- ------------------------------------------------------------
-- 6) klassenlehrer_assign_schueler — setzt fixiert = TRUE
--    (Body wie v28, nur Insert/Update um fixiert ergänzt)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.klassenlehrer_assign_schueler(
  p_schueler_code TEXT,
  p_projekt_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    UUID;
  v_caller_klasse TEXT;
  v_code         TEXT;
  v_schueler     RECORD;
  v_projekt      RECORD;
  v_alte         RECORD;
  v_belegt       INT;
  v_ueberbucht   BOOLEAN;
BEGIN
  IF NOT public.is_klassenlehrer() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_klassenlehrer');
  END IF;

  v_caller_id := public.current_app_user_id();
  v_caller_klasse := public.current_klassenlehrer_klasse();
  IF v_caller_klasse IS NULL OR v_caller_klasse = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'keine_klasse_zugeordnet');
  END IF;

  v_code := UPPER(TRIM(COALESCE(p_schueler_code, '')));
  IF v_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_code_leer');
  END IF;
  IF p_projekt_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_id_leer');
  END IF;

  SELECT * INTO v_schueler FROM public.schueler WHERE code = v_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_unbekannt', 'code', v_code);
  END IF;
  IF LOWER(TRIM(v_schueler.klasse)) <> v_caller_klasse THEN
    RETURN jsonb_build_object('success', false, 'error', 'fremde_klasse');
  END IF;

  SELECT * INTO v_projekt
    FROM public.projekte
   WHERE id = p_projekt_id AND status = 'veroeffentlicht';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_unbekannt_oder_unveroeffentlicht');
  END IF;

  IF v_schueler.klassenstufe < v_projekt.min_klasse
     OR v_schueler.klassenstufe > v_projekt.max_klasse THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'klassenstufe_ausserhalb',
      'min_klasse', v_projekt.min_klasse,
      'max_klasse', v_projekt.max_klasse
    );
  END IF;

  SELECT COUNT(*) INTO v_belegt
    FROM public.zuteilungen
   WHERE projekt_id = p_projekt_id
     AND schueler_code <> v_code;
  v_ueberbucht := v_belegt >= v_projekt.max_plaetze;

  SELECT * INTO v_alte FROM public.zuteilungen WHERE schueler_code = v_code;
  IF FOUND THEN
    UPDATE public.zuteilungen
       SET projekt_id = p_projekt_id,
           wahl_nr = NULL,
           fixiert = TRUE,
           zugewiesen_von = v_caller_id,
           kommentar = TRIM(BOTH ' |' FROM COALESCE(kommentar, '') || ' | Direkt durch Klassenlehrer ('
                                       || to_char(now(), 'YYYY-MM-DD') || ')'),
           updated_at = now()
     WHERE schueler_code = v_code;
  ELSE
    INSERT INTO public.zuteilungen (schueler_code, projekt_id, wahl_nr, zugewiesen_von, kommentar, fixiert)
    VALUES (
      v_code, p_projekt_id, NULL, v_caller_id,
      'Direkt durch Klassenlehrer (' || to_char(now(), 'YYYY-MM-DD') || ')',
      TRUE
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'schueler_code', v_code,
    'projekt_id', p_projekt_id,
    'projekt_titel', v_projekt.titel,
    'neue_belegung', v_belegt + 1,
    'max_plaetze', v_projekt.max_plaetze,
    'ueberbucht', v_ueberbucht
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

-- ------------------------------------------------------------
-- 7) run_verteilung — respektiert fixierte Zuordnungen
--    Änderungen ggü. v29:
--    a) Belegung wird mit fixierten Zuteilungen vorbelegt
--    b) Fixierte Schüler werden in beiden Schleifen übersprungen
--    c) Commit löscht nur zuteilungen mit fixiert = FALSE
--    d) Statistik enthält 'fixiert'
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_verteilung(
  p_seed TEXT DEFAULT NULL,
  p_commit BOOLEAN DEFAULT FALSE,
  p_bearbeiter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seed TEXT;
  v_seed_float DOUBLE PRECISION;
  v_verteilung_id UUID;
  v_zuteilungen JSONB := '[]'::jsonb;
  v_nicht_zugeteilt JSONB := '[]'::jsonb;
  v_belegung JSONB;
  v_auslastung JSONB := '[]'::jsonb;
  v_schueler RECORD;
  v_projekt RECORD;
  v_projekt_row RECORD;
  v_zugeteilt BOOLEAN;
  v_wahl_nr INT;
  v_ziel_projekt_id UUID;
  v_mit_wahlen INT := 0;
  v_ohne_wahlen INT := 0;
  v_fixiert INT := 0;
  v_stat_erstwahl INT := 0;
  v_stat_zweitwahl INT := 0;
  v_stat_drittwahl INT := 0;
  v_stat_nicht INT := 0;
  v_anzahl_schueler INT := 0;
  v_anzahl_projekte INT := 0;
  v_summe_plaetze INT := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;

  v_seed := COALESCE(
    NULLIF(TRIM(p_seed), ''),
    'krs-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substring(md5(random()::text), 1, 6)
  );
  v_seed_float := (hashtext(v_seed))::double precision / 2147483648.0;
  IF v_seed_float = 1.0 THEN v_seed_float := 0.9999999; END IF;
  IF v_seed_float = -1.0 THEN v_seed_float := -0.9999999; END IF;

  SELECT COUNT(*) INTO v_anzahl_schueler FROM schueler;
  SELECT COUNT(*), COALESCE(SUM(max_plaetze), 0)
    INTO v_anzahl_projekte, v_summe_plaetze
    FROM projekte WHERE status = 'veroeffentlicht';

  IF v_anzahl_projekte = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'keine_projekte_veroeffentlicht',
      'hinweis', 'Es gibt noch keine veröffentlichten Projekte.'
    );
  END IF;

  -- v38: Anzahl fixierter Schüler
  SELECT COUNT(*) INTO v_fixiert
    FROM zuteilungen WHERE fixiert = TRUE AND projekt_id IS NOT NULL;

  -- v38: Belegung mit fixierten Zuteilungen vorbelegen
  SELECT jsonb_object_agg(p.id::text, COALESCE(f.cnt, 0)) INTO v_belegung
    FROM projekte p
    LEFT JOIN (
      SELECT projekt_id, COUNT(*) AS cnt
        FROM zuteilungen
       WHERE fixiert = TRUE
       GROUP BY projekt_id
    ) f ON f.projekt_id = p.id
   WHERE p.status = 'veroeffentlicht';

  PERFORM setseed(v_seed_float);

  -- RSD-Hauptschleife — v38: fixierte Schüler ausgenommen
  FOR v_schueler IN
    SELECT s.code, s.klassenstufe,
           w.erstwahl_id, w.zweitwahl_id, w.drittwahl_id
      FROM schueler s
      JOIN wahlen w ON w.schueler_code = s.code
     WHERE NOT EXISTS (
             SELECT 1 FROM zuteilungen z
              WHERE z.schueler_code = s.code AND z.fixiert = TRUE
           )
     ORDER BY random()
  LOOP
    v_mit_wahlen := v_mit_wahlen + 1;
    v_zugeteilt := FALSE;

    FOR v_wahl_nr IN 1..3 LOOP
      v_ziel_projekt_id := CASE v_wahl_nr
        WHEN 1 THEN v_schueler.erstwahl_id
        WHEN 2 THEN v_schueler.zweitwahl_id
        WHEN 3 THEN v_schueler.drittwahl_id
      END;

      SELECT p.id, p.titel, p.max_plaetze, p.min_klasse, p.max_klasse
        INTO v_projekt
        FROM projekte p
       WHERE p.id = v_ziel_projekt_id
         AND p.status = 'veroeffentlicht';

      IF NOT FOUND THEN CONTINUE; END IF;

      IF v_schueler.klassenstufe < v_projekt.min_klasse
         OR v_schueler.klassenstufe > v_projekt.max_klasse THEN
        CONTINUE;
      END IF;

      IF ((v_belegung ->> v_projekt.id::text)::int) < v_projekt.max_plaetze THEN
        v_zuteilungen := v_zuteilungen || jsonb_build_object(
          'schueler_code', v_schueler.code,
          'projekt_id', v_projekt.id,
          'projekt_titel', v_projekt.titel,
          'wahl_nr', v_wahl_nr,
          'klassenstufe', v_schueler.klassenstufe
        );
        v_belegung := jsonb_set(
          v_belegung,
          ARRAY[v_projekt.id::text],
          to_jsonb(((v_belegung ->> v_projekt.id::text)::int) + 1)
        );
        v_zugeteilt := TRUE;
        IF v_wahl_nr = 1 THEN v_stat_erstwahl := v_stat_erstwahl + 1;
        ELSIF v_wahl_nr = 2 THEN v_stat_zweitwahl := v_stat_zweitwahl + 1;
        ELSE v_stat_drittwahl := v_stat_drittwahl + 1;
        END IF;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_zugeteilt THEN
      v_nicht_zugeteilt := v_nicht_zugeteilt || jsonb_build_object(
        'schueler_code', v_schueler.code,
        'klassenstufe', v_schueler.klassenstufe,
        'grund', 'alle_wahlen_voll'
      );
      v_stat_nicht := v_stat_nicht + 1;
    END IF;
  END LOOP;

  -- Schüler ohne Wahlen — v38: fixierte ausgenommen (sind ja versorgt)
  FOR v_schueler IN
    SELECT s.code, s.klassenstufe FROM schueler s
     WHERE NOT EXISTS(SELECT 1 FROM wahlen WHERE schueler_code = s.code)
       AND NOT EXISTS(
             SELECT 1 FROM zuteilungen z
              WHERE z.schueler_code = s.code AND z.fixiert = TRUE
           )
  LOOP
    v_ohne_wahlen := v_ohne_wahlen + 1;
    v_nicht_zugeteilt := v_nicht_zugeteilt || jsonb_build_object(
      'schueler_code', v_schueler.code,
      'klassenstufe', v_schueler.klassenstufe,
      'grund', 'hat_nicht_gewaehlt'
    );
  END LOOP;

  -- Projekt-Auslastung (Belegung enthält fixierte Plätze bereits)
  FOR v_projekt_row IN
    SELECT p.id, p.titel, p.max_plaetze, p.min_teilnehmer
      FROM projekte p WHERE p.status = 'veroeffentlicht'
     ORDER BY p.titel
  LOOP
    v_auslastung := v_auslastung || jsonb_build_object(
      'id', v_projekt_row.id,
      'titel', v_projekt_row.titel,
      'belegt', (v_belegung ->> v_projekt_row.id::text)::int,
      'max', v_projekt_row.max_plaetze,
      'min_teilnehmer', v_projekt_row.min_teilnehmer,
      'unter_minimum', (v_belegung ->> v_projekt_row.id::text)::int < v_projekt_row.min_teilnehmer
    );
  END LOOP;

  -- Commit — v38: NUR nicht-fixierte Zuteilungen ersetzen
  IF p_commit THEN
    UPDATE verteilungen SET ist_aktiv = FALSE WHERE ist_aktiv = TRUE;

    INSERT INTO verteilungen (gestartet_von, seed, ist_aktiv, ist_preview, statistik)
    VALUES (
      p_bearbeiter_id, v_seed, TRUE, FALSE,
      jsonb_build_object(
        'gesamt_schueler', v_anzahl_schueler,
        'mit_wahlen', v_mit_wahlen,
        'ohne_wahlen', v_ohne_wahlen,
        'fixiert', v_fixiert,
        'zugeteilt', v_stat_erstwahl + v_stat_zweitwahl + v_stat_drittwahl,
        'nicht_zugeteilt', v_stat_nicht,
        'erstwahl', v_stat_erstwahl,
        'zweitwahl', v_stat_zweitwahl,
        'drittwahl', v_stat_drittwahl
      )
    )
    RETURNING id INTO v_verteilung_id;

    DELETE FROM zuteilungen WHERE fixiert = FALSE;

    INSERT INTO zuteilungen (schueler_code, projekt_id, wahl_nr, verteilung_id, zugewiesen_von)
    SELECT
      z->>'schueler_code',
      (z->>'projekt_id')::uuid,
      (z->>'wahl_nr')::int,
      v_verteilung_id,
      p_bearbeiter_id
      FROM jsonb_array_elements(v_zuteilungen) AS z;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'seed', v_seed,
    'verteilung_id', v_verteilung_id,
    'committed', p_commit,
    'statistik', jsonb_build_object(
      'gesamt_schueler', v_anzahl_schueler,
      'mit_wahlen', v_mit_wahlen,
      'ohne_wahlen', v_ohne_wahlen,
      'fixiert', v_fixiert,
      'zugeteilt', v_stat_erstwahl + v_stat_zweitwahl + v_stat_drittwahl,
      'nicht_zugeteilt', v_stat_nicht,
      'erstwahl', v_stat_erstwahl,
      'zweitwahl', v_stat_zweitwahl,
      'drittwahl', v_stat_drittwahl,
      'prozent_erstwahl',  CASE WHEN v_mit_wahlen > 0 THEN round(100.0 * v_stat_erstwahl  / v_mit_wahlen) ELSE 0 END,
      'prozent_zweitwahl', CASE WHEN v_mit_wahlen > 0 THEN round(100.0 * v_stat_zweitwahl / v_mit_wahlen) ELSE 0 END,
      'prozent_drittwahl', CASE WHEN v_mit_wahlen > 0 THEN round(100.0 * v_stat_drittwahl / v_mit_wahlen) ELSE 0 END,
      'anzahl_projekte', v_anzahl_projekte,
      'summe_plaetze', v_summe_plaetze
    ),
    'zuteilungen', v_zuteilungen,
    'nicht_zugeteilt', v_nicht_zugeteilt,
    'projekte_auslastung', v_auslastung,
    'belegung', v_belegung,
    'zeitpunkt', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF')
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM,
      'seed', v_seed
    );
END;
$$;

-- ------------------------------------------------------------
-- Kontroll-SELECTs
-- ------------------------------------------------------------
-- 1) Spalte da?
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'zuteilungen' AND column_name = 'fixiert';

-- 2) Wie viele fixierte Zuteilungen gibt es?
SELECT fixiert, COUNT(*) FROM public.zuteilungen GROUP BY fixiert;

-- 3) Funktionen vorhanden?
SELECT proname, pg_get_function_identity_arguments(oid)
  FROM pg_proc
 WHERE proname IN ('admin_bulk_assign', 'admin_list_schueler', 'run_verteilung', 'update_zuteilung', 'klassenlehrer_assign_schueler')
 ORDER BY proname;
