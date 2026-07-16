# Projekt-Übergabe: KRS Projektwahl 2026 — v24 Sprint C

**Erstellt:** 2026-04-24
**Von:** Norbert + Opus (Sprint C Bundle)
**Stand:** v24 ist lokal fertig (alle 4 Phasen), noch nicht deployed.
**Vorgänger:** v23 (live seit 2026-04-24) — siehe `archive/UEBERGABE-v23-final.md`

---

## 🎯 Ziel von Sprint C

Admin-Dashboard-Bundle für die Projektwoche 2026: Nadine-Flow freischalten, Projekte mit Bildern anreichern, druckfertige PDF-Listen liefern und den Repo entrümpeln. Ein Deploy am Sprint-Ende für alle vier Features gleichzeitig.

---

## ✅ Umgesetzt in v24

| # | Feature | Status |
|---|---------|--------|
| 1 | Nadine-Flow — RLS `projektleitung` + `PASSWORD_RECOVERY`-Modal | ✅ Code + SQL bereit |
| 2 | Projekt-Bilder — Supabase Storage + Upload-UI + Thumbnail-Spalte | ✅ Code + SQL bereit |
| 3 | PDF-Template — Klassen- und Teilnehmerlisten mit KRS-Logo-Header | ✅ Code ready |
| 4 | Repo-Putztag — 66 Alt-Dateien nach `archive/` verschoben | ✅ |

Sprint-D-Kandidaten (nicht in v24): `<EditModal>`-Refactor, Custom Domain `projektwahl.realschule-schriesheim.de`.

---

## 🔍 Was sich in der Codebasis geändert hat

### `admin-dashboard-v2.html` (302 KB, 9263 Zeilen, war 8825)

- **Zeile 796:** `window.KRS_VERSION = 'v24'`
- **Zeile 201–202:** jsPDF 2.5.1 + jspdf-autotable 3.8.2 via cdnjs (UMD, attacht an `window.jspdf.jsPDF`)
- **Nadine-Flow:** `PASSWORD_RECOVERY`-Event-Listener im Auth-Handler, Modal mit Passwort-Setzen-Formular. Rolle `projektleitung` ist im `ALLOWED_SECTIONS`-Set freigeschaltet.
- **Projekt-Bilder:** Feld `bild_url` in Projekt-Model + Edit-Modal + Liste. `uploadProjektBild()`/`deleteProjektBild()`-Handler schreiben in Supabase Storage `projekt-bilder/projekte/<id>.<ext>`. Thumbnail-Spalte ist die 1. Spalte der Projekte-Tabelle (colspan=8).
- **PDF-Template:** `getJsPDF()`, `drawPdfHeader()`, `drawPdfFooter()`, `groupBy()` als Helper; `handleExportKlassenlisten()` (A4 portrait, 1 Seite pro Klasse, Header krs-blau RGB(74,106,131)); `handleExportTeilnehmerlisten()` (A4 portrait, 1 Seite pro Projekt, Header krs-orange RGB(232,119,34), Anwesend-Spalte leer zum Abhaken). Beide nutzen das vorhandene `LOGO_SRC` (base64-JPEG, Zeile 1402).

### `migration-v24-nadine-storage.sql` (NEU, 8,5 KB)

- **Helper-Funktionen** `is_projektleitung()` + `is_app_user()` (SECURITY DEFINER, STABLE).
- **RLS-Policies für `projektleitung`:** voller CRUD auf `projekte`; SELECT auf `users`, `schueler`, `zuteilungen`, `tauschwuensche`, `wahlen`, `verteilungen`, `system_settings`, `feedback`; UPDATE auf `feedback` (Mark-as-done). **Kein** UPDATE auf `system_settings` (Phase bleibt `super_admin`).
- **Storage-Bucket `projekt-bilder`:** public-read, 5 MB Limit, erlaubte MIME-Types `image/{jpeg,png,webp,gif}`. Upload/Update/Delete nur für `is_admin()` ODER `is_projektleitung()`.
- Alle Statements idempotent (CREATE OR REPLACE / DROP IF EXISTS).

### Repo-Putztag — `archive/` (66 Dateien)

