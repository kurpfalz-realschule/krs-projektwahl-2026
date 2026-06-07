-- ============================================================
-- migration-v29-bundle.sql
-- Sprint v29 Mega-Bundle (E1.7 + E1.8 Backend-Anteil)
--
-- ALLES in EINER Migration — du musst genau einmal in Supabase
-- den SQL Editor öffnen und auf Run klicken.
--
-- Was diese Migration macht:
--   1. update_zuteilung() bekommt einen Caller-Rollencheck
--      (is_admin() = super_admin OR projektleitung) als erste
--      Aktion im Body.
--   2. run_verteilung() bekommt den GLEICHEN Caller-Rollencheck
--      ganz oben (Body sonst identisch zu v10).
--   3. Beide Funktionen: REVOKE EXECUTE FROM anon, PUBLIC
--      und GRANT EXECUTE TO authenticated.
--      (Defense in depth zusätzlich zum Body-Check.)
--
-- Annahmen (müssen aus früheren Migrationen erfüllt sein):
--   - Helper public.is_admin() existiert (migration-auth-bridge.sql,
--     definiert für Rollen 'super_admin' und 'projektleitung').
--   - Tabellen schueler, projekte, zuteilungen, wahlen, verteilungen
--     existieren mit dem Schema von schema-v2-fixed.sql.
--   - update_zuteilung() und run_verteilung() sind aus
--     migration-verteilungsalgorithmus.sql bereits deployed.
--
-- Idempotent: ja, beide Funktionen sind CREATE OR REPLACE.
-- ============================================================


-- ============================================================
-- 1) run_verteilung — Caller-Guard ergänzt, Body sonst identisch
--    zu archive/old-migrations/migration-verteilungsalgorithmus.sql:39
-- ============================================================

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
  v_stat_erstwahl INT := 0;
  v_stat_zweitwahl INT := 0;
  v_stat_drittwahl INT := 0;
  v_stat_nicht INT := 0;
  v_anzahl_schueler INT := 0;
  v_anzahl_projekte INT := 0;
  v_summe_plaetze INT := 0;
BEGIN
  -- 0) Caller-Rollencheck (NEU in v29)
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;

  -- Seed vorbereiten (Text → deterministischer Float ∈ [-1, 1])
  v_seed := COALESCE(
    NULLIF(TRIM(p_seed), ''),
    'krs-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substring(md5(random()::text), 1, 6)
  );
  v_seed_float := (hashtext(v_seed))::double precision / 2147483648.0;
  IF v_seed_float = 1.0 THEN v_seed_float := 0.9999999; END IF;
  IF v_seed_float = -1.0 THEN v_seed_float := -0.9999999; END IF;

  -- Basis-Kennzahlen
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

  -- Belegung initialisieren
  SELECT jsonb_object_agg(id::text, 0) INTO v_belegung
    FROM projekte WHERE status = 'veroeffentlicht';

  -- Deterministische Zufallsfolge
  PERFORM setseed(v_seed_float);

  -- RSD-Hauptschleife
  FOR v_schueler IN
    SELECT s.code, s.klassenstufe,
           w.erstwahl_id, w.zweitwahl_id, w.drittwahl_id
      FROM schueler s
      JOIN wahlen w ON w.schueler_code = s.code
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

  -- Schüler ohne Wahlen
  FOR v_schueler IN
    SELECT s.code, s.klassenstufe FROM schueler s
     WHERE NOT EXISTS(SELECT 1 FROM wahlen WHERE schueler_code = s.code)
  LOOP
    v_ohne_wahlen := v_ohne_wahlen + 1;
    v_nicht_zugeteilt := v_nicht_zugeteilt || jsonb_build_object(
      'schueler_code', v_schueler.code,
      'klassenstufe', v_schueler.klassenstufe,
      'grund', 'hat_nicht_gewaehlt'
    );
  END LOOP;

  -- Projekt-Auslastung
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

  -- Commit (destruktiv)
  IF p_commit THEN
    UPDATE verteilungen SET ist_aktiv = FALSE WHERE ist_aktiv = TRUE;

    INSERT INTO verteilungen (gestartet_von, seed, ist_aktiv, ist_preview, statistik)
    VALUES (
      p_bearbeiter_id, v_seed, TRUE, FALSE,
      jsonb_build_object(
        'gesamt_schueler', v_anzahl_schueler,
        'mit_wahlen', v_mit_wahlen,
        'ohne_wahlen', v_ohne_wahlen,
        'zugeteilt', v_stat_erstwahl + v_stat_zweitwahl + v_stat_drittwahl,
        'nicht_zugeteilt', v_stat_nicht,
        'erstwahl', v_stat_erstwahl,
        'zweitwahl', v_stat_zweitwahl,
        'drittwahl', v_stat_drittwahl
      )
    )
    RETURNING id INTO v_verteilung_id;

    DELETE FROM zuteilungen;

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


