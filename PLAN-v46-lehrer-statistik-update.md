# Plan v46 — Klassenzahlen, Projekt-Statistik, Auto-Update, gewählt/zugeordnet

Erstellt: 2026-06-17 · Autonom (plane/teste/deploye) · **Keine DB-Migration, keine Datenänderung**

## Leitprinzip (Datenschutz der Daten)
Alle 4 Features rechnen **rein clientseitig** aus Daten, die `loadAll()` ohnehin lädt
(`admin_list_schueler` → `mockSchueler`: `hat_gewaehlt`, `zuteilung`=projekt_id, `wahl_nr`,
`fixiert`, `aktiv`, `klasse`; `mockProjekteData`). **Kein** INSERT/UPDATE/DELETE, **kein**
Schema-Eingriff, **keine** neue RPC nötig. Projekte/Wahlen/Zuordnungen bleiben unangetastet.

## Begriffe
- **gewählt** = Schüler hat selbst gewählt: `hat_gewaehlt && !fixiert` → grün
- **zugeordnet** = vorab fest zugeordnet (Klassenprojekt): `fixiert && zuteilung` → blau (📌)
- **gebucht** = erledigt = `gewählt || zugeordnet`
- **offen/fehlt** = sonst (aktiv, nicht gebucht) → gelb

## Feature 4 — gewählt vs. zugeordnet (Kern von Norberts Problem)
Status-Pills haben schon Farben. Bug: **Zähler ignorieren `fixiert`**. Fix an allen Zählstellen:
`istGebucht(s) = aktiv && (hat_gewaehlt || (fixiert && zuteilung))`.
- Dashboard-Card „Anmeldungen" (Z. 2959 ff.): „X gebucht / N" + Sub „Y gewählt · Z zugeordnet".
- AnmeldungenView Klassen-Aufschlüsselung (Z. 5191 ff.): pro Klasse gewählt + zugeordnet getrennt zählen, Balken = gebucht.
- KlassenlehrerView (Z. 4785/4909/4947): Fortschritt „gebucht von N", Pill zeigt auch 📌 zugeordnet.
- Mini-Legende (grün/blau/gelb) in SchuelerView + AnmeldungenView.

## Feature 1 — Lehrer sehen Anmeldezahlen ihrer Klasse
KlassenlehrerView existiert bereits. Ergänzen: „X gewählt · Y zugeordnet · Z offen (von N)" +
Prozent gebucht. Für Admin/Projektleitung in AnmeldungenView dieselbe Klarheit (schon Klassenliste).

## Feature 2 — Projekt-Beliebtheit / Statistik (Admin)
Neue Sektion **📊 Statistik** (nur super_admin + projektleitung). Pro Projekt aus `mockSchueler`:
- belegt = #(`zuteilung===p.id`), aufgeteilt gewählt vs. zugeordnet; Auslastung belegt/max_plaetze + Balken; frei.
- Sortierung nach Beliebtheit (belegt desc) → „welche Projekte kommen gut an".
- Nach Verlosung: Wahlqualität (wahl_nr 1/2/3) je Projekt.
- Graceful: falls je Wunsch-IDs verfügbar werden (optionale, separate read-only Funktion), Erstwunsch-Interesse anzeigen — sonst weglassen. **Nicht** Voraussetzung fürs Deploy.

## Feature 3 — Auto-Versionsprüfung + Update-Hinweis
Self-Fetch des **eigenen Dokuments** (`location.href`, `cache:'no-store'`, Cache-Bust), Regex
`KRS_VERSION = 'vXX'`, Vergleich mit `window.KRS_VERSION`. Bei Abweichung: dezent-prominentes,
schließbares Banner „Neue Version verfügbar — jetzt aktualisieren" → `location.reload()`.
- Poll alle 5 min **nur** wenn Tab sichtbar + bei `visibilitychange`.
- Single Source of Truth = die deployte Datei selbst → kann nicht „out of sync" gehen, keine Zusatzdatei.
- Nur Produktiv-Modus (Tests hermetisch); Test-Hook `window.__krsCheckUpdate(simVersion)` für E2E.
- In **beide** Apps (admin-dashboard + schueler-frontend) — schützt vor Stale-Cache (v42-Vorfall).

## Versionen
admin-dashboard v45→**v46**, schueler-frontend v42→**v46** (vereinheitlicht).

## Bekannte KRS-Fallen (Self-Review)
- **normalizer-drift**: keine neuen DB-Felder nötig → loadAll-Mapping bleibt vollständig. Wenn doch
  ein Feld ergänzt würde, MUSS es im loadAll-Mapping (Z. 2540) UND ggf. inline-Service stehen.
- **stale-closure (CDN React)**: neue useEffect/Interval mit korrekten Deps + Cleanup; keine
  veralteten Closures in Pollern; funktionale setState-Updates.
- **live-gang**: Banner darf laufende Eingabe nicht zerstören (kein Auto-Reload), nur Hinweis.
- **Tests**: Demo-Modus, neue Specs für Zähler(fixiert), Statistik-View, Update-Banner-Hook.

## Test-/Deploy-Gate
Playwright lokal grün → `git push` → GitHub Actions (E2E) → bei Grün Auto-Deploy GitHub Pages.
Nur getrackte Code-/Test-Dateien committen (kein service_key.txt, keine Personendaten — .gitignore deckt das).
