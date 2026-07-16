# Audit „Leck C" — KRS Projektwahl 2026

**Datum:** 13.07.2026 · **Supabase-Projekt:** `uzynvvtsyjfmtywsfxtz` · **Methode:** Read-only-Abfragen auf `pg_policies`, `pg_class`, `pg_views`, `pg_proc`, `pg_constraint` + empirischer Gegentest mit `SET LOCAL ROLE anon` (in Transaktion, `ROLLBACK`).

**Vorbemerkung (Ehrlichkeit):** Der Detailplan `07-SECURITY-SPRINT-DETAILPLAN` liegt nicht auf diesem Rechner. Was „Leck C" ursprünglich bezeichnete, ist hier nirgends definiert. Statt zu raten, wurde die Datenbank selbst auditiert. Der unten dokumentierte Befund **A-1** ist die einzige gefundene Stelle, an der Zugangscodes und Klarnamen ohne Login lesbar sind — sie passt zur Beschreibung „Leck" und wird hier als Leck C behandelt. Das ist eine begründete Zuordnung, keine bestätigte Identität mit dem Original-Detailplan.

---

## Befund A-1 (kritisch, verifiziert): View `zuteilungen_detail` ist ohne Login lesbar

| | |
|---|---|
| **Objekt** | `public.zuteilungen_detail` (View) |
| **Ursache** | `security_invoker = false` (Postgres-Default) → View läuft mit den Rechten des Owners `postgres` und **umgeht damit RLS**. Zusätzlich hat die Rolle `anon` ein `SELECT`-GRANT. |
| **Folge** | Wer den (öffentlichen, im Frontend eingebetteten) Publishable Key kennt, kann die View abfragen. |
| **Exponierte Felder** | `schueler_code` (= **Zugangscode**), `vorname`, `nachname`, `klasse`, `klassenstufe`, `projekt_titel`, Lehrkraft-Namen |
| **Messung als `anon`** | **391 Zeilen** lesbar (= alle aktiven Schüler:innen) |
| **Bewertung** | ⚠️ **kritisch** — Klarname + Klasse + Zugangscode von 391 Minderjährigen in einem Abruf |

**Gegenprobe (der RLS-Lockdown v35 selbst ist intakt):** als `anon` liefern `schueler`, `wahlen`, `zuteilungen`, `users`, `audit_log` jeweils **0 Zeilen**. Die View ist die Umgehung, nicht die Tabellen-Policies.

## Weitere geprüfte Objekte

| Objekt | Typ | anon-lesbar | Bewertung |
|---|---|---|---|
| `zuteilungen_detail` | View | **391 Zeilen** | ⚠️ **kritisch** (Befund A-1) |
| `verteilungen_uebersicht` | View | 13 Zeilen | ⚠️ gering — kein Schülerbezug, aber Lehrkraft-Namen + interne Statistik; `security_invoker` ebenfalls false. Mit schließen. |
| `projekte_stats` | View | 20 Zeilen | ✓ unkritisch (Aggregate veröffentlichter Projekte, keine PII). Vorsorglich mit schließen. |
| `projekte_public` | View | 20 Zeilen | ✓ korrekt (bewusst öffentlich, nur veröffentlichte Projekte) |
| `klassen_status` | View | 0 Zeilen | ✓ (`security_invoker = true`) |
| `offene_tauschwuensche` | View | 0 Zeilen | ✓ (`security_invoker = true`) |
| `schueler` | Tabelle | 0 Zeilen | ✓ RLS greift, keine anon-Policy |
| `wahlen`, `zuteilungen`, `tauschwuensche` | Tabellen | 0 Zeilen | ✓ RLS greift |
| `users`, `audit_log` | Tabellen | 0 Zeilen | ✓ RLS greift |
| `system_settings` | Tabelle | Policy `system_settings_public_select` | ✓ nur Whitelist (`phase`, `anmeldung_offen`, Deadlines) — keine PII |
| `projekte` | Tabelle | Policy `projekte_select_veroeffentlicht` (anon) | ✓ gewollt, keine PII |
| Policies gesamt | — | — | ✓ **kein `TO anon USING (true)` auf PII** gefunden |
| `admin_projekt_wahl_namen()` | RPC | anon EXECUTE | ✓ eigenes Gate im Body (`projektleitung`/`super_admin`), sonst `RAISE EXCEPTION` |
| `get_schueler_status(code)` | RPC | anon EXECUTE | ✓ gewollt — liefert nur die Zeile zum vorgelegten Code |

