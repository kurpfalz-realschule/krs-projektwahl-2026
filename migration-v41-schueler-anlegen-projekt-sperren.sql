-- ============================================================
-- Migration v41 — Schüler nachträglich anlegen + Projekte sperren
-- ============================================================
-- Drei Bausteine:
--   1) Spalte projekte.gesperrt (BOOLEAN, default false)
--      → "geschlossen für weitere SuS". Bereits zugeteilte/fixierte
--        Schüler:innen bleiben unberührt; nur Neu-Wahl + Auffüllen wird
--        unterbunden (Auffüllen-Logik im Admin-Frontend).
--   2) View projekte_public um Spalte gesperrt erweitert (Vollkopie v33).
--   3) RPC set_projekt_gesperrt(p_id, p_gesperrt) — admin-guarded.
--   4) RPC admin_create_schueler(vorname, nachname, klasse) — admin-guarded.
--      Erzeugt eindeutigen Anmelde-Code im Frontend-Format "<KLASSE>-XXXX",
--      leitet klassenstufe ab, setzt aktiv = TRUE.
--
-- Ausführen mit (Supabase SQL-Editor) ODER:
--   ~/.local/bin/supabase db query --linked --file migration-v41-schueler-anlegen-projekt-sperren.sql
--
-- Idempotent: kann gefahrlos mehrfach laufen.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) Spalte gesperrt
-- ------------------------------------------------------------
ALTER TABLE public.projekte
  ADD COLUMN IF NOT EXISTS gesperrt BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.projekte.gesperrt IS
  'v41: TRUE = für weitere Schüler:innen geschlossen (keine Neu-Wahl, kein Auffüllen). Bereits Zugeteilte bleiben.';

-- ------------------------------------------------------------
-- 2) projekte_public — Vollkopie der v33-Definition + gesperrt
-- ------------------------------------------------------------
-- WICHTIG: Bei CREATE OR REPLACE VIEW müssen bestehende Spalten in exakt
-- gleicher Reihenfolge bleiben; neue Spalten (gesperrt) NUR ans Ende anhängen.
CREATE OR REPLACE VIEW public.projekte_public AS
SELECT
  p.id,
  p.titel,
  p.kurzbeschreibung,
  p.langbeschreibung,
  p.min_klasse,
  p.max_klasse,
  p.ort,
  p.bild_url,
  NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name,
  u1.name AS lehrer1_name,
  u2.name AS lehrer2_name,
  p.gesperrt
FROM public.projekte p
JOIN public.users u1 ON p.lehrer_id = u1.id
LEFT JOIN public.users u2 ON p.lehrer2_id = u2.id
WHERE p.status = 'veroeffentlicht';

-- WICHTIG: CREATE OR REPLACE VIEW ersetzt die reloptions vollständig.
-- In der Produktiv-DB läuft projekte_public bewusst mit DEFINER-Rechten
-- (security_invoker = false), damit der öffentliche, anonyme Lesezugriff auf
-- die veröffentlichten Projekte funktioniert (anon hat keine eigene RLS-
-- Leseregel auf projekte/users). Daher hier explizit auf false halten —
-- security_invoker = true würde die Schülerwahl-Anzeige für anon brechen
-- (alle Projekte verschwinden). Optionale Härtung später nur zusammen mit
-- passenden RLS-SELECT-Policies für anon.
ALTER VIEW public.projekte_public SET (security_invoker = false);

GRANT SELECT ON public.projekte_public TO anon, authenticated;

