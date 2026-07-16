# Sprint D — Block A (Opus) abgeschlossen

**Datum:** 2026-04-25
**Status:** Code lokal fertig — **noch nicht deployed**
**Nächster Schritt:** Block B (Sonnet-Session) — Test-Coverage + Spec-Files + UEBERGABE-v25.md

---

## ✅ Geliefert

| # | Artefakt | Status |
|---|----------|--------|
| 1 | `migration-v25-projektlehrer-rls.sql` | ✅ NEU, 270 Zeilen, idempotent |
| 2 | `ProjektLehrerView` in `admin-dashboard-v2.html` | ✅ ergänzt (~230 neue Zeilen) |
| 3 | Login-Routing auf Rolle | ✅ angepasst |
| 4 | Version-Bump v24 → v25 | ✅ |

---

## 🔍 Was sich geändert hat

### `migration-v25-projektlehrer-rls.sql` (NEU, 9,3 KB)

| Block | Inhalt |
|-------|--------|
| 1 | Helper `is_projektlehrer()` (auth_user_id → rolle='projektlehrer') |
| 2 | Helper `current_app_user_id()` (liefert `users.id` zum aktuellen `auth.uid()`) |
| 3 | RLS auf `projekte`: SELECT/INSERT/UPDATE für projektlehrer **nur eigene** (`lehrer_id = current_app_user_id()`). DELETE bewusst NICHT. |
| 4 | Trigger `enforce_projektlehrer_whitelist()` (BEFORE INSERT/UPDATE): erzwingt `status='entwurf'` + `lehrer_id=self` bei INSERT, blockt UPDATE auf `lehrer_id`/`status`/`min_klasse`/`max_klasse`/`min_teilnehmer`/`max_plaetze`. super_admin und projektleitung sind unbeschränkt (frühes Return). |
| 5 | RLS `users`: projektlehrer darf eigene Zeile lesen (für `getCurrentDbUser()`). |
| 6 | Storage: Helper `storage_path_belongs_to_lehrer(name)` parst `projekte/<uuid>.<ext>` und prüft Owner. INSERT/UPDATE/DELETE-Policies für `projekt-bilder` für projektlehrer. SELECT bleibt public aus v24. |

**Sicherheits-Befund Reviewer:** RLS + Trigger blockt alle 4 Attack-Vektoren (fremd lesen, fremd editieren, Whitelist umgehen, fremdes Bild hochladen). ✓

### `admin-dashboard-v2.html` (~230 Zeilen +)

- **Zeile 796:** `window.KRS_VERSION = 'v25'`.
- **App-State (~6320–6325):** neuer `currentDbUserId`-State.
- **Effect (~6390–6400):** lädt `dbUser.id`; setzt `activeSection = 'mein-projekt'` bei Rolle `projektlehrer`, `'anmeldungen'` bei `klassenlehrer`.
- **ALLOWED_SECTIONS (~6450–6463):** `projektlehrer: new Set(['mein-projekt'])`. super_admin (null) sieht alles inkl. „Mein Projekt" (Briefing-Risiko #5).
- **Nav-Item (~6498):** `📚 Mein Projekt` — Visibility via ALLOWED_SECTIONS-Filter.
- **Routing-Switch (~6568):** `${activeSection === 'mein-projekt' && html\`<\${ProjektLehrerView} ... />\`}`.
- **Komponente `ProjektLehrerView` (~7493–7720):** Kartenraster eigener Projekte, Edit-Modal mit Whitelist-UI (titel, kurzbeschreibung, langbeschreibung, ort, bild_url editierbar; min/max/Klassen/Status read-only). „Neues Projekt"-Button nur in Phase `setup`/`anmeldung`. Defensiver Frontend-Guard im `openEditModal`. Demo-Modus mit Fallback-Owner.

---

## 🚀 Deploy-Plan v25 (Reihenfolge zwingend)

1. **SQL-Migration:** Supabase SQL-Editor → `migration-v25-projektlehrer-rls.sql` einspielen. (v24-Migration ist Voraussetzung — v25 referenziert `is_admin()`, `is_projektleitung()`, `auth_user_id`.)
2. **HTML deployen:** `https://github.com/BenditoT/krs-projektwahl-2026/upload/main` → Drag&Drop → Commit `v25: Sprint D Block A — Projektlehrer-Self-Service (RLS + Trigger + Mein-Projekt-View)`.
3. **Cache-Buster:** `?v=v25`.
4. **Smoke-Test (Schritt 4 unten).**
5. **Lehrer einladen** (Empfehlung Block B-Quick-Win): erstmal manuell via Supabase Auth Invite, danach `users.rolle = 'projektlehrer'` setzen, danach Lehrer als `lehrer_id` an mind. einem Projekt eintragen lassen.

---

## 🧪 Smoke-Test v25 (live)

