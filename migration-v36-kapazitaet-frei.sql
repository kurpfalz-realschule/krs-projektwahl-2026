-- ============================================================
-- Migration v36: Kapazitätsregel freigeben
-- ============================================================
-- Hintergrund: Feste Klassenprojekte haben teils >24 Schüler.
-- Die harte 12/24-Regel (12 pro Lehrkraft) fällt weg.
-- 12/24 bleibt im Frontend nur als Richtwert/Default erhalten.
--
-- Ausführen mit:
--   ~/.local/bin/supabase db query --linked --file migration-v36-kapazitaet-frei.sql
-- ============================================================

-- 1. Alte 12/24-Regel entfernen
ALTER TABLE public.projekte
  DROP CONSTRAINT IF EXISTS projekte_max_plaetze_lehrer_check;

-- 1b. Versteckter Alt-Constraint aus dem Ur-Schema (1..50) — beim ersten
--     Migrationslauf am 10.06.2026 entdeckt. Ohne diesen Drop deckelt die DB
--     weiter bei 50 Plätzen.
ALTER TABLE public.projekte
  DROP CONSTRAINT IF EXISTS projekte_max_plaetze_check;

-- 2. Neue Plausibilitätsgrenze: 1 bis 100 Plätze
--    NOT VALID, damit evtl. Bestandsdaten die Migration nicht blockieren.
ALTER TABLE public.projekte
  DROP CONSTRAINT IF EXISTS projekte_max_plaetze_range_check;

ALTER TABLE public.projekte
  ADD CONSTRAINT projekte_max_plaetze_range_check
  CHECK (max_plaetze BETWEEN 1 AND 100)
  NOT VALID;

-- Kontrolle: Constraint-Liste anzeigen
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.projekte'::regclass
  AND conname LIKE '%plaetze%';