-- ------------------------------------------------------------
-- 3) RPC set_projekt_gesperrt — admin-guarded
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_projekt_gesperrt(
  p_id       UUID,
  p_gesperrt BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_projekt RECORD;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;
  IF p_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'id_fehlt');
  END IF;

  SELECT * INTO v_projekt FROM public.projekte WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_unbekannt');
  END IF;

  UPDATE public.projekte
     SET gesperrt = COALESCE(p_gesperrt, FALSE),
         updated_at = now()
   WHERE id = p_id;

  RETURN jsonb_build_object(
    'success', true,
    'id', p_id,
    'gesperrt', COALESCE(p_gesperrt, FALSE)
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

REVOKE ALL  ON FUNCTION public.set_projekt_gesperrt(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_projekt_gesperrt(UUID, BOOLEAN) TO authenticated;

-- ------------------------------------------------------------
-- 4) RPC admin_create_schueler — admin-guarded
--    Code-Format identisch zur Frontend-Funktion generateAnmeldeCode:
--    "<KLASSE_UPPER>-XXXX"  (XXXX aus [A-Z0-9])
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_create_schueler(
  p_vorname  TEXT,
  p_nachname TEXT,
  p_klasse   TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vorname  TEXT := TRIM(COALESCE(p_vorname, ''));
  v_nachname TEXT := TRIM(COALESCE(p_nachname, ''));
  v_klasse   TEXT := LOWER(TRIM(COALESCE(p_klasse, '')));
  v_stufe    INT;
  v_chars    TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  v_code     TEXT;
  v_suffix   TEXT;
  v_i        INT;
  v_try      INT := 0;
  v_exists   BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_eingeloggt');
  END IF;
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_berechtigt');
  END IF;

  IF v_vorname = '' OR v_nachname = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_fehlt');
  END IF;

  -- Klasse validieren: 5..9 + Buchstabe, oder 10 + Buchstabe
  IF v_klasse !~ '^(?:[5-9]|10)[a-z]$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'klasse_ungueltig',
      'hinweis', 'Format z.B. 7b oder 10a');
  END IF;

  v_stufe := (regexp_match(v_klasse, '^(\d+)'))[1]::INT;

  -- Duplikat-Check (gleicher Name + Klasse) → Warnung, aber kein harter Block
  SELECT EXISTS(
    SELECT 1 FROM public.schueler
     WHERE LOWER(vorname) = LOWER(v_vorname)
       AND LOWER(nachname) = LOWER(v_nachname)
       AND LOWER(klasse)   = v_klasse
  ) INTO v_exists;

  -- Eindeutigen Code erzeugen (max. 25 Versuche)
  LOOP
    v_try := v_try + 1;
    v_suffix := '';
    FOR v_i IN 1..4 LOOP
      v_suffix := v_suffix || substr(v_chars, floor(random() * length(v_chars))::INT + 1, 1);
    END LOOP;
    v_code := UPPER(v_klasse) || '-' || v_suffix;

    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.schueler WHERE code = v_code);
    IF v_try >= 25 THEN
      RETURN jsonb_build_object('success', false, 'error', 'code_kollision');
    END IF;
  END LOOP;

  INSERT INTO public.schueler (code, vorname, nachname, klasse, klassenstufe, aktiv)
  VALUES (v_code, v_vorname, v_nachname, v_klasse, v_stufe, TRUE);

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'vorname', v_vorname,
    'nachname', v_nachname,
    'klasse', v_klasse,
    'klassenstufe', v_stufe,
    'warnung', CASE WHEN v_exists THEN 'name_existiert_bereits' ELSE NULL END
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_create_schueler(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_schueler(TEXT, TEXT, TEXT) TO authenticated;

-- ------------------------------------------------------------
-- 5) Server-seitige Durchsetzung der Sperre (Trigger auf wahlen)
--    Unabhängig von der jeweiligen create_wahl-Version: verhindert,
--    dass eine Schüler-Wahl ein gesperrtes Projekt enthält — auch bei
--    direktem RPC-Aufruf / DOM-Tampering. Betrifft NUR Schüler-Wahlen
--    (Tabelle wahlen), nicht Admin-/Klassenlehrer-Zuteilungen (zuteilungen).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_wahl_nicht_gesperrt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.projekte
     WHERE id IN (NEW.erstwahl_id, NEW.zweitwahl_id, NEW.drittwahl_id)
       AND gesperrt = TRUE
  ) THEN
    RAISE EXCEPTION 'projekt_gesperrt'
      USING ERRCODE = 'check_violation',
            HINT = 'Mindestens ein gewähltes Projekt ist gesperrt.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wahl_nicht_gesperrt ON public.wahlen;
CREATE TRIGGER trg_wahl_nicht_gesperrt
  BEFORE INSERT ON public.wahlen
  FOR EACH ROW EXECUTE FUNCTION public.enforce_wahl_nicht_gesperrt();

COMMIT;

-- ------------------------------------------------------------
-- KONTROLLE (optional nach dem Lauf einzeln ausführen)
-- ------------------------------------------------------------
-- SELECT column_name, data_type, column_default
--   FROM information_schema.columns
--  WHERE table_name = 'projekte' AND column_name = 'gesperrt';
--
-- SELECT proname FROM pg_proc
--  WHERE proname IN ('set_projekt_gesperrt','admin_create_schueler');
--
-- Testlauf (als eingeloggter Admin):
-- SELECT public.admin_create_schueler('Test','Schüler','7b');
-- SELECT public.set_projekt_gesperrt('<projekt-uuid>', true);