| Check | OK? |
|-------|-----|
| Norbert-Login (super_admin) → alle Tabs sichtbar inkl. „📚 Mein Projekt" | ☐ |
| Norbert sieht in „Mein Projekt" nur Projekte mit `lehrer_id = Norbert` | ☐ |
| Test-Projektlehrer-Login (z.B. Testaccount mit rolle='projektlehrer') → nur „Mein Projekt"-Tab sichtbar | ☐ |
| Projektlehrer sieht in der Karten-Liste **ausschließlich** eigene Projekte | ☐ |
| Edit-Modal: titel/kurzbeschreibung/langbeschreibung/ort/bild editierbar | ☐ |
| Edit-Modal: Plätze/Klassen/Status werden im Read-Only-Block angezeigt, nicht editierbar | ☐ |
| Speichern als Projektlehrer → DB-Update funktioniert ohne Fehler | ☐ |
| Manueller Versuch in DevTools, mit `service.updateProjekt(id, {status:'veroeffentlicht'})` zu mogeln → wirft Trigger-Exception | ☐ |
| „Neues Projekt"-Button nur in Phase setup/anmeldung sichtbar | ☐ |
| Bild-Upload zu eigenem Projekt funktioniert | ☐ |
| Manueller Versuch, Bild zu Pfad `projekte/<fremde-uuid>.jpg` hochzuladen → Storage-Policy blockt | ☐ |

---

## 🎯 Nächste Schritte (Block B — Sonnet)

Aus dem Sprint-D-Briefing:

**B1 · Test-Infrastruktur:** `loginAs(rolle)`-Helper, `?forceRolle=projektlehrer`-Override, `resetMockState()`, Upload-Fixtures.

**B2 · Spec-Files (17 Stück, ~55 Tests):** 11 CRUD-View-Specs + 6 Cross-Feature-Specs (Role-Guard, Bild-Upload, PDF, PASSWORD_RECOVERY, FeedbackButton, PhaseBadge).

**B3 · CI + Doku:** workflow-Update, `tests/README.md`, finale `UEBERGABE-v25.md` (Sprint-D-Komplett-Übergabe).

**3 E2E-Flow-Specs (Block A-Pflicht, hier offen für Block B):**
- `flow-projektlehrer-self-service.spec.ts`
- `flow-projektleitung-nadine.spec.ts`
- `flow-phase-lifecycle.spec.ts`

---

## ⚠️ Bekannte Restrisiken

| Risiko | Mitigation |
|--------|------------|
| Erste Render-Phase: `currentDbUserId` ist null → `ownProjekte=[]` für ~200–500 ms | Kosmetisch — `loadAll()` füllt das. Loading-Overlay deckt es ab. |
| Mock-Demo: Fallback-Owner nimmt ersten projektlehrer aus `mockLehrerData` — passt, solange dort einer drin ist. | Demo-Daten enthalten >40 projektlehrer. ✓ |
| Trigger blockiert UPDATE auf `created_at` durch `NEW.created_at := OLD.created_at` — sollte nicht stören, weil keiner das absichtlich ändert. | OK |
| `projekt-bilder`-Bucket-INSERT von v24 kommt **nicht** in v25 vor — wenn jemand v25 ohne v24 spielt, fehlt der Bucket. | Migration-Header sagt das explizit. v24 ist Pflichtvoraussetzung. |

---

## 🧭 Einstiegs-Prompt für Block B (Sonnet)

```
KRS Projektwahl 2026 — Sprint D Block A ist lokal fertig (noch nicht deployed).
Übergabe: UEBERGABE-v25-block-a.md.
Briefing: SPRINT-D-BRIEFING.md (v2 kompakt).

Beginne mit Block B (Sonnet): Test-Coverage + Spec-Files.
1. Test-Fixtures erweitern (loginAs(rolle), ?forceRolle=projektlehrer, resetMockState, Upload-Fixtures)
2. 17 Spec-Files (11 CRUD-Views + 6 Cross-Feature) anlegen
3. 3 E2E-Flow-Specs für die neue Projektlehrer-Rolle
4. CI-Gate aktualisieren, tests/README.md, UEBERGABE-v25.md (Sprint-D-Komplett-Übergabe)

Datei: /Users/admin/Downloads/Codex playground/projekwoche app neu/admin-dashboard-v2.html
Memory: project_krs_projektwahl_2026.md
```

---

## 📁 Relevante Dateien

| Datei | Zweck |
|-------|-------|
| `admin-dashboard-v2.html` | Hauptdatei (v25, ~9510 Zeilen) |
| `migration-v25-projektlehrer-rls.sql` | NEU — in Supabase SQL-Editor ausführen |
| `migration-v24-nadine-storage.sql` | Voraussetzung (Helper-Functions, Bucket) |
| `SPRINT-D-BRIEFING.md` | Sprint-Plan v2 kompakt |
| `UEBERGABE-v24.md` | Vorgänger-Übergabe |
