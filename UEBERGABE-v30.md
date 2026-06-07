# UEBERGABE v30 — KRS Projektwahl 2026
**Datum:** 2026-04-27
**Sprint:** v29 Mega-Bundle (E1.6 + E1.7 + E1.8)
**Status:** ✅ 82/82 Tests grün · 1 SQL-Run + 1 deploy = fertig

---

## 🚀 Was in dieser Session passiert ist — drei Sprints in einem Rutsch

### E1.8 — Security-Patch `update_zuteilung` UND `run_verteilung`
- Beide RPCs haben jetzt einen Caller-Rollencheck (`is_admin()` = super_admin OR projektleitung) als ersten Schritt im Body.
- Vorher: `GRANT EXECUTE ... TO anon, authenticated` — *jeder* anon-Aufruf konnte Schüler umbuchen oder eine Verteilung starten.
- Nachher: `REVOKE FROM anon, PUBLIC; GRANT TO authenticated` + Body-Guard. Defense in depth.
- Body von `run_verteilung` ist sonst **identisch** zu v10 (kopiert aus `archive/old-migrations/migration-verteilungsalgorithmus.sql`).
- Frontend behandelt neue Errors `nicht_eingeloggt` / `nicht_berechtigt` automatisch über das existierende `r.success === false` → Toast-Pattern. Kein Frontend-Änderung nötig.

### E1.7 — Title→ID Cleanup in UmbuchungView/ZuteilungenView
- `mockSchueler.zuteilung` ist jetzt **konsistent eine Projekt-ID** (KlassenlehrerView seit E1.5, jetzt auch UmbuchungView ab v29).
- Globaler Helper `resolveProjektTitel(idOrTitle)` in `admin-dashboard-v2.html` (~6375), defensiv: akzeptiert ID *oder* Legacy-Title.
- ZuteilungenView Demo-Synthese (~8810): liest `s.zuteilung`, lookup'd `projekt_id` + `projekt_titel`, fallback auf rohen Wert wenn nichts gefunden.
- SchuelerView Liste (~7286): zeigt aufgelösten Titel statt UUID.
- UmbuchungView (~9032):
  - Demo-Pfad schreibt `selectedStudent.zuteilung = projObj.id`, setzt `hat_gewaehlt = true`, dispatcht `'krs:mock-seeded'` für Cross-View-Refresh.
  - History-Eintrag (`mockUmbuchungen`) speichert *Titel* als Display-Snapshot (gut für die "Letzte Umbuchungen"-Tabelle).
  - `mockUmbuchungen` jetzt auf `window` exposed (für Tests).

### E1.6 — Erinnerungs-Trigger in KlassenlehrerView
- Button "📧 Erinnerung an X offene Schüler" (`data-testid="klassenlehrer-erinnerung-btn"`) im Header der KlassenlehrerView.
- Erscheint nur wenn `offeneSchueler.length > 0` (offen = ohne `hat_gewaehlt` UND ohne `zuteilung`).
- Klick öffnet ein neues Browserfenster mit druckfertiger Liste:
  - Klassenname + Datum + Counter
  - Tabelle: Name · Anmelde-Code · Anmelde-URL
  - Print-Stylesheet (`@media print`)
  - Druck-Button im Popup
- **Keine Mailto-Lösung**, weil Schüler keine eigenen E-Mail-Adressen im Schema haben (siehe `schema-v2-fixed.sql`).
- Globaler `htmlEscape`-Helper (~6385) für sichere Popup-HTML-Generierung.

---

## 📊 Test-Stand

| Spec-File | Tests | Status |
|-----------|-------|--------|
| (alle v28-Specs + flow-klassenlehrer) | 76 | ✅ |
| **flow-umbuchung-cleanup (E1.7 +3)** | 3 | ✅ |
| **flow-erinnerung (E1.6 +3)** | 3 | ✅ |
| **GESAMT** | **82** | **✅** |

Vollständiger Lauf lokal: `82 passed (2.3m)`

### Neue Specs

**`tests/e2e/flow-umbuchung-cleanup.spec.ts`** (E1.7)
1. Demo-Umbuchung speichert `mockSchueler.zuteilung` als Projekt-ID
2. UmbuchungView History zeigt Titel (nicht ID) für altes/neues Projekt
3. ZuteilungenView Demo-Synthese resolvt sowohl ID als auch Legacy-Titel

**`tests/e2e/flow-erinnerung.spec.ts`** (E1.6)
1. Button erscheint nicht wenn alle Schüler angemeldet sind
2. Button zeigt Counter und ist sichtbar wenn ≥1 offen
3. Klick öffnet Druckansicht (window.open) mit Klassenname und Schüler-Codes

---

## 🎯 Deploy-Schritte — minimal

