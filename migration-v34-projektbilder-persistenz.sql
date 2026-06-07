-- ============================================================
-- KRS Projektwahl 2026 — v34 Migration
-- Zweck: Projektbild-URL zuverlässig speichern
-- Datum: 2026-05-20
--
-- Wird vom Frontend nach erfolgreichem Storage-Upload genutzt. Die Funktion
-- prüft explizit die App-Rolle und verhindert, dass ein RLS-Update still mit
-- 0 betroffenen Zeilen durchläuft.
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_projekt_bild_url(
  p_projekt_id UUID,
  p_bild_url TEXT
)
RETURNS public.projekte
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.projekte;
BEGIN
  IF p_projekt_id IS NULL THEN
    RAISE EXCEPTION 'Projekt-ID fehlt';
  END IF;

  IF public.is_admin() OR public.is_projektleitung() THEN
    UPDATE public.projekte
       SET bild_url = NULLIF(p_bild_url, ''),
           updated_at = now()
     WHERE id = p_projekt_id
     RETURNING * INTO v_row;
  ELSIF public.is_projektlehrer() THEN
    UPDATE public.projekte p
       SET bild_url = NULLIF(p_bild_url, ''),
           updated_at = now()
     WHERE p.id = p_projekt_id
       AND public.projekt_belongs_to_current_app_user(p.lehrer_id, p.lehrer2_id)
     RETURNING * INTO v_row;
  ELSE
    RAISE EXCEPTION 'Keine Berechtigung zum Speichern von Projektbildern';
  END IF;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Projekt nicht gefunden oder keine Berechtigung';
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_projekt_bild_url(UUID, TEXT) TO authenticated;

-- ============================================================
-- ENDE v34-Migration
-- ============================================================
