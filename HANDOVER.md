# HANDOVER — krs-projektwahl (kanonisch)

**Ziel / Fertig wenn:** Leck-C-Security abgeschlossen — Codes rotiert, neue Serienbriefe
mit Testlauf verteilt, DSGVO-Notiz fürs DSB-Gespräch fertig.

## Stand 2026-07-12 (Fable-Orchestrator-Session)

- App-Stand: **v48** (Wünsche-Popover), Details in `HANDOVER-2026-07-02-v48-wuensche-popover.md`.
  Ältere v-Dateien bleiben als Archiv; DIESE Datei ist ab jetzt die kanonische Übergabe.
- **Norberts Entscheidungen (12.07.):**
  1. Projektwoche 2026 **läuft noch / steht bevor** → Code-**Rotation** + neue
     Serienbriefe (nicht bloß Deaktivierung).
  2. `07-SECURITY-SPRINT-DETAILPLAN` ist auf dem MacBook **nicht auffindbar**
     (vermutlich Mac Mini); „Leck C" hier nirgends definiert. Beschluss: ohne
     Detailplan weiter, Opus auditiert die DB selbst, Lücke explizit dokumentiert.
- **Sprint-Dateien erstellt (Fable implementiert nie selbst):**
  - `sprint opus krs-projektwahl.md` — Leck-C-Audit, Phasen-Check, Rotations-SQL
    (CHECK → Norbert-OK → UPDATE), DSGVO-1-Seiter. **ZUERST.**
  - `sprint sonnet krs-projektwahl.md` — Serienbriefe + Testlauf-Protokoll + ggf.
    Deploy. Startet erst nach Opus-Übergabe („Input von Opus" ausgefüllt).

## Nächster Schritt

Neue **Opus**-Session öffnen mit: „Lies und arbeite `krs-pw-deploy/sprint opus
krs-projektwahl.md` ab." Danach Sonnet-Session mit der Sonnet-Sprint-Datei.

## Offene Punkte

- Detailplan `07-SECURITY-SPRINT-DETAILPLAN` bei Gelegenheit vom Mini ins Playground
  holen (git/AirDrop) und mit dem Opus-Audit abgleichen.
- Rotation darf erst nach Norberts OK auf die CHECK-Query laufen.