### EINMAL Frontend deployen
```
deploy
```
(`git push origin main` → Actions → bei grün live auf https://benditot.github.io/krs-projektwahl-2026/)

### EINMAL SQL in Supabase ausführen
1. Supabase Dashboard → KRS-Projekt → SQL Editor → **+ New query**
2. Inhalt von `migration-v29-bundle.sql` (415 Zeilen) reinkopieren → **Run**
3. Erwartet: `Success. No rows returned`

### Verifikation (4 SQL-Queries im SQL-Editor)
```sql
-- a) Beide Funktionen vorhanden + SECURITY DEFINER?
SELECT proname, prosecdef FROM pg_proc
 WHERE proname IN ('run_verteilung', 'update_zuteilung');
-- → 2 Zeilen, prosecdef = true

-- b) anon hat KEIN EXECUTE mehr?
SELECT
  has_function_privilege('anon', 'public.run_verteilung(text, boolean, uuid)', 'EXECUTE')   AS run_anon,
  has_function_privilege('anon', 'public.update_zuteilung(text, uuid, uuid, text)', 'EXECUTE') AS upd_anon;
-- → beide false

-- c) authenticated hat EXECUTE?
SELECT
  has_function_privilege('authenticated', 'public.run_verteilung(text, boolean, uuid)', 'EXECUTE')   AS run_auth,
  has_function_privilege('authenticated', 'public.update_zuteilung(text, uuid, uuid, text)', 'EXECUTE') AS upd_auth;
-- → beide true
```

### Live-Smoke-Tests
- Als Admin in "Manuelle Umbuchung" → Schüler umbuchen → muss durchgehen
- Als Admin Verteilung neu starten → muss durchgehen
- Als Klassenlehrer → "Meine Klasse" → Erinnerungs-Button → Druckdialog erscheint

---

## 🐛 Bekannte Lücken / Out of Scope

### `update_zuteilung` Body-Klassenstufenprüfung
Der Body lehnt eine Klassenstufen-Mismatch nicht ab — er flagged sie nur via `hinweis: 'klassenstufe_ausserhalb_X_Y'`. Das ist Absicht (Admin darf bewusst gegen die Range buchen, z.B. bei Sonderfällen) und unverändert seit v10.

### Erinnerung als Email
Schüler haben keine Mailadressen im Schema. Wenn künftig E-Mail-Versand gewünscht ist, müsste:
- Schema erweitert werden (`schueler.eltern_email`)
- Edge Function in Supabase für Versand
- Oder: SMTP via Resend / Mailgun

Aktuell: Druckliste reicht für die meisten Klassenleiter-Workflows.

### `klassenlehrer_*` RPCs
Die in v28 deployten RPCs sind sauber rollenscoped — kein Patch nötig.

---

## 📁 Dateien geändert/neu

| Datei | Änderung |
|-------|----------|
| `migration-v29-bundle.sql` | **NEU** — Caller-Check + REVOKE für `update_zuteilung` + `run_verteilung` |
| `admin-dashboard-v2.html` | Helper `resolveProjektTitel` + `htmlEscape` (global), KlassenlehrerView Erinnerungs-Button, UmbuchungView Title→ID Cleanup, ZuteilungenView Demo-Lookup, SchuelerView Titel-Anzeige, `window.mockUmbuchungen` exposed |
| `tests/e2e/flow-umbuchung-cleanup.spec.ts` | **NEU** — 3 Specs E1.7 |
| `tests/e2e/flow-erinnerung.spec.ts` | **NEU** — 3 Specs E1.6 |
| `migration-v29-update-zuteilung-rollencheck.sql` | gelöscht (redundant zum Bundle) |

---

## 🔑 Wichtige Patterns (v30 Erweiterung)

10. **Globaler Helper-Slot in `admin-dashboard-v2.html`** — direkt nach `showToast` (~6376), vor `function App()`. Hier liegen `resolveProjektTitel`, `htmlEscape`. Cross-Component-Helper.
11. **`mockSchueler.zuteilung` ist immer eine Projekt-ID** — KlassenlehrerView und UmbuchungView schreiben konsistent. Reads gehen über `resolveProjektTitel`, der Legacy-Titel-Daten weiterhin akzeptiert.
12. **Defensive Lookups statt Datenmigration** — Bestandsdaten in laufenden Demo-Sessions können noch Title sein. Helper akzeptiert beides → kein Bruch.
13. **Server-RPC mit Caller-Guard** (v29 erweitertes Pattern) — `IF auth.uid() IS NULL THEN return error END IF; IF NOT public.is_admin() THEN return error END IF;` als erste zwei Statements im Body. Body danach unverändert.
14. **`window.mock<X>` Exposition für Tests** — auch `mockUmbuchungen` jetzt exponiert.

---

## 🎯 Nächster Sprint (Vorschläge)

1. **E2: Schüler-Frontend Refresh** (`schueler-frontend-v3.html`) — separater großer Sprint, eigener Bundle.
2. **E2.1: `update_zuteilung`-Klassenstufenprüfung** — entscheiden, ob hard-block (vs. nur hinweis-Flag) — UI-Entscheidung.
3. **E1.9: Mailto/Email-Versand für Erinnerung** — falls die Druckliste nicht reicht, Edge-Function-basiert.

**Einstiegs-Prompt für neuen Chat:**
```
Ich arbeite an der KRS Projektwahl App (admin-dashboard-v2.html, Preact+htm Single-File).
Sprint v29 Mega-Bundle abgeschlossen (E1.6 Erinnerung + E1.7 Title→ID Cleanup + E1.8 Security-Patch).
82 Tests grün. Migration v29 in Supabase ausgeführt, Frontend live.

Ordner: /Users/admin/Downloads/Codex playground/projekwoche app neu
Übergabe-Dokument: UEBERGABE-v30.md

Mögliche nächste Schritte: E2 (Schüler-Frontend Refresh), E2.1 (Klassenstufen-Hardblock),
E1.9 (Email-basierte Erinnerung).
```
