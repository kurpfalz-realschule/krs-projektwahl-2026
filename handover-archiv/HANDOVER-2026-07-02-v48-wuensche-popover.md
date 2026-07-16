# Übergabe v48 — Wünsche-Popover in der Zuteilungen-View

Erstellt: 2026-07-02 · App: admin-dashboard v47→**v48**

## Anforderung (Norbert)
„In dieser Ansicht soll zu sehen sein, was die Schüler als 1., 2. und 3. Wunsch
gewählt haben" — als Popup/Hover/Akkordeon, ressourcenschonend.

## Lösung
**Klick-Popover** (Hover fällt aus: iPad; Akkordeon macht die 392-Zeilen-Tabelle
unruhig): Die Wahl-Pill in der Zuteilungen-Tabelle ist jetzt ein Button („1. ▾").
Klick öffnet ein Modal mit den drei Wünschen des Schülers, das zugeteilte
Projekt ist mit „✓ zugeteilt" markiert. Ist das zugeteilte Projekt KEINER der
Wünsche (bzw. gar nicht gewählt), erklärt ein Hinweis die manuelle Zuteilung.

Datenfluss ressourcenschonend + datenschutzarm:
- **On-demand:** Wünsche werden erst beim Klick geladen — kein Massen-Payload,
  KEIN Eingriff ins loadAll-Mapping (Normalizer-Drift-Falle umgangen).
- **Produktiv:** neue read-only RPC `admin_schueler_wahlen(p_code)` — EIN
  Schüler pro Aufruf, `SECURITY DEFINER` + `is_app_user()`-Gate, anon revoked.
- **Demo:** clientseitig aus `mockSchueler[*].wahlen` + `mockProjekteData`.

## Geänderte/neue Dateien
- `migration-v48-schueler-wahlen-detail.sql` — **NEU**, read-only RPC (CHECK + Verifikation inkl.)
- `admin-dashboard-v2.html` — Service `schuelerWahlen({code})`, ZuteilungenView:
  `openWuensche()` + klickbare Wahl-Pill (`data-testid="wahl-popover-btn"`),
  `KRS_VERSION = 'v48'`
- `tests/e2e/feature-v48-wuensche-popover.spec.ts` — **NEU** (2 Tests: Wünsche
  mit Markierung; ohne Wahlen → Hinweis)

## Verifikation (diese Session)
- ✅ `node --check` aller 4 Script-Blöcke sauber
- ✅ `tsc -p tsconfig.test.json` fehlerfrei
- ✅ `playwright test --list` erkennt beide v48-Tests
- ⏳ Browser-E2E läuft im **GitHub-Actions-Gate** (Sandbox hat kein Chromium). Bei Grün Auto-Deploy.

## KRS-Fallen-Check (Self-Review)
- **normalizer-drift:** kein neues Feld über loadAll → Mapping unverändert; eigener On-demand-Pfad. ✓
- **stale-closure:** `openWuensche(z)` nutzt nur Row-Daten + frisch gefetchte rows, kein veralteter State. ✓
- **RLS/DSGVO:** Einzelabruf statt Massen-Export, is_app_user-Gate, anon revoked; Zweck (Umbuchungs-Entscheidung) dokumentiert. ✓
- **Service-Kopien:** Methode nur im Admin-Inline-Service — `krs-supabase-service.js` (Schüler-Frontend) braucht sie nicht, bewusst NICHT angefasst. ✓
- **Graceful ohne Migration:** RPC fehlt → Fehler-Toast, App läuft weiter (kein Crash). ✓

## DEPLOY (auf Norberts Mac) — Reihenfolge wichtig!

### 1) Migration zuerst (Supabase SQL-Editor)
`migration-v48-schueler-wahlen-detail.sql` ausführen, dann testen:
`SELECT * FROM admin_schueler_wahlen('<echter Code>');`
(Ohne Migration zeigt das Popover live nur einen Fehler-Toast — kein Schaden, aber keine Daten.)

### 2) Code pushen — Actions testet und deployt bei Grün automatisch
- Actions: https://github.com/kurpfalz-realschule/krs-projektwahl-2026/actions
- Live (Admin): https://kurpfalz-realschule.github.io/krs-projektwahl-2026/admin-dashboard-v2.html

## Offen / Merker
- Die 4 Prototyp-Features vom 2.7. (Abdeckung-zuerst-Verlosung, kosten-Feld,
  Phase-Gate in get_schueler_status, Wünsche in UmbuchungView) sind weiterhin
  NICHT in v48 — eigener Port-Sprint nötig (siehe UEBERGABE-v4 im Prototyp-Ordner).
