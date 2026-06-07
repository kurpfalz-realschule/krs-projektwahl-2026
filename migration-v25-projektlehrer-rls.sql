-- ============================================================
-- KRS Projektwahl 2026 — v25 Migration
-- Zweck: Projektlehrer-Self-Service (RLS + Spalten-Whitelist via Trigger)
-- Datum: 2026-04-25
--
-- WICHTIG: In Supabase SQL-Editor als Ganzes ausführen.
-- Alle Statements sind idempotent (CREATE OR REPLACE / DROP IF EXISTS).
--
-- Voraussetzungen aus v24:
--   - Helper-Funktionen public.is_admin(), public.is_projektleitung(),
--     public.is_app_user() existieren bereits.
--   - users.auth_user_id verknüpft public.users.id mit auth.users.id.
--   - Storage-Bucket 'projekt-bilder' existiert mit Admin/Projektleitung-Policies.
--
-- Effekt:
--   - Projektlehrer sehen nur eigene Projekte (lehrer_id = own user id).
--   - Projektlehrer können eigene Projekte editieren — ABER nur die
--     erlaubten Felder (titel, kurzbeschreibung, langbeschreibung, ort, bild_url).
--   - Projektlehrer können neue Projekte als status='entwurf' anlegen
--     (Trigger erzwingt das, egal was der Client schickt).
--   - Projektlehrer können Bilder zu eigenen Projekten hochladen/löschen.
--   - super_admin und projektleitung bleiben uneingeschränkt.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Helper-Funktion: is_projektlehrer()
-- ------------------------------------------------------------
-- Gibt TRUE zurück, wenn der aktuelle auth-User in der users-Tabelle
-- die Rolle 'projektlehrer' hat (kein super_admin, kein projektleitung).
CREATE OR REPLACE FUNCTION public.is_projektlehrer()
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
      AND u.rolle = 'projektlehrer'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_projektlehrer() TO authenticated;

-- ------------------------------------------------------------
-- 2. Helper-Funktion: current_app_user_id()
-- ------------------------------------------------------------
-- Liefert die public.users.id (App-User-PK) des aktuell eingeloggten Users
-- oder NULL, wenn kein App-User-Eintrag existiert.
-- Wird vom Whitelist-Trigger und den projektlehrer-RLS-Policies genutzt.
CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id
  FROM public.users u
  WHERE u.auth_user_id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated;

-- ------------------------------------------------------------
-- 3. RLS-Policies: projektlehrer auf projekte
-- ------------------------------------------------------------
-- Strategie: Eigene CRUD-Policies für die Rolle projektlehrer, die
-- ausschließlich auf Datensätze mit lehrer_id = current_app_user_id()
-- greifen. Bestehende Admin-/Projektleitung-Policies bleiben unverändert.

-- ---- SELECT eigene ----
DROP POLICY IF EXISTS "projektlehrer_select_eigene_projekte" ON public.projekte;
CREATE POLICY "projektlehrer_select_eigene_projekte"
  ON public.projekte FOR SELECT
  TO authenticated
  USING (
    public.is_projektlehrer()
    AND lehrer_id = public.current_app_user_id()
  );

-- ---- INSERT eigene (Trigger erzwingt status=entwurf + lehrer_id=self) ----
DROP POLICY IF EXISTS "projektlehrer_insert_eigene_projekte" ON public.projekte;
CREATE POLICY "projektlehrer_insert_eigene_projekte"
  ON public.projekte FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_projektlehrer()
    AND lehrer_id = public.current_app_user_id()
  );

-- ---- UPDATE eigene (Trigger erzwingt Spalten-Whitelist) ----
DROP POLICY IF EXISTS "projektlehrer_update_eigene_projekte" ON public.projekte;
CREATE POLICY "projektlehrer_update_eigene_projekte"
  ON public.projekte FOR UPDATE
  TO authenticated
  USING (
    public.is_projektlehrer()
    AND lehrer_id = public.current_app_user_id()
  )
  WITH CHECK (
    public.is_projektlehrer()
    AND lehrer_id = public.current_app_user_id()
  );

-- Bewusst KEIN DELETE für projektlehrer — Löschungen bleiben bei Projektleitung.

