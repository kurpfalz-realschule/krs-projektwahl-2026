-- =====================================================================
-- migration-v49-code-rotation.sql
-- KRS Projektwahl 2026 — Supabase-Projekt uzynvvtsyjfmtywsfxtz
-- Erstellt: 2026-07-13 (Opus-Sprint "Leck C")
--
-- ZWECK
--   TEIL 0  : Das eigentliche Leck schließen (anon-Lesezugriff auf Views).
--   TEIL 1  : CHECK — nur zählen, nichts ändern. ZUERST ausführen.
--   TEIL 2  : AKTION — Zugangscodes rotieren (nur nach Norberts OK).
--   TEIL 3  : UNDO  — Rotation zurückrollen.
--
-- REIHENFOLGE-REGEL
--   TEIL 0 ist unabhängig von der Rotation und MUSS zuerst laufen.
--   Eine Rotation ohne TEIL 0 ist wertlos: die neuen Codes wären über
--   dieselbe offene View sofort wieder auslesbar.
--
-- STATUS 16.07.2026 (Opus-Nachprüfung, read-only):
--   * TEIL 0 (REVOKE anon auf die drei Views) ist BEREITS EINGESPIELT —
--     anon liefert "permission denied", Datenabfluss gestoppt. Erneutes
--     Ausführen von TEIL 0 ist idempotent/unschädlich.
--   * TEIL 0b (security_invoker = true) noch NICHT gesetzt (optional, nach E2E).
--   * TEIL 2 (Rotation) noch NICHT gelaufen: code_rotation_log existiert nicht,
--     FKs stehen weiter auf ON UPDATE NO ACTION. TEIL 2.2 ist also weiterhin nötig.
--
-- BEFUND (Leck C, verifiziert am 13.07.2026 per SET LOCAL ROLE anon)
--   View public.zuteilungen_detail hat security_invoker = FALSE (Default)
--   und SELECT-GRANT für die Rolle anon. Damit umgeht sie RLS und liefert
--   jedem, der den (öffentlichen) Publishable Key kennt:
--     schueler_code (= Zugangscode!), vorname, nachname, klasse, klassenstufe
--   Messung als anon: 391 Zeilen lesbar. Die Tabellen selbst (schueler,
--   wahlen, zuteilungen, users) liefern als anon korrekt 0 Zeilen — der
--   RLS-Lockdown v35 ist also intakt, die View ist die Umgehung.
--   Ebenfalls anon-lesbar: verteilungen_uebersicht (Lehrkraft-Namen,
--   Statistik) und projekte_stats (Aggregat, keine PII).
--
-- FK-VERHALTEN (in der DB verifiziert, nicht angenommen)
--   wahlen_schueler_code_fkey        FK (schueler_code) REFERENCES schueler(code) ON DELETE CASCADE
--   zuteilungen_schueler_code_fkey   FK (schueler_code) REFERENCES schueler(code) ON DELETE CASCADE
--   tauschwuensche_schueler_code_fkey FK (schueler_code) REFERENCES schueler(code) ON DELETE CASCADE
--   => KEIN "ON UPDATE CASCADE". Ein naives
--        UPDATE schueler SET code = '...' WHERE code = '...'
--      schlägt daher mit FK-Verletzung fehl (oder verwaist Kinder).
--   => TEIL 2 stellt die drei FKs zuerst auf ON UPDATE CASCADE um
--      (nicht-destruktiv, Verhalten bei DELETE bleibt identisch) und
--      rotiert erst dann. Die Kind-Zeilen wandern automatisch mit.
--
-- CODE-FORMAT (aus der DB abgeleitet, Format bleibt gleich)
--   <KLASSE>-<4 Zeichen>, z. B. "7B-XXXX"; Frontend normalisiert mit
--   UPPER(TRIM(...)). Neue Codes: kryptografisch zufällig (pgcrypto,
--   extensions.gen_random_bytes) aus dem verwechslungsarmen Alphabet
--   ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (ohne I, O, 0, 1) => 32^4 ≈ 1,05 Mio
--   Möglichkeiten je Klasse, Kollisionsprüfung im Generator.
-- =====================================================================


-- =====================================================================
-- TEIL 0 — LECK SCHLIESSEN (sofort, unabhängig von der Rotation)
-- Nicht-destruktiv, idempotent. Bricht die Schüler-App NICHT:
-- schueler-frontend-v3.html liest zuteilungen_detail nicht (die Methode
-- listZuteilungen() ist dort ungenutzter Code aus dem gemeinsamen
-- DataService); der eigene Status läuft über get_schueler_status(code).
-- =====================================================================

REVOKE ALL ON public.zuteilungen_detail      FROM anon;
REVOKE ALL ON public.verteilungen_uebersicht FROM anon;
REVOKE ALL ON public.projekte_stats          FROM anon;

-- Belegtest (muss FEHLER "permission denied" liefern):
--   BEGIN; SET LOCAL ROLE anon;
--   SELECT count(*) FROM public.zuteilungen_detail;
--   ROLLBACK;


