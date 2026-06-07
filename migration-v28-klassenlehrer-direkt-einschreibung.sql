-- ============================================================
-- KRS Projektwahl 2026 — v28 Migration (Sprint E1.5)
-- Zweck: Klassenlehrer dürfen Schüler ihrer eigenen Klasse direkt
--        einem veröffentlichten Projekt zuweisen.
-- Datum: 2026-04-27
--
-- WICHTIG: In Supabase SQL-Editor als Ganzes ausführen.
-- Alle Statements sind idempotent (CREATE OR REPLACE / DROP IF EXISTS).
--
-- Voraussetzungen aus v24/v25:
--   - Helper public.is_admin(), public.is_projektleitung(),
--     public.current_app_user_id() existieren.
--   - users.klassenlehrer_von ist gefüllt (TEXT, z.B. '7a').
--
-- Effekt:
--   - Neuer Helper public.is_klassenlehrer().
--   - Neue RPCs:
--       klassenlehrer_assign_schueler(p_schueler_code text, p_projekt_id uuid)
--       klassenlehrer_unassign_schueler(p_schueler_code text)
--     beide prüfen serverseitig, dass der Schüler in der eigenen Klasse ist
--     und das Projekt veröffentlicht ist. SECURITY DEFINER, nur authenticated.
--   - SELECT-Policies, damit getCurrentDbUser() + KlassenlehrerView im Live-
--     Mode überhaupt Daten lesen können (eigene users-Row, eigene Klasse,
--     deren zuteilungen).
--   - Bewusst KEIN GRANT auf anon — die RPCs sind nur für eingeloggte User.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Helper-Funktion: is_klassenlehrer()
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_klassenlehrer()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.auth_user_id = auth.uid()
      AND u.rolle = 'klassenlehrer'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_klassenlehrer() TO authenticated;

-- ------------------------------------------------------------
-- 2. Helper-Funktion: current_klassenlehrer_klasse()
-- ------------------------------------------------------------
-- Liefert die Klasse (TEXT, lower-cased) des eingeloggten Klassenlehrers
-- oder NULL. Wird von RPCs und RLS-Policies genutzt.
CREATE OR REPLACE FUNCTION public.current_klassenlehrer_klasse()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT LOWER(TRIM(u.klassenlehrer_von))
    FROM public.users u
    WHERE u.auth_user_id = auth.uid()
      AND u.rolle = 'klassenlehrer'
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.current_klassenlehrer_klasse() TO authenticated;

-- ------------------------------------------------------------
-- 3. RPC: klassenlehrer_assign_schueler
-- ------------------------------------------------------------
-- Schreibt/aktualisiert eine zuteilungen-Zeile für einen Schüler aus der
-- Klasse des Klassenlehrers. Überbuchung wird (wie bei update_zuteilung)
-- erlaubt aber im Result-Objekt geflagged. Klassenstufe wird geprüft.
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
  -- 1) Caller muss Klassenlehrer sein
  IF NOT public.is_klassenlehrer() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_klassenlehrer');
  END IF;

  v_caller_id := public.current_app_user_id();
  v_caller_klasse := public.current_klassenlehrer_klasse();
  IF v_caller_klasse IS NULL OR v_caller_klasse = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'keine_klasse_zugeordnet');
  END IF;

  -- 2) Inputs normalisieren / prüfen
  v_code := UPPER(TRIM(COALESCE(p_schueler_code, '')));
  IF v_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_code_leer');
  END IF;
  IF p_projekt_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_id_leer');
  END IF;

  -- 3) Schüler existiert + ist in eigener Klasse
  SELECT * INTO v_schueler FROM public.schueler WHERE code = v_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_unbekannt', 'code', v_code);
  END IF;
  IF LOWER(TRIM(v_schueler.klasse)) <> v_caller_klasse THEN
    RETURN jsonb_build_object('success', false, 'error', 'fremde_klasse');
  END IF;

  -- 4) Projekt veröffentlicht?
  SELECT * INTO v_projekt
    FROM public.projekte
   WHERE id = p_projekt_id AND status = 'veroeffentlicht';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'projekt_unbekannt_oder_unveroeffentlicht');
  END IF;

  -- 5) Klassenstufe muss in den Projekt-Range passen
  IF v_schueler.klassenstufe < v_projekt.min_klasse
     OR v_schueler.klassenstufe > v_projekt.max_klasse THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'klassenstufe_ausserhalb',
      'min_klasse', v_projekt.min_klasse,
      'max_klasse', v_projekt.max_klasse
    );
  END IF;

  -- 6) Belegung zählen (ohne den Schüler selbst — wenn der hier schon drin ist)
  SELECT COUNT(*) INTO v_belegt
    FROM public.zuteilungen
   WHERE projekt_id = p_projekt_id
     AND schueler_code <> v_code;
  v_ueberbucht := v_belegt >= v_projekt.max_plaetze;

  -- 7) Insert/Update
  SELECT * INTO v_alte FROM public.zuteilungen WHERE schueler_code = v_code;
  IF FOUND THEN
    UPDATE public.zuteilungen
       SET projekt_id = p_projekt_id,
           wahl_nr = NULL,
           zugewiesen_von = v_caller_id,
           kommentar = TRIM(BOTH ' |' FROM COALESCE(kommentar, '') || ' | Direkt durch Klassenlehrer ('
                                       || to_char(now(), 'YYYY-MM-DD') || ')'),
           updated_at = now()
     WHERE schueler_code = v_code;
  ELSE
    INSERT INTO public.zuteilungen (schueler_code, projekt_id, wahl_nr, zugewiesen_von, kommentar)
    VALUES (
      v_code, p_projekt_id, NULL, v_caller_id,
      'Direkt durch Klassenlehrer (' || to_char(now(), 'YYYY-MM-DD') || ')'
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
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.klassenlehrer_assign_schueler(TEXT, UUID) TO authenticated;

-- ------------------------------------------------------------
-- 4. RPC: klassenlehrer_unassign_schueler
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.klassenlehrer_unassign_schueler(
  p_schueler_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_klasse TEXT;
  v_code         TEXT;
  v_schueler     RECORD;
BEGIN
  IF NOT public.is_klassenlehrer() THEN
    RETURN jsonb_build_object('success', false, 'error', 'nicht_klassenlehrer');
  END IF;

  v_caller_klasse := public.current_klassenlehrer_klasse();
  IF v_caller_klasse IS NULL OR v_caller_klasse = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'keine_klasse_zugeordnet');
  END IF;

  v_code := UPPER(TRIM(COALESCE(p_schueler_code, '')));
  IF v_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_code_leer');
  END IF;

  SELECT * INTO v_schueler FROM public.schueler WHERE code = v_code;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'schueler_unbekannt', 'code', v_code);
  END IF;
  IF LOWER(TRIM(v_schueler.klasse)) <> v_caller_klasse THEN
    RETURN jsonb_build_object('success', false, 'error', 'fremde_klasse');
  END IF;

  DELETE FROM public.zuteilungen WHERE schueler_code = v_code;

  RETURN jsonb_build_object('success', true, 'schueler_code', v_code);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.klassenlehrer_unassign_schueler(TEXT) TO authenticated;