-- ------------------------------------------------------------
-- 4. Spalten-Whitelist via Trigger
-- ------------------------------------------------------------
-- Postgres-RLS kennt keine Spalten-Granularität bei UPDATE — daher prüfen
-- wir per BEFORE INSERT/UPDATE-Trigger, ob ein projektlehrer (und NUR der)
-- nur die erlaubten Felder ändert.
--
-- Erlaubte Felder beim UPDATE für projektlehrer:
--   titel, kurzbeschreibung, langbeschreibung, ort, bild_url
-- Beim INSERT werden status, lehrer_id zwangsgesetzt.

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
  -- super_admin / projektleitung sind unbeschränkt — Trigger ist Rolle-spezifisch.
  v_is_admin := public.is_admin();
  v_is_pl    := public.is_projektleitung();
  IF v_is_admin OR v_is_pl THEN
    RETURN NEW;
  END IF;

  v_is_lehrer := public.is_projektlehrer();
  IF NOT v_is_lehrer THEN
    -- Andere Rollen / nicht-Lehrer: Trigger nicht zuständig.
    -- (RLS-Policies entscheiden, ob die Aktion überhaupt durchkommt.)
    RETURN NEW;
  END IF;

  v_self_id := public.current_app_user_id();
  IF v_self_id IS NULL THEN
    RAISE EXCEPTION 'Projektlehrer-Trigger: kein App-User-Eintrag gefunden';
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- Egal was der Client schickt: Status zurücksetzen, lehrer_id auf self setzen.
    NEW.status := 'entwurf';
    NEW.lehrer_id := v_self_id;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Whitelist: alle anderen Felder müssen unverändert bleiben.
    IF NEW.lehrer_id IS DISTINCT FROM OLD.lehrer_id THEN
      RAISE EXCEPTION 'Projektlehrer dürfen lehrer_id nicht ändern';
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
    -- created_at darf nie überschrieben werden
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

-- ------------------------------------------------------------
-- 5. RLS-Policy: projektlehrer darf eigene users-Zeile lesen
-- ------------------------------------------------------------
-- getCurrentDbUser() im Frontend selektiert public.users where auth_user_id = auth.uid().
-- Ohne SELECT-Policy würde RLS das blockieren → der Role-Guard im Frontend
-- bekäme NULL und der Lehrer wäre quasi "nicht freigeschaltet".
DROP POLICY IF EXISTS "projektlehrer_select_self" ON public.users;
CREATE POLICY "projektlehrer_select_self"
  ON public.users FOR SELECT
  TO authenticated
  USING (
    public.is_projektlehrer()
    AND auth_user_id = auth.uid()
  );

-- ------------------------------------------------------------
-- 6. Storage-Policies: projektlehrer darf Bilder eigener Projekte
-- ------------------------------------------------------------
-- Bild-Pfad-Konvention (Frontend): projekte/<projekt_id>.<ext>
-- → wir matchen anhand des Pfads gegen die projekte-Tabelle.

-- Helper: prüft, ob der Storage-Pfad zum projektlehrer gehört.
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
  v_proj_owner uuid;
BEGIN
  v_self := public.current_app_user_id();
  IF v_self IS NULL THEN
    RETURN false;
  END IF;
  -- erwartet "projekte/<uuid>.<ext>"
  IF p_name !~ '^projekte/[0-9a-fA-F-]+\.[a-zA-Z0-9]+$' THEN
    RETURN false;
  END IF;
  v_pid := substring(p_name FROM 'projekte/([0-9a-fA-F-]+)\.[a-zA-Z0-9]+$');
  IF v_pid IS NULL THEN
    RETURN false;
  END IF;
  SELECT p.lehrer_id INTO v_proj_owner
    FROM public.projekte p
    WHERE p.id::text = v_pid;
  RETURN v_proj_owner = v_self;
END;
$$;

GRANT EXECUTE ON FUNCTION public.storage_path_belongs_to_lehrer(text) TO authenticated;

-- INSERT: Projektlehrer darf hochladen, wenn der Pfad seinem Projekt entspricht
DROP POLICY IF EXISTS "projekt_bilder_lehrer_insert" ON storage.objects;
CREATE POLICY "projekt_bilder_lehrer_insert"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'projekt-bilder'
    AND public.is_projektlehrer()
    AND public.storage_path_belongs_to_lehrer(name)
  );