-- ---------------------------------------------------------------------
-- TEIL 0b — EMPFOHLEN, aber erst nach grünem E2E-Lauf ausführen
-- Auch für eingeloggte Lehrkräfte umgeht die View aktuell die RLS
-- (security_invoker = false => läuft als Owner "postgres"). Mit
-- security_invoker = true greifen die vorhandenen Policies:
-- Projektleitung/Admin sehen alles, Klassenlehrkräfte nur ihre Klasse,
-- Projektlehrkräfte nur ihr Projekt. Das ist das gewollte Verhalten,
-- ändert aber die Sichtbarkeit im Admin-Dashboard — deshalb testen.
-- ---------------------------------------------------------------------
-- ALTER VIEW public.zuteilungen_detail      SET (security_invoker = true);
-- ALTER VIEW public.verteilungen_uebersicht SET (security_invoker = true);
-- ALTER VIEW public.projekte_stats          SET (security_invoker = true);


-- =====================================================================
-- TEIL 1 — CHECK  (nur lesen, ändert nichts — ZUERST ausführen)
-- Ergebnis Norbert zeigen. Erst nach seinem OK TEIL 2 starten.
-- =====================================================================

SELECT
  (SELECT count(*) FROM public.schueler)                                AS schueler_gesamt,
  (SELECT count(*) FROM public.schueler WHERE COALESCE(aktiv, TRUE))    AS schueler_aktiv_rotiert,
  (SELECT count(*) FROM public.schueler WHERE NOT COALESCE(aktiv, TRUE))AS schueler_inaktiv_uebersprungen,
  (SELECT count(*) FROM public.wahlen)                                  AS wahlen_betroffen_cascade,
  (SELECT count(*) FROM public.zuteilungen)                             AS zuteilungen_betroffen_cascade,
  (SELECT count(*) FROM public.tauschwuensche)                          AS tauschwuensche_betroffen_cascade,
  (SELECT value #>> '{}' FROM public.system_settings WHERE key = 'phase')            AS phase,
  (SELECT value #>> '{}' FROM public.system_settings WHERE key = 'anmeldung_offen')  AS anmeldung_offen,
  (SELECT value #>> '{}' FROM public.system_settings WHERE key = 'tausch_deadline')  AS tausch_deadline,
  (SELECT count(*) FROM public.verteilungen WHERE ist_aktiv)            AS aktive_verteilungen;

-- Stand 13.07.2026 (Referenzwerte):
--   schueler_gesamt 503 | aktiv 391 | inaktiv 112 (10er-Abschlussklassen)
--   wahlen 235 | zuteilungen 391 | tauschwuensche 0 | aktive_verteilungen 1
--   phase 'projekttage' | anmeldung_offen false | tausch_deadline 2026-07-17
-- => Rotation berührt KEINE Wahl-Inhalte und KEINE Zuteilungs-Inhalte.
--    Über ON UPDATE CASCADE wandert lediglich der Schlüssel schueler_code
--    in wahlen/zuteilungen/tauschwuensche mit. Wahl-Reihenfolge, Zuteilung
--    und Verteilung bleiben unverändert.


-- =====================================================================
-- TEIL 2 — AKTION: CODE-ROTATION
-- NICHT ohne Norberts ausdrückliches OK ausführen.
-- Läuft in EINER Transaktion; bei jedem Fehler bleibt alles unverändert.
-- Rotiert nur AKTIVE Schüler:innen (inaktive 10er-Klassen bleiben, wie sie sind).
-- =====================================================================

BEGIN;

-- 2.1  Mapping-/Undo-Tabelle (PII-arm: nur alt/neu Code + Klasse, keine Namen)
CREATE TABLE IF NOT EXISTS public.code_rotation_log (
  id          BIGSERIAL PRIMARY KEY,
  batch       TEXT        NOT NULL,
  alt_code    TEXT        NOT NULL,
  neu_code    TEXT        NOT NULL,
  klasse      TEXT,
  rotated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (batch, alt_code),
  UNIQUE (batch, neu_code)
);

-- Kein Frontend-Zugriff: nur service_role / SQL-Editor (postgres) kommen ran.
ALTER TABLE public.code_rotation_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.code_rotation_log FROM anon, authenticated;

-- 2.2  FKs auf ON UPDATE CASCADE umstellen (DELETE-Verhalten unverändert)
ALTER TABLE public.wahlen
  DROP CONSTRAINT IF EXISTS wahlen_schueler_code_fkey,
  ADD  CONSTRAINT wahlen_schueler_code_fkey
       FOREIGN KEY (schueler_code) REFERENCES public.schueler(code)
       ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE public.zuteilungen
  DROP CONSTRAINT IF EXISTS zuteilungen_schueler_code_fkey,
  ADD  CONSTRAINT zuteilungen_schueler_code_fkey
       FOREIGN KEY (schueler_code) REFERENCES public.schueler(code)
       ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE public.tauschwuensche
  DROP CONSTRAINT IF EXISTS tauschwuensche_schueler_code_fkey,
  ADD  CONSTRAINT tauschwuensche_schueler_code_fkey
       FOREIGN KEY (schueler_code) REFERENCES public.schueler(code)
       ON DELETE CASCADE ON UPDATE CASCADE;

-- 2.3  Rotation (idempotent über den Batch-Namen: ein bereits gelaufener
--      Batch rotiert nicht erneut)
DO $rot$
DECLARE
  v_batch    TEXT := '2026-07-leck-c';
  v_alphabet TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- ohne I, O, 0, 1
  r          RECORD;
  v_new      TEXT;
  v_bytes    BYTEA;
  v_try      INT;
  v_count    INT := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM public.code_rotation_log WHERE batch = v_batch) THEN
    RAISE NOTICE 'Batch % existiert bereits — Rotation übersprungen.', v_batch;
    RETURN;
  END IF;

  FOR r IN
    SELECT code, klasse
    FROM public.schueler
    WHERE COALESCE(aktiv, TRUE)
    ORDER BY code
  LOOP
    v_try := 0;
    LOOP
      v_bytes := extensions.gen_random_bytes(4);   -- kryptografisch zufällig
      v_new := UPPER(regexp_replace(COALESCE(r.klasse, 'X'), '\s', '', 'g')) || '-' ||
               substr(v_alphabet, 1 + (get_byte(v_bytes, 0) % 32), 1) ||
               substr(v_alphabet, 1 + (get_byte(v_bytes, 1) % 32), 1) ||
               substr(v_alphabet, 1 + (get_byte(v_bytes, 2) % 32), 1) ||
               substr(v_alphabet, 1 + (get_byte(v_bytes, 3) % 32), 1);

      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.schueler         WHERE code     = v_new)
            AND NOT EXISTS (SELECT 1 FROM public.code_rotation_log WHERE neu_code = v_new);

      v_try := v_try + 1;
      IF v_try > 50 THEN
        RAISE EXCEPTION 'Kein kollisionsfreier Code für Klasse % gefunden', r.klasse;
      END IF;
    END LOOP;

    INSERT INTO public.code_rotation_log (batch, alt_code, neu_code, klasse)
    VALUES (v_batch, r.code, v_new, r.klasse);

    -- CASCADE aktualisiert wahlen / zuteilungen / tauschwuensche automatisch
    UPDATE public.schueler SET code = v_new WHERE code = r.code;

    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE 'Rotation Batch %: % Codes erneuert.', v_batch, v_count;
END
$rot$;

-- 2.4  Kontrolle VOR dem COMMIT (alle Werte müssen stimmen, sonst ROLLBACK)
SELECT
  (SELECT count(*) FROM public.code_rotation_log WHERE batch = '2026-07-leck-c') AS rotierte_codes,
  (SELECT count(*) FROM public.schueler WHERE COALESCE(aktiv, TRUE))             AS aktive_schueler,
  (SELECT count(*) FROM public.wahlen w
     WHERE NOT EXISTS (SELECT 1 FROM public.schueler s WHERE s.code = w.schueler_code))       AS verwaiste_wahlen,
  (SELECT count(*) FROM public.zuteilungen z
     WHERE NOT EXISTS (SELECT 1 FROM public.schueler s WHERE s.code = z.schueler_code))       AS verwaiste_zuteilungen,
  (SELECT count(*) FROM public.tauschwuensche t
     WHERE NOT EXISTS (SELECT 1 FROM public.schueler s WHERE s.code = t.schueler_code))       AS verwaiste_tauschwuensche;
-- Erwartung: rotierte_codes = aktive_schueler; alle "verwaist*" = 0.

COMMIT;
-- Bei unerwarteten Zahlen stattdessen:  ROLLBACK;


-- =====================================================================
-- TEIL 3 — UNDO (macht TEIL 2 rückgängig)
-- Funktioniert, solange die FKs auf ON UPDATE CASCADE stehen (siehe 2.2).
-- Voraussetzung: kein Schüler:innen-Datensatz wurde inzwischen mit einem
-- neuen Code neu angelegt/umbenannt.
-- =====================================================================

-- BEGIN;
-- DO $undo$
-- DECLARE
--   v_batch TEXT := '2026-07-leck-c';
--   r RECORD;
-- BEGIN
--   FOR r IN SELECT alt_code, neu_code FROM public.code_rotation_log
--            WHERE batch = v_batch ORDER BY id DESC
--   LOOP
--     UPDATE public.schueler SET code = r.alt_code WHERE code = r.neu_code;
--   END LOOP;
--   DELETE FROM public.code_rotation_log WHERE batch = v_batch;
--   RAISE NOTICE 'Rotation % zurückgerollt.', v_batch;
-- END
-- $undo$;
-- COMMIT;

-- Undo für TEIL 0 (nur falls die Schüler-App wider Erwarten bricht —
-- das öffnet das Leck wieder, daher nur als Notfall dokumentiert):
--   GRANT SELECT ON public.zuteilungen_detail TO anon;   -- NICHT empfohlen
