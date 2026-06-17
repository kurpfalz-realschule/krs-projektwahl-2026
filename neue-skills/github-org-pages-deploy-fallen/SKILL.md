---
name: github-org-pages-deploy-fallen
description: >
  Löst die wiederkehrenden Fallen beim Deployen von GitHub-Pages-Projekten, die in
  einer Organisation liegen (statt im privaten Account): 403 beim Push, weil der
  fine-grained Token nur dem privaten Account gehört; ein zweiter Credential-Helper
  (gh CLI) überstimmt den guten Token; divergierte Git-Historie durch Web-Upload-
  Commits; und stale Pages-Routing nach Repo-Umzug (alte User-URL liefert 404,
  Monitor zeigt fälschlich Rot, echte Nutzer sind ok). Nutze diesen Skill immer wenn
  ein Deploy/Push auf ein Org-Repo scheitert, ein Repo in eine Organisation umzieht,
  oder eine Pages-Seite nach dem Umzug 404 liefert. Triggert bei: "403 push",
  "Permission denied Org", "denied to <user> trotz Token", "kann Org-Repo nicht
  pushen", "fine-grained token", "Resource owner", "Org-Token", "git push 403", "gh
  credential helper", "gh auth git-credential", "useHttpPath", "zwei Tokens ablegen",
  "Web-Upload deploy", "Historie divergiert", "force-merge", "nicht force pushen",
  "Pages 404 nach Umzug", "Site not found", "Monitor rot aber Seite geht", "stale
  Pages routing", "Repo transfer Org", "warum 403 obwohl Token push-Recht hat".
---

## Worum es geht

Fallen, die im KRS-Projekt beim Umzug von einem privaten Account (`BenditoT`) in
eine Organisation (`kurpfalz-realschule`) wiederholt Zeit gekostet haben. Sie treten
gemeinsam auf, sobald GitHub-Pages-Repos in einer Org liegen.

## ⚡ Schnell-Diagnose bei `403 denied to <user>` (zuerst!)

Der Fehler nennt **immer denselben User** — das heißt **nicht**, dass der Token falsch
ist. Erst herausfinden, **welchen** Token Git wirklich sendet und ob er Schreibrecht hat:

```bash
cd "<PROJEKT>"
echo "=== aktive Helper ==="; git config --get-all credential.helper; \
  git config --get-all credential.https://github.com.helper
TOK=$(printf "protocol=https\nhost=github.com\npath=<ORG>/<REPO>.git\n\n" \
  | git credential fill 2>/dev/null | sed -n 's/^password=//p')
echo "Token-Anfang: ${TOK:0:11}"   # github_pat = fine-grained, ghp_ = classic
curl -s -H "Authorization: Bearer $TOK" \
  https://api.github.com/repos/<ORG>/<REPO> | grep -A6 '"permissions"'
```

- `"push": true` in den Permissions → **Token ist gut**, das Problem ist die Helper-Kette → **Falle 4**.
- `"push": false` / kein Block → Token hat kein Org-Schreibrecht → **Falle 1** (falscher Resource owner).
- Mehr als `osxkeychain` in der Helper-Liste (z. B. `!…/gh auth git-credential`) → **Falle 4**.

## Falle 1: 403 — Token gehört dem privaten Account, nicht der Org

**Symptom:** `git push` auf ein Org-Repo bricht mit 403 ab, Token hat kein push-Recht.
**Ursache:** Ein fine-grained PAT mit *Resource owner = privater Account* darf
**keine** Org-Repos beschreiben.

**Fix — Org-scoped Token** (`github.com/settings/personal-access-tokens/new`):
1. **Resource owner:** auf die **Organisation** umstellen. Fehlt die Org im Dropdown →
   erst Org-Settings → `…/settings/personal-access-tokens-onboarding` → „Allow access".
