-- ============================================================
-- KRS Projektwahl 2026 — v24 Migration
-- Zweck: Nadine-Flow (projektleitung-Rolle) + Projekt-Bilder-Storage
-- Datum: 2026-04-24
--
-- WICHTIG: In Supabase SQL-Editor als Ganzes ausführen.
-- Alle Statements sind idempotent (CREATE OR REPLACE / DROP IF EXISTS).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Helper-Funktion: is_projektleitung()
-- ------------------------------------------------------------
-- Gibt TRUE zurück, wenn der aktuelle auth-User in der users-Tabelle
-- die Rolle 'projektleitung' hat.
CREATE OR REPLACE FUNCTION public.is_projektleitung()
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
      AND u.rolle = 'projektleitung'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_projektleitung() TO authenticated;

-- ------------------------------------------------------------
-- 2. Helper-Funktion: is_app_user()
-- ------------------------------------------------------------
-- Gibt TRUE zurück, wenn der aktuelle auth-User überhaupt einen
-- users-Eintrag hat (also berechtigt ist, die App zu nutzen).
-- Ersetzt den is_admin()-Check im Gate.
CREATE OR REPLACE FUNCTION public.is_app_user()
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
      AND u.rolle IN ('super_admin', 'projektleitung', 'klassenlehrer', 'projektlehrer')
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_app_user() TO authenticated;

-- ------------------------------------------------------------
-- 3. RLS-Policies: projektleitung darf wie super_admin arbeiten
-- ------------------------------------------------------------
-- Strategie: Wir erweitern die bestehenden is_admin()-Policies durch
-- zusätzliche projektleitung-Policies. Alte Policies bleiben unverändert.

-- ---- projekte: volle CRUD für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_projekte" ON public.projekte;
CREATE POLICY "projektleitung_select_projekte"
  ON public.projekte FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

DROP POLICY IF EXISTS "projektleitung_insert_projekte" ON public.projekte;
CREATE POLICY "projektleitung_insert_projekte"
  ON public.projekte FOR INSERT
  TO authenticated
  WITH CHECK (public.is_projektleitung());

DROP POLICY IF EXISTS "projektleitung_update_projekte" ON public.projekte;
CREATE POLICY "projektleitung_update_projekte"
  ON public.projekte FOR UPDATE
  TO authenticated
  USING (public.is_projektleitung())
  WITH CHECK (public.is_projektleitung());

DROP POLICY IF EXISTS "projektleitung_delete_projekte" ON public.projekte;
CREATE POLICY "projektleitung_delete_projekte"
  ON public.projekte FOR DELETE
  TO authenticated
  USING (public.is_projektleitung());

-- ---- users: SELECT für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_users" ON public.users;
CREATE POLICY "projektleitung_select_users"
  ON public.users FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- ---- schueler: SELECT für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_schueler" ON public.schueler;
CREATE POLICY "projektleitung_select_schueler"
  ON public.schueler FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- ---- zuteilungen: SELECT für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_zuteilungen" ON public.zuteilungen;
CREATE POLICY "projektleitung_select_zuteilungen"
  ON public.zuteilungen FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- ---- tauschwuensche: SELECT für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_tauschwuensche" ON public.tauschwuensche;
CREATE POLICY "projektleitung_select_tauschwuensche"
  ON public.tauschwuensche FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- ---- wahlen: SELECT für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_wahlen" ON public.wahlen;
CREATE POLICY "projektleitung_select_wahlen"
  ON public.wahlen FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- ---- verteilungen: SELECT für projektleitung ----
DROP POLICY IF EXISTS "projektleitung_select_verteilungen" ON public.verteilungen;
CREATE POLICY "projektleitung_select_verteilungen"
  ON public.verteilungen FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- ---- system_settings: SELECT (alle), UPDATE nur phase-Key ----
DROP POLICY IF EXISTS "projektleitung_select_system_settings" ON public.system_settings;
CREATE POLICY "projektleitung_select_system_settings"
  ON public.system_settings FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

-- Bewusst KEIN UPDATE auf system_settings für projektleitung — nur super_admin ändert Phase.

-- ---- feedback: SELECT + UPDATE für projektleitung (Mark-as-done) ----
-- (Tabelle existiert seit v23)
DROP POLICY IF EXISTS "projektleitung_select_feedback" ON public.feedback;
CREATE POLICY "projektleitung_select_feedback"
  ON public.feedback FOR SELECT
  TO authenticated
  USING (public.is_projektleitung());

DROP POLICY IF EXISTS "projektleitung_update_feedback" ON public.feedback;
CREATE POLICY "projektleitung_update_feedback"
  ON public.feedback FOR UPDATE
  TO authenticated
  USING (public.is_projektleitung())
  WITH CHECK (public.is_projektleitung());

-- ------------------------------------------------------------
-- 4. Storage-Bucket: projekt-bilder
-- ------------------------------------------------------------
-- Public-Read, Authenticated-Write (für Admin + Projektleitung)
-- Bilder werden als Projekt-Cover unter /projekte/<projekt_id>.<ext> abgelegt.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'projekt-bilder',
  'projekt-bilder',
  true,
  5242880, -- 5 MB pro Bild
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ---- Storage-Policies für projekt-bilder ----

-- SELECT: Jeder darf Bilder lesen (public-Bucket, aber Policies müssen trotzdem stimmen)
DROP POLICY IF EXISTS "projekt_bilder_public_select" ON storage.objects;
CREATE POLICY "projekt_bilder_public_select"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'projekt-bilder');

-- INSERT: Admin + Projektleitung dürfen Bilder hochladen
DROP POLICY IF EXISTS "projekt_bilder_admin_insert" ON storage.objects;
CREATE POLICY "projekt_bilder_admin_insert"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'projekt-bilder'
    AND (public.is_admin() OR public.is_projektleitung())
  );

-- UPDATE: Admin + Projektleitung (z.B. Overwrite)
DROP POLICY IF EXISTS "projekt_bilder_admin_update" ON storage.objects;
CREATE POLICY "projekt_bilder_admin_update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'projekt-bilder'
    AND (public.is_admin() OR public.is_projektleitung())
  )
  WITH CHECK (
    bucket_id = 'projekt-bilder'
    AND (public.is_admin() OR public.is_projektleitung())
  );

-- DELETE: Admin + Projektleitung
DROP POLICY IF EXISTS "projekt_bilder_admin_delete" ON storage.objects;
CREATE POLICY "projekt_bilder_admin_delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'projekt-bilder'
    AND (public.is_admin() OR public.is_projektleitung())
  );

-- ------------------------------------------------------------
-- 5. Sanity-Checks (nur Anzeige — keine Änderungen)
-- ------------------------------------------------------------
-- Diese Queries auskommentieren und einzeln ausführen, falls gewünscht:
--
-- SELECT routine_name FROM information_schema.routines
--   WHERE routine_schema = 'public' AND routine_name IN ('is_admin','is_projektleitung','is_app_user');
--
-- SELECT policyname, tablename FROM pg_policies
--   WHERE schemaname = 'public' AND policyname LIKE 'projektleitung_%'
--   ORDER BY tablename, policyname;
--
-- SELECT id, public, file_size_limit FROM storage.buckets WHERE id = 'projekt-bilder';
--
-- SELECT policyname FROM pg_policies
--   WHERE schemaname = 'storage' AND tablename = 'objects'
--     AND policyname LIKE 'projekt_bilder_%';

-- ============================================================
-- ENDE v24-Migration
-- ============================================================
