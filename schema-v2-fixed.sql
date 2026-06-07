-- ============================================================
-- KRS Projektwahl 2026 — Supabase Datenbank-Schema v2 (FIXED)
-- Patches gegenüber schema-v2.sql:
--   * Klassenstufe 5–10 statt 5–9 (wegen Klasse 10)
--   * klassenstufe nullable (VKL/Zugang haben keine Stufe)
--   * users.id ohne REFERENCES auth.users (Phase 1 ohne Auth)
--   * users.kuerzel hinzugefügt (3-Buchstaben-Kürzel)
--   * Open-Mode Policies am Ende für Phase 1
-- ============================================================

-- ============================================================
-- 1. ENUMS
-- ============================================================

CREATE TYPE user_rolle AS ENUM (
  'super_admin', 
  'projektleitung', 
  'projektlehrer', 
  'klassenlehrer'  -- NEU: eigene Rolle für Klassenlehrer-Ansicht
);

CREATE TYPE projekt_status AS ENUM ('entwurf', 'veroeffentlicht');

CREATE TYPE system_phase AS ENUM (
  'setup',          -- Projekte werden angelegt
  'anmeldung',      -- Schüler melden sich an
  'verteilung',     -- Verteilung läuft
  'nachbearbeitung',-- Tauschwünsche, Umbuchungen
  'projekttage',    -- Projekttage laufen
  'abgeschlossen'   -- Archiv
);

CREATE TYPE tauschwunsch_status AS ENUM (
  'offen',
  'genehmigt',
  'abgelehnt',
  'zurueckgezogen'
);

-- ============================================================
-- 2. TABELLE: schueler
-- ============================================================

CREATE TABLE schueler (
  code TEXT PRIMARY KEY,
  vorname TEXT NOT NULL,
  nachname TEXT NOT NULL,
  klasse TEXT NOT NULL,
  klassenstufe INT CHECK (klassenstufe BETWEEN 5 AND 10),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_schueler_klasse ON schueler(klasse);
CREATE INDEX idx_schueler_klassenstufe ON schueler(klassenstufe);

-- ============================================================
-- 3. TABELLE: users (Lehrer-Accounts)
-- NEU: Feld klassenlehrer_von
-- ============================================================

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),  -- vorerst ohne auth-FK, später nachziehen
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  rolle user_rolle NOT NULL DEFAULT 'projektlehrer',
  kuerzel TEXT UNIQUE,  -- 3-Buchstaben-Kürzel, z.B. KOT, CAR, SMT
  klassenlehrer_von TEXT,  -- NEU: z.B. "7b" (optional, ein Lehrer kann Klassenlehrer sein)
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_users_rolle ON users(rolle);
CREATE INDEX idx_users_klasse ON users(klassenlehrer_von) WHERE klassenlehrer_von IS NOT NULL;

-- ============================================================
-- 4. TABELLE: projekte
-- NEU: min_teilnehmer
-- ============================================================

CREATE TABLE projekte (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titel TEXT NOT NULL,
  kurzbeschreibung TEXT NOT NULL CHECK (char_length(kurzbeschreibung) <= 300),
  langbeschreibung TEXT,
  lehrer_id UUID NOT NULL REFERENCES users(id),
  lehrer2_id UUID REFERENCES users(id),
  max_plaetze INT NOT NULL DEFAULT 12 CHECK (max_plaetze BETWEEN 1 AND 50),
  min_teilnehmer INT NOT NULL DEFAULT 6 CHECK (min_teilnehmer >= 1),  -- NEU
  min_klasse INT NOT NULL DEFAULT 5 CHECK (min_klasse BETWEEN 5 AND 10),
  max_klasse INT NOT NULL DEFAULT 10 CHECK (max_klasse BETWEEN 5 AND 10),
  ort TEXT,
  bild_url TEXT,
  status projekt_status NOT NULL DEFAULT 'entwurf',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT min_max_klasse_check CHECK (min_klasse <= max_klasse),
  CONSTRAINT min_teilnehmer_check CHECK (min_teilnehmer <= max_plaetze),
  CONSTRAINT projekte_unterschiedliche_lehrer_check CHECK (lehrer2_id IS NULL OR lehrer2_id <> lehrer_id),
  CONSTRAINT projekte_max_plaetze_lehrer_check CHECK (max_plaetze <= CASE WHEN lehrer2_id IS NULL THEN 12 ELSE 24 END)
);

