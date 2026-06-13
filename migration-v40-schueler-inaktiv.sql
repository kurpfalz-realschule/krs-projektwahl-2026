-- ============================================================
-- Migration v40 — Schüler "inaktiv" setzen (soft exclude)
-- ============================================================
-- Ziel: Schüler:innen von Wahl UND Verlosung ausschließen, ohne sie
--       zu löschen. Inaktive Schüler:innen:
--   • können sich im Schüler-Frontend NICHT anmelden
--     (get_schueler_status liefert error 'schueler_inaktiv' →
--      Frontend zeigt freundliche Meldung)
--   • werden von run_verteilung ignoriert (weder gezählt noch verteilt)
--   • erscheinen im Admin nur über den Filter "Nur inaktive"
--
-- Design-Entscheidung (mit Norbert abgestimmt):
--   Beim Inaktiv-Setzen werden vorhandene Wahl + Zuteilung + offene
--   Tauschwünsche GELÖSCHT (sauberer Schnitt). Bei Reaktivierung sind
--   diese Daten weg — der Schüler startet wieder bei "fehlt".
--
-- Reihenfolge der Schritte:
--   1) Spalte schueler.aktiv + Index
--   2) RPC set_schueler_aktiv(code, aktiv)  — admin-guarded
--   3) get_schueler_status — Inaktiv-Block (Vollkopie v33 + Check)
--   4) admin_list_schueler — Spalte aktiv (Vollkopie v38 + Spalte)
--   5) run_verteilung — aktiv-Filter (Vollkopie v38 + 3 Stellen)
--   6) Kontroll-SELECTs
-- ============================================================

-- ------------------------------------------------------------
-- 1) Spalte aktiv (Default TRUE → bestehende Schüler bleiben aktiv)
-- ------------------------------------------------------------
ALTER TABLE public.schueler
  ADD COLUMN IF NOT EXISTS aktiv BOOLEAN NOT NULL DEFAULT TRUE;

-- Teil-Index: nur die (seltenen) inaktiven Zeilen werden indiziert.
CREATE INDEX IF NOT EXISTS idx_schueler_inaktiv
  ON public.schueler (aktiv) WHERE NOT aktiv;