-- ------------------------------------------------------------
-- 5. RLS: SELECT-Policies, damit der Klassenlehrer im Live-Mode lesen darf
-- ------------------------------------------------------------
-- 5a) eigene users-Zeile (analog v25 projektlehrer_select_self)
DROP POLICY IF EXISTS "klassenlehrer_select_self" ON public.users;
CREATE POLICY "klassenlehrer_select_self"
  ON public.users FOR SELECT
  TO authenticated
  USING (
    public.is_klassenlehrer()
    AND auth_user_id = auth.uid()
  );

-- 5b) Schüler der eigenen Klasse
DROP POLICY IF EXISTS "klassenlehrer_select_eigene_klasse" ON public.schueler;
CREATE POLICY "klassenlehrer_select_eigene_klasse"
  ON public.schueler FOR SELECT
  TO authenticated
  USING (
    public.is_klassenlehrer()
    AND LOWER(TRIM(klasse)) = public.current_klassenlehrer_klasse()
  );

-- 5c) Zuteilungen der Schüler der eigenen Klasse
DROP POLICY IF EXISTS "klassenlehrer_select_zuteilungen_eigene_klasse" ON public.zuteilungen;
CREATE POLICY "klassenlehrer_select_zuteilungen_eigene_klasse"
  ON public.zuteilungen FOR SELECT
  TO authenticated
  USING (
    public.is_klassenlehrer()
    AND EXISTS (
      SELECT 1 FROM public.schueler s
      WHERE s.code = zuteilungen.schueler_code
        AND LOWER(TRIM(s.klasse)) = public.current_klassenlehrer_klasse()
    )
  );

-- (INSERT/UPDATE/DELETE auf zuteilungen läuft ausschließlich über die
--  obigen RPCs — keine direkten DML-Policies für klassenlehrer.)

-- ------------------------------------------------------------
-- 6. Sanity-Checks (auskommentiert)
-- ------------------------------------------------------------
-- SELECT routine_name FROM information_schema.routines
--   WHERE routine_schema='public'
--     AND routine_name IN ('is_klassenlehrer','current_klassenlehrer_klasse',
--                          'klassenlehrer_assign_schueler','klassenlehrer_unassign_schueler');
--
-- SELECT policyname, tablename FROM pg_policies
--   WHERE schemaname='public' AND policyname LIKE 'klassenlehrer_%'
--   ORDER BY tablename, policyname;

-- ============================================================
-- ENDE v28-Migration
-- ============================================================
