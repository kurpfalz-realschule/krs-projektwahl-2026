# Sprint E — Übergabe + Plan

**Erstellt:** 2026-04-25
**Vorgänger:** Sprint D (Block A komplett, Block B = Sonnet noch offen)
**Status:** v25 lokal fertig + erweitert um Patches (Bild-Fix, Status-Toggle, Lehrer-Einladen, Auto-Link, Logo-Race-Fix)

---

## 🎯 Wo wir stehen

### v25 Block A — geliefert
- Projektlehrer-Self-Service (RLS+Trigger+View)
- Auto-Link-Trigger `auth.users` → `public.users.auth_user_id`
- Lehrer-Einladen-Button (Magic-Link via `signInWithOtp`)
- Inline-Status-Toggle in Projekte-Tabelle
- Bulk-Veröffentlichen-Button für Projektleitung
- Bild-Upload Demo-Bug gefixt (mockProjekteData wird jetzt mit-mutiert)
- Logo-Race-Condition im Login-Gate gefixt (src wird vor render gesetzt)

### v25 Block B — offen (Sonnet)
- 17 Playwright-Spec-Files (~55 Tests) — siehe SPRINT-D-BRIEFING.md B2
- 3 E2E-Flow-Specs (projektlehrer-self-service, projektleitung-nadine, phase-lifecycle)
- CI-Gate erweitern, `tests/README.md` aktualisieren
- Finale UEBERGABE-v25.md (Sprint-D-Komplett-Übergabe)

---

## 📋 Sprint E — Themen-Vorschläge (priorisiert)

| Prio | Block | Modell | Inhalt | Aufwand |
|------|-------|--------|--------|---------|
| 🔴 Hoch | E0 | Sonnet | **Block B aus Sprint D fertig:** Test-Coverage (17 Specs + 3 Flows) | 4–5 h |
| 🟠 Mittel | E1 | Opus | **Klassenlehrer-Flow** — KlassenlehrerView mit eigener Klasse, fehlende Wahlen, Übersicht | 2–3 h |
| 🟠 Mittel | E2 | Opus | **EditModal-Refactor** — eine Komponente statt 4 Duplikate | 3 h |
| 🟠 Mittel | E3 | Opus | **Schüler-Frontend** auf v24/v25-Schema heben (Bilder anzeigen, Filter, Suche) | 2–3 h |
| 🟡 Nice | E4 | Sonnet | **Notification-Badges** für Projektleitung („X neue Entwürfe", „Y Tauschwünsche") | 1 h |
| 🟡 Nice | E5 | Sonnet | **Lehrer-Reminder-Mail** — wer noch kein Projekt angelegt hat (Bulk-Knopf für Nadine) | 2 h |
| 🟡 Nice | E6 | Opus | **Edge Function für Invites** — eigene `invite-lehrer` mit Service-Role + eigenem Template, statt globalem Magic-Link-Toggle | 2 h |
| ⚪ Bonus | E7 | Sonnet | **Custom Domain** projektwahl.realschule-schriesheim.de | 30 min |
| ⚪ Bonus | Opus | **Schema-Hygiene** — alte RLS-Policies aus schema-v2-fixed.sql aufräumen (`lehrer_id = auth.uid()` ist mit auth_user_id falsch) | 2 h |

**Empfehlung:** E0 zuerst (sonst sammeln wir technische Schuld), dann je nach Druck E1 (Klassenlehrer) oder E2 (Refactor).

---

## 🐛 Offene Bugs / Restthemen aus v25

| Thema | Status | Notiz |
|-------|--------|-------|
| WebSocket-Realtime | Sporadisch failen — Console-Warnung „WebSocket is closed before the connection is established" | Reconnect-Logic einbauen, oder bewusst auf manuellen `loadAll()` setzen |
| Bild-Upload bei Projekten (live, super_admin) | Möglicherweise Bug | Norbert hat „funktioniert nicht" gemeldet — Console-Output noch ausstehend, Tests sollen das in E0 abdecken |
| Logo im Login-Gate | Gefixt in v25.1 (Race-Condition) | Nach Deploy testen |
| E-Mail-Template Magic Link | Norbert hat manuell in Supabase angepasst | Saubere Lösung über Edge Function (E6) |

---

## 📦 Block C aus Sprint D — Optionen, falls noch nicht erledigt

Block C war im SPRINT-D-BRIEFING als optional markiert. Falls in Sprint E aufgenommen:

- **EditModal-Refactor** = E2
- **Custom Domain** = E7

---

## 🔐 Zugänge (unverändert)

- Supabase URL: `https://uzynvvtsyjfmtywsfxtz.supabase.co`
- Publishable Key: `sb_publishable_kdZSmagc_sbq9qwynebcxw_hKdhyDt1`
- Admin-Login: `lehrkraft22@example.de` / `Krs26PW`
- GitHub-Repo: `BenditoT/krs-projektwahl-2026`
- Live-URL: `https://benditot.github.io/krs-projektwahl-2026/`
- Auto-Link-Trigger: `trg_auto_link_app_user` auf `auth.users` (verknüpft `users.auth_user_id`)

---

## 📁 Relevante Dateien

