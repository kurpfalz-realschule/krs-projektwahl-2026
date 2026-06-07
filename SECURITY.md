# Sicherheitshinweise — krs-projektwahl-2026

**Dieses Repo darf KEINE echten Personendaten enthalten.**

- Echte Schueler-/Lehrerlisten (Namen, Zugangscodes, E-Mails) liegen ausschliesslich
  in Supabase, niemals im committeten Code oder in Seed-/CSV-Dateien.
- Im Frontend steht nur der oeffentliche `anon`-Key. Schutz = Row Level Security (RLS).
  Keine `open_read_*`-Policy mit `TO anon USING (true)` auf PII-Tabellen
  (schueler, users, zuteilungen). Siehe `migration-v35-rls-lockdown.sql`.
- Schuelerzugriff nur ueber `get_schueler_status(code)` (SECURITY DEFINER, nur eigene Zeile).
- Vollstaendige Listen nur ueber Admin-RPCs (z. B. `admin_list_schueler()`), per `is_app_user()` geschuetzt.
- Demo-/Mock-Daten ausschliesslich mit erfundenen Namen (Mustermann o. Ä.).
