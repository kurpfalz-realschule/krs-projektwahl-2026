# DSGVO-Notiz für das DSB-Gespräch — KRS Projektwahl 2026

**Stand:** 16.07.2026 · **Verantwortlich (fachlich):** N. Kotzan · **System:** Web-App „KRS
Projektwahl 2026" (Kurpfalz-Realschule Schriesheim), Supabase-Projekt `uzynvvtsyjfmtywsfxtz`
(EU-Region `eu-west-1`, Frankfurt/Irland). · **Einschätzung, kein Rechtsrat.**

## 1. Worum geht es (kurz)

Bei einem eigenen Datenbank-Audit (13.07.2026) wurde eine Fehlkonfiguration gefunden, durch
die bestimmte Schülerdaten **ohne Login** über den öffentlich im Frontend eingebetteten
Zugriffsschlüssel (Supabase „publishable key") abrufbar waren. Am 16.07.2026 wurde der
Zustand erneut geprüft: **Der Zugriff ist inzwischen gesperrt** (siehe Abschnitt 4).

> Ehrlichkeitshinweis: Der ursprüngliche Sicherheits-Detailplan („07-SECURITY-SPRINT-
> DETAILPLAN", Bezeichnung „Leck C") lag auf einem anderen Rechner und war beim Audit nicht
> verfügbar. Statt zu spekulieren, wurde die Datenbank selbst systematisch geprüft. Der unten
> beschriebene Befund ist die einzige gefundene Stelle mit Klartext-Abfluss und wird als
> „Leck C" behandelt — eine begründete Zuordnung, keine bestätigte Identität mit dem Original.

## 2. Was war betroffen (Datenkategorien)

- **Datenbank-View `zuteilungen_detail`.** Sie lief mit Owner-Rechten und umging dadurch die
  ansonsten aktive Zugriffsbeschränkung (Row Level Security). Abrufbar waren pro Datensatz:
  - **Zugangscode** (Pseudonym zum App-Login),
  - **Vorname, Nachname, Klasse, Klassenstufe** der Schüler:in,
  - zugeteiltes Projekt und Namen der betreuenden Lehrkräfte.
- **Umfang:** bis zu **391 aktive Schüler:innen** (Minderjährige) in einem einzigen Abruf.
- Zwei weitere Views (`verteilungen_uebersicht`, `projekte_stats`) waren ebenfalls ohne Login
  lesbar; sie enthielten **keine Schülernamen** (Lehrkraft-Namen bzw. reine Aggregat-Statistik).
- Die zugrundeliegenden Tabellen selbst (`schueler`, `wahlen`, `zuteilungen`, `users`) waren
  **nicht** ohne Login lesbar — die Zugriffsbeschränkung dort war intakt; nur die View umging sie.

## 3. Risiko-Einschätzung / Meldepflicht (Art. 33 DSGVO)

- **Art der Daten:** Klarname + Klasse + pseudonymer Zugangscode Minderjähriger. Keine
  besonderen Kategorien (Art. 9), keine Adressen/Kontaktdaten/Noten.
- **Bekannter tatsächlicher Zugriff durch Unbefugte:** **nicht belegt.** Der Abruf hätte
  technische Kenntnis des (zwar öffentlichen, aber nicht beworbenen) Schlüssels und der
  Datenstruktur erfordert. Es liegen **keine Hinweise** auf einen realen Abfluss vor; Logs
  werden noch gesichtet.
- **Vorläufige Einschätzung:** Eine **meldepflichtige Verletzung nach Art. 33** ist möglich,
  aber nicht zwingend — maßgeblich ist die Risiko-Abwägung (Sensibilität, Betroffenenzahl,
  Wahrscheinlichkeit realer Kenntnisnahme). Wegen der **Betroffenheit Minderjähriger** und der
  Kombination Name+Klasse+Login-Code sollte die **Meldung binnen 72 h vorsorglich vorbereitet**
  und die Entscheidung **mit dem/der Datenschutzbeauftragten** getroffen werden. **Das ist eine
  fachliche Einschätzung, keine rechtsverbindliche Bewertung.**

## 4. Ergriffene / laufende Maßnahmen

| # | Maßnahme | Status (16.07.2026) |
|---|----------|---------------------|
| 1 | Login-freien Lesezugriff (`anon`) auf die drei Views entzogen (`REVOKE`) | **erledigt** — heute verifiziert: Abruf als `anon` liefert „permission denied" |
| 2 | Grundschutz Row Level Security auf allen PII-Tabellen (Lockdown v35) | **aktiv** — Tabellen liefern ohne Login 0 Zeilen |
| 3 | Views zusätzlich auf `security_invoker = true` umstellen (auch für eingeloggte Rollen sauber) | **vorbereitet** (v49 TEIL 0b), nach E2E-Test einspielen |
| 4 | Zugangscodes rotieren + neue Serienbriefe (falls Missbrauch nicht auszuschließen) | **vorbereitet, noch nicht ausgeführt** (Entscheidung N. Kotzan; v49 TEIL 1/2) |
| 5 | Nachgelagert: Autorisierungs-Bypass in den Tausch-Funktionen schließen (Befund B-1) | **offen**, eigener getesteter Sprint |

## 5. Offene Punkte

- Entscheidung Code-Rotation ja/nein (Abwägung: Restrisiko vs. 391 neue Briefe, 5 Tage vor
  den Projekttagen 21.–23.07.). Anmeldung ist bereits geschlossen; das einzige Rest-Missbrauchs-
  fenster ist ein Tauschwunsch im fremden Namen bis zur Tausch-Deadline **17.07.2026**
  (aktuell 0 offene Tauschwünsche).
- Logs/Zugriffsstatistik auf Auffälligkeiten während des Expositionszeitraums sichten.
- Original-Detailplan vom anderen Rechner nachziehen und mit diesem Audit abgleichen.
- AVV mit Supabase, VVT-Eintrag und Löschkonzept für die Projektwahl-Daten prüfen/dokumentieren
  (separat vom akuten Vorfall).

---
*Grundlage: Audit `AUDIT-LECK-C-2026-07-13.md` (+ Nachprüfung 16.07.2026), Rotations-/Fix-SQL
`migration-v49-code-rotation.sql`. Keine echten Namen/Codes in dieser Notiz — nur aggregierte Zahlen.*