-- ============================================================
-- 2) update_zuteilung — Caller-Guard ergänzt, Body sonst identisch
--    zu archive/old-migrations/migration-verteilungsalgorithmus.sql:277
-- ============================================================

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
  -- 0) Caller-Rollencheck (NEU in v29)
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
           zugewiesen_von = p_bearbeiter_id,
           kommentar = TRIM(BOTH ' |' FROM COALESCE(kommentar, '') || ' | ' ||
                             COALESCE(NULLIF(TRIM(p_kommentar), ''), 'Manuell umgebucht') ||
                             ' (' || to_char(now(), 'YYYY-MM-DD') || ')'),
           updated_at = now()
     WHERE schueler_code = v_normalized;
  ELSE
    INSERT INTO zuteilungen (schueler_code, projekt_id, wahl_nr, zugewiesen_von, kommentar)
    VALUES (
      v_normalized, p_neues_projekt_id, NULL, p_bearbeiter_id,
      COALESCE(NULLIF(TRIM(p_kommentar), ''), 'Manuell zugeteilt') ||
        ' (' || to_char(now(), 'YYYY-MM-DD') || ')'
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
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM
    );
END;
$$;


-- ============================================================
-- 3) Berechtigungen — anon raus, authenticated bleibt
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.run_verteilung(TEXT, BOOLEAN, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.run_verteilung(TEXT, BOOLEAN, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.run_verteilung(TEXT, BOOLEAN, UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_zuteilung(TEXT, UUID, UUID, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_zuteilung(TEXT, UUID, UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.update_zuteilung(TEXT, UUID, UUID, TEXT) TO authenticated;


-- ============================================================
-- 4) Verifikation (manuell im SQL-Editor nach Deploy ausführen)
-- ============================================================
-- a) Beide Funktionen vorhanden + SECURITY DEFINER:
--    SELECT proname, prosecdef FROM pg_proc
--     WHERE proname IN ('run_verteilung', 'update_zuteilung');
--    -> 2 Zeilen, prosecdef = true bei beiden
--
-- b) anon hat KEIN EXECUTE mehr:
--    SELECT
--      has_function_privilege('anon', 'public.run_verteilung(text, boolean, uuid)', 'EXECUTE')   AS run_anon,
--      has_function_privilege('anon', 'public.update_zuteilung(text, uuid, uuid, text)', 'EXECUTE') AS upd_anon;
--    -> beide false
--
-- c) authenticated hat EXECUTE:
--    SELECT
--      has_function_privilege('authenticated', 'public.run_verteilung(text, boolean, uuid)', 'EXECUTE')   AS run_auth,
--      has_function_privilege('authenticated', 'public.update_zuteilung(text, uuid, uuid, text)', 'EXECUTE') AS upd_auth;
--    -> beide true
--
-- d) Smoke-Tests in der Live-App:
--    - Als Admin in Tab "Manuelle Umbuchung" → Schüler umbuchen → muss durchgehen
--    - Als Admin Verteilung neu starten → muss durchgehen
--    - (optional) Als Klassenlehrer/Projektlehrer eingeloggt → RPC im SQL-Editor:
--      SELECT public.update_zuteilung('TEST123','00000000-0000-0000-0000-000000000000');
--      -> { "success": false, "error": "nicht_berechtigt" }

-- ============================================================
-- DONE — kein weiterer DB-Run nötig.
-- ============================================================
