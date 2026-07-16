# HANDOVER — krs-projektwahl (kanonisch)

**Ziel / Fertig wenn:** Leck-C-Security abgeschlossen — Leck geschlossen, ggf. Codes rotiert +
neue Serienbriefe mit Testlauf verteilt, DSGVO-Notiz fürs DSB-Gespräch fertig.

## Stand 2026-07-16 (Opus-Session — Leck-C-Audit abgeschlossen)

**Kernbefund:** Das Leck ist **geschlossen**, eine Rotation ist **vorbereitet, aber noch nicht
entschieden/ausgeführt**. Alle DB-Prüfungen read-only, nur aggregierte Zahlen (echte
Schülerdaten Minderjähriger — keine Codes/Namen in Dateien oder Chat).

- **Leck C = View `zuteilungen_detail`** (Supabase `uzynvvtsyjfmtywsfxtz`): lief mit
  Owner-Rechten (`security_invoker=false`) und war für `anon` lesbar → Zugangscode + Vor-/
  Nachname + Klasse von **391 aktiven Schüler:innen** ohne Login abrufbar. Die Tabellen selbst
  (RLS-Lockdown v35) waren nie offen.
- **STATUS geschlossen:** anon-`REVOKE` auf die drei Views (`zuteilungen_detail`,
  `verteilungen_uebersicht`, `projekte_stats`) ist eingespielt, am 16.07. verifiziert (anon =
  „permission denied"). = v49 TEIL 0, bereits live.
- **Rotation NICHT ausgeführt:** `code_rotation_log` existiert nicht, FKs stehen weiter auf
  `ON UPDATE NO ACTION`. Fertiges SQL liegt in `migration-v49-code-rotation.sql`
  (TEIL 0 Leck schließen · TEIL 1 CHECK · TEIL 2 Rotation · TEIL 3 UNDO). **Rotation = Norberts
  Entscheidung** (Preis: 391 neue Briefe, 5 Tage vor den Projekttagen; Nutzen: nur noch gering,
  da Leck bereits zu und Anmeldung geschlossen).
- **Restrisiko bis Rotation entschieden:** Tauschwunsch im fremden Namen bis Tausch-Deadline
  **17.07.2026** — aktuell **0 offene Tauschwünsche**. Zusätzlich Befund **B-1** (Dev-Bypass in
  `ensure_admin_if_authed` → Tausch-RPCs ohne Login aufrufbar) weiter offen, **eigener Sprint**.
- **Kennzahlen (16.07.):** 503 Schüler gesamt / 391 aktiv / 112 inaktiv · 235 Wahlen · 391
  Zuteilungen · 0 Tauschwünsche · Phase `projekttage`, `anmeldung_offen=false`.

### Erstellte / geänderte Artefakte (Opus)
- `AUDIT-LECK-C-2026-07-13.md` — Audit + Abschnitt „Nachprüfung 16.07." (Leck geschlossen,
  Advisors, B-1).
- `migration-v49-code-rotation.sql` — Rotations-/Fix-SQL, CHECK→AKTION→UNDO, FK-verifiziert;
  Kopf mit STATUS-16.07.-Vermerk.
- `DSGVO-NOTIZ-DSB-projektwahl.md` — 1-Seiter fürs DSB-Gespräch (neu).
- `sprint sonnet krs-projektwahl.md` — Abschnitt „Input von Opus" ausgefüllt.

## Was Norbert jetzt tut (genau EINE Entscheidung)

**Rotation ja/nein?** Das Leck ist bereits geschlossen. Entscheide, ob die Zugangscodes trotzdem
rotiert werden sollen (dann 391 neue Serienbriefe vor dem 21.07.). Für die Zahlen-Grundlage:
in Supabase → SQL Editor die **CHECK-Query (TEIL 1)** aus `migration-v49-code-rotation.sql`
laufen lassen (nur Lesen). Danach:
- **Rotation gewünscht:** OK geben → TEIL 2 einspielen → **Sonnet-Sprint** (Serienbriefe + Testlauf) starten.
- **Keine Rotation:** nichts weiter nötig, Sonnet-Sprint entfällt (kurze Info ans Kollegium).

## Offene Punkte
- Entscheidung Code-Rotation (s. o.).
- **Befund B-1** schließen (Dev-Bypass in Tausch-RPCs) — eigener, getesteter Sprint (E2E hängt daran).
- **TEIL 0b** (`security_invoker=true` auf die drei Views) nach grünem E2E einspielen.
- Logs des Expositionszeitraums auf Auffälligkeiten sichten.
- Original-Detailplan `07-SECURITY-SPRINT-DETAILPLAN` vom Mac Mini nachziehen und abgleichen.
- Low-Prio Härtung: `function_search_path_mutable` (Advisor), Bucket `projekt-bilder` Listing.

## Git-Stand
- **NOCH NICHT committet** (Blocker: die Workspace-Shell der Opus-Session hing dauerhaft, git
  war nicht ausführbar). Uncommittet liegen bereit: Housekeeping (handover-archiv/ + entfernte
  Alt-Handover im Root) sowie die Opus-Artefakte (Audit-Update, v49, DSGVO-Notiz, Sonnet-Input,
  diese HANDOVER.md). Fertiger 2-Commit-Befehl steht in der Session-Übergabe an Norbert
  (kein Push — Push macht Norbert).
