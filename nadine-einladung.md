# Einladung: Lehrkraft 15 — KRS Projektwahl 2026

## Schritte vor dem Versand

1. **In LehrerView Nadine anlegen:**
   - Name: `Lehrkraft 15`
   - E-Mail: `(Dienst-E-Mail ergänzen)`
   - Rolle: `projektleitung`
   - Klassenlehrer von: (leer lassen)

2. **In Supabase Dashboard → Authentication → Users → Invite User:**
   - E-Mail: Nadines Dienst-E-Mail
   - Redirect URL: `https://benditot.github.io/krs-projektwahl-2026/admin-dashboard-v2.html`
   - Klick auf „Invite" → Supabase schickt Magic Link

3. **Parallele E-Mail an Nadine** (optional, falls Supabase-Mail im Spam landet):

---

Betreff: Zugang zur KRS Projektwahl-App 2026

Liebe Nadine,

ab sofort hast du Zugang zur Projektwahl-App für die Projektwoche 2026. Als Projektleitung kannst du die Projekte einsehen und verwalten.

Du bekommst (oder hast bereits bekommen) eine E-Mail von noreply@supabase.io mit einem Link zur Passwort-Einrichtung. Bitte klick darauf und leg ein Passwort fest.

Danach erreichst du die App unter:
https://benditot.github.io/krs-projektwahl-2026/admin-dashboard-v2.html

Login: deine Schul-E-Mail + das gerade festgelegte Passwort.

Bei Fragen meld dich einfach!

Viele Grüße
Norbert

---

## Hinweis zum PASSWORD_RECOVERY-Flow

Der Supabase Magic Link führt zur App mit einem `#access_token=...`-Fragment.
Die App erkennt das automatisch über `onAuthStateChange` (Event `PASSWORD_RECOVERY`).
Noch nicht implementiert: eigenes Passwort-Setup-Modal.
Workaround: Supabase leitet direkt zum eingebauten Auth-Flow weiter — Nadine setzt Passwort auf der Supabase-Seite, loggt sich danach normal in der App ein.
Für v24: PASSWORD_RECOVERY-Handler + In-App-Modal.
