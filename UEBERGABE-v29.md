# UEBERGABE v29 — KRS Projektwahl 2026
**Datum:** 2026-04-27
**Sprint:** E1.5 — KlassenlehrerView Direkt-Einschreibung
**Status:** ✅ 76/76 Tests grün, Demo live · Live benötigt Migration v28

---

## 🚀 Was in dieser Session passiert ist

### Sprint E1.5 — Klassenlehrer kann Schüler manuell zuweisen

#### Frontend (`KlassenlehrerView` in `admin-dashboard-v2.html` ~7918)
- Zuteilung-Spalte ist jetzt ein `<select data-testid="klassenlehrer-zuteilung-select" data-code=...>`
- Optionen: „— keine —" + alle veröffentlichten Projekte gefiltert auf die Klassenstufe der Klasse (`min_klasse ≤ klassenstufe ≤ max_klasse`)
- onChange ruft `service.klassenlehrerAssignSchueler({ code, projektId })`. `projektId === null` löscht die Zuteilung wieder.
- Lokales Re-Render via `setLocalKey(k => k + 1)` + Toast-Bestätigung. Während des Calls ist das `<select>` für die Zeile disabled (`busyCode`).
- `projektTitel`-Helper jetzt **defensiv**: lookup nach ID *oder* Titel — toleriert die Legacy-Title-Schreibweise von UmbuchungView, ohne deren Verhalten zu ändern.
- `mockSchueler[i].zuteilung` wird konsequent als **Projekt-ID** geschrieben (matched Production-Schema). `mockSchueler[i].hat_gewaehlt = true/false` zieht synchron mit (Header-Counter + Status-Badge bleiben konsistent).

#### KrsDataService (inline in `admin-dashboard-v2.html` ~777, **nicht** standalone-Datei)
- Neue Methode `klassenlehrerAssignSchueler({ code, projektId })`:
  - **Demo:** mutiert `window.mockSchueler` in-memory + dispatcht `'krs:mock-seeded'` → App-Listener bumpt `refreshKey` → alle Views rendern neu
  - **Live:** ruft RPC `klassenlehrer_assign_schueler` (oder `…_unassign_schueler` wenn `projektId === null`)
- ⚠️ Hinweis: Es existiert eine **zweite, ungenutzte** `krs-supabase-service.js` im Repo. Die App nutzt nur die inlined Version in `admin-dashboard-v2.html`. Die standalone Datei wurde mit gleicher Methode synchronisiert, ist aber dead code.

#### Backend — Migration `migration-v28-klassenlehrer-direkt-einschreibung.sql`
- Neue Helper:
  - `public.is_klassenlehrer()` (analog `is_projektlehrer()` aus v25)
  - `public.current_klassenlehrer_klasse()` — liefert die eigene Klasse lower-cased
- Neue RPCs (beide `SECURITY DEFINER`, nur `authenticated`):
  - `klassenlehrer_assign_schueler(p_schueler_code, p_projekt_id)` — prüft Rolle, eigene Klasse, Projekt-Status, Klassenstufe, schreibt/aktualisiert `zuteilungen` mit `wahl_nr=NULL`, Kommentar `"Direkt durch Klassenlehrer (YYYY-MM-DD)"`
  - `klassenlehrer_unassign_schueler(p_schueler_code)` — DELETE mit gleicher Klassenprüfung
- Neue RLS-Policies (Live-Mode, damit der Frontend-Read überhaupt funktioniert):
  - `klassenlehrer_select_self` auf `users` (eigene Zeile)
  - `klassenlehrer_select_eigene_klasse` auf `schueler` (alle Schüler der eigenen Klasse)
  - `klassenlehrer_select_zuteilungen_eigene_klasse` auf `zuteilungen` (Zuteilungen der eigenen Klasse)
- INSERT/UPDATE/DELETE auf `zuteilungen` läuft **ausschließlich über die RPCs** — keine direkten DML-Policies für klassenlehrer.

