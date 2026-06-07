# Handover: KRS Projektwahl 2026 fuer Bugfix-Chats

Stand: 2026-05-21  
Arbeitsordner: `/Users/admin/Downloads/Codex playground/projekwoche app neu`  
Repo: `https://github.com/BenditoT/krs-projektwahl-2026.git`  
Branch: `main`  
Letzter bekannter Live-Commit: `901ed14 fix projektbild reload`

Dieses Dokument ist als Startpunkt fuer einen neuen Codex-Chat gedacht. Es soll helfen, Bugfixes schnell und vorsichtig weiterzufuehren, ohne die Historie des aktuellen Chats zu kennen.

## Aktueller Live-Stand

- GitHub Pages: `https://benditot.github.io/krs-projektwahl-2026/`
- Admin-App: `https://benditot.github.io/krs-projektwahl-2026/admin-dashboard-v2.html`
- Schueler-App: `https://benditot.github.io/krs-projektwahl-2026/schueler-frontend-v3.html`
- Supabase-Projekt: `uzynvvtsyjfmtywsfxtz`
- Supabase-URL: `https://uzynvvtsyjfmtywsfxtz.supabase.co`
- Admin-Version in `admin-dashboard-v2.html`: `window.KRS_VERSION = 'v35';`
- Schueler-Version in `schueler-frontend-v3.html`: `window.KRS_VERSION = 'v34';`

Die App ist eine statische GitHub-Pages-App. Es gibt keinen Build-Schritt fuer die Produktivdateien. HTML, JS und CSS liegen direkt in den grossen Single-File-HTMLs.

## Wichtige Dateien

- `admin-dashboard-v2.html`: Admin/Projektleitungs-App, inkl. Datenservice, UI, Projektverwaltung, Lehrer-/Schuelerlisten, Verteilung und Bild-Upload.
- `schueler-frontend-v3.html`: Schueler-App fuer Code-Eingabe, Projektwahl, Status und Tauschwunsch.
- `tenant.js`: Schulkonfiguration, Branding, Logo, Supabase-URL und Publishable Key. Wird vor den Apps geladen.
- `index.html`: Einstieg/Weiterleitung.
- `tests/e2e/`: Playwright-Tests. Die meisten laufen mit `?forceMode=demo`.
- `playwright.config.ts`: Testserver und Browserkonfiguration.
- `.github/workflows/playwright.yml`: CI und GitHub-Pages-Deploy.
- `migration-v34-projektbilder-persistenz.sql`: letzte wichtige Bild-Migration mit RPC `set_projekt_bild_url`.
- `HANDOVER-v35-projektbilder.md`: Detail-Handover zum zuletzt geloesten Projektbild-Bug.

Wichtig: `krs-supabase-service.js` existiert noch, ist aber fuer die aktuellen HTML-Seiten nicht die alleinige Wahrheit. Die Apps enthalten grosse inline DataService-Implementierungen. Bei Bugfixes zuerst in den HTML-Dateien pruefen, welche Funktion tatsaechlich geladen wird.

## Architektur in einem Satz

Zwei statische Preact/htm Single-Page-Apps sprechen direkt aus dem Browser mit Supabase; Playwright testet lokal gegen die statischen Dateien und erzwingt fuer stabile Tests meist den Demo-Modus.

## Datenbank und Supabase

Zentrale Tabellen/Views/Funktionen:

- Tabellen: `users`, `schueler`, `projekte`, `wahlen`, `zuteilungen`, `tauschwuensche`, `verteilungen`, `system_settings`
- Views: `projekte_public`, `projekte_stats`, `zuteilungen_detail`
- RPCs: `get_schueler_status`, `create_wahl`, `set_projekt_bild_url`
- Storage-Bucket fuer Projektbilder: `projekt-bilder`

Die App nutzt Supabase Auth. Lehrkraefte brauchen Accounts, wenn sie eigene Projekte verwalten sollen. Die Projektleitung/Admin kann Projekte fuer andere anlegen. Lehrer koennen trotzdem Projektinformationen verwalten, wenn ihr Account mit einem `users`-Datensatz und der passenden Rolle bzw. Projektzuordnung verbunden ist.