CREATE INDEX idx_projekte_lehrer ON projekte(lehrer_id);
CREATE INDEX idx_projekte_lehrer2 ON projekte(lehrer2_id);
CREATE INDEX idx_projekte_status ON projekte(status);

-- ============================================================
-- 5. TABELLE: wahlen (immutable)
-- ============================================================

CREATE TABLE wahlen (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schueler_code TEXT NOT NULL UNIQUE REFERENCES schueler(code) ON DELETE CASCADE,
  erstwahl_id UUID NOT NULL REFERENCES projekte(id),
  zweitwahl_id UUID NOT NULL REFERENCES projekte(id),
  drittwahl_id UUID NOT NULL REFERENCES projekte(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  ip_hash TEXT,
  
  CONSTRAINT unterschiedliche_wahlen CHECK (
    erstwahl_id != zweitwahl_id 
    AND zweitwahl_id != drittwahl_id 
    AND erstwahl_id != drittwahl_id
  )
);

CREATE INDEX idx_wahlen_erstwahl ON wahlen(erstwahl_id);
CREATE INDEX idx_wahlen_zweitwahl ON wahlen(zweitwahl_id);
CREATE INDEX idx_wahlen_drittwahl ON wahlen(drittwahl_id);

-- ============================================================
-- 6. TABELLE: verteilungen (NEU)
-- Speichert alle Verteilungs-Durchläufe
-- ============================================================

CREATE TABLE verteilungen (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gestartet_von UUID REFERENCES users(id),
  gestartet_am TIMESTAMPTZ DEFAULT now(),
  seed TEXT NOT NULL,              -- für Reproduzierbarkeit
  ist_aktiv BOOLEAN DEFAULT false,  -- nur EINE Verteilung ist "aktiv"
  ist_preview BOOLEAN DEFAULT true, -- wird erst true mit commit
  statistik JSONB,                 -- { erstwahl: 342, zweitwahl: 78, ... }
  kommentar TEXT
);

CREATE INDEX idx_verteilungen_aktiv ON verteilungen(ist_aktiv) WHERE ist_aktiv = true;
CREATE INDEX idx_verteilungen_datum ON verteilungen(gestartet_am DESC);

-- Nur EINE aktive Verteilung zur Zeit erzwingen
CREATE UNIQUE INDEX idx_verteilungen_nur_eine_aktiv 
  ON verteilungen(ist_aktiv) 
  WHERE ist_aktiv = true;

-- ============================================================
-- 7. TABELLE: zuteilungen (mutable, verweist auf Verteilung)
-- NEU: verteilung_id
-- ============================================================

CREATE TABLE zuteilungen (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schueler_code TEXT NOT NULL UNIQUE REFERENCES schueler(code) ON DELETE CASCADE,
  projekt_id UUID REFERENCES projekte(id),
  wahl_nr INT CHECK (wahl_nr IN (1, 2, 3)),
  verteilung_id UUID REFERENCES verteilungen(id),  -- NEU: aus welcher Verteilung?
  zugewiesen_von UUID REFERENCES users(id),
  kommentar TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_zuteilungen_projekt ON zuteilungen(projekt_id);
CREATE INDEX idx_zuteilungen_verteilung ON zuteilungen(verteilung_id);

-- ============================================================
-- 8. TABELLE: tauschwuensche (NEU)
-- ============================================================

CREATE TABLE tauschwuensche (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schueler_code TEXT NOT NULL REFERENCES schueler(code) ON DELETE CASCADE,
  von_projekt_id UUID NOT NULL REFERENCES projekte(id),
  nach_projekt_id UUID REFERENCES projekte(id),  -- NULL = "irgendwo anders hin"
  begruendung TEXT NOT NULL CHECK (char_length(begruendung) >= 10),
  status tauschwunsch_status NOT NULL DEFAULT 'offen',
  bearbeitet_von UUID REFERENCES users(id),
  bearbeitet_am TIMESTAMPTZ,
  ablehnungsgrund TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_tausch_schueler ON tauschwuensche(schueler_code);
CREATE INDEX idx_tausch_status ON tauschwuensche(status);
CREATE INDEX idx_tausch_created ON tauschwuensche(created_at DESC);

-- Rate-Limit: max 1 offener Wunsch pro Schüler
CREATE UNIQUE INDEX idx_tausch_nur_einer_offen 
  ON tauschwuensche(schueler_code) 
  WHERE status = 'offen';

-- ============================================================
-- 9. TABELLE: audit_log
-- ============================================================

CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  aktion TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_audit_user ON audit_log(user_id);
CREATE INDEX idx_audit_aktion ON audit_log(aktion);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);

-- ============================================================
-- 10. TABELLE: system_settings
-- NEU: phase-Feld
-- ============================================================

CREATE TABLE system_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES users(id)
);

-- Initial-Einstellungen
INSERT INTO system_settings (key, value) VALUES
  ('phase', '"setup"'::jsonb),
  ('anmeldung_offen', 'false'::jsonb),
  ('anmeldung_deadline', '"2026-07-10T23:59:59+02:00"'::jsonb),
  ('tausch_deadline', '"2026-07-17T23:59:59+02:00"'::jsonb),
  ('projekttage_beginn', '"2026-07-21"'::jsonb),
  ('projekttage_ende', '"2026-07-23"'::jsonb),
  ('schulfest_datum', '"2026-07-23"'::jsonb);

-- ============================================================
-- 11. VIEWS
-- ============================================================

-- Öffentliche Projekt-Ansicht
CREATE OR REPLACE VIEW projekte_public AS
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
FROM projekte p
JOIN users u1 ON p.lehrer_id = u1.id
LEFT JOIN users u2 ON p.lehrer2_id = u2.id
WHERE p.status = 'veroeffentlicht';

-- Projekt-Statistik (für Admin)
CREATE OR REPLACE VIEW projekte_stats AS
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
FROM projekte p
JOIN users u1 ON p.lehrer_id = u1.id
LEFT JOIN users u2 ON p.lehrer2_id = u2.id
LEFT JOIN zuteilungen z ON z.projekt_id = p.id
LEFT JOIN wahlen w1 ON w1.erstwahl_id = p.id
LEFT JOIN wahlen w2 ON w2.zweitwahl_id = p.id
LEFT JOIN wahlen w3 ON w3.drittwahl_id = p.id
WHERE p.status = 'veroeffentlicht'
GROUP BY p.id, p.titel, p.max_plaetze, p.min_teilnehmer, u1.name, u2.name;

-- Zuteilungen mit allen Kontextinfos
CREATE OR REPLACE VIEW zuteilungen_detail AS
SELECT 
  z.id,
  z.schueler_code,
  s.vorname, s.nachname, s.klasse, s.klassenstufe,
  z.projekt_id, p.titel AS projekt_titel,
  NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name,
  z.wahl_nr,
  z.updated_at,
  u1.name AS lehrer1_name,
  u2.name AS lehrer2_name
FROM zuteilungen z
JOIN schueler s ON z.schueler_code = s.code
LEFT JOIN projekte p ON z.projekt_id = p.id
LEFT JOIN users u1 ON p.lehrer_id = u1.id
LEFT JOIN users u2 ON p.lehrer2_id = u2.id;

-- Anmelde-Status pro Klasse (Klassenlehrer-Ansicht)
CREATE OR REPLACE VIEW klassen_status AS
SELECT 
  s.klasse,
  COUNT(s.code) AS anzahl_schueler,
  COUNT(w.id) AS angemeldet,
  COUNT(s.code) - COUNT(w.id) AS fehlt_noch,
  COUNT(z.id) FILTER (WHERE z.wahl_nr = 1) AS zugeteilt_w1,
  COUNT(z.id) FILTER (WHERE z.wahl_nr = 2) AS zugeteilt_w2,
  COUNT(z.id) FILTER (WHERE z.wahl_nr = 3) AS zugeteilt_w3,
  COUNT(z.id) FILTER (WHERE z.wahl_nr IS NULL AND z.projekt_id IS NOT NULL) AS manuell
FROM schueler s
LEFT JOIN wahlen w ON w.schueler_code = s.code
LEFT JOIN zuteilungen z ON z.schueler_code = s.code
GROUP BY s.klasse
ORDER BY s.klasse;

-- Offene Tauschwünsche mit Kontextinfos
CREATE OR REPLACE VIEW offene_tauschwuensche AS
SELECT 
  t.id,
  t.schueler_code,
  s.vorname, s.nachname, s.klasse,
  t.von_projekt_id, pv.titel AS von_projekt_titel,
  t.nach_projekt_id, pn.titel AS nach_projekt_titel,
  t.begruendung,
  t.created_at,
  -- 1:1-Tausch-Erkennung: gibt es einen Schüler, der den umgekehrten Wunsch hat?
  EXISTS(
    SELECT 1 FROM tauschwuensche t2
    WHERE t2.status = 'offen'
      AND t2.von_projekt_id = t.nach_projekt_id
      AND t2.nach_projekt_id = t.von_projekt_id
      AND t2.id != t.id
  ) AS eins_zu_eins_tausch_moeglich,
  -- Falls ja: wer?
  (SELECT t2.schueler_code FROM tauschwuensche t2
    WHERE t2.status = 'offen'
      AND t2.von_projekt_id = t.nach_projekt_id
      AND t2.nach_projekt_id = t.von_projekt_id
    LIMIT 1) AS tauschpartner_code
FROM tauschwuensche t
JOIN schueler s ON t.schueler_code = s.code
JOIN projekte pv ON t.von_projekt_id = pv.id
LEFT JOIN projekte pn ON t.nach_projekt_id = pn.id
WHERE t.status = 'offen'
ORDER BY t.created_at ASC;

-- ============================================================
-- 12. RPC-FUNKTIONEN
-- ============================================================

-- Schüler-Identität + Status prüfen (erweitert für phasenbewusstes Frontend)
CREATE OR REPLACE FUNCTION get_schueler_status(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_schueler RECORD;
  v_phase TEXT;
  v_wahl RECORD;
  v_zuteilung RECORD;
  v_offener_tausch RECORD;
  v_projekt_details RECORD;
  v_result JSONB;
BEGIN
  -- Aktuelle Phase
  SELECT value #>> '{}' INTO v_phase FROM system_settings WHERE key = 'phase';
  
  -- Schüler suchen
  SELECT * INTO v_schueler FROM schueler WHERE code = UPPER(TRIM(p_code));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'code_unbekannt');
  END IF;
  
  v_result := jsonb_build_object(
    'success', true,
    'phase', v_phase,
    'schueler', jsonb_build_object(
      'code', v_schueler.code,
      'vorname', v_schueler.vorname,
      'nachname', v_schueler.nachname,
      'klasse', v_schueler.klasse,
      'klassenstufe', v_schueler.klassenstufe
    )
  );
  
  -- Wahlen schon abgegeben?
  SELECT * INTO v_wahl FROM wahlen WHERE schueler_code = v_schueler.code;
  IF FOUND THEN
    v_result := v_result || jsonb_build_object('hat_gewaehlt', true, 
      'wahlen', jsonb_build_object(
        'erstwahl_id', v_wahl.erstwahl_id,
        'zweitwahl_id', v_wahl.zweitwahl_id,
        'drittwahl_id', v_wahl.drittwahl_id,
        'gewaehlt_am', v_wahl.created_at
      )
    );
  ELSE
    v_result := v_result || jsonb_build_object('hat_gewaehlt', false);
  END IF;
  
  -- Zuteilung vorhanden?
  SELECT z.*, p.titel, p.kurzbeschreibung, p.ort,
         NULLIF(CONCAT_WS(', ', u1.name, u2.name), '') AS lehrer_name
  INTO v_projekt_details
  FROM zuteilungen z
  LEFT JOIN projekte p ON z.projekt_id = p.id
  LEFT JOIN users u1 ON p.lehrer_id = u1.id
  LEFT JOIN users u2 ON p.lehrer2_id = u2.id
  WHERE z.schueler_code = v_schueler.code AND z.projekt_id IS NOT NULL;
  
  IF FOUND THEN
    v_result := v_result || jsonb_build_object('hat_zuteilung', true,
      'zuteilung', jsonb_build_object(
        'projekt_id', v_projekt_details.projekt_id,
        'projekt_titel', v_projekt_details.titel,
        'projekt_beschreibung', v_projekt_details.kurzbeschreibung,
        'lehrer', v_projekt_details.lehrer_name,
        'ort', v_projekt_details.ort,
        'wahl_nr', v_projekt_details.wahl_nr
      )
    );
  ELSE
    v_result := v_result || jsonb_build_object('hat_zuteilung', false);
  END IF;
  
  -- Offener Tauschwunsch?
  SELECT t.*, p.titel AS nach_titel
  INTO v_offener_tausch
  FROM tauschwuensche t
  LEFT JOIN projekte p ON t.nach_projekt_id = p.id
  WHERE t.schueler_code = v_schueler.code AND t.status = 'offen';
  
  IF FOUND THEN
    v_result := v_result || jsonb_build_object('hat_offenen_tausch', true,
      'tauschwunsch', jsonb_build_object(
        'id', v_offener_tausch.id,
        'nach_projekt_titel', v_offener_tausch.nach_titel,
        'erstellt_am', v_offener_tausch.created_at
      )
    );
  ELSE
    v_result := v_result || jsonb_build_object('hat_offenen_tausch', false);
  END IF;
  
  RETURN v_result;
END;
$$;

-- Wahl abgeben
CREATE OR REPLACE FUNCTION create_wahl(
  p_code TEXT,
  p_vorname_bestaetigung TEXT,
  p_nachname_bestaetigung TEXT,
  p_erstwahl UUID,
  p_zweitwahl UUID,
  p_drittwahl UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_schueler RECORD;
  v_anmeldung_offen BOOLEAN;
BEGIN
  SELECT (value::text = 'true') INTO v_anmeldung_offen FROM system_settings WHERE key = 'anmeldung_offen';
  IF NOT v_anmeldung_offen THEN
    RETURN jsonb_build_object('success', false, 'error', 'anmeldung_geschlossen');
  END IF;
  
  SELECT * INTO v_schueler FROM schueler WHERE code = UPPER(TRIM(p_code));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ungueltiger_code');
  END IF;
  
  IF LOWER(TRIM(v_schueler.vorname)) != LOWER(TRIM(p_vorname_bestaetigung)) 
     OR LOWER(TRIM(v_schueler.nachname)) != LOWER(TRIM(p_nachname_bestaetigung)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_stimmt_nicht');
  END IF;
  
  IF EXISTS(SELECT 1 FROM wahlen WHERE schueler_code = v_schueler.code) THEN
    RETURN jsonb_build_object('success', false, 'error', 'bereits_angemeldet');
  END IF;
  
  INSERT INTO wahlen (schueler_code, erstwahl_id, zweitwahl_id, drittwahl_id)
  VALUES (v_schueler.code, p_erstwahl, p_zweitwahl, p_drittwahl);
  
  RETURN jsonb_build_object('success', true, 'schueler_code', v_schueler.code, 'vorname', v_schueler.vorname);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

-- Tauschwunsch stellen
CREATE OR REPLACE FUNCTION create_tauschwunsch(
  p_code TEXT,
  p_vorname_bestaetigung TEXT,
  p_nachname_bestaetigung TEXT,
  p_nach_projekt_id UUID,
  p_begruendung TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_schueler RECORD;
  v_aktuelles_projekt_id UUID;
  v_tausch_offen BOOLEAN;
  v_deadline TIMESTAMPTZ;
BEGIN
  -- Tausch-Deadline prüfen
  SELECT (value #>> '{}')::timestamptz INTO v_deadline FROM system_settings WHERE key = 'tausch_deadline';
  IF now() > v_deadline THEN
    RETURN jsonb_build_object('success', false, 'error', 'tauschfenster_geschlossen');
  END IF;
  
  -- Schüler verifizieren
  SELECT * INTO v_schueler FROM schueler WHERE code = UPPER(TRIM(p_code));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ungueltiger_code');
  END IF;
  
  IF LOWER(TRIM(v_schueler.vorname)) != LOWER(TRIM(p_vorname_bestaetigung))
     OR LOWER(TRIM(v_schueler.nachname)) != LOWER(TRIM(p_nachname_bestaetigung)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_stimmt_nicht');
  END IF;
  
  -- Aktuelles Projekt ermitteln
  SELECT projekt_id INTO v_aktuelles_projekt_id FROM zuteilungen WHERE schueler_code = v_schueler.code;
  IF v_aktuelles_projekt_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'keine_zuteilung');
  END IF;
  
  -- Schon offener Wunsch?
  IF EXISTS(SELECT 1 FROM tauschwuensche WHERE schueler_code = v_schueler.code AND status = 'offen') THEN
    RETURN jsonb_build_object('success', false, 'error', 'bereits_offener_wunsch');
  END IF;
  
  -- Begründung prüfen
  IF char_length(TRIM(p_begruendung)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'begruendung_zu_kurz');
  END IF;
  
  -- Wunsch anlegen
  INSERT INTO tauschwuensche (schueler_code, von_projekt_id, nach_projekt_id, begruendung)
  VALUES (v_schueler.code, v_aktuelles_projekt_id, p_nach_projekt_id, TRIM(p_begruendung));
  
  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'datenbank_fehler', 'details', SQLERRM);
END;
$$;

-- Tauschwunsch zurückziehen
CREATE OR REPLACE FUNCTION withdraw_tauschwunsch(
  p_code TEXT,
  p_vorname_bestaetigung TEXT,
  p_nachname_bestaetigung TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_schueler RECORD;
BEGIN
  SELECT * INTO v_schueler FROM schueler WHERE code = UPPER(TRIM(p_code));
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'ungueltiger_code'); END IF;
  
  IF LOWER(TRIM(v_schueler.vorname)) != LOWER(TRIM(p_vorname_bestaetigung))
     OR LOWER(TRIM(v_schueler.nachname)) != LOWER(TRIM(p_nachname_bestaetigung)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_stimmt_nicht');
  END IF;
  
  UPDATE tauschwuensche 
  SET status = 'zurueckgezogen', bearbeitet_am = now()
  WHERE schueler_code = v_schueler.code AND status = 'offen';
  
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================
-- 13. TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_projekte_updated_at BEFORE UPDATE ON projekte
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_zuteilungen_updated_at BEFORE UPDATE ON zuteilungen
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 14. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE schueler ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE projekte ENABLE ROW LEVEL SECURITY;
ALTER TABLE wahlen ENABLE ROW LEVEL SECURITY;
ALTER TABLE zuteilungen ENABLE ROW LEVEL SECURITY;
ALTER TABLE verteilungen ENABLE ROW LEVEL SECURITY;
ALTER TABLE tauschwuensche ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

-- Projekte: Anon sieht veröffentlichte
CREATE POLICY "Anon sieht veröffentlichte Projekte" ON projekte
  FOR SELECT TO anon, authenticated
  USING (status = 'veroeffentlicht');

CREATE POLICY "Lehrer verwaltet eigene Projekte" ON projekte
  FOR ALL TO authenticated
  USING (auth.uid() IN (lehrer_id, lehrer2_id))
  WITH CHECK (auth.uid() IN (lehrer_id, lehrer2_id));

CREATE POLICY "Admins verwalten alle Projekte" ON projekte
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() 
    AND rolle IN ('super_admin', 'projektleitung')));

-- Wahlen: nur Admins
CREATE POLICY "Admins sehen alle Wahlen" ON wahlen
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() 
    AND rolle IN ('super_admin', 'projektleitung')));

-- Zuteilungen: Admins alles, Lehrer nur eigene Teilnehmer, Klassenlehrer eigene Klasse
CREATE POLICY "Admins verwalten Zuteilungen" ON zuteilungen
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() 
    AND rolle IN ('super_admin', 'projektleitung')));