**Status:** SQL geschrieben, lokal abgelegt. **Muss noch im Supabase SQL-Editor ausgeführt werden**, bevor Live-Mode für Klassenlehrer freigeschaltet werden kann.

---

## 📊 Aktueller Test-Stand

| Spec-File | Tests | Status |
|-----------|-------|--------|
| (alle v28-Specs) | 73 | ✅ |
| **flow-klassenlehrer (E1.5 +3)** | 6 (3 alt + 3 neu) | ✅ |
| **GESAMT** | **76** | **✅** |

Vollständiger Lauf lokal: `76 passed (2.0m)`

### Neue Specs in `tests/e2e/flow-klassenlehrer.spec.ts`
1. `E1.5: Klassenlehrer weist offenen Schüler einem Projekt zu` — selectOption → Status flippt → mockSchueler.zuteilung = Projekt-ID, hat_gewaehlt = true
2. `E1.5: Klassenlehrer kann Zuteilung wieder entfernen` — selectOption('') → Status zurück auf "offen", Felder reset
3. `E1.5: Dropdown filtert auf veröffentlicht + passende Klassenstufe` — entwurf-Projekte und out-of-range Klassenstufen erscheinen nicht in den Optionen

---

## 🐛 Pre-existing Issues (nicht in E1.5 Scope, aber dokumentiert)

### 1. `mockSchueler.zuteilung` Title-vs-ID Inkonsistenz
- `UmbuchungView` (admin-dashboard-v2.html ~8967) schreibt `s.zuteilung = projTitel` (Titel)
- `ZuteilungenView` (~8702) liest `s.zuteilung` als Titel
- `KlassenlehrerView` (E1) las es als ID — `projektTitel`-Helper wurde in E1.5 defensiv gemacht (akzeptiert beides)
- **Saubere Lösung wäre:** UmbuchungView und ZuteilungenView ebenfalls auf ID umstellen
- **Risiko aktuell:** keine — alle Read-Pfade sind robust

### 2. `update_zuteilung` RPC ohne Rollenprüfung
- Datei: `archive/old-migrations/migration-verteilungsalgorithmus.sql:277`
- `SECURITY DEFINER`, `GRANT EXECUTE ... TO anon, authenticated` — **keine** interne Caller-Check
- Theoretisch könnte ein authenticated User mit Rolle != admin/projektleitung die RPC aufrufen und beliebige Schüler umbuchen
- E1.5 löst das **nicht** — die neuen `klassenlehrer_*` RPCs sind sauber rollenscoped, aber das alte Loch bleibt
- **Empfehlung:** separates Mini-Sprint: Caller-Check in `update_zuteilung` (admin OR projektleitung) ergänzen

---

## 🔧 Technische Details

### KlassenlehrerView Dropdown-Filter
```javascript
const verfuegbareProjekte = useMemo(() => {
  return (mockProjekteData || [])
    .filter(p => p.status === 'veroeffentlicht')
    .filter(p => {
      if (klassenstufe == null) return true;
      const minOk = p.min_klasse == null || klassenstufe >= p.min_klasse;
      const maxOk = p.max_klasse == null || klassenstufe <= p.max_klasse;
      return minOk && maxOk;
    })
    .sort((a, b) => String(a.titel || '').localeCompare(String(b.titel || ''), 'de'));
}, [refreshKey, localKey, klassenstufe]);
```

### Service-Methode (Demo)
```javascript
async klassenlehrerAssignSchueler({ code, projektId }) {
  const cleanCode = String(code || '').toUpperCase().trim();
  if (this.isDemo) {
    const s = (window.mockSchueler || []).find(x => x.code?.toUpperCase() === cleanCode);
    if (!s) return { success: false, error: 'schueler_unbekannt' };
    s.zuteilung = projektId || null;
    s.hat_gewaehlt = !!projektId;
    window.dispatchEvent(new Event('krs:mock-seeded'));
    return { success: true, schueler_code: cleanCode, projekt_id: projektId || null };
  }
  // Live: RPC-Call
  const rpc = projektId ? 'klassenlehrer_assign_schueler' : 'klassenlehrer_unassign_schueler';
  // ...
}
```