Supabase CLI ist lokal vorhanden unter `~/.local/bin/supabase` und das Projekt ist mit Supabase verlinkt. Fuer SQL-Dateien wurde zuletzt dieses Muster verwendet:

```bash
~/.local/bin/supabase db query --linked --file migration-v34-projektbilder-persistenz.sql
```

Keine parallelen Supabase-DB-Queries starten. Bei frueheren Arbeiten war die CLI empfindlich gegen parallele Login-/Query-Vorgaenge.

## Letzte groessere Aenderungen

### v33: Zwei Lehrer pro Projekt

- Projekte koennen `lehrer_id` und `lehrer2_id` haben.
- Wenn ein zweiter Lehrer gesetzt ist, sind bis zu 24 Plaetze moeglich.
- Ohne zweiten Lehrer bleibt die normale Obergrenze bei 12 Plaetzen.
- Lehrerduplikate werden verhindert: Lehrer 1 und Lehrer 2 duerfen nicht dieselbe Person sein.
- UI enthaelt Lehrer-2-Auswahl und bessere Plaetze-Eingabe.
- Neue Lehrer- und Schuelerlisten wurden damals in Supabase eingespielt.

### v34: Logo und Projektbild-Persistenz

- Logo kommt aus `tenant.js` bzw. `krs-logo.jpg`.
- Projektbilder werden in Supabase Storage Bucket `projekt-bilder` geladen.
- Bild-URL wird ueber RPC `set_projekt_bild_url` gespeichert.
- Migration: `migration-v34-projektbilder-persistenz.sql`.

### v35: Projektbild verschwindet nach Reload nicht mehr

Live-Bug: Upload funktionierte, aber nach Reload war das Bild weg. Ursache war nicht der Upload, sondern die Admin-Normalisierung in `loadAll()`: `bild_url` wurde aus den Live-Daten nicht in `window.MOCK_PROJEKTE` uebernommen.

Fix in `admin-dashboard-v2.html`:

```js
bild_url: p.bild_url || null,
```

Danach lokal `npm run test:typecheck` und `npm run test:e2e` erfolgreich. GitHub Actions und Pages Deploy waren erfolgreich.

## Bugfix-Workflow

1. Zustand pruefen:

```bash
git status --short --untracked-files=all
git log -1 --oneline
```

Im Arbeitsordner liegen viele untracked Alt-/Archivdateien. Nicht blind `git add .` nutzen. Immer nur die tatsaechlich geaenderten Dateien stagen.

2. Reproduktion suchen:

```bash
npm run serve
```

Dann lokal z.B.:

- `http://127.0.0.1:4173/admin-dashboard-v2.html?forceMode=demo`
- `http://127.0.0.1:4173/schueler-frontend-v3.html?forceMode=demo`

3. Quelle der Wahrheit finden:

- Fuer Admin-Bugs fast immer `admin-dashboard-v2.html`.
- Fuer Schueler-Bugs fast immer `schueler-frontend-v3.html`.
- Bei geteilter Datenlogik beide Dateien vergleichen.
- Besonders kritisch: `loadAll()`, `listProjekte()`, Formular-Save-Handler, Demo-Daten und Live-Normalisierung.

4. Test ergaenzen oder bestehenden Test erweitern.

Playwright-Tests liegen in `tests/e2e/`. Fuer neue UI-Bugs moeglichst einen gezielten Test schreiben. Viele bisherige Tests laufen im Demo-Modus; Live-/RLS-/Supabase-Schema-Bugs koennen dadurch unentdeckt bleiben. Wenn ein Bug nur live auftritt, zusaetzlich per Supabase Query oder Live-Browser pruefen.

5. Lokal pruefen:

```bash
npm run test:typecheck
npm run test:e2e -- tests/e2e/<gezielter-test>.spec.ts
npm run test:e2e
```

6. Deploy:

```bash
git add <genaue-dateien>
git commit -m "<kurze beschreibung>"
git push origin main
gh run list --branch main --limit 3
gh run watch <run-id> --exit-status
```

