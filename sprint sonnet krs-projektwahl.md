# Sprint SONNET — krs-projektwahl: Serienbriefe + Testlauf nach Code-Rotation

Erstellt: 2026-07-12 von Fable (Orchestrator). Selbsterklärend — keine Chat-Historie nötig.
**⛔ ERST STARTEN, wenn der Opus-Sprint (`sprint opus krs-projektwahl.md`) den Abschnitt
„Input von Opus" unten ausgefüllt hat und die Rotation von Norbert freigegeben + ausgeführt ist.**

## Kontext

- App: KRS Projektwahl 2026, dieser Ordner (`krs-pw-deploy`). Schüler loggen sich mit
  Zugangscode ein (`schueler-frontend-v3.html`, `get_schueler_status(code)`).
- Wegen eines Sicherheitsvorfalls („Leck C") wurden die Zugangscodes rotiert
  (Opus-Sprint). Die Projektwoche **läuft noch / steht bevor** — alle Schüler:innen
  brauchen daher NEUE Briefe mit neuem Code + QR, VOR dem nächsten Schultag mit App-Nutzung.
- Zeitdruck: Serienbrief-Druck dauert 1–2 Werktage; Sommerferien BW ~Ende Juli.
- Schülerdaten: NIE in Repo/Code/Ausgaben (siehe `SECURITY.md`). Quelle für echte
  Listen: nur Supabase bzw. `_KRS-ZENTRALE`.

## Input von Opus (ausgefüllt 16.07.2026 — Opus-Session)

- **Leck-C-Befund:** View `zuteilungen_detail` umging RLS (`security_invoker = false`) und war
  für `anon` lesbar → Zugangscode + Vor-/Nachname + Klasse von **391 aktiven Schüler:innen**
  ohne Login abrufbar. Details: `AUDIT-LECK-C-2026-07-13.md`.
- **STATUS des Lecks:** **geschlossen.** Der anon-`REVOKE` (v49 TEIL 0) ist eingespielt, am
  16.07. verifiziert (Abruf als `anon` = „permission denied"). Der Grundschutz (RLS-Lockdown v35)
  war die ganze Zeit intakt.
- **Rotation ausgeführt am:** **NOCH NICHT ausgeführt** (Stand 16.07.). `code_rotation_log`
  existiert noch nicht. **Entscheidung Rotation ja/nein liegt bei Norbert** — CHECK-Query steht
  in `migration-v49-code-rotation.sql` TEIL 1. Erst wenn Norbert die Rotation freigibt UND sie
  gelaufen ist, startet dieser Sonnet-Sprint mit den Serienbriefen.
  · **Mapping-/Undo-Tabelle:** `public.code_rotation_log` (Spalten: `batch`, `alt_code`,
  `neu_code`, `klasse`, `rotated_at`; PII-arm, keine Namen). Batch-Name: `2026-07-leck-c`.
- **Besonderheiten für Briefe:**
  - Nur **aktive** Schüler:innen bekommen neue Codes (`schueler.aktiv = TRUE`, 391 Stück).
    Die 112 inaktiven (10er-Abschlussklassen) werden **nicht** rotiert → **keine Briefe** für sie.
  - Neues Code-Format bleibt gleich: `<KLASSE>-<4 Zeichen>` aus dem Alphabet
    `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (ohne I/O/0/1). Frontend normalisiert `UPPER(TRIM(...))` —
    QR-Deep-Link `?code=` in Großbuchstaben erzeugen.
  - Neue Codes NUR über Admin-RPC/`code_rotation_log` (service_role) abrufen, lokal ausgeben,
    **nichts committen** (echte Minderjährigen-Codes).
  - Alte Codes sind nach der Rotation sofort tot → Hinweistext im Brief bleibt Pflicht.
  - **Falls Norbert die Rotation NICHT freigibt:** Leck ist bereits geschlossen, dann sind
    KEINE neuen Briefe nötig und dieser Sonnet-Sprint entfällt (nur kurze Info an Kollegium).

## Ziel / Fertig wenn

Jede:r aktive Schüler:in hat einen druckfertigen A4-Brief mit neuem Code + QR-Deep-Link,
der komplette Ablauf wurde mit einem TEST-Schüler durchgespielt und protokolliert,
und der Go-Live (Briefe austeilen) ist mit Datum angekündigt.

## Aufgaben

### 1. Serienbriefe (Skill: `serienbrief-code-qr-druck`)
- [ ] Brief-Generator nach KRS-Muster: pro Person genau eine A4-Seite, QR öffnet
  App mit `?code=…` vorausgefüllt, Klartext-Kurzlink dazu, `page-break-inside:avoid`,
  Fallback ohne QR. Vorlage/Vorarbeit existiert: `generate_schuelerbrief.py` +
  `beispiel-schuelerbrief.pdf` in `../projekwoche app neu/` — wiederverwenden statt neu bauen.
- [ ] Datenquelle: NEUE Codes (nur aktive Schüler, `schueler.aktiv = TRUE`) — Abruf
  über Admin-RPC, Ausgabe lokal, nichts committen.
- [ ] Hinweistext im Brief: „Dein alter Code funktioniert nicht mehr" (1 Satz, schülergerecht).
- **Akzeptanz:** Stichprobe 3 Briefe: QR scannt korrekt auf Live-URL mit vorausgefülltem
  Code, eine Seite pro Kind, Umlaute korrekt.

### 2. Testlauf VOR echten Schülern (Skill: `live-gang-testlauf-protokoll`)
Lektion aus dem v42-Vorfall (entkoppeltes Status-Flag → Schüler sahen „Anmeldung
nicht geöffnet"): kompletter Durchlauf mit Test-Nutzer, PFLICHT.
- [ ] Test-Schüler in DB anlegen (erfundener Name!), Brief für ihn generieren,
  QR mit echtem Gerät scannen, einloggen, Wahl durchklicken, wieder aufräumen.
- [ ] Alten (rotierten) Code testen → muss sauber abgewiesen werden (Fehlermeldung prüfen).
- [ ] Protokoll als `TESTLAUF-PROTOKOLL-code-rotation.md`: Schritte, Ergebnis, Datum, Gerät.
- [ ] Ankündigung formulieren (an Norbert für Kollegium/Klassenlehrer): WANN neue
  Briefe kommen und ab wann alte Codes tot sind.
- **Akzeptanz:** Protokoll vollständig, beide Pfade (neuer Code ✓ / alter Code ✗) belegt.

### 3. Deploy nur falls Code geändert wurde (Skill: `krs-git-deploy`)
- [ ] Falls App-Dateien angefasst wurden: git push → GitHub-Actions-E2E-Gate → bei
  Grün Auto-Deploy. Bei rotem Gate: Screenshot/Trace auswerten, NIE Timeouts erhöhen
  (Skill `flaky-ci-echter-bug-diagnose`).
- **Akzeptanz:** Gate grün ODER kein Deploy nötig (begründet).

## Scope-Grenze

**Mach NUR diese Aufgaben.** Keine RLS-/Policy-Änderungen, kein SQL außer Test-Schüler
anlegen/aufräumen, keine DSGVO-Texte (alles Opus-Sprint). Keine neuen Features,
kein Refactoring, nichts „mitverbessern".

## Abschlusspflicht

Am Ende: kanonische `HANDOVER.md` dieses Ordners aktualisieren (keine neue v-Datei),
Dashboard-Eintrag in `_PROJEKT-ZENTRALE/PROJEKT-DASHBOARD.html` (DATA-Block) aktualisieren,
Änderungen committen. Session-Abschluss nach Norberts Standard: klickbare Links,
max. 1 Terminal-Befehl, Abschnitt „Was Norbert jetzt tut" mit genau EINER Handlung.