CREATE POLICY "Projektlehrer sehen eigene Teilnehmer" ON zuteilungen
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM projekte 
    WHERE projekte.id = zuteilungen.projekt_id 
    AND auth.uid() IN (projekte.lehrer_id, projekte.lehrer2_id)));

CREATE POLICY "Klassenlehrer sehen eigene Klasse" ON zuteilungen
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM users u 
    JOIN schueler s ON s.klasse = u.klassenlehrer_von
    WHERE u.id = auth.uid() 
    AND s.code = zuteilungen.schueler_code
  ));

-- Verteilungen: nur Admins
CREATE POLICY "Admins verwalten Verteilungen" ON verteilungen
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() 
    AND rolle IN ('super_admin', 'projektleitung')));

-- Tauschwünsche: Admins alles, Projektlehrer sehen für ihre Projekte
CREATE POLICY "Admins verwalten Tauschwuensche" ON tauschwuensche
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() 
    AND rolle IN ('super_admin', 'projektleitung')));

-- Audit-Log: nur Super-Admin liest
CREATE POLICY "Super-Admin liest Audit-Log" ON audit_log
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND rolle = 'super_admin'));

-- Users
CREATE POLICY "User sieht eigene Daten" ON users
  FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Super-Admin sieht alle Users" ON users
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND rolle = 'super_admin'));

