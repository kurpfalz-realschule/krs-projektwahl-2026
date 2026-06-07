-- ============================================================
-- KRS Projektwahl 2026 — v33 Migration
-- Zweck: Zwei Lehrkräfte pro Projekt + 12 Plätze je Lehrkraft
-- Datum: 2026-05-20
--
-- In Supabase SQL-Editor ausführen, bevor admin-dashboard-v2.html v33
-- deployed wird. Idempotent, bestehende Ein-Lehrer-Projekte bleiben gültig.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Datenmodell: optionale zweite Lehrkraft
-- ------------------------------------------------------------
ALTER TABLE public.projekte
  ADD COLUMN IF NOT EXISTS lehrer2_id UUID REFERENCES public.users(id);

CREATE INDEX IF NOT EXISTS idx_projekte_lehrer2 ON public.projekte(lehrer2_id);

ALTER TABLE public.projekte
  DROP CONSTRAINT IF EXISTS projekte_unterschiedliche_lehrer_check;

ALTER TABLE public.projekte
  ADD CONSTRAINT projekte_unterschiedliche_lehrer_check
  CHECK (lehrer2_id IS NULL OR lehrer2_id <> lehrer_id);

-- Neue/aktualisierte Zeilen: 12 Plätze pro Lehrkraft.
-- NOT VALID verhindert, dass evtl. alte Bestandsdaten die Migration blockieren.
ALTER TABLE public.projekte
  DROP CONSTRAINT IF EXISTS projekte_max_plaetze_lehrer_check;

ALTER TABLE public.projekte
  ADD CONSTRAINT projekte_max_plaetze_lehrer_check
  CHECK (max_plaetze <= CASE WHEN lehrer2_id IS NULL THEN 12 ELSE 24 END)
  NOT VALID;

-- ------------------------------------------------------------
-- 2. Views: Lehrkraft-Namen zusammenführen
-- ------------------------------------------------------------
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
  u2.name AS lehrer2_name
FROM public.projekte p
JOIN public.users u1 ON p.lehrer_id = u1.id
LEFT JOIN public.users u2 ON p.lehrer2_id = u2.id
WHERE p.status = 'veroeffentlicht';

CREATE OR REPLACE VIEW public.projekte_stats AS
SELECT
  p.id,
  p.titel,
  p.max_plaetze,
  p.min_teilnehmer,
  NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name,
  COUNT(DISTINCT z.schueler_code) AS belegt,
  p.max_plaetze - COUNT(DISTINCT z.schueler_code) AS frei,
  COUNT(DISTINCT w1.schueler_code) AS erstwahl_wuensche,
  COUNT(DISTINCT w2.schueler_code) AS zweitwahl_wuensche,
  COUNT(DISTINCT w3.schueler_code) AS drittwahl_wuensche,
  COUNT(DISTINCT w1.schueler_code) + COUNT(DISTINCT w2.schueler_code) + COUNT(DISTINCT w3.schueler_code) AS gesamt_wuensche,
  u1.name AS lehrer1_name,
  u2.name AS lehrer2_name
FROM public.projekte p
JOIN public.users u1 ON p.lehrer_id = u1.id
LEFT JOIN public.users u2 ON p.lehrer2_id = u2.id
LEFT JOIN public.zuteilungen z ON z.projekt_id = p.id
LEFT JOIN public.wahlen w1 ON w1.erstwahl_id = p.id
LEFT JOIN public.wahlen w2 ON w2.zweitwahl_id = p.id
LEFT JOIN public.wahlen w3 ON w3.drittwahl_id = p.id
WHERE p.status = 'veroeffentlicht'
GROUP BY p.id, p.titel, p.max_plaetze, p.min_teilnehmer, u1.name, u2.name;

CREATE OR REPLACE VIEW public.zuteilungen_detail AS
SELECT
  z.id,
  z.schueler_code,
  s.vorname,
  s.nachname,
  s.klasse,
  s.klassenstufe,
  z.projekt_id,
  p.titel AS projekt_titel,
  NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name,
  z.wahl_nr,
  z.updated_at,
  u1.name AS lehrer1_name,
  u2.name AS lehrer2_name
FROM public.zuteilungen z
JOIN public.schueler s ON z.schueler_code = s.code
LEFT JOIN public.projekte p ON z.projekt_id = p.id
LEFT JOIN public.users u1 ON p.lehrer_id = u1.id
LEFT JOIN public.users u2 ON p.lehrer2_id = u2.id;

-- ------------------------------------------------------------
-- 3. Schüler-Status-RPC: Ergebnis zeigt beide Lehrkräfte
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
-- 4. Projektlehrer-Rechte: beide zugeordneten Lehrkräfte gelten als "eigene"
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.projekt_belongs_to_current_app_user(
  p_lehrer_id UUID,
  p_lehrer2_id UUID DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_app_user_id() IS NOT NULL
     AND public.current_app_user_id() IN (p_lehrer_id, p_lehrer2_id);
$$;

GRANT EXECUTE ON FUNCTION public.projekt_belongs_to_current_app_user(UUID, UUID) TO authenticated;

DROP POLICY IF EXISTS "projektlehrer_select_eigene_projekte" ON public.projekte;
CREATE POLICY "projektlehrer_select_eigene_projekte"
  ON public.projekte FOR SELECT
  TO authenticated
  USING (
    public.is_projektlehrer()
    AND public.projekt_belongs_to_current_app_user(lehrer_id, lehrer2_id)
  );

DROP POLICY IF EXISTS "projektlehrer_insert_eigene_projekte" ON public.projekte;
CREATE POLICY "projektlehrer_insert_eigene_projekte"
  ON public.projekte FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_projektlehrer()
    AND lehrer_id = public.current_app_user_id()
    AND lehrer2_id IS NULL
  );

