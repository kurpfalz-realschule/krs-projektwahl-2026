-- ============================================================
-- MIGRATION: Tauschwünsche-Workflow RPCs
-- Datum: 2026-04-21
-- Ziel:   Admin kann Tauschwünsche genehmigen/ablehnen; atomarer 1:1-Swap
-- Aus:    projekwoche app neu / v9 Wiring
-- ============================================================
--
-- AUSFÜHREN: Supabase Dashboard → Projekt "krs-projektwahl-2026" →
--            SQL Editor → Neue Query → diesen Block einfügen → RUN
--
-- ============================================================

-- ------------------------------------------------------------
-- 1) genehmige_tauschwunsch (einseitiger Platz-Tausch)
-- ------------------------------------------------------------
-- Setzt den Schüler in das gewünschte nach_projekt_id um.
-- Voraussetzungen:
--   - Tauschwunsch ist offen
--   - nach_projekt_id ist gesetzt (NULL-Wünsche müssen manuell bearbeitet
--     werden, weil das Zielprojekt erst entschieden werden muss)
--
-- Ablauf:
--   - zuteilungen.projekt_id ← nach_projekt_id
--   - wahl_nr ← NULL (manuelle Umbuchung, nicht aus Wahl-Algorithmus)
--   - tauschwuensche.status ← 'genehmigt', bearbeitet_von/am gesetzt
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION genehmige_tauschwunsch(
  p_tausch_id UUID,
  p_bearbeiter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tausch RECORD;
BEGIN
  -- Wunsch laden + Lock (FOR UPDATE gegen Race)
  SELECT * INTO v_tausch
  FROM tauschwuensche
  WHERE id = p_tausch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'tausch_unbekannt');
  END IF;

  IF v_tausch.status <> 'offen' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'tausch_nicht_offen',
      'status', v_tausch.status
    );
  END IF;

  IF v_tausch.nach_projekt_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'kein_zielprojekt',
      'hinweis', 'Wunsch ohne Zielprojekt — bitte manuell umbuchen'
    );
  END IF;

  -- Zuteilung umschreiben
  UPDATE zuteilungen
  SET projekt_id = v_tausch.nach_projekt_id,
      wahl_nr = NULL,
      zugewiesen_von = p_bearbeiter_id,
      kommentar = COALESCE(kommentar, '') ||
                  ' | Tausch genehmigt ' || to_char(now(), 'YYYY-MM-DD'),
      updated_at = now()
  WHERE schueler_code = v_tausch.schueler_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'keine_zuteilung',
      'hinweis', 'Schüler hat keine Zuteilung — Tausch nicht durchführbar'
    );
  END IF;

  -- Wunsch als genehmigt markieren
  UPDATE tauschwuensche
  SET status = 'genehmigt',
      bearbeitet_von = p_bearbeiter_id,
      bearbeitet_am = now()
  WHERE id = p_tausch_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM
    );
END;
$$;

-- ------------------------------------------------------------
-- 2) lehn_tauschwunsch_ab
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION lehn_tauschwunsch_ab(
  p_tausch_id UUID,
  p_grund TEXT DEFAULT NULL,
  p_bearbeiter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tausch RECORD;
BEGIN
  SELECT * INTO v_tausch FROM tauschwuensche WHERE id = p_tausch_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'tausch_unbekannt');
  END IF;

  IF v_tausch.status <> 'offen' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'tausch_nicht_offen',
      'status', v_tausch.status
    );
  END IF;

  UPDATE tauschwuensche
  SET status = 'abgelehnt',
      ablehnungsgrund = NULLIF(TRIM(COALESCE(p_grund, '')), ''),
      bearbeitet_von = p_bearbeiter_id,
      bearbeitet_am = now()
  WHERE id = p_tausch_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM
    );
END;
$$;

