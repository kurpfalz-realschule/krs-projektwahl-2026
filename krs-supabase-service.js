// =====================================================================
// KRS Projektwahl 2026 — DataService (Dual-Mode: Demo + Produktiv)
// =====================================================================
// Laden (in dieser Reihenfolge):
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="./krs-supabase-config.js"></script>
//   <script src="./krs-supabase-service.js"></script>
//
// Nutzung:
//   const service = new KrsDataService();  // auto: Demo wenn keine Config, sonst Produktiv
//   const projekte = await service.listProjektePublic();
//   const status = await service.getSchuelerStatus('7B-A7K2');
//
// Normalisierung:
//   Projekte werden einheitlich mit Feldern { id, titel, beschreibung,
//   lehrer, ort, min_klasse, max_klasse, freie_plaetze? } zurückgegeben,
//   unabhängig davon ob Demo- oder Produktiv-Modus aktiv ist. Dadurch
//   muss das Frontend nicht unterscheiden.
// =====================================================================

(function () {
  'use strict';

  const CFG = window.KRS_SUPABASE || {};
  const HAS_SUPABASE =
    !!CFG.url &&
    !!(CFG.publishableKey || CFG.anonKey) &&
    typeof window.supabase !== 'undefined';

  // ---------- Normalisierung ----------
  function joinLehrerNames(row) {
    const names = [];
    const first =
      row.lehrer_name ||
      row.lehrer1_name ||
      (row.lehrer && typeof row.lehrer === 'object' ? row.lehrer.name : row.lehrer);
    const second =
      row.lehrer2_name ||
      row.zweitlehrer_name ||
      (row.lehrer2 && typeof row.lehrer2 === 'object' ? row.lehrer2.name : row.lehrer2);
    [first, second].forEach(name => {
      const clean = String(name || '').trim();
      if (clean && !names.includes(clean)) names.push(clean);
    });
    return names.join(', ');
  }

  function normalizeProjektPublic(row) {
    // Für projekte_public (View) — hat lehrer_name, kurzbeschreibung, langbeschreibung
    return {
      id: row.id,
      titel: row.titel,
      beschreibung: row.kurzbeschreibung || row.beschreibung || '',
      langbeschreibung: row.langbeschreibung || '',
      lehrer: joinLehrerNames(row),
      ort: row.ort || '',
      min_klasse: row.min_klasse,
      max_klasse: row.max_klasse,
      bild_url: row.bild_url || null,
    };
  }

  function normalizeMockProjekt(row) {
    // Für MOCK_PROJEKTE (Demo) — hat bereits beschreibung + lehrer + freie_plaetze
    return {
      id: row.id,
      titel: row.titel,
      beschreibung: row.beschreibung || row.kurzbeschreibung || '',
      langbeschreibung: row.langbeschreibung || '',
      lehrer: joinLehrerNames(row),
      ort: row.ort || '',
      min_klasse: row.min_klasse,
      max_klasse: row.max_klasse,
      freie_plaetze: row.freie_plaetze,
      bild_url: row.bild_url || null,
    };
  }

  class KrsDataService {
    constructor() {
      this.isDemo = !HAS_SUPABASE;
      this.mode = HAS_SUPABASE ? 'produktiv' : 'demo';
      if (!this.isDemo) {
        this.client = window.supabase.createClient(
          CFG.url,
          CFG.publishableKey || CFG.anonKey,
          {
            realtime: { params: { eventsPerSecond: 10 } },
            auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
          }
        );
      }
      // Gecachter Lookup users-Row des eingeloggten Auth-Users.
      // Invalidiert bei onAuthStateChange.
      this._dbUserCache = null;
      this._dbUserCacheAuthId = null;
      if (!this.isDemo) {
        this.client.auth.onAuthStateChange((_event, session) => {
          // Wenn Session wechselt → Cache leeren
          const newId = session && session.user ? session.user.id : null;
          if (newId !== this._dbUserCacheAuthId) {
            this._dbUserCache = null;
            this._dbUserCacheAuthId = null;
          }
        });
      }
    }

    // =====================================================================
    // ---------- AUTH ----------
    // =====================================================================
    // Alle Auth-Methoden sind No-Ops im Demo-Modus und geben sinnvolle
    // Defaults zurück, damit das Frontend keine Fallunterscheidung braucht.

    async getSession() {
      if (this.isDemo) return null;
      const { data } = await this.client.auth.getSession();
      return data ? data.session : null;
    }

    async getCurrentUser() {
      if (this.isDemo) return null;
      const { data } = await this.client.auth.getUser();
      return data ? data.user : null;
    }

    async login(email, password) {
      if (this.isDemo) return { error: { message: 'Login nur im Produktiv-Modus verfügbar' } };
      return this.client.auth.signInWithPassword({
        email: String(email || '').trim().toLowerCase(),
        password: String(password || ''),
      });
    }

    async logout() {
      if (this.isDemo) return { error: null };
      this._dbUserCache = null;
      this._dbUserCacheAuthId = null;
      return this.client.auth.signOut();
    }

    async resetPasswordForEmail(email, redirectTo) {
      if (this.isDemo) return { error: { message: 'Passwort-Reset nur im Produktiv-Modus' } };
      const opts = {};
      if (redirectTo) opts.redirectTo = redirectTo;
      return this.client.auth.resetPasswordForEmail(
        String(email || '').trim().toLowerCase(),
        opts
      );
    }

    async updatePassword(newPassword) {
      if (this.isDemo) return { error: { message: 'Passwort ändern nur im Produktiv-Modus' } };
      return this.client.auth.updateUser({ password: String(newPassword || '') });
    }

    // Fragt die RPC is_admin() ab. Liefert false wenn kein Login, RPC-Fehler
    // oder kein Admin. Bewusst defensiv — keine Exception nach außen.
    async isAdmin() {
      if (this.isDemo) return true; // im Demo-Modus ist alles offen
      try {
        const { data, error } = await this.client.rpc('is_admin');
        if (error) return false;
        return data === true;
      } catch (_) {
        return false;
      }
    }

    // Liefert die users-Row (users.id, kuerzel, rolle, ...) des eingeloggten
    // Auth-Users. Nutzt auth_user_id-Lookup. Resultat wird gecached, solange
    // sich die auth-Session nicht ändert.
    async getCurrentDbUser() {
      if (this.isDemo) return null;
      const { data: { user } } = await this.client.auth.getUser();
      if (!user) { this._dbUserCache = null; this._dbUserCacheAuthId = null; return null; }
      if (this._dbUserCache && this._dbUserCacheAuthId === user.id) return this._dbUserCache;
      const { data, error } = await this.client
        .from('users')
        .select('id, kuerzel, email, name, rolle, klassenlehrer_von, auth_user_id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
      if (error) {
        // Bei RLS-Block liefern wir null (User kann seine eigene Row nicht lesen?
        // Theoretisch sollte users_select_self das erlauben). Logging nur.
        console.warn('[KRS] getCurrentDbUser:', error.message);
        return null;
      }
      this._dbUserCache = data || null;
      this._dbUserCacheAuthId = user.id;
      return this._dbUserCache;
    }

    // Convenience: nur users.id (UUID5 aus Kürzel) — oder null.
    async getCurrentDbUserId() {
      const u = await this.getCurrentDbUser();
      return u ? u.id : null;
    }

    // Observer-API — ruft callback(session) auf. Liefert Unsubscribe.
    onAuthStateChange(callback) {
      if (this.isDemo) return { unsubscribe: () => {} };
      const { data } = this.client.auth.onAuthStateChange((_event, session) => {
        try { callback(session); } catch (e) { console.error('[KRS] auth handler:', e); }
      });
      return {
        unsubscribe: () => {
          try { data.subscription.unsubscribe(); } catch (_) { /* noop */ }
        }
      };
    }

    // Interner Helper: ermittelt bearbeiter_id für RPC-Calls, die den
    // ausführenden Admin loggen sollen. Wenn caller einen expliziten Wert
    // übergibt, verwenden wir den (auch null, falls caller das bewusst will).
    // Sonst versuchen wir, users.id aus der Auth-Session herzuleiten.
    async _resolveBearbeiterId(explicit) {
      if (explicit !== undefined && explicit !== null) return explicit;
      if (this.isDemo) return null;
      try { return await this.getCurrentDbUserId(); }
      catch (_) { return null; }
    }

    // ---------- SYSTEM-SETTINGS ----------
    async getPhase() {
      if (this.isDemo) return window.MOCK_PHASE || 'anmeldung';
      const { data, error } = await this.client
        .from('system_settings')
        .select('value')
        .eq('key', 'phase')
        .maybeSingle();
      if (error) throw new Error('getPhase: ' + error.message);
      // value ist JSONB — kann "anmeldung" oder {"state":"anmeldung"} sein
      if (!data) return 'anmeldung';
      const v = data.value;
      if (typeof v === 'string') return v;
      if (v && typeof v === 'object' && v.state) return v.state;
      return String(v || 'anmeldung').replace(/^"|"$/g, '');
    }

    async getSystemSetting(key) {
      if (this.isDemo) return null;
      const { data, error } = await this.client
        .from('system_settings')
        .select('value')
        .eq('key', key)
        .maybeSingle();
      if (error) throw new Error('getSystemSetting(' + key + '): ' + error.message);
      return data ? data.value : null;
    }

    async setPhase(newPhase) {
      if (this.isDemo) { window.MOCK_PHASE = newPhase; return { success: true }; }
      // system_settings.value ist JSONB → wir speichern den String selbst als JSON-String
      const { error } = await this.client
        .from('system_settings')
        .upsert({ key: 'phase', value: JSON.stringify(newPhase) }, { onConflict: 'key' });
      if (error) throw new Error('setPhase: ' + error.message);
      return { success: true };
    }

    async setSystemSetting(key, value) {
      if (this.isDemo) return { success: true };
      const { error } = await this.client
        .from('system_settings')
        .upsert({ key, value }, { onConflict: 'key' });
      if (error) throw new Error('setSystemSetting(' + key + '): ' + error.message);
      return { success: true };
    }

    // ---------- USERS (Lehrkräfte) ----------
    async createUser(payload) {
      if (this.isDemo) {
        const id = (crypto.randomUUID && crypto.randomUUID()) || String(Date.now());
        const neu = { id, ...payload };
        (window.MOCK_USERS ||= []).push(neu);
        return neu;
      }
      const { data, error } = await this.client.from('users').insert(payload).select('*').single();
      if (error) throw new Error('createUser: ' + error.message);
      return data;
    }

    async updateUser(id, patch) {
      if (this.isDemo) {
        const arr = window.MOCK_USERS || [];
        const u = arr.find(x => x.id === id);
        if (u) Object.assign(u, patch);
        return u;
      }
      const { data, error } = await this.client.from('users').update(patch).eq('id', id).select('*').single();
      if (error) throw new Error('updateUser: ' + error.message);
      return data;
    }

    async deleteUser(id) {
      if (this.isDemo) {
        const arr = window.MOCK_USERS || [];
        const i = arr.findIndex(x => x.id === id);
        if (i !== -1) arr.splice(i, 1);
        return { id };
      }
      const { error } = await this.client.from('users').delete().eq('id', id);
      if (error) throw new Error('deleteUser: ' + error.message);
      return { id };
    }

    async listUsers() {
      if (this.isDemo) return window.MOCK_USERS || [];
      const { data, error } = await this.client
        .from('users')
        .select('id, email, name, rolle, kuerzel, klassenlehrer_von')
        .order('name');
      if (error) throw new Error('listUsers: ' + error.message);
      return data || [];
    }

    // ---------- SCHÜLER ----------
    async listSchueler() {
      if (this.isDemo) return window.MOCK_SCHUELER_LISTE || [];
      const { data, error } = await this.client
        .from('schueler')
        .select('*')
        .order('klasse')
        .order('nachname');
      if (error) throw new Error('listSchueler: ' + error.message);
      return data || [];
    }

    // Schüler-Status inkl. Wahlen, Zuteilung, Tauschwunsch — RPC kapselt alles in einem Call
    async getSchuelerStatus(code) {
      const cleanCode = String(code || '').toUpperCase().trim();
      if (!cleanCode) return { success: false, error: 'code_fehlt' };

      if (this.isDemo) {
        const src = window.MOCK_SCHUELER || {};
        const s = src[cleanCode];
        if (!s) return { success: false, error: 'code_unbekannt' };
        const phase = window.MOCK_PHASE || 'anmeldung';
        const out = {
          success: true,
          phase,
          schueler: {
            code: cleanCode,
            vorname: s.vorname,
            nachname: s.nachname,
            klasse: s.klasse,
            klassenstufe: s.klassenstufe,
          },
          hat_gewaehlt: !!(s.status && s.status.hat_gewaehlt),
          hat_zuteilung: !!(s.status && s.status.zuteilung),
          hat_offenen_tausch: !!(s.status && s.status.offener_tausch),
        };
        if (s.status && s.status.zuteilung) {
          out.zuteilung = {
            projekt_id: s.status.zuteilung.projekt_id,
            wahl_nr: s.status.zuteilung.wahl_nr,
          };
        }
        return out;
      }

      const { data, error } = await this.client.rpc('get_schueler_status', { p_code: cleanCode });
      if (error) throw new Error('getSchuelerStatus: ' + error.message);
      return data || { success: false, error: 'unbekannt' };
    }

    // ---------- PROJEKTE (öffentlich sichtbar für Schüler:innen) ----------
    async listProjektePublic() {
      if (this.isDemo) {
        const src = window.MOCK_PROJEKTE || [];
        return src.map(normalizeMockProjekt);
      }
      const { data, error } = await this.client
        .from('projekte_public')
        .select('*')
        .order('titel');
      if (error) throw new Error('listProjektePublic: ' + error.message);
      return (data || []).map(normalizeProjektPublic);
    }

    // Vollständige Projektliste (für Admin-Dashboard)
    async listProjekte() {
      if (this.isDemo) {
        const src = window.MOCK_PROJEKTE || [];
        return src.map(normalizeMockProjekt);
      }
      let { data, error } = await this.client
        .from('projekte')
        .select('*, lehrer:users!lehrer_id(name, kuerzel), lehrer2:users!lehrer2_id(name, kuerzel)')
        .order('titel');
      if (error && /lehrer2_id|lehrer2|relationship|schema cache/i.test(error.message || '')) {
        console.warn('[KRS] listProjekte: lehrer2_id fehlt noch, Fallback auf Ein-Lehrer-Schema.');
        ({ data, error } = await this.client
          .from('projekte')
          .select('*, lehrer:users!lehrer_id(name, kuerzel)')
          .order('titel'));
      }
      if (error) throw new Error('listProjekte: ' + error.message);
      return data || [];
    }

    async createProjekt(payload) {
      if (this.isDemo) {
        const id = (crypto.randomUUID && crypto.randomUUID()) || String(Date.now());
        const neu = { id, ...payload, created_at: new Date().toISOString() };
        (window.MOCK_PROJEKTE ||= []).push(neu);
        return neu;
      }
      const { data, error } = await this.client
        .from('projekte')
        .insert(payload)
        .select('*')
        .single();
      if (error) throw new Error('createProjekt: ' + error.message);
      return data;
    }

    async updateProjekt(id, patch) {
      if (this.isDemo) {
        const arr = window.MOCK_PROJEKTE || [];
        const p = arr.find(x => x.id === id);
        if (p) Object.assign(p, patch);
        return p;
      }
      const { data, error } = await this.client
        .from('projekte')
        .update(patch)
        .eq('id', id)
        .select('*')
        .single();
      if (error) throw new Error('updateProjekt: ' + error.message);
      return data;
    }

    async deleteProjekt(id) {
      if (this.isDemo) {
        const arr = window.MOCK_PROJEKTE || [];
        const i = arr.findIndex(x => x.id === id);
        if (i !== -1) arr.splice(i, 1);
        return { id };
      }
      const { error } = await this.client.from('projekte').delete().eq('id', id);
      if (error) throw new Error('deleteProjekt: ' + error.message);
      return { id };
    }

    // ---------- WAHLEN ----------
    // create_wahl RPC (schema-v2-fixed): nimmt alle drei Wahlen + Namensbestätigung
    async createWahl({ code, vorname, nachname, erstwahl_id, zweitwahl_id, drittwahl_id }) {
      if (this.isDemo) {
        // Simuliere Business-Regeln serverseitig
        const src = window.MOCK_SCHUELER || {};
        const cleanCode = String(code || '').toUpperCase().trim();
        const s = src[cleanCode];
        if (!s) return { success: false, error: 'ungueltiger_code' };
        if (
          String(s.vorname || '').trim().toLowerCase() !== String(vorname || '').trim().toLowerCase() ||
          String(s.nachname || '').trim().toLowerCase() !== String(nachname || '').trim().toLowerCase()
        ) {
          return { success: false, error: 'name_stimmt_nicht' };
        }
        if (s.status && s.status.hat_gewaehlt) {
          return { success: false, error: 'bereits_angemeldet' };
        }
        const ids = [erstwahl_id, zweitwahl_id, drittwahl_id];
        if (new Set(ids).size !== 3) {
          return { success: false, error: 'unterschiedliche_wahlen' };
        }
        // Persistieren im Mock
        s.status = {
          hat_gewaehlt: true,
          wahlen: { erstwahl_id, zweitwahl_id, drittwahl_id, gewaehlt_am: new Date().toISOString() },
        };
        return { success: true, schueler_code: cleanCode, vorname: s.vorname };
      }

      const { data, error } = await this.client.rpc('create_wahl', {
        p_code: String(code || '').toUpperCase().trim(),
        p_vorname_bestaetigung: String(vorname || ''),
        p_nachname_bestaetigung: String(nachname || ''),
        p_erstwahl: erstwahl_id,
        p_zweitwahl: zweitwahl_id,
        p_drittwahl: drittwahl_id,
      });
      if (error) throw new Error('createWahl: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // ---------- TAUSCHWÜNSCHE ----------
    async createTauschwunsch({ code, vorname, nachname, nach_projekt_id, begruendung }) {
      if (this.isDemo) {
        if (String(begruendung || '').trim().length < 10) {
          return { success: false, error: 'begruendung_zu_kurz' };
        }
        return { success: true };
      }
      const { data, error } = await this.client.rpc('create_tauschwunsch', {
        p_code: String(code || '').toUpperCase().trim(),
        p_vorname_bestaetigung: String(vorname || ''),
        p_nachname_bestaetigung: String(nachname || ''),
        p_nach_projekt_id: nach_projekt_id,
        p_begruendung: String(begruendung || ''),
      });
      if (error) throw new Error('createTauschwunsch: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // Offene Tauschwünsche (für Admin)
    // Nutzt die View `offene_tauschwuensche`, die bereits Schüler- und
    // Projekt-Infos + 1:1-Tausch-Erkennung mitliefert. Kein Client-seitiger
    // Join nötig.
    async listTauschwuensche() {
      if (this.isDemo) return [];
      const { data, error } = await this.client
        .from('offene_tauschwuensche')
        .select('*')
        .order('created_at', { ascending: true });
      if (error) throw new Error('listTauschwuensche: ' + error.message);
      return data || [];
    }

    // Admin-Aktion: Tauschwunsch genehmigen (einseitig, mit Umbuchung)
    async genehmigeTausch(tauschId, bearbeiterId) {
      if (this.isDemo) return { success: true };
      const bid = await this._resolveBearbeiterId(bearbeiterId);
      const { data, error } = await this.client.rpc('genehmige_tauschwunsch', {
        p_tausch_id: tauschId,
        p_bearbeiter_id: bid,
      });
      if (error) throw new Error('genehmigeTausch: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // Admin-Aktion: Tauschwunsch ablehnen
    async lehnTauschAb(tauschId, grund = null, bearbeiterId) {
      if (this.isDemo) return { success: true };
      const bid = await this._resolveBearbeiterId(bearbeiterId);
      const { data, error } = await this.client.rpc('lehn_tauschwunsch_ab', {
        p_tausch_id: tauschId,
        p_grund: grund,
        p_bearbeiter_id: bid,
      });
      if (error) throw new Error('lehnTauschAb: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // Admin-Aktion: Atomarer 1:1-Swap zweier Tauschwünsche
    async genehmige1zu1Tausch(tauschA, tauschB, bearbeiterId) {
      if (this.isDemo) return { success: true };
      const bid = await this._resolveBearbeiterId(bearbeiterId);
      const { data, error } = await this.client.rpc('genehmige_1zu1_tausch', {
        p_tausch_a: tauschA,
        p_tausch_b: tauschB,
        p_bearbeiter_id: bid,
      });
      if (error) throw new Error('genehmige1zu1Tausch: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    async withdrawTauschwunsch({ code, vorname, nachname }) {
      if (this.isDemo) return { success: true };
      const { data, error } = await this.client.rpc('withdraw_tauschwunsch', {
        p_code: String(code || '').toUpperCase().trim(),
        p_vorname_bestaetigung: String(vorname || ''),
        p_nachname_bestaetigung: String(nachname || ''),
      });
      if (error) throw new Error('withdrawTauschwunsch: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // ---------- ZUTEILUNGEN (für Admin/Lehrer) ----------
    async listZuteilungen() {
      if (this.isDemo) return window.MOCK_ZUTEILUNGEN || [];
      const { data, error } = await this.client.from('zuteilungen_detail').select('*');
      if (error) throw new Error('listZuteilungen: ' + error.message);
      return data || [];
    }

    // ---------- VERTEILUNG (Algorithmus: Preview / Commit) ----------
    // Führt den Random-Serial-Dictatorship-Algorithmus auf dem Server aus.
    //   opts.seed    — optional; fixer Seed-String für reproduzierbaren Lauf.
    //   opts.commit  — true: schreibt zuteilungen + deaktiviert alte Verteilungen.
    //                   false (Default): nur Preview, nichts wird persistiert.
    //   opts.bearbeiterId — optional; User-ID des ausführenden Admins.
    // Rückgabe: JSONB aus run_verteilung mit { success, seed, statistik,
    //   zuteilungen[], nicht_zugeteilt[], projekte_auslastung[], ... }.
    async runVerteilung({ seed = null, commit = false, bearbeiterId } = {}) {
      if (this.isDemo) {
        // Fallback: client-seitiger Algorithmus (für Demo-Dashboard)
        if (typeof window.VerteilungsAlgorithmus !== 'function') {
          return { success: false, error: 'demo_algorithmus_nicht_geladen' };
        }
        const algo = new window.VerteilungsAlgorithmus();
        const projekte = (window.MOCK_PROJEKTE || []).map(normalizeMockProjekt);
        const schueler = (typeof window.generateTestSchueler === 'function')
          ? window.generateTestSchueler(projekte)
          : [];
        try {
          const result = algo.verteile({ schueler, projekte, seed: seed || undefined });
          return { success: true, committed: !!commit, ...result };
        } catch (e) {
          return { success: false, error: String(e && e.message || e) };
        }
      }
      const bid = await this._resolveBearbeiterId(bearbeiterId);
      const { data, error } = await this.client.rpc('run_verteilung', {
        p_seed: seed,
        p_commit: !!commit,
        p_bearbeiter_id: bid,
      });
      if (error) throw new Error('runVerteilung: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // Direkt-Einschreibung durch Klassenlehrer (Sprint E1.5).
    // Demo: mutiert mockSchueler in-memory + dispatcht 'krs:mock-seeded'.
    // Live: ruft RPC `klassenlehrer_assign_schueler`, das Klassen- und
    //       Status-Constraints serverseitig prüft (RLS-sicher).
    async klassenlehrerAssignSchueler({ code, projektId }) {
      const cleanCode = String(code || '').toUpperCase().trim();
      if (!cleanCode) return { success: false, error: 'code_fehlt' };

      if (this.isDemo) {
        const list = (typeof window !== 'undefined' && window.mockSchueler) || [];
        const s = list.find(x => String(x.code || '').toUpperCase() === cleanCode);
        if (!s) return { success: false, error: 'schueler_unbekannt' };
        if (projektId) {
          s.zuteilung = projektId;
          s.hat_gewaehlt = true;
        } else {
          s.zuteilung = null;
          s.hat_gewaehlt = false;
        }
        try { window.dispatchEvent(new Event('krs:mock-seeded')); } catch (_) {}
        return { success: true, schueler_code: cleanCode, projekt_id: projektId || null };
      }

      const rpc = projektId ? 'klassenlehrer_assign_schueler' : 'klassenlehrer_unassign_schueler';
      const params = projektId
        ? { p_schueler_code: cleanCode, p_projekt_id: projektId }
        : { p_schueler_code: cleanCode };
      const { data, error } = await this.client.rpc(rpc, params);
      if (error) throw new Error('klassenlehrerAssignSchueler: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // Manuelle Umbuchung einzelner Schüler (Admin)
    async updateZuteilung({ code, projektId, bearbeiterId, kommentar = null }) {
      const cleanCode = String(code || '').toUpperCase().trim();
      if (!cleanCode || !projektId) return { success: false, error: 'parameter_fehlen' };
      if (this.isDemo) {
        const arr = window.MOCK_ZUTEILUNGEN || (window.MOCK_ZUTEILUNGEN = []);
        const i = arr.findIndex(z => String(z.schueler_code || '').toUpperCase() === cleanCode);
        if (i !== -1) arr[i].projekt_id = projektId;
        else arr.push({ schueler_code: cleanCode, projekt_id: projektId, wahl_nr: 0 });
        return { success: true };
      }
      const bid = await this._resolveBearbeiterId(bearbeiterId);
      const { data, error } = await this.client.rpc('update_zuteilung', {
        p_schueler_code: cleanCode,
        p_neues_projekt_id: projektId,
        p_bearbeiter_id: bid,
        p_kommentar: kommentar,
      });
      if (error) throw new Error('updateZuteilung: ' + error.message);
      return data || { success: false, error: 'keine_antwort' };
    }

    // Historie aller bisherigen Verteilungsläufe (View).
    // Die View sortiert selbst schon nach gestartet_am DESC — wir lassen
    // die Client-Sortierung weg (ein expliziter order('zeitpunkt') wäre
    // falsch, diese Spalte existiert nicht in verteilungen_uebersicht).
    async listVerteilungen() {
      if (this.isDemo) return window.MOCK_VERTEILUNGEN || [];
      const { data, error } = await this.client
        .from('verteilungen_uebersicht')
        .select('*')
        .order('gestartet_am', { ascending: false });
      if (error) throw new Error('listVerteilungen: ' + error.message);
      return data || [];
    }

    // ---------- REALTIME ----------
    _sub(table, channelName, callback) {
      if (this.isDemo) return { unsubscribe: () => {} };
      const ch = this.client
        .channel(channelName)
        .on('postgres_changes', { event: '*', schema: 'public', table }, (payload) => {
          try { callback(payload); } catch (e) { console.error('[KRS] Realtime-Handler:', e); }
        })
        .subscribe();
      return {
        unsubscribe: () => {
          try { this.client.removeChannel(ch); } catch (_) { /* noop */ }
        },
      };
    }

    subscribeProjekte(callback)   { return this._sub('projekte',       'rt-projekte-' + Math.random().toString(36).slice(2,8), callback); }
    subscribeWahlen(callback)     { return this._sub('wahlen',         'rt-wahlen-'   + Math.random().toString(36).slice(2,8), callback); }
    subscribeZuteilungen(callback){ return this._sub('zuteilungen',    'rt-zut-'      + Math.random().toString(36).slice(2,8), callback); }
    subscribeTauschwuensche(cb)   { return this._sub('tauschwuensche', 'rt-tausch-'   + Math.random().toString(36).slice(2,8), cb); }
    subscribeVerteilungen(cb)     { return this._sub('verteilungen',   'rt-vert-'     + Math.random().toString(36).slice(2,8), cb); }
  }

  // ---------- Export ----------
  window.KrsDataService = KrsDataService;
  window.KRS_MODE = HAS_SUPABASE ? 'produktiv' : 'demo';
  console.info('[KRS] DataService bereit — Modus:', window.KRS_MODE);
})();