-- System-Settings
CREATE POLICY "Alle sehen bestimmte Settings" ON system_settings
  FOR SELECT TO anon, authenticated
  USING (key IN ('phase', 'anmeldung_offen', 'anmeldung_deadline', 'tausch_deadline', 'projekttage_beginn', 'projekttage_ende'));

CREATE POLICY "Super-Admin verwaltet Settings" ON system_settings
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND rolle = 'super_admin'));

-- ============================================================
-- ENDE Schema v2
-- ============================================================


-- ============================================================
-- 15. OPEN-MODE POLICIES (Phase 1 — ohne Auth)
-- Während der Testphase: SELECT frei, mutierende Ops via Service-Key
-- Diese Policies werden später durch strikte Auth-Policies ersetzt.
-- ============================================================

-- Schüler: alle dürfen lesen (für Code-Login-Flow nötig)
DROP POLICY IF EXISTS "open_read_schueler" ON schueler;
CREATE POLICY "open_read_schueler" ON schueler
  FOR SELECT TO anon, authenticated USING (true);

-- Projekte: alle dürfen lesen
DROP POLICY IF EXISTS "open_read_projekte" ON projekte;
CREATE POLICY "open_read_projekte" ON projekte
  FOR SELECT TO anon, authenticated USING (true);

-- Users: alle dürfen lesen (für Dashboard-Anzeige)
DROP POLICY IF EXISTS "open_read_users" ON users;
CREATE POLICY "open_read_users" ON users
  FOR SELECT TO anon, authenticated USING (true);

-- System-Settings: alle dürfen lesen
DROP POLICY IF EXISTS "open_read_settings" ON system_settings;
CREATE POLICY "open_read_settings" ON system_settings
  FOR SELECT TO anon, authenticated USING (true);

-- Zuteilungen: alle dürfen lesen (Phase 1)
DROP POLICY IF EXISTS "open_read_zuteilungen" ON zuteilungen;
CREATE POLICY "open_read_zuteilungen" ON zuteilungen
  FOR SELECT TO anon, authenticated USING (true);

-- Wahlen: keine offenen Policies! Wahlen werden nur via RPC create_wahl() erstellt.