-- UPDATE: dito (Overwrite via upsert: true im Frontend)
DROP POLICY IF EXISTS "projekt_bilder_lehrer_update" ON storage.objects;
CREATE POLICY "projekt_bilder_lehrer_update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'projekt-bilder'
    AND public.is_projektlehrer()
    AND public.storage_path_belongs_to_lehrer(name)
  )
  WITH CHECK (
    bucket_id = 'projekt-bilder'
    AND public.is_projektlehrer()
    AND public.storage_path_belongs_to_lehrer(name)
  );

-- DELETE: dito
DROP POLICY IF EXISTS "projekt_bilder_lehrer_delete" ON storage.objects;
CREATE POLICY "projekt_bilder_lehrer_delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'projekt-bilder'
    AND public.is_projektlehrer()
    AND public.storage_path_belongs_to_lehrer(name)
  );

-- (SELECT bleibt 'projekt_bilder_public_select' aus v24 — Bilder sind öffentlich sichtbar.)

-- ------------------------------------------------------------
-- 7. Auto-Link auth.users.id ↔ public.users.auth_user_id
-- ------------------------------------------------------------
-- Damit Norbert/Nadine Lehrer einladen können, ohne danach jedes Mal in die
-- Supabase-Auth-Konsole zu müssen, um auth_user_id zu setzen:
-- Bei jedem neuen auth.users-INSERT (passiert bei Magic-Link-Erstklick oder
-- inviteUserByEmail) suchen wir per E-Mail einen existierenden public.users-
-- Eintrag und verknüpfen automatisch. Match ist case-insensitive.

CREATE OR REPLACE FUNCTION public.auto_link_app_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.email IS NULL THEN
    RETURN NEW;
  END IF;
  UPDATE public.users
    SET auth_user_id = NEW.id
    WHERE LOWER(email) = LOWER(NEW.email)
      AND auth_user_id IS NULL;
  RETURN NEW;
END;
$$;

-- Trigger auf auth.users (System-Schema, deshalb explizit qualifiziert)
DROP TRIGGER IF EXISTS trg_auto_link_app_user ON auth.users;
CREATE TRIGGER trg_auto_link_app_user
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_link_app_user();

-- Bonus: Backfill für bereits angelegte auth.users (z.B. Nadine), die nicht verknüpft sind.
-- Idempotent — passiert nur, wenn auth_user_id NULL ist und exakter E-Mail-Match existiert.
UPDATE public.users u
   SET auth_user_id = a.id
  FROM auth.users a
  WHERE u.auth_user_id IS NULL
    AND LOWER(u.email) = LOWER(a.email);

-- ------------------------------------------------------------
-- 8. Sanity-Checks (auskommentiert — bei Bedarf einzeln ausführen)
-- ------------------------------------------------------------
--
-- -- Helper-Funktionen vorhanden?
-- SELECT routine_name FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name IN ('is_admin','is_projektleitung','is_projektlehrer','is_app_user',
--                          'current_app_user_id','enforce_projektlehrer_whitelist',
--                          'storage_path_belongs_to_lehrer');
--
-- -- Projektlehrer-Policies da?
-- SELECT policyname, tablename FROM pg_policies
--   WHERE schemaname = 'public'
--     AND policyname LIKE 'projektlehrer_%'
--   ORDER BY tablename, policyname;
--
-- -- Trigger registriert?
-- SELECT tgname, tgrelid::regclass FROM pg_trigger
--   WHERE tgname = 'trg_projekte_lehrer_whitelist';
--
-- -- Storage-Policies für projektlehrer da?
-- SELECT policyname FROM pg_policies
--   WHERE schemaname = 'storage'
--     AND tablename = 'objects'
--     AND policyname LIKE 'projekt_bilder_lehrer_%';
--
-- -- Auto-Link-Trigger registriert?
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_auto_link_app_user';
--
-- -- Wie viele users.auth_user_id sind verknüpft?
-- SELECT COUNT(*) FILTER (WHERE auth_user_id IS NOT NULL) AS verknuepft,
--        COUNT(*) FILTER (WHERE auth_user_id IS NULL)     AS offen
--   FROM public.users;

-- ============================================================
-- ENDE v25-Migration
-- ============================================================
