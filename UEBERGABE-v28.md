# UEBERGABE v28 — KRS Projektwahl 2026
**Datum:** 2026-04-27
**Sprint:** E1 — KlassenlehrerView
**Status:** ✅ 73/73 Tests grün, Deploy via Actions

---

## 🚀 Was in dieser Session passiert ist

### Sprint E1 — KlassenlehrerView (Read-Only) + Pre-existing Bugfix

#### Neue Komponente `KlassenlehrerView`
- Read-Only-View für Rolle `klassenlehrer`: zeigt alle Schüler der eigenen Klasse
- Spalten: Code, Nachname, Vorname, Status (✓ Angemeldet / ○ Offen), Zuteilung
- Header zeigt Klassen-Aggregat: `X von Y angemeldet (Z%) · N offen`
- Demo-Fallback: ohne `currentDbUserId` wird der erste `klassenlehrer` aus `mockLehrerData` genommen
- Filter-Logik: `mockSchueler.filter(s => s.klasse === lehrer.klassenlehrer_von)`

#### Routing & Rollen
- Neue Section `meine-klasse` mit NavItem `📋 Meine Klasse`
- `ALLOWED_SECTIONS.klassenlehrer` jetzt `new Set(['meine-klasse'])` (vorher: `dashboard`, `anmeldungen`)
- Default-Section nach Login als `klassenlehrer` → `meine-klasse` (Live + `?forceRolle=`-Override)

#### Mock-Daten
- User `u23` (Lehrkraft 23) zum **Klassenlehrer von 7a** umgewidmet (war `projektlehrer`)
- 25 Schüler in Klasse 7a → Demo zeigt sofort Daten

#### Test-Infrastruktur
- App-Level-Listener auf `window.dispatchEvent(new Event('krs:mock-seeded'))` → bumpt `refreshKey`, damit Views nach externer Mock-Mutation re-rendern
- `seedMockData`-Fixture dispatcht das Event nach jeder Mutation
- 3 neue Specs in `tests/e2e/flow-klassenlehrer.spec.ts`
- `feature-role-guard.spec.ts` für neue ALLOWED_SECTIONS angepasst

#### Pre-existing Bugfix (Bonus)
- Bug im `title`-Attribut der "Alle Entwürfe veröffentlichen"-Button: deutsche Gänsefüßchen `„entwurf"` mit doppelten `"` brachen den htm-Parser, sobald `entwurfsCount > 0`
- Symptom: `Failed to execute 'setAttribute' … '„veröffentlicht setzen' is not a valid attribute name` → Tabellen-Render bricht ab → "neues Projekt erscheint nicht in Tabelle"
- Fix: `title="..."` → `title='...'` (single quotes erlauben doppelte Anführungszeichen im Attribut)
- **Das ist der eigentliche v27-Bug.** Die `localKey`+`useMemo`-Lösung in v27 war ein guter Workaround, der Parser-Crash steckte aber in der Bulk-Button-`title`. Beide Fixes ergänzen sich gut — `localKey` bleibt drin, weil es das Re-Render-Pattern für Demo-Mutationen sauber macht.

---

## 📊 Aktueller Test-Stand

| Spec-File | Tests | Status |
|-----------|-------|--------|
| (alle 28 v27-Specs) | 70 | ✅ |
| **flow-klassenlehrer (NEU)** | 3 | ✅ |
| **GESAMT** | **73** | **✅** |

Vollständiger Lauf lokal: `73 passed (1.9m)`

---

## 🔧 Technische Details

### `KlassenlehrerView` ({admin-dashboard-v2.html} ~7913)
```javascript
function KlassenlehrerView({ refreshKey, currentDbUserId }) {
  const effectiveOwnerId = currentDbUserId
    || (window.KRS_MODE !== 'produktiv'
        ? (mockLehrerData.find(l => l.rolle === 'klassenlehrer') || {}).id
        : null);

  const lehrer = useMemo(() => mockLehrerData.find(l => l.id === effectiveOwnerId) || null,
    [refreshKey, effectiveOwnerId]);
  const klasse = lehrer?.klassenlehrer_von || '';

  const schueler = useMemo(() => {
    if (!klasse) return [];
    return mockSchueler.filter(s => s.klasse === klasse)
      .sort((a, b) => a.nachname.localeCompare(b.nachname, 'de'));
  }, [refreshKey, klasse]);
  // ...
}
```

### App-Level Test-Hook
```javascript
useEffect(() => {
  const onSeed = () => setRefreshKey(k => k + 1);
  window.addEventListener('krs:mock-seeded', onSeed);
  return () => window.removeEventListener('krs:mock-seeded', onSeed);
}, []);
```
Wird in `seedMockData` (tests/fixtures/app.ts) nach jeder Mutation gefeuert. Greift in jedem Modus, da harmlos.

---

## 📁 Projektdaten

| Was | Wert |
|-----|------|
| Lokaler Ordner | `/Users/admin/Downloads/Codex playground/projekwoche app neu` |
| GitHub Repo | https://github.com/BenditoT/krs-projektwahl-2026 |
| Actions | https://github.com/BenditoT/krs-projektwahl-2026/actions |
| Live URL | https://benditot.github.io/krs-projektwahl-2026/ |
| Hauptdatei | `admin-dashboard-v2.html` |
| Letzter Commit | (siehe `git log` — v28: Sprint E1) |

---

## 🎯 Nächster Sprint: E1.5 — KlassenlehrerView Direkt-Einschreibung (optional)

Ideen für die nächsten Schritte:
1. **E1.5: Direkt-Einschreibung** — Klassenlehrer kann Schüler manuell einem Projekt zuweisen (z.B. wenn Schüler ohne Anmeldung erscheint). UI: "Zuteilung"-Spalte editierbar machen via Dropdown.
2. **E1.6: Erinnerung-Trigger** — Button "Erinnerung an offene Schüler senden" (E-Mail-Liste exportieren oder Mailto-Link).
3. **E2: Schüler-Frontend Refresh** — Schüler-Frontend nach gleichem Pattern überarbeiten (Single-File schueler-frontend-v3.html).

**Einstiegs-Prompt für neuen Chat:**
```
Ich arbeite an der KRS Projektwahl App (admin-dashboard-v2.html, Preact+htm Single-File).
Sprint E1 abgeschlossen — KlassenlehrerView (Read-Only) ist live, 73 Tests grün.

Ordner: /Users/admin/Downloads/Codex playground/projekwoche app neu
Übergabe-Dokument: UEBERGABE-v28.md

Mögliche nächste Schritte: E1.5 (Direkt-Einschreibung), E1.6 (Erinnerung-Trigger),
E2 (Schüler-Frontend Refresh). Lass uns reden, was Priorität hat.
```

---

## 🔑 Wichtige Patterns (aktualisiert)

1. **Demo-Mode Mutation → `setLocalKey(k => k + 1)`** (v27) — interne UI-Mutationen
2. **Externe Mock-Mutation → `window.dispatchEvent(new Event('krs:mock-seeded'))`** (v28) — Test-Setup via seedMockData
3. **`useMemo` mit `[refreshKey, localKey]`** — refreshKey kommt von außen, localKey intern
4. **`window.mockX` Exposition** — für Playwright seedMockData
5. **`key=${p.id}`** — auf allen Map-Renderings
6. **HTML-Attribute mit deutschen Gänsefüßchen** — `title='...'` (single quotes), niemals `title="..."` mit `„entwurf"` darin → htm-Parser crasht
7. **Deploy:** `git push origin main` → Actions → bei grün live