-- ------------------------------------------------------------
-- 3) genehmige_1zu1_tausch (atomarer Schüler-gegen-Schüler-Swap)
-- ------------------------------------------------------------
-- Genehmigt zwei Tauschwünsche gleichzeitig, die zueinander passen:
--   Schüler A: von=X, nach=Y
--   Schüler B: von=Y, nach=X
-- Ergebnis: A sitzt in Y, B sitzt in X — beide Wünsche genehmigt.
-- Vorteil gegenüber 2x genehmige_tauschwunsch: keine Zwischenzustände,
--   keine Kapazitäts-Verletzung.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION genehmige_1zu1_tausch(
  p_tausch_a UUID,
  p_tausch_b UUID,
  p_bearbeiter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_a RECORD;
  v_b RECORD;
BEGIN
  IF p_tausch_a = p_tausch_b THEN
    RETURN jsonb_build_object('success', false, 'error', 'gleiche_tausch_id');
  END IF;

  -- Beide laden + Lock (in fester Reihenfolge gegen Deadlock)
  IF p_tausch_a < p_tausch_b THEN
    SELECT * INTO v_a FROM tauschwuensche WHERE id = p_tausch_a FOR UPDATE;
    SELECT * INTO v_b FROM tauschwuensche WHERE id = p_tausch_b FOR UPDATE;
  ELSE
    SELECT * INTO v_b FROM tauschwuensche WHERE id = p_tausch_b FOR UPDATE;
    SELECT * INTO v_a FROM tauschwuensche WHERE id = p_tausch_a FOR UPDATE;
  END IF;

  IF v_a.id IS NULL OR v_b.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'tausch_unbekannt');
  END IF;

  IF v_a.status <> 'offen' OR v_b.status <> 'offen' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'mindestens_einer_nicht_offen'
    );
  END IF;

  -- Passen die beiden zueinander? (von↔nach kreuzweise)
  IF v_a.von_projekt_id IS NULL OR v_a.nach_projekt_id IS NULL
     OR v_b.von_projekt_id IS NULL OR v_b.nach_projekt_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'projekte_unvollstaendig'
    );
  END IF;

  IF v_a.von_projekt_id <> v_b.nach_projekt_id
     OR v_a.nach_projekt_id <> v_b.von_projekt_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'kein_match',
      'hinweis', 'Die beiden Wünsche passen nicht 1:1 aufeinander'
    );
  END IF;

  -- Swap durchführen
  UPDATE zuteilungen
  SET projekt_id = v_a.nach_projekt_id,
      wahl_nr = NULL,
      zugewiesen_von = p_bearbeiter_id,
      kommentar = COALESCE(kommentar, '') ||
                  ' | 1:1-Tausch ' || to_char(now(), 'YYYY-MM-DD'),
      updated_at = now()
  WHERE schueler_code = v_a.schueler_code;

  UPDATE zuteilungen
  SET projekt_id = v_b.nach_projekt_id,
      wahl_nr = NULL,
      zugewiesen_von = p_bearbeiter_id,
      kommentar = COALESCE(kommentar, '') ||
                  ' | 1:1-Tausch ' || to_char(now(), 'YYYY-MM-DD'),
      updated_at = now()
  WHERE schueler_code = v_b.schueler_code;

  -- Beide Wünsche als genehmigt markieren
  UPDATE tauschwuensche
  SET status = 'genehmigt',
      bearbeitet_von = p_bearbeiter_id,
      bearbeitet_am = now()
  WHERE id IN (p_tausch_a, p_tausch_b);

  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'datenbank_fehler',
      'details', SQLERRM
    );
END;
$$;

-- ------------------------------------------------------------
-- 4) Berechtigungen
-- ------------------------------------------------------------
-- Die Funktionen laufen mit SECURITY DEFINER, damit der anon-Role
-- sie ausführen kann — Sicherheit folgt dann via RLS-Phase 3 (RLS auf
-- users/zuteilungen/tauschwuensche + Admin-Check innerhalb der RPC).
-- Vorerst: Execute für anon + authenticated freigeben.

GRANT EXECUTE ON FUNCTION genehmige_tauschwunsch(UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION lehn_tauschwunsch_ab(UUID, TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION genehmige_1zu1_tausch(UUID, UUID, UUID) TO anon, authenticated;

-- ============================================================
-- DONE
-- ============================================================