- Alle historischen `UEBERGABE-krs-projektwahl-2026-v*.md` (v2–v20 + original).
- Alle v20-Experten-Reviews (`_review-v20-*.md` + `EXPERTEN-REVIEW-*.md` + `REVIEW-V2-ANTWORTEN.md`).
- v22/v23-Übergaben (`UEBERGABE-v22-sonnet-sprint-b.md`, `UEBERGABE-v23*.md`, `SPRINT-0-DEPLOY-V23.md`).
- Planungs-Dokumente (`PROJEKT-BRIEFING.md`, `AUTH-ROADMAP.md`, `IMPORT-ANFORDERUNGEN.md`).
- Backup-HTML (`admin-dashboard-v1.html`, `admin-dashboard-v2.html.bak-pre-sprint-b`).
- Unter `archive/old-migrations/`: 11 alte SQL-Dateien (auth-bridge, rls-phase-b, verteilungsalgorithmus, views-security-invoker, feedback-v23, smoke-tests, all-in-one, set-password-direct, schema-v2 alt, makerspace-seed).
- Unter `archive/deploy-snapshot-v20/`: alter Deploy-Ordner.
- Unter `archive/test-results-v23/`: alte Playwright-Fehler (waren Fehlalarm).
- Nicht referenzierte Legacy-Scripts (`verteilung.js`, `generated-data.js`, `generate_schuelerbrief.py`).

**Im Root verblieben** (alles aktiv genutzt): `admin-dashboard-v2.html`, `schueler-frontend-v3.html`, `index.html`, `admin.html`/`schueler.html` (Redirect-Stubs), `krs-logo.jpg`, `krs-supabase-config.js`, `krs-supabase-service.js`, `beispiel-schuelerbrief.pdf`, `schema-v2-fixed.sql`, `seed-lehrer.sql`, `seed-schueler.sql`, `migration-tauschwuensche-rpcs.sql`, `migration-v24-nadine-storage.sql`, `nadine-einladung.md`, CSV-Templates, `tests/` + `playwright.config.ts` + `package.json`.

---

## 🚀 Deploy-Plan v24 (Reihenfolge einhalten!)

### Schritt 1 — SQL-Migration in Supabase ausführen

1. Supabase Dashboard öffnen → Projekt `uzynvvtsyjfmtywsfxtz` → **SQL Editor**.
2. Inhalt von `migration-v24-nadine-storage.sql` komplett einfügen und **Run** klicken.
3. Sanity-Check (optional, in SQL-Editor):

```sql
-- Helper-Funktionen da?
SELECT routine_name FROM information_schema.routines
  WHERE routine_schema='public' AND routine_name IN ('is_projektleitung','is_app_user');

-- Projektleitung-Policies da?
SELECT policyname, tablename FROM pg_policies
  WHERE schemaname='public' AND policyname LIKE 'projektleitung_%' ORDER BY tablename;

-- Storage-Bucket da?
SELECT id, public, file_size_limit FROM storage.buckets WHERE id='projekt-bilder';
```

### Schritt 2 — HTML deployen (Drag & Drop)

1. `https://github.com/BenditoT/krs-projektwahl-2026/upload/main` öffnen.
2. `admin-dashboard-v2.html` per Drag & Drop hochladen.
3. Commit-Message: `v24: Nadine-Flow + Projekt-Bilder + PDF-Template + Repo-Putztag`.
4. **Commit changes.**
5. 30–60 Sek. warten bis GitHub-Pages gebaut hat.

### Schritt 3 — Lehrkraft 15 einladen

1. Supabase Dashboard → **Authentication** → **Users** → **Invite User**.
2. E-Mail: `nadine.jooss@Realschule-Schriesheim.de`.
3. Nadine bekommt Invite-Mail → Link öffnet Live-App mit `type=recovery`-Query → `PASSWORD_RECOVERY`-Modal öffnet sich → Nadine setzt Passwort.
4. Danach im Admin-Dashboard → **Lehrer** → Nadine anlegen/updaten mit Rolle `projektleitung`.
5. Sobald der `users`-Datensatz mit `auth_user_id` verknüpft ist, sieht Nadine die erlaubten Sections (Dashboard, Projekte, Anmeldungen, Export, Phase, Feedback).

### Schritt 4 — Smoke-Test (live)

Aufrufen: `https://benditot.github.io/krs-projektwahl-2026/?v=v24` (Cache-Buster!)

| Check | Ergebnis |
|-------|----------|
| Login Norbert → alle Tabs sichtbar | ☐ |
| Header zeigt `v24` in Console-Log | ☐ |
| Projekte → Edit → Bild hochladen → Thumbnail in Liste sichtbar | ☐ |
| Projekte → Edit → Bild löschen funktioniert | ☐ |
| Export → PDF „Klassenlisten" lädt (1 Seite pro Klasse, Logo-Header) | ☐ |
| Export → PDF „Teilnehmerlisten" lädt (1 Seite pro Projekt, Anwesend-Spalte leer) | ☐ |
| Export → CSV-Exports funktionieren weiterhin | ☐ |
| FeedbackButton (💬) öffnet Modal, sendet Feedback | ☐ |
| PhaseBadge oben rechts sichtbar, Klick → Phase-Tab | ☐ |
| Login-Gate zeigt KRS-Logo | ☐ |
| Nadine-Login → nur 6 Tabs (Dashboard, Projekte, Anmeldungen, Export, Phase, Feedback) | ☐ Nach Invite |