## Befund B-1 (mittel, verifiziert): Tausch-RPCs sind ohne Login aufrufbar

`ensure_admin_if_authed()` hat einen bewussten Dev-Bypass:

> `-- Fall A: Kein Auth → kein Check (Dev-Phase, Rückwärtskompatibilität)` · `IF auth.uid() IS NULL THEN RETURN; END IF;`

Damit passieren `genehmige_tauschwunsch()`, `genehmige_1zu1_tausch()` und `lehn_tauschwunsch_ab()` die Autorisierung, wenn **gar niemand** eingeloggt ist. Empirisch bestätigt: Aufruf als `anon` liefert `{"success": false, "error": "tausch_unbekannt"}` — also **nicht** „nicht berechtigt", das Gate wurde passiert.

**Folge:** Ein Unbefugter könnte mit dem öffentlichen Key beliebige Tauschwünsche genehmigen/ablehnen und damit Zuteilungen verändern. Kein Datenabfluss, aber ein Integritätsrisiko.
**Aktuell entschärft durch:** `tauschwuensche` = 0 Zeilen, Tausch-Deadline 17.07.2026.
**Empfehlung:** Fall A entfernen (anon → `RAISE EXCEPTION`). **Nicht Teil dieses Sprints** — gehört in einen eigenen, getesteten Sprint, weil E2E-Tests im Demo-Modus daran hängen können.

## Git-Repo (Aufgabe 1, letzter Punkt)

| Prüfung | Ergebnis |
|---|---|
| `schueler-template.csv`, `lehrer-template.csv`, `projekte-template.csv` | ✓ nur erfundene Namen (Max Mustermann …), keine Codes |
| `tests/fixtures/` | ✓ keine echten Personendaten |
| `.gitignore` | ✓ blockt `seed-schueler.sql`, `seed-lehrer.sql`, `lehrer-kuerzel.csv`, `*Schülerliste*`, `beispiel-schuelerbrief.pdf` |
| Echte Codes/Namen im Repo | ✓ keine gefunden |

## Phasen-Check (Aufgabe 2)

| Kennzahl | Wert (13.07.2026) |
|---|---|
| Phase | `projekttage` |
| `anmeldung_offen` | `false` |
| Tausch-Deadline | 17.07.2026, 23:59 |
| Projekttage | 21.–23.07.2026 |
| Schüler:innen gesamt / aktiv | 503 / **391** (112 inaktiv = 10er-Abschlussklassen) |
| Wahlen | 235 |
| Zuteilungen | 391 |
| Tauschwünsche | 0 |
| Aktive Verteilung | 1 |

**Berührt eine Rotation Wahlen/Zuteilungen?** Inhaltlich **nein**. Die FKs stehen auf `ON DELETE CASCADE`, **ohne** `ON UPDATE CASCADE` — ein naives `UPDATE schueler SET code = …` würde deshalb an der FK scheitern. `migration-v49` stellt die drei FKs zuerst auf `ON UPDATE CASCADE` um; danach wandert nur der Schlüssel `schueler_code` in `wahlen`/`zuteilungen`/`tauschwuensche` mit. Wahlinhalte, Zuteilungen und die aktive Verteilung bleiben unverändert.

## Nachprüfung 16.07.2026 (Opus-Session) — Leck ist geschlossen

