# Handover v35: Projektbilder verschwinden nach Upload

Stand: 21.05.2026, Projekt `krs-projektwahl-2026`, Branch `main`.

## Kontext

Nach v34 waren Logos live sichtbar, aber Projektbilder wirkten im Admin weiter "weg", sobald nach dem Upload neu geladen oder das Projekt erneut geöffnet wurde.

## Root Cause

Der Upload selbst war seit v34 korrekt:

- Datei landet in Supabase Storage Bucket `projekt-bilder`.
- `projekte.bild_url` wird über RPC `public.set_projekt_bild_url(uuid,text)` gespeichert.
- Live-DB hatte bereits eine gespeicherte URL für `Makerspace-Projekt`.

Der Fehler lag im Admin-Reload:

- `App.loadAll()` lädt live `service.listProjekte()`.
- Danach wird in `replaceArray(mockProjekteData, projekte.map(...))` für das Admin-UI normalisiert.
- Dabei fehlte `bild_url`; dadurch wurde die URL nach jedem `loadAll()` aus dem lokalen UI-State entfernt.

Fix:

```js
bild_url: p.bild_url || null,
```

in der `mockProjekteData`-Normalisierung in `admin-dashboard-v2.html`.

## Geänderte Dateien

- `admin-dashboard-v2.html`
  - `loadAll()` übernimmt jetzt `bild_url`.
- `tests/e2e/feature-projekt-bild-upload.spec.ts`
  - Regressionstest ergänzt: Produktiv-Reload muss `bild_url` in die Projektliste übernehmen.

## Bereits verifiziert

Lokal grün:

```bash
npm run test:typecheck
npm run test:e2e -- tests/e2e/feature-projekt-bild-upload.spec.ts
```

Vorherige v34-Verifikation war ebenfalls grün:

```bash
npm run test:e2e
```

v34 war live deployed mit Commit:

```text
268d63e fix projektbilder und logo fallback
```

## Supabase-Status

v34-RPC ist live installiert und geprüft:

```sql
select proname, pg_get_function_result(p.oid) as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'set_projekt_bild_url';
```

Erwartet:

```text
set_projekt_bild_url | projekte
```

DB-Check zeigte mindestens ein persistiertes Bild:

```sql
select p.id, p.titel, p.status, p.bild_url, pp.bild_url as public_bild_url
from public.projekte p
left join public.projekte_public pp on pp.id = p.id
where p.bild_url is not null and p.bild_url <> ''
order by p.updated_at desc;
```

Beobachtet: `Makerspace-Projekt` mit Storage-URL im Bucket `projekt-bilder`.

## Nächste Schritte

1. Vollständigen E2E-Lauf optional noch einmal starten:

```bash
npm run test:e2e
```

2. Genau diese Dateien committen:

```bash
git add admin-dashboard-v2.html tests/e2e/feature-projekt-bild-upload.spec.ts HANDOVER-v35-projektbilder.md
git commit -m "fix projektbild reload"
git push origin main
```

3. GitHub Actions Deploy abwarten:

```bash
gh run list --limit 5 --branch main
gh run watch <run-id> --exit-status
```

4. Live prüfen:

```bash
curl -LfsS https://benditot.github.io/krs-projektwahl-2026/admin-dashboard-v2.html | rg "bild_url: p\\.bild_url|KRS_VERSION"
```

5. Danach im Admin ein Projekt mit Bild öffnen: Bild sollte nach Upload, nach Reload und beim erneuten Öffnen bleiben.

## Achtung Worktree

Der Worktree enthält viele ältere untracked Dateien (`archive/`, Mail-Entwürfe, Skills usw.). Diese nicht ungefragt stage/committen.