2. **Repository access:** All repositories (oder gezielt).
3. **Repository permissions** (nicht „Account"!): **Contents = Read and write**,
   **Workflows = Read and write**, Metadata bleibt Read-only.
4. „Generate token" → kopieren (nur **einmal** sichtbar, beginnt `github_pat_…`).

Token kollisionsfrei im Schlüsselbund ablegen:
```bash
printf "protocol=https\nhost=github.com\nusername=<ACCOUNT>\npassword=<TOKEN>\n\n" \
  | git credential-osxkeychain store
```

## Falle 4: Zweiter Credential-Helper (gh CLI) überstimmt den guten Token

**Symptom (KRS, 17.06.2026):** Push bleibt bei `403 denied to <user>`, obwohl ein
frisch erstellter Org-Token laut API `"push": true, "admin": true` hat. Schlüsselbund
neu setzen half **nicht**.
**Ursache:** Neben `osxkeychain` war die **GitHub-CLI als Credential-Helper**
registriert (`credential.https://github.com.helper = !…/gh auth git-credential`).
Beim Push antwortete `gh` mit **seinem eigenen, alten** Token (gleicher User, ohne
Org-Recht) und überstimmte den guten Schlüsselbund-Token. `git credential fill` zog
zufällig den guten — daher die Verwirrung.

**Fix — gh aus der Git-Credential-Kette nehmen:**
```bash
git config --global --unset-all credential.https://github.com.helper
git config --get-all credential.helper        # soll nur osxkeychain zeigen
git config --get-all credential.https://github.com.helper   # soll LEER sein
cd "<PROJEKT>" && git push
```
Bringt Schritt 1 „no such section", liegt der Eintrag woanders:
`git config --show-origin --get-all credential.https://github.com.helper`.
`gh` selbst bleibt voll nutzbar — ihm wird nur die Git-Passwort-Rolle entzogen.

**Zwei Tokens nebeneinander** (eigene + Org-Repos): fine-grained Tokens haben genau
**einen** Resource owner → man braucht zwei. Git nach Pfad unterscheiden lassen:
```bash
git config --global credential.useHttpPath true
printf "protocol=https\nhost=github.com\npath=<ORG>/<REPO>.git\nusername=<ACCOUNT>\npassword=<ORG_TOKEN>\n\n" \
  | git credential-osxkeychain store
```
Der **persönliche** Token wird dann pro eigenem Repo beim ersten Push einmal abgefragt
und gespeichert. **Einfachere Alternativen:** ein **klassischer** Token (`ghp_…`,
Scopes `repo`+`workflow`) deckt alles ab; oder **SSH** statt HTTPS (einmal einrichten,
nie wieder Token-Stress). Wichtig: `<TOKEN>`/`<ORG_TOKEN>` im `store`-Befehl **wirklich
ersetzen** — der Platzhalter wird sonst wörtlich gespeichert (→ erneut 403).

## Falle 2: Divergierte Historie durch Web-Upload — NICHT force-mergen

Wenn zwischendurch per **Web-Upload** (Commits „Add files via upload") deployed wurde,
läuft die Remote-`main` davon → `git push` ist kein Fast-Forward mehr.
- **Vor jedem Upload prüfen**, ob der Remote neuere Commits hat.
- **Nie** `git push --force` auf `main` — das überschreibt fremde Web-Commits.
- Saubere Auflösung: lokalen Stand sichern, per Branch + Pull-Request mergen.
- Ohne Org-Token ist Web-Upload (Oberfläche/Browser-Automation) der pragmatische Weg;
  die lokale Historie ist dann bewusst „nur Referenz".

## Falle 3: Stale Pages-Routing nach Repo-Umzug (404 / Monitor falsch-rot)

**Symptom:** Nach Umzug von `privat.github.io/<repo>` auf `org.github.io/<repo>`
liefert die Org-URL **aus GitHubs eigenem Netz** (Actions-Runner, Health-Monitor) 404
„Site not found", obwohl **echte Nutzer (externer Browser) 200** bekommen.
**Diagnose:** Extern testen → 200, App lädt → **kein echter Ausfall**. Im Runner: 404 +
tote alte User-Pages-URL als Sub-Resource. Frischer Deploy löst den Redirect nicht.
**Konsequenz:** Die Röte ist **kosmetisch** — erst extern gegenprüfen, **bevor** man
die Live-Tools offline nimmt.
**Behebung:** GitHub-Support (Kategorie *Pages*) bitten, das stale Routing zu löschen
(Runner-Log als Beweis). Workaround: Settings → Pages → Unpublish + neu deployen.
Optional Monitor-Cron pausieren, damit keine roten Fehl-Mails kommen.

## Modul-Repos in die Org holen (Repo-Transfer)

Reine GitHub-Klicks: Repo → Settings → Danger Zone → **Transfer** → neuer Owner = Org →
Repo-Namen bestätigen. Danach **Settings → Pages** erneut auf `main /(root)`. Neue URL:
`https://<org>.github.io/<repo>/`. Auch hier kann Falle 3 auftreten.

## Checkliste vor dem Go-Live
1. Org-Token vorhanden (Contents+Workflows R/W) **oder** Web-Upload-Weg gewählt.
2. **Nur ein** Credential-Helper aktiv (kein gh-Override) — sonst Falle 4.
3. Remote-Stand vor Upload geprüft; keine Force-Pushes.
4. Pages-Source je Repo aktiv (`main /(root)` bzw. GitHub Actions).
5. Jede URL **extern** im Browser geöffnet → 200, kein 404, App lädt.
6. 404 nur im Runner? → kosmetisch, Support-Ticket, nicht offline nehmen.

## Quelle (projektintern)
`GO-LIVE-ANLEITUNG-2026-06-13.md`, `GitHub-Support-Ticket-Pages-Routing.md`,
KRS-Vorfall 17.06.2026 (gh-Helper-403). Verwandt: `git-deploy-keychain`,
`flaky-ci-echter-bug-diagnose`.
