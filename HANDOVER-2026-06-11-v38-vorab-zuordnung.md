# Projekt-Übergabe: KRS Projektwahl 2026 — v38 „Vorab-Zuordnung"
Erstellt am: 2026-06-11
Von: Cowork-Session (Vorab-Zuordnung ganzer Klassen + Einzelschüler)

---

## 🎯 Was v38 kann

Ganze Klassen (z.B. **7a + 7d**) und Einzelschüler (z.B. Französisch-Gruppe) können
**vor der Anmeldephase** fest einem Projekt zugeordnet werden. Diese Zuordnungen sind
**fixiert**: Die Schüler müssen nicht wählen, die Verlosung überspringt sie, rechnet
ihre Plätze an — und löscht sie beim Commit **nicht** mehr (vorher Datenverlust-Bug!).

## ✅ Änderungen in dieser Session

| Bereich | Änderung |
|---|---|
| **Migration** | `migration-v38-vorab-zuordnung.sql` — ⚠️ **VOR dem Deploy in Supabase ausführen!** Nicht-destruktiv (nur neue Spalte + Funktions-Updates, kein Datenverlust) |
| **DB: fixiert-Spalte** | `zuteilungen.fixiert BOOLEAN DEFAULT FALSE` + Backfill (bestehende manuelle Zuordnungen mit `wahl_nr IS NULL` → fixiert) |
| **DB: admin_bulk_assign** | Neue RPC: Bulk-Zuordnen (auch Entwurf-Projekte, mit Hinweis) und Bulk-Aufheben (`p_projekt_id = NULL`). Nur Admins |
| **DB: run_verteilung** | Überspringt fixierte Schüler, belegt deren Plätze vor, Commit löscht nur `fixiert = FALSE`. Statistik enthält jetzt `fixiert` |
| **DB: admin_list_schueler** | **Bugfix:** liefert jetzt `hat_gewaehlt`, `zuteilung`, `wahl_nr`, `fixiert` mit — vorher zeigte der Schüler-Tab im Live-Modus nie Status/Zuteilung an |
| **DB: update_zuteilung / klassenlehrer_assign_schueler** | Setzen jetzt `fixiert = TRUE` (manuelle Eingriffe überleben eine erneute Verlosung) |
| **Admin: Mehrfach-Klassenfilter** | Klassen-Dropdown mit Checkboxen (`data-testid="klassen-filter"`), mehrere Klassen gleichzeitig, schließt bei Klick außerhalb |
| **Admin: Bulk-Zuordnung** | Auswahl-Leiste: „📌 Projekt zuordnen (N)" → Modal mit Projekt-Dropdown (Belegung, Klassenstufen, Entwurf-Warnung, Überbuchungs-Warnung) + „↩️ Zuordnung aufheben" mit confirm() |
| **Admin: Status-Pill** | Fixierte Schüler zeigen „📌 zugeordnet" statt „⏳ fehlt" |
| **Admin: CSV-Export** | Neuer Button „📤 CSV exportieren" (gefilterte Liste bzw. alle, BOM für Excel) — funktioniert in Demo UND Live |
| **Demo-Verlosung** | `verteile()` akzeptiert `fixierte[]`, Demo-`runVerteilung` liest sie aus `window.mockSchueler` |
| **Schüler-App** | Vorab zugeordnete Schüler sehen in Phase „anmeldung" direkt ihr Projekt (kein Wahlformular, kein Tauschwunsch-Button) |
| **Tests** | `tests/e2e/feature-vorab-zuordnung.spec.ts` — 6 neue Tests (Filter, Bulk-Zuordnen, Aufheben, Verlosung, CSV-Export, Schüler-App). `tsc` clean, `--list` ok |
| **Version** | Beide Apps auf **v38** |

## 🚀 Deploy-Reihenfolge (wichtig!)

**Schritt 1 — Migration in Supabase** (zuerst, sonst fehlt dem neuen Frontend die RPC):

```
cd "/Users/admin/Downloads/Codex playground/projekwoche app neu"
~/.local/bin/supabase db query --linked --file migration-v38-vorab-zuordnung.sql
```

Alternativ: Inhalt der Datei im Supabase SQL-Editor als Ganzes ausführen.
Die Kontroll-SELECTs am Ende müssen die Spalte `fixiert` und 5 Funktionen zeigen.

**Schritt 2 — Push** (CI testet, bei Grün automatischer Deploy):

```
cd "/Users/admin/Downloads/Codex playground/projekwoche app neu"
git add admin-dashboard-v2.html schueler-frontend-v3.html migration-v38-vorab-zuordnung.sql tests/e2e/feature-vorab-zuordnung.spec.ts HANDOVER-2026-06-11-v38-vorab-zuordnung.md
git commit -m "v38: Vorab-Zuordnung — Bulk-Zuordnung ganzer Klassen, Mehrfach-Klassenfilter, fixierte Zuteilungen, CSV-Export"
git push
```

Actions: https://github.com/BenditoT/krs-projektwahl-2026/actions