GitHub Actions deployed nur bei Push auf `main` und nur, wenn sich relevante Pfade aendern:

- `admin-dashboard-v2.html`
- `schueler-frontend-v3.html`
- `index.html`
- `tests/**`
- `playwright.config.ts`
- `package.json`
- `.github/workflows/playwright.yml`

Nur Dokumentationsaenderungen loesen aktuell keinen Pages-Deploy aus.

7. Live verifizieren:

```bash
curl -L https://benditot.github.io/krs-projektwahl-2026/admin-dashboard-v2.html | rg "KRS_VERSION|gesuchter-fix"
curl -L https://benditot.github.io/krs-projektwahl-2026/schueler-frontend-v3.html | rg "KRS_VERSION|gesuchter-fix"
```

GitHub Pages kann cachen. Bei Browserpruefung hart neu laden oder Cache umgehen.

## Typische Fallen

- Demo-Modus ist nicht gleich Live-Modus. Ein Test mit `?forceMode=demo` kann gruen sein, obwohl Supabase-Live-Daten anders normalisiert werden.
- `loadAll()` kopiert Live-Daten in globale Mock-/State-Arrays. Wenn dort ein Feld fehlt, wirkt es live wie "gespeichert, aber wieder verschwunden".
- Nach Supabase-Migrationen kann der PostgREST Schema Cache kurz hinterherhinken. Fehlermeldungen wie `schema cache` oder `Could not find the function` ernst nehmen.
- Das Admin-HTML ist sehr gross. Kleine, gezielte Patches sind sicherer als grobe Refactors.
- Lehrer-Projekt-Rechte haengen an `lehrer_id` und `lehrer2_id`. Bei Bugfixes fuer "Mein Projekt" immer beide IDs beruecksichtigen.
- Die `tenant.js`-URLs enthalten aktuell noch eine alte `schueler_url` mit `schueler.html`; die sichtbare Schueler-App ist aber `schueler-frontend-v3.html`. Vor Aenderungen pruefen, welche Stelle diese URL benutzt.
- Nicht ungefragt alte Archivdateien, `.claude-skills`, Skill-Patches oder untracked Legacy-Dokumente stagen.

## Pruefbefehle fuer aktuelle Bildfunktion

Live-HTML enthaelt v35 und Bild-Normalisierung:

```bash
curl -L https://benditot.github.io/krs-projektwahl-2026/admin-dashboard-v2.html \
  | rg "KRS_VERSION = 'v35'|bild_url: p\\.bild_url"
```

Supabase-Projektbild pruefen, wenn Zugriff vorhanden:

```sql
select id, titel, bild_url
from public.projekte
where titel ilike '%Makerspace%';

select id, titel, bild_url
from public.projekte_public
where titel ilike '%Makerspace%';
```

Beide Abfragen sollten eine `bild_url` zeigen, wenn ein Bild gesetzt ist.

## Kommunikation/Material

Bereits vorhandene Entwuerfe:

- `MAIL-Kollegium-Projektwoche-Accounts.md`: Mail an Kollegium zu Accounts, Supabase-Absender und Bedienung.
- `MAIL-Nadine-Aenderungen-v33.md`: Zusammenfassung/Anweisungen fuer Nadine.
- `DEPLOY-v33-zwei-lehrer-und-listen.md`: Deploy-Notizen zu v33.
- `HANDOVER-v35-projektbilder.md`: Detailuebergabe zum Projektbild-Bug.

## Vorschlag fuer einen neuen Chat

Wenn ein neuer Chat uebernimmt, am besten so starten:

```text
Lies bitte zuerst HANDOVER-projekt-bugfixes.md und HANDOVER-v35-projektbilder.md.
Arbeitsordner ist /Users/admin/Downloads/Codex playground/projekwoche app neu.
Bitte pruefe vor Aenderungen git status, stage keine untracked Altdateien, und arbeite bei Bugfixes zuerst mit gezielten Playwright-Tests.
Aktueller Live-Stand ist main @ 901ed14, Admin v35, Schueler v34.
```