| Datei | Zweck | Stand |
|-------|-------|-------|
| `admin-dashboard-v2.html` | Hauptdatei | v25 + Patches |
| `migration-v25-projektlehrer-rls.sql` | RLS + Trigger + Auto-Link | erweitert |
| `migration-v24-nadine-storage.sql` | Voraussetzung (Helper, Bucket) | live |
| `schema-v2-fixed.sql` | Original-Schema | enthält alte falsche Policies (Sprint-E-Aufräumkandidat) |
| `tests/` + `playwright.config.ts` | Test-Suite | 3 Smoke-Specs (v22.1) — muss in E0 wachsen |
| `SPRINT-D-BRIEFING.md` | Sprint-D-Plan | Block A erledigt, B offen |
| `UEBERGABE-v25-block-a.md` | Block-A-Detail | OK |
| `UEBERGABE-sprint-e.md` | Diese Datei | aktiv |

---

## 🧭 Einstiegs-Prompts

### Für E0 — Test-Coverage (Sonnet)

```
KRS Projektwahl 2026 — Sprint E0 (= Sprint D Block B fertigstellen).
Übergabe: UEBERGABE-sprint-e.md, UEBERGABE-v25-block-a.md.
Briefing: SPRINT-D-BRIEFING.md (Block B Details).

v25 ist live. Keine neuen Features in dieser Session — nur Tests.

Aufgabe (Sonnet):
1. tests/fixtures/app.ts erweitern: loginAs(rolle), ?forceRolle=projektlehrer, resetMockState, Upload-Fixtures
2. 11 CRUD-View-Specs (schueler, dashboard, anmeldungen, verteilung, zuteilungen, tauschwuensche, umbuchung, export, feedback, phase, einstellungen)
3. 6 Cross-Feature-Specs (FeedbackButton, PhaseBadge, Role-Guard, Bild-Upload, PDF-Export, PASSWORD_RECOVERY)
4. 3 E2E-Flow-Specs (flow-projektlehrer-self-service, flow-projektleitung-nadine, flow-phase-lifecycle)
5. CI-Gate-Update (.github/workflows/playwright.yml)
6. tests/README.md aktualisieren
7. UEBERGABE-v25.md final schreiben

Datei: /Users/admin/Downloads/Codex playground/projekwoche app neu/admin-dashboard-v2.html
Memory: project_krs_projektwahl_2026.md
```

### Für E1 — Klassenlehrer-Flow (Opus)

```
KRS Projektwahl 2026 — Sprint E1: Klassenlehrer-Flow.
Übergabe: UEBERGABE-sprint-e.md.

Stand: super_admin / projektleitung / projektlehrer fertig. Klassenlehrer-Rolle existiert im Schema (users.rolle, users.klassenlehrer_von), aber UI fehlt.

Aufgabe (Opus):
1. migration-v26-klassenlehrer.sql — RLS für SELECT auf users/schueler/zuteilungen für eigene Klasse, INSERT/UPDATE/DELETE auf wahlen für Schüler eigener Klasse (UPDATE nur falls Schüler nicht selbst gewählt hat)
2. KlassenlehrerView in admin-dashboard-v2.html — Übersicht eigene Klasse: Anmeldungen, fehlende Wahlen, Zuteilungen
3. ALLOWED_SECTIONS: klassenlehrer = ['mein-klasse'] (oder + 'anmeldungen' filtered)
4. Login-Routing auf 'mein-klasse' bei Rolle klassenlehrer
5. UEBERGABE-sprint-e1.md schreiben

Datei: /Users/admin/Downloads/Codex playground/projekwoche app neu/admin-dashboard-v2.html
```

### Für E2 — EditModal-Refactor (Opus)

```
KRS Projektwahl 2026 — Sprint E2: EditModal-Refactor.
Übergabe: UEBERGABE-sprint-e.md.

Voraussetzung: E0 muss durch sein, damit der Refactor durchs Test-Net abgesichert ist.

Aufgabe (Opus):
1. <EditModal>-Komponente extrahieren mit Props { title, fields, formData, setFormData, onSave, onDelete, onClose, readOnlyFields, helperText }
2. Generische Felder-Schema (text/textarea/number/select/file/readonly)
3. Migration der 4 Duplikate (ProjekteView, LehrerView, ProjektLehrerView, ggf. SchuelerView)
4. Tests laufen lassen — alle Specs grün
5. UEBERGABE-sprint-e2.md
```

---

## 🛠 Was du JETZT machen musst (Patches v25.1)

1. **Migration neu einspielen:** `migration-v25-projektlehrer-rls.sql` (idempotent, kann re-run werden — Auto-Link-Trigger ist neu)
2. **HTML neu hochladen:** Drag&Drop auf https://github.com/BenditoT/krs-projektwahl-2026/upload/main, Commit-Message: `v25.1: Bild-Bug + Status-Toggle + Bulk-Veröffentlichen + Lehrer-Einladen + Logo-Race + Auto-Link`
3. **Cache-Buster:** `?v=v25-2`
4. **E-Mail-Template anpassen:** Supabase → Auth → Email Templates → Magic Link (Text aus Chat übernehmen)
5. **Testen:** Test-Lehrer einladen, Bild hochladen, Status togglen, Bulk-Veröffentlichen probieren