DROP POLICY IF EXISTS "projektlehrer_update_eigene_projekte" ON public.projekte;
CREATE POLICY "projektlehrer_update_eigene_projekte"
  ON public.projekte FOR UPDATE
  TO authenticated
  USING (
    public.is_projektlehrer()
    AND public.projekt_belongs_to_current_app_user(lehrer_id, lehrer2_id)
  )
  WITH CHECK (
    public.is_projektlehrer()
    AND public.projekt_belongs_to_current_app_user(lehrer_id, lehrer2_id)
  );

CREATE OR REPLACE FUNCTION public.enforce_projektlehrer_whitelist()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_lehrer boolean;
  v_is_admin  boolean;
  v_is_pl     boolean;
  v_self_id   uuid;
BEGIN
  v_is_admin := public.is_admin();
  v_is_pl    := public.is_projektleitung();
  IF v_is_admin OR v_is_pl THEN
    RETURN NEW;
  END IF;

  v_is_lehrer := public.is_projektlehrer();
  IF NOT v_is_lehrer THEN
    RETURN NEW;
  END IF;

  v_self_id := public.current_app_user_id();
  IF v_self_id IS NULL THEN
    RAISE EXCEPTION 'Projektlehrer-Trigger: kein App-User-Eintrag gefunden';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status := 'entwurf';
    NEW.lehrer_id := v_self_id;
    NEW.lehrer2_id := NULL;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.lehrer_id IS DISTINCT FROM OLD.lehrer_id THEN
      RAISE EXCEPTION 'Projektlehrer dürfen lehrer_id nicht ändern';
    END IF;
    IF NEW.lehrer2_id IS DISTINCT FROM OLD.lehrer2_id THEN
      RAISE EXCEPTION 'Projektlehrer dürfen lehrer2_id nicht ändern';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'Projektlehrer dürfen status nicht ändern';
    END IF;
    IF NEW.min_klasse IS DISTINCT FROM OLD.min_klasse THEN
      RAISE EXCEPTION 'Projektlehrer dürfen min_klasse nicht ändern';
    END IF;
    IF NEW.max_klasse IS DISTINCT FROM OLD.max_klasse THEN
      RAISE EXCEPTION 'Projektlehrer dürfen max_klasse nicht ändern';
    END IF;
    IF NEW.min_teilnehmer IS DISTINCT FROM OLD.min_teilnehmer THEN
      RAISE EXCEPTION 'Projektlehrer dürfen min_teilnehmer nicht ändern';
    END IF;
    IF NEW.max_plaetze IS DISTINCT FROM OLD.max_plaetze THEN
      RAISE EXCEPTION 'Projektlehrer dürfen max_plaetze nicht ändern';
    END IF;
    NEW.created_at := OLD.created_at;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_projekte_lehrer_whitelist ON public.projekte;
CREATE TRIGGER trg_projekte_lehrer_whitelist
  BEFORE INSERT OR UPDATE ON public.projekte
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_projektlehrer_whitelist();

-- Projektlehrer sehen Teilnehmerlisten für beide Rollen im Projekt.
DROP POLICY IF EXISTS "Projektlehrer sehen eigene Teilnehmer" ON public.zuteilungen;
CREATE POLICY "Projektlehrer sehen eigene Teilnehmer"
  ON public.zuteilungen FOR SELECT
  TO authenticated
  USING (
    public.is_projektlehrer()
    AND EXISTS (
      SELECT 1
      FROM public.projekte p
      WHERE p.id = zuteilungen.projekt_id
        AND public.projekt_belongs_to_current_app_user(p.lehrer_id, p.lehrer2_id)
    )
  );

-- Storage-Helper: Bildpfad gehört zu Projekt von Lehrer 1 oder Lehrer 2.
CREATE OR REPLACE FUNCTION public.storage_path_belongs_to_lehrer(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_self uuid;
  v_pid  text;
  v_ok   boolean;
BEGIN
  v_self := public.current_app_user_id();
  IF v_self IS NULL THEN
    RETURN false;
  END IF;
  IF p_name !~ '^projekte/[0-9a-fA-F-]+\.[a-zA-Z0-9]+$' THEN
    RETURN false;
  END IF;
  v_pid := substring(p_name FROM 'projekte/([0-9a-fA-F-]+)\.[a-zA-Z0-9]+$');
  IF v_pid IS NULL THEN
    RETURN false;
  END IF;
  SELECT public.projekt_belongs_to_current_app_user(p.lehrer_id, p.lehrer2_id)
    INTO v_ok
    FROM public.projekte p
   WHERE p.id::text = v_pid;
  RETURN COALESCE(v_ok, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.storage_path_belongs_to_lehrer(text) TO authenticated;

-- ============================================================
-- ENDE v33-Migration
-- ============================================================