-- ------------------------------------------------------------
-- 2) set_schueler_aktiv — ein Schüler aktiv/inaktiv schalten
--    p_aktiv = FALSE → löscht Wahl, Zuteilung, offene Tauschwünsche
--    p_aktiv = TRUE  → reaktiviert (keine Daten werden erzeugt)
--    Nur Admins dürfen schalten.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_schueler_aktiv(
  p_code  TEXT,
  p_aktiv BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code        TEXT := UPPER(TRIM(COALESCE(p_code, '')));
  v_schueler    RECORD;
  v_del_wahlen  INT := 0;
  v_del_zut     INT := 0;
  v_del_tausch  INT := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;
  IF v_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_fehlt');
  END IF;

  SELECT * INTO v_schueler FROM public.schueler WHERE code = v_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_unbekannt');
  END IF;

  IF p_aktiv THEN
    -- Reaktivieren
    UPDATE public.schueler SET aktiv = TRUE WHERE code = v_code;
    RETURN jsonb_build_object(
      'success', true, 'code', v_code, 'aktiv', true
    );
  END IF;

  -- Inaktiv setzen → sauberer Schnitt: alle Wahl-Daten entfernen.
  WITH d AS (DELETE FROM public.tauschwuensche WHERE schueler_code = v_code RETURNING 1)
    SELECT COUNT(*) INTO v_del_tausch FROM d;
  WITH d AS (DELETE FROM public.zuteilungen   WHERE schueler_code = v_code RETURNING 1)
    SELECT COUNT(*) INTO v_del_zut FROM d;
  WITH d AS (DELETE FROM public.wahlen        WHERE schueler_code = v_code RETURNING 1)
    SELECT COUNT(*) INTO v_del_wahlen FROM d;

  UPDATE public.schueler SET aktiv = FALSE WHERE code = v_code;

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'aktiv', false,
    'geloescht', jsonb_build_object(
      'wahlen', v_del_wahlen,
      'zuteilungen', v_del_zut,
      'tauschwuensche', v_del_tausch
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'datenbank_fehler', 'details', SQLERRM
    );
END;
$$;

REVOKE ALL  ON FUNCTION public.set_schueler_aktiv(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_schueler_aktiv(TEXT, BOOLEAN) TO authenticated;


-- ------------------------------------------------------------
-- 3) get_schueler_status — inaktive Schüler blocken
--    (Vollkopie aus migration-v33, ergänzt um Aktiv-Check direkt
--     nach dem Existenz-Check.)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_schueler_status(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schueler RECORD;
  v_wahl RECORD;
  v_zuteilung RECORD;
  v_tausch RECORD;
  v_phase TEXT;
BEGIN
  SELECT * INTO v_schueler FROM public.schueler WHERE code = UPPER(TRIM(p_code));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END IF;

  -- v40: inaktive Schüler:innen nehmen nicht an der Projektwahl teil.
  IF NOT COALESCE(v_schueler.aktiv, TRUE) THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_inaktiv');
  END IF;

  SELECT value #>> '{}' INTO v_phase
  FROM public.system_settings
  WHERE key = 'phase';
  IF v_phase IS NULL OR v_phase = '' THEN
    v_phase := 'anmeldung';
  END IF;

  SELECT * INTO v_wahl
  FROM public.wahlen
  WHERE schueler_code = v_schueler.code;

  SELECT
    z.*,
    p.titel,
    p.kurzbeschreibung,
    p.ort,
    NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name
  INTO v_zuteilung
  FROM public.zuteilungen z
  LEFT JOIN public.projekte p ON z.projekt_id = p.id
  LEFT JOIN public.users u1 ON p.lehrer_id = u1.id
  LEFT JOIN public.users u2 ON p.lehrer2_id = u2.id
  WHERE z.schueler_code = v_schueler.code
    AND z.projekt_id IS NOT NULL;

  SELECT t.*, p.titel AS nach_titel
  INTO v_tausch
  FROM public.tauschwuensche t
  LEFT JOIN public.projekte p ON t.nach_projekt_id = p.id
  WHERE t.schueler_code = v_schueler.code
    AND t.status = 'offen'
  ORDER BY t.created_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'success', true,
    'phase', v_phase,
    'schueler', jsonb_build_object(
      'code', v_schueler.code,
      'vorname', v_schueler.vorname,
      'nachname', v_schueler.nachname,
      'klasse', v_schueler.klasse,
      'klassenstufe', v_schueler.klassenstufe
    ),
    'hat_gewaehlt', v_wahl IS NOT NULL,
    'hat_zuteilung', v_zuteilung IS NOT NULL,
    'zuteilung', CASE WHEN v_zuteilung IS NOT NULL THEN jsonb_build_object(
      'projekt_id', v_zuteilung.projekt_id,
      'projekt_titel', v_zuteilung.titel,
      'projekt_beschreibung', v_zuteilung.kurzbeschreibung,
      'lehrer', v_zuteilung.lehrer_name,
      'ort', v_zuteilung.ort,
      'wahl_nr', v_zuteilung.wahl_nr
    ) ELSE NULL END,
    'hat_offenen_tausch', v_tausch IS NOT NULL,
    'offener_tausch', CASE WHEN v_tausch IS NOT NULL THEN jsonb_build_object(
      'id', v_tausch.id,
      'nach_projekt_id', v_tausch.nach_projekt_id,
      'nach_projekt_titel', v_tausch.nach_titel,
      'begruendung', v_tausch.begruendung,
      'created_at', v_tausch.created_at
    ) ELSE NULL END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_schueler_status(TEXT) TO anon, authenticated;


-- ------------------------------------------------------------
-- 4) admin_list_schueler — Spalte aktiv ergänzen
--    (Vollkopie aus migration-v38, RETURNS TABLE + SELECT erweitert.)
--    DROP nötig, weil sich die Rückgabe-Signatur ändert.
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
  fixiert       BOOLEAN,
  aktiv         BOOLEAN
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
    COALESCE(z.fixiert, FALSE) AS fixiert,
    COALESCE(s.aktiv, TRUE) AS aktiv
  FROM public.schueler s
  LEFT JOIN public.zuteilungen z ON z.schueler_code = s.code
  ORDER BY s.klasse, s.nachname;
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_list_schueler() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_schueler() TO authenticated;


-- ------------------------------------------------------------
-- 5) run_verteilung — inaktive Schüler ignorieren
--    (Vollkopie aus migration-v38, ergänzt um aktiv-Filter an
--     3 Stellen: Gesamtzahl, RSD-Hauptschleife, "ohne Wahlen".)
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

  -- v40: nur aktive Schüler zählen
  SELECT COUNT(*) INTO v_anzahl_schueler FROM schueler WHERE aktiv;
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

  -- RSD-Hauptschleife — v38: fixierte Schüler ausgenommen; v40: nur aktive
  FOR v_schueler IN
    SELECT s.code, s.klassenstufe,
           w.erstwahl_id, w.zweitwahl_id, w.drittwahl_id
      FROM schueler s
      JOIN wahlen w ON w.schueler_code = s.code
     WHERE s.aktiv
       AND NOT EXISTS (
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

  -- Schüler ohne Wahlen — v38: fixierte ausgenommen; v40: nur aktive
  FOR v_schueler IN
    SELECT s.code, s.klassenstufe FROM schueler s
     WHERE s.aktiv
       AND NOT EXISTS(SELECT 1 FROM wahlen WHERE schueler_code = s.code)
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
-- 6) Kontroll-SELECTs (nach dem Lauf prüfen)
-- ------------------------------------------------------------
-- a) Spalte da?
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'schueler' AND column_name = 'aktiv';

-- b) Verteilung aktiv/inaktiv
SELECT aktiv, COUNT(*) FROM public.schueler GROUP BY aktiv;

-- c) Funktionen vorhanden + Signaturen?
SELECT proname, pg_get_function_identity_arguments(oid)
  FROM pg_proc
 WHERE proname IN ('set_schueler_aktiv', 'admin_list_schueler', 'get_schueler_status', 'run_verteilung')
 ORDER BY proname;