Erneute read-only-Prüfung derselben Objekte gegen die Live-DB `uzynvvtsyjfmtywsfxtz`:

| Prüfung (16.07.) | Ergebnis |
|---|---|
| `zuteilungen_detail` als `anon` | **permission denied** — `has_table_privilege('anon',…,'SELECT') = false` |
| `verteilungen_uebersicht` als `anon` | **permission denied** (`false`) |
| `projekte_stats` als `anon` | **permission denied** (`false`) |
| `projekte_public` als `anon` | `true` (gewollt, nur veröffentlichte Projekte, keine PII) |
| Tabellen `schueler`/`wahlen`/`zuteilungen`/`users` als `anon` | weiterhin 0 Zeilen (RLS intakt) |

**Fazit:** Der `REVOKE` aus **TEIL 0** von `migration-v49-code-rotation.sql` wurde zwischen dem
13.07. und dem 16.07. bereits eingespielt — **Befund A-1 ist behoben, der Datenabfluss gestoppt.**
`security_invoker` steht auf diesen drei Views weiterhin auf `false` (TEIL 0b noch offen; wirkt
nur noch gegen eingeloggte Rollen, kein anon-Abfluss mehr).

**Rotation:** noch **nicht** ausgeführt — `code_rotation_log` existiert nicht, die drei FKs stehen
weiter auf `ON UPDATE NO ACTION` / `ON DELETE CASCADE` (per `pg_constraint` verifiziert). v49 TEIL 2
ist einspielbereit, die Voraussetzung (FK-Umstellung in 2.2) ist also weiterhin nötig und korrekt.

**Befund B-1** (Dev-Bypass in `ensure_admin_if_authed`): **weiterhin vorhanden** (per
`pg_get_functiondef` bestätigt). Unverändert, gehört in einen eigenen Sprint.

**`get_advisors` (security) — ergänzend:**
- `security_definer_view` (WARN) auf `zuteilungen_detail`, `verteilungen_uebersicht`,
  `projekte_stats`, `projekte_public` → die PII-Views sind durch den anon-REVOKE entschärft;
  vollständige Behebung = TEIL 0b (`security_invoker = true`).
- `function_search_path_mutable` (WARN, gering) auf mehreren Funktionen (`create_wahl`,
  `create_tauschwunsch`, `genehmige_tauschwunsch`, …) → Härtung, nicht akut.
- `public_bucket_allows_listing` auf Bucket `projekt-bilder` (public, Projekt-Coverbilder,
  **keine PII**) → gering.
- `anon_security_definer_function_executable` (INFO) inkl. `genehmige_tauschwunsch` → deckt sich
  mit Befund B-1.

## Empfehlung (Priorität)

1. **Sofort, unabhängig von allem anderen:** TEIL 0 aus `migration-v49-code-rotation.sql` — `REVOKE` des anon-Zugriffs auf die drei Views. Das stoppt den Abfluss. Ohne diesen Schritt ist jede Rotation wertlos, weil die neuen Codes sofort wieder auslesbar wären.
2. **Danach entscheiden:** Rotation ja/nein. Sachlage: Die Anmeldung ist geschlossen, alle 391 Zuteilungen stehen. Ein geleakter Code erlaubt derzeit noch: eigene Zuteilung einsehen und bis 17.07. einen Tauschwunsch im fremden Namen stellen/zurückziehen (Vorname/Nachname zur Bestätigung sind über dieselbe View mitgeleakt). Preis der Rotation: 391 neue Serienbriefe, 8 Tage vor den Projekttagen. Das ist Norberts Abwägung — die CHECK-Query in TEIL 1 liefert die Zahlen dafür.
3. **Nachgelagert (eigener Sprint):** Befund B-1 schließen, `security_invoker = true` auf die Views setzen (TEIL 0b), anon-Schreib-GRANTs auf den Tabellen entfernen (aktuell durch RLS folgenlos, aber unnötig).