---

## 📁 Projektdaten

| Was | Wert |
|-----|------|
| Lokaler Ordner | `/Users/admin/Downloads/Codex playground/projekwoche app neu` |
| GitHub Repo | https://github.com/BenditoT/krs-projektwahl-2026 |
| Actions | https://github.com/BenditoT/krs-projektwahl-2026/actions |
| Live URL | https://benditot.github.io/krs-projektwahl-2026/ |
| Hauptdatei | `admin-dashboard-v2.html` |
| Neue Migration | `migration-v28-klassenlehrer-direkt-einschreibung.sql` |

---

## 🎯 Deploy-Schritte

1. `deploy` (Demo geht sofort live, kein DB-Run nötig)
2. **Wenn Live-Mode aktiviert werden soll:** Migration v28 im Supabase SQL-Editor ausführen
3. Erste Klassenlehrer-User (Live) testen: einloggen → "Meine Klasse" → ein offener Schüler → Dropdown → speichern → in Supabase `zuteilungen`-Tabelle prüfen

---

## 🎯 Nächster Sprint (Vorschläge)

1. **E1.6: Erinnerung-Trigger** — Button "Erinnerung an offene Schüler senden" (Mailto oder CSV-Export)
2. **E1.7: Cleanup Title→ID** in UmbuchungView/ZuteilungenView (siehe Pre-existing Issue #1)
3. **E1.8: Sicherheits-Patch `update_zuteilung`** (siehe Pre-existing Issue #2)
4. **E2: Schüler-Frontend Refresh** (schueler-frontend-v3.html nach gleichem Pattern wie v28)

**Einstiegs-Prompt für neuen Chat:**
```
Ich arbeite an der KRS Projektwahl App (admin-dashboard-v2.html, Preact+htm Single-File).
Sprint E1.5 abgeschlossen — Klassenlehrer können Schüler direkt einschreiben, 76 Tests grün.
Migration v28 ist geschrieben aber noch nicht in Supabase ausgeführt (Demo läuft, Live erst nach SQL-Run).

Ordner: /Users/admin/Downloads/Codex playground/projekwoche app neu
Übergabe-Dokument: UEBERGABE-v29.md

Mögliche nächste Schritte: E1.6 (Erinnerungen), E1.7 (Title→ID-Cleanup),
E1.8 (Security-Patch update_zuteilung), E2 (Schüler-Frontend).
```

---

## 🔑 Wichtige Patterns (aktualisiert)

1. **Demo-Mode Mutation → `setLocalKey(k => k + 1)`** (v27) — interne UI-Mutationen
2. **Externe Mock-Mutation → `window.dispatchEvent(new Event('krs:mock-seeded'))`** (v28) — Test-Setup via seedMockData *und* von Service-Methoden, die Mocks ändern
3. **`useMemo` mit `[refreshKey, localKey, …]`** — refreshKey kommt von außen, localKey intern
4. **`window.mockX` Exposition** — für Playwright seedMockData *und* Demo-Service-Mutationen
5. **`key=${p.id}`** — auf allen Map-Renderings
6. **HTML-Attribute mit deutschen Gänsefüßchen** — `title='...'` (single quotes)
7. **`KrsDataService` ist inline** in admin-dashboard-v2.html (~260) — nicht in der gleichnamigen `.js`-Datei. Neue Service-Methoden immer in der inlined Version ergänzen.
8. **RLS-Migration-Pattern** (E1.5/v28) — `is_<rolle>()`-Helper, `current_<rolle>_<scope>()`-Helper, RPCs mit `SECURITY DEFINER` + Rollencheck am Anfang, SELECT-Policies für Live-Read, kein direktes DML
9. **Deploy:** `git push origin main` → Actions → bei grün live