**Schritt 3 — Verifikation live:** Admin öffnen → Schüler-Tab → Klassenfilter zeigt
Checkbox-Dropdown, Button „📤 CSV exportieren" vorhanden, Konsole meldet v38.

## 📌 Bedienung (Kurzanleitung für Norbert)

1. Schüler-Tab → Klassenfilter → z.B. **7A** und **7D** anhaken
2. Kopf-Checkbox in der Tabelle → alle gefilterten ausgewählt
3. **„📌 Projekt zuordnen"** → Projekt wählen → bestätigen
4. Einzelschüler (Französisch): per Suche/Checkbox einzeln dazu — Klassenfilter egal, die Auswahl bleibt über Filterwechsel erhalten
5. Korrektur: auswählen → **„↩️ Zuordnung aufheben"**

⚠️ Projekt sollte **veröffentlicht** sein, bevor Schüler ihren Code eingeben —
sonst sehen sie „Zuteilung lässt sich nicht laden". Das Modal warnt bei Entwürfen.

## ⏭️ GitHub-URL ohne „BenditoT" (offen, Entscheidung getroffen: Org)

Kurzlink reicht NICHT (Adresszeile zeigt nach Redirect trotzdem benditot.github.io).
Plan: **GitHub-Organisation** gründen (z.B. `krs-projektwahl`), Repo dorthin übertragen:

1. github.com → Settings → Organizations → **New organization** (Free) → Name z.B. `krs-projektwahl`
2. Repo `BenditoT/krs-projektwahl-2026` → Settings → ganz unten **Transfer ownership** → an die Org
3. In der Org: Repo → Settings → Pages → Source „GitHub Actions" wieder aktivieren (Secrets/Actions wandern mit, Pages-Aktivierung neu prüfen)
4. Neue URL: `https://krs-projektwahl.github.io/krs-projektwahl-2026/`
5. **`tenant.js` anpassen** (frontend_url, schueler_url) + `nadine-einladung.md`/Supabase Auth Redirect-URLs (Magic-Link!) auf neue Domain umstellen
6. Lokales Repo: `git remote set-url origin https://github.com/krs-projektwahl/krs-projektwahl-2026.git`
7. Optional: Bitly-Kurzlink + QR für die Serienbriefe — zeigt dann auf die neutrale URL

⚠️ Die alte Pages-URL `benditot.github.io/...` funktioniert nach dem Transfer NICHT mehr
(github.com-Links leiten um, Pages-URLs nicht) — Serienbriefe erst NACH dem Umzug drucken.

## ⚠️ Stolpersteine (geerbt + neu)

1. Migration v37 (`migration-v37-termine-seed.sql`) war laut v37-Handover evtl. noch nicht ausgeführt — prüfen!
2. Cowork-Sandbox kann nicht pushen / kein lokales Playwright — CI ist das Test-Gate
3. Untracked Altdateien nie mitstagen — immer einzeln `git add <datei>`
4. Demo-`mockSchueler` hat nur 6 Schüler (5a–10b je 1) — Tests seeden eigene via `seedMockData`
5. `schueler.html` ist nur ein Redirect auf `schueler-frontend-v3.html` — nichts zu syncen
6. CSV-**Import** im Live-Modus weiterhin nicht aktiv (bewusste Fehlermeldung)

## 📋 Offene Aufgaben (Rest v37, Reihenfolge-Vorschlag)

| # | Aufgabe | Aufwand |
|---|---|---|
| 1 | Schüler-App: sichtbare Fehlerbanner + Retry (statt Konsole) | 1–2 h |
| 2 | Mobile-Polish Schüler-App + Playwright-Mobile-Project | 2–4 h |
| 3 | GitHub-Org-Umzug (siehe oben) + tenant.js + Auth-Redirects | 1 h |
| 4 | Audit-Log + Undo (Roadmap #6, RLS mitdenken!) | ~14 h |
| 5 | Bulk-Actions Projekte-Tabelle (Schüler-Seite ist mit v38 erledigt) | ~3 h |

---

## 🚀 Einstiegs-Prompt für neuen Chat

> Ich arbeite an der KRS Projektwahl-App (Kurpfalz-Realschule Schriesheim).
> **Workspace:** /Users/admin/Downloads/Codex playground/projekwoche app neu/
> **Stack:** Zwei Single-File Preact-Apps (admin-dashboard-v2.html, schueler-frontend-v3.html) + Supabase. Demo-Modus via ?forceMode=demo. 107 Playwright-Tests als CI-Deploy-Gate.
> **Stand:** v38 fertig gebaut (Vorab-Zuordnung ganzer Klassen, fixierte Zuteilungen, CSV-Export) — lies HANDOVER-2026-06-11-v38-vorab-zuordnung.md für Details, Deploy-Reihenfolge und offene Aufgaben.
>
> Wichtig: Ich bin Lehrer, kein Profi-Entwickler — Schritt für Schritt, Pläne als Tabellen, deutsch. Du kannst nicht pushen und kein lokales Playwright — Push mache ich im Terminal (Befehle ohne #-Kommentare, mit cd-Zeile). Bei Schema-Änderungen Migration mitdenken (idempotent + Kontroll-SELECT).