### Schritt 5 — Memory & Übergabe aktualisieren

- `project_krs_projektwahl_2026.md` auf v24 LIVE bumpen (wenn Deploy gelaufen ist).
- Diese Datei (UEBERGABE-v24.md) als Referenz behalten.

---

## ⚠️ Bekannte Fallstricke

- **SQL-Migration VOR HTML-Deploy laufen lassen**, sonst fehlen Storage-Bucket und RLS-Policies → Bild-Upload crasht, Nadine kann nichts sehen.
- **Chrome-MCP `file_upload` zu GitHub bleibt blockiert** → nur Drag & Drop.
- **Fastly-CDN cached 30–60 Min.** → immer `?v=v24` Cache-Buster beim Smoke-Test.
- **Demo-Modus** zeigt weiterhin alle Tabs (`currentUserRolle = 'super_admin'`). Role-Guard greift nur im Produktiv-Modus mit echtem `users`-Eintrag.
- **JSONB-Felder niemals mit `JSON.stringify()` vor upsert** (v18-Falle, weiter gültig).
- **`projekt_status` enum:** nur `{entwurf, veroeffentlicht}`.

---

## 🔐 Zugänge (unverändert seit v22)

- Supabase URL: `https://uzynvvtsyjfmtywsfxtz.supabase.co`
- Publishable Key: `sb_publishable_kdZSmagc_sbq9qwynebcxw_hKdhyDt1`
- Admin-Login: `lehrkraft22@example.de` / `Krs26PW`
- GitHub-Repo: `BenditoT/krs-projektwahl-2026`
- Live-URL: `https://benditot.github.io/krs-projektwahl-2026/`

---

## 📁 Relevante Dateien im Root

| Datei | Zweck |
|-------|-------|
| `admin-dashboard-v2.html` | Hauptdatei (v24, 9263 Zeilen) |
| `migration-v24-nadine-storage.sql` | In Supabase SQL-Editor ausführen |
| `nadine-einladung.md` | Schritt-für-Schritt für Nadines Invite |
| `schema-v2-fixed.sql` | Referenz-Schema (Stand v20) |
| `seed-lehrer.sql` / `seed-schueler.sql` | Seed-Daten für Neuaufsetzen |
| `migration-tauschwuensche-rpcs.sql` | RPCs für Tauschwünsche (v21, weiter aktiv) |
| `tests/` + `playwright.config.ts` | E2E-Test-Suite (`npm run test:e2e`) |
| `.claude-skills/` | Interne Skills (playwright, opus-sonnet-split) |

---

## 🧭 Einstiegs-Prompt für den nächsten Chat (nach Deploy)

```
KRS Projektwahl 2026 — v24 ist live deployed.

Letzte Übergabe: UEBERGABE-v24.md.
Stand: Sprint C abgeschlossen (Nadine-Flow, Projekt-Bilder, PDF-Template, Repo-Putztag).

Nächste mögliche Aufgaben (Sprint D):
1. <EditModal>-Refactor (alle 4 Views auf gemeinsame Komponente)
2. Custom Domain projektwahl.realschule-schriesheim.de
3. Weitere Quick-Wins aus dem Alltag

Datei: /sessions/<session>/mnt/projekwoche app neu/admin-dashboard-v2.html
Memory: project_krs_projektwahl_2026.md

Bitte erst klären, was als nächstes dran ist, bevor du loslegst.
```

---

## 📝 Commit-Message-Vorschlag

```
v24: Sprint C Bundle — Nadine-Flow + Projekt-Bilder + PDF-Template + Putztag

- RLS-Policies für Rolle projektleitung (is_projektleitung, is_app_user Helper)
- Storage-Bucket projekt-bilder (public-read, 5 MB, Admin+Projektleitung write)
- PASSWORD_RECOVERY-Modal für Invite-Flow (Lehrkraft 15)
- Projekt-Bilder: Upload/Delete + Thumbnail-Spalte in Projekte-Tabelle
- PDF-Export: Klassenlisten (krs-blau) + Teilnehmerlisten (krs-orange) mit Logo-Header
- jsPDF 2.5.1 + autotable 3.8.2 via cdnjs
- Repo-Putztag: 66 Alt-Dateien nach archive/ verschoben
- Version v23 → v24
```
