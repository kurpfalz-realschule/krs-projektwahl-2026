// ============================================================
// tenant.js — Schul-spezifische Konfiguration
//
// JEDE Schule editiert NUR diese Datei. Logo, Schul-Name, Termine,
// Kontakt, Footer-Links und Supabase-Credentials hier eintragen.
//
// Wird als ERSTES Script in index.html, admin-dashboard-v2.html und
// schueler-frontend-v3.html geladen, sodass alle nachfolgenden Scripts
// auf window.TENANT zugreifen können.
//
// Default-Werte unten sind die Konfiguration der Kurpfalz-Realschule
// Schriesheim (KRS) — der Pilot-Werkstatt. Pilot-Schulen ersetzen die
// Werte komplett, der Schlüssel-Aufbau bleibt unverändert.
//
// Master-Repo: https://github.com/kurpfalz-realschule/krs-projektwahl-2026
// Lizenz: CC BY-NC 4.0 (siehe LICENSE)
// ============================================================
(function () {
  'use strict';

  // Default-Tenant: KRS Schriesheim. Wenn ein Fork keine eigenen Werte
  // einträgt, läuft die App weiter mit diesem Default — Backward-Compat.
  window.TENANT = window.TENANT || {
    schule: {
      name_lang: 'Kurpfalz-Realschule Schriesheim',
      name_kurz: 'KRS',
      ort: 'Schriesheim'
    },
    branding: {
      logo_url: 'krs-logo.jpg',
      primaer: '#4A6A83',
      akzent: '#E87722',
      warm: '#F5B335'
    },
    termine: {
      projektwoche_jahr: 2026,
      projekttage_von: '2026-07-21',
      projekttage_bis: '2026-07-23',
      schulfest: '2026-07-24'
    },
    kontakt: {
      verantwortlich_name: 'Norbert Kotzan',
      verantwortlich_email: 'kotzan@realschule-schriesheim.de'
    },
    links: {
      datenschutz: 'https://realschule-schriesheim.de/datenschutzerklaerung/',
      impressum: 'https://realschule-schriesheim.de/kontakt-service/impressum-3/'
    },
    supabase: {
      url: 'https://uzynvvtsyjfmtywsfxtz.supabase.co',
      publishableKey: 'sb_publishable_kdZSmagc_sbq9qwynebcxw_hKdhyDt1'
    },
    deploy: {
      frontend_url: 'https://kurpfalz-realschule.github.io/krs-projektwahl-2026/',
      schueler_url: 'https://kurpfalz-realschule.github.io/krs-projektwahl-2026/schueler.html'
    }
  };

  // Backward-Compat: window.KRS_SUPABASE wird vom existierenden DataService
  // gelesen. Wir füttern ihn aus window.TENANT.supabase, sodass Forks
  // nur tenant.js editieren müssen, nicht zwei Dateien.
  if (!window.KRS_SUPABASE) {
    window.KRS_SUPABASE = {
      url: window.TENANT.supabase.url,
      publishableKey: window.TENANT.supabase.publishableKey,
      schueler_url: window.TENANT.deploy.schueler_url
    };
  }

  // Helper für Datum-Formatierung in der UI.
  // Beispiel: { von:'2026-07-21', bis:'2026-07-23' } → '21.–23. Juli 2026'
  window.TENANT_HELPERS = {
    terminBereich() {
      const t = window.TENANT && window.TENANT.termine;
      if (!t || !t.projekttage_von || !t.projekttage_bis) return '';
      const von = new Date(t.projekttage_von);
      const bis = new Date(t.projekttage_bis);
      if (isNaN(von) || isNaN(bis)) return '';
      const monat = bis.toLocaleDateString('de-DE', { month: 'long' });
      return `${von.getDate()}.–${bis.getDate()}. ${monat} ${bis.getFullYear()}`;
    },
    terminTag(datumIso) {
      if (!datumIso) return '';
      const d = new Date(datumIso);
      if (isNaN(d)) return '';
      const monat = d.toLocaleDateString('de-DE', { month: 'long' });
      return `${d.getDate()}. ${monat}`;
    },
    projektwocheTitel() {
      const t = window.TENANT;
      const jahr = t && t.termine && t.termine.projektwoche_jahr;
      const kurz = t && t.schule && t.schule.name_kurz;
      return `${kurz || 'Schule'} Projektwoche ${jahr || ''}`.trim();
    }
  };

  // CSS-Branding-Override: setzt --krs-blau / --krs-orange / --krs-gelb
  // aus tenant.branding.* — kein Refactor von 200+ CSS-Regeln nötig.
  // Setzt zusätzlich document.title basierend auf der Schul-Konfig.
  function applyBranding() {
    if (!window.TENANT) return;
    if (window.TENANT.branding && document.documentElement && document.documentElement.style) {
      const r = document.documentElement.style;
      const b = window.TENANT.branding;
      if (b.primaer) r.setProperty('--krs-blau', b.primaer);
      if (b.akzent)  r.setProperty('--krs-orange', b.akzent);
      if (b.warm)    r.setProperty('--krs-gelb', b.warm);
    }
    if (document.title === 'Projekttage' || document.title === 'Projektwoche-Anmeldung' || document.title === 'Schul-Dashboard') {
      const T = window.TENANT;
      const kurz = T.schule && T.schule.name_kurz;
      const jahr = T.termine && T.termine.projektwoche_jahr;
      if (kurz) document.title = `${kurz} Projektwoche ${jahr || ''}`.trim();
    }
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyBranding);
  } else {
    applyBranding();
  }
})();
